#requires -Version 5.1
<#
.SYNOPSIS
    Core Module Tests for LLM Workflow Platform

.DESCRIPTION
    Pester v5 test suite for core infrastructure modules:
    - FileLock.ps1: File locking and concurrency control
    - Journal.ps1: Journaling and checkpoint functions
    - AtomicWrite.ps1: Atomic file write operations

.NOTES
    File: CoreModule.Tests.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Requires: Pester 5.0+
#>

BeforeAll {
    # Set up test environment
    $tempRoot = [System.IO.Path]::GetTempPath()
    $script:TestRoot = Join-Path $tempRoot "CoreModuleTests_$([Guid]::NewGuid().ToString('N'))"
    $script:ModuleRoot = Join-Path (Join-Path $PSScriptRoot "..") "module" | Join-Path -ChildPath "LLMWorkflow"
    $script:CoreModulePath = Join-Path $script:ModuleRoot "core"

    # Create test directories
    New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:TestRoot ".llm-workflow") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:TestRoot ".llm-workflow") "locks") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:TestRoot ".llm-workflow") "journals") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:TestRoot ".llm-workflow") "manifests") -Force | Out-Null

    # Import modules
    $fileLockPath = Join-Path $script:CoreModulePath "FileLock.ps1"
    $journalPath = Join-Path $script:CoreModulePath "Journal.ps1"
    $atomicWritePath = Join-Path $script:CoreModulePath "AtomicWrite.ps1"
    $runIdPath = Join-Path $script:CoreModulePath "RunId.ps1"

    if (Test-Path $fileLockPath) { try { . $fileLockPath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
    if (Test-Path $journalPath) { try { . $journalPath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
    if (Test-Path $atomicWritePath) { try { . $atomicWritePath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
    if (Test-Path $runIdPath) { try { . $runIdPath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }

    if (-not (Get-Command Get-ExecutionMode -ErrorAction SilentlyContinue)) {
        function Get-ExecutionMode {
            return "interactive"
        }
    }
}

Describe "FileLock Module Tests" {
    BeforeEach {
        # Clean up any existing locks
        $locksDir = Join-Path (Join-Path $script:TestRoot ".llm-workflow") "locks"
        if (Test-Path $locksDir) {
            Remove-Item -Path "$locksDir\*.lock" -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Lock-File Function" {
        It "Should acquire and release a lock successfully" {
            $lock = Lock-File -Name "sync" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot
            $lock | Should -Not -BeNullOrEmpty
            $lock.Name | Should -Be "sync"
            $lock.RunId | Should -Not -BeNullOrEmpty
            
            # Release the lock
            $released = Unlock-File -Name "sync" -ProjectRoot $script:TestRoot
            $released | Should -Be $true
        }

        It "Should throw when acquiring already held lock without -Force" {
            $lock1 = Lock-File -Name "index" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot
            $lock1 | Should -Not -BeNullOrEmpty
            
            { Lock-File -Name "index" -TimeoutSeconds 1 -ProjectRoot $script:TestRoot } | 
                Should -Throw -ExpectedMessage "*already held*"
            
            Unlock-File -Name "index" -ProjectRoot $script:TestRoot | Out-Null
        }

        It "Should allow nested locking with -Force" {
            $lock1 = Lock-File -Name "pack" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot
            $lock1 | Should -Not -BeNullOrEmpty
            
            $lock2 = Lock-File -Name "pack" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot -Force
            $lock2 | Should -Not -BeNullOrEmpty
            
            Unlock-File -Name "pack" -ProjectRoot $script:TestRoot | Out-Null
        }

        It "Should return null on timeout when lock is held by another" {
            # Simulate another process holding the lock
            $lockFile = Join-Path (Join-Path (Join-Path $script:TestRoot ".llm-workflow") "locks") "ingest.lock"
            $otherLockContent = @{
                schemaVersion = 1
                pid = 99999
                host = "remote-test-host"
                executionMode = "ci"
                runId = "20260401T000000Z-0000"
                timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
                user = "otheruser"
            } | ConvertTo-Json
            
            # Create directory if needed
            $lockDir = Split-Path -Parent $lockFile
            if (-not (Test-Path $lockDir)) {
                New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
            }
            [System.IO.File]::WriteAllText($lockFile, $otherLockContent)
            
            $result = Lock-File -Name "ingest" -TimeoutSeconds 0 -ProjectRoot $script:TestRoot
            $result | Should -BeNullOrEmpty
            
            Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
        }

        It "Should throw on invalid lock name" {
            { Lock-File -Name "invalid-lock-name" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot } | 
                Should -Throw -ExpectedMessage "*Invalid lock name*"
        }
    }

    Context "Test-FileLock Function" {
        It "Should detect existing locks" {
            # Initially no lock
            Test-FileLock -Name "heal" -ProjectRoot $script:TestRoot | Should -Be $false
            
            # Acquire lock
            $lock = Lock-File -Name "heal" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot
            
            # Should detect lock
            Test-FileLock -Name "heal" -ProjectRoot $script:TestRoot | Should -Be $true
            
            Unlock-File -Name "heal" -ProjectRoot $script:TestRoot | Out-Null
        }

        It "Should exclude stale locks by default" {
            # Create a stale lock (old timestamp)
            $lockFile = Join-Path (Join-Path (Join-Path $script:TestRoot ".llm-workflow") "locks") "sync.lock"
            $staleLockContent = @{
                schemaVersion = 1
                pid = 99999
                host = ([Environment]::MachineName).ToLowerInvariant()
                executionMode = "ci"
                runId = "20260401T000000Z-0000"
                timestamp = [DateTime]::UtcNow.AddHours(-2).ToString("yyyy-MM-ddTHH:mm:ssZ")
                user = "testuser"
            } | ConvertTo-Json
            
            $lockDir = Split-Path -Parent $lockFile
            if (-not (Test-Path $lockDir)) {
                New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
            }
            [System.IO.File]::WriteAllText($lockFile, $staleLockContent)
            
            # Should not detect stale lock by default
            Test-FileLock -Name "sync" -ProjectRoot $script:TestRoot | Should -Be $false
            
            # Should detect with IncludeStale
            Test-FileLock -Name "sync" -ProjectRoot $script:TestRoot -IncludeStale | Should -Be $true
            
            Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Remove-StaleLock Function" {
        It "Should reclaim stale locks" {
            # Create a stale lock
            $lockFile = Join-Path (Join-Path (Join-Path $script:TestRoot ".llm-workflow") "locks") "index.lock"
            $staleLockContent = @{
                schemaVersion = 1
                pid = 99999
                host = ([Environment]::MachineName).ToLowerInvariant()
                executionMode = "ci"
                runId = "20260401T000000Z-0000"
                timestamp = [DateTime]::UtcNow.AddHours(-2).ToString("yyyy-MM-ddTHH:mm:ssZ")
                user = "testuser"
            } | ConvertTo-Json
            
            $lockDir = Split-Path -Parent $lockFile
            if (-not (Test-Path $lockDir)) {
                New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
            }
            [System.IO.File]::WriteAllText($lockFile, $staleLockContent)
            
            # Verify lock is stale
            Test-StaleLock -Name "index" -ProjectRoot $script:TestRoot | Should -Be $true
            
            # Remove stale lock
            $removed = Remove-StaleLock -Name "index" -ProjectRoot $script:TestRoot -Force
            $removed | Should -Be $true
            
            # Verify lock is gone
            Test-Path $lockFile | Should -Be $false
        }

        It "Should return false for non-stale locks" {
            # Acquire a valid lock
            $lock = Lock-File -Name "pack" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot
            
            # Should not be stale
            Test-StaleLock -Name "pack" -ProjectRoot $script:TestRoot | Should -Be $false
            
            # Should not remove
            Remove-StaleLock -Name "pack" -ProjectRoot $script:TestRoot -Force | Should -Be $false
            
            Unlock-File -Name "pack" -ProjectRoot $script:TestRoot | Out-Null
        }

        It "Should support CheckOnly mode" {
            # Create a stale lock
            $lockFile = Join-Path (Join-Path (Join-Path $script:TestRoot ".llm-workflow") "locks") "ingest.lock"
            $staleLockContent = @{
                schemaVersion = 1
                pid = 99999
                host = ([Environment]::MachineName).ToLowerInvariant()
                executionMode = "ci"
                runId = "20260401T000000Z-0000"
                timestamp = [DateTime]::UtcNow.AddHours(-2).ToString("yyyy-MM-ddTHH:mm:ssZ")
                user = "testuser"
            } | ConvertTo-Json
            
            $lockDir = Split-Path -Parent $lockFile
            if (-not (Test-Path $lockDir)) {
                New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
            }
            [System.IO.File]::WriteAllText($lockFile, $staleLockContent)
            
            # CheckOnly should return true but not remove
            Remove-StaleLock -Name "ingest" -ProjectRoot $script:TestRoot -CheckOnly | Should -Be $true
            Test-Path $lockFile | Should -Be $true
            
            Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Cross-Platform Compatibility" {
        It "Should create lock files with correct schema" {
            $lock = Lock-File -Name "sync" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot
            $lock.Content | Should -Not -BeNullOrEmpty
            $lock.Content.schemaVersion | Should -Be 1
            $lock.Content.pid | Should -Be $PID
            $lock.Content.host | Should -Be ([Environment]::MachineName).ToLowerInvariant()
            $lock.Content.runId | Should -Not -BeNullOrEmpty
            $lock.Content.timestamp | Should -Not -BeNullOrEmpty
            $lock.Content.executionMode | Should -Not -BeNullOrEmpty
            
            Unlock-File -Name "sync" -ProjectRoot $script:TestRoot | Out-Null
        }

        It "Should handle hosts with different case" {
            $lockFile = Join-Path (Join-Path (Join-Path $script:TestRoot ".llm-workflow") "locks") "heal.lock"
            $lockContent = @{
                schemaVersion = 1
                pid = $PID
                host = ([Environment]::MachineName).ToUpperInvariant()
                executionMode = "interactive"
                runId = "20260401T000000Z-0000"
                timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
                user = "testuser"
            } | ConvertTo-Json
            
            $lockDir = Split-Path -Parent $lockFile
            if (-not (Test-Path $lockDir)) {
                New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
            }
            [System.IO.File]::WriteAllText($lockFile, $lockContent)
            
            # Should recognize as our lock regardless of case
            $lock = Lock-File -Name "heal" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot -Force
            $lock | Should -Not -BeNullOrEmpty
            
            Unlock-File -Name "heal" -ProjectRoot $script:TestRoot | Out-Null
        }
    }
}

Describe "Journal Module Tests" {
    BeforeAll {
        $script:JournalDir = Join-Path (Join-Path $script:TestRoot ".llm-workflow") "journals"
        $script:ManifestDir = Join-Path (Join-Path $script:TestRoot ".llm-workflow") "manifests"
    }

    Context "New-JournalEntry Function" {
        It "Should create valid journal entries" {
            $runId = "20260413T000000Z-abcd"
            $entry = New-JournalEntry -RunId $runId -Step "ingest" -Status "before" `
                -Metadata @{ source = "github" } `
                -State @{ filesProcessed = 0 } `
                -JournalDirectory $script:JournalDir
            
            $entry | Should -Not -BeNullOrEmpty
            $entry.schemaVersion | Should -Be 1
            $entry.runId | Should -Be $runId
            $entry.step | Should -Be "ingest"
            $entry.status | Should -Be "before"
            $entry.metadata.source | Should -Be "github"
            $entry.state.filesProcessed | Should -Be 0
        }

        It "Should calculate duration for after entries" {
            $runId = "20260413T000001Z-ef01"
            
            # Create before entry
            $beforeEntry = New-JournalEntry -RunId $runId -Step "ingest" -Status "before" `
                -JournalDirectory $script:JournalDir
            
            Start-Sleep -Milliseconds 50
            
            # Create after entry
            $afterEntry = New-JournalEntry -RunId $runId -Step "ingest" -Status "after" `
                -JournalDirectory $script:JournalDir
            
            $afterEntry.durationMs | Should -Not -BeNullOrEmpty
            $afterEntry.durationMs | Should -BeGreaterOrEqual 0
        }

        It "Should create valid JSON-lines output" {
            $runId = "20260413T000002Z-ab12"
            
            New-JournalEntry -RunId $runId -Step "step1" -Status "before" `
                -JournalDirectory $script:JournalDir | Out-Null
            New-JournalEntry -RunId $runId -Step "step1" -Status "after" `
                -JournalDirectory $script:JournalDir | Out-Null
            
            $journalPath = Join-Path $script:JournalDir "$runId.journal.json"
            Test-Path $journalPath | Should -Be $true
            
            $content = Get-Content -Path $journalPath -Raw
            $entries = $content | ConvertFrom-Json
            $entries.Count | Should -Be 2
        }
    }

    Context "Get-JournalState Function" {
        It "Should return resumable state" {
            $runId = "20260413T000003Z-cd34"
            
            # Create a complete manifest first
            $manifest = New-RunManifest -RunId $runId -Command "sync" `
                -Args @("--all") -ManifestDirectory $script:ManifestDir
            
            # Create journal entries
            New-JournalEntry -RunId $runId -Step "ingest" -Status "before" `
                -JournalDirectory $script:JournalDir | Out-Null
            New-JournalEntry -RunId $runId -Step "ingest" -Status "after" `
                -JournalDirectory $script:JournalDir | Out-Null
            New-JournalEntry -RunId $runId -Step "embed" -Status "before" `
                -JournalDirectory $script:JournalDir | Out-Null
            
            $state = Get-JournalState -RunId $runId `
                -JournalDirectory $script:JournalDir `
                -ManifestDirectory $script:ManifestDir
            
            $state | Should -Not -BeNullOrEmpty
            $state.RunId | Should -Be $runId
            $state.Exists | Should -Be $true
            $state.CanResume | Should -Be $true
            $state.CompletedSteps | Should -Contain "ingest"
            $state.PendingSteps | Should -Contain "embed"
            $state.LastCheckpoint | Should -Not -BeNullOrEmpty
        }

        It "Should detect completed runs" {
            $runId = "20260413T000004Z-de45"
            
            $manifest = New-RunManifest -RunId $runId -Command "build" `
                -ManifestDirectory $script:ManifestDir
            
            New-JournalEntry -RunId $runId -Step "start" -Status "start" `
                -JournalDirectory $script:JournalDir | Out-Null
            New-JournalEntry -RunId $runId -Step "complete" -Status "complete" `
                -JournalDirectory $script:JournalDir | Out-Null
            
            $state = Get-JournalState -RunId $runId `
                -JournalDirectory $script:JournalDir `
                -ManifestDirectory $script:ManifestDir
            
            $state.IsComplete | Should -Be $true
            $state.CanResume | Should -Be $false
        }

        It "Should return correct state for non-existent run" {
            $state = Get-JournalState -RunId "20260413T235959Z-beef" `
                -JournalDirectory $script:JournalDir `
                -ManifestDirectory $script:ManifestDir
            
            $state.Exists | Should -Be $false
            $state.CanResume | Should -Be $false
        }
    }

    Context "Journal Format Schema Validation" {
        It "Should follow schemaVersion in all entries" {
            $runId = "20260413T000005Z-ae56"
            
            $entry = New-JournalEntry -RunId $runId -Step "test" -Status "before" `
                -JournalDirectory $script:JournalDir
            
            $entry.schemaVersion | Should -Be 1
            $entry.updatedUtc | Should -Not -BeNullOrEmpty
            $entry.createdByRunId | Should -Be $runId
        }

        It "Should include timestamps in ISO 8601 format" {
            $runId = "20260413T000006Z-bf67"
            
            $entry = New-JournalEntry -RunId $runId -Step "test" -Status "before" `
                -JournalDirectory $script:JournalDir
            
            $entry.timestamp | Should -Match "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"
        }
    }

    Context "Complete-RunManifest Function" {
        It "Should complete manifest with correct exit status" {
            $runId = "20260413T000007Z-2345"
            
            $manifest = New-RunManifest -RunId $runId -Command "sync" `
                -ManifestDirectory $script:ManifestDir
            
            $completed = Complete-RunManifest -RunId $runId -ExitCode 0 `
                -Warnings @("Warning 1") -Errors @() `
                -ManifestDirectory $script:ManifestDir
            
            $completed | Should -Not -BeNullOrEmpty
            $completed.exitStatus | Should -Be "success"
            $completed.exitCode | Should -Be 0
            $completed.completedAt | Should -Not -BeNullOrEmpty
        }

        It "Should handle different exit codes correctly" {
            $runId = "20260413T000008Z-6789"
            
            New-RunManifest -RunId $runId -Command "build" `
                -ManifestDirectory $script:ManifestDir | Out-Null
            
            $completed1 = Complete-RunManifest -RunId $runId -ExitCode 1 `
                -ManifestDirectory $script:ManifestDir
            $completed1.exitStatus | Should -Be "failure"
            
            $runId2 = "20260413T000009Z-abcd"
            New-RunManifest -RunId $runId2 -Command "build" `
                -ManifestDirectory $script:ManifestDir | Out-Null
            $completed6 = Complete-RunManifest -RunId $runId2 -ExitCode 6 `
                -ManifestDirectory $script:ManifestDir
            $completed6.exitStatus | Should -Be "partial"
            
            $runId3 = "20260413T000010Z-ce89"
            New-RunManifest -RunId $runId3 -Command "build" `
                -ManifestDirectory $script:ManifestDir | Out-Null
            $completed12 = Complete-RunManifest -RunId $runId3 -ExitCode 12 `
                -ManifestDirectory $script:ManifestDir
            $completed12.exitStatus | Should -Be "aborted"
        }
    }
}

Describe "AtomicWrite Module Tests" {
    BeforeAll {
        $script:AtomicTestDir = Join-Path $script:TestRoot "atomic-tests"
        if (-not (Test-Path $script:AtomicTestDir)) {
            New-Item -ItemType Directory -Path $script:AtomicTestDir -Force | Out-Null
        }
    }

    Context "Write-AtomicFile Function" {
        It "Should write files atomically" {
            $testPath = Join-Path $script:AtomicTestDir "atomic-test.txt"
            $content = "Test content for atomic write"
            
            $result = Write-AtomicFile -Path $testPath -Content $content
            
            $result.Success | Should -Be $true
            $result.Path | Should -Be $testPath
            $result.BytesWritten | Should -BeGreaterThan 0
            
            Get-Content -Path $testPath -Raw | Should -Be $content
        }

        It "Should write JSON files correctly" {
            $testPath = Join-Path $script:AtomicTestDir "atomic-test.json"
            $data = @{ name = "test"; value = 42; nested = @{ key = "value" } }
            
            $result = Write-AtomicFile -Path $testPath -Content $data -Format Json
            
            $result.Success | Should -Be $true
            
            $readData = Get-Content -Path $testPath -Raw | ConvertFrom-Json
            $readData.name | Should -Be "test"
            $readData.value | Should -Be 42
            $readData.nested.key | Should -Be "value"
        }

        It "Should write byte arrays correctly" {
            $testPath = Join-Path $script:AtomicTestDir "atomic-test.bin"
            $bytes = [byte[]]@(0x00, 0x01, 0x02, 0x03, 0xFF)
            
            $result = Write-AtomicFile -Path $testPath -Content $bytes -Format Bytes
            
            $result.Success | Should -Be $true
            $result.BytesWritten | Should -Be 5
            
            $readBytes = [System.IO.File]::ReadAllBytes($testPath)
            $readBytes.Length | Should -Be 5
            $readBytes[0] | Should -Be 0x00
            $readBytes[4] | Should -Be 0xFF
        }

        It "Should create parent directories if needed" {
            $testPath = Join-Path (Join-Path (Join-Path $script:AtomicTestDir "nested") "deep") "file.txt"
            $content = "Deep nested content"
            
            $result = Write-AtomicFile -Path $testPath -Content $content
            
            $result.Success | Should -Be $true
            Test-Path $testPath | Should -Be $true
        }
    }

    Context "Backup and Rollback" {
        It "Should create backup before destructive writes" {
            $testPath = Join-Path $script:AtomicTestDir "backup-test.txt"
            $originalContent = "Original content"
            $newContent = "New content"
            
            # Create original file
            Write-AtomicFile -Path $testPath -Content $originalContent | Out-Null
            
            # Write with backup
            $result = Write-AtomicFile -Path $testPath -Content $newContent -CreateBackup
            
            $result.Success | Should -Be $true
            
            # Check backup exists
            $backupPath = "$testPath.backup"
            Test-Path $backupPath | Should -Be $true
            Get-Content -Path $backupPath -Raw | Should -Be $originalContent
        }

        It "Should work with Backup-File function" {
            $testPath = Join-Path $script:AtomicTestDir "backup-file-test.txt"
            $content = "Test content for backup"
            
            Write-AtomicFile -Path $testPath -Content $content | Out-Null
            
            $result = Backup-File -Path $testPath -BackupCount 3
            
            $result.Success | Should -Be $true
            $result.BackupPath | Should -Not -BeNullOrEmpty
            Test-Path $result.BackupPath | Should -Be $true
        }

        It "Should roll back old backups correctly" {
            $testPath = Join-Path $script:AtomicTestDir "backup-rotation-test.txt"
            $content = "Version 1"
            
            Write-AtomicFile -Path $testPath -Content $content | Out-Null
            
            # Create 5 backups
            for ($i = 1; $i -le 5; $i++) {
                Start-Sleep -Milliseconds 10
                Backup-File -Path $testPath -BackupCount 3 | Out-Null
                Write-AtomicFile -Path $testPath -Content "Version $($i + 1)" | Out-Null
            }
            
            # Should only keep 3 backups
            $backups = @(Get-ChildItem -Path $script:AtomicTestDir -Filter "backup-rotation-test.txt.*.bak")
            $backups.Count | Should -BeLessOrEqual 3
        }
    }

    Context "Write-JsonAtomic Function" {
        It "Should include schema headers" {
            $testPath = Join-Path $script:AtomicTestDir "schema-test.json"
            $data = @{ items = @(1, 2, 3); name = "test" }
            
            $result = Write-JsonAtomic -Path $testPath -Data $data -SchemaVersion 2 -SchemaName "test-data"
            
            $result.Success | Should -Be $true
            $result.SchemaVersion | Should -Be 2
            $result.SchemaName | Should -Be "test-data"
            
            $readData = Get-Content -Path $testPath -Raw | ConvertFrom-Json
            $readData._schema.version | Should -Be 2
            $readData._schema.name | Should -Be "test-data"
            $readData._schema.createdAt | Should -Not -BeNullOrEmpty
            $readData.data.items.Count | Should -Be 3
        }

        It "Should reject schema version 0" {
            $testPath = Join-Path $script:AtomicTestDir "no-schema-test.json"
            $data = @{ key = "value" }
            
            { Write-JsonAtomic -Path $testPath -Data $data -SchemaVersion 0 } | Should -Throw
        }
    }

    Context "Read-JsonAtomic Function" {
        It "Should read schema-stamped files correctly" {
            $testPath = Join-Path $script:AtomicTestDir "read-test.json"
            $data = @{ config = @{ enabled = $true } }
            
            Write-JsonAtomic -Path $testPath -Data $data -SchemaVersion 1 -SchemaName "config" | Out-Null
            
            $result = Read-JsonAtomic -Path $testPath
            
            $result.Success | Should -Be $true
            $result.Schema.version | Should -Be 1
            $result.Schema.name | Should -Be "config"
            $result.Data.config.enabled | Should -Be $true
        }

        It "Should validate schema version when expected" {
            $testPath = Join-Path $script:AtomicTestDir "schema-validation-test.json"
            $data = @{ value = 123 }
            
            Write-JsonAtomic -Path $testPath -Data $data -SchemaVersion 2 | Out-Null
            
            $result = Read-JsonAtomic -Path $testPath -ExpectedSchemaVersion 2
            $result.Success | Should -Be $true
            
            $resultFail = Read-JsonAtomic -Path $testPath -ExpectedSchemaVersion 3
            $resultFail.Success | Should -Be $false
            $resultFail.Error | Should -Match "version mismatch"
        }
    }

    Context "Add-JsonLine Function" {
        It "Should append valid JSON lines" {
            $testPath = Join-Path $script:AtomicTestDir "lines.jsonl"
            
            $result1 = Add-JsonLine -Path $testPath -Data @{ event = "start"; timestamp = "2024-01-01" }
            $result2 = Add-JsonLine -Path $testPath -Data @{ event = "end"; timestamp = "2024-01-02" }
            
            $result1.Success | Should -Be $true
            $result1.LineNumber | Should -Be 1
            $result2.LineNumber | Should -Be 2
            
            $lines = Get-Content -Path $testPath
            $lines.Count | Should -Be 2
            ($lines[0] | ConvertFrom-Json).event | Should -Be "start"
            ($lines[1] | ConvertFrom-Json).event | Should -Be "end"
        }
    }
}
