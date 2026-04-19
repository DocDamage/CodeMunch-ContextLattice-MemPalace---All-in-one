#requires -Version 5.1
<#
.SYNOPSIS
    Configuration path management for LLM Workflow platform.

.DESCRIPTION
    Handles configuration file discovery, path resolution, and loading
    of configuration from various locations (central, project, profile).

.NOTES
    Version: 1.0.0
    Compatible with: PowerShell 5.1+
    Config directories follow XDG Base Directory Specification where applicable.
#>

# Module-level constants
$script:ConfigFileName = 'effective-config.json'
$script:PolicyFileName = 'policy.json'
$script:WorkspaceFileName = 'workspace.json'
$script:ProjectConfigDir = '.llm-workflow'
$script:ConfigSubdir = 'config'
$script:EnvPrefix = 'LLMWF_'

<#
.SYNOPSIS
    Gets configuration file paths.

.DESCRIPTION
    Returns standardized paths to configuration files based on
    scope (project, central/profile) and file type.

.PARAMETER Scope
    The configuration scope: 'project', 'central', or 'profile'.

.PARAMETER Type
    The config type: 'effective', 'policy', or 'workspace'.

.PARAMETER ProjectPath
    Optional project root path for project-scoped config.

.OUTPUTS
    System.IO.FileInfo or string path to the configuration file.

.EXAMPLE
    Get-ConfigPath -Scope project -Type effective
    Returns: ./.llm-workflow/config/effective-config.json

.EXAMPLE
    Get-ConfigPath -Scope central -Type policy
    Returns: ~/.config/llm-workflow/policy.json
#>
function Get-ConfigPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('project', 'central', 'profile', 'workspace')]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [ValidateSet('effective', 'policy', 'workspace', 'profile')]
        [string]$Type,

        [Parameter(Mandatory = $false)]
        [string]$ProjectPath = (Get-Location).Path
    )

    $fileName = switch ($Type) {
        'effective' { $script:ConfigFileName }
        'policy' { $script:PolicyFileName }
        'workspace' { $script:WorkspaceFileName }
        'profile' { 'profile.json' }
        default { $script:ConfigFileName }
    }

    switch ($Scope) {
        'project' {
            $configDir = Join-Path $ProjectPath $script:ProjectConfigDir $script:ConfigSubdir
            return Join-Path $configDir $fileName
        }
        'central' {
            # Use XDG_CONFIG_HOME or default to ~/.config
            $configHome = if ($env:XDG_CONFIG_HOME) { 
                $env:XDG_CONFIG_HOME 
            } else { 
                Join-Path $HOME '.config' 
            }
            $configDir = Join-Path $configHome 'llm-workflow'
            return Join-Path $configDir $fileName
        }
        'profile' {
            # Profile configs are stored in central location
            return Get-ConfigPath -Scope central -Type profile
        }
        'workspace' {
            # Workspace config is in project
            return Get-ConfigPath -Scope project -Type workspace -ProjectPath $ProjectPath
        }
    }
}

<#
.SYNOPSIS
    Finds the project root directory.

.DESCRIPTION
    Searches upward from the given path to find the project root
    by looking for the .llm-workflow directory.

.PARAMETER StartPath
    The path to start searching from. Defaults to current directory.

.OUTPUTS
    String path to project root, or $null if not found.

.EXAMPLE
    Find-ProjectRoot
    Returns: C:\Projects\MyLLMProject

.EXAMPLE
    Find-ProjectRoot -StartPath C:\Projects\MyLLMProject\src
    Returns: C:\Projects\MyLLMProject
#>
function Find-ProjectRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$StartPath = (Get-Location).Path
    )

    $currentPath = Resolve-Path $StartPath
    
    while ($currentPath -and $currentPath -ne [IO.Path]::GetPathRoot($currentPath)) {
        $configDir = Join-Path $currentPath $script:ProjectConfigDir
        if (Test-Path $configDir -PathType Container) {
            return $currentPath
        }
        $currentPath = Split-Path $currentPath -Parent
    }

    return $null
}

<#
.SYNOPSIS
    Ensures the project configuration directory exists.

.DESCRIPTION
    Creates the .llm-workflow/config directory structure if it doesn't exist.

.PARAMETER ProjectPath
    The project root path.

.OUTPUTS
    String path to the created config directory.

.EXAMPLE
    Initialize-ProjectConfigDir -ProjectPath C:\MyProject
#>
function Initialize-ProjectConfigDir {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ProjectPath = (Get-Location).Path
    )

    $configDir = Join-Path $ProjectPath $script:ProjectConfigDir $script:ConfigSubdir
    
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        Write-Verbose "Created config directory: $configDir"
    }

    return $configDir
}

<#
.SYNOPSIS
    Ensures the central configuration directory exists.

.DESCRIPTION
    Creates the central config directory (~/.config/llm-workflow) if needed.

.OUTPUTS
    String path to the central config directory.

.EXAMPLE
    Initialize-CentralConfigDir
#>
function Initialize-CentralConfigDir {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $configHome = if ($env:XDG_CONFIG_HOME) { 
        $env:XDG_CONFIG_HOME 
    } else { 
        Join-Path $HOME '.config' 
    }
    $configDir = Join-Path $configHome 'llm-workflow'
    
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        Write-Verbose "Created central config directory: $configDir"
    }

    return $configDir
}

<#
.SYNOPSIS
    Loads project-level configuration.

.DESCRIPTION
    Reads and parses the project configuration file. Returns null
    if the file doesn't exist or is invalid.

.PARAMETER ProjectPath
    Optional project root path. Auto-detected if not specified.

.PARAMETER MergeWithDefaults
    If true, merges with default configuration.

.PARAMETER IncludeSource
    If true, adds _source metadata to each value.

.OUTPUTS
    Hashtable containing project configuration, or null.

.EXAMPLE
    $config = Get-ProjectConfig
    PS> $config.provider.model
    gpt-4

.EXAMPLE
    $config = Get-ProjectConfig -IncludeSource
    PS> $config.provider.model._value
    gpt-4
    PS> $config.provider.model._source
    project
#>
function Get-ProjectConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ProjectPath = $null,

        [Parameter(Mandatory = $false)]
        [switch]$MergeWithDefaults,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeSource
    )

    # Auto-detect project path if not provided
    if ([string]::IsNullOrEmpty($ProjectPath)) {
        $ProjectPath = Find-ProjectRoot
        if (-not $ProjectPath) {
            Write-Verbose "No project root found"
            if ($MergeWithDefaults) {
                return Get-DefaultConfig
            }
            return @{}
        }
    }

    $configPath = Get-ConfigPath -Scope project -Type effective -ProjectPath $ProjectPath
    
    if (-not (Test-Path $configPath)) {
        Write-Verbose "Project config not found at: $configPath"
        if ($MergeWithDefaults) {
            return Get-DefaultConfig
        }
        return @{}
    }

    try {
        $configJson = Get-Content $configPath -Raw -ErrorAction Stop
        $config = ConvertFrom-Json $configJson -ErrorAction Stop
        
        # Convert to hashtable and add source tracking if requested
        $configHash = ConvertTo-Hashtable -InputObject $config
        
        if ($IncludeSource) {
            $configHash = Add-SourceMetadata -Config $configHash -Source 'project'
        }

        if ($MergeWithDefaults) {
            $defaults = Get-DefaultConfig
            $configHash = Merge-Config -Base $defaults -Overlay $configHash
        }

        return $configHash
    }
    catch {
        Write-Warning "Failed to load project config from '$configPath': $_"
        if ($MergeWithDefaults) {
            return Get-DefaultConfig
        }
        return @{}
    }
}

<#
.SYNOPSIS
    Loads central/profile configuration.

.DESCRIPTION
    Reads and parses the central (user-level) configuration file.
    Returns null if the file doesn't exist.

.PARAMETER ProfileName
    Optional profile name to load. If not specified, loads the default profile.

.PARAMETER MergeWithDefaults
    If true, merges with default configuration.

.PARAMETER IncludeSource
    If true, adds _source metadata to each value.

.OUTPUTS
    Hashtable containing profile configuration, or empty hashtable.

.EXAMPLE
    $config = Get-ProfileConfig
    PS> $config.provider.apiKey
    sk-...

.EXAMPLE
    $config = Get-ProfileConfig -ProfileName 'work'
#>
function Get-ProfileConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ProfileName = 'default',

        [Parameter(Mandatory = $false)]
        [switch]$MergeWithDefaults,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeSource
    )

    $configDir = Initialize-CentralConfigDir
    
    # Profile-specific file or default effective-config.json
    if ($ProfileName -eq 'default') {
        $configPath = Join-Path $configDir $script:ConfigFileName
    } else {
        $configPath = Join-Path $configDir "profile.$ProfileName.json"
    }
    
    if (-not (Test-Path $configPath)) {
        Write-Verbose "Profile config not found at: $configPath"
        if ($MergeWithDefaults) {
            return Get-DefaultConfig
        }
        return @{}
    }

    try {
        $configJson = Get-Content $configPath -Raw -ErrorAction Stop
        $config = ConvertFrom-Json $configJson -ErrorAction Stop
        
        $configHash = ConvertTo-Hashtable -InputObject $config
        
        if ($IncludeSource) {
            $sourceLabel = if ($ProfileName -eq 'default') { 'central' } else { "profile:$ProfileName" }
            $configHash = Add-SourceMetadata -Config $configHash -Source $sourceLabel
        }

        if ($MergeWithDefaults) {
            $defaults = Get-DefaultConfig
            $configHash = Merge-Config -Base $defaults -Overlay $configHash
        }

        return $configHash
    }
    catch {
        Write-Warning "Failed to load profile config from '$configPath': $_"
        if ($MergeWithDefaults) {
            return Get-DefaultConfig
        }
        return @{}
    }
}

<#
.SYNOPSIS
    Loads environment variable configuration.

.DESCRIPTION
    Reads configuration values from environment variables with the
    LLMWF_ prefix. Supports nested configuration via double underscore.

.PARAMETER IncludeSource
    If true, adds _source metadata to each value.

.OUTPUTS
    Hashtable containing environment-based configuration.

.EXAMPLE
    $envConfig = Get-EnvironmentConfig
    # LLMWF_PROVIDER_MODEL=gpt-4 becomes $envConfig.provider.model

.EXAMPLE
    $envConfig = Get-EnvironmentConfig -IncludeSource
    PS> $envConfig.provider.model._value
    gpt-4
    PS> $envConfig.provider.model._source
    environment
#>
function Get-EnvironmentConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$IncludeSource
    )

    $config = @{}
    $prefix = $script:EnvPrefix

    Get-ChildItem Env: | Where-Object { $_.Name -like "$prefix*" } | ForEach-Object {
        $envName = $_.Name
        $envValue = $_.Value
        
        # Remove prefix and split by double underscore for nesting
        $configPath = $envName.Substring($prefix.Length)
        $keys = $configPath -split '__'
        
        # Convert keys to lowercase for consistency
        $keys = $keys | ForEach-Object { $_.ToLower() }
        
        # Build nested structure
        $current = $config
        for ($i = 0; $i -lt $keys.Count - 1; $i++) {
            $key = $keys[$i]
            if (-not $current.ContainsKey($key)) {
                $current[$key] = @{}
            }
            $current = $current[$key]
        }
        
        # Set the final value
        $finalKey = $keys[-1]
        
        if ($IncludeSource) {
            $current[$finalKey] = @{
                _value = $envValue
                _source = 'environment'
                _envName = $envName
            }
        } else {
            $current[$finalKey] = $envValue
        }
    }

    return $config
}

<#
.SYNOPSIS
    Saves configuration to project config file.

.DESCRIPTION
    Writes configuration to the project-level effective-config.json file.

.PARAMETER Config
    The configuration hashtable to save.

.PARAMETER ProjectPath
    Optional project root path. Auto-detected if not specified.

.PARAMETER Force
    If true, overwrites existing file without prompting.

.EXAMPLE
    Save-ProjectConfig -Config $myConfig

.EXAMPLE
    Save-ProjectConfig -Config $myConfig -ProjectPath C:\MyProject
#>
function Save-ProjectConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $false)]
        [string]$ProjectPath = $null,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    # Auto-detect project path if not provided
    if ([string]::IsNullOrEmpty($ProjectPath)) {
        $ProjectPath = Find-ProjectRoot
        if (-not $ProjectPath) {
            throw "No project root found. Please specify -ProjectPath or run from within a project."
        }
    }

    $configPath = Get-ConfigPath -Scope project -Type effective -ProjectPath $ProjectPath

    if ((Test-Path $configPath) -and -not $Force -and -not $PSCmdlet.ShouldProcess($configPath, 'Overwrite')) {
        return
    }

    # Ensure directory exists
    $configDir = Split-Path $configPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Add metadata
    $configToSave = $Config.Clone()
    $configToSave['schemaVersion'] = 1
    $configToSave['updatedUtc'] = (Get-Date -Format 'o')

    # Remove internal metadata before saving
    $configToSave = Remove-SourceMetadata -Config $configToSave

    try {
        $json = $configToSave | ConvertTo-Json -Depth 10 -Compress:$false
        Set-Content -Path $configPath -Value $json -Force:$Force
        Write-Verbose "Configuration saved to: $configPath"
    }
    catch {
        throw "Failed to save configuration: $_"
    }
}

<#
.SYNOPSIS
    Saves configuration to central config file.

.DESCRIPTION
    Writes configuration to the central (user-level) config file.

.PARAMETER Config
    The configuration hashtable to save.

.PARAMETER ProfileName
    Optional profile name. Saves to default if not specified.

.PARAMETER Force
    If true, overwrites existing file without prompting.

.EXAMPLE
    Save-CentralConfig -Config $myConfig

.EXAMPLE
    Save-CentralConfig -Config $myConfig -ProfileName 'work'
#>
function Save-CentralConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $false)]
        [string]$ProfileName = 'default',

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    $configDir = Initialize-CentralConfigDir
    
    if ($ProfileName -eq 'default') {
        $configPath = Join-Path $configDir $script:ConfigFileName
    } else {
        $configPath = Join-Path $configDir "profile.$ProfileName.json"
    }

    if ((Test-Path $configPath) -and -not $Force -and -not $PSCmdlet.ShouldProcess($configPath, 'Overwrite')) {
        return
    }

    # Add metadata
    $configToSave = $Config.Clone()
    $configToSave['schemaVersion'] = 1
    $configToSave['updatedUtc'] = (Get-Date -Format 'o')
    $configToSave['profileName'] = $ProfileName

    # Remove internal metadata
    $configToSave = Remove-SourceMetadata -Config $configToSave

    try {
        $json = $configToSave | ConvertTo-Json -Depth 10 -Compress:$false
        Set-Content -Path $configPath -Value $json -Force:$Force
        Write-Verbose "Configuration saved to: $configPath"
    }
    catch {
        throw "Failed to save configuration: $_"
    }
}

# Helper function: Convert PSCustomObject to Hashtable
function ConvertTo-Hashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $InputObject
    )

    process {
        if ($null -eq $InputObject) {
            return $null
        }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @()
            foreach ($item in $InputObject) {
                $collection += (ConvertTo-Hashtable -InputObject $item)
            }
            return $collection
        }

        if ($InputObject -is [PSCustomObject]) {
            $hash = @{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $hash[$property.Name] = (ConvertTo-Hashtable -InputObject $property.Value)
            }
            return $hash
        }

        return $InputObject
    }
}

# Helper function: Add source metadata to config values
function Add-SourceMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    $result = @{}
    foreach ($key in $Config.Keys) {
        $value = $Config[$key]
        if ($value -is [hashtable]) {
            # Check if already has metadata
            if ($value.ContainsKey('_value') -or $value.ContainsKey('_source')) {
                $result[$key] = $value
            } else {
                $result[$key] = Add-SourceMetadata -Config $value -Source $Source
            }
        } else {
            $result[$key] = @{
                _value = $value
                _source = $Source
            }
        }
    }
    return $result
}

# Helper function: Remove source metadata from config
function Remove-SourceMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $result = @{}
    foreach ($key in $Config.Keys) {
        # Skip metadata keys
        if ($key -eq 'schemaVersion' -or $key -eq 'updatedUtc' -or $key -eq 'createdByRunId' -or $key -eq 'profileName') {
            $result[$key] = $Config[$key]
            continue
        }

        $value = $Config[$key]
        if ($value -is [hashtable]) {
            # Check if this is a metadata wrapper
            if ($value.ContainsKey('_value')) {
                $result[$key] = $value['_value']
            } else {
                $result[$key] = Remove-SourceMetadata -Config $value
            }
        } else {
            $result[$key] = $value
        }
    }
    return $result
}

# Helper function: Merge two configurations
function Merge-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Base,

        [Parameter(Mandatory = $true)]
        [hashtable]$Overlay
    )

    $result = $Base.Clone()
    foreach ($key in $Overlay.Keys) {
        $overlayValue = $Overlay[$key]
        if ($result.ContainsKey($key) -and $result[$key] -is [hashtable] -and $overlayValue -is [hashtable]) {
            $result[$key] = Merge-Config -Base $result[$key] -Overlay $overlayValue
        } else {
            $result[$key] = $overlayValue
        }
    }
    return $result
}

# Export module members
Export-ModuleMember -Function @(
    'Get-ConfigPath',
    'Find-ProjectRoot',
    'Initialize-ProjectConfigDir',
    'Initialize-CentralConfigDir',
    'Get-ProjectConfig',
    'Get-ProfileConfig',
    'Get-EnvironmentConfig',
    'Save-ProjectConfig',
    'Save-CentralConfig'
)
