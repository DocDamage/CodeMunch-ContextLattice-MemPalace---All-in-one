#requires -Version 5.1
<#
.SYNOPSIS
    Core configuration management for LLM Workflow platform.

.DESCRIPTION
    Provides the main configuration resolution, validation, and explanation
    functionality for the Effective Configuration System.

.NOTES
    Version: 1.0.0
    Compatible with: PowerShell 5.1+
    Precedence (lowest to highest):
        1. Built-in defaults
        2. Central named profile
        3. Project config
        4. Environment variables
        5. Command arguments
#>

# Import dependent modules
$script:ModulePath = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $script:ModulePath 'ConfigSchema.ps1') -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $script:ModulePath 'ConfigPath.ps1') -Force -ErrorAction SilentlyContinue

# Module-level cache
$script:CachedConfig = $null
$script:CachedTimestamp = $null
$script:CurrentExecutionMode = 'interactive'

<#
.SYNOPSIS
    Gets the effective configuration from all sources.

.DESCRIPTION
    Resolves configuration by merging values from all sources in order
    of precedence: defaults -> profile -> project -> environment -> arguments.
    Supports caching, source tracking, and secret masking.

.PARAMETER Profile
    Optional profile name to load from central config.

.PARAMETER ProjectPath
    Optional project path. Auto-detected if not specified.

.PARAMETER Arguments
    Optional hashtable of command-line argument overrides.

.PARAMETER Explain
    If true, includes source tracking metadata for each value.

.PARAMETER MaskSecrets
    If true, masks secret values in the output (default: true).

.PARAMETER NoCache
    If true, bypasses cached configuration and re-resolves.

.PARAMETER Raw
    If true, returns raw values without masking or metadata.

.OUTPUTS
    Hashtable containing the effective configuration.

.EXAMPLE
    $config = Get-EffectiveConfig
    PS> $config.provider.model
    gpt-4

.EXAMPLE
    $config = Get-EffectiveConfig -Explain
    PS> $config.provider.model._value
    gpt-4
    PS> $config.provider.model._source
    environment

.EXAMPLE
    $config = Get-EffectiveConfig -Arguments @{ 'execution.mode' = 'ci' }
#>
function Get-EffectiveConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Profile = 'default',

        [Parameter(Mandatory = $false)]
        [string]$ProjectPath = $null,

        [Parameter(Mandatory = $false)]
        [hashtable]$Arguments = @{},

        [Parameter(Mandatory = $false)]
        [switch]$Explain,

        [Parameter(Mandatory = $false)]
        [switch]$MaskSecrets = $true,

        [Parameter(Mandatory = $false)]
        [switch]$NoCache,

        [Parameter(Mandatory = $false)]
        [switch]$Raw
    )

    # Check cache if enabled
    if (-not $NoCache -and -not $Explain -and -not $Raw) {
        if ($script:CachedConfig -and $script:CachedTimestamp) {
            $cacheAge = (Get-Date) - $script:CachedTimestamp
            if ($cacheAge.TotalSeconds -lt 30) {
                Write-Verbose "Returning cached configuration"
                return $script:CachedConfig
            }
        }
    }

    Write-Verbose "Resolving effective configuration..."

    # Level 1: Built-in defaults
    $defaults = Get-DefaultConfig
    $result = $defaults.Clone()
    $sources = @{}
    $shadowed = @{}

    # Track sources if explaining
    if ($Explain) {
        foreach ($key in $defaults.Keys) {
            $sources = Track-Source -Sources $sources -Path $key -Source 'default' -Value $defaults[$key]
        }
    }

    # Level 2: Central/Profile config (lowest external priority)
    $profileConfig = Get-ProfileConfig -ProfileName $Profile -IncludeSource:$Explain
    if ($profileConfig -and $profileConfig.Count -gt 0) {
        Write-Verbose "Merging profile config (profile: $Profile)"
        $mergeResult = Merge-ConfigWithTracking -Base $result -Overlay $profileConfig -SourceLabel 'profile' -Sources $sources -Shadowed $shadowed -Explain:$Explain
        $result = $mergeResult.Config
        $sources = $mergeResult.Sources
        $shadowed = $mergeResult.Shadowed
    }

    # Level 3: Project config
    $projectConfig = Get-ProjectConfig -ProjectPath $ProjectPath -IncludeSource:$Explain
    if ($projectConfig -and $projectConfig.Count -gt 0) {
        Write-Verbose "Merging project config"
        $mergeResult = Merge-ConfigWithTracking -Base $result -Overlay $projectConfig -SourceLabel 'project' -Sources $sources -Shadowed $shadowed -Explain:$Explain
        $result = $mergeResult.Config
        $sources = $mergeResult.Sources
        $shadowed = $mergeResult.Shadowed
    }

    # Level 4: Environment variables
    $envConfig = Get-EnvironmentConfig -IncludeSource:$Explain
    if ($envConfig -and $envConfig.Count -gt 0) {
        Write-Verbose "Merging environment config"
        $mergeResult = Merge-ConfigWithTracking -Base $result -Overlay $envConfig -SourceLabel 'environment' -Sources $sources -Shadowed $shadowed -Explain:$Explain
        $result = $mergeResult.Config
        $sources = $mergeResult.Sources
        $shadowed = $mergeResult.Shadowed
    }

    # Level 5: Command arguments (highest priority)
    if ($Arguments -and $Arguments.Count -gt 0) {
        Write-Verbose "Merging argument overrides"
        $argConfig = @{}
        foreach ($key in $Arguments.Keys) {
            # Support dot-notation keys like 'execution.mode'
            Set-NestedValue -Config $argConfig -Path $key -Value $Arguments[$key]
        }
        
        if ($Explain) {
            $argConfig = Add-SourceMetadata -Config $argConfig -Source 'argument'
        }
        
        $mergeResult = Merge-ConfigWithTracking -Base $result -Overlay $argConfig -SourceLabel 'argument' -Sources $sources -Shadowed $shadowed -Explain:$Explain
        $result = $mergeResult.Config
        $sources = $mergeResult.Sources
        $shadowed = $mergeResult.Shadowed
    }

    # Add metadata
    $result['schemaVersion'] = 1
    $result['updatedUtc'] = (Get-Date -Format 'o')

    if ($Explain) {
        $result['_metadata'] = @{
            sources = $sources
            shadowed = $shadowed
            resolutionOrder = @('default', 'profile', 'project', 'environment', 'argument')
        }
    }

    # Mask secrets unless raw output requested
    if ($MaskSecrets -and -not $Raw) {
        $schema = Get-ConfigSchema
        $result = Protect-ConfigSecrets -Config $result -Schema $schema
    }

    # Update cache
    if (-not $Explain -and -not $Raw) {
        $script:CachedConfig = $result.Clone()
        $script:CachedTimestamp = Get-Date
    }

    return $result
}

<#
.SYNOPSIS
    Gets a single configuration value with source information.

.DESCRIPTION
    Retrieves a specific configuration value by path, optionally
    including source tracking and validation information.

.PARAMETER Path
    The configuration path using dot notation (e.g., 'provider.model').

.PARAMETER DefaultValue
    Default value to return if path not found.

.PARAMETER Config
    Optional configuration hashtable. Uses Get-EffectiveConfig if not provided.

.PARAMETER IncludeSource
    If true, returns a metadata object with value and source.

.PARAMETER Validate
    If true, validates the value against schema.

.OUTPUTS
    The configuration value, or PSCustomObject with metadata if IncludeSource.

.EXAMPLE
    Get-ConfigValue -Path 'provider.model'
    gpt-4

.EXAMPLE
    Get-ConfigValue -Path 'provider.model' -IncludeSource
    Returns: @{ Value = 'gpt-4'; Source = 'environment'; IsSecret = $false }

.EXAMPLE
    Get-ConfigValue -Path 'execution.timeout' -DefaultValue 300
#>
function Get-ConfigValue {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [object]$DefaultValue = $null,

        [Parameter(Mandatory = $false)]
        [hashtable]$Config = $null,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeSource,

        [Parameter(Mandatory = $false)]
        [switch]$Validate
    )

    # Get config if not provided
    if (-not $Config) {
        $Config = Get-EffectiveConfig -Explain:$IncludeSource -NoCache:$($IncludeSource)
    }

    # Navigate the path
    $keys = $Path -split '\.'
    $current = $Config
    $schema = Get-ConfigSchema
    $currentSchema = $schema

    foreach ($key in $keys) {
        # Handle metadata-wrapped values
        if ($current -is [hashtable] -and $current.ContainsKey('_value')) {
            $current = $current['_value']
        }

        if (-not ($current -is [hashtable]) -or -not $current.ContainsKey($key)) {
            if ($IncludeSource) {
                return [PSCustomObject]@{
                    Value = $DefaultValue
                    Source = 'default'
                    Path = $Path
                    IsDefault = $true
                    IsValid = $true
                    Errors = @()
                }
            }
            return $DefaultValue
        }

        $current = $current[$key]

        # Track schema
        if ($currentSchema -and $currentSchema.ContainsKey($key)) {
            if ($currentSchema[$key].ContainsKey('properties')) {
                $currentSchema = $currentSchema[$key].properties
            } else {
                $currentSchema = $currentSchema[$key]
            }
        }
    }

    # Extract value from metadata wrapper if present
    $source = 'unknown'
    $shadowedBy = @()
    $isSecret = $false

    if ($current -is [hashtable]) {
        if ($current.ContainsKey('_value')) {
            $source = $current['_source']
            $current = $current['_value']
        }
        if ($current.ContainsKey('_metadata') -and $current._metadata.ContainsKey('sources')) {
            $pathSource = $current._metadata.sources[$Path]
            if ($pathSource) {
                $source = $pathSource.source
                $shadowedBy = $pathSource.shadowedBy
            }
        }
    }

    # Check if secret
    $isSecret = Test-SecretKey -Key ($keys[-1]) -Schema $currentSchema

    # Validate if requested
    $validation = $null
    if ($Validate -and $currentSchema) {
        $validation = Test-ConfigValue -Path $Path -Value $current -Schema $currentSchema
    }

    if ($IncludeSource) {
        $result = [PSCustomObject]@{
            Value = $current
            Source = $source
            Path = $Path
            IsSecret = $isSecret
            IsDefault = ($source -eq 'default')
            ShadowedBy = $shadowedBy
        }

        if ($validation) {
            $result | Add-Member -NotePropertyName 'IsValid' -NotePropertyValue $validation.IsValid
            $result | Add-Member -NotePropertyName 'ValidationErrors' -NotePropertyValue $validation.Errors
        }

        return $result
    }

    return $current
}

<#
.SYNOPSIS
    Validates configuration against schema.

.DESCRIPTION
    Performs comprehensive validation of configuration values against
    the defined schema, returning detailed error information.

.PARAMETER Config
    The configuration hashtable to validate. Uses effective config if not provided.

.PARAMETER Strict
    If true, treats warnings as errors.

.PARAMETER CheckRequired
    If true, validates that all required fields are present.

.OUTPUTS
    PSCustomObject with validation results.

.EXAMPLE
    $result = Test-ConfigValidation
    PS> $result.IsValid
    True

.EXAMPLE
    $result = Test-ConfigValidation -Config $myConfig -Strict
    PS> $result.Errors
    @{ Path = 'provider.timeout'; Message = 'Value below minimum'; Severity = 'error' }
#>
function Test-ConfigValidation {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$Config = $null,

        [Parameter(Mandatory = $false)]
        [switch]$Strict,

        [Parameter(Mandatory = $false)]
        [switch]$CheckRequired
    )

    # Get config if not provided
    if (-not $Config) {
        $Config = Get-EffectiveConfig -Explain
    }

    $schema = Get-ConfigSchema
    $errors = @()
    $warnings = @()

    # Remove metadata before validation
    $cleanConfig = @{}
    foreach ($key in $Config.Keys) {
        if (-not $key.StartsWith('_')) {
            $cleanConfig[$key] = $Config[$key]
        }
    }

    # Validate each category
    foreach ($category in $schema.Keys) {
        if ($category -eq 'schemaVersion') { continue }

        $categorySchema = $schema[$category]
        
        # Check if category exists
        if (-not $cleanConfig.ContainsKey($category)) {
            if ($CheckRequired -and $categorySchema.required -eq $true) {
                $errors += [PSCustomObject]@{
                    Path = $category
                    Message = "Required category '$category' is missing"
                    Severity = 'error'
                    Source = 'validation'
                }
            }
            continue
        }

        $categoryValue = $cleanConfig[$category]

        # Validate category properties
        if ($categorySchema.properties) {
            foreach ($propName in $categorySchema.properties.Keys) {
                $propSchema = $categorySchema.properties[$propName]
                $fullPath = "$category.$propName"

                # Check if property exists
                if ($categoryValue -is [hashtable] -and $categoryValue.ContainsKey($propName)) {
                    $propValue = $categoryValue[$propName]
                    
                    # Unwrap metadata if present
                    if ($propValue -is [hashtable] -and $propValue.ContainsKey('_value')) {
                        $propValue = $propValue['_value']
                    }

                    $validation = Test-ConfigValue -Path $fullPath -Value $propValue -Schema $propSchema
                    
                    if (-not $validation.IsValid) {
                        foreach ($err in $validation.Errors) {
                            $errors += [PSCustomObject]@{
                                Path = $fullPath
                                Message = $err
                                Severity = 'error'
                                Source = 'validation'
                            }
                        }
                    }

                    if ($validation.Warnings) {
                        foreach ($warn in $validation.Warnings) {
                            $warnings += [PSCustomObject]@{
                                Path = $fullPath
                                Message = $warn
                                Severity = 'warning'
                                Source = 'validation'
                            }
                        }
                    }
                } elseif ($CheckRequired -and $propSchema.required -eq $true) {
                    $errors += [PSCustomObject]@{
                        Path = $fullPath
                        Message = "Required property '$propName' is missing"
                        Severity = 'error'
                        Source = 'validation'
                    }
                }
            }
        }
    }

    # Check for unknown categories
    foreach ($key in $cleanConfig.Keys) {
        if (-not $schema.ContainsKey($key)) {
            $warnings += [PSCustomObject]@{
                Path = $key
                Message = "Unknown configuration category '$key'"
                Severity = 'warning'
                Source = 'validation'
            }
        }
    }

    $isValid = ($errors.Count -eq 0)
    if ($Strict -and $warnings.Count -gt 0) {
        $isValid = $false
    }

    return [PSCustomObject]@{
        IsValid = $isValid
        Errors = $errors
        Warnings = $warnings
        ErrorCount = $errors.Count
        WarningCount = $warnings.Count
        ValidatedAt = (Get-Date -Format 'o')
    }
}

<#
.SYNOPSIS
    Exports configuration with source explanation.

.DESCRIPTION
    Generates a detailed explanation of configuration value sources,
    including shadowing information and secret masking.

.PARAMETER Config
    Optional configuration to explain. Uses effective config if not provided.

.PARAMETER Format
    Output format: 'table', 'list', 'json', or 'yaml'.

.PARAMETER IncludeDefaults
    If true, includes default values in output.

.PARAMETER Path
    Optional path filter to explain only specific values.

.OUTPUTS
    Formatted configuration explanation.

.EXAMPLE
    Export-ConfigExplanation
    Displays table of all config values with sources.

.EXAMPLE
    Export-ConfigExplanation -Path 'provider' -Format json
    Returns JSON of provider settings with sources.
#>
function Export-ConfigExplanation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$Config = $null,

        [Parameter(Mandatory = $false)]
        [ValidateSet('table', 'list', 'json', 'yaml')]
        [string]$Format = 'table',

        [Parameter(Mandatory = $false)]
        [switch]$IncludeDefaults,

        [Parameter(Mandatory = $false)]
        [string]$Path = $null
    )

    # Get config if not provided
    if (-not $Config) {
        $Config = Get-EffectiveConfig -Explain -MaskSecrets
    }

    # Filter by path if specified
    if ($Path) {
        $keys = $Path -split '\.'
        foreach ($key in $keys) {
            if ($Config.ContainsKey($key)) {
                $Config = $Config[$key]
            } else {
                Write-Error "Path '$Path' not found in configuration"
                return
            }
        }
    }

    # Flatten config for explanation
    $flattened = Flatten-Config -Config $Config -Prefix $Path

    # Filter defaults if not included
    if (-not $IncludeDefaults) {
        $flattened = $flattened | Where-Object { $_.Source -ne 'default' }
    }

    switch ($Format) {
        'table' {
            $flattened | Select-Object Path, Value, Source, @{N='ShadowedBy'; E={$_.ShadowedBy -join ', '}}, @{N='IsSecret'; E={$_.IsSecret}} | 
                Format-Table -AutoSize
        }
        'list' {
            foreach ($item in $flattened) {
                Write-Output ""
                Write-Output "Path:    $($item.Path)"
                Write-Output "Value:   $($item.Value)"
                Write-Output "Source:  $($item.Source)"
                if ($item.ShadowedBy) {
                    Write-Output "Shadowed by: $($item.ShadowedBy -join ', ')"
                }
                if ($item.IsSecret) {
                    Write-Output "[SECRET]"
                }
                Write-Output "---"
            }
        }
        'json' {
            $output = @{
                explained = $flattened
                metadata = @{
                    generatedAt = (Get-Date -Format 'o')
                    totalValues = $flattened.Count
                }
            }
            $output | ConvertTo-Json -Depth 5
        }
        'yaml' {
            # Simple YAML-like output
            Write-Output "# Configuration Explanation"
            Write-Output "# Generated: $(Get-Date -Format 'o')"
            Write-Output ""
            foreach ($item in $flattened) {
                Write-Output "$($item.Path):"
                Write-Output "  value: $($item.Value)"
                Write-Output "  source: $($item.Source)"
                if ($item.ShadowedBy) {
                    Write-Output "  shadowedBy: [$($item.ShadowedBy -join ', ')]"
                }
                Write-Output "  isSecret: $($item.IsSecret)"
                Write-Output ""
            }
        }
    }
}

<#
.SYNOPSIS
    Gets the current execution mode.

.DESCRIPTION
    Returns the active execution mode for the current session.
    Reads from cached config or environment, defaults to 'interactive'.

.OUTPUTS
    String representing the execution mode.

.EXAMPLE
    $mode = Get-ExecutionMode
    PS> $mode
    interactive
#>
function Get-ExecutionMode {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Check module-level override first
    if ($script:CurrentExecutionMode -and $script:CurrentExecutionMode -ne 'interactive') {
        return $script:CurrentExecutionMode
    }

    # Check environment variable
    if ($env:LLMWF_EXECUTION_MODE) {
        $mode = $env:LLMWF_EXECUTION_MODE.ToLower()
        if (Test-ExecutionMode -Mode $mode) {
            return $mode
        }
    }

    # Check effective config
    try {
        $config = Get-EffectiveConfig -NoCache
        if ($config.execution -and $config.execution.mode) {
            $mode = $config.execution.mode.ToString().ToLower()
            if (Test-ExecutionMode -Mode $mode) {
                return $mode
            }
        }
    }
    catch {
        Write-Verbose "Could not read execution mode from config: $_"
    }

    return 'interactive'
}

<#
.SYNOPSIS
    Sets the execution mode for the current session.

.DESCRIPTION
    Updates the module-level execution mode override. This does not
    persist to configuration files.

.PARAMETER Mode
    The execution mode to set.

.PARAMETER Persist
    If true, also saves to project configuration.

.PARAMETER ProjectPath
    Optional project path for persisting.

.OUTPUTS
    None

.EXAMPLE
    Set-ExecutionMode -Mode 'ci'

.EXAMPLE
    Set-ExecutionMode -Mode 'watch' -Persist
#>
function Set-ExecutionMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('interactive', 'ci', 'watch', 'heal-watch', 'scheduled', 'mcp-readonly', 'mcp-mutating')]
        [string]$Mode,

        [Parameter(Mandatory = $false)]
        [switch]$Persist,

        [Parameter(Mandatory = $false)]
        [string]$ProjectPath = $null
    )

    $oldMode = $script:CurrentExecutionMode
    $script:CurrentExecutionMode = $Mode.ToLower()

    Write-Verbose "Execution mode changed from '$oldMode' to '$Mode'"

    # Clear cache to force re-resolution
    $script:CachedConfig = $null
    $script:CachedTimestamp = $null

    if ($Persist) {
        # Update environment variable
        $env:LLMWF_EXECUTION_MODE = $Mode

        # Update project config if found
        if ([string]::IsNullOrEmpty($ProjectPath)) {
            $ProjectPath = Find-ProjectRoot
        }

        if ($ProjectPath) {
            $config = Get-ProjectConfig -ProjectPath $ProjectPath
            if (-not $config.ContainsKey('execution')) {
                $config['execution'] = @{}
            }
            $config['execution']['mode'] = $Mode
            Save-ProjectConfig -Config $config -ProjectPath $ProjectPath -Force
            Write-Verbose "Execution mode persisted to project config"
        } else {
            Write-Warning "No project found to persist execution mode"
        }
    }
}

<#
.SYNOPSIS
    Clears the configuration cache.

.DESCRIPTION
    Forces the next Get-EffectiveConfig call to re-resolve all
    configuration values from sources.

.EXAMPLE
    Clear-ConfigCache
#>
function Clear-ConfigCache {
    [CmdletBinding()]
    param()

    $script:CachedConfig = $null
    $script:CachedTimestamp = $null
    Write-Verbose "Configuration cache cleared"
}

# Helper function: Merge configuration with source tracking
function Merge-ConfigWithTracking {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Base,

        [Parameter(Mandatory = $true)]
        [hashtable]$Overlay,

        [Parameter(Mandatory = $true)]
        [string]$SourceLabel,

        [Parameter(Mandatory = $false)]
        [hashtable]$Sources = @{},

        [Parameter(Mandatory = $false)]
        [hashtable]$Shadowed = @{},

        [Parameter(Mandatory = $false)]
        [switch]$Explain
    )

    $result = $Base.Clone()

    foreach ($key in $Overlay.Keys) {
        $overlayValue = $Overlay[$key]

        # Check if this key already exists and would be shadowed
        if ($result.ContainsKey($key) -and $Explain) {
            $currentSource = $Sources[$key]
            if ($currentSource) {
                if (-not $Shadowed[$key]) {
                    $Shadowed[$key] = @()
                }
                $Shadowed[$key] += @($SourceLabel)
            }
        }

        # Handle nested hashtables
        if ($result.ContainsKey($key) -and $result[$key] -is [hashtable] -and $overlayValue -is [hashtable]) {
            $nestedResult = Merge-ConfigWithTracking -Base $result[$key] -Overlay $overlayValue -SourceLabel $SourceLabel -Sources $Sources -Shadowed $Shadowed -Explain:$Explain
            $result[$key] = $nestedResult.Config
            $Sources = $nestedResult.Sources
            $Shadowed = $nestedResult.Shadowed
        } else {
            $result[$key] = $overlayValue
            if ($Explain) {
                $Sources[$key] = @{
                    source = $SourceLabel
                    value = if ($overlayValue -is [hashtable] -and $overlayValue.ContainsKey('_value')) { 
                        $overlayValue['_value'] 
                    } else { 
                        $overlayValue 
                    }
                }
            }
        }
    }

    return @{
        Config = $result
        Sources = $Sources
        Shadowed = $Shadowed
    }
}

# Helper function: Track source metadata
function Track-Source {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Sources,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $false)]
        $Value = $null
    )

    $Sources[$Path] = @{
        source = $Source
        value = $Value
    }

    # Handle nested values
    if ($Value -is [hashtable]) {
        foreach ($key in $Value.Keys) {
            $Sources = Track-Source -Sources $Sources -Path "$Path.$key" -Source $Source -Value $Value[$key]
        }
    }

    return $Sources
}

# Helper function: Set nested value using dot notation
function Set-NestedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        $Value
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

    $current[$keys[-1]] = $Value
}

# Helper function: Flatten configuration for explanation
function Flatten-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $false)]
        [string]$Prefix = ''
    )

    $results = @()

    foreach ($key in $Config.Keys) {
        # Skip metadata keys
        if ($key.StartsWith('_') -or $key -in @('schemaVersion', 'updatedUtc', 'createdByRunId', 'profileName')) {
            continue
        }

        $value = $Config[$key]
        $fullPath = if ($Prefix) { "$Prefix.$key" } else { $key }

        # Determine source
        $source = 'default'
        $shadowedBy = @()
        $isSecret = Test-SecretKey -Key $key

        if ($value -is [hashtable]) {
            if ($value.ContainsKey('_value')) {
                $source = $value['_source']
                $displayValue = if ($isSecret) { '***REDACTED***' } else { $value['_value'] }
                $results += [PSCustomObject]@{
                    Path = $fullPath
                    Value = $displayValue
                    Source = $source
                    ShadowedBy = $shadowedBy
                    IsSecret = $isSecret
                }
            } elseif ($value.ContainsKey('_metadata')) {
                # Skip metadata wrapper
                continue
            } else {
                # Recurse into nested hashtable
                $nested = Flatten-Config -Config $value -Prefix $fullPath
                $results += $nested
            }
        } else {
            $displayValue = if ($isSecret) { '***REDACTED***' } else { $value }
            $results += [PSCustomObject]@{
                Path = $fullPath
                Value = $displayValue
                Source = $source
                ShadowedBy = $shadowedBy
                IsSecret = $isSecret
            }
        }
    }

    return $results
}

# Export module members
Export-ModuleMember -Function @(
    'Get-EffectiveConfig',
    'Get-ConfigValue',
    'Test-ConfigValidation',
    'Export-ConfigExplanation',
    'Get-ExecutionMode',
    'Set-ExecutionMode',
    'Clear-ConfigCache'
)
