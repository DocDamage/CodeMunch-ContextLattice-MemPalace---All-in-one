#requires -Version 5.1
<#
.SYNOPSIS
    Unit tests for ConfidencePolicy module.

.DESCRIPTION
    Tests the Phase 5 Confidence and Abstain Policy system.
    Covers confidence calculation, answer modes, abstention, and escalation.
#>

BeforeAll {
    $ErrorActionPreference = 'Stop'

    $modulePath = Join-Path $PSScriptRoot '../module/LLMWorkflow/retrieval/ConfidencePolicy.ps1'
    try {
        . $modulePath
    }
    catch {
        # Export-ModuleMember may throw when dot-sourcing; functions are still loaded
    }
}

Describe 'Get-DefaultConfidencePolicy' {
    It 'Get-DefaultConfidencePolicy returns valid policy' {
        $policy = Get-DefaultConfidencePolicy

        $policy | Should -Not -BeNullOrEmpty
        $policy.policyName | Should -Be 'default'
        $policy.schemaVersion | Should -Be 1
        $policy.thresholds | Should -Not -BeNullOrEmpty
        $policy.thresholds.direct | Should -Be 0.85
        $policy.thresholds.caveat | Should -Be 0.70
        $policy.thresholds.abstain | Should -Be 0.50
    }

    It 'Get-DefaultConfidencePolicy includes all required weights' {
        $policy = Get-DefaultConfidencePolicy

        $policy.weights | Should -Not -BeNullOrEmpty
        $policy.weights.relevance | Should -Be 0.40
        $policy.weights.authority | Should -Be 0.30
        $policy.weights.consistency | Should -Be 0.20
        $policy.weights.coverage | Should -Be 0.10
    }

    It 'Get-DefaultConfidencePolicy includes authority role weights' {
        $policy = Get-DefaultConfidencePolicy

        $policy.authorityRoleWeights | Should -Not -BeNullOrEmpty
        $policy.authorityRoleWeights['core-runtime'] | Should -Be 1.00
        $policy.authorityRoleWeights['community'] | Should -Be 0.50
    }
}

Describe 'Get-ConfidenceComponents' {
    It 'Get-ConfidenceComponents calculates all components' {
        $evidence = @(
            @{ sourceId = "ev1"; relevanceScore = 0.90; sourceType = "core-runtime"; evidenceType = "code-example" },
            @{ sourceId = "ev2"; relevanceScore = 0.85; sourceType = "exemplar-pattern"; evidenceType = "tutorial" }
        )

        $components = Get-ConfidenceComponents -Evidence $evidence -Context @{}

        $components.relevance | Should -Not -BeNullOrEmpty
        $components.authority | Should -Not -BeNullOrEmpty
        $components.consistency | Should -Not -BeNullOrEmpty
        $components.coverage | Should -Not -BeNullOrEmpty
    }

    It 'Get-ConfidenceComponents relevance is weighted correctly' {
        $evidence = @(
            @{ sourceId = "ev1"; relevanceScore = 1.0; sourceType = "core-runtime" }
        )

        $components = Get-ConfidenceComponents -Evidence $evidence -Context @{}

        $components.relevance.score | Should -BeGreaterOrEqual 0.35
    }

    It 'Get-ConfidenceComponents handles low relevance' {
        $evidence = @(
            @{ sourceId = "ev1"; relevanceScore = 0.3; sourceType = "core-runtime" },
            @{ sourceId = "ev2"; relevanceScore = 0.2; sourceType = "community" }
        )

        $components = Get-ConfidenceComponents -Evidence $evidence -Context @{}

        $components.relevance.score | Should -BeLessOrEqual 0.20
    }

    It 'Get-ConfidenceComponents detects contradictions' {
        $evidence = @(
            @{ sourceId = "ev1"; relevanceScore = 0.9; sourceType = "core-runtime"; claim = "A" },
            @{ sourceId = "ev2"; relevanceScore = 0.9; sourceType = "exemplar-pattern"; claim = "B" },
            @{ sourceId = "ev3"; relevanceScore = 0.8; sourceType = "community"; claim = "C" }
        )

        $components = Get-ConfidenceComponents -Evidence $evidence -Context @{}

        $components.consistency.details.distinctClaims | Should -BeGreaterOrEqual 2
    }
}

Describe 'Get-AnswerMode' {
    It "Get-AnswerMode returns 'direct' for high confidence" {
        $policy = Get-DefaultConfidencePolicy
        $mode = Get-AnswerMode -ConfidenceScore 0.90 -Policy $policy -EvidenceIssues @()

        $mode | Should -Be 'direct'
    }

    It "Get-AnswerMode returns 'caveat' for medium confidence" {
        $policy = Get-DefaultConfidencePolicy
        $mode = Get-AnswerMode -ConfidenceScore 0.75 -Policy $policy -EvidenceIssues @()

        $mode | Should -Be 'caveat'
    }

    It "Get-AnswerMode returns 'abstain' for low confidence" {
        $policy = Get-DefaultConfidencePolicy
        $mode = Get-AnswerMode -ConfidenceScore 0.40 -Policy $policy -EvidenceIssues @()

        $mode | Should -Be 'abstain'
    }

    It 'Get-AnswerMode escalates on policy violation' {
        $policy = Get-DefaultConfidencePolicy
        $issues = @(@{ type = 'policy-violation'; severity = 'critical'; description = 'Test violation' })
        $mode = Get-AnswerMode -ConfidenceScore 0.95 -Policy $policy -EvidenceIssues $issues

        $mode | Should -Be 'escalate'
    }

    It 'Get-AnswerMode escalates on boundary issue' {
        $policy = Get-DefaultConfidencePolicy
        $issues = @(@{ type = 'boundary-issue'; severity = 'high'; description = 'Security boundary' })
        $mode = Get-AnswerMode -ConfidenceScore 0.95 -Policy $policy -EvidenceIssues $issues

        $mode | Should -Be 'escalate'
    }

    It "Get-AnswerMode returns 'caveat' with major issues even at high confidence" {
        $policy = Get-DefaultConfidencePolicy
        $issues = @(@{ type = 'low-relevance'; severity = 'high'; description = 'Low relevance evidence' })
        $mode = Get-AnswerMode -ConfidenceScore 0.90 -Policy $policy -EvidenceIssues $issues

        $mode | Should -Be 'caveat'
    }
}

Describe 'Test-ShouldAbstain' {
    It 'Test-ShouldAbstain returns true for low confidence' {
        $policy = Get-DefaultConfidencePolicy
        $evidence = @(@{ sourceId = "ev1"; relevanceScore = 0.3 })

        $result = Test-ShouldAbstain -ConfidenceScore 0.40 -Evidence $evidence -Policy $policy

        $result | Should -Be $true
    }

    It 'Test-ShouldAbstain returns false for adequate confidence' {
        $policy = Get-DefaultConfidencePolicy
        $evidence = @(@{ sourceId = "ev1"; relevanceScore = 0.8 })

        $result = Test-ShouldAbstain -ConfidenceScore 0.70 -Evidence $evidence -Policy $policy

        $result | Should -Be $false
    }

    It 'Test-ShouldAbstain returns true for all low-trust sources' {
        $policy = Get-DefaultConfidencePolicy
        $evidence = @(
            @{ sourceId = "ev1"; relevanceScore = 0.6; trustTier = 'Low' },
            @{ sourceId = "ev2"; relevanceScore = 0.7; trustTier = 'Quarantined' }
        )

        $result = Test-ShouldAbstain -ConfidenceScore 0.65 -Evidence $evidence -Policy $policy

        $result | Should -Be $true
    }

    It 'Test-ShouldAbstain respects minimum evidence count' {
        $policy = Get-DefaultConfidencePolicy
        $policy.minimumEvidenceCount = 2
        $evidence = @(@{ sourceId = "ev1"; relevanceScore = 0.9 })

        $result = Test-ShouldAbstain -ConfidenceScore 0.90 -Evidence $evidence -Policy $policy

        $result | Should -Be $true
    }
}

Describe 'Get-AbstainDecision' {
    It 'Get-AbstainDecision creates valid abstain decision' {
        $decision = Get-AbstainDecision -Reason "Insufficient evidence" -Alternatives @{ suggestion = "Try again" }

        $decision | Should -Not -BeNullOrEmpty
        $decision.answerMode | Should -Be 'abstain'
        $decision.shouldAbstain | Should -Be $true
        $decision.abstainReason | Should -Be "Insufficient evidence"
        $decision.confidenceScore | Should -Be 0.0
    }

    It 'Get-AbstainDecision includes alternatives' {
        $alternatives = @{ suggestion = "Rephrase query"; escalate = $true }
        $decision = Get-AbstainDecision -Reason "Test" -Alternatives $alternatives

        $decision.alternatives | Should -Not -BeNullOrEmpty
        $decision.alternatives.suggestion | Should -Be "Rephrase query"
    }

    It 'Get-AbstainDecision includes evidence issues' {
        $decision = Get-AbstainDecision -Reason "Test reason"

        $decision.evidenceIssues | Should -Not -BeNullOrEmpty
        $decision.evidenceIssues[0].type | Should -Be 'abstention'
    }
}

Describe 'Get-EscalationDecision' {
    It 'Get-EscalationDecision creates valid escalation decision' {
        $decision = Get-EscalationDecision -Reason "Security concern" -EscalationTarget "security-team"

        $decision | Should -Not -BeNullOrEmpty
        $decision.answerMode | Should -Be 'escalate'
        $decision.escalationTarget | Should -Be 'security-team'
        $decision.abstainReason | Should -Be "Security concern"
    }

    It 'Get-EscalationDecision includes context' {
        $context = @{ query = "sensitive query"; userId = "user123" }
        $decision = Get-EscalationDecision -Reason "Test" -Context $context

        $decision.escalationContext | Should -Not -BeNullOrEmpty
        $decision.escalationContext.query | Should -Be "sensitive query"
    }

    It 'Get-EscalationDecision defaults to human-review target' {
        $decision = Get-EscalationDecision -Reason "Test"

        $decision.escalationTarget | Should -Be 'human-review'
    }
}

Describe 'Test-AnswerConfidence (Integration)' {
    It 'Test-AnswerConfidence returns complete decision' {
        $evidence = @(
            @{ sourceId = "ev1"; relevanceScore = 0.95; sourceType = "core-runtime"; evidenceType = "code-example" },
            @{ sourceId = "ev2"; relevanceScore = 0.90; sourceType = "exemplar-pattern"; evidenceType = "tutorial" }
        )
        $plan = @{
            planId = "plan-123"
            confidencePolicy = @{}
        }

        $decision = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $plan -Context @{}

        $decision.evaluationId | Should -Not -BeNullOrEmpty
        $decision.confidenceScore | Should -BeGreaterThan 0
        $decision.components | Should -Not -BeNullOrEmpty
        $decision.reasoning | Should -Not -BeNullOrEmpty
    }

    It 'Test-AnswerConfidence abstains with no evidence' {
        $plan = @{ planId = "plan-123" }

        $decision = Test-AnswerConfidence -Evidence @() -AnswerPlan $plan -Context @{}

        $decision.answerMode | Should -Be 'abstain'
        $decision.shouldAbstain | Should -Be $true
    }

    It 'Test-AnswerConfidence handles high confidence evidence' {
        $evidence = @(
            @{ sourceId = "ev1"; relevanceScore = 0.98; sourceType = "core-runtime"; evidenceType = "api-reference" },
            @{ sourceId = "ev2"; relevanceScore = 0.97; sourceType = "core-runtime"; evidenceType = "code-example" }
        )
        $plan = @{ planId = "plan-123" }

        $decision = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $plan -Context @{}

        $decision.confidenceScore | Should -BeGreaterOrEqual 0.80
    }

    It 'Test-AnswerConfidence includes timestamp' {
        $evidence = @(@{ sourceId = "ev1"; relevanceScore = 0.9; sourceType = "core-runtime" })
        $plan = @{ planId = "plan-123" }

        $decision = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $plan -Context @{}

        $decision.evaluatedAt | Should -Not -BeNullOrEmpty
        { $null = [DateTime]::Parse($decision.evaluatedAt) } | Should -Not -Throw
    }
}

Describe 'Merge-ConfidencePolicy' {
    It 'Merge-ConfidencePolicy merges custom thresholds' {
        $custom = @{ thresholds = @{ direct = 0.90; caveat = 0.75 } }
        $merged = Merge-ConfidencePolicy -CustomPolicy $custom

        $merged.thresholds.direct | Should -Be 0.90
        $merged.thresholds.caveat | Should -Be 0.75
        $merged.thresholds.abstain | Should -Be 0.50
    }

    It 'Merge-ConfidencePolicy sets policy name' {
        $custom = @{ policyName = "custom-policy" }
        $merged = Merge-ConfidencePolicy -CustomPolicy $custom

        $merged.policyName | Should -Be "custom-policy"
    }

    It 'Merge-ConfidencePolicy preserves default values' {
        $custom = @{ minimumEvidenceCount = 3 }
        $merged = Merge-ConfidencePolicy -CustomPolicy $custom

        $merged.minimumEvidenceCount | Should -Be 3
        $merged.weights.relevance | Should -Be 0.40
    }
}

Describe 'Confidence Threshold Edge Cases' {
    It 'Get-AnswerMode handles exact threshold boundaries' {
        $policy = Get-DefaultConfidencePolicy

        $mode85 = Get-AnswerMode -ConfidenceScore 0.85 -Policy $policy -EvidenceIssues @()
        $mode70 = Get-AnswerMode -ConfidenceScore 0.70 -Policy $policy -EvidenceIssues @()
        $mode50 = Get-AnswerMode -ConfidenceScore 0.50 -Policy $policy -EvidenceIssues @()

        $mode85 | Should -Be 'direct'
        $mode70 | Should -Be 'caveat'
        $mode50 | Should -Be 'caveat'
    }

    It 'Get-AnswerMode handles zero confidence' {
        $policy = Get-DefaultConfidencePolicy
        $mode = Get-AnswerMode -ConfidenceScore 0.0 -Policy $policy -EvidenceIssues @()

        $mode | Should -Be 'abstain'
    }

    It 'Get-AnswerMode handles maximum confidence' {
        $policy = Get-DefaultConfidencePolicy
        $mode = Get-AnswerMode -ConfidenceScore 1.0 -Policy $policy -EvidenceIssues @()

        $mode | Should -Be 'direct'
    }
}

Describe 'Complex Scenarios' {
    It 'Complex scenario: High confidence with contradictory evidence' {
        $evidence = @(
            @{ sourceId = "core1"; relevanceScore = 0.95; sourceType = "core-runtime"; claim = "Approach A" },
            @{ sourceId = "core2"; relevanceScore = 0.95; sourceType = "core-runtime"; claim = "Approach B" }
        )
        $plan = @{ planId = "plan-123" }

        $decision = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $plan -Context @{}

        $acceptableModes = @('dispute', 'caveat')
        $acceptableModes | Should -Contain $decision.answerMode
    }

    It 'Complex scenario: Mixed trust tier sources' {
        $evidence = @(
            @{ sourceId = "high1"; relevanceScore = 0.9; sourceType = "core-runtime"; trustTier = 'High' },
            @{ sourceId = "low1"; relevanceScore = 0.8; sourceType = "community"; trustTier = 'Low' }
        )
        $plan = @{ planId = "plan-123" }

        $decision = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $plan -Context @{}

        $decision.confidenceScore | Should -BeGreaterThan 0
        $decision.shouldAbstain | Should -Be $false
    }

    It 'Complex scenario: Deprecated evidence warning' {
        $evidence = @(
            @{ sourceId = "old1"; relevanceScore = 0.9; sourceType = "core-runtime"; isDeprecated = $true },
            @{ sourceId = "new1"; relevanceScore = 0.85; sourceType = "core-runtime"; isDeprecated = $false }
        )
        $plan = @{ planId = "plan-123" }

        $decision = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $plan -Context @{}

        $deprecatedIssue = $decision.evidenceIssues | Where-Object { $_.type -eq 'deprecated-evidence' }
        $deprecatedIssue | Should -Not -BeNullOrEmpty
    }
}
