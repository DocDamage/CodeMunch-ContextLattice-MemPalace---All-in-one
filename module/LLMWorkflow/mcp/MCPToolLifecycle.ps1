# MCP Tool Lifecycle Management
# Workstream 7: Retrieval Substrate and MCP Governance

Set-StrictMode -Version Latest

#===============================================================================
# Script-level Variables
#===============================================================================

$script:ValidLifecycleStates = @('draft', 'experimental', 'stable', 'deprecated', 'retired')

# Transition matrix: source state -> array of allowed target states
$script:AllowedTransitions = @{
    'draft'        = @('experimental', 'retired')
    'experimental' = @('stable', 'retired')
    'stable'       = @('deprecated', 'retired')
    'deprecated'   = @('retired', 'stable')
    'retired'      = @()  # terminal state
}

#===============================================================================
# Lifecycle Functions
#===============================================================================

function Set-MCPToolLifecycleState {
    <#
    .SYNOPSIS
        Transitions an MCP tool to a new lifecycle state.

    .DESCRIPTION
        Updates the lifecycleState of a registered tool after validating
        that the transition is allowed. Updates the tool's updatedAt
        timestamp and sets deprecation flags when entering deprecated state.

    .PARAMETER ToolId
        The tool identifier.

    .PARAMETER State
        Target lifecycle state: draft, experimental, stable, deprecated, retired.

    .PARAMETER Force
        If specified, bypasses transition validation.

    .PARAMETER DeprecationNotice
        Required when transitioning to deprecated state.

    .PARAMETER ReplacedBy
        Optional replacement tool ID.

    .PARAMETER Registry
        Optional registry hashtable. Uses the script-level registry by default.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with transition result.

    .EXAMPLE
        Set-MCPToolLifecycleState -ToolId "search-retrieval" -State "stable"
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('draft', 'experimental', 'stable', 'deprecated', 'retired')]
        [string]$State,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [string]$DeprecationNotice = "",

        [Parameter()]
        [string]$ReplacedBy = "",

        [Parameter()]
        [System.Collections.Hashtable]$Registry = $null
    )

    process {
        if (-not $Registry) {
            # Attempt to use the module-level registry if available
            if ($script:MCPToolRegistry) {
                $Registry = $script:MCPToolRegistry
            }
            else {
                throw "Registry is not available. Ensure MCPToolRegistry.ps1 is loaded."
            }
        }

        $tool = $Registry[$ToolId]
        if (-not $tool) {
            throw "Tool not found in registry: $ToolId"
        }

        $currentState = $tool.lifecycleState

        if (-not $Force) {
            $validation = Test-MCPToolLifecycleTransition -FromState $currentState -ToState $State
            if (-not $validation.IsValid) {
                throw "Invalid lifecycle transition from '$currentState' to '$State': $($validation.Reason)"
            }
        }

        if ($PSCmdlet.ShouldProcess("Tool '$ToolId'", "Transition lifecycle state from '$currentState' to '$State'")) {
            $tool.lifecycleState = $State
            $tool.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)

            if ($State -eq 'deprecated') {
                $tool.deprecated = $true
                if ($DeprecationNotice) {
                    $tool.deprecationNotice = $DeprecationNotice
                }
                if ($ReplacedBy) {
                    $tool.replacedBy = $ReplacedBy
                }
            }
            elseif ($State -eq 'stable') {
                $tool.deprecated = $false
                if ($currentState -eq 'deprecated') {
                    # Reversing deprecation
                    $tool.deprecationNotice = ""
                    $tool.replacedBy = ""
                }
            }
            elseif ($State -eq 'retired') {
                $tool.deprecated = $true
            }

            $Registry[$ToolId] = $tool

            Write-Verbose "[MCPToolLifecycle] Transitioned '$ToolId' from '$currentState' to '$State'"

            return [pscustomobject]@{
                Success = $true
                ToolId = $ToolId
                PreviousState = $currentState
                NewState = $State
                UpdatedAt = $tool.updatedAt
            }
        }

        return [pscustomobject]@{
            Success = $false
            ToolId = $ToolId
            PreviousState = $currentState
            NewState = $State
        }
    }
}

function Test-MCPToolLifecycleTransition {
    <#
    .SYNOPSIS
        Validates whether a lifecycle state transition is allowed.

    .PARAMETER FromState
        Source lifecycle state.

    .PARAMETER ToState
        Target lifecycle state.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with IsValid and Reason.

    .EXAMPLE
        Test-MCPToolLifecycleTransition -FromState "stable" -ToState "deprecated"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('draft', 'experimental', 'stable', 'deprecated', 'retired')]
        [string]$FromState,

        [Parameter(Mandatory = $true)]
        [ValidateSet('draft', 'experimental', 'stable', 'deprecated', 'retired')]
        [string]$ToState
    )

    if ($FromState -eq $ToState) {
        return [pscustomobject]@{
            IsValid = $true
            Reason = "No transition needed."
        }
    }

    $allowed = $script:AllowedTransitions[$FromState]
    if ($allowed -contains $ToState) {
        return [pscustomobject]@{
            IsValid = $true
            Reason = "Transition allowed."
        }
    }

    return [pscustomobject]@{
        IsValid = $false
        Reason = "Transition from '$FromState' to '$ToState' is not allowed. Allowed targets: $($allowed -join ', ')"
    }
}

function Get-MCPToolDeprecationNotice {
    <#
    .SYNOPSIS
        Generates deprecation information for a tool.

    .DESCRIPTION
        Returns a structured deprecation notice if the tool is deprecated
        or in the process of being deprecated. Returns null for active tools.

    .PARAMETER ToolId
        The tool identifier.

    .PARAMETER Registry
        Optional registry hashtable. Uses the script-level registry by default.

    .OUTPUTS
        System.Management.Automation.PSCustomObject or $null.

    .EXAMPLE
        Get-MCPToolDeprecationNotice -ToolId "old-tool"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolId,

        [Parameter()]
        [System.Collections.Hashtable]$Registry = $null
    )

    if (-not $Registry) {
        if ($script:MCPToolRegistry) {
            $Registry = $script:MCPToolRegistry
        }
        else {
            return $null
        }
    }

    $tool = $Registry[$ToolId]
    if (-not $tool) {
        return $null
    }

    if (-not $tool.deprecated -and $tool.lifecycleState -ne 'deprecated' -and $tool.lifecycleState -ne 'retired') {
        return $null
    }

    $notice = [ordered]@{
        toolId = $ToolId
        deprecated = $tool.deprecated
        lifecycleState = $tool.lifecycleState
        message = if ($tool.deprecationNotice) { $tool.deprecationNotice } else { "Tool '$ToolId' is $($tool.lifecycleState)." }
        replacedBy = $tool.replacedBy
        updatedAt = $tool.updatedAt
    }

    return [pscustomobject]$notice
}

function Invoke-MCPToolRegistrySync {
    <#
    .SYNOPSIS
        Syncs the MCP tool registry with canonical sources.

    .DESCRIPTION
        Reconciles the in-memory registry with a persisted JSON file.
        Optionally removes retired tools older than the audit retention
        window and writes the merged registry back to disk.

    .PARAMETER Path
        Path to the canonical registry JSON file.

    .PARAMETER RetentionDays
        Number of days to retain retired tools before removal. Default: 180.

    .PARAMETER RemoveExpired
        If specified, removes retired tools older than RetentionDays.

    .PARAMETER Registry
        Optional registry hashtable. Uses the script-level registry by default.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with sync result.

    .EXAMPLE
        Invoke-MCPToolRegistrySync -Path "./mcp-tools.json" -RemoveExpired
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [int]$RetentionDays = 180,

        [Parameter()]
        [switch]$RemoveExpired,

        [Parameter()]
        [System.Collections.Hashtable]$Registry = $null
    )

    if (-not $Registry) {
        if ($script:MCPToolRegistry) {
            $Registry = $script:MCPToolRegistry
        }
        else {
            $Registry = @{}
        }
    }

    $removedCount = 0
    $mergedCount = 0

    # Load persisted registry if it exists
    if (Test-Path -LiteralPath $Path) {
        try {
            $persisted = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
            if ($persisted.tools) {
                foreach ($tool in $persisted.tools) {
                    $toolId = $tool.toolId
                    if (-not $toolId) { continue }

                    if (-not $Registry.ContainsKey($toolId)) {
                        $Registry[$toolId] = $tool
                        $mergedCount++
                    }
                }
            }
        }
        catch {
            Write-Warning "[MCPToolLifecycle] Failed to load persisted registry from '$Path': $_"
        }
    }

    # Remove expired retired tools
    if ($RemoveExpired) {
        $cutoff = [DateTime]::UtcNow.AddDays(-$RetentionDays)
        $keysToRemove = [System.Collections.Generic.List[string]]::new()

        foreach ($key in $Registry.Keys) {
            $tool = $Registry[$key]
            if ($tool.lifecycleState -eq 'retired' -and $tool.updatedAt) {
                try {
                    $updated = [DateTime]::Parse($tool.updatedAt)
                    if ($updated -lt $cutoff) {
                        $keysToRemove.Add($key)
                    }
                }
                catch {
                    Write-Verbose "[MCPToolLifecycle] Could not parse updatedAt for '$key'; skipping expiration check."
                }
            }
        }

        foreach ($key in $keysToRemove) {
            $null = $Registry.Remove($key)
            $removedCount++
        }
    }

    # Write back
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

    $script:MCPToolRegistry = $Registry

    return [pscustomobject]@{
        Success = $true
        Path = $Path
        MergedCount = $mergedCount
        RemovedCount = $removedCount
        TotalCount = $Registry.Count
    }
}

#===============================================================================
# Export Module Members
#===============================================================================

if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'Set-MCPToolLifecycleState',
        'Test-MCPToolLifecycleTransition',
        'Get-MCPToolDeprecationNotice',
        'Invoke-MCPToolRegistrySync'
    )
}
