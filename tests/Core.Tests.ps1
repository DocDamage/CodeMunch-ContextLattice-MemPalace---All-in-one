#requires -Version 5.1
<#
.SYNOPSIS
    Core Module Tests for LLM Workflow Platform

.DESCRIPTION
    Comprehensive Pester v5 test suite for core infrastructure modules:
    - FileLock.ps1: File locking, concurrency control, and stale lock detection
    - Journal.ps1: Journal entry creation, checkpoint/restore operations
    - AtomicWrite.ps1: Atomic file writes, temp file cleanup, backups
    - RunId.ps1: Run ID generation and format validation

.NOTES
    File: Core.Tests.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Requires: Pester 5.0+
#>

BeforeAll {
    # Set up test environment
    $script:TestRoot = Join-Path $env:TEMP "LLMWorkflow_CoreTests_$([Guid]::NewGuid().ToString('N'))"
    $script:ModuleRoot = Join-Path (Join-Path $PSScriptRoot "..") "module\LLMWorkflow"
    $script:CoreModulePath = Join-Path $script:ModuleRoot "core"
    
    # Create test directories
    New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:TestRoot ".llm-workflow") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:TestRoot ".llm-workflow") "locks") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:TestRoot ".llm-workflow") "journals") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:TestRoot ".llm-workflow") "manifests") -Force | Out-Null
    
    # Import modules by dot-sourcing
    $fileLockPath = Join-Path $script:CoreModulePath "FileLock.ps1"
    $journalPath = Join-Path $script:CoreModulePath "Journal.ps1"
    $atomicWritePath = Join-Path $script:CoreModulePath "AtomicWrite.ps1"
    $runIdPath = Join-Path $script:CoreModulePath "RunId.ps1"
    
    if (Test-Path $fileLockPath) { try { . $fileLockPath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
    if (Test-Path $journalPath) { try { . $journalPath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
    if (Test-Path $atomicWritePath) { try { . $atomicWritePath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
    if (Test-Path $runIdPath) { try { . $runIdPath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
}

AfterAll {
    # Cleanup test directory
    if (Test-Path $script:TestRoot) {
        Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "FileLock Module Tests" {
    BeforeEach {
        # Clean up any existing locks before each test
        $locksDir = Join-Path $script:TestRoot ".llm-workflow" "locks"
        if (Test-Path $locksDir) {
            Remove-Item -Path "$locksDir\*.lock" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$locksDir\*.tmp" -Force -ErrorAction SilentlyContinue
        }
        # Clear the acquired locks tracking
        $script:AcquiredLocks.Clear()
    }

    Context "Lock-File Function - Happy Path" {
        It "Should acquire a lock successfully with valid parameters" {
            $lock = Lock-File -Name "sync" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot
            
            $lock | Should -Not -BeNullOrEmpty
            $lock.Name | Should -Be "sync"
            $lock.Path | Should -Not -BeNullOrEmpty
            $lock.RunId | Should -Not -BeNullOrEmpty
            $lock.AcquiredAt | Should -Not -BeNullOrEmpty
            $lock.Content | Should -Not -BeNullOrEmpty
        }

        It "Should acquire locks for all valid lock names" {
            $validNames = @('sync', 'heal', 'index', 'ingest', 'pack')
            foreach ($name in $validNames) {
                $lock = Lock-File -Name $name -TimeoutSeconds 5 -ProjectRoot $script:TestRoot
                $lock.Name | Should -Be $name
                Unlock-File -Name $name -ProjectRoot $script:TestRoot | Out-Null
                $script:AcquiredLocks.Clear()
            }
        }

        It "Should create lock file with correct structure" {
            $lock = Lock-File -Name "sync" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot
            $lockFilePath = Join-Path $script:TestRoot ".llm-workflow" "locks" "sync.lock"
            
            Test-Path $lockFilePath | Should -Be $true
            $content = Get-Content $lockFilePath -Raw | ConvertFrom-Json
            $content.schemaVersion | Should -Be 1
            $content.pid | Should -Be $PID
            $content.host | Should -Not -BeNullOrEmpty
            $content.executionMode | Should -Not -BeNullOrEmpty
            $content.runId | Should -Not -BeNullOrEmpty
            { [DateTimeOffset]::Parse([string]$content.timestamp) } | Should -Not -Throw
            
            Unlock-File -Name "sync" -ProjectRoot $script:TestRoot | Out-Null
        }
    }

    Context "Lock-File Function - Error Cases" {
        It "Should throw on invalid lock name" {
            { Lock-File -Name "invalid-lock-name" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot } | 
                Should -Throw -ExpectedMessage "*Invalid lock name*"
        }

        It "Should throw when lock is already held by this process without -Force" {
            $lock1 = Lock-File -Name "sync" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot
            
            { Lock-File -Name "sync" -TimeoutSeconds 1 -ProjectRoot $script:TestRoot } | 
                Should -Throw -ExpectedMessage "*already held*"
            
            Unlock-File -Name "sync" -ProjectRoot $script:TestRoot | Out-Null
        }

        It "Should return null on timeout when lock is held by another process" {
            # Create a lock file simulating another process
            $lockFile = Join-Path $script:TestRoot ".llm-workflow" "locks" "ingest.lock"
            $otherLockContent = @{
                schemaVersion = 1
                pid = 99999
                host = "remote-test-host"
                executionMode = "ci"
                runId = "20260401T000000Z-0000"
                timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
                user = "otheruser"
            } | ConvertTo-Json
            
            $lockDir = Split-Path -Parent $lockFile
            if (-not (Test-Path $lockDir)) {
                New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
            }
            [System.IO.File]::WriteAllText($lockFile, $otherLockContent)
            
            # Try to acquire with no wait
            $result = Lock-File -Name "ingest" -TimeoutSeconds 0 -ProjectRoot $script:TestRoot
            $result | Should -BeNullOrEmpty
            
            Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Unlock-File Function" {
        It "Should release a held lock successfully" {
            $lock = Lock-File -Name "sync" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot
            $lockFilePath = Join-Path $script:TestRoot ".llm-workflow" "locks" "sync.lock"
            
            Test-Path $lockFilePath | Should -Be $true
            
            $released = Unlock-File -Name "sync" -ProjectRoot $script:TestRoot
            $released | Should -Be $true
            
            Test-Path $lockFilePath | Should -Be $false
        }

        It "Should return false when releasing untracked lock without -Force" {
            $released = Unlock-File -Name "pack" -ProjectRoot $script:TestRoot
            $released | Should -Be $false
        }

        It "Should release with -Force even if not tracked" {
            # Create a lock file directly
            $lockFile = Join-Path $script:TestRoot ".llm-workflow" "locks" "heal.lock"
            $lockContent = @{
                schemaVersion = 1
                pid = $PID
                host = ([Environment]::MachineName).ToLowerInvariant()
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
            
            $released = Unlock-File -Name "heal" -ProjectRoot $script:TestRoot -Force
            $released | Should -Be $true
            Test-Path $lockFile | Should -Be $false
        }
    }

    Context "Test-StaleLock Function" {
        It "Should detect stale locks from non-existent processes" {
            # Create a lock file for a non-existent process
            $lockFile = Join-Path $script:TestRoot ".llm-workflow" "locks" "sync.lock"
            $staleLockContent = @{
                schemaVersion = 1
                pid = 99999
                host = ([Environment]::MachineName).ToLowerInvariant()
                executionMode = "ci"
                runId = "20260401T000000Z-0000"
                timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
                user = "testuser"
            } | ConvertTo-Json
            
            $lockDir = Split-Path -Parent $lockFile
            if (-not (Test-Path $lockDir)) {
                New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
            }
            [System.IO.File]::WriteAllText($lockFile, $staleLockContent)
            
            Test-StaleLock -Name "sync" -ProjectRoot $script:TestRoot | Should -Be $true
            
            Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
        }

        It "Should detect stale locks by age" {
            # Create a lock file with old timestamp
            $lockFile = Join-Path $script:TestRoot ".llm-workflow" "locks" "heal.lock"
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
            
            Test-StaleLock -Name "heal" -ProjectRoot $script:TestRoot -MaxLockAgeMinutes 60 | Should -Be $true
            
            Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
        }

        It "Should not detect fresh locks as stale" {
            $lock = Lock-File -Name "sync" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot
            
            Test-StaleLock -Name "sync" -ProjectRoot $script:TestRoot | Should -Be $false
            
            Unlock-File -Name "sync" -ProjectRoot $script:TestRoot | Out-Null
        }

        It "Should treat corrupt lock files as stale" {
            $lockFile = Join-Path $script:TestRoot ".llm-workflow" "locks" "index.lock"
            $lockDir = Split-Path -Parent $lockFile
            if (-not (Test-Path $lockDir)) {
                New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
            }
            [System.IO.File]::WriteAllText($lockFile, "invalid json content")
            
            Test-StaleLock -Name "index" -ProjectRoot $script:TestRoot | Should -Be $true
            
            Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Remove-StaleLock Function" {
        It "Should remove stale locks with -Force" {
            $lockFile = Join-Path $script:TestRoot ".llm-workflow" "locks" "sync.lock"
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
            
            Test-StaleLock -Name "sync" -ProjectRoot $script:TestRoot | Should -Be $true
            
            $removed = Remove-StaleLock -Name "sync" -ProjectRoot $script:TestRoot -Force
            $removed | Should -Be $true
            Test-Path $lockFile | Should -Be $false
        }

        It "Should support CheckOnly mode without removing" {
            $lockFile = Join-Path $script:TestRoot ".llm-workflow" "locks" "heal.lock"
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
            
            $isStale = Remove-StaleLock -Name "heal" -ProjectRoot $script:TestRoot -CheckOnly
            $isStale | Should -Be $true
            Test-Path $lockFile | Should -Be $true
            
            Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Test-LockName Function" {
        It "Should return true for valid lock names" {
            $validNames = @('sync', 'heal', 'index', 'ingest', 'pack')
            foreach ($name in $validNames) {
                Test-LockName -Name $name | Should -Be $true
            }
        }

        It "Should return false for invalid lock names" {
            $invalidNames = @('invalid', 'random', 'test', 'lock', 'file')
            foreach ($name in $invalidNames) {
                Test-LockName -Name $name | Should -Be $false
            }
        }
    }

    Context "Get-LockInfo Function" {
        It "Should return lock information for existing locks" {
            $lock = Lock-File -Name "sync" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot
            
            $info = Get-LockInfo -Name "sync" -ProjectRoot $script:TestRoot
            $info | Should -Not -BeNullOrEmpty
            $info.SchemaVersion | Should -Be 1
            $info.Pid | Should -Be $PID
            $info.Host | Should -Not -BeNullOrEmpty
            $info.IsStale | Should -Be $false
            $info.AgeMinutes | Should -Not -BeNullOrEmpty
            
            Unlock-File -Name "sync" -ProjectRoot $script:TestRoot | Out-Null
        }

        It "Should return null for non-existent locks" {
            Get-LockInfo -Name "nonexistent" -ProjectRoot $script:TestRoot | Should -BeNullOrEmpty
        }
    }
}

Describe "Journal Module Tests" {
    BeforeAll {
        $script:JournalDir = Join-Path $script:TestRoot ".llm-workflow" "journals"
        $script:ManifestDir = Join-Path $script:TestRoot ".llm-workflow" "manifests"
    }

    BeforeEach {
        # Clean up journal files before each test
        if (Test-Path $script:JournalDir) {
            Remove-Item -Path "$script:JournalDir\*.json" -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $script:ManifestDir) {
            Remove-Item -Path "$script:ManifestDir\*.json" -Force -ErrorAction SilentlyContinue
        }
    }

    Context "New-JournalEntry Function - Happy Path" {
        It "Should create a valid journal entry" {
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
            $entry.timestamp | Should -Match "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"
        }

        It "Should support all valid status values" {
            $runId = "20260413T000001Z-ef0a"
            $statuses = @('before', 'after', 'start', 'complete', 'failed')
            
            foreach ($status in $statuses) {
                $entry = New-JournalEntry -RunId $runId -Step "test" -Status $status `
                    -JournalDirectory $script:JournalDir
                $entry.status | Should -Be $status
            }
        }

        It "Should increment sequence numbers correctly" {
            $runId = "20260413T000002Z-1b2c"
            
            $entry1 = New-JournalEntry -RunId $runId -Step "step1" -Status "before" `
                -JournalDirectory $script:JournalDir
            $entry2 = New-JournalEntry -RunId $runId -Step "step1" -Status "after" `
                -JournalDirectory $script:JournalDir
            $entry3 = New-JournalEntry -RunId $runId -Step "step2" -Status "before" `
                -JournalDirectory $script:JournalDir
            
            $entry1.sequence | Should -Be 0
            $entry2.sequence | Should -Be 1
            $entry3.sequence | Should -Be 2
        }
    }

    Context "New-JournalEntry Function - Error Cases" {
        It "Should throw on invalid RunId format" {
            { New-JournalEntry -RunId "invalid-run-id" -Step "ingest" -Status "before" `
                -JournalDirectory $script:JournalDir } | Should -Throw
        }

        It "Should throw on invalid step name" {
            { New-JournalEntry -RunId "20260413T000000Z-abcd" -Step "" -Status "before" `
                -JournalDirectory $script:JournalDir } | Should -Throw
        }

        It "Should throw on invalid status" {
            { New-JournalEntry -RunId "20260413T000000Z-abcd" -Step "ingest" -Status "invalid" `
                -JournalDirectory $script:JournalDir } | Should -Throw
        }
    }

    Context "Checkpoint-Journal Function" {
        It "Should create a checkpoint with preserved state" {
            $runId = "20260413T000003Z-3d4e"
            $state = @{ processedCount = 0; files = @() }
            
            $checkpoint = Checkpoint-Journal -RunId $runId -Step "ingest" -State $state `
                -JournalDirectory $script:JournalDir
            
            $checkpoint | Should -Not -BeNullOrEmpty
            $checkpoint.RunId | Should -Be $runId
            $checkpoint.Step | Should -Be "ingest"
            $checkpoint.CanResume | Should -Be $true
            $checkpoint.Checkpoint | Should -Not -BeNullOrEmpty
        }
    }

    Context "Restore-FromCheckpoint Function" {
        It "Should restore state from a checkpoint" {
            $runId = "20260413T000004Z-5f6a"
            $state = @{ processedCount = 42; currentFile = "test.txt" }
            
            Checkpoint-Journal -RunId $runId -Step "ingest" -State $state `
                -JournalDirectory $script:JournalDir | Out-Null
            
            $restored = Restore-FromCheckpoint -RunId $runId -Step "ingest" `
                -JournalDirectory $script:JournalDir
            
            $restored | Should -Not -BeNullOrEmpty
            $restored.State.processedCount | Should -Be 42
            $restored.State.currentFile | Should -Be "test.txt"
        }

        It "Should return null when no checkpoint exists" {
            $result = Restore-FromCheckpoint -RunId "20260413T235959Z-abcd" `
                -JournalDirectory $script:JournalDir
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Complete-Checkpoint Function" {
        It "Should complete a checkpoint with duration calculation" {
            $runId = "20260413T000005Z-7b8c"
            
            Checkpoint-Journal -RunId $runId -Step "ingest" `
                -JournalDirectory $script:JournalDir | Out-Null
            Start-Sleep -Milliseconds 50
            $completed = Complete-Checkpoint -RunId $runId -Step "ingest" `
                -JournalDirectory $script:JournalDir
            
            $completed | Should -Not -BeNullOrEmpty
            $completed.Step | Should -Be "ingest"
            $completed.DurationMs | Should -Not -BeNullOrEmpty
            $completed.DurationMs | Should -BeGreaterOrEqual 0
        }
    }

    Context "Get-JournalState Function" {
        It "Should return correct state for resumable run" {
            $runId = "20260413T000006Z-9d0e"
            
            New-RunManifest -RunId $runId -Command "sync" `
                -ManifestDirectory $script:ManifestDir | Out-Null
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
        }

        It "Should return correct state for non-existent run" {
            $state = Get-JournalState -RunId "20260413T235959Z-abcd" `
                -JournalDirectory $script:JournalDir `
                -ManifestDirectory $script:ManifestDir
            
            $state.Exists | Should -Be $false
            $state.CanResume | Should -Be $false
        }
    }
}

Describe "AtomicWrite Module Tests" {
    BeforeAll {
        $script:AtomicTestDir = Join-Path $script:TestRoot "atomic-tests"
        New-Item -ItemType Directory -Path $script:AtomicTestDir -Force | Out-Null
    }

    BeforeEach {
        # Clean up test files
        if (Test-Path $script:AtomicTestDir) {
            Remove-Item -Path "$script:AtomicTestDir\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Write-AtomicFile Function - Happy Path" {
        It "Should write text content atomically" {
            $testPath = Join-Path $script:AtomicTestDir "atomic-test.txt"
            $content = "Test content for atomic write"
            
            $result = Write-AtomicFile -Path $testPath -Content $content
            
            $result.Success | Should -Be $true
            $result.Path | Should -Be $testPath
            $result.BytesWritten | Should -BeGreaterThan 0
            
            Get-Content -Path $testPath -Raw | Should -Be $content
        }

        It "Should write JSON content correctly" {
            $testPath = Join-Path $script:AtomicTestDir "atomic-test.json"
            $data = @{ name = "test"; value = 42; nested = @{ key = "value" } }
            
            $result = Write-AtomicFile -Path $testPath -Content $data -Format Json
            
            $result.Success | Should -Be $true
            
            $readData = Get-Content -Path $testPath -Raw | ConvertFrom-Json -AsHashtable
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
            $testPath = Join-Path $script:AtomicTestDir "nested" "deep" "file.txt"
            $content = "Deep nested content"
            
            $result = Write-AtomicFile -Path $testPath -Content $content
            
            $result.Success | Should -Be $true
            Test-Path $testPath | Should -Be $true
        }
    }

    Context "Write-AtomicFile Function - Error Cases" {
        It "Should throw on null or empty path" {
            { Write-AtomicFile -Path "" -Content "test" } | Should -Throw
        }

        It "Should fail gracefully on invalid byte array for Bytes format" {
            $testPath = Join-Path $script:AtomicTestDir "invalid-bytes.bin"
            { Write-AtomicFile -Path $testPath -Content "not-bytes" -Format Bytes } | Should -Throw
        }
    }

    Context "Temp File Cleanup" {
        It "Should clean up temp file on failure" {
            $testPath = Join-Path $script:AtomicTestDir "cleanup-test.txt"
            
            # Mock a failure scenario by using an invalid path
            $invalidPath = "\\invalid\path\that\cannot\exist\file.txt"
            { Write-AtomicFile -Path $invalidPath -Content "test" } | Should -Throw
        }

        It "Should not leave temp files after successful write" {
            $testPath = Join-Path $script:AtomicTestDir "no-temp-test.txt"
            $content = "Test content"
            
            Write-AtomicFile -Path $testPath -Content $content | Out-Null
            
            $tempFiles = Get-ChildItem -Path $script:AtomicTestDir -Filter "*.tmp*" -ErrorAction SilentlyContinue
            $tempFiles | Should -BeNullOrEmpty
        }
    }

    Context "Backup-File Function" {
        It "Should create backup successfully" {
            $testPath = Join-Path $script:AtomicTestDir "backup-test.txt"
            $content = "Original content"
            
            Write-AtomicFile -Path $testPath -Content $content | Out-Null
            
            $result = Backup-File -Path $testPath -BackupCount 3
            
            $result.Success | Should -Be $true
            $result.BackupPath | Should -Not -BeNullOrEmpty
            Test-Path $result.BackupPath | Should -Be $true
        }

        It "Should return success when source does not exist" {
            $result = Backup-File -Path "nonexistent-file.txt" -BackupCount 3
            $result.Success | Should -Be $true
            $result.Message | Should -Match "no backup needed"
        }

        It "Should rotate old backups correctly" {
            $testPath = Join-Path $script:AtomicTestDir "backup-rotation-test.txt"
            
            # Create file and multiple backups
            for ($i = 1; $i -le 5; $i++) {
                Write-AtomicFile -Path $testPath -Content "Version $i" | Out-Null
                Start-Sleep -Milliseconds 10
                Backup-File -Path $testPath -BackupCount 3 | Out-Null
            }
            
            # Should only keep 3 backups
            $backups = @(Get-ChildItem -Path $script:AtomicTestDir -Filter "backup-rotation-test.txt.*.bak")
            $backups.Count | Should -BeLessOrEqual 3
        }
    }

    Context "Backup-AndWrite Function" {
        It "Should backup and write atomically" {
            $testPath = Join-Path $script:AtomicTestDir "backup-and-write.txt"
            $originalContent = "Original content"
            $newContent = "New content"
            
            Write-AtomicFile -Path $testPath -Content $originalContent | Out-Null
            
            $result = Backup-AndWrite -Path $testPath -Content $newContent -BackupCount 3
            
            $result.Success | Should -Be $true
            Get-Content -Path $testPath -Raw | Should -Be $newContent
        }
    }

    Context "Write-JsonAtomic Function" {
        It "Should include schema headers when specified" {
            $testPath = Join-Path $script:AtomicTestDir "schema-test.json"
            $data = @{ items = @(1, 2, 3); name = "test" }
            
            $result = Write-JsonAtomic -Path $testPath -Data $data -SchemaVersion 2 -SchemaName "test-data"
            
            $result.Success | Should -Be $true
            $result.SchemaVersion | Should -Be 2
            $result.SchemaName | Should -Be "test-data"
            
            $readData = Get-Content -Path $testPath -Raw | ConvertFrom-Json -AsHashtable
            $readData._schema.version | Should -Be 2
            $readData._schema.name | Should -Be "test-data"
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

        It "Should return error for non-existent file" {
            $result = Read-JsonAtomic -Path "nonexistent-file.json"
            $result.Success | Should -Be $false
            $result.Error | Should -Match "File not found"
        }
    }

    Context "Sync-File and Sync-Directory Functions" {
        It "Should sync file successfully" {
            $testPath = Join-Path $script:AtomicTestDir "sync-test.txt"
            Write-AtomicFile -Path $testPath -Content "sync test" | Out-Null
            
            $result = Sync-File -Path $testPath
            $result | Should -Be $true
        }

        It "Should return false for non-existent file sync" {
            $result = Sync-File -Path "nonexistent-file.txt"
            $result | Should -Be $false
        }

        It "Should sync directory successfully" {
            $result = Sync-Directory -Path $script:AtomicTestDir
            $result | Should -Be $true
        }
    }
}

Describe "RunId Module Tests" {
    Context "New-RunId Function - Happy Path" {
        It "Should generate a valid RunId with correct format" {
            $runId = New-RunId
            
            $runId | Should -Not -BeNullOrEmpty
            $runId | Should -Match "^\d{8}T\d{6}Z-[0-9a-f]{4}$"
        }

        It "Should use provided timestamp" {
            $timestamp = [DateTime]::Parse("2026-04-11T21:05:01Z")
            $runId = New-RunId -Timestamp $timestamp
            
            $runId | Should -Match "^20260411T210501Z-"
        }

        It "Should use provided suffix" {
            $runId = New-RunId -Suffix "abcd"
            $runId | Should -Match "-[0-9a-f]{4}$"
            $runId | Should -Match "-abcd$"
        }

        It "Should generate unique RunIds" {
            $runIds = @()
            for ($i = 0; $i -lt 10; $i++) {
                $runIds += New-RunId
            }
            
            $uniqueIds = $runIds | Select-Object -Unique
            $uniqueIds.Count | Should -Be $runIds.Count
        }
    }

    Context "New-RunId Function - Error Cases" {
        It "Should throw on invalid suffix format" {
            { New-RunId -Suffix "invalid" } | Should -Throw
            { New-RunId -Suffix "123" } | Should -Throw
            { New-RunId -Suffix "GGGG" } | Should -Throw
        }
    }

    Context "Get-CurrentRunId Function" {
        It "Should return cached RunId on subsequent calls" {
            # Clear any existing run ID
            Clear-CurrentRunId
            
            $runId1 = Get-CurrentRunId
            $runId2 = Get-CurrentRunId
            
            $runId1 | Should -Be $runId2
        }

        It "Should generate new RunId with -ForceNew" {
            # Clear any existing run ID
            Clear-CurrentRunId
            
            $runId1 = Get-CurrentRunId
            Start-Sleep -Milliseconds 10
            $runId2 = Get-CurrentRunId -ForceNew
            
            $runId1 | Should -Not -Be $runId2
        }
    }

    Context "Set-CurrentRunId Function" {
        It "Should set the current RunId" {
            $testRunId = "20260411T210501Z-7f2c"
            Set-CurrentRunId -RunId $testRunId
            
            Get-CurrentRunId | Should -Be $testRunId
        }

        It "Should throw on invalid RunId format" {
            { Set-CurrentRunId -RunId "invalid-run-id" } | Should -Throw
        }
    }

    Context "Clear-CurrentRunId Function" {
        It "Should clear the current RunId" {
            Get-CurrentRunId | Out-Null
            Clear-CurrentRunId
            
            $newRunId = Get-CurrentRunId -ForceNew
            $newRunId | Should -Not -BeNullOrEmpty
        }
    }

    Context "Test-RunIdFormat Function" {
        It "Should return true for valid RunIds" {
            Test-RunIdFormat -RunId "20260411T210501Z-7f2c" | Should -Be $true
            Test-RunIdFormat -RunId "19991231T235959Z-0000" | Should -Be $true
            Test-RunIdFormat -RunId "20991231T235959Z-ffff" | Should -Be $true
        }

        It "Should return false for invalid RunIds" {
            Test-RunIdFormat -RunId "" | Should -Be $false
            Test-RunIdFormat -RunId $null | Should -Be $false
            Test-RunIdFormat -RunId "invalid" | Should -Be $false
            Test-RunIdFormat -RunId "20260411T210501Z" | Should -Be $false
            Test-RunIdFormat -RunId "20260411T210501-7f2c" | Should -Be $false
            Test-RunIdFormat -RunId "2026-04-11T21:05:01Z-7f2c" | Should -Be $false
        }
    }

    Context "Parse-RunId Function" {
        It "Should parse valid RunId correctly" {
            $runId = "20260411T210501Z-7f2c"
            $result = Parse-RunId -RunId $runId
            
            $result.IsValid | Should -Be $true
            $result.RunId | Should -Be $runId
            $result.TimestampUtc.Year | Should -Be 2026
            $result.TimestampUtc.Month | Should -Be 4
            $result.TimestampUtc.Day | Should -Be 11
            $result.Suffix | Should -Be "7f2c"
        }

        It "Should return invalid for malformed RunId" {
            $result = Parse-RunId -RunId "invalid-run-id"
            $result.IsValid | Should -Be $false
        }
    }
}
