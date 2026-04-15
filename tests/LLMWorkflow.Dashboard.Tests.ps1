#requires -Version 5.1

BeforeAll {
    $scriptPath = Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'module') 'LLMWorkflow\LLMWorkflow.Dashboard.ps1'
    . $scriptPath
}

Describe 'LLMWorkflow.Dashboard hardening' {
    BeforeEach {
        $script:SavedEnv = @{
            OPENAI_API_KEY                       = $env:OPENAI_API_KEY
            KIMI_API_KEY                         = $env:KIMI_API_KEY
            GEMINI_API_KEY                       = $env:GEMINI_API_KEY
            GLM_API_KEY                          = $env:GLM_API_KEY
            CONTEXTLATTICE_ORCHESTRATOR_URL      = $env:CONTEXTLATTICE_ORCHESTRATOR_URL
            CONTEXTLATTICE_ORCHESTRATOR_API_KEY  = $env:CONTEXTLATTICE_ORCHESTRATOR_API_KEY
        }

        $env:OPENAI_API_KEY = ''
        $env:KIMI_API_KEY = ''
        $env:GEMINI_API_KEY = ''
        $env:GLM_API_KEY = ''
        $env:CONTEXTLATTICE_ORCHESTRATOR_URL = ''
        $env:CONTEXTLATTICE_ORCHESTRATOR_API_KEY = ''
    }

    AfterEach {
        foreach ($entry in $script:SavedEnv.GetEnumerator()) {
            Set-Item -Path "env:$($entry.Key)" -Value ([string]$entry.Value)
        }
    }

    It 'Allows dot-sourcing without executing the dashboard loop' {
        Get-Command -Name Invoke-LLMWorkflowDashboardMain -CommandType Function | Should -Not -BeNullOrEmpty
        Get-Command -Name Invoke-DashboardCheck -CommandType Function | Should -Not -BeNullOrEmpty
    }

    It 'Handles python command probe exceptions without throwing' {
        Mock Get-Command {
            throw [System.InvalidOperationException]::new('python probe failed')
        } -ParameterFilter { $Name -eq 'python' }
        Mock Resolve-ProviderProfile { $null }

        $result = Invoke-DashboardCheck -ProjectRoot $TestDrive -Provider 'auto' -TimeoutSec 1 -OnCheckComplete { param($c, $t, $n, $s, $d, $l) }
        $pythonCheck = @($result.Checks | Where-Object { $_.Name -eq 'python_command' })[0]

        $pythonCheck.Ok | Should -Be $false
        @($result.Checks.Name) | Should -Contain 'codemunch_runtime'
    }

    It 'Handles codemunch command probe exceptions without throwing' {
        Mock Get-Command {
            [pscustomobject]@{ Name = 'python'; Source = 'python.exe' }
        } -ParameterFilter { $Name -eq 'python' }
        Mock Get-Command {
            throw [System.InvalidOperationException]::new('codemunch probe failed')
        } -ParameterFilter { $Name -eq 'codemunch-pro' }
        Mock Get-PythonVersion { '3.11.0' }
        Mock Test-PythonImport { $false }
        Mock Resolve-ProviderProfile { $null }

        $result = Invoke-DashboardCheck -ProjectRoot $TestDrive -Provider 'auto' -TimeoutSec 1 -OnCheckComplete { param($c, $t, $n, $s, $d, $l) }
        $runtimeCheck = @($result.Checks | Where-Object { $_.Name -eq 'codemunch_runtime' })[0]

        $runtimeCheck.Ok | Should -Be $false
        $runtimeCheck.Detail | Should -Match 'Install with'
    }

    It 'Classifies version floor misses as WARN instead of FAIL' {
        $check = [pscustomobject]@{
            Name = 'chromadb_version'
            Ok = $false
            Detail = 'Found 0.4.24, need >= 0.5.0'
        }

        (Get-DashboardCheckStatus -Check $check) | Should -Be 'WARN'
    }

    It 'Classifies skipped context connectivity checks as WARN' {
        $check = [pscustomobject]@{
            Name = 'contextlattice_health'
            Ok = $false
            Detail = 'Missing context env vars; cannot run connectivity test.'
        }

        (Get-DashboardCheckStatus -Check $check) | Should -Be 'WARN'
    }

    It 'Reports warning-only plain-text runs as passed with WARN status lines' {
        $checks = @(
            [pscustomobject]@{
                Name = 'chromadb_version'
                Ok = $false
                Detail = 'Found 0.4.24, need >= 0.5.0'
                LatencyMs = $null
            }
        )

        $output = @(Write-PlainTextReport -Checks $checks -ProjectPath $TestDrive -Provider 'auto' -ProviderResolved $null)

        ($output -join "`n") | Should -Match '\[WARN\]\s+chromadb_version'
        $output[-1] | Should -Be '[llm-workflow-doctor] all checks passed'
    }
}
