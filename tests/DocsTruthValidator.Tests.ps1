#requires -Version 5.1
<#
.SYNOPSIS
    Tests for the documentation truth validator.

.DESCRIPTION
    Verifies that the CI-facing docs-truth validation script executes
    successfully on the current repository and reports the expected live
    version and metric counts.
#>

BeforeAll {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ValidatorPath = Join-Path $script:ProjectRoot 'tools\ci\validate-docs-truth.ps1'
    $isWindowsHost = $PSVersionTable.PSEdition -eq 'Desktop' -or [System.Environment]::OSVersion.Platform -eq 'Win32NT'
    $script:ShellExe = if ($isWindowsHost) { 'powershell' } else { 'pwsh' }

    function Invoke-DocsTruthValidatorProcess {
        $args = @('-NoProfile', '-File', $script:ValidatorPath)
        if ($script:ShellExe -eq 'powershell') {
            $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:ValidatorPath)
        }

        $output = & $script:ShellExe @args 2>&1
        $exitCode = $LASTEXITCODE

        [pscustomobject]@{
            ExitCode = $exitCode
            Output   = @($output)
            Text     = (@($output) -join [Environment]::NewLine)
        }
    }

    $script:ExpectedVersion = (Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'VERSION') -Raw).Trim()
    $script:ExpectedModules = (Get-ChildItem -Path (Join-Path $script:ProjectRoot 'module\LLMWorkflow') -Filter '*.ps1' -Recurse |
        Where-Object {
            $_.Name -notlike '*.Tests.ps1' -and
            $_.FullName -notlike '*\templates\*' -and
            $_.FullName -notlike '*\LLMWorkflow\scripts\*'
        }).Count
    $script:ExpectedPacks = (Get-ChildItem -Path (Join-Path $script:ProjectRoot 'packs\manifests') -Filter '*.json' |
        Where-Object {
            Test-Path (Join-Path (Join-Path $script:ProjectRoot 'packs\registries') ($_.BaseName + '.sources.json'))
        }).Count
    $script:ExpectedParsers = (Get-ChildItem -Path (Join-Path $script:ProjectRoot 'module\LLMWorkflow\ingestion\parsers') -Filter '*.ps1' |
        Where-Object {
            $_.Name -notlike '*.Tests.ps1' -and
            ($_.Name.EndsWith('Parser.ps1') -or $_.Name.EndsWith('Extractor.ps1'))
        }).Count
    $script:ExpectedGoldenTasks = (Select-String -Path (Join-Path $script:ProjectRoot 'module\LLMWorkflow\governance\GoldenTaskDefinitions.ps1') -Pattern '-TaskId "gt-').Count
    $script:ExpectedMcpTools = 55
}

Describe 'validate-docs-truth.ps1' {
    It 'exists in tools/ci' {
        Test-Path -LiteralPath $script:ValidatorPath | Should -Be $true
    }

    It 'runs successfully against the current repository' {
        $result = Invoke-DocsTruthValidatorProcess

        if ($result.ExitCode -ne 0) {
            Write-Host $result.Text
        }

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match 'Documentation truth validated successfully\.'
    }

    It 'reports the expected live version and metric counts' {
        $result = Invoke-DocsTruthValidatorProcess

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match ("Version:\s+{0}" -f [regex]::Escape($script:ExpectedVersion))
        $result.Text | Should -Match ("Modules:\s+{0}" -f $script:ExpectedModules)
        $result.Text | Should -Match ("Packs:\s+{0}" -f $script:ExpectedPacks)
        $result.Text | Should -Match ("Parsers:\s+{0}" -f $script:ExpectedParsers)
        $result.Text | Should -Match ("Golden Tasks:\s+{0}" -f $script:ExpectedGoldenTasks)
        $result.Text | Should -Match ("MCP Tools:\s+{0}" -f $script:ExpectedMcpTools)
    }
}
