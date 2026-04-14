#requires -Version 5.1
<#
.SYNOPSIS
    Primitive tests for Journal.ps1
.DESCRIPTION
    Pester v5 tests for journaling, checkpoints, and run manifests.
#>

Describe 'Primitive.Journal Tests' {
BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..\module\LLMWorkflow\core\Journal.ps1'
    $script:RunIdPath = Join-Path $PSScriptRoot '..\module\LLMWorkflow\core\RunId.ps1'

    if (-not (Get-Command Test-RunIdFormat -ErrorAction SilentlyContinue)) {
        if (Test-Path $script:RunIdPath) {
            try { . $script:RunIdPath } catch { if ($_.Exception.Message -notlike '*Export-ModuleMember*') { throw } }
        }
    }
    if (-not (Get-Command Test-RunIdFormat -ErrorAction SilentlyContinue)) {
        function Test-RunIdFormat { param([string]$RunId) return $RunId -match '^\d{8}T\d{6}Z-[0-9a-f]{4}$' }
        function New-RunId { return '20260101T000000Z-0001' }
        function Get-CurrentRunId { return '20260101T000000Z-0001' }
    }

    if (Test-Path $script:ModulePath) {
        try { . $script:ModulePath } catch { if ($_.Exception.Message -notlike '*Export-ModuleMember*') { throw } }
    }
    else {
        throw "Module not found: $script:ModulePath"
    }

    $script:TestDir = Join-Path $TestDrive 'JournalTests'
    New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
}

AfterAll {
    if (Test-Path $script:TestDir) {
        Remove-Item -LiteralPath $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

AfterEach {
    Get-ChildItem -Path $script:TestDir -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Test-StepName' {
    It 'Returns true for valid step names' {
        Test-StepName -Step 'ingest' | Should -Be $true
        Test-StepName -Step 'my_step-123' | Should -Be $true
    }

    It 'Returns false for invalid step names' {
        Test-StepName -Step '' | Should -Be $false
        Test-StepName -Step 'bad name!' | Should -Be $false
    }
}

Describe 'New-RunManifest' {
    It 'Creates a manifest file atomically' {
        $manifestDir = Join-Path $script:TestDir 'manifests'
        $result = New-RunManifest -RunId '20260101T000000Z-0001' -Command 'sync' -Args @('--all') -ManifestDirectory $manifestDir
        $result | Should -Not -BeNullOrEmpty
        $result.command | Should -Be 'sync'
        $result.runId | Should -Be '20260101T000000Z-0001'
        Join-Path $manifestDir '20260101T000000Z-0001.run.json' | Should -Exist
    }

    It 'Throws on invalid RunId format' {
        { New-RunManifest -RunId 'bad-id' -Command 'sync' -ManifestDirectory $script:TestDir } | Should -Throw '*Invalid RunId*'
    }
}

Describe 'Complete-RunManifest' {
    It 'Updates manifest with exit code and completion timestamp' {
        $manifestDir = Join-Path $script:TestDir 'manifests2'
        New-RunManifest -RunId '20260101T000000Z-0002' -Command 'build' -ManifestDirectory $manifestDir | Out-Null
        $result = Complete-RunManifest -RunId '20260101T000000Z-0002' -ExitCode 0 -ManifestDirectory $manifestDir
        $result | Should -Not -BeNullOrEmpty
        $result.exitCode | Should -Be 0
        $result.exitStatus | Should -Be 'success'
        $result.completedAt | Should -Not -BeNullOrEmpty
    }

    It 'Returns null when manifest is missing' {
        $result = Complete-RunManifest -RunId '20260101T000000Z-9999' -ExitCode 0 -ManifestDirectory $script:TestDir
        $result | Should -BeNullOrEmpty
    }
}

Describe 'New-JournalEntry' {
    It 'Writes a journal entry and increments sequence' {
        $journalDir = Join-Path $script:TestDir 'journals'
        $e1 = New-JournalEntry -RunId '20260101T000000Z-0003' -Step 'ingest' -Status 'before' -JournalDirectory $journalDir
        $e1.sequence | Should -Be 0
        $e2 = New-JournalEntry -RunId '20260101T000000Z-0003' -Step 'ingest' -Status 'after' -JournalDirectory $journalDir
        $e2.sequence | Should -Be 1
        $e2.durationMs | Should -Not -BeNullOrEmpty
    }

    It 'Throws on invalid step name' {
        { New-JournalEntry -RunId '20260101T000000Z-0004' -Step 'bad name!' -Status 'before' -JournalDirectory $script:TestDir } | Should -Throw '*Invalid step name*'
    }
}

Describe 'Checkpoint-Journal / Complete-Checkpoint / Restore-FromCheckpoint' {
    It 'Creates a checkpoint and restores state' {
        $journalDir = Join-Path $script:TestDir 'journals2'
        $cp = Checkpoint-Journal -RunId '20260101T000000Z-0005' -Step 'export' -State @{ count = 5 } -JournalDirectory $journalDir
        $cp.CanResume | Should -Be $true
        $cp.Step | Should -Be 'export'

        $restored = Restore-FromCheckpoint -RunId '20260101T000000Z-0005' -Step 'export' -JournalDirectory $journalDir
        $restored | Should -Not -BeNullOrEmpty
        $restored.State.count | Should -Be 5

        Complete-Checkpoint -RunId '20260101T000000Z-0005' -Step 'export' -JournalDirectory $journalDir | Out-Null
        $after = Restore-FromCheckpoint -RunId '20260101T000000Z-0005' -Step 'export' -JournalDirectory $journalDir
        $after | Should -BeNullOrEmpty
    }
}

Describe 'Get-JournalState' {
    It 'Returns resume state for an existing journal' {
        $journalDir = Join-Path $script:TestDir 'journals3'
        $manifestDir = Join-Path $script:TestDir 'manifests3'
        New-RunManifest -RunId '20260101T000000Z-0006' -Command 'test' -ManifestDirectory $manifestDir | Out-Null
        Checkpoint-Journal -RunId '20260101T000000Z-0006' -Step 'ingest' -State @{} -JournalDirectory $journalDir | Out-Null

        $state = Get-JournalState -RunId '20260101T000000Z-0006' -JournalDirectory $journalDir -ManifestDirectory $manifestDir
        $state.Exists | Should -Be $true
        $state.CanResume | Should -Be $true
        $state.PendingSteps | Should -Contain 'ingest'
    }

    It 'Returns non-existent result for missing journal' {
        $state = Get-JournalState -RunId '20260101T000000Z-9999' -JournalDirectory $script:TestDir
        $state.Exists | Should -Be $false
    }
}

Describe 'Export-JournalReport' {
    It 'Generates a text report for existing journal' {
        $journalDir = Join-Path $script:TestDir 'journals4'
        $manifestDir = Join-Path $script:TestDir 'manifests4'
        New-RunManifest -RunId '20260101T000000Z-0007' -Command 'test' -ManifestDirectory $manifestDir | Out-Null
        Checkpoint-Journal -RunId '20260101T000000Z-0007' -Step 'ingest' -State @{} -JournalDirectory $journalDir | Out-Null
        Complete-Checkpoint -RunId '20260101T000000Z-0007' -Step 'ingest' -JournalDirectory $journalDir | Out-Null

        $report = Export-JournalReport -RunId '20260101T000000Z-0007' -JournalDirectory $journalDir -ManifestDirectory $manifestDir -Format text
        $report | Should -Not -BeNullOrEmpty
        $report | Should -Match 'Journal Report'
    }

    It 'Returns not-found message for missing journal' {
        $report = Export-JournalReport -RunId '20260101T000000Z-9999' -JournalDirectory $script:TestDir -Format text
        $report | Should -Match 'not found|Journal not found'
    }
}

Describe 'Write-JournalEntry' {
    It 'Atomically writes a journal entry with verification' {
        $journalDir = Join-Path $script:TestDir 'journals5'
        $result = Write-JournalEntry -RunId '20260101T000000Z-0008' -Step 'sync' -Status 'start' -JournalDirectory $journalDir -VerifyWrite
        $result.Success | Should -Be $true
        $result.LineNumber | Should -BeGreaterThan 0
    }
}

Describe 'Rotate-Journal' {
    It 'Rotates an existing journal to archive' {
        $journalDir = Join-Path $script:TestDir 'journals6'
        Write-JournalEntry -RunId '20260101T000000Z-0009' -Step 'sync' -Status 'start' -JournalDirectory $journalDir | Out-Null
        $result = Rotate-Journal -RunId '20260101T000000Z-0009' -JournalDirectory $journalDir -Force
        $result.Success | Should -Be $true
        $result.Rotated | Should -Be $true
        $result.ArchivedPath | Should -Exist
    }

    It 'Returns no-rotate result when journal does not exist' {
        $result = Rotate-Journal -RunId '20260101T000000Z-9999' -JournalDirectory $script:TestDir -Force
        $result.Success | Should -Be $true
        $result.Rotated | Should -Be $false
    }
}

Describe 'Test-JournalIntegrity' {
    It 'Validates a correct journal' {
        $journalDir = Join-Path $script:TestDir 'journals7'
        Write-JournalEntry -RunId '20260101T000000Z-0010' -Step 'sync' -Status 'start' -JournalDirectory $journalDir | Out-Null
        Write-JournalEntry -RunId '20260101T000000Z-0010' -Step 'sync' -Status 'complete' -JournalDirectory $journalDir | Out-Null

        $result = Test-JournalIntegrity -RunId '20260101T000000Z-0010' -JournalDirectory $journalDir
        $result.IsValid | Should -Be $true
        $result.CheckResults.ValidJson | Should -Be $true
        $result.CheckResults.SequenceValid | Should -Be $true
    }

    It 'Reports invalid for missing journal' {
        $result = Test-JournalIntegrity -RunId '20260101T000000Z-9999' -JournalDirectory $script:TestDir
        $result.IsValid | Should -Be $false
        ($result.Errors | Where-Object { $_ -like '*not found*' }) | Should -Not -BeNullOrEmpty
    }
}

Describe 'Add-RunArtifact' {
    It 'Appends artifact to run manifest' {
        $manifestDir = Join-Path $script:TestDir 'manifests5'
        New-RunManifest -RunId '20260101T000000Z-0011' -Command 'test' -ManifestDirectory $manifestDir | Out-Null
        Add-RunArtifact -RunId '20260101T000000Z-0011' -ArtifactPath 'output.txt' -ArtifactType 'file' -ManifestDirectory $manifestDir

        $manifest = Get-Content -LiteralPath (Join-Path $manifestDir '20260101T000000Z-0011.run.json') -Raw | ConvertFrom-Json
        $manifest.artifactsWritten | Should -Not -BeNullOrEmpty
        $manifest.artifactsWritten[0].path | Should -Be 'output.txt'
    }
}
}