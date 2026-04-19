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

#===============================================================================
# Helper Functions
#===============================================================================

#===============================================================================
# Core Review Functions (22 functions as specified)
#===============================================================================

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
    $decisions = @($request.decisions)
    $approvalCount = @($decisions | Where-Object { $_ -and ($_.decision -eq 'approved') }).Count
    $rejectionCount = @($decisions | Where-Object { $_ -and ($_.decision -eq 'rejected') }).Count
    $needsWorkCount = @($decisions | Where-Object { $_ -and ($_.decision -eq 'needs-work') }).Count
    
    $minApprovers = 1
    if ($request.conditions -and $request.conditions.ContainsKey('minApprovers')) { $minApprovers = $request.conditions.minApprovers }
    
    $requireOwnerApproval = $false
    if ($request.conditions -and $request.conditions.ContainsKey('requireOwnerApproval')) { $requireOwnerApproval = $request.conditions.requireOwnerApproval }
    
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

#===============================================================================
# Internal Helper Functions
#===============================================================================

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
