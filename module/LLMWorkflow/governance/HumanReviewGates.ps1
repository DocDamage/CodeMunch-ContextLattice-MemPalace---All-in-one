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
#>

Set-StrictMode -Version Latest

#===============================================================================
# Configuration and Constants
#===============================================================================

$script:ReviewStateFileName = "review-gates.json"
$script:ReviewStateSchemaVersion = 1
$script:ReviewStateSchemaName = "human-review-gates"

# Default review policies by operation type
$script:DefaultReviewPolicies = @{
    "pack-promotion" = @{
        name = "Pack Promotion Review Policy"
        description = "Reviews required for pack promotion operations"
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
            requests = @{}
            policies = @{}
            stats = @{
                totalRequests = 0
                approvedCount = 0
                rejectedCount = 0
                pendingCount = 0
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
            }
        }
        
        return $state
    }
    catch {
        Write-Warning "Failed to load review state: $_. Initializing new state."
        return @{
            schemaVersion = $script:ReviewStateSchemaVersion
            requests = @{}
            policies = @{}
            stats = @{
                totalRequests = 0
                approvedCount = 0
                rejectedCount = 0
                pendingCount = 0
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
# Core Review Functions
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
        
        [string]$ProjectRoot = "."
    )
    
    # Generate unique request ID
    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmss")
    $random = -join ((1..6) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
    $requestId = "review-$timestamp-$random"
    
    # Build the review request
    $request = @{
        requestId = $requestId
        operation = $Operation
        status = "pending"
        priority = $Priority
        changeSet = $ChangeSet
        requester = $Requester
        justification = $Justification
        reviewers = $Reviewers
        decisions = @()
        conditions = $(if ($Conditions) { $Conditions } else { @{ minApprovers = 1 } })
        notificationsSent = @()
        createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        expiresAt = $null
        escalatedAt = $null
        completedAt = $null
        metadata = @{
            host = [Environment]::MachineName.ToLowerInvariant()
            pid = $PID
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
    
    # Check if reviewer has already submitted a decision
    $existingDecisionIndex = -1
    for ($i = 0; $i -lt $request.decisions.Count; $i++) {
        if ($request.decisions[$i].reviewer -eq $Reviewer) {
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
        $request.decisions[$existingDecisionIndex] = $decisionRecord
    }
    else {
        # Add new decision
        $request.decisions += @($decisionRecord)
    }
    
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
        
        [string]$ProjectRoot = "."
    )
    
    # Determine conditions (PowerShell 5.1 compatibility)
    $policyConditions = if ($Conditions) { $Conditions } else { @{ 
        minApprovers = 1 
        requireOwnerApproval = $false
        autoExpireHours = 72
    }}
    
    $policy = @{
        name = $PolicyName
        description = "Custom review policy for $PolicyName"
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
    
    $approvalCount = ($Request.decisions | Where-Object { $_.decision -eq 'approved' }).Count
    $rejectionCount = ($Request.decisions | Where-Object { $_.decision -eq 'rejected' }).Count
    
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
        $ownerApproved = ($Request.decisions | Where-Object { 
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
    if (-not $Request.ContainsKey('notificationsSent')) {
        $Request['notificationsSent'] = @()
    }
    $Request.notificationsSent += @($notificationRecord)
    
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
            Write-Verbose "Removed review request $RequestId"
        }
        else {
            Write-Warning "Request $RequestId is still $($request.status). Use -Force to remove pending requests."
        }
    }
}

#===============================================================================
# Export Module Members
#===============================================================================

# Only export if running as a module (not when dot-sourced)
try {
    Export-ModuleMember -Function @(
    # Core review functions
    'Test-HumanReviewRequired',
    'New-ReviewGateRequest',
    'Submit-ReviewDecision',
    'Test-ReviewComplete',
    'Get-ReviewStatus',
    'Get-PendingReviews',
    'Invoke-GateCheck',
    'New-ReviewPolicy',
    'Get-ReviewPolicy',
    
    # Condition evaluators
    'Test-LargeSourceDelta',
    'Test-MajorVersionJump',
    'Test-TrustTierChange',
    'Test-VisibilityBoundaryChange',
    'Test-EvalRegression',
    
    # State management
    'Get-ReviewState',
    'Save-ReviewState',
    'Invoke-ReviewEscalation',
    'Remove-ReviewRequest'
) -ErrorAction SilentlyContinue
}
catch {
    # Silently ignore when dot-sourcing (not running as a module)
}
