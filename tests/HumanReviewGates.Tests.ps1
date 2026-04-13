#requires -Version 5.1
<#
.SYNOPSIS
    Unit tests for the Human Review Gates module.

.DESCRIPTION
    Tests the core functionality of the HumanReviewGates module including
    condition evaluators, review request management, and policy enforcement.
#>

BeforeAll {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    $modulePath = Join-Path $PSScriptRoot "..\module\LLMWorkflow\governance\HumanReviewGates.ps1"
    . $modulePath

    $script:testRequestId = $null
    $script:statePath = Join-Path $PSScriptRoot "..\.llm-workflow\state\review-gates.json"
    $script:stateBackupPath = Join-Path $PSScriptRoot "..\.llm-workflow\state\review-gates-backup-$([Guid]::NewGuid()).json"
    if (Test-Path $script:statePath) {
        Copy-Item $script:statePath $script:stateBackupPath -Force
    }
}

AfterAll {
    if (Test-Path $script:stateBackupPath) {
        Copy-Item $script:stateBackupPath $script:statePath -Force
        Remove-Item $script:stateBackupPath -Force
    }
}

Describe 'Module Loading' {
    It 'Module script loads successfully' {
        $cmd = Get-Command -Name Test-HumanReviewRequired -CommandType Function -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty
    }

    It 'All required functions are available' {
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
            $cmd | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Condition Evaluators' {
    It 'Test-MajorVersionJump detects major version change' {
        $result = Test-MajorVersionJump -OldVersion '1.0.0' -NewVersion '2.0.0'
        $result | Should -Be $true
    }

    It 'Test-MajorVersionJump ignores minor version change' {
        $result = Test-MajorVersionJump -OldVersion '1.0.0' -NewVersion '1.1.0'
        $result | Should -Be $false
    }

    It 'Test-MajorVersionJump ignores patch version change' {
        $result = Test-MajorVersionJump -OldVersion '1.0.0' -NewVersion '1.0.1'
        $result | Should -Be $false
    }

    It 'Test-LargeSourceDelta detects large delta' {
        $result = Test-LargeSourceDelta -ChangeSet @{ sourceDeltaPercent = 45 } -ThresholdPercent 30
        $result | Should -Be $true
    }

    It 'Test-LargeSourceDelta ignores small delta' {
        $result = Test-LargeSourceDelta -ChangeSet @{ sourceDeltaPercent = 15 } -ThresholdPercent 30
        $result | Should -Be $false
    }

    It 'Test-LargeSourceDelta handles missing data' {
        $result = Test-LargeSourceDelta -ChangeSet @{ otherField = 'value' } -ThresholdPercent 30
        $result | Should -Be $false
    }

    It 'Test-TrustTierChange detects trust tier changes list' {
        $result = Test-TrustTierChange -ChangeSet @{ trustTierChanges = @('change1', 'change2') }
        $result | Should -Be $true
    }

    It 'Test-TrustTierChange detects old vs new tier' {
        $result = Test-TrustTierChange -ChangeSet @{ oldTrustTier = 'A'; newTrustTier = 'B' }
        $result | Should -Be $true
    }

    It 'Test-TrustTierChange ignores identical tiers' {
        $result = Test-TrustTierChange -ChangeSet @{ oldTrustTier = 'A'; newTrustTier = 'A' }
        $result | Should -Be $false
    }

    It 'Test-VisibilityBoundaryChange detects visibility change flag' {
        $result = Test-VisibilityBoundaryChange -ChangeSet @{ visibilityChanged = $true }
        $result | Should -Be $true
    }

    It 'Test-VisibilityBoundaryChange detects old vs new visibility' {
        $result = Test-VisibilityBoundaryChange -ChangeSet @{ oldVisibility = 'private'; newVisibility = 'public' }
        $result | Should -Be $true
    }

    It 'Test-VisibilityBoundaryChange detects export boundary change' {
        $result = Test-VisibilityBoundaryChange -ChangeSet @{ exportBoundaryChanged = $true }
        $result | Should -Be $true
    }

    It 'Test-EvalRegression detects regression flag' {
        $evalResults = @(@{ regression = $true })
        $result = Test-EvalRegression -EvalResults $evalResults
        $result | Should -Be $true
    }

    It 'Test-EvalRegression detects high severity caveat' {
        $evalResults = @(@{ caveats = @(@{ severity = 'high' }) })
        $result = Test-EvalRegression -EvalResults $evalResults
        $result | Should -Be $true
    }

    It 'Test-EvalRegression detects score degradation' {
        $evalResults = @(@{ scoreDelta = -0.15 })
        $result = Test-EvalRegression -EvalResults $evalResults
        $result | Should -Be $true
    }

    It 'Test-EvalRegression ignores small score change' {
        $evalResults = @(@{ scoreDelta = -0.05 })
        $result = Test-EvalRegression -EvalResults $evalResults
        $result | Should -Be $false
    }
}

Describe 'Policy Management' {
    It 'Get-ReviewPolicy returns default pack-promotion policy' {
        $policy = Get-ReviewPolicy -PolicyName 'pack-promotion'
        $policy | Should -Not -BeNullOrEmpty
        $policy.triggers.largeSourceDelta.enabled | Should -Be $true
    }

    It 'Get-ReviewPolicy returns default source-ingestion policy' {
        $policy = Get-ReviewPolicy -PolicyName 'source-ingestion'
        $policy | Should -Not -BeNullOrEmpty
    }

    It 'Get-ReviewPolicy returns null for unknown policy' {
        $policy = Get-ReviewPolicy -PolicyName 'nonexistent-policy'
        $policy | Should -Be $null
    }
}

Describe 'Review Request Creation' {
    It 'New-ReviewGateRequest creates valid request' {
        $changeSet = @{
            packId = 'test-pack'
            oldVersion = '1.0.0'
            newVersion = '2.0.0'
        }

        $request = New-ReviewGateRequest -Operation 'pack-promotion' -ChangeSet $changeSet `
            -Requester 'testuser' -Justification 'Test request' -Reviewers @('reviewer1', 'reviewer2') `
            -Conditions @{ minApprovers = 2; requireOwnerApproval = $false }

        $request.requestId | Should -Not -BeNullOrEmpty
        $request.status | Should -Be 'pending'
        $request.operation | Should -Be 'pack-promotion'

        $script:testRequestId = $request.requestId
    }

    It 'Request ID follows expected format' {
        $script:testRequestId | Should -Not -BeNullOrEmpty
        $script:testRequestId | Should -Match '^review-\d{8}T\d{6}-[a-f0-9]{6}$'
    }

    It 'Get-ReviewStatus returns correct status for new request' {
        $status = Get-ReviewStatus -RequestId $script:testRequestId
        $status.Status | Should -Be 'pending'
        $status.Progress.Approvals | Should -Be 0
        $status.Progress.MinRequired | Should -BeGreaterOrEqual 1
    }
}

Describe 'Decision Submission' {
    It 'Submit-ReviewDecision accepts approval' {
        $result = Submit-ReviewDecision -RequestId $script:testRequestId -Reviewer 'reviewer1' `
            -Decision 'approved' -Comments 'Looks good'

        $result.Request.status | Should -Be 'pending'
    }

    It 'Get-ReviewStatus reflects approval' {
        $status = Get-ReviewStatus -RequestId $script:testRequestId
        $status.Progress.Approvals | Should -Be 1
        $status.Decisions.Count | Should -Be 1
    }

    It 'Submit-ReviewDecision accepts second approval and completes' {
        $result = Submit-ReviewDecision -RequestId $script:testRequestId -Reviewer 'reviewer2' `
            -Decision 'approved' -Comments 'Approved'

        $result.Request.status | Should -Be 'approved'
        $result.IsComplete | Should -Be $true
    }
}

Describe 'Review Detection' {
    It 'Test-HumanReviewRequired detects large source delta trigger' {
        $changeSet = @{
            packId = 'test-pack'
            oldVersion = '1.0.0'
            newVersion = '1.1.0'
            sourceDeltaPercent = 45
        }

        $result = Test-HumanReviewRequired -Operation 'pack-promotion' -ChangeSet $changeSet
        $result.Required | Should -Be $true
        $result.Triggers | Should -Contain 'large-source-delta'
    }

    It 'Test-HumanReviewRequired detects major version jump' {
        $changeSet = @{
            packId = 'test-pack'
            oldVersion = '1.0.0'
            newVersion = '2.0.0'
        }

        $result = Test-HumanReviewRequired -Operation 'pack-promotion' -ChangeSet $changeSet
        $result.Required | Should -Be $true
        $result.Triggers | Should -Contain 'major-version-jump'
    }

    It 'Test-HumanReviewRequired allows clean changes' {
        $changeSet = @{
            packId = 'test-pack'
            oldVersion = '1.0.0'
            newVersion = '1.0.1'
            sourceDeltaPercent = 5
        }

        $result = Test-HumanReviewRequired -Operation 'pack-promotion' -ChangeSet $changeSet
        $result.Required | Should -Be $false
    }
}

Describe 'Gate Check' {
    It 'Invoke-GateCheck auto-approves clean changes' {
        $uniquePack = 'gate-clean-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $context = @{
            packId = $uniquePack
            oldVersion = '1.0.0'
            newVersion = '1.0.1'
            sourceDeltaPercent = 5
        }

        $result = Invoke-GateCheck -GateName 'pack-promotion' -Context $context -AutoApproveIfClean
        $result.GateOpen | Should -Be $true
        $result.Status | Should -Be 'auto-approved'
    }

    It 'Invoke-GateCheck blocks on review triggers' {
        $uniquePack = 'gate-block-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $context = @{
            packId = $uniquePack
            oldVersion = '1.0.0'
            newVersion = '2.0.0'
            sourceDeltaPercent = 45
        }

        $result = Invoke-GateCheck -GateName 'pack-promotion' -Context $context
        $result.GateOpen | Should -Be $false
        $result.Status | Should -Be 'pending'
        $result.RequestId | Should -Not -BeNullOrEmpty
    }
}

Describe 'Pending Reviews Query' {
    It 'Get-PendingReviews returns pending requests' {
        $uniquePack = 'pending-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $changeSet = @{ packId = $uniquePack; oldVersion = '1.0.0'; newVersion = '1.0.1'; sourceDeltaPercent = 5 }
        $request = New-ReviewGateRequest -Operation 'pack-promotion' -ChangeSet $changeSet `
            -Requester 'testuser' -Justification 'Pending query test' -Reviewers @('reviewer1')

        $pending = Get-PendingReviews
        $pending | Where-Object { $_.requestId -eq $request.requestId } | Should -Not -BeNullOrEmpty
    }

    It 'Get-PendingReviews filters by reviewer' {
        $uniquePack = 'pending-filter-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $changeSet = @{ packId = $uniquePack; oldVersion = '1.0.0'; newVersion = '1.0.1'; sourceDeltaPercent = 5 }
        $request = New-ReviewGateRequest -Operation 'pack-promotion' -ChangeSet $changeSet `
            -Requester 'testuser' -Justification 'Filter test' -Reviewers @('reviewer1')

        $pending = Get-PendingReviews -Reviewer 'reviewer1'
        $pending | Where-Object { $_.requestId -eq $request.requestId } | Should -Not -BeNullOrEmpty
    }
}

Describe 'Policy Creation' {
    AfterAll {
        $state = Get-ReviewState
        if ($state.policies.ContainsKey('custom-test-policy')) {
            $state.policies.Remove('custom-test-policy')
            [void](Save-ReviewState -State $state)
        }
    }

    It 'New-ReviewPolicy creates custom policy' {
        $rules = @{
            largeSourceDelta = @{ enabled = $true; thresholdPercent = 50 }
            majorVersionJump = @{ enabled = $true }
        }

        $policy = New-ReviewPolicy -PolicyName 'custom-test-policy' -Rules $rules -DefaultReviewers @('admin1')
        $policy | Should -Not -BeNullOrEmpty
        $policy.triggers.largeSourceDelta.thresholdPercent | Should -Be 50
    }

    It 'Get-ReviewPolicy retrieves custom policy' {
        $policy = Get-ReviewPolicy -PolicyName 'custom-test-policy'
        $policy | Should -Not -BeNullOrEmpty
        $policy.defaultReviewers | Should -Contain 'admin1'
    }
}

Describe 'State Persistence' {
    It 'Review state file is created' {
        $statePath = Join-Path $PSScriptRoot "..\.llm-workflow\state\review-gates.json"
        Test-Path $statePath | Should -Be $true
    }

    It 'Review state has correct structure' {
        $state = Get-ReviewState
        $state.ContainsKey('requests') | Should -Be $true
        $state.ContainsKey('stats') | Should -Be $true
    }
}

Describe 'Escalation' {
    It 'Invoke-ReviewEscalation runs without error' {
        $escalated = Invoke-ReviewEscalation
        @($escalated).Count | Should -BeGreaterOrEqual 0
    }
}
