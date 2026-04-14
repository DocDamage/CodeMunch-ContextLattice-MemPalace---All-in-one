# Policy Externalization Adapter
# Provides an adapter layer to an external policy engine (OPA-style) with
# in-process fallback when no external engine is available.
# Invariant 3.6: Destructive or agent-invokable operations must pass a policy gate.

Set-StrictMode -Version Latest

#===============================================================================
# Configuration and Constants
#===============================================================================

$script:DefaultAdapterConfig = @{
    EngineUri = $null
    EngineType = "fallback"
    TimeoutSeconds = 5
    FallbackMode = "in-process"
    DefaultDecision = "deny"
}

$script:AdapterInstances = @{}

# Safety levels used for policy decisions
enum PolicySafetyLevel {
    ReadOnly
    Mutating
    Destructive
    Networked
}

#===============================================================================
# Adapter Configuration Functions
#===============================================================================

function New-PolicyAdapter {
    <#
    .SYNOPSIS
        Creates a new policy adapter configuration.
    
    .DESCRIPTION
        Configures an adapter that can target an external OPA-style policy engine
        or fall back to an in-process evaluator when the engine is unavailable.
    
    .PARAMETER EngineUri
        URI of the external policy engine endpoint (e.g., http://localhost:8181/v1/data).
    
    .PARAMETER EngineType
        Type of policy engine. Supported values: "opa", "fallback".
    
    .PARAMETER TimeoutSeconds
        Request timeout for external engine calls. Defaults to 5.
    
    .PARAMETER FallbackMode
        Fallback behavior when the external engine is unreachable:
        "in-process" (default) or "default-decision".
    
    .PARAMETER DefaultDecision
        Default decision when FallbackMode is "default-decision". Defaults to "deny".
    
    .OUTPUTS
        PSCustomObject representing the adapter configuration.
    
    .EXAMPLE
        $adapter = New-PolicyAdapter -EngineUri "http://localhost:8181/v1/data/llmworkflow" -EngineType "opa"
    #>
    [CmdletBinding()]
    param(
        [string]$EngineUri = $null,
        
        [ValidateSet("opa", "fallback")]
        [string]$EngineType = "fallback",
        
        [int]$TimeoutSeconds = 5,
        
        [ValidateSet("in-process", "default-decision")]
        [string]$FallbackMode = "in-process",
        
        [ValidateSet("allow", "deny")]
        [string]$DefaultDecision = "deny"
    )
    
    if ($EngineType -eq "opa" -and [string]::IsNullOrWhiteSpace($EngineUri)) {
        throw "EngineUri is required when EngineType is 'opa'."
    }
    
    $adapterId = [Guid]::NewGuid().ToString("N")
    $adapter = [PSCustomObject]@{
        AdapterId = $adapterId
        EngineUri = $EngineUri
        EngineType = $EngineType
        TimeoutSeconds = $TimeoutSeconds
        FallbackMode = $FallbackMode
        DefaultDecision = $DefaultDecision
        CreatedAt = [DateTime]::UtcNow.ToString("o")
    }
    
    $script:AdapterInstances[$adapterId] = $adapter
    
    Write-Verbose "Created policy adapter '$adapterId' with engine type '$EngineType'."
    return $adapter
}

#===============================================================================
# Policy Decision Functions
#===============================================================================

function Invoke-PolicyDecision {
    <#
    .SYNOPSIS
        Sends input to the policy engine and returns a decision with explanation.
    
    .DESCRIPTION
        Evaluates a policy decision request against the configured engine.
        If the external engine is unavailable, falls back to in-process evaluation.
    
    .PARAMETER Adapter
        Policy adapter returned by New-PolicyAdapter.
    
    .PARAMETER Domain
        Policy domain to evaluate (e.g., "execution_mode", "mcp_exposure").
    
    .PARAMETER InputObject
        Hashtable or PSCustomObject containing the query input.
    
    .OUTPUTS
        PSCustomObject with properties: Decision (allow/deny), Explanation, Engine, Fallback.
    
    .EXAMPLE
        $result = Invoke-PolicyDecision -Adapter $adapter -Domain "execution_mode" -InputObject @{ mode = "ci"; command = "build" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Adapter,
        
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        
        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )
    
    # Normalize input to hashtable for consistent handling
    $normalizedInput = ConvertTo-PolicyInputHashtable -InputObject $InputObject
    $normalizedInput['domain'] = $Domain
    
    # Attempt external engine if configured
    if ($Adapter.EngineType -eq "opa" -and -not [string]::IsNullOrWhiteSpace($Adapter.EngineUri)) {
        try {
            $externalResult = Invoke-ExternalPolicyEngine -Adapter $Adapter -InputObject $normalizedInput
            if ($externalResult) {
                return $externalResult
            }
        }
        catch {
            Write-Verbose "External policy engine call failed: $_"
        }
    }
    
    # Fallback path
    if ($Adapter.FallbackMode -eq "default-decision") {
        return [PSCustomObject]@{
            Decision = $Adapter.DefaultDecision
            Explanation = "External engine unavailable; using default decision '$($Adapter.DefaultDecision)'."
            Engine = $Adapter.EngineType
            Fallback = $true
            Timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
    
    # In-process fallback
    $fallbackResult = Invoke-InProcessPolicyEngine -InputObject $normalizedInput
    $combined = @{}
    $fallbackResult.PSObject.Properties | ForEach-Object { $combined[$_.Name] = $_.Value }
    $combined['Engine'] = $Adapter.EngineType
    $combined['Fallback'] = $true
    return [PSCustomObject]$combined
}

function Test-PolicyDecision {
    <#
    .SYNOPSIS
        Boolean wrapper around Invoke-PolicyDecision.
    
    .DESCRIPTION
        Returns $true if the policy decision is "allow", $false otherwise.
    
    .PARAMETER Adapter
        Policy adapter returned by New-PolicyAdapter.
    
    .PARAMETER Domain
        Policy domain to evaluate.
    
    .PARAMETER InputObject
        Query input object.
    
    .OUTPUTS
        Boolean
    
    .EXAMPLE
        if (Test-PolicyDecision -Adapter $adapter -Domain "execution_mode" -InputObject @{ mode = "ci"; command = "build" }) { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Adapter,
        
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        
        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )
    
    $result = Invoke-PolicyDecision -Adapter $Adapter -Domain $Domain -InputObject $InputObject
    return ($result.Decision -eq "allow")
}

function Get-PolicyExplanation {
    <#
    .SYNOPSIS
        Returns a human-readable explanation for a policy decision.
    
    .DESCRIPTION
        Generates or augments the explanation for a policy decision result,
        making it suitable for operator logs and UI display.
    
    .PARAMETER DecisionResult
        The PSCustomObject returned from Invoke-PolicyDecision.
    
    .PARAMETER IncludeInputSummary
        If specified, includes a brief summary of the evaluated input.
    
    .OUTPUTS
        String containing the human-readable explanation.
    
    .EXAMPLE
        $explanation = Get-PolicyExplanation -DecisionResult $result
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DecisionResult,
        
        [switch]$IncludeInputSummary
    )
    
    $explanation = $DecisionResult.Explanation
    if ([string]::IsNullOrWhiteSpace($explanation)) {
        $explanation = "No explanation available for decision '$($DecisionResult.Decision)'."
    }
    
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add($explanation)
    
    if ($DecisionResult.Fallback) {
        $parts.Add("(evaluated via fallback path)")
    }
    
    if ($IncludeInputSummary -and $DecisionResult.InputSummary) {
        $parts.Add("Input summary: $($DecisionResult.InputSummary)")
    }
    
    return ($parts -join " ")
}

#===============================================================================
# Internal Engine Functions
#===============================================================================

function Invoke-ExternalPolicyEngine {
    <#
    .SYNOPSIS
        Calls an external OPA-style policy engine.
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$Adapter,
        [hashtable]$InputObject
    )
    
    $body = @{ input = $InputObject } | ConvertTo-Json -Depth 10 -Compress
    $uri = $Adapter.EngineUri.TrimEnd('/')
    
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/json" -TimeoutSec $Adapter.TimeoutSeconds -ErrorAction Stop
        
        $decision = if ($response.result -eq $true -or ($response.result -is [bool] -and $response.result)) { "allow" } else { "deny" }
        $explanation = if ($response.result.explanation) { $response.result.explanation } elseif ($response.result.reason) { $response.result.reason } else { "External engine returned decision: $decision" }
        
        return [PSCustomObject]@{
            Decision = $decision
            Explanation = $explanation
            Engine = $Adapter.EngineType
            Fallback = $false
            Timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
    catch {
        Write-Verbose "External engine request failed: $_"
        return $null
    }
}

function Invoke-InProcessPolicyEngine {
    <#
    .SYNOPSIS
        In-process fallback evaluator for policy decisions.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$InputObject
    )
    
    $domain = $InputObject['domain']
    $mode = $InputObject['mode']
    $command = $InputObject['command']
    $safetyLevel = $InputObject['safetyLevel']
    
    switch ($domain) {
        "execution_mode" {
            return Evaluate-ExecutionModePolicy -Mode $mode -Command $command -SafetyLevel $safetyLevel
        }
        "mcp_exposure" {
            return Evaluate-McpExposurePolicy -InputObject $InputObject
        }
        "interpack_transfer" {
            return Evaluate-InterpackTransferPolicy -InputObject $InputObject
        }
        "workspace_boundary" {
            return Evaluate-WorkspaceBoundaryPolicy -InputObject $InputObject
        }
        default {
            return [PSCustomObject]@{
                Decision = "deny"
                Explanation = "Unknown policy domain '$domain'; defaulting to deny."
                Engine = "fallback"
                Fallback = $true
                Timestamp = [DateTime]::UtcNow.ToString("o")
            }
        }
    }
}

function Evaluate-ExecutionModePolicy {
    [CmdletBinding()]
    param(
        [string]$Mode,
        [string]$Command,
        [string]$SafetyLevel
    )
    
    $allowedModes = @("interactive", "ci", "watch", "heal-watch", "scheduled", "mcp-readonly", "mcp-mutating")
    if ($allowedModes -notcontains $Mode) {
        return [PSCustomObject]@{
            Decision = "deny"
            Explanation = "Execution mode '$Mode' is not recognized."
            Timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
    
    # Restrict destructive operations in non-interactive modes
    $nonInteractive = @("ci", "watch", "heal-watch", "scheduled", "mcp-readonly", "mcp-mutating")
    if ($nonInteractive -contains $Mode -and $SafetyLevel -eq "Destructive") {
        return [PSCustomObject]@{
            Decision = "deny"
            Explanation = "Destructive operations are not allowed in '$Mode' mode."
            Timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
    
    # Restrict mutating in readonly modes
    if ($Mode -eq "mcp-readonly" -and $SafetyLevel -eq "Mutating") {
        return [PSCustomObject]@{
            Decision = "deny"
            Explanation = "Mutating operations are not allowed in 'mcp-readonly' mode."
            Timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
    
    return [PSCustomObject]@{
        Decision = "allow"
        Explanation = "Command '$Command' is allowed in '$Mode' mode."
        Timestamp = [DateTime]::UtcNow.ToString("o")
    }
}

function Evaluate-McpExposurePolicy {
    [CmdletBinding()]
    param(
        [hashtable]$InputObject
    )
    
    $toolCategory = $InputObject['toolCategory']
    $requiresReview = $InputObject['requiresReview']
    $workspaceBound = $InputObject['workspaceBound']
    
    if ($toolCategory -eq "mutating" -and $requiresReview -ne $true) {
        return [PSCustomObject]@{
            Decision = "deny"
            Explanation = "Mutating MCP tools require review before exposure."
            Timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
    
    if ($workspaceBound -eq $false) {
        return [PSCustomObject]@{
            Decision = "deny"
            Explanation = "MCP tools must be workspace-bound."
            Timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
    
    return [PSCustomObject]@{
        Decision = "allow"
        Explanation = "MCP tool exposure is allowed under current constraints."
        Timestamp = [DateTime]::UtcNow.ToString("o")
    }
}

function Evaluate-InterpackTransferPolicy {
    [CmdletBinding()]
    param(
        [hashtable]$InputObject
    )
    
    $sourceQuarantine = $InputObject['sourceQuarantine']
    $promoted = $InputObject['promoted']
    $provenanceVerified = $InputObject['provenanceVerified']
    
    if ($sourceQuarantine -eq $true -and $promoted -ne $true) {
        return [PSCustomObject]@{
            Decision = "deny"
            Explanation = "Transfers from quarantined sources require promotion."
            Timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
    
    if ($provenanceVerified -eq $false) {
        return [PSCustomObject]@{
            Decision = "deny"
            Explanation = "Asset provenance must be verified for inter-pack transfers."
            Timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
    
    return [PSCustomObject]@{
        Decision = "allow"
        Explanation = "Inter-pack transfer satisfies source and provenance requirements."
        Timestamp = [DateTime]::UtcNow.ToString("o")
    }
}

function Evaluate-WorkspaceBoundaryPolicy {
    [CmdletBinding()]
    param(
        [hashtable]$InputObject
    )
    
    $visibility = $InputObject['visibility']
    $crossesBoundary = $InputObject['crossesBoundary']
    $allowedDestinations = $InputObject['allowedDestinations']
    
    $validVisibilities = @("private", "local-team", "shared", "public-reference")
    if ($validVisibilities -notcontains $visibility) {
        return [PSCustomObject]@{
            Decision = "deny"
            Explanation = "Visibility '$visibility' is not recognized."
            Timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
    
    if ($crossesBoundary -eq $true) {
        if ($visibility -eq "private") {
            return [PSCustomObject]@{
                Decision = "deny"
                Explanation = "Private assets may not cross workspace boundaries."
                Timestamp = [DateTime]::UtcNow.ToString("o")
            }
        }
        if ($allowedDestinations -is [array] -and $allowedDestinations.Count -eq 0) {
            return [PSCustomObject]@{
                Decision = "deny"
                Explanation = "Cross-boundary operation requires at least one allowed destination."
                Timestamp = [DateTime]::UtcNow.ToString("o")
            }
        }
    }
    
    return [PSCustomObject]@{
        Decision = "allow"
        Explanation = "Workspace boundary constraints are satisfied."
        Timestamp = [DateTime]::UtcNow.ToString("o")
    }
}

#===============================================================================
# Utility Functions
#===============================================================================

function ConvertTo-PolicyInputHashtable {
    [CmdletBinding()]
    param(
        [object]$InputObject
    )
    
    if ($InputObject -is [hashtable]) {
        return $InputObject
    }
    
    if ($InputObject -is [PSCustomObject]) {
        $hash = @{}
        $InputObject.PSObject.Properties | ForEach-Object {
            $hash[$_.Name] = $_.Value
        }
        return $hash
    }
    
    return @{ value = $InputObject }
}

function Get-PolicyAdapter {
    <#
    .SYNOPSIS
        Retrieves a policy adapter by ID.
    
    .PARAMETER AdapterId
        The adapter ID to retrieve.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AdapterId
    )
    
    if ($script:AdapterInstances.ContainsKey($AdapterId)) {
        return $script:AdapterInstances[$AdapterId]
    }
    return $null
}

function Remove-PolicyAdapter {
    <#
    .SYNOPSIS
        Removes a policy adapter by ID.
    
    .PARAMETER AdapterId
        The adapter ID to remove.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AdapterId
    )
    
    if ($script:AdapterInstances.ContainsKey($AdapterId)) {
        $script:AdapterInstances.Remove($AdapterId) | Out-Null
        Write-Verbose "Removed policy adapter '$AdapterId'."
        return $true
    }
    return $false
}

# Export module members when loaded as a module
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'New-PolicyAdapter',
        'Invoke-PolicyDecision',
        'Test-PolicyDecision',
        'Get-PolicyExplanation',
        'Get-PolicyAdapter',
        'Remove-PolicyAdapter'
    ) -Variable @() -Alias @()
}
