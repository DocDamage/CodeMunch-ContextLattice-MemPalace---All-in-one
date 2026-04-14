#requires -Version 5.1
Set-StrictMode -Version Latest


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
    
    $deltaPercent = 0
    if ($ChangeSet.ContainsKey('sourceDeltaPercent')) {
        $deltaPercent = $ChangeSet.sourceDeltaPercent
    }
    elseif ($ChangeSet.ContainsKey('delta') -and $ChangeSet.delta.ContainsKey('totalLines') -and $ChangeSet.delta.totalLines -gt 0) {
        $deltaPercent = ($ChangeSet.delta.linesChanged / $ChangeSet.delta.totalLines) * 100
    }
    else {
        return $false
    }
    
    return $deltaPercent -ge $ThresholdPercent
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
    
    if ($null -eq $EvalResults) {
        return $false
    }
    
    # Handle single hashtable input
    $resultsArray = @()
    if ($EvalResults -is [hashtable]) {
        $resultsArray = @($EvalResults)
    }
    else {
        $resultsArray = @($EvalResults)
    }

    if ($resultsArray.Count -eq 0) {
        return $false
    }
    
    foreach ($result in $resultsArray) {
        # Check for direct pass rate regression if available
        if ($result.ContainsKey('previousPassRate') -and $result.ContainsKey('currentPassRate')) {
            if ($result.currentPassRate -lt $result.previousPassRate) {
                return $true
            }
        }
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


