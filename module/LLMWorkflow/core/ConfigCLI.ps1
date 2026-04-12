#requires -Version 5.1
<#
.SYNOPSIS
    CLI wrapper for LLM Workflow configuration commands.

.DESCRIPTION
    Provides command-line interface commands for the Effective Configuration System:
    - Get-LLMWorkflowEffectiveConfig
    - llmconfig --explain
    - llmconfig --validate

.NOTES
    Version: 1.0.0
    Compatible with: PowerShell 5.1+
#>

# Import core configuration module
$script:ModulePath = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $script:ModulePath 'Config.ps1') -Force -ErrorAction Stop

<#
.SYNOPSIS
    Gets the effective configuration for LLM Workflow.

.DESCRIPTION
    High-level command to retrieve the fully resolved configuration
    with optional explanation and validation.

.PARAMETER Profile
    The profile name to load.

.PARAMETER ProjectPath
    Path to the project directory.

.PARAMETER Explain
    Show source information for each value.

.PARAMETER Validate
    Validate the configuration and show errors.

.PARAMETER ShowSecrets
    Show secret values (use with caution).

.PARAMETER Format
    Output format: table, list, json, yaml.

.PARAMETER Path
    Filter to specific configuration path.

.OUTPUTS
    Configuration data in requested format.

.EXAMPLE
    Get-LLMWorkflowEffectiveConfig
    Returns the effective configuration.

.EXAMPLE
    Get-LLMWorkflowEffectiveConfig -Explain -Format table
    Shows configuration with sources in table format.

.EXAMPLE
    Get-LLMWorkflowEffectiveConfig -Validate
    Validates and returns configuration with validation results.
#>
function Get-LLMWorkflowEffectiveConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Profile = 'default',

        [Parameter(Mandatory = $false)]
        [string]$ProjectPath = $null,

        [Parameter(Mandatory = $false)]
        [switch]$Explain,

        [Parameter(Mandatory = $false)]
        [switch]$Validate,

        [Parameter(Mandatory = $false)]
        [switch]$ShowSecrets,

        [Parameter(Mandatory = $false)]
        [ValidateSet('table', 'list', 'json', 'yaml', 'object')]
        [string]$Format = 'object',

        [Parameter(Mandatory = $false)]
        [string]$Path = $null
    )

    # Build configuration
    $configParams = @{
        Profile = $Profile
        Explain = $Explain
        MaskSecrets = (-not $ShowSecrets)
        NoCache = $true
    }

    if ($ProjectPath) {
        $configParams['ProjectPath'] = $ProjectPath
    }

    # Get effective config
    $effectiveConfig = Get-EffectiveConfig @configParams

    # Validate if requested
    $validation = $null
    if ($Validate) {
        $validation = Test-ConfigValidation -Config $effectiveConfig
    }

    # Handle path filtering
    if ($Path) {
        $value = Get-ConfigValue -Path $Path -Config $effectiveConfig -IncludeSource:$Explain
        if ($Format -eq 'object') {
            return $value
        }
        $effectiveConfig = @{ $Path = $value }
    }

    # Output based on format
    switch ($Format) {
        'object' {
            $result = [PSCustomObject]@{
                Config = $effectiveConfig
            }
            if ($validation) {
                $result | Add-Member -NotePropertyName 'Validation' -NotePropertyValue $validation
            }
            return $result
        }
        'json' {
            $output = @{
                config = $effectiveConfig
            }
            if ($validation) {
                $output['validation'] = $validation
            }
            return $output | ConvertTo-Json -Depth 10
        }
        'yaml' {
            # Simple YAML-like output
            $output = @()
            $output += "# LLM Workflow Effective Configuration"
            $output += "# Generated: $(Get-Date -Format 'o')"
            $output += "# Profile: $Profile"
            $output += ""
            
            if ($validation) {
                $output += "# Validation: $(if ($validation.IsValid) { 'PASSED' } else { 'FAILED' })"
                if ($validation.Errors.Count -gt 0) {
                    $output += "# Errors: $($validation.Errors.Count)"
                }
                $output += ""
            }

            $flat = Flatten-ConfigForOutput -Config $effectiveConfig
            foreach ($item in $flat) {
                $output += "$($item.Path): $($item.Value)"
            }
            return $output -join "`n"
        }
        'table' {
            if ($Explain) {
                Export-ConfigExplanation -Config $effectiveConfig -Format table
            } else {
                $flat = Flatten-ConfigForOutput -Config $effectiveConfig
                $flat | Select-Object Path, Value | Format-Table -AutoSize
            }
        }
        'list' {
            Export-ConfigExplanation -Config $effectiveConfig -Format list
        }
    }

    # Return validation info if present
    if ($validation -and -not $validation.IsValid) {
        Write-Warning "Configuration validation failed with $($validation.Errors.Count) error(s)"
        foreach ($err in $validation.Errors) {
            Write-Warning "  [$($err.Severity)] $($err.Path): $($err.Message)"
        }
    }
}

<#
.SYNOPSIS
    LLM Configuration CLI command.

.DESCRIPTION
    Main entry point for the llmconfig CLI command.
    Supports --explain, --validate, and other configuration operations.

.PARAMETER Explain
    Show detailed explanation of configuration sources.

.PARAMETER Validate
    Validate the current configuration.

.PARAMETER Path
    Specific configuration path to query.

.PARAMETER Profile
    Profile name to use.

.PARAMETER Format
    Output format.

.PARAMETER Set
    Set a configuration value (key=value).

.PARAMETER Get
    Get a specific configuration value.

.PARAMETER Mode
    Set execution mode.

.EXAMPLE
    llmconfig --explain
    Shows configuration with source explanation.

.EXAMPLE
    llmconfig --validate
    Validates the configuration.

.EXAMPLE
    llmconfig --explain --path provider.model
    Explains the source of provider.model.

.EXAMPLE
    llmconfig --set provider.model=gpt-4
    Sets the provider model.

.EXAMPLE
    llmconfig --get execution.mode
    Gets the execution mode.

.EXAMPLE
    llmconfig --mode ci
    Sets execution mode to CI.
#>
function Invoke-LLMConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Explain,

        [Parameter(Mandatory = $false)]
        [switch]$Validate,

        [Parameter(Mandatory = $false)]
        [string]$Path = $null,

        [Parameter(Mandatory = $false)]
        [string]$Profile = 'default',

        [Parameter(Mandatory = $false)]
        [ValidateSet('table', 'list', 'json', 'yaml')]
        [string]$Format = 'table',

        [Parameter(Mandatory = $false)]
        [string]$Set = $null,

        [Parameter(Mandatory = $false)]
        [string]$Get = $null,

        [Parameter(Mandatory = $false)]
        [string]$Mode = $null,

        [Parameter(Mandatory = $false)]
        [switch]$ShowSecrets,

        [Parameter(Mandatory = $false)]
        [string]$ProjectPath = $null,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$RemainingArguments
    )

    # Handle --mode (set execution mode)
    if ($Mode) {
        $validModes = Get-ValidExecutionModes
        if ($validModes -notcontains $Mode.ToLower()) {
            Write-Error "Invalid execution mode '$Mode'. Valid modes: $($validModes -join ', ')"
            return
        }
        Set-ExecutionMode -Mode $Mode -Persist
        Write-Host "Execution mode set to: $Mode" -ForegroundColor Green
        return
    }

    # Handle --get (get specific value)
    if ($Get) {
        $value = Get-ConfigValue -Path $Get -IncludeSource:$Explain
        if ($value -is [PSCustomObject] -and $value.PSObject.Properties['Value']) {
            Write-Output $value.Value
        } else {
            Write-Output $value
        }
        return
    }

    # Handle --set (set specific value)
    if ($Set) {
        if ($Set -notmatch '^([^=]+)=(.*)$') {
            Write-Error "Invalid set format. Use: --set key=value or --set section.key=value"
            return
        }
        
        $setPath = $Matches[1]
        $setValue = $Matches[2]

        # Find project
        if (-not $ProjectPath) {
            $ProjectPath = Find-ProjectRoot
        }

        if (-not $ProjectPath) {
            # Save to central config instead
            $config = Get-ProfileConfig -ProfileName $Profile
            Set-NestedValue -Config $config -Path $setPath -Value $setValue
            Save-CentralConfig -Config $config -ProfileName $Profile
            Write-Host "Configuration saved to central profile '$Profile': $setPath = $setValue" -ForegroundColor Green
        } else {
            $config = Get-ProjectConfig -ProjectPath $ProjectPath
            Set-NestedValue -Config $config -Path $setPath -Value $setValue
            Save-ProjectConfig -Config $config -ProjectPath $ProjectPath
            Write-Host "Configuration saved to project: $setPath = $setValue" -ForegroundColor Green
        }
        
        Clear-ConfigCache
        return
    }

    # Handle --validate
    if ($Validate) {
        $config = Get-EffectiveConfig -Explain
        $validation = Test-ConfigValidation -Config $config

        if ($validation.IsValid) {
            Write-Host "Configuration is valid" -ForegroundColor Green
            Write-Host "  Validated at: $($validation.ValidatedAt)" -ForegroundColor Gray
        } else {
            Write-Host "Configuration validation failed" -ForegroundColor Red
            Write-Host "  Errors: $($validation.ErrorCount)" -ForegroundColor Red
            Write-Host "  Warnings: $($validation.WarningCount)" -ForegroundColor Yellow
            Write-Host ""
            
            if ($validation.Errors.Count -gt 0) {
                Write-Host "Errors:" -ForegroundColor Red
                foreach ($err in $validation.Errors) {
                    Write-Host "  [$($err.Severity)] $($err.Path): $($err.Message)" -ForegroundColor Red
                }
            }
            
            if ($validation.Warnings.Count -gt 0) {
                Write-Host "Warnings:" -ForegroundColor Yellow
                foreach ($warn in $validation.Warnings) {
                    Write-Host "  [$($warn.Severity)] $($warn.Path): $($warn.Message)" -ForegroundColor Yellow
                }
            }
        }

        return $validation
    }

    # Handle --explain (default if no specific action)
    if ($Explain -or (-not $Validate -and -not $Get -and -not $Set -and -not $Mode)) {
        $config = Get-EffectiveConfig -Explain -MaskSecrets:(-not $ShowSecrets)
        Export-ConfigExplanation -Config $config -Format $Format -Path $Path
        return
    }
}

<#
.SYNOPSIS
    Creates an alias for the llmconfig command.

.DESCRIPTION
    Sets up 'llmconfig' as an alias for Invoke-LLMConfig.

.EXAMPLE
    Register-LLMConfigAlias
#>
function Register-LLMConfigAlias {
    [CmdletBinding()]
    param()

    $aliasName = 'llmconfig'
    $functionName = 'Invoke-LLMConfig'

    # Remove existing alias if present
    if (Get-Alias -Name $aliasName -ErrorAction SilentlyContinue) {
        Remove-Alias -Name $aliasName -Force
    }

    New-Alias -Name $aliasName -Value $functionName -Scope Global -Force
    Write-Verbose "Registered alias: $aliasName -> $functionName"
}

<#
.SYNOPSIS
    Flattens configuration for output.

.DESCRIPTION
    Helper function to flatten nested configuration into a simple list.

.PARAMETER Config
    The configuration hashtable.

.PARAMETER Prefix
    Path prefix for recursion.

.OUTPUTS
    Array of flattened configuration items.
#>
function Flatten-ConfigForOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $false)]
        [string]$Prefix = ''
    )

    $results = @()

    foreach ($key in $Config.Keys) {
        if ($key.StartsWith('_')) { continue }

        $value = $Config[$key]
        $fullPath = if ($Prefix) { "$Prefix.$key" } else { $key }

        if ($value -is [hashtable]) {
            if ($value.ContainsKey('_value')) {
                $results += [PSCustomObject]@{
                    Path = $fullPath
                    Value = $value['_value']
                    Source = $value['_source']
                }
            } elseif (-not $value.ContainsKey('_metadata')) {
                # Recurse into nested hashtable
                $nested = Flatten-ConfigForOutput -Config $value -Prefix $fullPath
                $results += $nested
            }
        } elseif ($value -isnot [array]) {
            $results += [PSCustomObject]@{
                Path = $fullPath
                Value = $value
                Source = 'default'
            }
        }
    }

    return $results
}

<#
.SYNOPSIS
    Sets a nested configuration value.

.DESCRIPTION
    Helper function to set a value using dot notation path.

.PARAMETER Config
    The configuration hashtable.

.PARAMETER Path
    Dot-notation path (e.g., 'provider.model').

.PARAMETER Value
    The value to set.
#>
function Set-NestedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $keys = $Path -split '\.'
    $current = $Config

    for ($i = 0; $i -lt $keys.Count - 1; $i++) {
        $key = $keys[$i]
        if (-not $current.ContainsKey($key)) {
            $current[$key] = @{}
        }
        $current = $current[$key]
    }

    # Try to parse value types
    $finalValue = $Value
    $lastKey = $keys[-1]
    
    # Try boolean
    if ($Value -eq 'true') { $finalValue = $true }
    elseif ($Value -eq 'false') { $finalValue = $false }
    # Try number
    elseif ($Value -match '^-?\d+$') { $finalValue = [int]$Value }
    elseif ($Value -match '^-?\d+\.\d+$') { $finalValue = [double]$Value }

    $current[$lastKey] = $finalValue
}

# Export module members
Export-ModuleMember -Function @(
    'Get-LLMWorkflowEffectiveConfig',
    'Invoke-LLMConfig',
    'Register-LLMConfigAlias'
)

# Auto-register alias on module load
Register-LLMConfigAlias
