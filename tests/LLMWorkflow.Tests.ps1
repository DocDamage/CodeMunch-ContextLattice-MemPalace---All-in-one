Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$manifestPath = Join-Path $repoRoot "module\LLMWorkflow\LLMWorkflow.psd1"

Describe "LLMWorkflow Module" {
    BeforeAll {
        Import-Module $manifestPath -Force
    }

    It "exports expected commands" {
        (Get-Command Install-LLMWorkflow -ErrorAction Stop).Source | Should Be "LLMWorkflow"
        (Get-Command Invoke-LLMWorkflowUp -ErrorAction Stop).Source | Should Be "LLMWorkflow"
        (Get-Command llmup -ErrorAction Stop).CommandType | Should Be "Alias"
    }

    It "bootstraps missing tool folders and loads .env values" {
        $projectRoot = Join-Path $TestDrive "sample-project"
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null

        $glmBaseUrl = "https://example.test/glm"
        $kimiKey = "kimi_test_key"
        @"
GLM_BASE_URL=$glmBaseUrl
KIMI_API_KEY=$kimiKey
"@ | Set-Content -LiteralPath (Join-Path $projectRoot ".env") -Encoding UTF8

        Invoke-LLMWorkflowUp `
            -ProjectRoot $projectRoot `
            -SkipDependencyInstall `
            -SkipContextVerify `
            -SkipBridgeDryRun

        (Test-Path -LiteralPath (Join-Path $projectRoot "tools\codemunch")) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $projectRoot "tools\contextlattice")) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $projectRoot "tools\memorybridge")) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $projectRoot ".codemunch\index.defaults.json")) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $projectRoot ".contextlattice\orchestrator.env.sample")) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $projectRoot ".memorybridge\bridge.config.json")) | Should Be $true
        $env:GLM_BASE_URL | Should Be $glmBaseUrl
        $env:KIMI_API_KEY | Should Be $kimiKey
    }

    It "updates profile idempotently during install" {
        $installRoot = Join-Path $TestDrive "llm-workflow-home"
        $profilePath = Join-Path $TestDrive "Microsoft.PowerShell_profile.ps1"

        Install-LLMWorkflow `
            -InstallRoot $installRoot `
            -ProfilePath $profilePath `
            -SkipUserEnvPersist

        Install-LLMWorkflow `
            -InstallRoot $installRoot `
            -ProfilePath $profilePath `
            -SkipUserEnvPersist

        $profileContent = Get-Content -LiteralPath $profilePath -Raw
        ([regex]::Matches($profileContent, "# >>> llm-workflow >>>")).Count | Should Be 1
        ([regex]::Matches($profileContent, "# <<< llm-workflow <<<")).Count | Should Be 1
        $profileContent | Should Match "Set-Alias llmup llm-workflow-up -Scope Global"
    }
}
