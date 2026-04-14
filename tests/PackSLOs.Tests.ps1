#requires -Version 5.1
<#
.SYNOPSIS
    Tests for PackSLOs module.

.DESCRIPTION
    Unit tests for Pack SLO and Telemetry functionality.
#>

# Import the module
$modulePath = Join-Path $PSScriptRoot '..\module\LLMWorkflow\governance\PackSLOs.ps1'
try { . $modulePath } catch { if ($_.Exception.Message -notlike '*Export-ModuleMember*') { throw } }

# Test data
$testPackId = 'test-pack'
$testTelemetryDir = Join-Path (Join-Path $PSScriptRoot '..') '.llm-workflow\telemetry'

# Helper function to clean up test data
function Cleanup-TestData {
    param([string]$PackId)
    $packDir = Join-Path $testTelemetryDir $PackId
    if (Test-Path $packDir) {
        Remove-Item -Path $packDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "PackSLOs Module" {
    
    BeforeAll {
        # Ensure telemetry directory exists
        if (-not (Test-Path $testTelemetryDir)) {
            New-Item -ItemType Directory -Path $testTelemetryDir -Force | Out-Null
        }
    }
    
    AfterAll {
        Cleanup-TestData -PackId $testPackId
    }

    Context "New-PackSLO" {
        It "Creates SLO configuration with defaults" {
            $slo = New-PackSLO -PackId $testPackId -ReviewCadence "weekly" -Owner "test-team" -Force
            
            $slo | Should -Not -BeNullOrEmpty
            $slo.packId | Should -Be $testPackId
            $slo.reviewCadence | Should -Be "weekly"
            $slo.owner | Should -Be "test-team"
            $slo.targets.p95RetrievalLatencyMs | Should -Be 1200
            $slo.targets.answerGroundingRate | Should -Be 0.95
        }
        
        It "Uses custom targets when provided" {
            $customTargets = @{
                p95RetrievalLatencyMs = 800
                answerGroundingRate = 0.98
            }
            $slo = New-PackSLO -PackId $testPackId -Targets $customTargets -Force
            
            $slo.targets.p95RetrievalLatencyMs | Should -Be 800
            $slo.targets.answerGroundingRate | Should -Be 0.98
        }
    }

    Context "Record-Telemetry" {
        BeforeEach {
            Cleanup-TestData -PackId $testPackId
        }
        
        It "Records telemetry data point" {
            $result = Record-Telemetry -PackId $testPackId -MetricName "refreshLatencyMs" -Value 2500 -RunId "test-run-1"
            
            $result | Should -Be $true
            
            # Verify file was created
            $metricFile = Join-Path $testTelemetryDir "$testPackId/refreshLatencyMs.jsonl"
            Test-Path $metricFile | Should -Be $true
        }
        
        It "Records multiple data points" {
            Record-Telemetry -PackId $testPackId -MetricName "buildSuccessRate" -Value 1.0 -RunId "test-run-1"
            Record-Telemetry -PackId $testPackId -MetricName "buildSuccessRate" -Value 0.95 -RunId "test-run-2"
            Record-Telemetry -PackId $testPackId -MetricName "buildSuccessRate" -Value 0.98 -RunId "test-run-3"
            
            $metricFile = Join-Path $testTelemetryDir "$testPackId/buildSuccessRate.jsonl"
            $lines = Get-Content $metricFile
            $lines.Count | Should -Be 3
        }
    }

    Context "Test-SLOCompliance" {
        It "Returns compliant when metrics meet targets" {
            $metrics = @{
                p95RetrievalLatencyMs = 1000  # Below target of 1200
                answerGroundingRate = 0.96    # Above target of 0.95
                parserFailureRate = 0.01      # Below target of 0.02
            }
            
            $result = Test-SLOCompliance -PackId $testPackId -ActualMetrics $metrics
            
            $result | Should -Not -BeNullOrEmpty
            $result.isCompliant | Should -Be $true
            $result.summary.failed | Should -Be 0
        }
        
        It "Returns non-compliant when metrics miss targets" {
            $metrics = @{
                p95RetrievalLatencyMs = 1500  # Above target of 1200
                answerGroundingRate = 0.90    # Below target of 0.95
            }
            
            $result = Test-SLOCompliance -PackId $testPackId -ActualMetrics $metrics
            
            $result.isCompliant | Should -Be $false
            $result.violations.Count | Should -BeGreaterThan 0
        }
    }

    Context "Get-TelemetryMetrics" {
        BeforeAll {
            # Seed test data
            Cleanup-TestData -PackId $testPackId
            for ($i = 1; $i -le 10; $i++) {
                Record-Telemetry -PackId $testPackId -MetricName "testMetric" -Value ($i * 100) -RunId "test-run-$i"
            }
        }
        
        It "Calculates average correctly" {
            $from = [DateTime]::UtcNow.AddHours(-1)
            $to = [DateTime]::UtcNow.AddMinutes(1)
            
            $avg = Get-TelemetryMetrics -PackId $testPackId -MetricName "testMetric" -From $from -To $to -Aggregation "avg"
            
            $avg | Should -Not -BeNullOrEmpty
            # Average of 100, 200, ..., 1000 = 550
            [math]::Round($avg) | Should -Be 550
        }
        
        It "Calculates P95 correctly" {
            $from = [DateTime]::UtcNow.AddHours(-1)
            $to = [DateTime]::UtcNow.AddMinutes(1)
            
            $p95 = Get-TelemetryMetrics -PackId $testPackId -MetricName "testMetric" -From $from -To $to -Aggregation "p95"
            
            $p95 | Should -Not -BeNullOrEmpty
        }
    }

    Context "Get-PackHealthDashboard" {
        It "Returns dashboard data structure" {
            $dashboard = Get-PackHealthDashboard -PackId "rpgmaker-mz"
            
            $dashboard | Should -Not -BeNullOrEmpty
            $dashboard.packId | Should -Be "rpgmaker-mz"
            $dashboard.generatedAt | Should -Not -BeNullOrEmpty
            $dashboard.sloConfig | Should -Not -BeNullOrEmpty
            $dashboard.recommendations | Should -Not -BeNullOrEmpty
        }
    }

    Context "SLO Violations" {
        BeforeAll {
            # Clean up any existing violations
            $violationFile = Join-Path $PSScriptRoot '..' '.llm-workflow' 'telemetry' 'violations.jsonl'
            if (Test-Path $violationFile) {
                Remove-Item $violationFile -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Registers a violation" {
            $result = Register-SLOViolation -PackId $testPackId -MetricName "p95RetrievalLatencyMs" `
                -ExpectedValue 1200 -ActualValue 2500 -Severity "critical" -RunId "test-run"
            
            $result | Should -Be $true
        }
        
        It "Retrieves violations" {
            $violations = Get-SLOViolations -PackId $testPackId -TimeRange "1h" -Severity "all"
            
            $violations | Should -Not -BeNullOrEmpty
            $violations.Count | Should -BeGreaterThan 0
        }
    }

    Context "Export/Import PackSLO" {
        $exportPath = Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') '.llm-workflow') 'exports') 'test-export.json'
        
        BeforeAll {
            # Ensure exports directory exists
            $exportDir = Split-Path $exportPath -Parent
            if (-not (Test-Path $exportDir)) {
                New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
            }
            
            # Create a test SLO
            New-PackSLO -PackId "export-test-pack" -Owner "export-team" -Force | Out-Null
        }
        
        It "Exports SLO configuration" {
            $result = Export-PackSLO -PackId "export-test-pack" -OutputPath $exportPath
            
            $result | Should -Not -BeNullOrEmpty
            Test-Path $result | Should -Be $true
        }
        
        It "Imports SLO configuration" {
            $imported = Import-PackSLO -Path $exportPath -ApplyToPackId "imported-pack" -Force
            
            $imported | Should -Not -BeNullOrEmpty
            $imported.packId | Should -Be "imported-pack"
            $imported.owner | Should -Be "export-team"
        }
        
        AfterAll {
            if (Test-Path $exportPath) {
                Remove-Item $exportPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Predefined SLOs" {
        It "Returns RPG Maker MZ predefined SLO" {
            $dashboard = Get-PackHealthDashboard -PackId "rpgmaker-mz"
            
            $dashboard.sloConfig | Should -Not -BeNullOrEmpty
            $dashboard.sloConfig.packId | Should -Be "rpgmaker-mz"
            $dashboard.sloConfig.targets.p95RetrievalLatencyMs | Should -Be 1200
            $dashboard.sloConfig.owner | Should -Be "rpgmaker-team"
        }
        
        It "Returns Godot Engine predefined SLO" {
            $dashboard = Get-PackHealthDashboard -PackId "godot-engine"
            
            $dashboard.sloConfig.packId | Should -Be "godot-engine"
            $dashboard.sloConfig.targets.p95RetrievalLatencyMs | Should -Be 1500
            $dashboard.sloConfig.owner | Should -Be "godot-team"
        }
        
        It "Returns Blender Engine predefined SLO" {
            $dashboard = Get-PackHealthDashboard -PackId "blender-engine"
            
            $dashboard.sloConfig.packId | Should -Be "blender-engine"
            $dashboard.sloConfig.targets.p95RetrievalLatencyMs | Should -Be 1800
            $dashboard.sloConfig.owner | Should -Be "blender-team"
        }
    }
}

Write-Host "PackSLOs tests loaded. Run with Pester to execute." -ForegroundColor Green
