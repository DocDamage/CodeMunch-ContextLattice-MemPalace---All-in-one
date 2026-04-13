# MCP Tool Registry Management
# Workstream 7: Retrieval Substrate and MCP Governance

Set-StrictMode -Version Latest

#===============================================================================
# Script-level Variables
#===============================================================================

$script:MCPToolRegistry = $null

$script:ValidSafetyLevels = @('read-only', 'mutating', 'destructive', 'networked')
$script:ValidCapabilities = @('search', 'ingest', 'transform', 'explain', 'diagnose', 'heal', 'governance')
$script:ValidLifecycleStates = @('draft', 'experimental', 'stable', 'deprecated', 'retired')

#===============================================================================
# Registry Functions
#===============================================================================

function New-MCPToolRegistry {
    <#
    .SYNOPSIS
        Creates a new in-memory MCP tool registry.

    .DESCRIPTION
        Initializes an empty, synchronized hashtable that serves as the
        canonical in-memory MCP tool registry.

    .OUTPUTS
        System.Collections.Hashtable. The initialized registry.

    .EXAMPLE
        $registry = New-MCPToolRegistry
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param()

    $script:MCPToolRegistry = [hashtable]::Synchronized(@{})
    return $script:MCPToolRegistry
}

function Register-MCPTool {
    <#
    .SYNOPSIS
        Registers an MCP tool with full metadata in the registry.

    .DESCRIPTION
        Adds or updates a tool entry in the MCP tool registry. Validates
        required metadata fields per the MCP Governance Model.

    .PARAMETER ToolId
        Globally unique tool identifier.

    .PARAMETER OwningPack
        The pack that owns this tool.

    .PARAMETER SafetyLevel
        One of: read-only, mutating, destructive, networked.

    .PARAMETER ExecutionModeRequirements
        Array of allowed execution modes. Defaults to empty (no restriction).

    .PARAMETER IsMutating
        True if the tool changes external state.

    .PARAMETER IsReadOnly
        True if the tool only reads state.

    .PARAMETER ReviewRequired
        True if promotions/changes require human review.

    .PARAMETER DependencyFootprint
        Array of module/package dependencies.

    .PARAMETER TelemetryTags
        Array of telemetry routing tags.

    .PARAMETER Capability
        Primary capability taxonomy bucket.

    .PARAMETER Deprecated
        True if the tool is deprecated.

    .PARAMETER DeprecationNotice
        Human-readable deprecation explanation.

    .PARAMETER ReplacedBy
        Tool ID of the preferred replacement.

    .PARAMETER LifecycleState
        Current lifecycle state. Defaults to 'draft'.

    .PARAMETER Version
        Semantic version of the tool contract. Defaults to '1.0.0'.

    .PARAMETER Registry
        Optional registry hashtable. Uses the script-level registry by default.

    .OUTPUTS
        System.Management.Automation.PSCustomObject. The registered tool metadata.

    .EXAMPLE
        Register-MCPTool -ToolId "search-retrieval" -OwningPack "retrieval" `
            -SafetyLevel "read-only" -Capability "search"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9_-]{1,64}$')]
        [string]$ToolId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OwningPack,

        [Parameter(Mandatory = $true)]
        [ValidateSet('read-only', 'mutating', 'destructive', 'networked')]
        [string]$SafetyLevel,

        [Parameter()]
        [string[]]$ExecutionModeRequirements = @(),

        [Parameter()]
        [bool]$IsMutating = $false,

        [Parameter()]
        [bool]$IsReadOnly = $true,

        [Parameter()]
        [bool]$ReviewRequired = $false,

        [Parameter()]
        [string[]]$DependencyFootprint = @(),

        [Parameter()]
        [string[]]$TelemetryTags = @(),

        [Parameter(Mandatory = $true)]
        [ValidateSet('search', 'ingest', 'transform', 'explain', 'diagnose', 'heal', 'governance')]
        [string]$Capability,

        [Parameter()]
        [bool]$Deprecated = $false,

        [Parameter()]
        [string]$DeprecationNotice = "",

        [Parameter()]
        [string]$ReplacedBy = "",

        [Parameter()]
        [ValidateSet('draft', 'experimental', 'stable', 'deprecated', 'retired')]
        [string]$LifecycleState = 'draft',

        [Parameter()]
        [string]$Version = '1.0.0',

        [Parameter()]
        [System.Collections.Hashtable]$Registry = $script:MCPToolRegistry
    )

    process {
        if (-not $Registry) {
            $Registry = New-MCPToolRegistry
        }

        if ($IsMutating -and $SafetyLevel -eq 'read-only') {
            throw "SafetyLevel cannot be 'read-only' when IsMutating is true."
        }

        $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        $existing = $Registry[$ToolId]
        $registeredAt = if ($existing -and $existing.registeredAt) { $existing.registeredAt } else { $now }

        $tool = [ordered]@{
            toolId = $ToolId
            owningPack = $OwningPack
            safetyLevel = $SafetyLevel
            executionModeRequirements = @($ExecutionModeRequirements)
            isMutating = $IsMutating
            isReadOnly = $IsReadOnly
            reviewRequired = $ReviewRequired
            dependencyFootprint = @($DependencyFootprint)
            telemetryTags = @($TelemetryTags)
            capability = $Capability
            deprecated = $Deprecated
            deprecationNotice = $DeprecationNotice
            replacedBy = $ReplacedBy
            lifecycleState = $LifecycleState
            registeredAt = $registeredAt
            updatedAt = $now
            version = $Version
        }

        $toolObject = [pscustomobject]$tool
        $Registry[$ToolId] = $toolObject

        Write-Verbose "[MCPToolRegistry] Registered tool '$ToolId' (pack: $OwningPack, state: $LifecycleState)"
        return $toolObject
    }
}

function Get-MCPTool {
    <#
    .SYNOPSIS
        Retrieves metadata for a single MCP tool.

    .PARAMETER ToolId
        The tool identifier to look up.

    .PARAMETER Registry
        Optional registry hashtable. Uses the script-level registry by default.

    .OUTPUTS
        System.Management.Automation.PSCustomObject or $null.

    .EXAMPLE
        $tool = Get-MCPTool -ToolId "search-retrieval"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolId,

        [Parameter()]
        [System.Collections.Hashtable]$Registry = $script:MCPToolRegistry
    )

    if (-not $Registry) {
        return $null
    }

    $result = $Registry[$ToolId]
    if ($result) {
        return $result
    }

    return $null
}

function Find-MCPTools {
    <#
    .SYNOPSIS
        Discovers MCP tools by pack, capability, or safety level.

    .DESCRIPTION
        Returns all tools matching the specified filters. If no filters are
        provided, returns all tools in the registry.

    .PARAMETER OwningPack
        Filter by owning pack.

    .PARAMETER Capability
        Filter by primary capability.

    .PARAMETER SafetyLevel
        Filter by safety level.

    .PARAMETER IncludeDeprecated
        If specified, includes deprecated and retired tools.

    .PARAMETER Registry
        Optional registry hashtable. Uses the script-level registry by default.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]. Matching tools.

    .EXAMPLE
        Find-MCPTools -Capability "search" -SafetyLevel "read-only"
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [string]$OwningPack = "",

        [Parameter()]
        [string]$Capability = "",

        [Parameter()]
        [string]$SafetyLevel = "",

        [Parameter()]
        [switch]$IncludeDeprecated,

        [Parameter()]
        [System.Collections.Hashtable]$Registry = $script:MCPToolRegistry
    )

    if (-not $Registry) {
        return @()
    }

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($key in $Registry.Keys) {
        $tool = $Registry[$key]

        if (-not $IncludeDeprecated -and ($tool.deprecated -or $tool.lifecycleState -eq 'retired')) {
            continue
        }

        if ($OwningPack -and $tool.owningPack -ne $OwningPack) {
            continue
        }

        if ($Capability -and $tool.capability -ne $Capability) {
            continue
        }

        if ($SafetyLevel -and $tool.safetyLevel -ne $SafetyLevel) {
            continue
        }

        $results.Add($tool)
    }

    return $results.ToArray()
}

function Export-MCPToolRegistry {
    <#
    .SYNOPSIS
        Exports the MCP tool registry to a JSON file.

    .PARAMETER Path
        Destination file path.

    .PARAMETER Registry
        Optional registry hashtable. Uses the script-level registry by default.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with export result.

    .EXAMPLE
        Export-MCPToolRegistry -Path "./mcp-tools.json"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [System.Collections.Hashtable]$Registry = $script:MCPToolRegistry
    )

    if (-not $Registry) {
        throw "Registry is not initialized. Call New-MCPToolRegistry first."
    }

    $payload = [ordered]@{
        schemaVersion = 1
        exportedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        tools = @($Registry.Values | ForEach-Object { $_ })
    }

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }

    $payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8

    return [pscustomobject]@{
        Success = $true
        Path = $Path
        ToolCount = $Registry.Count
    }
}

function Import-MCPToolRegistry {
    <#
    .SYNOPSIS
        Imports an MCP tool registry from a JSON file.

    .DESCRIPTION
        Hydrates the in-memory registry from a JSON file produced by
        Export-MCPToolRegistry. Merges with existing entries by default.

    .PARAMETER Path
        Source file path.

    .PARAMETER Merge
        If true, merges imported tools with the existing registry.
        If false, replaces the existing registry. Default is true.

    .PARAMETER Registry
        Optional registry hashtable. Uses the script-level registry by default.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with import result.

    .EXAMPLE
        Import-MCPToolRegistry -Path "./mcp-tools.json"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [bool]$Merge = $true,

        [Parameter()]
        [System.Collections.Hashtable]$Registry = $script:MCPToolRegistry
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Registry file not found: $Path"
    }

    $content = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if (-not $content.tools) {
        throw "Invalid registry file: missing 'tools' array."
    }

    if (-not $Registry -or -not $Merge) {
        $Registry = New-MCPToolRegistry
    }

    $importedCount = 0
    foreach ($tool in $content.tools) {
        $toolId = $tool.toolId
        if (-not $toolId) { continue }

        $Registry[$toolId] = $tool
        $importedCount++
    }

    $script:MCPToolRegistry = $Registry

    return [pscustomobject]@{
        Success = $true
        Path = $Path
        ImportedCount = $importedCount
        TotalCount = $Registry.Count
    }
}

#===============================================================================
# Export Module Members
#===============================================================================

if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'New-MCPToolRegistry',
        'Register-MCPTool',
        'Get-MCPTool',
        'Find-MCPTools',
        'Export-MCPToolRegistry',
        'Import-MCPToolRegistry'
    )
}
