#requires -Version 5.1
<#
.SYNOPSIS
    Unit tests for IncidentBundle module.

.DESCRIPTION
    Tests the Phase 5 Answer Incident Bundle system.
#>

BeforeAll {
    $ErrorActionPreference = 'Stop'

    $modulePath = Join-Path $PSScriptRoot '../module/LLMWorkflow/retrieval/IncidentBundle.ps1'
    $typeConvertersPath = Join-Path $PSScriptRoot '../module/LLMWorkflow/core/TypeConverters.ps1'
    $replayHarnessPath = Join-Path $PSScriptRoot '../module/LLMWorkflow/governance/ReplayHarness.ps1'

    try {
        if (Test-Path $typeConvertersPath) { . $typeConvertersPath }
        if (Test-Path $replayHarnessPath) { . $replayHarnessPath }
        . $modulePath
    }
    catch {
        # Export-ModuleMember may throw when dot-sourcing; functions are still loaded
    }
}

Describe 'New-AnswerIncidentBundle' {
    It 'New-AnswerIncidentBundle creates bundle with required fields' {
        $bundle = New-AnswerIncidentBundle -Query "How do I use X?" -FinalAnswer "You use X like this..."

        $bundle.incidentId | Should -Not -BeNullOrEmpty
        $bundle.createdAt | Should -Not -BeNullOrEmpty
        $bundle.status | Should -Be 'open'
        $bundle.bundle.query | Should -Be "How do I use X?"
        $bundle.bundle.finalAnswer | Should -Be "You use X like this..."
        $bundle.schemaVersion | Should -Be 1
    }
}

Describe 'Add-IncidentEvidence' {
    It 'Add-IncidentEvidence adds selected evidence' {
        $bundle = New-AnswerIncidentBundle -Query "Test query"
        $evidence = @{ source = 'doc1.md'; authority = 'official'; content = 'Important info' }

        $bundle = Add-IncidentEvidence -Incident $bundle -Evidence $evidence -Type 'selected'

        $bundle.bundle.selectedEvidence.Count | Should -Be 1
        $bundle.bundle.selectedEvidence[0].source | Should -Be 'doc1.md'
    }

    It 'Add-IncidentEvidence adds excluded evidence' {
        $bundle = New-AnswerIncidentBundle -Query "Test query"
        $evidence = @{ source = 'old-doc.md'; authority = 'community' }

        $bundle = Add-IncidentEvidence -Incident $bundle -Evidence $evidence -Type 'excluded'

        $bundle.bundle.excludedEvidence.Count | Should -Be 1
    }
}

Describe 'Add-IncidentFeedback' {
    It 'Add-IncidentFeedback links feedback to incident' {
        $bundle = New-AnswerIncidentBundle -Query "Test query"
        $bundle = Add-IncidentFeedback -Incident $bundle -FeedbackType 'thumbs-down' -FeedbackText 'This is wrong!'

        $bundle.bundle.linkedFeedback | Should -Not -BeNullOrEmpty
        $bundle.bundle.linkedFeedback.type | Should -Be 'thumbs-down'
        $bundle.bundle.linkedFeedback.text | Should -Be 'This is wrong!'
    }
}

Describe 'Export-IncidentBundle' {
    It 'Export-IncidentBundle saves to file' {
        $bundle = New-AnswerIncidentBundle -Query "Export test" -FinalAnswer "Test answer"
        $export = Export-IncidentBundle -Incident $bundle

        $export.Success | Should -Be $true
        Test-Path $export.Path | Should -Be $true

        Remove-Item $export.Path -Force
    }
}

Describe 'Import-IncidentBundle' {
    It 'Import-IncidentBundle loads from file' {
        $bundle = New-AnswerIncidentBundle -Query "Import test" -FinalAnswer "Test answer"
        $export = Export-IncidentBundle -Incident $bundle

        $loaded = Import-IncidentBundle -Path $export.Path

        $loaded.incidentId | Should -Be $bundle.incidentId
        $loaded.bundle.query | Should -Be $bundle.bundle.query

        Remove-Item $export.Path -Force
    }
}

Describe 'Get-IncidentBundle' {
    It 'Get-IncidentBundle retrieves by ID' {
        $bundle = New-AnswerIncidentBundle -Query "Get test" -FinalAnswer "Test answer"
        $export = Export-IncidentBundle -Incident $bundle

        $loaded = Get-IncidentBundle -IncidentId $bundle.incidentId

        $loaded | Should -Not -BeNullOrEmpty
        $loaded.incidentId | Should -Be $bundle.incidentId

        Remove-Item $export.Path -Force
    }
}

Describe 'Test-IncidentPattern' {
    It 'Test-IncidentPattern identifies known patterns' {
        $bundle = New-AnswerIncidentBundle -Query "Test query" -FinalAnswer "Answer"
        $bundle.bundle.confidenceDecision = @{ score = 0.5; shouldAbstain = $false }

        $patterns = Test-IncidentPattern -Incident $bundle

        $patterns | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-IncidentRootCause' {
    It 'Get-IncidentRootCause analyzes low-confidence incident' {
        $bundle = New-AnswerIncidentBundle -Query "Test query" -FinalAnswer "Low confidence answer"
        $bundle.bundle.confidenceDecision = @{ score = 0.5; shouldAbstain = $false }

        $analysis = Get-IncidentRootCause -Incident $bundle

        $analysis.Analysis | Should -Not -BeNullOrEmpty
        $analysis.Analysis.category | Should -Be 'low-confidence-should-abstain'
    }
}

Describe 'New-IncidentReport' {
    It 'New-IncidentReport generates text report' {
        $bundle = New-AnswerIncidentBundle -Query "Report test" -FinalAnswer "Test answer"
        $report = New-IncidentReport -Incident $bundle -Format Text

        $report.Length | Should -BeGreaterThan 100
        $report | Should -BeLike "*ANSWER INCIDENT REPORT*"
        $report | Should -BeLike "*Report test*"
    }

    It 'New-IncidentReport generates markdown report' {
        $bundle = New-AnswerIncidentBundle -Query "MD Report test" -FinalAnswer "Test answer"
        $report = New-IncidentReport -Incident $bundle -Format Markdown

        $report | Should -BeLike "# Answer Incident Report*"
        $report | Should -BeLike "*MD Report test*"
    }
}

Describe 'Export-IncidentAnalysis' {
    It 'Export-IncidentAnalysis creates governance report' {
        $bundle = New-AnswerIncidentBundle -Query "Gov test" -FinalAnswer "Test answer"
        $analysis = Get-IncidentRootCause -Incident $bundle
        $bundle = $analysis.UpdatedIncident

        $govReport = Export-IncidentAnalysis -Incident $bundle

        $govReport.reportType | Should -Be 'answer-incident-analysis'
        $govReport.incident.incidentId | Should -Be $bundle.incidentId
    }
}

Describe 'Invoke-IncidentReplay' {
    It 'Invoke-IncidentReplay creates replay record' {
        $bundle = New-AnswerIncidentBundle -Query "Replay test" -FinalAnswer "Original answer"

        $replay = Invoke-IncidentReplay -IncidentId $bundle.incidentId -NewSystemConfig @{ }

        $replay.replayId | Should -Not -BeNullOrEmpty
        $replay.incidentId | Should -Be $bundle.incidentId
        $replay.originalAnswer | Should -Be "Original answer"
    }
}

Describe 'Compare-IncidentReplay' {
    It 'Compare-IncidentReplay compares results' {
        $bundle = New-AnswerIncidentBundle -Query "Compare test" -FinalAnswer "Answer"
        $replay = Invoke-IncidentReplay -IncidentId $bundle.incidentId -NewSystemConfig @{ }

        $comparison = Compare-IncidentReplay -Incident $bundle -ReplayResult $replay

        $comparison.comparisonId | Should -Not -BeNullOrEmpty
        $comparison.incidentId | Should -Be $bundle.incidentId
    }
}

Describe 'Test-IncidentFixed' {
    It 'Test-IncidentFixed evaluates fix status' {
        $bundle = New-AnswerIncidentBundle -Query "Fix test" -FinalAnswer "Answer"
        $analysis = Get-IncidentRootCause -Incident $bundle
        $bundle = $analysis.UpdatedIncident

        $fixed = Test-IncidentFixed -Incident $bundle

        $fixed.Keys | Should -Contain 'isFixed'
    }
}

Describe 'Register-Incident' {
    It 'Register-Incident adds to registry' {
        $uniqueId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $bundle = New-AnswerIncidentBundle -Query "Register test $uniqueId" -FinalAnswer "Test answer"
        $reg = Register-Incident -Incident $bundle

        $reg.Success | Should -Be $true
        Test-Path $reg.Path | Should -Be $true

        Remove-Item $reg.Path -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Update-IncidentStatus' {
    It 'Update-IncidentStatus changes status' {
        $uniqueId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $bundle = New-AnswerIncidentBundle -Query "Status test $uniqueId" -FinalAnswer "Test answer"
        $reg = Register-Incident -Incident $bundle

        $update = Update-IncidentStatus -IncidentId $bundle.incidentId -Status 'investigating' -Notes 'Looking into it'

        $update.OldStatus | Should -Be 'open'
        $update.NewStatus | Should -Be 'investigating'

        $loaded = Get-IncidentBundle -IncidentId $bundle.incidentId
        $loaded.status | Should -Be 'investigating'

        Remove-Item $reg.Path -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IncidentMetrics' {
    It 'Get-IncidentMetrics calculates metrics' {
        $metrics = Get-IncidentMetrics

        $metrics.generatedAt | Should -Not -BeNullOrEmpty
        $metrics.summary | Should -Not -BeNullOrEmpty
        $metrics.summary.totalIncidents | Should -BeGreaterOrEqual 0
    }
}

Describe 'Search-IncidentBundles' {
    It 'Search-IncidentBundles filters by status' {
        $uniqueId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $bundle = New-AnswerIncidentBundle -Query "Search test $uniqueId" -FinalAnswer "Test answer"
        $reg = Register-Incident -Incident $bundle
        Update-IncidentStatus -IncidentId $bundle.incidentId -Status 'closed' | Out-Null

        $search = Search-IncidentBundles -Status 'closed'

        $found = $search | Where-Object { $_.incidentId -eq $bundle.incidentId }
        $found | Should -Not -BeNullOrEmpty

        Remove-Item $reg.Path -Force -ErrorAction SilentlyContinue
    }

    It 'Search-IncidentBundles filters by query pattern' {
        $uniqueId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $bundle = New-AnswerIncidentBundle -Query "UNIQUE_SEARCH_PATTERN_TEST_$uniqueId" -FinalAnswer "Test answer"
        $reg = Register-Incident -Incident $bundle

        $search = Search-IncidentBundles -QueryPattern "UNIQUE_SEARCH_PATTERN"

        $found = $search | Where-Object { $_.incidentId -eq $bundle.incidentId }
        $found | Should -Not -BeNullOrEmpty

        Remove-Item $reg.Path -Force -ErrorAction SilentlyContinue
    }
}
