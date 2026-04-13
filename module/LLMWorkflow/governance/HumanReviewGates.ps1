#requires -Version 5.1
<#
.SYNOPSIS
    Human Review Gates module for LLM Workflow platform governance.

.DESCRIPTION
    Implements human review gate functionality as specified in the Canonical Architecture
    Section 10.3. Provides automated detection of changes requiring human review,
    review request management, and policy-based enforcement.

    Review triggers include:
    - Large source deltas
    - Parser major version jumps
    - Trust tier changes
    - Visibility boundary changes
    - Eval regressions with caveats
    - New low-confidence extraction modes
    
    Gate Types:
    - Destructive operations (delete, overwrite)
    - Network operations (external API calls)
    - High-value operations (pack promotion)
    - Cross-pack mutations (inter-pack pipelines)
    - First-time operations (new sources)
    - Suspicious patterns (secret detection)

    Requirements from Section 10.3:
    - Review BEFORE locks acquired
    - Review BEFORE destructive operations
    - Persistent review log with run ID
    - Timeout and escalation support

.NOTES
    File: HumanReviewGates.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Compatible with: PowerShell 5.1+

.EXAMPLE
    # Check if human review is required for a pack promotion
    $result = Test-HumanReviewRequired -Operation "pack-promote" -ChangeSet $changes -Policy $policy
    if ($result.Required) { New-ReviewGateRequest @result.RequestParams }

.EXAMPLE
    # Submit a review decision
    Submit-ReviewDecision -RequestId "review-xxxxx" -Reviewer "alice" -Decision "approved" -Comments "Looks good"

.EXAMPLE
    # Quick gate check with auto-approval
    $gate = Invoke-ReviewGate -OperationType "destructive" -Context $context -AutoApproveIfClean
    if (-not $gate.Approved) { exit 1 }
#>

Set-StrictMode -Version Latest

#===============================================================================
# Configuration and Constants
#===============================================================================

$script:ReviewStateFileName = "review-gates.json"
$script:ReviewLogFileName = "review-log.jsonl"
$script:ReviewStateSchemaVersion = 1
$script:ReviewStateSchemaName = "human-review-gates"

# Gate operation types (Section 10.3)
$script:GateOperationTypes = @{
    DESTRUCTIVE = 'destructive'       # delete, overwrite, prune
    NETWORK = 'network'               # external API calls
    HIGH_VALUE = 'high-value'         # pack promotion, prod deploy
    CROSS_PACK = 'cross-pack'         # inter-pack mutations
    FIRST_TIME = 'first-time'         # new sources, first run
    SUSPICIOUS = 'suspicious'         # secret detection, policy violations
}

# Default review policies by operation type
$script:DefaultReviewPolicies = @{
    "pack-promotion" = @{
        name = "Pack Promotion Review Policy"
        description = "Reviews required for pack promotion operations"
        operationType = 'high-value'
        triggers = @{
            largeSourceDelta = @{ enabled = $true; thresholdPercent = 30 }
            majorVersionJump = @{ enabled = $true }
            trustTierChange = @{ enabled = $true }
            evalRegression = @{ enabled = $true }
        }
        conditions = @{
            minApprovers = 2
            requireOwnerApproval = $true
            autoExpireHours = 72
        }
        defaultReviewers = @()
    }
    "source-ingestion" = @{
        name = "Source Ingestion Review Policy"
        description = "Reviews required for new source ingestion"
        operationType = 'first-time'
        triggers = @{
            newSource = @{ enabled = $true }
            trustTierChange = @{ enabled = $true }
            lowConfidenceExtraction = @{ enabled = $true }
        }
        conditions = @{
            minApprovers = 1
            requireOwnerApproval = $false
            autoExpireHours = 48
        }
        defaultReviewers = @()
    }
    "parser-upgrade" = @{
        name = "Parser Upgrade Review Policy"
        description = "Reviews required for parser version changes"
        operationType = 'high-value'
        triggers = @{
            majorVersionJump = @{ enabled = $true }
            extractionModeChange = @{ enabled = $true }
            parserVersionChanged = @{ enabled = $true }
        }
        conditions = @{
            minApprovers = 2
            requireOwnerApproval = $true
            autoExpireHours = 72
        }
        defaultReviewers = @()
    }
    "visibility-change" = @{
        name = "Visibility Change Review Policy"
        description = "Reviews required for visibility boundary changes"
        operationType = 'high-value'
        triggers = @{
            visibilityBoundaryChange = @{ enabled = $true }
            exportPermissionChange = @{ enabled = $true }
        }
        conditions = @{
            minApprovers = 2
            requireOwnerApproval = $true
            autoExpireHours = 48
        }
        defaultReviewers = @()
    }
    "destructive-operation" = @{
        name = "Destructive Operation Review Policy"
        description = "Reviews required for destructive operations (delete, overwrite, prune)"
        operationType = 'destructive'
        triggers = @{
            fileDelete = @{ enabled = $true }
            dataOverwrite = @{ enabled = $true }
            packPrune = @{ enabled = $true }
            stateReset = @{ enabled = $true }
        }
        conditions = @{
            minApprovers = 2
            requireOwnerApproval = $true
            autoExpireHours = 24
            requireExplicitConfirmation = $true
        }
        defaultReviewers = @()
    }
    "network-operation" = @{
        name = "Network Operation Review Policy"
        description = "Reviews required for external API calls and network operations"
        operationType = 'network'
        triggers = @{
            externalAPICall = @{ enabled = $true }
            dataExport = @{ enabled = $true }
            thirdPartyUpload = @{ enabled = $true }
        }
        conditions = @{
            minApprovers = 1
            requireOwnerApproval = $false
            autoExpireHours = 24
        }
        defaultReviewers = @()
    }
    "cross-pack-mutation" = @{
        name = "Cross-Pack Mutation Review Policy"
        description = "Reviews required for inter-pack pipeline operations"
        operationType = 'cross-pack'
        triggers = @{
            crossPackDataTransfer = @{ enabled = $true }
            packDependencyChange = @{ enabled = $true }
            sharedStateMutation = @{ enabled = $true }
        }
        conditions = @{
            minApprovers = 2
            requireOwnerApproval = $true
            autoExpireHours = 72
        }
        defaultReviewers = @()
    }
    "suspicious-pattern" = @{
        name = "Suspicious Pattern Review Policy"
        description = "Reviews triggered by secret detection or policy violations"
        operationType = 'suspicious'
        triggers = @{
            secretDetected = @{ enabled = $true }
            policyViolation = @{ enabled = $true }
            unusualAccessPattern = @{ enabled = $true }
        }
        conditions = @{
            minApprovers = 2
            requireOwnerApproval = $true
            autoExpireHours = 4
            immediateEscalation = $true
        }
        defaultReviewers = @()
    }
}

# Decision types
$script:ValidDecisions = @('approved', 'rejected', 'needs-work')

# Request status values
$script:ValidStatuses = @('pending', 'approved', 'rejected', 'needs-work', 'expired', 'escalated')

#===============================================================================
# Review State Management
#===============================================================================

function Get-ReviewStatePath {
    <#
    .SYNOPSIS
        Gets the path to the review gates state file.
    
    .PARAMETER ProjectRoot
        The project root directory. Defaults to current directory.
    
    .OUTPUTS
        System.String. The full path to the review state file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ProjectRoot = "."
    )
    
    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) {
        $resolvedRoot = $ProjectRoot
    }
    
    $stateDir = Join-Path $resolvedRoot ".llm-workflow\state"
    
    if (-not (Test-Path -LiteralPath $stateDir)) {
        try {
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        }
        catch {
            throw "Failed to create state directory: $stateDir. Error: $_"
        }
    }
    
    return Join-Path $stateDir $script:ReviewStateFileName
}

function Get-ReviewLogPath {
    <#
    .SYNOPSIS
        Gets the path to the review log file (JSON Lines format).
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        System.String. The full path to the review log file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ProjectRoot = "."
    )
    
    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) {
        $resolvedRoot = $ProjectRoot
    }
    
    $logsDir = Join-Path $resolvedRoot ".llm-workflow\logs"
    
    if (-not (Test-Path -LiteralPath $logsDir)) {
        try {
            New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
        }
        catch {
            throw "Failed to create logs directory: $logsDir. Error: $_"
        }
    }
    
    return Join-Path $logsDir $script:ReviewLogFileName
}

function Get-ReviewState {
    <#
    .SYNOPSIS
        Loads the review gates state from file.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        Hashtable. The review state data.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$ProjectRoot = "."
    )
    
    $statePath = Get-ReviewStatePath -ProjectRoot $ProjectRoot
    
    if (-not (Test-Path -LiteralPath $statePath)) {
        # Initialize empty state
        return @{
            schemaVersion = $script:ReviewStateSchemaVersion
            schemaName = $script:ReviewStateSchemaName
            requests = @{}
            policies = @{}
            stats = @{
                totalRequests = 0
                approvedCount = 0
                rejectedCount = 0
                pendingCount = 0
                expiredCount = 0
            }
            lastUpdated = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
    }
    
    try {
        $content = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8
        
        # Handle empty file
        if ([string]::IsNullOrWhiteSpace($content)) {
            throw "State file is empty"
        }
        
        $jsonObj = $content | ConvertFrom-Json
        
        # Handle null result from ConvertFrom-Json
        if ($null -eq $jsonObj) {
            throw "Failed to parse state file"
        }
        
        # Convert PSCustomObject to Hashtable (PowerShell 5.1 compatible)
        $state = ConvertTo-Hashtable -InputObject $jsonObj
        
        # Ensure required structure exists
        if (-not $state -or -not $state.ContainsKey('requests')) { $state = @{}; $state['requests'] = @{} }
        if (-not $state.ContainsKey('policies')) { $state['policies'] = @{} }
        if (-not $state.ContainsKey('stats')) { 
            $state['stats'] = @{
                totalRequests = 0
                approvedCount = 0
                rejectedCount = 0
                pendingCount = 0
                expiredCount = 0
            }
        }
        if (-not $state.ContainsKey('schemaName')) {
            $state['schemaName'] = $script:ReviewStateSchemaName
        }
        
        return $state
    }
    catch {
        Write-Warning "Failed to load review state: $_. Initializing new state."
        return @{
            schemaVersion = $script:ReviewStateSchemaVersion
            schemaName = $script:ReviewStateSchemaName
            requests = @{}
            policies = @{}
            stats = @{
                totalRequests = 0
                approvedCount = 0
                rejectedCount = 0
                pendingCount = 0
                expiredCount = 0
            }
            lastUpdated = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
    }
}

function Save-ReviewState {
    <#
    .SYNOPSIS
        Saves the review gates state to file atomically.
    
    .PARAMETER State
        The state data to save.
    
    .PARAMETER ProjectRoot
        The project root directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        
        [string]$ProjectRoot = "."
    )
    
    $statePath = Get-ReviewStatePath -ProjectRoot $ProjectRoot
    $State['lastUpdated'] = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    try {
        # Create backup if file exists
        if (Test-Path -LiteralPath $statePath) {
            $backupTimestamp = [DateTime]::Now.ToString("yyyyMMddHHmmss")
            $backupPath = "$statePath.backup.$backupTimestamp"
            Copy-Item -LiteralPath $statePath -Destination $backupPath -Force -ErrorAction SilentlyContinue
        }
        
        # Atomic write
        $tempPath = "$statePath.tmp.$PID.$([Guid]::NewGuid().ToString('N'))"
        $json = $State | ConvertTo-Json -Depth 20 -Compress:$false
        [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.Encoding]::UTF8)
        
        # Atomic rename (PowerShell 5.1 compatible)
        if (Test-Path -LiteralPath $statePath) {
            Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        }
        Move-Item -LiteralPath $tempPath -Destination $statePath -Force
        
        return
    }
    catch {
        # Clean up temp file
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw "Failed to save review state: $_"
    }
}

function Write-ReviewLogEntry {
    <#
    .SYNOPSIS
        Writes an entry to the review log (JSON Lines format).
    
    .DESCRIPTION
        Persists review events to a JSON Lines log file as per Section 10.3
        requirement for persistent review log with run ID.
    
    .PARAMETER Entry
        The log entry to write.
    
    .PARAMETER ProjectRoot
        The project root directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry,
        
        [string]$ProjectRoot = "."
    )
    
    try {
        $logPath = Get-ReviewLogPath -ProjectRoot $ProjectRoot
        
        # Add standard fields
        $Entry['timestamp'] = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        if (-not $Entry.ContainsKey('runId')) {
            $Entry['runId'] = Get-CurrentRunId -ErrorAction SilentlyContinue
        }
        
        # Convert to JSON line
        $jsonLine = $Entry | ConvertTo-Json -Compress -Depth 5
        
        # Append to log file
        $jsonLine | Out-File -FilePath $logPath -Encoding UTF8 -Append
    }
    catch {
        Write-Warning "Failed to write review log entry: $_"
    }
}

function Update-ReviewRequest {
    <#
    .SYNOPSIS
        Updates a specific review request in the state.
    
    .PARAMETER RequestId
        The review request ID.
    
    .PARAMETER Updates
        Hashtable of updates to apply.
    
    .PARAMETER ProjectRoot
        The project root directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestId,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Updates,
        
        [string]$ProjectRoot = "."
    )
    
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    
    if (-not $state.requests.ContainsKey($RequestId)) {
        throw "Review request not found: $RequestId"
    }
    
    $request = $state.requests[$RequestId]
    
    # Apply updates
    foreach ($key in $Updates.Keys) {
        $request[$key] = $Updates[$key]
    }
    
    $request['updatedAt'] = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    Save-ReviewState -State $state -ProjectRoot $ProjectRoot
    return $request
}

#===============================================================================
# Helper Functions
#===============================================================================

function ConvertTo-Hashtable {
    <#
    .SYNOPSIS
        Recursively converts a PSCustomObject to a Hashtable.
    
    .DESCRIPTION
        PowerShell 5.1 compatible conversion of JSON objects to hashtables.
    
    .PARAMETER InputObject
        The object to convert.
    
    .OUTPUTS
        Hashtable representation of the input object.
    #>
    param($InputObject)
    
    if ($null -eq $InputObject) {
        return $null
    }
    
    if ($InputObject -is [Array] -or $InputObject -is [System.Collections.ArrayList]) {
        $array = @()
        foreach ($item in $InputObject) {
            $converted = ConvertTo-Hashtable -InputObject $item
            $array += $converted
        }
        return $array
    }
    
    if ($InputObject -is [PSObject]) {
        $hash = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $value = ConvertTo-Hashtable -InputObject $property.Value
            $hash[$property.Name] = $value
        }
        return $hash
    }
    
    return $InputObject
}

function Get-PropertyValue {
    <#
    .SYNOPSIS
        Safely gets a property value from an object (hashtable or PSCustomObject).
    
    .DESCRIPTION
        PowerShell 5.1 compatible property accessor that works with both
        hashtables and PSCustomObjects.
    
    .PARAMETER Object
        The object to get the property from.
    
    .PARAMETER PropertyName
        The name of the property.
    
    .OUTPUTS
        The property value, or null if not found.
    #>
    param($Object, $PropertyName)
    
    if ($null -eq $Object) {
        return $null
    }
    
    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($PropertyName)) {
            return $Object[$PropertyName]
        }
    }
    elseif ($Object.PSObject -and $Object.PSObject.Properties[$PropertyName]) {
        return $Object.PSObject.Properties[$PropertyName].Value
    }
    
    return $null
}

#===============================================================================
# Core Review Functions (22 functions as specified)
#===============================================================================

function Test-HumanReviewRequired {
    <#
    .SYNOPSIS
        Checks if human review is required for a given operation and change set.
    
    .DESCRIPTION
        Evaluates the change set against the review policy to determine if
        human review is required. Returns detailed information about triggers
        and recommended reviewers.
    
    .PARAMETER Operation
        The operation type: 'pack-promote', 'source-update', 'parser-upgrade', etc.
    
    .PARAMETER ChangeSet
        Hashtable describing what changed (packId, versions, deltas, etc.)
    
    .PARAMETER Policy
        Review policy configuration. Uses default if not specified.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject with Required (bool), Triggers (array), Reviewers (array), RequestParams (hashtable)
    
    .EXAMPLE
        $result = Test-HumanReviewRequired -Operation "pack-promote" -ChangeSet $changes
        if ($result.Required) { Write-Host "Review required due to: $($result.Triggers -join ', ')" }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$ChangeSet,
        
        [hashtable]$Policy = $null,
        
        [string]$ProjectRoot = "."
    )
    
    # Normalize operation name
    $normalizedOp = $Operation.ToLowerInvariant() -replace '-', '-'
    
    # Get policy if not provided
    if ($null -eq $Policy) {
        $state = Get-ReviewState -ProjectRoot $ProjectRoot
        if ($state.policies.ContainsKey($normalizedOp)) {
            $Policy = $state.policies[$normalizedOp]
        }
        elseif ($script:DefaultReviewPolicies.ContainsKey($normalizedOp)) {
            $Policy = $script:DefaultReviewPolicies[$normalizedOp]
        }
        else {
            # No policy found - use permissive defaults
            return New-Object -TypeName PSObject -Property @{
                Required = $false
                Triggers = @()
                Reviewers = @()
                RequestParams = @{}
                Reason = "No review policy defined for operation: $Operation"
            }
        }
    }
    
    $triggers = [System.Collections.Generic.List[string]]::new()
    
    # Evaluate each trigger condition
    if ($Policy.triggers.ContainsKey('largeSourceDelta') -and $Policy.triggers.largeSourceDelta.enabled) {
        $threshold = $Policy.triggers.largeSourceDelta.thresholdPercent
        if (Test-LargeSourceDelta -ChangeSet $ChangeSet -ThresholdPercent $threshold) {
            $triggers.Add("large-source-delta")
        }
    }
    
    if ($Policy.triggers.ContainsKey('majorVersionJump') -and $Policy.triggers.majorVersionJump.enabled) {
        if ($ChangeSet.ContainsKey('oldVersion') -and $ChangeSet.ContainsKey('newVersion')) {
            if (Test-MajorVersionJump -OldVersion $ChangeSet.oldVersion -NewVersion $ChangeSet.newVersion) {
                $triggers.Add("major-version-jump")
            }
        }
    }
    
    if ($Policy.triggers.ContainsKey('trustTierChange') -and $Policy.triggers.trustTierChange.enabled) {
        if (Test-TrustTierChange -ChangeSet $ChangeSet) {
            $triggers.Add("trust-tier-change")
        }
    }
    
    if ($Policy.triggers.ContainsKey('visibilityBoundaryChange') -and $Policy.triggers.visibilityBoundaryChange.enabled) {
        if (Test-VisibilityBoundaryChange -ChangeSet $ChangeSet) {
            $triggers.Add("visibility-boundary-change")
        }
    }
    
    if ($Policy.triggers.ContainsKey('evalRegression') -and $Policy.triggers.evalRegression.enabled) {
        if ($ChangeSet.ContainsKey('evalResults') -and (Test-EvalRegression -EvalResults $ChangeSet.evalResults)) {
            $triggers.Add("eval-regression")
        }
    }
    
    if ($Policy.triggers.ContainsKey('lowConfidenceExtraction') -and $Policy.triggers.lowConfidenceExtraction.enabled) {
        if ($ChangeSet.ContainsKey('extractionConfidence') -and $ChangeSet.extractionConfidence -lt 0.7) {
            $triggers.Add("low-confidence-extraction")
        }
    }
    
    if ($Policy.triggers.ContainsKey('newSource') -and $Policy.triggers.newSource.enabled) {
        if ($ChangeSet.ContainsKey('isNewSource') -and $ChangeSet.isNewSource) {
            $triggers.Add("new-source")
        }
    }
    
    if ($Policy.triggers.ContainsKey('extractionModeChange') -and $Policy.triggers.extractionModeChange.enabled) {
        if ($ChangeSet.ContainsKey('extractionModeChanged') -and $ChangeSet.extractionModeChanged) {
            $triggers.Add("extraction-mode-change")
        }
    }
    
    if ($Policy.triggers.ContainsKey('exportPermissionChange') -and $Policy.triggers.exportPermissionChange.enabled) {
        if ($ChangeSet.ContainsKey('exportPermissionChanged') -and $ChangeSet.exportPermissionChanged) {
            $triggers.Add("export-permission-change")
        }
    }
    
    # Check for destructive operation triggers
    if ($Policy.triggers.ContainsKey('fileDelete') -and $Policy.triggers.fileDelete.enabled) {
        if ($ChangeSet.ContainsKey('filesDeleted') -and $ChangeSet.filesDeleted.Count -gt 0) {
            $triggers.Add("file-delete")
        }
    }
    
    if ($Policy.triggers.ContainsKey('dataOverwrite') -and $Policy.triggers.dataOverwrite.enabled) {
        if ($ChangeSet.ContainsKey('willOverwrite') -and $ChangeSet.willOverwrite) {
            $triggers.Add("data-overwrite")
        }
    }
    
    # Check for network operation triggers
    if ($Policy.triggers.ContainsKey('externalAPICall') -and $Policy.triggers.externalAPICall.enabled) {
        if ($ChangeSet.ContainsKey('externalAPICalls') -and $ChangeSet.externalAPICalls.Count -gt 0) {
            $triggers.Add("external-api-call")
        }
    }
    
    # Check for suspicious pattern triggers
    if ($Policy.triggers.ContainsKey('secretDetected') -and $Policy.triggers.secretDetected.enabled) {
        if ($ChangeSet.ContainsKey('secretsDetected') -and $ChangeSet.secretsDetected.Count -gt 0) {
            $triggers.Add("secret-detected")
        }
    }
    
    $required = $triggers.Count -gt 0
    $reviewers = @()
    if ($required -and $Policy.ContainsKey('defaultReviewers')) { 
        $reviewers = $Policy.defaultReviewers 
    }
    
    # Build request parameters if review is required
    $requestParams = @{}
    if ($required) {
        $requestParams = @{
            Operation = $Operation
            ChangeSet = $ChangeSet
            Reviewers = $reviewers
            Conditions = $Policy.conditions
            Triggers = $triggers.ToArray()
            OperationType = if ($Policy.ContainsKey('operationType')) { $Policy.operationType } else { 'unknown' }
        }
    }
    
    return New-Object -TypeName PSObject -Property @{
        Required = $required
        Triggers = $triggers.ToArray()
        Reviewers = $reviewers
        RequestParams = $requestParams
        Reason = $(if ($required) { "Review required due to: $($triggers -join ', ')" } else { "No review triggers matched" })
    }
}

function Request-HumanReview {
    <#
    .SYNOPSIS
        Requests human review for an operation.
    
    .DESCRIPTION
        Creates a new review request for the specified operation.
        This is the main entry point for requesting human review.
    
    .PARAMETER Operation
        The operation requiring review.
    
    .PARAMETER ChangeSet
        Hashtable describing what changed.
    
    .PARAMETER Requester
        Username of the person requesting the review.
    
    .PARAMETER Justification
        Business justification for the change.
    
    .PARAMETER Priority
        Priority level: low, normal, high, critical.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject representing the created review request.
    
    .EXAMPLE
        $request = Request-HumanReview -Operation "pack-promote" -ChangeSet $changes `
            -Requester "alice" -Justification "Major feature release"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$ChangeSet,
        
        [Parameter(Mandatory = $true)]
        [string]$Requester,
        
        [string]$Justification = "",
        
        [ValidateSet('low', 'normal', 'high', 'critical')]
        [string]$Priority = 'normal',
        
        [string]$ProjectRoot = "."
    )
    
    # Check if review is required
    $check = Test-HumanReviewRequired -Operation $Operation -ChangeSet $ChangeSet -ProjectRoot $ProjectRoot
    
    if (-not $check.Required) {
        Write-Verbose "No review required for operation '$Operation'"
        return New-Object -TypeName PSObject -Property @{
            RequestId = $null
            Status = "not-required"
            Message = "Human review not required for this operation"
            CheckResult = $check
        }
    }
    
    # Create the review request
    $requestParams = $check.RequestParams
    return New-ReviewGateRequest @requestParams -Requester $Requester -Justification $Justification -Priority $Priority -ProjectRoot $ProjectRoot
}

function Test-ReviewGate {
    <#
    .SYNOPSIS
        Checks if operation needs review (alias for Test-HumanReviewRequired).
    
    .DESCRIPTION
        Evaluates whether a review gate is required for the given operation.
        This is a simplified interface for quick gate checks.
    
    .PARAMETER OperationType
        The type of operation (destructive, network, high-value, cross-pack, first-time, suspicious).
    
    .PARAMETER Context
        Hashtable with operation context.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        Boolean indicating if review is required.
    
    .EXAMPLE
        if (Test-ReviewGate -OperationType "destructive" -Context $ctx) { Request-HumanReview ... }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('destructive', 'network', 'high-value', 'cross-pack', 'first-time', 'suspicious')]
        [string]$OperationType,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,
        
        [string]$ProjectRoot = "."
    )
    
    # Map operation type to policy
    $policyMap = @{
        'destructive' = 'destructive-operation'
        'network' = 'network-operation'
        'high-value' = 'pack-promotion'
        'cross-pack' = 'cross-pack-mutation'
        'first-time' = 'source-ingestion'
        'suspicious' = 'suspicious-pattern'
    }
    
    $operation = $policyMap[$OperationType]
    $result = Test-HumanReviewRequired -Operation $operation -ChangeSet $Context -ProjectRoot $ProjectRoot
    
    return $result.Required
}

function Invoke-ReviewGate {
    <#
    .SYNOPSIS
        Execute gate check with interactive prompt.
    
    .DESCRIPTION
        Performs a complete gate check including review requirement evaluation
        and optional interactive approval prompt.
    
    .PARAMETER OperationType
        The type of operation.
    
    .PARAMETER Context
        Operation context.
    
    .PARAMETER Prompt
        Custom prompt message for interactive mode.
    
    .PARAMETER Interactive
        Show interactive prompt if review is required.
    
    .PARAMETER AutoApproveIfClean
        Automatically approve if no review triggers detected.
    
    .PARAMETER Requester
        Requester identity.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject with Approved (bool), RequestId, and Status.
    
    .EXAMPLE
        $gate = Invoke-ReviewGate -OperationType "destructive" -Context $ctx -Interactive
        if (-not $gate.Approved) { exit 1 }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('destructive', 'network', 'high-value', 'cross-pack', 'first-time', 'suspicious')]
        [string]$OperationType,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,
        
        [string]$Prompt = "This operation requires human review. Do you want to proceed?",
        
        [switch]$Interactive,
        
        [switch]$AutoApproveIfClean,
        
        [string]$Requester = $env:USER,
        
        [string]$ProjectRoot = "."
    )
    
    # Map operation type to policy name
    $policyMap = @{
        'destructive' = 'destructive-operation'
        'network' = 'network-operation'
        'high-value' = 'pack-promotion'
        'cross-pack' = 'cross-pack-mutation'
        'first-time' = 'source-ingestion'
        'suspicious' = 'suspicious-pattern'
    }
    
    $operation = $policyMap[$OperationType]
    
    # Check if review is required
    $check = Test-HumanReviewRequired -Operation $operation -ChangeSet $Context -ProjectRoot $ProjectRoot
    
    if (-not $check.Required) {
        if ($AutoApproveIfClean) {
            # Log the auto-approval
            Write-ReviewLogEntry -Entry @{
                eventType = 'auto-approved'
                operation = $operation
                operationType = $OperationType
                reason = 'No review triggers detected'
                requester = $Requester
            } -ProjectRoot $ProjectRoot
            
            return New-Object -TypeName PSObject -Property @{
                Approved = $true
                RequestId = $null
                Status = "auto-approved"
                Message = "No review required - automatically approved"
                Triggers = @()
            }
        }
        
        return New-Object -TypeName PSObject -Property @{
            Approved = $true
            RequestId = $null
            Status = "open"
            Message = "No review required"
            Triggers = @()
        }
    }
    
    # Review is required
    Write-Host "`n[REVIEW GATE TRIGGERED]" -ForegroundColor Yellow
    Write-Host "Operation: $operation" -ForegroundColor White
    Write-Host "Type: $OperationType" -ForegroundColor White
    Write-Host "Triggers: $($check.Triggers -join ', ')" -ForegroundColor Cyan
    
    if ($Interactive) {
        Write-Host "`n$Prompt" -ForegroundColor Yellow
        $response = Read-Host "Enter 'yes' to approve, 'no' to deny"
        
        if ($response -eq 'yes') {
            $request = Request-HumanReview -Operation $operation -ChangeSet $Context -Requester $Requester -Priority 'high' -ProjectRoot $ProjectRoot
            $decision = Approve-Operation -RequestId $request.requestId -Reviewer $Requester -Comments "Interactive approval" -ProjectRoot $ProjectRoot
            
            return New-Object -TypeName PSObject -Property @{
                Approved = $true
                RequestId = $request.requestId
                Status = "approved"
                Message = "Operation approved interactively"
                Triggers = $check.Triggers
            }
        }
        else {
            return New-Object -TypeName PSObject -Property @{
                Approved = $false
                RequestId = $null
                Status = "denied-by-user"
                Message = "Operation denied by user"
                Triggers = $check.Triggers
            }
        }
    }
    
    # Create review request
    $request = Request-HumanReview -Operation $operation -ChangeSet $Context -Requester $Requester -Priority 'normal' -ProjectRoot $ProjectRoot
    
    return New-Object -TypeName PSObject -Property @{
        Approved = $false
        RequestId = $request.requestId
        Status = "pending-review"
        Message = "Review request created - awaiting approval"
        Triggers = $check.Triggers
    }
}

function Approve-Operation {
    <#
    .SYNOPSIS
        Records human approval for an operation.
    
    .DESCRIPTION
        Submits an approval decision for a pending review request.
        Alias for Submit-ReviewDecision with 'approved' decision.
    
    .PARAMETER RequestId
        The review request ID.
    
    .PARAMETER Reviewer
        Username of the reviewer.
    
    .PARAMETER Comments
        Optional review comments.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject with the updated review request.
    
    .EXAMPLE
        Approve-Operation -RequestId "review-xxxxx" -Reviewer "alice" -Comments "Looks good"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestId,
        
        [Parameter(Mandatory = $true)]
        [string]$Reviewer,
        
        [string]$Comments = "",
        
        [string]$ProjectRoot = "."
    )
    
    return Submit-ReviewDecision -RequestId $RequestId -Reviewer $Reviewer -Decision 'approved' -Comments $Comments -ProjectRoot $ProjectRoot
}

function Deny-Operation {
    <#
    .SYNOPSIS
        Records human denial for an operation.
    
    .DESCRIPTION
        Submits a rejection decision for a pending review request.
        Alias for Submit-ReviewDecision with 'rejected' decision.
    
    .PARAMETER RequestId
        The review request ID.
    
    .PARAMETER Reviewer
        Username of the reviewer.
    
    .PARAMETER Comments
        Required comments explaining the denial.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject with the updated review request.
    
    .EXAMPLE
        Deny-Operation -RequestId "review-xxxxx" -Reviewer "alice" -Comments "Security concerns"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestId,
        
        [Parameter(Mandatory = $true)]
        [string]$Reviewer,
        
        [Parameter(Mandatory = $true)]
        [string]$Comments,
        
        [string]$ProjectRoot = "."
    )
    
    if ([string]::IsNullOrWhiteSpace($Comments)) {
        throw "Comments are required when denying an operation"
    }
    
    return Submit-ReviewDecision -RequestId $RequestId -Reviewer $Reviewer -Decision 'rejected' -Comments $Comments -ProjectRoot $ProjectRoot
}

function Get-ReviewHistory {
    <#
    .SYNOPSIS
        Gets review decisions history.
    
    .DESCRIPTION
        Retrieves the review decision history from the review log.
        Supports filtering by request ID, operation, reviewer, and date range.
    
    .PARAMETER RequestId
        Filter by specific request ID.
    
    .PARAMETER Operation
        Filter by operation type.
    
    .PARAMETER Reviewer
        Filter by reviewer username.
    
    .PARAMETER Decision
        Filter by decision type (approved, rejected, needs-work).
    
    .PARAMETER FromDate
        Start date for the query.
    
    .PARAMETER ToDate
        End date for the query.
    
    .PARAMETER Limit
        Maximum number of results to return.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        Array of review log entries.
    
    .EXAMPLE
        Get-ReviewHistory -Operation "pack-promotion" -Limit 10
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string]$RequestId = "",
        
        [string]$Operation = "",
        
        [string]$Reviewer = "",
        
        [ValidateSet('', 'approved', 'rejected', 'needs-work')]
        [string]$Decision = "",
        
        [DateTime]$FromDate = [DateTime]::MinValue,
        
        [DateTime]$ToDate = [DateTime]::MaxValue,
        
        [int]$Limit = 0,
        
        [string]$ProjectRoot = "."
    )
    
    $logPath = Get-ReviewLogPath -ProjectRoot $ProjectRoot
    
    if (-not (Test-Path -LiteralPath $logPath)) {
        return @()
    }
    
    $results = @()
    
    try {
        $lines = Get-Content -LiteralPath $logPath -Encoding UTF8
        
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            
            try {
                $entry = $line | ConvertFrom-Json
                
                # Apply filters
                if ($RequestId -and $entry.requestId -ne $RequestId) { continue }
                if ($Operation -and $entry.operation -ne $Operation) { continue }
                if ($Reviewer -and $entry.reviewer -ne $Reviewer) { continue }
                if ($Decision -and $entry.decision -ne $Decision) { continue }
                
                if ($entry.timestamp) {
                    $entryTime = [DateTime]::Parse($entry.timestamp)
                    if ($entryTime -lt $FromDate -or $entryTime -gt $ToDate) { continue }
                }
                
                $results += $entry
            }
            catch {
                Write-Verbose "Failed to parse log entry: $_"
            }
        }
    }
    catch {
        Write-Warning "Failed to read review log: $_"
    }
    
    # Sort by timestamp (newest first)
    $sorted = $results | Sort-Object -Property timestamp -Descending
    
    # Apply limit
    if ($Limit -gt 0 -and $sorted.Count -gt $Limit) {
        $sorted = $sorted | Select-Object -First $Limit
    }
    
    return $sorted
}

function New-ReviewGateRequest {
    <#
    .SYNOPSIS
        Creates a new review gate request.
    
    .DESCRIPTION
        Creates a new review request with unique ID, stores it in the review state,
        and triggers notifications if configured.
    
    .PARAMETER Operation
        The operation requiring review.
    
    .PARAMETER ChangeSet
        Hashtable describing what changed.
    
    .PARAMETER Requester
        Username of the person requesting the review.
    
    .PARAMETER Justification
        Business justification for the change.
    
    .PARAMETER Reviewers
        Array of required reviewer usernames.
    
    .PARAMETER Conditions
        Optional approval conditions.
    
    .PARAMETER Priority
        Priority level: low, normal, high, critical.
    
    .PARAMETER OperationType
        The operation type category.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject representing the created review request.
    
    .EXAMPLE
        $request = New-ReviewGateRequest -Operation "pack-promote" -ChangeSet $changes `
            -Requester "alice" -Justification "Major feature release" -Reviewers @("bob", "carol")
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$ChangeSet,
        
        [Parameter(Mandatory = $true)]
        [string]$Requester,
        
        [string]$Justification = "",
        
        [array]$Reviewers = @(),
        
        [hashtable]$Conditions = $null,
        
        [ValidateSet('low', 'normal', 'high', 'critical')]
        [string]$Priority = 'normal',
        
        [string]$OperationType = 'unknown',
        
        [string]$ProjectRoot = "."
    )
    
    # Generate unique request ID
    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmss")
    $random = -join ((1..6) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
    $requestId = "review-$timestamp-$random"
    
    # Get run ID for persistent log
    $runId = Get-CurrentRunId
    
    # Build the review request
    $request = @{
        requestId = $requestId
        operation = $Operation
        operationType = $OperationType
        status = "pending"
        priority = $Priority
        changeSet = $ChangeSet
        requester = $Requester
        justification = $Justification
        reviewers = $Reviewers
        decisions = @()
        conditions = $(if ($Conditions) { $Conditions } else { @{ minApprovers = 1 } })
        notificationsSent = @()
        runId = $runId
        createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        expiresAt = $null
        escalatedAt = $null
        completedAt = $null
        metadata = @{
            host = [Environment]::MachineName.ToLowerInvariant()
            pid = $PID
            version = $script:ReviewStateSchemaVersion
        }
    }
    
    # Calculate expiration time
    $expireHours = 72  # Default
    if ($null -ne $Conditions -and $Conditions.ContainsKey('autoExpireHours')) {
        $expireHours = $Conditions.autoExpireHours
    }
    $request.expiresAt = [DateTime]::UtcNow.AddHours($expireHours).ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    # Save to state (suppress output)
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    $state.requests[$requestId] = $request
    $state.stats.totalRequests++
    $state.stats.pendingCount++
    [void](Save-ReviewState -State $state -ProjectRoot $ProjectRoot)
    
    # Write to persistent log
    Write-ReviewLogEntry -Entry @{
        eventType = 'request-created'
        requestId = $requestId
        operation = $Operation
        operationType = $OperationType
        requester = $Requester
        priority = $Priority
        triggers = if ($ChangeSet.ContainsKey('triggers')) { $ChangeSet.triggers } else { @() }
    } -ProjectRoot $ProjectRoot
    
    # Trigger notification hooks (suppress output)
    [void](Invoke-ReviewNotification -Request $request -EventType "created" -ProjectRoot $ProjectRoot)
    
    Write-Verbose "Created review request $requestId for operation '$Operation'"
    
    # Return as PSCustomObject (PowerShell 5.1 compatible)
    return New-Object -TypeName PSObject -Property $request
}

function Submit-ReviewDecision {
    <#
    .SYNOPSIS
        Submits a review decision for a pending review request.
    
    .DESCRIPTION
        Records a reviewer's decision (approved, rejected, needs-work) on a
        review request. Checks for approval conditions and updates request status.
    
    .PARAMETER RequestId
        The review request ID.
    
    .PARAMETER Reviewer
        Username of the reviewer.
    
    .PARAMETER Decision
        The decision: 'approved', 'rejected', or 'needs-work'.
    
    .PARAMETER Comments
        Optional review comments.
    
    .PARAMETER Conditions
        Optional approval conditions being imposed.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject with the updated review request and approval status.
    
    .EXAMPLE
        Submit-ReviewDecision -RequestId "review-xxxxx" -Reviewer "bob" `
            -Decision "approved" -Comments "Code review passed"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestId,
        
        [Parameter(Mandatory = $true)]
        [string]$Reviewer,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('approved', 'rejected', 'needs-work')]
        [string]$Decision,
        
        [string]$Comments = "",
        
        [hashtable]$Conditions = @{},
        
        [string]$ProjectRoot = "."
    )
    
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    
    if (-not $state.requests.ContainsKey($RequestId)) {
        throw "Review request not found: $RequestId"
    }
    
    $request = $state.requests[$RequestId]
    
    # Validate request is still pending
    if ($request.status -notin @('pending', 'needs-work')) {
        throw "Cannot submit decision: request is already $($request.status)"
    }
    
    # Ensure decisions is an array
    if (-not $request.ContainsKey('decisions') -or $null -eq $request.decisions) {
        $request['decisions'] = @()
    }
    # PowerShell 5.1: Ensure we have an array
    $decisionsArray = @($request.decisions)
    
    # Check if reviewer has already submitted a decision
    $existingDecisionIndex = -1
    for ($i = 0; $i -lt $decisionsArray.Count; $i++) {
        if ($decisionsArray[$i].reviewer -eq $Reviewer) {
            $existingDecisionIndex = $i
            break
        }
    }
    
    $decisionRecord = @{
        reviewer = $Reviewer
        decision = $Decision
        comments = $Comments
        conditions = $Conditions
        submittedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    
    if ($existingDecisionIndex -ge 0) {
        # Update existing decision
        $decisionsArray[$existingDecisionIndex] = $decisionRecord
    }
    else {
        # Add new decision
        $decisionsArray += @($decisionRecord)
    }
    $request['decisions'] = $decisionsArray
    
    # Write to persistent log
    Write-ReviewLogEntry -Entry @{
        eventType = 'decision-submitted'
        requestId = $RequestId
        operation = $request.operation
        reviewer = $Reviewer
        decision = $Decision
        comments = $Comments
    } -ProjectRoot $ProjectRoot
    
    # Check if review is complete
    $completionCheck = Test-ReviewCompleteInternal -Request $request
    
    if ($completionCheck.IsComplete) {
        $request.status = $completionCheck.FinalStatus
        $request.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        
        # Update stats
        if ($request.status -eq 'approved') {
            $state.stats.approvedCount++
        }
        elseif ($request.status -eq 'rejected') {
            $state.stats.rejectedCount++
        }
        $state.stats.pendingCount--
        
        # Log completion
        Write-ReviewLogEntry -Entry @{
            eventType = 'request-completed'
            requestId = $RequestId
            operation = $request.operation
            finalStatus = $completionCheck.FinalStatus
            totalDecisions = $request.decisions.Count
        } -ProjectRoot $ProjectRoot
    }
    elseif ($Decision -eq 'needs-work') {
        $request.status = 'needs-work'
    }
    
    $request.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    # Save state (suppress output)
    [void](Save-ReviewState -State $state -ProjectRoot $ProjectRoot)
    
    # Trigger notification (suppress output)
    [void](Invoke-ReviewNotification -Request $request -EventType "decision-submitted" -ProjectRoot $ProjectRoot)
    
    Write-Verbose "Submitted $Decision decision from $Reviewer for request $RequestId"
    
    return New-Object -TypeName PSObject -Property @{
        Request = $request
        IsComplete = $completionCheck.IsComplete
        FinalStatus = $completionCheck.FinalStatus
        Approved = $completionCheck.FinalStatus -eq 'approved'
    }
}

function Test-ReviewComplete {
    <#
    .SYNOPSIS
        Checks if a review request is complete.
    
    .PARAMETER RequestId
        The review request ID.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        Boolean indicating if review is complete.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestId,
        
        [string]$ProjectRoot = "."
    )
    
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    
    if (-not $state.requests.ContainsKey($RequestId)) {
        throw "Review request not found: $RequestId"
    }
    
    $request = $state.requests[$RequestId]
    $result = Test-ReviewCompleteInternal -Request $request
    
    return $result.IsComplete
}

function Get-ReviewStatus {
    <#
    .SYNOPSIS
        Gets the current status of a review request.
    
    .DESCRIPTION
        Returns detailed status information including approval progress,
        remaining requirements, and time remaining.
    
    .PARAMETER RequestId
        The review request ID.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject with detailed review status.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestId,
        
        [string]$ProjectRoot = "."
    )
    
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    
    if (-not $state.requests.ContainsKey($RequestId)) {
        throw "Review request not found: $RequestId"
    }
    
    $request = $state.requests[$RequestId]
    
    # Calculate approval metrics
    $approvalCount = ($request.decisions | Where-Object { $_.decision -eq 'approved' }).Count
    $rejectionCount = ($request.decisions | Where-Object { $_.decision -eq 'rejected' }).Count
    $needsWorkCount = ($request.decisions | Where-Object { $_.decision -eq 'needs-work' }).Count
    
    $minApprovers = 1
    if ($request.conditions.ContainsKey('minApprovers')) { $minApprovers = $request.conditions.minApprovers }
    
    $requireOwnerApproval = $false
    if ($request.conditions.ContainsKey('requireOwnerApproval')) { $requireOwnerApproval = $request.conditions.requireOwnerApproval }
    
    # Calculate time remaining
    $timeRemaining = $null
    if ($request.expiresAt) {
        $expires = [DateTime]::Parse($request.expiresAt)
        $timeRemaining = $expires - [DateTime]::UtcNow
    }
    
    # Check if owner has approved
    $ownerApproved = $false
    if ($requireOwnerApproval -and $request.changeSet.ContainsKey('owner')) {
        $ownerApproved = ($request.decisions | Where-Object { 
            $_.reviewer -eq $request.changeSet.owner -and $_.decision -eq 'approved' 
        }).Count -gt 0
    }
    
    $resultObj = @{
        RequestId = $requestId
        Status = $request.status
        Operation = $request.operation
        Requester = $request.requester
        CreatedAt = $request.createdAt
        UpdatedAt = $request.updatedAt
        ExpiresAt = $request.expiresAt
        CompletedAt = $request.completedAt
        RunId = $request.runId
        Progress = New-Object -TypeName PSObject -Property @{
            Approvals = $approvalCount
            Rejections = $rejectionCount
            NeedsWork = $needsWorkCount
            MinRequired = $minApprovers
            OwnerApproved = $ownerApproved
            OwnerApprovalRequired = $requireOwnerApproval
        }
        RemainingRequirements = @(
            if ($approvalCount -lt $minApprovers) { "Need $($minApprovers - $approvalCount) more approval(s)" }
            if ($requireOwnerApproval -and -not $ownerApproved) { "Owner approval required" }
        )
        TimeRemaining = $(if ($timeRemaining) { $timeRemaining } else { $null })
        IsExpired = $(if ($timeRemaining) { $timeRemaining.TotalHours -lt 0 } else { $false })
        Decisions = $request.decisions
        CanComplete = ($approvalCount -ge $minApprovers) -and (-not $requireOwnerApproval -or $ownerApproved) -and ($rejectionCount -eq 0)
    }
    
    return New-Object -TypeName PSObject -Property $resultObj
}

function Get-PendingReviews {
    <#
    .SYNOPSIS
        Gets a list of pending review requests.
    
    .DESCRIPTION
        Returns pending reviews filtered by reviewer and/or priority.
        Supports listing reviews assigned to a specific reviewer.
    
    .PARAMETER Reviewer
        Optional reviewer username to filter by.
    
    .PARAMETER Priority
        Optional priority level to filter by.
    
    .PARAMETER IncludeExpired
        Include expired reviews in results.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        Array of review request objects.
    
    .EXAMPLE
        Get-PendingReviews -Reviewer "alice"
        Get-PendingReviews -Priority "high" -IncludeExpired
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string]$Reviewer = "",
        
        [ValidateSet('', 'low', 'normal', 'high', 'critical')]
        [string]$Priority = "",
        
        [switch]$IncludeExpired,
        
        [string]$ProjectRoot = "."
    )
    
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    $pendingStatuses = @('pending', 'needs-work')
    
    $results = @()
    
    foreach ($requestId in $state.requests.Keys) {
        $request = $state.requests[$requestId]
        
        # Filter by status
        if ($request.status -notin $pendingStatuses) {
            continue
        }
        
        # Filter by reviewer if specified
        if ($Reviewer -and $request.reviewers) {
            $reviewerList = @($request.reviewers)
            if ($reviewerList.Count -gt 0 -and $reviewerList -notcontains $Reviewer) {
                continue
            }
        }
        
        # Filter by priority if specified
        if ($Priority -and $request.priority -ne $Priority) {
            continue
        }
        
        # Check expiration
        $isExpired = $false
        if ($request.expiresAt) {
            $expires = [DateTime]::Parse($request.expiresAt)
            $isExpired = $expires -lt [DateTime]::UtcNow
        }
        
        if ($isExpired -and -not $IncludeExpired) {
            continue
        }
        
        # Add status flag
        $requestWithFlag = $request.Clone()
        $requestWithFlag['isExpired'] = $isExpired
        
        $results += (New-Object -TypeName PSObject -Property $requestWithFlag)
    }
    
    # Sort by priority then creation time
    $priorityOrder = @{ 'critical' = 0; 'high' = 1; 'normal' = 2; 'low' = 3 }
    $sortedResults = $results | Sort-Object -Property @(
        @{ Expression = { $priorityOrder[$_.priority] }; Ascending = $true }
        @{ Expression = { $_.createdAt }; Ascending = $true }
    )
    
    # Ensure we always return an array
    return @($sortedResults)
}

function Invoke-GateCheck {
    <#
    .SYNOPSIS
        Performs a gate check for automated processes.
    
    .DESCRIPTION
        Checks if a gate is open (approved) or closed (pending/rejected).
        Can automatically approve if no triggers are detected.
    
    .PARAMETER GateName
        The gate name: 'pack-promotion', 'source-ingestion', 'parser-upgrade', 'visibility-change'.
    
    .PARAMETER Context
        Context data for the gate check.
    
    .PARAMETER AutoApproveIfClean
        Automatically approve if no review triggers are detected.
    
    .PARAMETER Requester
        Requester identity for auto-approval.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject with GateOpen (bool), RequestId, and Status.
    
    .EXAMPLE
        $result = Invoke-GateCheck -GateName "pack-promotion" -Context $context -AutoApproveIfClean
        if (-not $result.GateOpen) { Wait-ForApproval -RequestId $result.RequestId }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GateName,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,
        
        [switch]$AutoApproveIfClean,
        
        [string]$Requester = "system",
        
        [string]$ProjectRoot = "."
    )
    
    # Check if review is required
    $reviewCheck = Test-HumanReviewRequired -Operation $GateName -ChangeSet $Context -ProjectRoot $ProjectRoot
    
    if (-not $reviewCheck.Required) {
        if ($AutoApproveIfClean) {
            Write-Verbose "Gate '$GateName' is clean - no review required. Auto-approving."
            return New-Object -TypeName PSObject -Property @{
                GateOpen = $true
                RequestId = $null
                Status = "auto-approved"
                Message = "No review triggers detected - automatically approved"
                Triggers = @()
            }
        }
        
        return New-Object -TypeName PSObject -Property @{
            GateOpen = $true
            RequestId = $null
            Status = "open"
            Message = "No review required"
            Triggers = @()
        }
    }
    
    # Review is required - check if there's an existing request
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    $existingRequest = $null
    
    foreach ($reqId in $state.requests.Keys) {
        $req = $state.requests[$reqId]
        if ($req.operation -eq $GateName -and $req.status -in @('pending', 'needs-work', 'approved')) {
            # Check if it's the same change context
            $isMatch = $true
            if ($Context.ContainsKey('packId') -and $req.changeSet.ContainsKey('packId')) {
                if ($Context.packId -ne $req.changeSet.packId) { $isMatch = $false }
            }
            if ($Context.ContainsKey('newVersion') -and $req.changeSet.ContainsKey('newVersion')) {
                if ($Context.newVersion -ne $req.changeSet.newVersion) { $isMatch = $false }
            }
            
            if ($isMatch) {
                $existingRequest = $req
                break
            }
        }
    }
    
    if ($existingRequest) {
        $status = Get-ReviewStatus -RequestId $existingRequest.requestId -ProjectRoot $ProjectRoot
        
        return New-Object -TypeName PSObject -Property @{
            GateOpen = $status.Status -eq 'approved'
            RequestId = $existingRequest.requestId
            Status = $status.Status
            Message = "Existing review request found"
            Triggers = $reviewCheck.Triggers
            ReviewStatus = $status
        }
    }
    
    # No existing request - create one
    $newRequest = New-ReviewGateRequest `
        -Operation $GateName `
        -ChangeSet $Context `
        -Requester $Requester `
        -Justification "Auto-created by gate check for $GateName" `
        -Reviewers $reviewCheck.Reviewers `
        -ProjectRoot $ProjectRoot
    
    return New-Object -TypeName PSObject -Property @{
        GateOpen = $false
        RequestId = $newRequest.requestId
        Status = "pending"
        Message = "New review request created"
        Triggers = $reviewCheck.Triggers
    }
}

function New-ReviewPolicy {
    <#
    .SYNOPSIS
        Defines a new review policy.
    
    .DESCRIPTION
        Creates and stores a custom review policy for a specific operation type.
    
    .PARAMETER PolicyName
        The name of the policy (operation type).
    
    .PARAMETER Rules
        Hashtable of trigger rules.
    
    .PARAMETER DefaultReviewers
        Array of default reviewers.
    
    .PARAMETER Conditions
        Approval conditions.
    
    .PARAMETER OperationType
        The operation type category.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject representing the created policy.
    
    .EXAMPLE
        New-ReviewPolicy -PolicyName "custom-operation" -Rules $rules -DefaultReviewers @("alice", "bob")
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyName,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Rules,
        
        [array]$DefaultReviewers = @(),
        
        [hashtable]$Conditions = $null,
        
        [string]$OperationType = 'unknown',
        
        [string]$ProjectRoot = "."
    )
    
    # Determine conditions (PowerShell 5.1 compatibility)
    if ($Conditions) {
        $policyConditions = $Conditions
    }
    else {
        $policyConditions = @{
            minApprovers = 1
            requireOwnerApproval = $false
            autoExpireHours = 72
        }
    }
    
    $policy = @{
        name = $PolicyName
        description = "Custom review policy for $PolicyName"
        operationType = $OperationType
        triggers = $Rules
        conditions = $policyConditions
        defaultReviewers = $DefaultReviewers
        createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    $state.policies[$PolicyName] = $policy
    Save-ReviewState -State $state -ProjectRoot $ProjectRoot
    
    Write-Verbose "Created review policy '$PolicyName'"
    
    return New-Object -TypeName PSObject -Property $policy
}

function Get-ReviewPolicy {
    <#
    .SYNOPSIS
        Gets a review policy by name.
    
    .PARAMETER PolicyName
        The policy name.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject representing the policy, or null if not found.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyName,
        
        [string]$ProjectRoot = "."
    )
    
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    
    if ($state.policies.ContainsKey($PolicyName)) {
        return New-Object -TypeName PSObject -Property $state.policies[$PolicyName]
    }
    
    if ($script:DefaultReviewPolicies.ContainsKey($PolicyName)) {
        return New-Object -TypeName PSObject -Property $script:DefaultReviewPolicies[$PolicyName]
    }
    
    return $null
}

function Remove-ReviewRequest {
    <#
    .SYNOPSIS
        Removes a review request from the system.
    
    .DESCRIPTION
        Permanently deletes a review request. Should be used for cleanup
        of old completed reviews.
    
    .PARAMETER RequestId
        The review request ID to remove.
    
    .PARAMETER Force
        Skip confirmation prompt.
    
    .PARAMETER ProjectRoot
        The project root directory.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestId,
        
        [switch]$Force,
        
        [string]$ProjectRoot = "."
    )
    
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    
    if (-not $state.requests.ContainsKey($RequestId)) {
        Write-Warning "Review request not found: $RequestId"
        return
    }
    
    $request = $state.requests[$RequestId]
    
    if ($PSCmdlet.ShouldProcess($RequestId, "Remove review request")) {
        if ($Force -or $request.status -in @('approved', 'rejected', 'expired')) {
            $state.requests.Remove($RequestId)
            Save-ReviewState -State $state -ProjectRoot $ProjectRoot
            
            # Log removal
            Write-ReviewLogEntry -Entry @{
                eventType = 'request-removed'
                requestId = $RequestId
                operation = $request.operation
                removedBy = $env:USER
            } -ProjectRoot $ProjectRoot
            
            Write-Verbose "Removed review request $RequestId"
        }
        else {
            Write-Warning "Request $RequestId is still $($request.status). Use -Force to remove pending requests."
        }
    }
}

#===============================================================================
# Review Condition Evaluators
#===============================================================================

function Test-LargeSourceDelta {
    <#
    .SYNOPSIS
        Tests if a source delta exceeds the threshold.
    
    .DESCRIPTION
        Evaluates whether the source delta percentage in the change set
        exceeds the specified threshold.
    
    .PARAMETER ChangeSet
        The change set to evaluate.
    
    .PARAMETER ThresholdPercent
        The threshold percentage (default: 30).
    
    .OUTPUTS
        Boolean indicating if delta is large.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ChangeSet,
        
        [int]$ThresholdPercent = 30
    )
    
    if (-not $ChangeSet.ContainsKey('sourceDeltaPercent')) {
        return $false
    }
    
    return $ChangeSet.sourceDeltaPercent -gt $ThresholdPercent
}

function Test-MajorVersionJump {
    <#
    .SYNOPSIS
        Tests if version change is a major version jump.
    
    .DESCRIPTION
        Compares semantic versions to detect major version changes.
    
    .PARAMETER OldVersion
        The old version string.
    
    .PARAMETER NewVersion
        The new version string.
    
    .OUTPUTS
        Boolean indicating if it's a major version jump.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OldVersion,
        
        [Parameter(Mandatory = $true)]
        [string]$NewVersion
    )
    
    try {
        $oldParts = $OldVersion -split '\.'
        $newParts = $NewVersion -split '\.'
        
        $oldMajor = [int]$oldParts[0]
        $newMajor = [int]$newParts[0]
        
        return $newMajor -gt $oldMajor
    }
    catch {
        # If parsing fails, treat as major change
        return $OldVersion -ne $NewVersion
    }
}

function Test-TrustTierChange {
    <#
    .SYNOPSIS
        Tests if trust tier has changed materially.
    
    .DESCRIPTION
        Checks for trust tier changes that require review.
    
    .PARAMETER ChangeSet
        The change set to evaluate.
    
    .OUTPUTS
        Boolean indicating if trust tier changed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ChangeSet
    )
    
    if ($ChangeSet.ContainsKey('trustTierChanges') -and $ChangeSet.trustTierChanges.Count -gt 0) {
        return $true
    }
    
    if ($ChangeSet.ContainsKey('oldTrustTier') -and $ChangeSet.ContainsKey('newTrustTier')) {
        return $ChangeSet.oldTrustTier -ne $ChangeSet.newTrustTier
    }
    
    return $false
}

function Test-VisibilityBoundaryChange {
    <#
    .SYNOPSIS
        Tests if visibility boundaries have changed.
    
    .DESCRIPTION
        Checks for changes to visibility or export boundaries.
    
    .PARAMETER ChangeSet
        The change set to evaluate.
    
    .OUTPUTS
        Boolean indicating if boundaries changed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ChangeSet
    )
    
    if ($ChangeSet.ContainsKey('visibilityChanged') -and $ChangeSet.visibilityChanged) {
        return $true
    }
    
    if ($ChangeSet.ContainsKey('oldVisibility') -and $ChangeSet.ContainsKey('newVisibility')) {
        return $ChangeSet.oldVisibility -ne $ChangeSet.newVisibility
    }
    
    if ($ChangeSet.ContainsKey('exportBoundaryChanged') -and $ChangeSet.exportBoundaryChanged) {
        return $true
    }
    
    return $false
}

function Test-EvalRegression {
    <#
    .SYNOPSIS
        Tests if eval results contain regressions with caveats.
    
    .DESCRIPTION
        Analyzes evaluation results for regressions that require human review.
    
    .PARAMETER EvalResults
        Array of evaluation result objects.
    
    .OUTPUTS
        Boolean indicating if regressions exist.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$EvalResults
    )
    
    if ($null -eq $EvalResults -or $EvalResults.Count -eq 0) {
        return $false
    }
    
    foreach ($result in $EvalResults) {
        # Get property value safely (handles both hashtables and PSCustomObjects)
        $regression = Get-PropertyValue -Object $result -PropertyName 'regression'
        $caveats = Get-PropertyValue -Object $result -PropertyName 'caveats'
        $scoreDelta = Get-PropertyValue -Object $result -PropertyName 'scoreDelta'
        
        # Check for regression markers
        if ($regression -eq $true) {
            return $true
        }
        
        # Check for caveats with severity
        if ($caveats -and (@($caveats).Count -gt 0)) {
            foreach ($caveat in $caveats) {
                $severity = Get-PropertyValue -Object $caveat -PropertyName 'severity'
                if ($severity -in @('high', 'critical')) {
                    return $true
                }
            }
        }
        
        # Check for score degradation
        if ($null -ne $scoreDelta -and $scoreDelta -lt -0.1) {
            return $true
        }
    }
    
    return $false
}

function Test-SecretPattern {
    <#
    .SYNOPSIS
        Tests if the change set contains potential secrets.
    
    .DESCRIPTION
        Detects common secret patterns (API keys, passwords, tokens) in the change set.
    
    .PARAMETER ChangeSet
        The change set to evaluate.
    
    .OUTPUTS
        Boolean indicating if secrets were detected.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ChangeSet
    )
    
    if ($ChangeSet.ContainsKey('secretsDetected') -and $ChangeSet.secretsDetected.Count -gt 0) {
        return $true
    }
    
    if ($ChangeSet.ContainsKey('content')) {
        # Secret detection patterns (escaped for PowerShell parser compatibility)
        $secretPatterns = @(
            "api[_-]?key\s*[=:]\s*[`"']?[a-zA-Z0-9]{16,}[`"']?",
            "password\s*[=:]\s*[`"'][^`"']{8,}[`"']",
            "token\s*[=:]\s*[`"']?[a-zA-Z0-9_-]{20,}[`"']?",
            "secret\s*[=:]\s*[`"']?[a-zA-Z0-9]{16,}[`"']?",
            "-----BEGIN (RSA |DSA |EC |OPENSSH )?PRIVATE KEY-----"
        )
        
        foreach ($pattern in $secretPatterns) {
            if ($ChangeSet.content -match $pattern) {
                return $true
            }
        }
    }
    
    return $false
}

#===============================================================================
# Internal Helper Functions
#===============================================================================

function Test-ReviewCompleteInternal {
    <#
    .SYNOPSIS
        Internal function to check if review conditions are met.
    
    .PARAMETER Request
        The review request object.
    
    .OUTPUTS
        Hashtable with IsComplete and FinalStatus.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Request
    )
    
    # Ensure decisions is an array for PowerShell 5.1 compatibility
    $decisionsList = @($Request.decisions)
    $approvalCount = @($decisionsList | Where-Object { $_.decision -eq 'approved' }).Count
    $rejectionCount = @($decisionsList | Where-Object { $_.decision -eq 'rejected' }).Count
    
    $minApprovers = 1
    if ($Request.conditions.ContainsKey('minApprovers')) {
        $minApprovers = $Request.conditions.minApprovers
    }
    
    # Check for rejections (immediate fail)
    if ($rejectionCount -gt 0) {
        return @{ IsComplete = $true; FinalStatus = 'rejected' }
    }
    
    # Check minimum approvals
    if ($approvalCount -lt $minApprovers) {
        return @{ IsComplete = $false; FinalStatus = $null }
    }
    
    # Check owner approval requirement
    $requireOwnerApproval = $false
    if ($Request.conditions.ContainsKey('requireOwnerApproval')) {
        $requireOwnerApproval = $Request.conditions.requireOwnerApproval
    }
    
    if ($requireOwnerApproval -and $Request.changeSet.ContainsKey('owner')) {
        $ownerApproved = @($decisionsList | Where-Object { 
            $_.reviewer -eq $Request.changeSet.owner -and $_.decision -eq 'approved' 
        }).Count -gt 0
        
        if (-not $ownerApproved) {
            return @{ IsComplete = $false; FinalStatus = $null }
        }
    }
    
    return @{ IsComplete = $true; FinalStatus = 'approved' }
}

function Invoke-ReviewNotification {
    <#
    .SYNOPSIS
        Triggers notification hooks for review events.
    
    .DESCRIPTION
        Sends notifications via configured channels (email, webhook, etc.).
        This is a stub for integration with external notification systems.
    
    .PARAMETER Request
        The review request.
    
    .PARAMETER EventType
        The type of event: created, decision-submitted, expired, etc.
    
    .PARAMETER ProjectRoot
        The project root directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Request,
        
        [Parameter(Mandatory = $true)]
        [string]$EventType,
        
        [string]$ProjectRoot = "."
    )
    
    # Track notification in request
    $notificationRecord = @{
        eventType = $EventType
        timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        channels = @()
    }
    
    # Hook: Check for notification configuration
    $notifyConfigPath = Join-Path $ProjectRoot ".llm-workflow/notify-config.json"
    $config = $null
    
    if (Test-Path -LiteralPath $notifyConfigPath) {
        try {
            $config = Get-Content -LiteralPath $notifyConfigPath -Raw | ConvertFrom-Json -AsHashtable
        }
        catch {
            Write-Verbose "Failed to load notification config: $_"
        }
    }
    
    # Email notification stub
    if ($config -and $config.email -and $config.email.enabled) {
        $notificationRecord.channels += "email"
        # Integration point: Send-MailMessage or external email service
        Write-Verbose "[Notification] Email would be sent for $EventType on $($Request.requestId)"
    }
    
    # Webhook notification stub
    if ($config -and $config.webhook -and $config.webhook.enabled) {
        $notificationRecord.channels += "webhook"
        # Integration point: Invoke-RestMethod to webhook URL
        Write-Verbose "[Notification] Webhook would be called for $EventType on $($Request.requestId)"
    }
    
    # Console notification (always for high priority)
    if ($Request.priority -in @('high', 'critical') -or $EventType -eq 'expired') {
        $notificationRecord.channels += "console"
        Write-Host "[Review Gate] $EventType for $($Request.operation) - Request: $($Request.requestId)" -ForegroundColor Yellow
    }
    
    # Update request with notification record
    if (-not $Request.ContainsKey('notificationsSent') -or $null -eq $Request.notificationsSent) {
        $Request['notificationsSent'] = @()
    }
    $notificationsArray = @($Request.notificationsSent)
    $notificationsArray += @($notificationRecord)
    $Request['notificationsSent'] = $notificationsArray
    
    # Save state if request exists
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    if ($state.requests.ContainsKey($Request.requestId)) {
        $state.requests[$Request.requestId] = $Request
        Save-ReviewState -State $state -ProjectRoot $ProjectRoot
    }
}

function Invoke-ReviewEscalation {
    <#
    .SYNOPSIS
        Escalates expired or stuck review requests.
    
    .DESCRIPTION
        Checks for reviews that need escalation and triggers escalation
        notifications. Should be run periodically (e.g., via scheduled task).
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        Array of escalated review requests.
    
    .EXAMPLE
        # Run daily via scheduled task
        Invoke-ReviewEscalation | ForEach-Object { Send-EscalationEmail $_ }
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string]$ProjectRoot = "."
    )
    
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    $escalated = @()
    $now = [DateTime]::UtcNow
    
    foreach ($requestId in $state.requests.Keys) {
        $request = $state.requests[$requestId]
        
        # Skip completed or already escalated
        if ($request.status -notin @('pending', 'needs-work')) {
            continue
        }
        
        # Check expiration
        if ($request.expiresAt) {
            $expires = [DateTime]::Parse($request.expiresAt)
            
            if ($expires -lt $now -and $request.status -ne 'expired') {
                # Mark as expired/escalated
                $request.status = 'escalated'
                $request.escalatedAt = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
                $request.updatedAt = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
                
                # Trigger escalation notification (suppress output)
                [void](Invoke-ReviewNotification -Request $request -EventType "expired" -ProjectRoot $ProjectRoot)
                
                # Log escalation
                Write-ReviewLogEntry -Entry @{
                    eventType = 'request-escalated'
                    requestId = $requestId
                    operation = $request.operation
                    reason = 'timeout-expired'
                } -ProjectRoot $ProjectRoot
                
                $escalated += (New-Object -TypeName PSObject -Property $request)
                
                Write-Warning "Review request $requestId has expired and been escalated"
            }
        }
    }
    
    $escalatedCount = @($escalated).Count
    if ($escalatedCount -gt 0) {
        [void](Save-ReviewState -State $state -ProjectRoot $ProjectRoot)
    }
    
    # Ensure we always return an array (PowerShell 5.1 compatible)
    return @($escalated)
}

#===============================================================================
# Required Public API Functions (as per specification)
#===============================================================================

function New-HumanReviewGate {
    <#
    .SYNOPSIS
        Creates a new human review gate configuration.
    
    .DESCRIPTION
        Creates and stores a review gate configuration that defines when human
        review is required for specific operations. This is a high-level wrapper
        around New-ReviewPolicy with additional gate-specific settings.
    
    .PARAMETER GateName
        The unique name for this review gate.
    
    .PARAMETER OperationType
        The type of operation: destructive, network, high-value, cross-pack, first-time, suspicious.
    
    .PARAMETER Triggers
        Hashtable defining what triggers the review requirement.
    
    .PARAMETER Conditions
        Approval conditions including minApprovers, requireOwnerApproval, autoExpireHours.
    
    .PARAMETER DefaultReviewers
        Array of default reviewer usernames.
    
    .PARAMETER Description
        Human-readable description of the gate's purpose.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject representing the created gate configuration.
    
    .EXAMPLE
        $gate = New-HumanReviewGate -GateName "prod-deploy" -OperationType "high-value" `
            -Triggers @{ largeSourceDelta = @{ enabled = $true; thresholdPercent = 20 } } `
            -Conditions @{ minApprovers = 2; requireOwnerApproval = $true } `
            -DefaultReviewers @("alice", "bob")
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GateName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('destructive', 'network', 'high-value', 'cross-pack', 'first-time', 'suspicious')]
        [string]$OperationType,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Triggers,
        
        [hashtable]$Conditions = $null,
        
        [array]$DefaultReviewers = @(),
        
        [string]$Description = "",
        
        [string]$ProjectRoot = "."
    )
    
    # Set default conditions if not provided
    if ($Conditions) {
        $gateConditions = $Conditions
    }
    else {
        $gateConditions = @{
            minApprovers = 1
            requireOwnerApproval = $false
            autoExpireHours = 72
        }
    }
    
    # Build the gate configuration
    $gateConfig = @{
        name = $GateName
        description = $(if ($Description) { $Description } else { "Human review gate for $GateName" })
        operationType = $OperationType
        triggers = $Triggers
        conditions = $gateConditions
        defaultReviewers = $DefaultReviewers
        createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        version = 1
    }
    
    # Store in state
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    $state.policies[$GateName] = $gateConfig
    Save-ReviewState -State $state -ProjectRoot $ProjectRoot
    
    # Log gate creation
    Write-ReviewLogEntry -Entry @{
        eventType = 'gate-created'
        gateName = $GateName
        operationType = $OperationType
        createdBy = $env:USER
    } -ProjectRoot $ProjectRoot
    
    Write-Verbose "Created human review gate '$GateName' for operation type '$OperationType'"
    
    return New-Object -TypeName PSObject -Property $gateConfig
}

function Submit-ReviewRequest {
    <#
    .SYNOPSIS
        Submits content for human review.
    
    .DESCRIPTION
        Submits content requiring human review, creating a review request.
        This is the primary entry point for submitting review requests.
    
    .PARAMETER GateName
        The review gate name (or operation type).
    
    .PARAMETER Content
        The content being submitted for review.
    
    .PARAMETER Requester
        Username of the person submitting the request.
    
    .PARAMETER Justification
        Business justification for the change.
    
    .PARAMETER Priority
        Priority level: low, normal, high, critical.
    
    .PARAMETER Context
        Additional context data for the review.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject representing the created review request.
    
    .EXAMPLE
        $request = Submit-ReviewRequest -GateName "prod-deploy" `
            -Content $deploymentPackage `
            -Requester "alice" -Priority "high" `
            -Justification "Critical security patch"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GateName,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Content,
        
        [Parameter(Mandatory = $true)]
        [string]$Requester,
        
        [string]$Justification = "",
        
        [ValidateSet('low', 'normal', 'high', 'critical')]
        [string]$Priority = 'normal',
        
        [hashtable]$Context = @{},
        
        [string]$ProjectRoot = "."
    )
    
    # Get the gate/policy configuration
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    $gateConfig = $null
    
    if ($state.policies.ContainsKey($GateName)) {
        $gateConfig = $state.policies[$GateName]
    }
    elseif ($script:DefaultReviewPolicies.ContainsKey($GateName)) {
        $gateConfig = $script:DefaultReviewPolicies[$GateName]
    }
    
    # Build change set from content and context
    $changeSet = @{
        content = $Content
        context = $Context
    }
    
    # Add metadata from context
    if ($Context.ContainsKey('packId')) { $changeSet['packId'] = $Context.packId }
    if ($Context.ContainsKey('owner')) { $changeSet['owner'] = $Context.owner }
    if ($Context.ContainsKey('oldVersion')) { $changeSet['oldVersion'] = $Context.oldVersion }
    if ($Context.ContainsKey('newVersion')) { $changeSet['newVersion'] = $Context.newVersion }
    if ($Context.ContainsKey('triggers')) { $changeSet['triggers'] = $Context.triggers }
    
    # Determine operation type
    $operationType = 'unknown'
    if ($gateConfig -and $gateConfig.ContainsKey('operationType')) {
        $operationType = $gateConfig.operationType
    }
    
    # Get default reviewers from gate config
    $reviewers = @()
    if ($gateConfig -and $gateConfig.ContainsKey('defaultReviewers')) {
        $reviewers = $gateConfig.defaultReviewers
    }
    
    # Get conditions from gate config
    $conditions = @{ minApprovers = 1; autoExpireHours = 72 }
    if ($gateConfig -and $gateConfig.ContainsKey('conditions')) {
        $conditions = $gateConfig.conditions
    }
    
    # Create the review request
    $request = New-ReviewGateRequest `
        -Operation $GateName `
        -ChangeSet $changeSet `
        -Requester $Requester `
        -Justification $Justification `
        -Reviewers $reviewers `
        -Conditions $conditions `
        -Priority $Priority `
        -OperationType $operationType `
        -ProjectRoot $ProjectRoot
    
    Write-Verbose "Submitted review request $($request.requestId) to gate '$GateName'"
    
    return $request
}

function Get-ReviewRequest {
    <#
    .SYNOPSIS
        Gets a review request by ID.
    
    .DESCRIPTION
        Retrieves the details of a specific review request including its
        current status, decisions, and metadata.
    
    .PARAMETER RequestId
        The unique ID of the review request.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject with the review request details, or null if not found.
    
    .EXAMPLE
        $request = Get-ReviewRequest -RequestId "review-20260115T120000-a1b2c3"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestId,
        
        [string]$ProjectRoot = "."
    )
    
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    
    if (-not $state.requests.ContainsKey($RequestId)) {
        return $null
    }
    
    $request = $state.requests[$RequestId]
    
    # Add computed properties
    $request['isExpired'] = $false
    if ($request.ContainsKey('expiresAt') -and $request.expiresAt) {
        $expires = [DateTime]::Parse($request.expiresAt)
        $request['isExpired'] = $expires -lt [DateTime]::UtcNow
    }
    
    return New-Object -TypeName PSObject -Property $request
}

function Approve-ReviewRequest {
    <#
    .SYNOPSIS
        Approves a review request.
    
    .DESCRIPTION
        Submits an approval decision for a pending review request.
        Supports multi-level approvals for critical operations.
    
    .PARAMETER RequestId
        The review request ID.
    
    .PARAMETER Reviewer
        Username of the reviewer.
    
    .PARAMETER Comments
        Optional approval comments.
    
    .PARAMETER Conditions
        Optional conditions being imposed with the approval.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject with the updated review request and approval status.
    
    .EXAMPLE
        Approve-ReviewRequest -RequestId "review-xxxxx" -Reviewer "alice" -Comments "Approved after security review"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestId,
        
        [Parameter(Mandatory = $true)]
        [string]$Reviewer,
        
        [string]$Comments = "",
        
        [hashtable]$Conditions = @{},
        
        [string]$ProjectRoot = "."
    )
    
    return Submit-ReviewDecision `
        -RequestId $RequestId `
        -Reviewer $Reviewer `
        -Decision 'approved' `
        -Comments $Comments `
        -Conditions $Conditions `
        -ProjectRoot $ProjectRoot
}

function Reject-ReviewRequest {
    <#
    .SYNOPSIS
        Rejects a review request with reasons.
    
    .DESCRIPTION
        Submits a rejection decision for a review request with detailed
        reasons explaining why the request was rejected.
    
    .PARAMETER RequestId
        The review request ID.
    
    .PARAMETER Reviewer
        Username of the reviewer.
    
    .PARAMETER Reasons
        Required array of rejection reasons.
    
    .PARAMETER Comments
        Additional comments explaining the rejection.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject with the updated review request.
    
    .EXAMPLE
        Reject-ReviewRequest -RequestId "review-xxxxx" -Reviewer "alice" `
            -Reasons @("Security concerns", "Incomplete documentation") `
            -Comments "Please address the security issues and resubmit"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestId,
        
        [Parameter(Mandatory = $true)]
        [string]$Reviewer,
        
        [Parameter(Mandatory = $true)]
        [array]$Reasons,
        
        [string]$Comments = "",
        
        [string]$ProjectRoot = "."
    )
    
    if ($null -eq $Reasons -or $Reasons.Count -eq 0) {
        throw "At least one reason is required when rejecting a review request"
    }
    
    # Build rejection comments with reasons
    $reasonsText = "Rejection reasons:`n" + ($Reasons | ForEach-Object { "- $_" } | Out-String)
    $fullComments = if ($Comments) { "$Comments`n`n$reasonsText" } else { $reasonsText }
    
    $result = Submit-ReviewDecision `
        -RequestId $RequestId `
        -Reviewer $Reviewer `
        -Decision 'rejected' `
        -Comments $fullComments `
        -ProjectRoot $ProjectRoot
    
    # Log rejection with reasons
    Write-ReviewLogEntry -Entry @{
        eventType = 'request-rejected'
        requestId = $RequestId
        reviewer = $Reviewer
        reasons = $Reasons
    } -ProjectRoot $ProjectRoot
    
    return $result
}

function Assert-ReviewGate {
    <#
    .SYNOPSIS
        Asserts that a review gate is satisfied, throwing if not.
    
    .DESCRIPTION
        Checks if a review gate is satisfied (approved) and throws an exception
        if it's not. This is used for enforcing review gates in automated workflows.
        Supports multi-level approvals for critical operations.
    
    .PARAMETER GateName
        The name of the gate to check.
    
    .PARAMETER RequestId
        Optional specific request ID to check.
    
    .PARAMETER Context
        Context data for the gate check.
    
    .PARAMETER AutoApproveIfClean
        Automatically approve if no review triggers are detected.
    
    .PARAMETER Requester
        Requester identity.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject with success status if assertion passes.
    
    .EXAMPLE
        Assert-ReviewGate -GateName "prod-deploy" -Context $context
    
    .NOTES
        Throws exception if gate is not satisfied.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GateName,
        
        [string]$RequestId = "",
        
        [hashtable]$Context = @{},
        
        [switch]$AutoApproveIfClean,
        
        [string]$Requester = $env:USER,
        
        [string]$ProjectRoot = "."
    )
    
    # If specific request ID provided, check that
    if ($RequestId) {
        $request = Get-ReviewRequest -RequestId $RequestId -ProjectRoot $ProjectRoot
        
        if ($null -eq $request) {
            throw "ReviewGateAssertionFailed: Request '$RequestId' not found"
        }
        
        if ($request.status -eq 'approved') {
            return New-Object -TypeName PSObject -Property @{
                Success = $true
                RequestId = $RequestId
                Status = 'approved'
                Message = "Review gate '$GateName' is satisfied"
            }
        }
        
        if ($request.status -eq 'rejected') {
            throw "ReviewGateAssertionFailed: Request '$RequestId' has been rejected"
        }
        
        if ($request.isExpired) {
            throw "ReviewGateAssertionFailed: Request '$RequestId' has expired"
        }
        
        throw "ReviewGateAssertionFailed: Request '$RequestId' is pending approval (status: $($request.status))"
    }
    
    # Otherwise, perform a gate check
    $result = Invoke-GateCheck `
        -GateName $GateName `
        -Context $Context `
        -AutoApproveIfClean:$AutoApproveIfClean `
        -Requester $Requester `
        -ProjectRoot $ProjectRoot
    
    if (-not $result.GateOpen) {
        if ($result.Status -eq 'pending') {
            throw "ReviewGateAssertionFailed: Review gate '$GateName' requires approval. Request ID: $($result.RequestId)"
        }
        elseif ($result.Status -eq 'rejected') {
            throw "ReviewGateAssertionFailed: Review gate '$GateName' has been rejected"
        }
        else {
            throw "ReviewGateAssertionFailed: Review gate '$GateName' is not satisfied (status: $($result.Status))"
        }
    }
    
    return New-Object -TypeName PSObject -Property @{
        Success = $true
        RequestId = $result.RequestId
        Status = $result.Status
        Message = "Review gate '$GateName' is satisfied"
    }
}

function Get-ReviewGateStatus {
    <#
    .SYNOPSIS
        Gets statistics and status for review gates.
    
    .DESCRIPTION
        Retrieves comprehensive statistics about review gates including
        pending requests, approval rates, and gate-specific metrics.
    
    .PARAMETER GateName
        Optional specific gate name to get status for.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject with gate statistics.
    
    .EXAMPLE
        $stats = Get-ReviewGateStatus
        $gateStats = Get-ReviewGateStatus -GateName "prod-deploy"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$GateName = "",
        
        [string]$ProjectRoot = "."
    )
    
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    $now = [DateTime]::UtcNow
    
    # Calculate overall statistics (ensure arrays for PS 5.1 compatibility)
    $allRequests = @($state.requests.Values)
    $total = $allRequests.Count
    $pending = @($allRequests | Where-Object { $_.status -eq 'pending' }).Count
    $approved = @($allRequests | Where-Object { $_.status -eq 'approved' }).Count
    $rejected = @($allRequests | Where-Object { $_.status -eq 'rejected' }).Count
    $expired = @($allRequests | Where-Object { $_.status -eq 'expired' }).Count
    $escalated = @($allRequests | Where-Object { $_.status -eq 'escalated' }).Count
    
    # Calculate approval rate
    $decidedCount = $approved + $rejected
    $approvalRate = if ($decidedCount -gt 0) { $approved / $decidedCount } else { 0 }
    
    # Calculate expired pending requests
    $expiredPending = 0
    foreach ($req in $allRequests | Where-Object { $_.status -in @('pending', 'needs-work') }) {
        if ($req.expiresAt) {
            $expires = [DateTime]::Parse($req.expiresAt)
            if ($expires -lt $now) {
                $expiredPending++
            }
        }
    }
    
    $stats = @{
        TotalRequests = $total
        Pending = $pending
        Approved = $approved
        Rejected = $rejected
        Expired = $expired
        Escalated = $escalated
        ExpiredPending = $expiredPending
        ApprovalRate = [math]::Round($approvalRate * 100, 2)
        LastUpdated = $state.lastUpdated
        Gates = @{}
    }
    
    # If specific gate requested, include detailed stats
    if ($GateName) {
        $gateRequests = @($allRequests | Where-Object { $_.operation -eq $GateName })
        
        $stats.Gates[$GateName] = @{
            Total = $gateRequests.Count
            Pending = @($gateRequests | Where-Object { $_.status -eq 'pending' }).Count
            Approved = @($gateRequests | Where-Object { $_.status -eq 'approved' }).Count
            Rejected = @($gateRequests | Where-Object { $_.status -eq 'rejected' }).Count
            Escalated = @($gateRequests | Where-Object { $_.status -eq 'escalated' }).Count
            AverageResolutionHours = 0
        }
        
        # Calculate average resolution time for approved requests
        $resolvedRequests = @($gateRequests | Where-Object { $_.status -eq 'approved' -and $_.completedAt })
        if ($resolvedRequests.Count -gt 0) {
            $totalHours = 0
            foreach ($req in $resolvedRequests) {
                $created = [DateTime]::Parse($req.createdAt)
                $completed = [DateTime]::Parse($req.completedAt)
                $totalHours += ($completed - $created).TotalHours
            }
            $stats.Gates[$GateName].AverageResolutionHours = [math]::Round($totalHours / $resolvedRequests.Count, 2)
        }
        
        # Include recent pending requests for this gate
        $stats.Gates[$GateName].RecentPending = @($gateRequests | 
            Where-Object { $_.status -in @('pending', 'needs-work') } | 
            Sort-Object createdAt -Descending | 
            Select-Object -First 5 | 
            ForEach-Object { $_.requestId })
    }
    else {
        # Include stats for all gates
        $gateNames = @($allRequests | ForEach-Object { $_.operation } | Select-Object -Unique)
        
        foreach ($gName in $gateNames) {
            $gateRequests = @($allRequests | Where-Object { $_.operation -eq $gName })
            
            $stats.Gates[$gName] = @{
                Total = $gateRequests.Count
                Pending = @($gateRequests | Where-Object { $_.status -eq 'pending' }).Count
                Approved = @($gateRequests | Where-Object { $_.status -eq 'approved' }).Count
                Rejected = @($gateRequests | Where-Object { $_.status -eq 'rejected' }).Count
            }
        }
    }
    
    return New-Object -TypeName PSObject -Property $stats
}

function Test-ReviewPolicy {
    <#
    .SYNOPSIS
        Tests if a review policy passes (no review required).
    
    .DESCRIPTION
        Evaluates a change set against a review policy to determine if
        the policy passes (no review required) or fails (review required).
    
    .PARAMETER PolicyName
        The name of the policy to test.
    
    .PARAMETER ChangeSet
        The change set to evaluate.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        PSCustomObject with Passes (bool), Triggers (array), and Details.
    
    .EXAMPLE
        $result = Test-ReviewPolicy -PolicyName "pack-promotion" -ChangeSet $changes
        if (-not $result.Passes) { Submit-ReviewRequest ... }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyName,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$ChangeSet,
        
        [string]$ProjectRoot = "."
    )
    
    # Use Test-HumanReviewRequired to check if review is required
    $result = Test-HumanReviewRequired -Operation $PolicyName -ChangeSet $ChangeSet -ProjectRoot $ProjectRoot
    
    # Determine if policy passes (no review required)
    $passes = -not $result.Required
    
    # Build detailed results
    $details = @{
        PolicyName = $PolicyName
        OperationType = $(if ($result.RequestParams.ContainsKey('OperationType')) { $result.RequestParams.OperationType } else { 'unknown' })
        TriggersMatched = $result.Triggers
        ReviewRequired = $result.Required
        RecommendedReviewers = $result.Reviewers
    }
    
    return New-Object -TypeName PSObject -Property @{
        Passes = $passes
        Triggers = $result.Triggers
        Details = $details
        Message = $result.Reason
    }
}

#===============================================================================
# Export Module Members
#===============================================================================

# Only export if running as a module (not when dot-sourced)
try {
    Export-ModuleMember -Function @(
        # Core review functions (as specified in requirements)
        'Request-HumanReview'
        'Test-ReviewGate'
        'Invoke-ReviewGate'
        'Approve-Operation'
        'Deny-Operation'
        'Get-ReviewHistory'
        
        # Additional core functions
        'Test-HumanReviewRequired'
        'New-ReviewGateRequest'
        'Submit-ReviewDecision'
        'Test-ReviewComplete'
        'Get-ReviewStatus'
        'Get-PendingReviews'
        'Invoke-GateCheck'
        'New-ReviewPolicy'
        'Get-ReviewPolicy'
        
        # Required Public API Functions (Section 10.3)
        'New-HumanReviewGate'
        'Submit-ReviewRequest'
        'Get-ReviewRequest'
        'Approve-ReviewRequest'
        'Reject-ReviewRequest'
        'Assert-ReviewGate'
        'Get-ReviewGateStatus'
        'Test-ReviewPolicy'
        
        # Condition evaluators
        'Test-LargeSourceDelta'
        'Test-MajorVersionJump'
        'Test-TrustTierChange'
        'Test-VisibilityBoundaryChange'
        'Test-EvalRegression'
        'Test-SecretPattern'
        
        # State management
        'Get-ReviewState'
        'Save-ReviewState'
        'Get-ReviewLogPath'
        'Write-ReviewLogEntry'
        'Invoke-ReviewEscalation'
        'Remove-ReviewRequest'
    ) -ErrorAction SilentlyContinue
}
catch {
    # Silently ignore when dot-sourcing (not running as a module)
}
