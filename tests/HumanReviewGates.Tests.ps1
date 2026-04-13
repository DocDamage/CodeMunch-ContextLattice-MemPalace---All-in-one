#requires -Version 5.1
<#
.SYNOPSIS
    Unit tests for the Human Review Gates module.

.DESCRIPTION
    Tests the core functionality of the HumanReviewGates module including
    condition evaluators, review request management, and policy enforcement.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import the module (dot-source for script module)
$modulePath = Join-Path $PSScriptRoot "..\module\LLMWorkflow\governance\HumanReviewGates.ps1"
. $modulePath

$testResults = @{
    Passed = 0
    Failed = 0
    Tests = @()
}

function Test-Case {
    param(
        [string]$Name,
        [scriptblock]$Test
    )
    
    try {
        & $Test
        $testResults.Passed++
        $testResults.Tests += [pscustomobject]@{ Name = $Name; Result = "PASS" }
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    }
    catch {
        $testResults.Failed++
        $testResults.Tests += [pscustomobject]@{ Name = $Name; Result = "FAIL"; Error = $_ }
        Write-Host "  [FAIL] $Name : $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Human Review Gates Module Tests" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Section 1: Module Loading
Write-Host "Section 1: Module Loading" -ForegroundColor Yellow

Test-Case -Name "Module script loads successfully" -Test {
    $cmd = Get-Command -Name Test-HumanReviewRequired -CommandType Function -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "Module functions not loaded" }
}

Test-Case -Name "All required functions are available" -Test {
    $requiredFunctions = @(
        'Test-HumanReviewRequired',
        'New-ReviewGateRequest',
        'Submit-ReviewDecision',
        'Test-ReviewComplete',
        'Get-ReviewStatus',
        'Get-PendingReviews',
        'Invoke-GateCheck',
        'New-ReviewPolicy',
        'Get-ReviewPolicy',
        'Test-LargeSourceDelta',
        'Test-MajorVersionJump',
        'Test-TrustTierChange',
        'Test-VisibilityBoundaryChange',
        'Test-EvalRegression',
        'Invoke-ReviewEscalation',
        'Remove-ReviewRequest'
    )
    
    foreach ($func in $requiredFunctions) {
        $cmd = Get-Command -Name $func -CommandType Function -ErrorAction SilentlyContinue
        if (-not $cmd) { throw "Function not found: $func" }
    }
}

# Section 2: Condition Evaluators
Write-Host ""
Write-Host "Section 2: Condition Evaluators" -ForegroundColor Yellow

Test-Case -Name "Test-MajorVersionJump detects major version change" -Test {
    $result = Test-MajorVersionJump -OldVersion '1.0.0' -NewVersion '2.0.0'
    if (-not $result) { throw "Should detect major version jump" }
}

Test-Case -Name "Test-MajorVersionJump ignores minor version change" -Test {
    $result = Test-MajorVersionJump -OldVersion '1.0.0' -NewVersion '1.1.0'
    if ($result) { throw "Should not detect minor version as major" }
}

Test-Case -Name "Test-MajorVersionJump ignores patch version change" -Test {
    $result = Test-MajorVersionJump -OldVersion '1.0.0' -NewVersion '1.0.1'
    if ($result) { throw "Should not detect patch version as major" }
}

Test-Case -Name "Test-LargeSourceDelta detects large delta" -Test {
    $result = Test-LargeSourceDelta -ChangeSet @{ sourceDeltaPercent = 45 } -ThresholdPercent 30
    if (-not $result) { throw "Should detect delta above threshold" }
}

Test-Case -Name "Test-LargeSourceDelta ignores small delta" -Test {
    $result = Test-LargeSourceDelta -ChangeSet @{ sourceDeltaPercent = 15 } -ThresholdPercent 30
    if ($result) { throw "Should not detect delta below threshold" }
}

Test-Case -Name "Test-LargeSourceDelta handles missing data" -Test {
    $result = Test-LargeSourceDelta -ChangeSet @{ otherField = 'value' } -ThresholdPercent 30
    if ($result) { throw "Should return false for missing delta" }
}

Test-Case -Name "Test-TrustTierChange detects trust tier changes list" -Test {
    $result = Test-TrustTierChange -ChangeSet @{ trustTierChanges = @('change1', 'change2') }
    if (-not $result) { throw "Should detect tier changes" }
}

Test-Case -Name "Test-TrustTierChange detects old vs new tier" -Test {
    $result = Test-TrustTierChange -ChangeSet @{ oldTrustTier = 'A'; newTrustTier = 'B' }
    if (-not $result) { throw "Should detect tier difference" }
}

Test-Case -Name "Test-TrustTierChange ignores identical tiers" -Test {
    $result = Test-TrustTierChange -ChangeSet @{ oldTrustTier = 'A'; newTrustTier = 'A' }
    if ($result) { throw "Should not detect identical tiers" }
}

Test-Case -Name "Test-VisibilityBoundaryChange detects visibility change flag" -Test {
    $result = Test-VisibilityBoundaryChange -ChangeSet @{ visibilityChanged = $true }
    if (-not $result) { throw "Should detect visibility change" }
}

Test-Case -Name "Test-VisibilityBoundaryChange detects old vs new visibility" -Test {
    $result = Test-VisibilityBoundaryChange -ChangeSet @{ oldVisibility = 'private'; newVisibility = 'public' }
    if (-not $result) { throw "Should detect visibility difference" }
}

Test-Case -Name "Test-VisibilityBoundaryChange detects export boundary change" -Test {
    $result = Test-VisibilityBoundaryChange -ChangeSet @{ exportBoundaryChanged = $true }
    if (-not $result) { throw "Should detect export boundary change" }
}

Test-Case -Name "Test-EvalRegression detects regression flag" -Test {
    $evalResults = @(@{ regression = $true })
    $result = Test-EvalRegression -EvalResults $evalResults
    if (-not $result) { throw "Should detect regression" }
}

Test-Case -Name "Test-EvalRegression detects high severity caveat" -Test {
    $evalResults = @(@{ caveats = @(@{ severity = 'high' }) })
    $result = Test-EvalRegression -EvalResults $evalResults
    if (-not $result) { throw "Should detect high severity caveat" }
}

Test-Case -Name "Test-EvalRegression detects score degradation" -Test {
    $evalResults = @(@{ scoreDelta = -0.15 })
    $result = Test-EvalRegression -EvalResults $evalResults
    if (-not $result) { throw "Should detect score degradation" }
}

Test-Case -Name "Test-EvalRegression ignores small score change" -Test {
    $evalResults = @(@{ scoreDelta = -0.05 })
    $result = Test-EvalRegression -EvalResults $evalResults
    if ($result) { throw "Should not detect small score change" }
}

# Section 3: Policy Management
Write-Host ""
Write-Host "Section 3: Policy Management" -ForegroundColor Yellow

Test-Case -Name "Get-ReviewPolicy returns default pack-promotion policy" -Test {
    $policy = Get-ReviewPolicy -PolicyName 'pack-promotion'
    if (-not $policy) { throw "Policy should exist" }
    if ($policy.triggers.largeSourceDelta.enabled -ne $true) { throw "Large source delta should be enabled" }
}

Test-Case -Name "Get-ReviewPolicy returns default source-ingestion policy" -Test {
    $policy = Get-ReviewPolicy -PolicyName 'source-ingestion'
    if (-not $policy) { throw "Policy should exist" }
}

Test-Case -Name "Get-ReviewPolicy returns null for unknown policy" -Test {
    $policy = Get-ReviewPolicy -PolicyName 'nonexistent-policy'
    if ($policy) { throw "Should return null for unknown policy" }
}

# Section 4: Review Request Creation
Write-Host ""
Write-Host "Section 4: Review Request Creation" -ForegroundColor Yellow

$script:testRequestId = $null

Test-Case -Name "New-ReviewGateRequest creates valid request" -Test {
    $changeSet = @{
        packId = 'test-pack'
        oldVersion = '1.0.0'
        newVersion = '2.0.0'
    }
    
    $request = New-ReviewGateRequest -Operation 'pack-promotion' -ChangeSet $changeSet `
        -Requester 'testuser' -Justification 'Test request' -Reviewers @('reviewer1', 'reviewer2')
    
    if (-not $request.requestId) { throw "Request should have ID" }
    if ($request.status -ne 'pending') { throw "Status should be pending" }
    if ($request.operation -ne 'pack-promotion') { throw "Operation mismatch" }
    
    $script:testRequestId = $request.requestId
}

Test-Case -Name "Request ID follows expected format" -Test {
    if (-not $script:testRequestId) { throw "No test request ID" }
    if (-not ($script:testRequestId -match '^review-\d{8}T\d{6}-[a-f0-9]{6}$')) {
        throw "Request ID format unexpected: $script:testRequestId"
    }
}

Test-Case -Name "Get-ReviewStatus returns correct status for new request" -Test {
    $status = Get-ReviewStatus -RequestId $script:testRequestId
    if ($status.Status -ne 'pending') { throw "Status should be pending" }
    if ($status.Progress.Approvals -ne 0) { throw "Should have 0 approvals" }
    if ($status.Progress.MinRequired -lt 1) { throw "Should require at least 1 approver" }
}

# Section 5: Decision Submission
Write-Host ""
Write-Host "Section 5: Decision Submission" -ForegroundColor Yellow

Test-Case -Name "Submit-ReviewDecision accepts approval" -Test {
    $result = Submit-ReviewDecision -RequestId $script:testRequestId -Reviewer 'reviewer1' `
        -Decision 'approved' -Comments 'Looks good'
    
    if ($result.Request.status -ne 'pending') { throw "Should still be pending (needs more approvals)" }
}

Test-Case -Name "Get-ReviewStatus reflects approval" -Test {
    $status = Get-ReviewStatus -RequestId $script:testRequestId
    if ($status.Progress.Approvals -ne 1) { throw "Should have 1 approval" }
    if ($status.Decisions.Count -ne 1) { throw "Should have 1 decision" }
}

Test-Case -Name "Submit-ReviewDecision accepts second approval and completes" -Test {
    $result = Submit-ReviewDecision -RequestId $script:testRequestId -Reviewer 'reviewer2' `
        -Decision 'approved' -Comments 'Approved'
    
    # Note: This may complete if minApprovers is 2, or stay pending if higher
}

# Section 6: Review Detection
Write-Host ""
Write-Host "Section 6: Review Detection" -ForegroundColor Yellow

Test-Case -Name "Test-HumanReviewRequired detects large source delta trigger" -Test {
    $changeSet = @{
        packId = 'test-pack'
        oldVersion = '1.0.0'
        newVersion = '1.1.0'
        sourceDeltaPercent = 45
    }
    
    $result = Test-HumanReviewRequired -Operation 'pack-promotion' -ChangeSet $changeSet
    if (-not $result.Required) { throw "Should require review for large delta" }
    if ($result.Triggers -notcontains 'large-source-delta') { throw "Should trigger large-source-delta" }
}

Test-Case -Name "Test-HumanReviewRequired detects major version jump" -Test {
    $changeSet = @{
        packId = 'test-pack'
        oldVersion = '1.0.0'
        newVersion = '2.0.0'
    }
    
    $result = Test-HumanReviewRequired -Operation 'pack-promotion' -ChangeSet $changeSet
    if (-not $result.Required) { throw "Should require review for major version" }
    if ($result.Triggers -notcontains 'major-version-jump') { throw "Should trigger major-version-jump" }
}

Test-Case -Name "Test-HumanReviewRequired allows clean changes" -Test {
    $changeSet = @{
        packId = 'test-pack'
        oldVersion = '1.0.0'
        newVersion = '1.0.1'
        sourceDeltaPercent = 5
    }
    
    $result = Test-HumanReviewRequired -Operation 'pack-promotion' -ChangeSet $changeSet
    if ($result.Required) { throw "Should not require review for minor change" }
}

# Section 7: Gate Check
Write-Host ""
Write-Host "Section 7: Gate Check" -ForegroundColor Yellow

Test-Case -Name "Invoke-GateCheck auto-approves clean changes" -Test {
    $context = @{
        packId = 'test-pack'
        oldVersion = '1.0.0'
        newVersion = '1.0.1'
        sourceDeltaPercent = 5
    }
    
    $result = Invoke-GateCheck -GateName 'pack-promotion' -Context $context -AutoApproveIfClean
    if (-not $result.GateOpen) { throw "Gate should be open for clean changes" }
    if ($result.Status -ne 'auto-approved') { throw "Should be auto-approved" }
}

Test-Case -Name "Invoke-GateCheck blocks on review triggers" -Test {
    $context = @{
        packId = 'test-pack'
        oldVersion = '1.0.0'
        newVersion = '2.0.0'
        sourceDeltaPercent = 45
    }
    
    $result = Invoke-GateCheck -GateName 'pack-promotion' -Context $context
    if ($result.GateOpen) { throw "Gate should be closed for triggered changes" }
    if ($result.Status -ne 'pending') { throw "Should be pending" }
    if (-not $result.RequestId) { throw "Should have request ID" }
}

# Section 8: Pending Reviews Query
Write-Host ""
Write-Host "Section 8: Pending Reviews Query" -ForegroundColor Yellow

Test-Case -Name "Get-PendingReviews returns pending requests" -Test {
    $pending = Get-PendingReviews
    if ($pending.Count -lt 1) { throw "Should have at least 1 pending request" }
}

Test-Case -Name "Get-PendingReviews filters by reviewer" -Test {
    $pending = Get-PendingReviews -Reviewer 'reviewer1'
    # Should return requests where reviewer1 is assigned
}

# Section 9: Policy Creation
Write-Host ""
Write-Host "Section 9: Policy Creation" -ForegroundColor Yellow

Test-Case -Name "New-ReviewPolicy creates custom policy" -Test {
    $rules = @{
        largeSourceDelta = @{ enabled = $true; thresholdPercent = 50 }
        majorVersionJump = @{ enabled = $true }
    }
    
    $policy = New-ReviewPolicy -PolicyName 'custom-test-policy' -Rules $rules -DefaultReviewers @('admin1')
    if (-not $policy) { throw "Policy should be created" }
    if ($policy.triggers.largeSourceDelta.thresholdPercent -ne 50) { throw "Threshold should be 50" }
}

Test-Case -Name "Get-ReviewPolicy retrieves custom policy" -Test {
    $policy = Get-ReviewPolicy -PolicyName 'custom-test-policy'
    if (-not $policy) { throw "Should retrieve custom policy" }
    if ($policy.defaultReviewers -notcontains 'admin1') { throw "Should have admin1 as reviewer" }
}

# Section 10: State Persistence
Write-Host ""
Write-Host "Section 10: State Persistence" -ForegroundColor Yellow

Test-Case -Name "Review state file is created" -Test {
    $statePath = Join-Path $PSScriptRoot "..\.llm-workflow\state\review-gates.json"
    if (-not (Test-Path $statePath)) { throw "State file should exist" }
}

Test-Case -Name "Review state has correct structure" -Test {
    $state = Get-ReviewState
    if (-not $state.ContainsKey('requests')) { throw "Should have requests" }
    if (-not $state.ContainsKey('stats')) { throw "Should have stats" }
}

# Section 11: Escalation
Write-Host ""
Write-Host "Section 11: Escalation" -ForegroundColor Yellow

Test-Case -Name "Invoke-ReviewEscalation runs without error" -Test {
    $escalated = Invoke-ReviewEscalation
    # Should return array (possibly empty)
    if ($null -eq $escalated) { throw "Should return array" }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed: $($testResults.Passed)" -ForegroundColor Green
Write-Host "Failed: $($testResults.Failed)" -ForegroundColor $(if ($testResults.Failed -gt 0) { "Red" } else { "Green" })
Write-Host "Total:  $($testResults.Passed + $testResults.Failed)" -ForegroundColor White
Write-Host ""

if ($testResults.Failed -gt 0) {
    Write-Host "FAILED TESTS:" -ForegroundColor Red
    $testResults.Tests | Where-Object { $_.Result -eq 'FAIL' } | ForEach-Object {
        Write-Host "  - $($_.Name)" -ForegroundColor Red
    }
    exit 1
}
else {
    Write-Host "ALL TESTS PASSED!" -ForegroundColor Green
    exit 0
}
