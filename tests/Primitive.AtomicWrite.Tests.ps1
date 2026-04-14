#requires -Version 5.1
<#
.SYNOPSIS
    Primitive tests for AtomicWrite.ps1
.DESCRIPTION
    Pester v5 tests for atomic file write operations.
#>

Describe 'Primitive.AtomicWrite Tests' {
BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..\module\LLMWorkflow\core\AtomicWrite.ps1'
    if (Test-Path $script:ModulePath) {
        try { . $script:ModulePath } catch { if ($_.Exception.Message -notlike '*Export-ModuleMember*') { throw } }
    }
    else {
        throw "Module not found: $script:ModulePath"
    }
    $script:TestDir = Join-Path $TestDrive 'AtomicWriteTests'
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

Describe 'Write-AtomicFile' {
    It 'Writes text atomically and returns success metadata' {
        $path = Join-Path $script:TestDir 'test.txt'
        $result = Write-AtomicFile -Path $path -Content 'hello world'
        $result.Success | Should -Be $true
        $result.Path | Should -Be $path
        $result.BytesWritten | Should -BeGreaterThan 0
        Get-Content -LiteralPath $path -Raw | Should -Be 'hello world'
    }

    It 'Writes JSON atomically with correct format' {
        $path = Join-Path $script:TestDir 'data.json'
        $obj = @{ name = 'test'; value = 42 }
        $result = Write-AtomicFile -Path $path -Content $obj -Format Json
        $result.Success | Should -Be $true
        $parsed = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $parsed.name | Should -Be 'test'
        $parsed.value | Should -Be 42
    }

    It 'Throws when given invalid path' {
        { Write-AtomicFile -Path '' -Content 'x' } | Should -Throw
    }
}

Describe 'Read-JsonAtomic / Write-JsonAtomic' {
    It 'Round-trips JSON data with schema header' {
        $path = Join-Path $script:TestDir 'schema.json'
        $data = @{ key = 'value' }
        $writeResult = Write-JsonAtomic -Path $path -Data $data -SchemaVersion 2 -SchemaName 'test-schema'
        $writeResult.Success | Should -Be $true
        $writeResult.SchemaVersion | Should -Be 2

        $readResult = Read-JsonAtomic -Path $path -ExpectedSchemaVersion 2 -ExpectedSchemaName 'test-schema'
        $readResult.Success | Should -Be $true
        $readResult.Data.key | Should -Be 'value'
    }

    It 'Returns error when file is not found' {
        $result = Read-JsonAtomic -Path (Join-Path $script:TestDir 'nonexistent.json')
        $result.Success | Should -Be $false
        $result.Error | Should -Match 'not found|notfound|File not found'
    }

    It 'Returns error on schema version mismatch' {
        $path = Join-Path $script:TestDir 'mismatch.json'
        Write-JsonAtomic -Path $path -Data @{ a = 1 } -SchemaVersion 1 | Out-Null
        $result = Read-JsonAtomic -Path $path -ExpectedSchemaVersion 99
        $result.Success | Should -Be $false
        $result.Error | Should -Match 'mismatch|version'
    }
}

Describe 'Backup-File' {
    It 'Creates a timestamped backup of an existing file' {
        $path = Join-Path $script:TestDir 'backup-target.txt'
        'content' | Set-Content -LiteralPath $path -Encoding UTF8 -NoNewline
        $result = Backup-File -Path $path -BackupCount 2
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Exist
        Test-Path -LiteralPath $result.BackupPath | Should -Be $true
    }

    It 'Returns success with no backup path when source does not exist' {
        $result = Backup-File -Path (Join-Path $script:TestDir 'does-not-exist.txt')
        $result.Success | Should -Be $true
        $result.BackupPath | Should -BeNullOrEmpty
    }
}

Describe 'Backup-AndWrite' {
    It 'Backs up existing file before writing new content' {
        $path = Join-Path $script:TestDir 'baw.txt'
        'original' | Set-Content -LiteralPath $path -Encoding UTF8 -NoNewline
        $result = Backup-AndWrite -Path $path -Content 'updated' -Format Text
        $result.Success | Should -Be $true
        Get-Content -LiteralPath $path -Raw | Should -Be 'updated'
    }
}

Describe 'Sync-File' {
    It 'Returns true for an existing file' {
        $path = Join-Path $script:TestDir 'sync.txt'
        'data' | Set-Content -LiteralPath $path -Encoding UTF8 -NoNewline
        Sync-File -Path $path | Should -Be $true
    }

    It 'Returns false for a non-existent file' {
        Sync-File -Path (Join-Path $script:TestDir 'nope.txt') | Should -Be $false
    }
}

Describe 'Sync-Directory' {
    It 'Returns true for an existing directory' {
        Sync-Directory -Path $script:TestDir | Should -Be $true
    }

    It 'Returns false for a non-existent directory' {
        Sync-Directory -Path (Join-Path $script:TestDir 'not-a-dir') | Should -Be $false
    }
}

Describe 'Invoke-AtomicRollback' {
    It 'Restores file from simple backup suffix' {
        $path = Join-Path $script:TestDir 'rollback.txt'
        'original' | Set-Content -LiteralPath $path -Encoding UTF8 -NoNewline
        $backup = "$path.backup"
        Copy-Item -LiteralPath $path -Destination $backup -Force
        'corrupted' | Set-Content -LiteralPath $path -Encoding UTF8 -NoNewline

        $result = Invoke-AtomicRollback -Path $path
        $result.Success | Should -Be $true
        Get-Content -LiteralPath $path -Raw | Should -Be 'original'
    }

    It 'Returns failure when no backup exists' {
        $path = Join-Path $script:TestDir 'nobackup.txt'
        'data' | Set-Content -LiteralPath $path -Encoding UTF8 -NoNewline
        $result = Invoke-AtomicRollback -Path $path
        $result.Success | Should -Be $false
    }
}

Describe 'Test-FileIntegrity' {
    It 'Validates existing file with expected size' {
        $path = Join-Path $script:TestDir 'integrity.txt'
        'abc' | Set-Content -LiteralPath $path -Encoding UTF8 -NoNewline
        $size = (Get-Item -LiteralPath $path).Length
        $result = Test-FileIntegrity -Path $path -ExpectedSize $size
        $result.IsValid | Should -Be $true
    }

    It 'Returns invalid when file does not exist' {
        $result = Test-FileIntegrity -Path (Join-Path $script:TestDir 'missing.bin')
        $result.IsValid | Should -Be $false
    }

    It 'Returns invalid on size mismatch' {
        $path = Join-Path $script:TestDir 'integrity.txt'
        'abc' | Set-Content -LiteralPath $path -Encoding UTF8 -NoNewline
        $result = Test-FileIntegrity -Path $path -ExpectedSize 9999
        $result.IsValid | Should -Be $false
    }
}

Describe 'Add-JsonLine' {
    It 'Appends a JSON object line to a JSONL file' {
        $path = Join-Path $script:TestDir 'log.jsonl'
        $result = Add-JsonLine -Path $path -Data @{ event = 'test' }
        $result.Success | Should -Be $true
        $result.LineNumber | Should -BeGreaterThan 0
        @((Get-Content -LiteralPath $path)).Count | Should -Be 1
    }
}
}