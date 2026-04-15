#requires -Version 5.1

BeforeAll {
    $modulePath = Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'module') 'LLMWorkflow\DashboardViews.ps1'
    . $modulePath
}

Describe 'DashboardViews hardening' {
    Context 'Get-PackList' {
        It 'Returns empty list when manifest scan throws unexpectedly' {
            $projectRoot = Join-Path $TestDrive 'proj-manifest-scan'
            $manifestDir = Join-Path $projectRoot 'packs/manifests'
            New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null

            Mock Get-ChildItem {
                throw [System.IO.IOException]::new('manifest scan failed')
            } -ParameterFilter { $Path -eq $manifestDir -and $Filter -eq '*.json' }

            $packs = Get-PackList -ProjectRoot $projectRoot
            @($packs).Count | Should -Be 0
        }
    }

    Context 'Show-PackHealthDashboard' {
        It 'Falls back to basic health when Test-PackHealth command probe throws' {
            $projectRoot = Join-Path $TestDrive 'proj-health-fallback'
            $manifestDir = Join-Path $projectRoot 'packs/manifests'
            New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null

            '{"packId":"demo-pack","domain":"demo","version":"1.0.0"}' |
                Set-Content -LiteralPath (Join-Path $manifestDir 'demo-pack.json') -Encoding UTF8

            Mock Get-Command {
                throw [System.InvalidOperationException]::new('unexpected command resolution failure')
            } -ParameterFilter { $Name -eq 'Test-PackHealth' }

            $json = Show-PackHealthDashboard -ProjectRoot $projectRoot -OutputFormat JSON
            $data = $json | ConvertFrom-Json

            $data.summary.totalPacks | Should -BeGreaterThan 0
            @($data.packs.packId) | Should -Contain 'demo-pack'
        }
    }

    Context 'Show-CrossPackGraph' {
        It 'Uses known relationships when pipeline scan throws unexpectedly' {
            $projectRoot = Join-Path $TestDrive 'proj-graph-fallback'
            $manifestDir = Join-Path $projectRoot 'packs/manifests'
            $pipelinesDir = Join-Path $projectRoot '.llm-workflow/interpack/pipelines'
            New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
            New-Item -ItemType Directory -Path $pipelinesDir -Force | Out-Null

            '{"packId":"demo-pack","domain":"demo","version":"1.0.0"}' |
                Set-Content -LiteralPath (Join-Path $manifestDir 'demo-pack.json') -Encoding UTF8

            Mock Get-ChildItem {
                throw [System.IO.IOException]::new('pipeline scan failed')
            } -ParameterFilter { $Path -eq $pipelinesDir -and $Filter -eq '*.json' }

            $json = Show-CrossPackGraph -ProjectRoot $projectRoot -OutputFormat JSON
            $data = $json | ConvertFrom-Json

            @($data.edges).Count | Should -Be 2
        }
    }

    Context 'Show-MCPGatewayStatus' {
        It 'Falls back to demo gateway data when command probe throws' {
            Mock Get-Command {
                throw [System.InvalidOperationException]::new('status command probe failed')
            } -ParameterFilter { $Name -eq 'Get-MCPCompositeGatewayStatus' }

            $json = Show-MCPGatewayStatus -OutputFormat JSON
            $data = $json | ConvertFrom-Json

            $data.gatewayStatus.isRunning | Should -Be $true
            @($data.circuitBreakers).Count | Should -BeGreaterThan 0
        }
    }

    Context 'Show-FederationStatus' {
        It 'Falls back to demo federation data when command probe throws' {
            Mock Get-Command {
                throw [System.InvalidOperationException]::new('federation command probe failed')
            } -ParameterFilter { $Name -eq 'Get-MemoryFederations' }

            $json = Show-FederationStatus -OutputFormat JSON
            $data = $json | ConvertFrom-Json

            $data.summary.totalNodes | Should -BeGreaterThan 0
            @($data.nodes).Count | Should -BeGreaterThan 0
        }
    }
}
