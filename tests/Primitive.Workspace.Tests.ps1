#requires -Version 5.1
<#
.SYNOPSIS
    Primitive tests for Workspace.ps1
.DESCRIPTION
    Pester v5 tests for workspace creation, switching, validation, and removal.
#>

Describe 'Primitive.Workspace Tests' {
BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..\module\LLMWorkflow\core\Workspace.ps1'
    if (Test-Path $script:ModulePath) {
        try { . $script:ModulePath } catch { if ($_.Exception.Message -notlike '*Export-ModuleMember*') { throw } }
    }
    else {
        throw "Module not found: $script:ModulePath"
    }

    $script:TestDir = Join-Path $TestDrive 'WorkspaceTests'
    New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null

    # Redirect workspace storage to test directory
    $script:OriginalStoragePath = $script:WorkspaceStoragePath
    $script:WorkspaceStoragePath = Join-Path $script:TestDir 'workspaces'
    Initialize-WorkspaceStorage
}

AfterAll {
    # Restore original storage path and clean up any created default workspace under real HOME
    $script:WorkspaceStoragePath = $script:OriginalStoragePath
    $realWorkspaceDir = Join-Path (Join-Path $HOME '.llm-workflow') 'workspaces'
    if (Test-Path $realWorkspaceDir) {
        Remove-Item -LiteralPath $realWorkspaceDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $realLlmDir = Join-Path $HOME '.llm-workflow'
    if (Test-Path $realLlmDir) {
        Remove-Item -LiteralPath $realLlmDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

AfterEach {
    # Clean test workspace storage between tests
    if (Test-Path (Join-Path $script:TestDir 'workspaces')) {
        Remove-Item -LiteralPath (Join-Path $script:TestDir 'workspaces\*.json') -Force -ErrorAction SilentlyContinue
    }
    $script:CurrentWorkspace = $null
    [Environment]::SetEnvironmentVariable('LLM_WORKFLOW_CURRENT_WORKSPACE', $null, 'Process')
}

Describe 'New-Workspace' {
    It 'Creates a new workspace with required fields' {
        $ws = New-Workspace -WorkspaceId 'test-proj' -Type 'project' -DisplayName 'Test Project'
        $ws.workspaceId | Should -Be 'test-proj'
        $ws.type | Should -Be 'project'
        $ws.displayName | Should -Be 'Test Project'
        (Join-Path $script:WorkspaceStoragePath 'test-proj.json') | Should -Exist
    }

    It 'Throws when workspace ID is invalid' {
        { New-Workspace -WorkspaceId '123' -Type 'project' } | Should -Throw '*Invalid workspace ID*'
    }

    It 'Throws when workspace already exists' {
        New-Workspace -WorkspaceId 'dup-proj' -Type 'project' | Out-Null
        { New-Workspace -WorkspaceId 'dup-proj' -Type 'project' } | Should -Throw '*already exists*'
    }

    It 'Throws when using reserved workspace ID' {
        { New-Workspace -WorkspaceId 'admin' -Type 'personal' } | Should -Throw '*Invalid workspace ID*'
    }
}

Describe 'Get-CurrentWorkspace / Switch-Workspace' {
    It 'Switches to an existing workspace and caches it' {
        New-Workspace -WorkspaceId 'switch-proj' -Type 'project' | Out-Null
        $ws = Switch-Workspace -WorkspaceId 'switch-proj'
        $ws.workspaceId | Should -Be 'switch-proj'

        $current = Get-CurrentWorkspace
        $current.workspaceId | Should -Be 'switch-proj'
    }

    It 'Throws when switching to non-existent workspace' {
        { Switch-Workspace -WorkspaceId 'missing-proj' } | Should -Throw '*not found*'
    }
}

Describe 'Get-WorkspacePacks' {
    It 'Returns packs enabled in a workspace' {
        New-Workspace -WorkspaceId 'pack-proj' -Type 'project' -PacksEnabled @('pack-a', 'pack-b') | Out-Null
        $packs = Get-WorkspacePacks -WorkspaceId 'pack-proj'
        $packs | Should -Contain 'pack-a'
        $packs | Should -Contain 'pack-b'
    }

    It 'Returns empty array when no packs are enabled' {
        New-Workspace -WorkspaceId 'empty-proj' -Type 'project' | Out-Null
        $packs = Get-WorkspacePacks -WorkspaceId 'empty-proj'
        $packs | Should -BeNullOrEmpty
    }
}

Describe 'Test-WorkspaceContext' {
    It 'Returns valid for a well-formed workspace' {
        New-Workspace -WorkspaceId 'valid-proj' -Type 'project' -PacksEnabled @('core') | Out-Null
        $result = Test-WorkspaceContext -WorkspaceId 'valid-proj'
        $result.Valid | Should -Be $true
        $result.Checks.SchemaVersion | Should -Be $true
        $result.Checks.ValidType | Should -Be $true
    }

    It 'Returns invalid when required pack is missing' {
        New-Workspace -WorkspaceId 'no-pack-proj' -Type 'project' | Out-Null
        $result = Test-WorkspaceContext -WorkspaceId 'no-pack-proj' -RequiredPacks @('missing-pack')
        $result.Valid | Should -Be $false
        $result.Errors | Should -Contain 'Required pack not enabled: missing-pack'
    }

    It 'Returns invalid when project type is required but not set' {
        New-Workspace -WorkspaceId 'personal-ws' -Type 'personal' | Out-Null
        $result = Test-WorkspaceContext -WorkspaceId 'personal-ws' -RequireProjectType
        $result.Valid | Should -Be $false
        $result.Errors | Should -Contain "Workspace must be type 'project', found: personal"
    }
}

Describe 'Get-WorkspaceList' {
    It 'Lists all workspaces' {
        New-Workspace -WorkspaceId 'list-a' -Type 'project' | Out-Null
        New-Workspace -WorkspaceId 'list-b' -Type 'project' | Out-Null
        $list = Get-WorkspaceList
        $ids = $list | ForEach-Object { $_.WorkspaceId }
        $ids | Should -Contain 'list-a'
        $ids | Should -Contain 'list-b'
    }
}

Describe 'Remove-Workspace' {
    It 'Removes an existing workspace' {
        New-Workspace -WorkspaceId 'remove-me' -Type 'project' | Out-Null
        (Join-Path $script:WorkspaceStoragePath 'remove-me.json') | Should -Exist
        Remove-Workspace -WorkspaceId 'remove-me' -Force
        (Join-Path $script:WorkspaceStoragePath 'remove-me.json') | Should -Not -Exist
    }

    It 'Throws when removing the default personal workspace' {
        { Remove-Workspace -WorkspaceId 'personal-default' -Force } | Should -Throw '*Cannot remove the default personal workspace*'
    }

    It 'Throws when workspace does not exist' {
        { Remove-Workspace -WorkspaceId 'no-such-ws' -Force } | Should -Throw '*not found*'
    }
}
}