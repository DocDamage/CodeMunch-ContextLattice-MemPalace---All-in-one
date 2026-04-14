#requires -Version 5.1
<#
.SYNOPSIS
    Primitive tests for FileLock.ps1
.DESCRIPTION
    Pester v5 tests for file locking and concurrency control.
#>

Describe 'Primitive.FileLock Tests' {
BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..\module\LLMWorkflow\core\FileLock.ps1'
    $script:RunIdPath = Join-Path $PSScriptRoot '..\module\LLMWorkflow\core\RunId.ps1'

    if (-not (Get-Command New-RunId -ErrorAction SilentlyContinue)) {
        if (Test-Path $script:RunIdPath) {
            try { . $script:RunIdPath } catch { if ($_.Exception.Message -notlike '*Export-ModuleMember*') { throw } }
        }
    }
    if (-not (Get-Command New-RunId -ErrorAction SilentlyContinue)) {
        function New-RunId { return "20260101T000000Z-0001" }
    }
    if (-not (Get-Command Get-ExecutionMode -ErrorAction SilentlyContinue)) {
        function Get-ExecutionMode { return 'interactive' }
    }

    if (Test-Path $script:ModulePath) {
        try { . $script:ModulePath } catch { if ($_.Exception.Message -notlike '*Export-ModuleMember*') { throw } }
    }
    else {
        throw "Module not found: $script:ModulePath"
    }

    $script:TestDir = Join-Path $TestDrive 'FileLockTests'
    New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
}

AfterAll {
    Release-AllLocks -ProjectRoot $script:TestDir | Out-Null
    if (Test-Path $script:TestDir) {
        Remove-Item -LiteralPath $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

AfterEach {
    Release-AllLocks -ProjectRoot $script:TestDir | Out-Null
    $locksDir = Join-Path (Join-Path $script:TestDir '.llm-workflow') 'locks'
    if (Test-Path $locksDir) {
        Remove-Item -LiteralPath "$locksDir\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Lock-File' {
    It 'Acquires a lock and returns lock info' {
        $lock = Lock-File -Name 'sync' -TimeoutSeconds 5 -ProjectRoot $script:TestDir
        $lock | Should -Not -BeNullOrEmpty
        $lock.Name | Should -Be 'sync'
        $lock.RunId | Should -Not -BeNullOrEmpty
        $lock.Path | Should -Exist
    }

    It 'Throws when lock is already held without -Force' {
        Lock-File -Name 'sync' -TimeoutSeconds 1 -ProjectRoot $script:TestDir | Out-Null
        { Lock-File -Name 'sync' -TimeoutSeconds 1 -ProjectRoot $script:TestDir } | Should -Throw '*already held*'
    }

    It 'Throws on invalid lock name' {
        { Lock-File -Name 'invalid' -TimeoutSeconds 1 -ProjectRoot $script:TestDir } | Should -Throw '*Invalid lock name*'
    }
}

Describe 'Unlock-File' {
    It 'Releases a held lock' {
        Lock-File -Name 'index' -TimeoutSeconds 1 -ProjectRoot $script:TestDir | Out-Null
        Unlock-File -Name 'index' -ProjectRoot $script:TestDir | Should -Be $true
        Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $script:TestDir '.llm-workflow') 'locks') 'index.lock') | Should -Be $false
    }

    It 'Returns false when lock was not tracked and -Force is not used' {
        Unlock-File -Name 'heal' -ProjectRoot $script:TestDir | Should -Be $false
    }
}

Describe 'Test-FileLock' {
    It 'Returns true when lock is active' {
        Lock-File -Name 'pack' -TimeoutSeconds 1 -ProjectRoot $script:TestDir | Out-Null
        Test-FileLock -Name 'pack' -ProjectRoot $script:TestDir | Should -Be $true
    }

    It 'Returns false when lock does not exist' {
        Test-FileLock -Name 'pack' -ProjectRoot $script:TestDir | Should -Be $false
    }

    It 'Returns false for invalid lock name' {
        Test-FileLock -Name 'bad-name' -ProjectRoot $script:TestDir | Should -Be $false
    }
}

Describe 'Test-StaleLock' {
    It 'Returns false for a valid current-process lock' {
        Lock-File -Name 'ingest' -TimeoutSeconds 1 -ProjectRoot $script:TestDir | Out-Null
        Test-StaleLock -Name 'ingest' -ProjectRoot $script:TestDir | Should -Be $false
    }

    It 'Returns true for a stale lock (non-existent PID)' {
        $locksDir = Join-Path (Join-Path $script:TestDir '.llm-workflow') 'locks'
        New-Item -ItemType Directory -Path $locksDir -Force | Out-Null
        $lockFile = Join-Path $locksDir 'sync.lock'
        @{
            schemaVersion = 1
            pid = 99999
            host = $env:COMPUTERNAME.ToLowerInvariant()
            executionMode = 'interactive'
            runId = '20260101T000000Z-0001'
            timestamp = ([DateTime]::UtcNow.AddHours(-2).ToString('yyyy-MM-ddTHH:mm:ssZ'))
            user = $env:USERNAME
        } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $lockFile -Encoding UTF8

        Test-StaleLock -Name 'sync' -ProjectRoot $script:TestDir | Should -Be $true
    }
}

Describe 'Get-LockInfo' {
    It 'Returns lock metadata for existing lock' {
        Lock-File -Name 'heal' -TimeoutSeconds 1 -ProjectRoot $script:TestDir | Out-Null
        $info = Get-LockInfo -Name 'heal' -ProjectRoot $script:TestDir
        $info | Should -Not -BeNullOrEmpty
        $info.Pid | Should -Be $PID
        $info.Host | Should -Be $env:COMPUTERNAME.ToLowerInvariant()
    }

    It 'Returns null when lock does not exist' {
        Get-LockInfo -Name 'heal' -ProjectRoot $script:TestDir | Should -BeNullOrEmpty
    }
}

Describe 'Get-LockFilePath / Get-LockDirectory' {
    It 'Returns canonical lock file path' {
        $path = Get-LockFilePath -Name 'sync' -ProjectRoot $script:TestDir
        $path | Should -BeLike '*\.llm-workflow\locks\sync.lock'
    }

    It 'Creates lock directory if missing' {
        $dir = Get-LockDirectory -ProjectRoot $script:TestDir
        $dir | Should -Exist
    }
}

Describe 'Remove-StaleLock' {
    It 'Removes a stale lock with -Force' {
        $locksDir = Join-Path (Join-Path $script:TestDir '.llm-workflow') 'locks'
        New-Item -ItemType Directory -Path $locksDir -Force | Out-Null
        $lockFile = Join-Path $locksDir 'index.lock'
        @{
            schemaVersion = 1
            pid = 99999
            host = $env:COMPUTERNAME.ToLowerInvariant()
            executionMode = 'interactive'
            runId = '20260101T000000Z-0001'
            timestamp = ([DateTime]::UtcNow.AddHours(-2).ToString('yyyy-MM-ddTHH:mm:ssZ'))
            user = $env:USERNAME
        } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $lockFile -Encoding UTF8

        Remove-StaleLock -Name 'index' -ProjectRoot $script:TestDir -Force | Should -Be $true
        Test-Path -LiteralPath $lockFile | Should -Be $false
    }

    It 'Returns false for a non-stale lock' {
        Lock-File -Name 'index' -TimeoutSeconds 1 -ProjectRoot $script:TestDir | Out-Null
        Remove-StaleLock -Name 'index' -ProjectRoot $script:TestDir -Force | Should -Be $false
    }
}

Describe 'Get-AllLocks / Release-AllLocks' {
    It 'Lists all active locks' {
        Lock-File -Name 'sync' -TimeoutSeconds 1 -ProjectRoot $script:TestDir | Out-Null
        Lock-File -Name 'pack' -TimeoutSeconds 1 -ProjectRoot $script:TestDir | Out-Null
        $all = Get-AllLocks -ProjectRoot $script:TestDir
        @($all).Count | Should -BeGreaterOrEqual 1
    }

    It 'Releases all tracked locks' {
        Lock-File -Name 'sync' -TimeoutSeconds 1 -ProjectRoot $script:TestDir | Out-Null
        Lock-File -Name 'pack' -TimeoutSeconds 1 -ProjectRoot $script:TestDir -Force | Out-Null
        $released = Release-AllLocks -ProjectRoot $script:TestDir
        $released | Should -Contain 'sync'
    }
}

Describe 'Send-LockHeartbeat' {
    It 'Updates timestamp on a held lock' {
        Lock-File -Name 'sync' -TimeoutSeconds 1 -ProjectRoot $script:TestDir | Out-Null
        Send-LockHeartbeat -Name 'sync' -ProjectRoot $script:TestDir | Should -Be $true
    }

    It 'Returns false for a lock not held by this process' {
        Send-LockHeartbeat -Name 'pack' -ProjectRoot $script:TestDir | Should -Be $false
    }
}
}