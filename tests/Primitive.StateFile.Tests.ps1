#requires -Version 5.1
<#
.SYNOPSIS
    Primitive tests for StateFile.ps1
.DESCRIPTION
    Pester v5 tests for state file read, write, update, and migration.
#>

Describe 'Primitive.StateFile Tests' {
BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..\module\LLMWorkflow\core\StateFile.ps1'
    if (Test-Path $script:ModulePath) {
        try { . $script:ModulePath } catch { if ($_.Exception.Message -notlike '*Export-ModuleMember*') { throw } }
    }
    else {
        throw "Module not found: $script:ModulePath"
    }
    $script:TestDir = Join-Path $TestDrive 'StateFileTests'
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

Describe 'Get-StateDirectory / Get-StateFilePath' {
    It 'Returns canonical state directory path' {
        $dir = Get-StateDirectory -ProjectRoot $script:TestDir
        $dir | Should -BeLike '*\.llm-workflow\state'
        $dir | Should -Exist
    }

    It 'Returns canonical state file path with .json extension' {
        $path = Get-StateFilePath -Name 'sync-state' -ProjectRoot $script:TestDir
        $path | Should -BeLike '*sync-state.json'
    }
}

Describe 'Write-StateFile / Read-StateFile' {
    It 'Writes and reads state with schema header' {
        $path = Join-Path $script:TestDir 'test-state.json'
        $data = @{ status = 'idle'; count = 0 }
        $writeResult = Write-StateFile -Path $path -Data $data -SchemaVersion 1 -SchemaName 'test-state'
        $writeResult.Success | Should -Be $true
        $writeResult.Path | Should -Be $path

        $readResult = Read-StateFile -Path $path
        $readResult.Success | Should -Be $true
        $readResult.Data.status | Should -Be 'idle'
        $readResult.Data.count | Should -Be 0
        $readResult.Version | Should -Be 1
    }

    It 'Returns default value when file is missing' {
        $path = Join-Path $script:TestDir 'missing-state.json'
        $default = @{ fallback = $true }
        $readResult = Read-StateFile -Path $path -DefaultValue $default
        $readResult.Success | Should -Be $true
        $readResult.Data.fallback | Should -Be $true
        $readResult.Exists | Should -Be $false
    }

    It 'Returns error when file is missing and no default is given' {
        $path = Join-Path $script:TestDir 'missing-state.json'
        $readResult = Read-StateFile -Path $path
        $readResult.Success | Should -Be $false
        $readResult.Error | Should -Match 'not found|State file not found'
    }

    It 'Returns error for empty file without default' {
        $path = Join-Path $script:TestDir 'empty-state.json'
        [string]::Empty | Set-Content -LiteralPath $path -Encoding UTF8
        $readResult = Read-StateFile -Path $path
        $readResult.Success | Should -Be $false
        $readResult.Error | Should -Match 'empty|State file is empty'
    }
}

Describe 'Update-StateFile' {
    It 'Applies hashtable updates atomically' {
        $path = Join-Path $script:TestDir 'update-state.json'
        Write-StateFile -Path $path -Data @{ count = 1 } -SchemaVersion 1 | Out-Null

        $result = Update-StateFile -Path $path -Updates @{ count = 2; name = 'test' }
        $result.Success | Should -Be $true
        $result.UpdatedFields | Should -Contain 'count'
        $result.UpdatedFields | Should -Contain 'name'

        $read = Read-StateFile -Path $path
        $read.Data.count | Should -Be 2
        $read.Data.name | Should -Be 'test'
    }

    It 'Creates file when missing and -CreateIfMissing is specified' {
        $path = Join-Path $script:TestDir 'new-update-state.json'
        $result = Update-StateFile -Path $path -Updates @{ key = 'value' } -CreateIfMissing
        $result.Success | Should -Be $true
        $read = Read-StateFile -Path $path
        $read.Data.key | Should -Be 'value'
    }

    It 'Fails optimistic lock when version does not match' {
        $path = Join-Path $script:TestDir 'opt-state.json'
        Write-StateFile -Path $path -Data @{ v = 1 } -SchemaVersion 2 | Out-Null
        $result = Update-StateFile -Path $path -Updates @{ v = 2 } -ExpectedVersion 99
        $result.Success | Should -Be $false
        $result.Error | Should -Match 'Optimistic lock failed|expected version'
    }
}

Describe 'Test-StateVersion' {
    It 'Returns valid when version is within range' {
        $path = Join-Path $script:TestDir 'version-state.json'
        Write-StateFile -Path $path -Data @{} -SchemaVersion 3 | Out-Null
        $result = Test-StateVersion -Path $path -MinVersion 1 -MaxVersion 5
        $result.IsValid | Should -Be $true
        $result.ActualVersion | Should -Be 3
    }

    It 'Returns invalid on exact version mismatch' {
        $path = Join-Path $script:TestDir 'version-state.json'
        Write-StateFile -Path $path -Data @{} -SchemaVersion 3 | Out-Null
        $result = Test-StateVersion -Path $path -ExactVersion 99
        $result.IsValid | Should -Be $false
    }

    It 'Returns invalid when file does not exist' {
        $result = Test-StateVersion -Path (Join-Path $script:TestDir 'no-file.json') -MinVersion 1
        $result.IsValid | Should -Be $false
        $result.Exists | Should -Be $false
    }
}

Describe 'Backup-StateFile' {
    It 'Creates a timestamped backup' {
        $path = Join-Path $script:TestDir 'backup-state.json'
        Write-StateFile -Path $path -Data @{ a = 1 } | Out-Null
        $result = Backup-StateFile -Path $path -BackupCount 2
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Exist
    }

    It 'Returns success with null path when source is missing' {
        $result = Backup-StateFile -Path (Join-Path $script:TestDir 'missing.json')
        $result.Success | Should -Be $true
        $result.BackupPath | Should -BeNullOrEmpty
    }
}

Describe 'Migrate-StateFile' {
    It 'Migrates data and updates schema version' {
        $path = Join-Path $script:TestDir 'migrate-state.json'
        Write-StateFile -Path $path -Data @{ list = @(1, 2) } -SchemaVersion 1 | Out-Null

        $result = Migrate-StateFile -Path $path -FromVersion 1 -ToVersion 2 -MigrationScript {
            param($old)
            return @{ items = $old.list; count = $old.list.Count }
        }

        $result.Success | Should -Be $true
        $result.NewVersion | Should -Be 2

        $read = Read-StateFile -Path $path
        $read.Data.items.Count | Should -Be 2
    }

    It 'Fails migration when source version does not match' {
        $path = Join-Path $script:TestDir 'migrate-fail.json'
        Write-StateFile -Path $path -Data @{} -SchemaVersion 1 | Out-Null
        $result = Migrate-StateFile -Path $path -FromVersion 99 -ToVersion 2 -MigrationScript { param($old) return $old }
        $result.Success | Should -Be $false
    }
}

Describe 'Get-StateFiles' {
    It 'Lists state files in project root' {
        $stateDir = Get-StateDirectory -ProjectRoot $script:TestDir
        Write-StateFile -Path (Join-Path $stateDir 'a.json') -Data @{} | Out-Null
        Write-StateFile -Path (Join-Path $stateDir 'b.json') -Data @{} | Out-Null
        $files = Get-StateFiles -ProjectRoot $script:TestDir
        $files.Count | Should -BeGreaterOrEqual 2
    }
}

Describe 'Initialize-StateFile' {
    It 'Creates a new state file when it does not exist' {
        $path = Join-Path $script:TestDir 'init-state.json'
        $result = Initialize-StateFile -Path $path -DefaultData @{ status = 'ready' } -SchemaVersion 1
        $result.Created | Should -Be $true
        $result.Version | Should -Be 1
        $read = Read-StateFile -Path $path
        $read.Data.status | Should -Be 'ready'
    }

    It 'Does not overwrite existing file without -Overwrite' {
        $path = Join-Path $script:TestDir 'init-state2.json'
        Initialize-StateFile -Path $path -DefaultData @{ status = 'ready' } | Out-Null
        $result = Initialize-StateFile -Path $path -DefaultData @{ status = 'changed' }
        $result.Created | Should -Be $false
        $read = Read-StateFile -Path $path
        $read.Data.status | Should -Be 'ready'
    }
}
}