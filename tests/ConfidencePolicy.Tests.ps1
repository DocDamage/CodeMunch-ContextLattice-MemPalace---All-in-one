#requires -Version 5.1
<#
.SYNOPSIS
    Unit tests for ConfidencePolicy module.

.DESCRIPTION
    Tests the Phase 5 Confidence and Abstain Policy system.
    Covers confidence calculation, answer modes, abstention, and escalation.
#>

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'
$script:TestResults = @{
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
        $script:TestResults.Passed++
        $script:TestResults.Tests += @{ Name = $Name; Result = 'PASS' }
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    }
    catch {
        $script:TestResults.Failed++
        $script:TestResults.Tests += @{ Name = $Name; Result = 'FAIL'; Error = $_ }
        Write-Host "  [FAIL] $Name : $_" -ForegroundColor Red
    }
}

# Import the module
$modulePath = Join-Path $PSScriptRoot '../module/LLMWorkflow/retrieval/ConfidencePolicy.ps1'

Write-Host "`nLoading ConfidencePolicy module from: $modulePath" -ForegroundColor Cyan
# Source the file (Export-ModuleMember warning is expected when not loaded as module)
try { . $modulePath } catch { Write-Warning "Import warning (expected): $_" }

Write-Host "`nRunning ConfidencePolicy Tests..." -ForegroundColor Cyan
Write-Host "=" * 60

#===============================================================================
# Test 1: Get-DefaultConfidencePolicy
#===============================================================================
Test-Case -Name "Get-DefaultConfidencePolicy returns valid policy" -Test {
    $policy = Get-DefaultConfidencePolicy
    
    if (-not $policy) { throw "Policy is null" }
    if ($policy.policyName -ne 'default') { throw "Expected policy name 'default'" }
    if ($policy.schemaVersion -ne 1) { throw "Expected schema version 1" }
    if (-not $policy.thresholds) { throw "Missing thresholds" }
    if ($policy.thresholds.direct -ne 0.85) { throw "Expected direct threshold 0.85" }
    if ($policy.thresholds.caveat -ne 0.70) { throw "Expected caveat threshold 0.70" }
    if ($policy.thresholds.abstain -ne 0.50) { throw "Expected abstain threshold 0.50" }
}

Test-Case -Name "Get-DefaultConfidencePolicy includes all required weights" -Test {
    $policy = Get-DefaultConfidencePolicy
    
    if (-not $policy.weights) { throw "Missing weights" }
    if ($policy.weights.relevance -ne 0.40) { throw "Expected relevance weight 0.40" }
    if ($policy.weights.authority -ne 0.30) { throw "Expected authority weight 0.30" }
    if ($policy.weights.consistency -ne 0.20) { throw "Expected consistency weight 0.20" }
    if ($policy.weights.coverage -ne 0.10) { throw "Expected coverage weight 0.10" }
}

Test-Case -Name "Get-DefaultConfidencePolicy includes authority role weights" -Test {
    $policy = Get-DefaultConfidencePolicy
    
    if (-not $policy.authorityRoleWeights) { throw "Missing authorityRoleWeights" }
    if ($policy.authorityRoleWeights['core-runtime'] -ne 1.00) { throw "Expected core-runtime weight 1.00" }
    if ($policy.authorityRoleWeights['community'] -ne 0.50) { throw "Expected community weight 0.50" }
}

#===============================================================================
# Test 2: Get-ConfidenceComponents
#===============================================================================
Test-Case -Name "Get-ConfidenceComponents calculates all components" -Test {
    $evidence = @(
        @{ sourceId = "ev1"; relevanceScore = 0.90; sourceType = "core-runtime"; evidenceType = "code-example" },
        @{ sourceId = "ev2"; relevanceScore = 0.85; sourceType = "exemplar-pattern"; evidenceType = "tutorial" }
    )
    
    $components = Get-ConfidenceComponents -Evidence $evidence -Context @{}
    
    if (-not $components.relevance) { throw "Missing relevance component" }
    if (-not $components.authority) { throw "Missing authority component" }
    if (-not $components.consistency) { throw "Missing consistency component" }
    if (-not $components.coverage) { throw "Missing coverage component" }
}

Test-Case -Name "Get-ConfidenceComponents relevance is weighted correctly" -Test {
    $evidence = @(
        @{ sourceId = "ev1"; relevanceScore = 1.0; sourceType = "core-runtime" }
    )
    
    $components = Get-ConfidenceComponents -Evidence $evidence -Context @{}
    
    # Relevance component should be close to 0.40 (max weight for relevance)
    if ($components.relevance.score -lt 0.35) { 
        throw "Expected relevance score >= 0.35, got $($components.relevance.score)" 
    }
}

Test-Case -Name "Get-ConfidenceComponents handles low relevance" -Test {
    $evidence = @(
        @{ sourceId = "ev1"; relevanceScore = 0.3; sourceType = "core-runtime" },
        @{ sourceId = "ev2"; relevanceScore = 0.2; sourceType = "community" }
    )
    
    $components = Get-ConfidenceComponents -Evidence $evidence -Context @{}
    
    # Low relevance should result in lower score
    if ($components.relevance.score -gt 0.20) { 
        throw "Expected low relevance score, got $($components.relevance.score)" 
    }
}

Test-Case -Name "Get-ConfidenceComponents detects contradictions" -Test {
    $evidence = @(
        @{ sourceId = "ev1"; relevanceScore = 0.9; sourceType = "core-runtime"; claim = "A" },
        @{ sourceId = "ev2"; relevanceScore = 0.9; sourceType = "exemplar-pattern"; claim = "B" },
        @{ sourceId = "ev3"; relevanceScore = 0.8; sourceType = "community"; claim = "C" }
    )
    
    $components = Get-ConfidenceComponents -Evidence $evidence -Context @{}
    
    # Multiple distinct claims should reduce consistency
    if ($components.consistency.details.distinctClaims -lt 2) { 
        throw "Expected multiple distinct claims" 
    }
}

#===============================================================================
# Test 3: Get-AnswerMode
#===============================================================================
Test-Case -Name "Get-AnswerMode returns 'direct' for high confidence" -Test {
    $policy = Get-DefaultConfidencePolicy
    $mode = Get-AnswerMode -ConfidenceScore 0.90 -Policy $policy -EvidenceIssues @()
    
    if ($mode -ne 'direct') { throw "Expected 'direct', got '$mode'" }
}

Test-Case -Name "Get-AnswerMode returns 'caveat' for medium confidence" -Test {
    $policy = Get-DefaultConfidencePolicy
    $mode = Get-AnswerMode -ConfidenceScore 0.75 -Policy $policy -EvidenceIssues @()
    
    if ($mode -ne 'caveat') { throw "Expected 'caveat', got '$mode'" }
}

Test-Case -Name "Get-AnswerMode returns 'abstain' for low confidence" -Test {
    $policy = Get-DefaultConfidencePolicy
    $mode = Get-AnswerMode -ConfidenceScore 0.40 -Policy $policy -EvidenceIssues @()
    
    if ($mode -ne 'abstain') { throw "Expected 'abstain', got '$mode'" }
}

Test-Case -Name "Get-AnswerMode escalates on policy violation" -Test {
    $policy = Get-DefaultConfidencePolicy
    $issues = @(@{ type = 'policy-violation'; severity = 'critical'; description = 'Test violation' })
    $mode = Get-AnswerMode -ConfidenceScore 0.95 -Policy $policy -EvidenceIssues $issues
    
    if ($mode -ne 'escalate') { throw "Expected 'escalate', got '$mode'" }
}

Test-Case -Name "Get-AnswerMode escalates on boundary issue" -Test {
    $policy = Get-DefaultConfidencePolicy
    $issues = @(@{ type = 'boundary-issue'; severity = 'high'; description = 'Security boundary' })
    $mode = Get-AnswerMode -ConfidenceScore 0.95 -Policy $policy -EvidenceIssues $issues
    
    if ($mode -ne 'escalate') { throw "Expected 'escalate', got '$mode'" }
}

Test-Case -Name "Get-AnswerMode returns 'caveat' with major issues even at high confidence" -Test {
    $policy = Get-DefaultConfidencePolicy
    $issues = @(@{ type = 'low-relevance'; severity = 'high'; description = 'Low relevance evidence' })
    $mode = Get-AnswerMode -ConfidenceScore 0.90 -Policy $policy -EvidenceIssues $issues
    
    if ($mode -ne 'caveat') { throw "Expected 'caveat' due to major issues, got '$mode'" }
}

#===============================================================================
# Test 4: Test-ShouldAbstain
#===============================================================================
Test-Case -Name "Test-ShouldAbstain returns true for low confidence" -Test {
    $policy = Get-DefaultConfidencePolicy
    $evidence = @(@{ sourceId = "ev1"; relevanceScore = 0.3 })
    
    $result = Test-ShouldAbstain -ConfidenceScore 0.40 -Evidence $evidence -Policy $policy
    
    if (-not $result) { throw "Expected abstain for confidence 0.40" }
}

Test-Case -Name "Test-ShouldAbstain returns false for adequate confidence" -Test {
    $policy = Get-DefaultConfidencePolicy
    $evidence = @(@{ sourceId = "ev1"; relevanceScore = 0.8 })
    
    $result = Test-ShouldAbstain -ConfidenceScore 0.70 -Evidence $evidence -Policy $policy
    
    if ($result) { throw "Expected not to abstain for confidence 0.70" }
}

Test-Case -Name "Test-ShouldAbstain returns true for all low-trust sources" -Test {
    $policy = Get-DefaultConfidencePolicy
    $evidence = @(
        @{ sourceId = "ev1"; relevanceScore = 0.6; trustTier = 'Low' },
        @{ sourceId = "ev2"; relevanceScore = 0.7; trustTier = 'Quarantined' }
    )
    
    $result = Test-ShouldAbstain -ConfidenceScore 0.65 -Evidence $evidence -Policy $policy
    
    if (-not $result) { throw "Expected abstain for all low-trust sources" }
}

Test-Case -Name "Test-ShouldAbstain respects minimum evidence count" -Test {
    $policy = Get-DefaultConfidencePolicy
    $policy.minimumEvidenceCount = 2
    $evidence = @(@{ sourceId = "ev1"; relevanceScore = 0.9 })
    
    $result = Test-ShouldAbstain -ConfidenceScore 0.90 -Evidence $evidence -Policy $policy
    
    if (-not $result) { throw "Expected abstain for insufficient evidence count" }
}

#===============================================================================
# Test 5: Get-AbstainDecision
#===============================================================================
Test-Case -Name "Get-AbstainDecision creates valid abstain decision" -Test {
    $decision = Get-AbstainDecision -Reason "Insufficient evidence" -Alternatives @{ suggestion = "Try again" }
    
    if (-not $decision) { throw "Decision is null" }
    if ($decision.answerMode -ne 'abstain') { throw "Expected answerMode 'abstain'" }
    if (-not $decision.shouldAbstain) { throw "Expected shouldAbstain true" }
    if ($decision.abstainReason -ne "Insufficient evidence") { throw "Reason mismatch" }
    if ($decision.confidenceScore -ne 0.0) { throw "Expected confidence score 0.0" }
}

Test-Case -Name "Get-AbstainDecision includes alternatives" -Test {
    $alternatives = @{ suggestion = "Rephrase query"; escalate = $true }
    $decision = Get-AbstainDecision -Reason "Test" -Alternatives $alternatives
    
    if (-not $decision.alternatives) { throw "Missing alternatives" }
    if ($decision.alternatives.suggestion -ne "Rephrase query") { throw "Alternative mismatch" }
}

Test-Case -Name "Get-AbstainDecision includes evidence issues" -Test {
    $decision = Get-AbstainDecision -Reason "Test reason"
    
    if (-not $decision.evidenceIssues) { throw "Missing evidence issues" }
    if ($decision.evidenceIssues[0].type -ne 'abstention') { throw "Expected abstention issue type" }
}

#===============================================================================
# Test 6: Get-EscalationDecision
#===============================================================================
Test-Case -Name "Get-EscalationDecision creates valid escalation decision" -Test {
    $decision = Get-EscalationDecision -Reason "Security concern" -EscalationTarget "security-team"
    
    if (-not $decision) { throw "Decision is null" }
    if ($decision.answerMode -ne 'escalate') { throw "Expected answerMode 'escalate'" }
    if ($decision.escalationTarget -ne 'security-team') { throw "Target mismatch" }
    if ($decision.abstainReason -ne "Security concern") { throw "Reason mismatch" }
}

Test-Case -Name "Get-EscalationDecision includes context" -Test {
    $context = @{ query = "sensitive query"; userId = "user123" }
    $decision = Get-EscalationDecision -Reason "Test" -Context $context
    
    if (-not $decision.escalationContext) { throw "Missing escalation context" }
    if ($decision.escalationContext.query -ne "sensitive query") { throw "Context mismatch" }
}

Test-Case -Name "Get-EscalationDecision defaults to human-review target" -Test {
    $decision = Get-EscalationDecision -Reason "Test"
    
    if ($decision.escalationTarget -ne 'human-review') { throw "Expected default target 'human-review'" }
}

#===============================================================================
# Test 7: Test-AnswerConfidence (Integration)
#===============================================================================
Test-Case -Name "Test-AnswerConfidence returns complete decision" -Test {
    $evidence = @(
        @{ sourceId = "ev1"; relevanceScore = 0.95; sourceType = "core-runtime"; evidenceType = "code-example" },
        @{ sourceId = "ev2"; relevanceScore = 0.90; sourceType = "exemplar-pattern"; evidenceType = "tutorial" }
    )
    $plan = @{ 
        planId = "plan-123"
        confidencePolicy = @{}
    }
    
    $decision = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $plan -Context @{}
    
    if (-not $decision.evaluationId) { throw "Missing evaluationId" }
    if ($decision.confidenceScore -le 0) { throw "Expected positive confidence score" }
    if (-not $decision.components) { throw "Missing components" }
    if (-not $decision.reasoning) { throw "Missing reasoning" }
}

Test-Case -Name "Test-AnswerConfidence abstains with no evidence" -Test {
    $plan = @{ planId = "plan-123" }
    
    # Use empty array to test no evidence
    $decision = Test-AnswerConfidence -Evidence @() -AnswerPlan $plan -Context @{}
    
    if ($decision.answerMode -ne 'abstain') { throw "Expected abstain for no evidence" }
    if (-not $decision.shouldAbstain) { throw "Expected shouldAbstain true" }
}

Test-Case -Name "Test-AnswerConfidence handles high confidence evidence" -Test {
    $evidence = @(
        @{ sourceId = "ev1"; relevanceScore = 0.98; sourceType = "core-runtime"; evidenceType = "api-reference" },
        @{ sourceId = "ev2"; relevanceScore = 0.97; sourceType = "core-runtime"; evidenceType = "code-example" }
    )
    $plan = @{ planId = "plan-123" }
    
    $decision = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $plan -Context @{}
    
    if ($decision.confidenceScore -lt 0.80) { 
        throw "Expected high confidence score, got $($decision.confidenceScore)" 
    }
}

Test-Case -Name "Test-AnswerConfidence includes timestamp" -Test {
    $evidence = @(@{ sourceId = "ev1"; relevanceScore = 0.9; sourceType = "core-runtime" })
    $plan = @{ planId = "plan-123" }
    
    $decision = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $plan -Context @{}
    
    if (-not $decision.evaluatedAt) { throw "Missing evaluatedAt timestamp" }
    # Verify valid datetime format
    try {
        $null = [DateTime]::Parse($decision.evaluatedAt)
    }
    catch {
        throw "Invalid timestamp format: $($decision.evaluatedAt)"
    }
}

#===============================================================================
# Test 8: Merge-ConfidencePolicy
#===============================================================================
Test-Case -Name "Merge-ConfidencePolicy merges custom thresholds" -Test {
    $custom = @{ thresholds = @{ direct = 0.90; caveat = 0.75 } }
    $merged = Merge-ConfidencePolicy -CustomPolicy $custom
    
    if ($merged.thresholds.direct -ne 0.90) { throw "Expected direct threshold 0.90" }
    if ($merged.thresholds.caveat -ne 0.75) { throw "Expected caveat threshold 0.75" }
    # Other thresholds should retain defaults
    if ($merged.thresholds.abstain -ne 0.50) { throw "Expected abstain threshold to remain 0.50" }
}

Test-Case -Name "Merge-ConfidencePolicy sets policy name" -Test {
    $custom = @{ policyName = "custom-policy" }
    $merged = Merge-ConfidencePolicy -CustomPolicy $custom
    
    if ($merged.policyName -ne "custom-policy") { throw "Expected policy name 'custom-policy'" }
}

Test-Case -Name "Merge-ConfidencePolicy preserves default values" -Test {
    $custom = @{ minimumEvidenceCount = 3 }
    $merged = Merge-ConfidencePolicy -CustomPolicy $custom
    
    if ($merged.minimumEvidenceCount -ne 3) { throw "Expected minimumEvidenceCount 3" }
    # Weights should still be present
    if ($merged.weights.relevance -ne 0.40) { throw "Expected relevance weight to be preserved" }
}

#===============================================================================
# Test 9: Confidence Threshold Edge Cases
#===============================================================================
Test-Case -Name "Get-AnswerMode handles exact threshold boundaries" -Test {
    $policy = Get-DefaultConfidencePolicy
    
    # Test exact boundary values
    $mode85 = Get-AnswerMode -ConfidenceScore 0.85 -Policy $policy -EvidenceIssues @()
    $mode70 = Get-AnswerMode -ConfidenceScore 0.70 -Policy $policy -EvidenceIssues @()
    $mode50 = Get-AnswerMode -ConfidenceScore 0.50 -Policy $policy -EvidenceIssues @()
    
    if ($mode85 -ne 'direct') { throw "Expected 'direct' at 0.85" }
    if ($mode70 -ne 'caveat') { throw "Expected 'caveat' at 0.70" }
    if ($mode50 -ne 'caveat') { throw "Expected 'caveat' at 0.50 (borderline case)" }
}

Test-Case -Name "Get-AnswerMode handles zero confidence" -Test {
    $policy = Get-DefaultConfidencePolicy
    $mode = Get-AnswerMode -ConfidenceScore 0.0 -Policy $policy -EvidenceIssues @()
    
    if ($mode -ne 'abstain') { throw "Expected 'abstain' for zero confidence" }
}

Test-Case -Name "Get-AnswerMode handles maximum confidence" -Test {
    $policy = Get-DefaultConfidencePolicy
    $mode = Get-AnswerMode -ConfidenceScore 1.0 -Policy $policy -EvidenceIssues @()
    
    if ($mode -ne 'direct') { throw "Expected 'direct' for maximum confidence" }
}

#===============================================================================
# Test 10: Complex Scenarios
#===============================================================================
Test-Case -Name "Complex scenario: High confidence with contradictory evidence" -Test {
    $evidence = @(
        @{ sourceId = "core1"; relevanceScore = 0.95; sourceType = "core-runtime"; claim = "Approach A" },
        @{ sourceId = "core2"; relevanceScore = 0.95; sourceType = "core-runtime"; claim = "Approach B" }
    )
    $plan = @{ planId = "plan-123" }
    
    $decision = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $plan -Context @{}
    
    # Should detect dispute due to contradictory high-authority sources
    if ($decision.answerMode -ne 'dispute') { 
        # May also be caveat depending on implementation - both are acceptable
        if ($decision.answerMode -ne 'caveat') {
            throw "Expected 'dispute' or 'caveat' for contradictory high-authority evidence, got '$($decision.answerMode)'" 
        }
    }
}

Test-Case -Name "Complex scenario: Mixed trust tier sources" -Test {
    $evidence = @(
        @{ sourceId = "high1"; relevanceScore = 0.9; sourceType = "core-runtime"; trustTier = 'High' },
        @{ sourceId = "low1"; relevanceScore = 0.8; sourceType = "community"; trustTier = 'Low' }
    )
    $plan = @{ planId = "plan-123" }
    
    $decision = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $plan -Context @{}
    
    if ($decision.confidenceScore -le 0) { throw "Expected positive confidence" }
    # Should not abstain since we have high-trust source
    if ($decision.shouldAbstain) { throw "Should not abstain with high-trust source present" }
}

Test-Case -Name "Complex scenario: Deprecated evidence warning" -Test {
    $evidence = @(
        @{ sourceId = "old1"; relevanceScore = 0.9; sourceType = "core-runtime"; isDeprecated = $true },
        @{ sourceId = "new1"; relevanceScore = 0.85; sourceType = "core-runtime"; isDeprecated = $false }
    )
    $plan = @{ planId = "plan-123" }
    
    $decision = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $plan -Context @{}
    
    # Should identify deprecated evidence issue
    $deprecatedIssue = $decision.evidenceIssues | Where-Object { $_.type -eq 'deprecated-evidence' }
    if (-not $deprecatedIssue) { throw "Expected deprecated evidence issue" }
}

#===============================================================================
# Test Summary
#===============================================================================
Write-Host "`n" -NoNewline
Write-Host "=" * 60
Write-Host "Test Summary:" -ForegroundColor Cyan
Write-Host "  Passed: $($script:TestResults.Passed)" -ForegroundColor Green
Write-Host "  Failed: $($script:TestResults.Failed)" -ForegroundColor $(if($script:TestResults.Failed -gt 0){'Red'}else{'Green'})
Write-Host "=" * 60

if ($script:TestResults.Failed -gt 0) {
    exit 1
}
