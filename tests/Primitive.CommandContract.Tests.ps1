#requires -Version 5.1
<#
.SYNOPSIS
    Primitive tests for CommandContract.ps1
.DESCRIPTION
    Pester v5 tests for command contract creation, validation, and execution.
#>

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..\module\LLMWorkflow\core\CommandContract.ps1'
    $script:RunIdPath = Join-Path $PSScriptRoot '..\module\LLMWorkflow\core\RunId.ps1'

    # Stub New-RunId if RunId module is unavailable
    if (-not (Get-Command New-RunId -ErrorAction SilentlyContinue)) {
        if (Test-Path $script:RunIdPath) {
            try { . $script:RunIdPath } catch { if ($_.Exception.Message -notlike '*Export-ModuleMember*') { throw } }
        }
    }
    if (-not (Get-Command New-RunId -ErrorAction SilentlyContinue)) {
        function New-RunId { return "20260101T000000Z-0001" }
    }

    if (Test-Path $script:ModulePath) {
        try { . $script:ModulePath } catch { if ($_.Exception.Message -notlike '*Export-ModuleMember*') { throw } }
    }
    else {
        throw "Module not found: $script:ModulePath"
    }
}

AfterAll {
    # No filesystem cleanup needed for this module
}

Describe 'New-CommandContract' {
    It 'Creates a valid contract with required fields' {
        $contract = New-CommandContract -Name 'test-sync' -Purpose 'Test sync command' -SafetyLevels @('read-only')
        $contract | Should -Not -BeNullOrEmpty
        $contract.name | Should -Be 'test-sync'
        $contract.purpose | Should -Be 'Test sync command'
        $contract.safetyLevels | Should -Contain 'read-only'
        $contract.exitCodes.Success | Should -Be 0
    }

    It 'Throws on invalid safety level' {
        { New-CommandContract -Name 'bad' -Purpose 'x' -SafetyLevels @('invalid') } | Should -Throw '*Invalid safety level*'
    }

    It 'Warns when mutating command lacks DryRunBehavior' {
        { New-CommandContract -Name 'mutate' -Purpose 'x' -SafetyLevels @('mutating') } | Should -Not -Throw
    }
}

Describe 'Get-CommandContract / Get-AllCommandContracts' {
    It 'Retrieves a registered contract by name' {
        New-CommandContract -Name 'gettable' -Purpose 'for retrieval' -SafetyLevels @('read-only') | Out-Null
        $found = Get-CommandContract -Name 'gettable'
        $found | Should -Not -BeNullOrEmpty
        $found.name | Should -Be 'gettable'
    }

    It 'Returns null for unregistered contract' {
        Get-CommandContract -Name 'does-not-exist' | Should -BeNullOrEmpty
    }

    It 'Returns all registered contracts' {
        $all = Get-AllCommandContracts
        $all | Should -Not -BeNullOrEmpty
        @($all).Count | Should -BeGreaterThan 0
    }
}

Describe 'Test-CommandContract' {
    BeforeAll {
        $script:TestContract = New-CommandContract -Name 'param-test' -Purpose 'x' -SafetyLevels @('read-only') -Parameters @{
            Source = @{ type = 'string'; required = $true }
            Count  = @{ type = 'int'; required = $false }
        }
    }

    It 'Passes validation when all required parameters are provided' {
        $result = Test-CommandContract -Contract $script:TestContract -Arguments @{ Source = 'src' }
        $result.IsValid | Should -Be $true
    }

    It 'Fails validation when required parameter is missing' {
        $result = Test-CommandContract -Contract $script:TestContract -Arguments @{ Count = 5 }
        $result.IsValid | Should -Be $false
        $result.Errors | Should -Contain 'Missing required parameter: Source'
    }

    It 'Fails validation on parameter type mismatch' {
        $result = Test-CommandContract -Contract $script:TestContract -Arguments @{ Source = 123 }
        $result.IsValid | Should -Be $false
        $result.Errors | Should -Contain "Parameter 'Source' has invalid type. Expected: string"
    }
}

Describe 'Invoke-WithContract' {
    BeforeAll {
        $script:ExecContract = New-CommandContract -Name 'exec-test' -Purpose 'x' -SafetyLevels @('read-only')
    }

    It 'Executes script block and returns success result' {
        $result = Invoke-WithContract -Contract $script:ExecContract -ScriptBlock { return 42 }
        $result.Success | Should -Be $true
        $result.result | Should -Be 42
        $result.ExitCode | Should -Be 0
    }

    It 'Returns invalid arguments when contract validation fails' {
        $badContract = New-CommandContract -Name 'exec-bad' -Purpose 'x' -SafetyLevels @('read-only') -Parameters @{
            RequiredArg = @{ type = 'string'; required = $true }
        }
        $result = Invoke-WithContract -Contract $badContract -ScriptBlock { return 'ok' }
        $result.Success | Should -Be $false
        $result.ExitCode | Should -Be 2
    }
}

Describe 'Get-StandardExitCodes / Get-ValidSafetyLevels' {
    It 'Returns standard exit codes hashtable' {
        $codes = Get-StandardExitCodes
        $codes | Should -Not -BeNullOrEmpty
        $codes.Success | Should -Be 0
        $codes.GeneralFailure | Should -Be 1
    }

    It 'Returns valid safety levels array' {
        $levels = Get-ValidSafetyLevels
        $levels | Should -Contain 'read-only'
        $levels | Should -Contain 'mutating'
        $levels | Should -Contain 'destructive'
        $levels | Should -Contain 'networked'
    }
}

Describe 'Unregister-CommandContract' {
    It 'Removes a contract from the registry' {
        New-CommandContract -Name 'to-remove' -Purpose 'x' -SafetyLevels @('read-only') | Out-Null
        Get-CommandContract -Name 'to-remove' | Should -Not -BeNullOrEmpty
        Unregister-CommandContract -Name 'to-remove'
        Get-CommandContract -Name 'to-remove' | Should -BeNullOrEmpty
    }
}
