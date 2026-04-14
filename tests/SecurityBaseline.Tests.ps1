#requires -Version 5.1
<#
.SYNOPSIS
    Security Baseline Tests for LLM Workflow Platform

.DESCRIPTION
    Pester v5 test suite for Workstream 5 security and supply-chain
    enforcement scripts:
    - Invoke-SecurityBaseline.ps1: orchestration and promotion gates
    - Invoke-SBOMBuild.ps1: SBOM generation and component discovery
    - Invoke-SecretScan.ps1: regex-based secret detection
    - Invoke-VulnerabilityScan.ps1: configuration vulnerability patterns

.NOTES
    File: SecurityBaseline.Tests.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Requires: Pester 5.0+
#>

BeforeAll {
    $script:TestRoot = Join-Path $TestDrive "SecurityBaselineTests"
    $script:SecurityScriptPath = Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "scripts") "security"

    New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null

    $baselinePath = Join-Path $script:SecurityScriptPath "Invoke-SecurityBaseline.ps1"
    $sbomPath = Join-Path $script:SecurityScriptPath "Invoke-SBOMBuild.ps1"
    $secretPath = Join-Path $script:SecurityScriptPath "Invoke-SecretScan.ps1"
    $vulnPath = Join-Path $script:SecurityScriptPath "Invoke-VulnerabilityScan.ps1"

    if (Test-Path $baselinePath) { try { . $baselinePath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
    if (Test-Path $sbomPath) { try { . $sbomPath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
    if (Test-Path $secretPath) { try { . $secretPath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
    if (Test-Path $vulnPath) { try { . $vulnPath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
}

Describe "Invoke-SecurityBaseline Orchestration" {
    Context "Baseline invocation with mock scans" {
        BeforeEach {
            $script:ReportsDir = Join-Path $script:TestRoot "reports"
            if (Test-Path $script:ReportsDir) {
                Remove-Item -Path $script:ReportsDir -Recurse -Force
            }
        }

        It "Should run all scans and produce a consolidated report" {
            $result = Invoke-SecurityBaseline -ProjectRoot $script:TestRoot -OutputPath $script:ReportsDir

            $result | Should -Not -BeNullOrEmpty
            $result.overallPassed | Should -Be $true
            $result.scans.secretScan.summary.scannedFiles | Should -Not -BeNullOrEmpty
            $result.scans.sbom.success | Should -Be $true
            $result.scans.vulnerabilityScan.summary.scannedFiles | Should -Not -BeNullOrEmpty
            $result.promotionGate.Passed | Should -Be $true
        }

        It "Should write report files to the output directory" {
            Invoke-SecurityBaseline -ProjectRoot $script:TestRoot -OutputPath $script:ReportsDir | Out-Null

            $reportFiles = Get-ChildItem -Path $script:ReportsDir -Filter "*.json"
            $reportFiles.Count | Should -BeGreaterOrEqual 4
        }

        It "Should fail on critical findings when -FailOnCritical is specified" {
            # Create a file with a critical secret
            $secretFile = Join-Path $script:TestRoot "secret.env"
            'API_KEY=sk-123456789012345678901234567890123456789012345678' | Set-Content -LiteralPath $secretFile

            { Invoke-SecurityBaseline -ProjectRoot $script:TestRoot -OutputPath $script:ReportsDir -FailOnCritical } |
                Should -Throw -ExpectedMessage "*Critical findings detected*"
        }

        It "Should block promotion when thresholds are exceeded" {
            # Clean up any lingering secret files from previous tests
            $secretFile = Join-Path $script:TestRoot "secret.env"
            if (Test-Path $secretFile) {
                Remove-Item -LiteralPath $secretFile -Force
            }

            # Create a file with a high-severity vulnerability pattern
            $composeFile = Join-Path $script:TestRoot "docker-compose.yml"
            "services:`n  app:`n    privileged: true" | Set-Content -LiteralPath $composeFile

            $result = Invoke-SecurityBaseline -ProjectRoot $script:TestRoot -OutputPath $script:ReportsDir -MaxAllowedHigh 0

            $result.promotionGate.Passed | Should -Be $false
            $result.promotionGate.BlockedBy | Should -Contain "vulns-high"
        }
    }
}

Describe "Invoke-SBOMBuild" {
    Context "SBOM generation validation" {
        BeforeEach {
            $script:SbomTestDir = Join-Path $script:TestRoot "sbom-test"
            if (Test-Path $script:SbomTestDir) {
                Remove-Item -Path $script:SbomTestDir -Recurse -Force
            }
            New-Item -ItemType Directory -Path $script:SbomTestDir -Force | Out-Null
        }

        It "Should generate a valid CycloneDX SBOM" {
            $outputPath = Join-Path $script:SbomTestDir "sbom.json"
            $result = Invoke-SBOMBuild -ProjectRoot $script:SbomTestDir -OutputPath $outputPath

            $result.success | Should -Be $true
            Test-Path $outputPath | Should -Be $true

            $sbom = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
            $sbom.bomFormat | Should -Be 'CycloneDX'
            $sbom.specVersion | Should -Be '1.5'
            $sbom.metadata.tools[0].name | Should -Match 'Syft-compatible'
        }

        It "Should discover PowerShell module components" {
            $moduleDir = Join-Path (Join-Path $script:SbomTestDir "module") "TestModule"
            New-Item -ItemType Directory -Path $moduleDir -Force | Out-Null
            '@{ ModuleVersion = "1.2.3"; RootModule = "TestModule.psm1" }' |
                Set-Content -LiteralPath (Join-Path $moduleDir "TestModule.psd1")

            $components = Get-SBOMComponents -ProjectRoot $script:SbomTestDir

            $moduleComponent = $components | Where-Object { $_.name -eq 'TestModule' }
            $moduleComponent | Should -Not -BeNullOrEmpty
            $moduleComponent.type | Should -Be 'library'
            $moduleComponent.version | Should -Be '1.2.3'
            $moduleComponent.purl | Should -Be 'pkg:powershell/TestModule@1.2.3'
        }

        It "Should discover JSON config components" {
            '{ "version": "2.0", "name": "app-config" }' |
                Set-Content -LiteralPath (Join-Path $script:SbomTestDir "app-config.json")

            $components = Get-SBOMComponents -ProjectRoot $script:SbomTestDir

            $configComponent = $components | Where-Object { $_.name -eq 'app-config' }
            $configComponent | Should -Not -BeNullOrEmpty
            $configComponent.type | Should -Be 'configuration'
            ($configComponent.properties | Where-Object { $_.name -eq 'configVersion' }).value | Should -Be '2.0'
        }

        It "Should discover Dockerfile components" {
            'FROM node:18-alpine' |
                Set-Content -LiteralPath (Join-Path $script:SbomTestDir "Dockerfile")

            $components = Get-SBOMComponents -ProjectRoot $script:SbomTestDir

            $containerComponent = $components | Where-Object { $_.name -eq 'Dockerfile' }
            $containerComponent | Should -Not -BeNullOrEmpty
            $containerComponent.type | Should -Be 'container'
            ($containerComponent.properties | Where-Object { $_.name -eq 'baseImage' }).value | Should -Be 'node:18-alpine'
        }
    }
}

Describe "Invoke-SecretScan" {
    Context "Secret scan fixture detection" {
        BeforeEach {
            $script:SecretTestDir = Join-Path $script:TestRoot "secret-test"
            if (Test-Path $script:SecretTestDir) {
                Remove-Item -Path $script:SecretTestDir -Recurse -Force
            }
            New-Item -ItemType Directory -Path $script:SecretTestDir -Force | Out-Null
        }

        It "Should detect an OpenAI API key" {
            $testFile = Join-Path $script:SecretTestDir "config.ps1"
            ' $key = "sk-123456789012345678901234567890123456789012345678" ' |
                Set-Content -LiteralPath $testFile

            $result = Invoke-SecretScan -ProjectRoot $script:SecretTestDir

            $result.summary.totalFindings | Should -BeGreaterThan 0
            $result.findings | Where-Object { $_.PatternName -eq 'OpenAI_API_Key' } | Should -Not -BeNullOrEmpty
        }

        It "Should detect a JWT token" {
            $testFile = Join-Path $script:SecretTestDir "token.txt"
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U' |
                Set-Content -LiteralPath $testFile

            $result = Invoke-SecretScan -ProjectRoot $script:SecretTestDir

            $jwtFinding = $result.findings | Where-Object { $_.PatternName -eq 'JWT_Token' }
            $jwtFinding | Should -Not -BeNullOrEmpty
            $jwtFinding.Severity | Should -Be 'high'
        }

        It "Should respect severity threshold" {
            $testFile = Join-Path $script:SecretTestDir "email.txt"
            'contact@example.com' | Set-Content -LiteralPath $testFile

            $resultLow = Invoke-SecretScan -ProjectRoot $script:SecretTestDir -SeverityThreshold 'low'
            $resultHigh = Invoke-SecretScan -ProjectRoot $script:SecretTestDir -SeverityThreshold 'high'

            $resultLow.findings | Where-Object { $_.PatternName -eq 'Email_Address' } | Should -Not -BeNullOrEmpty
            $resultHigh.findings | Where-Object { $_.PatternName -eq 'Email_Address' } | Should -BeNullOrEmpty
        }

        It "Should write findings to JSON when -OutputPath is provided" {
            $testFile = Join-Path $script:SecretTestDir "secret.env"
            'AWS_KEY=AKIA1234567890ABCDEF' | Set-Content -LiteralPath $testFile

            $outputPath = Join-Path $script:SecretTestDir "findings.json"
            Invoke-SecretScan -ProjectRoot $script:SecretTestDir -OutputPath $outputPath | Out-Null

            Test-Path $outputPath | Should -Be $true
            $json = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
            $json.scanType | Should -Be 'secret'
            $json.findings.Count | Should -BeGreaterThan 0
        }
    }
}

Describe "Invoke-VulnerabilityScan" {
    Context "Vulnerability pattern detection" {
        BeforeEach {
            $script:VulnTestDir = Join-Path $script:TestRoot "vuln-test"
            if (Test-Path $script:VulnTestDir) {
                Remove-Item -Path $script:VulnTestDir -Recurse -Force
            }
            New-Item -ItemType Directory -Path $script:VulnTestDir -Force | Out-Null
        }

        It "Should detect Dockerfile :latest tag" {
            $dockerFile = Join-Path $script:VulnTestDir "Dockerfile"
            'FROM ubuntu:latest' | Set-Content -LiteralPath $dockerFile

            $result = Invoke-VulnerabilityScan -ProjectRoot $script:VulnTestDir

            $finding = $result.findings | Where-Object { $_.PatternName -eq 'Dockerfile_Latest_Tag' }
            $finding | Should -Not -BeNullOrEmpty
            $finding.Severity | Should -Be 'medium'
        }

        It "Should detect missing HEALTHCHECK in Dockerfile" {
            $dockerFile = Join-Path $script:VulnTestDir "Dockerfile"
            "FROM alpine:3.18`nRUN echo hello" | Set-Content -LiteralPath $dockerFile

            $result = Invoke-VulnerabilityScan -ProjectRoot $script:VulnTestDir

            $finding = $result.findings | Where-Object { $_.PatternName -eq 'Dockerfile_No_Healthcheck' }
            $finding | Should -Not -BeNullOrEmpty
            $finding.Severity | Should -Be 'low'
        }

        It "Should detect privileged container in docker-compose" {
            $composeFile = Join-Path $script:VulnTestDir "docker-compose.yml"
            "services:`n  app:`n    privileged: true" | Set-Content -LiteralPath $composeFile

            $result = Invoke-VulnerabilityScan -ProjectRoot $script:VulnTestDir

            $finding = $result.findings | Where-Object { $_.PatternName -eq 'DockerCompose_Privileged' }
            $finding | Should -Not -BeNullOrEmpty
            $finding.Severity | Should -Be 'high'
        }

        It "Should detect Invoke-Expression in PowerShell" {
            $scriptFile = Join-Path $script:VulnTestDir "dangerous.ps1"
            'Invoke-Expression $userInput' | Set-Content -LiteralPath $scriptFile

            $result = Invoke-VulnerabilityScan -ProjectRoot $script:VulnTestDir

            $finding = $result.findings | Where-Object { $_.PatternName -eq 'PowerShell_InvokeExpression' }
            $finding | Should -Not -BeNullOrEmpty
            $finding.Severity | Should -Be 'high'
        }
    }
}

Describe "Promotion Gate Logic" {
    Context "Test-PromotionGate internal function" {
        It "Should pass when no findings exceed thresholds" {
            $secretReport = [pscustomobject]@{
                summary = @{ critical = 0; high = 0 }
            }
            $vulnReport = [pscustomobject]@{
                summary = @{ critical = 0; high = 0 }
            }

            $gate = Test-PromotionGate -SecretScanReport $secretReport -VulnerabilityScanReport $vulnReport

            $gate.Passed | Should -Be $true
            $gate.BlockedBy.Count | Should -Be 0
        }

        It "Should block when secret critical exceeds threshold" {
            $secretReport = [pscustomobject]@{
                summary = @{ critical = 1; high = 0 }
            }
            $vulnReport = [pscustomobject]@{
                summary = @{ critical = 0; high = 0 }
            }

            $gate = Test-PromotionGate -SecretScanReport $secretReport -VulnerabilityScanReport $vulnReport

            $gate.Passed | Should -Be $false
            $gate.BlockedBy | Should -Contain 'secrets-critical'
        }

        It "Should block when vulnerability high exceeds threshold" {
            $secretReport = [pscustomobject]@{
                summary = @{ critical = 0; high = 0 }
            }
            $vulnReport = [pscustomobject]@{
                summary = @{ critical = 0; high = 2 }
            }

            $gate = Test-PromotionGate -SecretScanReport $secretReport -VulnerabilityScanReport $vulnReport -MaxAllowedHigh 1

            $gate.Passed | Should -Be $false
            $gate.BlockedBy | Should -Contain 'vulns-high'
        }

        It "Should allow high findings within threshold" {
            $secretReport = [pscustomobject]@{
                summary = @{ critical = 0; high = 1 }
            }
            $vulnReport = [pscustomobject]@{
                summary = @{ critical = 0; high = 1 }
            }

            $gate = Test-PromotionGate -SecretScanReport $secretReport -VulnerabilityScanReport $vulnReport -MaxAllowedHigh 2

            $gate.Passed | Should -Be $true
        }
    }
}
