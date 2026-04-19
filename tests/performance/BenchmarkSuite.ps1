#requires -Version 7.0
<#
.SYNOPSIS
    LLM Workflow Performance Benchmarking Suite
.DESCRIPTION
    Main benchmarking framework for measuring performance of LLM Workflow operations.
    Supports timing, memory tracking, statistical analysis, baseline comparison, and trend tracking.
.NOTES
    Version: 1.0.0
    Author: LLM Workflow Team
#>

using namespace System.Collections.Generic
using namespace System.Diagnostics

# Error Handling
$ErrorActionPreference = 'Stop'
$script:BenchmarkConfig = $null
$script:BaselineData = $null
$script:BenchmarkResults = [List[object]]::new()

#region Configuration

<#
.SYNOPSIS
    Sets the benchmark configuration.
#>
function Set-BenchmarkConfig {
    [CmdletBinding()]
    param(
        [int]$WarmupRuns = 1,
        [int]$BenchmarkRuns = 10,
        [string]$BaselinePath = "$PSScriptRoot\baselines",
        [string]$ResultsPath = "$PSScriptRoot\results",
        [double]$RegressionThresholdPercent = 10.0,
        [double]$MemoryRegressionThresholdMB = 50.0,
        [switch]$EnableMemoryTracking = $true,
        [switch]$EnableGC = $true
    )

    $script:BenchmarkConfig = [PSCustomObject]@{
        WarmupRuns = $WarmupRuns
        BenchmarkRuns = $BenchmarkRuns
        BaselinePath = $BaselinePath
        ResultsPath = $ResultsPath
        RegressionThresholdPercent = $RegressionThresholdPercent
        MemoryRegressionThresholdMB = $MemoryRegressionThresholdMB
        EnableMemoryTracking = $EnableMemoryTracking
        EnableGC = $EnableGC
        StartTime = Get-Date
    }

    # Ensure directories exist
    @($BaselinePath, $ResultsPath) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
        }
    }

    Write-Host "Benchmark Configuration:" -ForegroundColor Cyan
    Write-Host "  Warmup Runs: $WarmupRuns" -ForegroundColor Gray
    Write-Host "  Benchmark Runs: $BenchmarkRuns" -ForegroundColor Gray
    Write-Host "  Baseline Path: $BaselinePath" -ForegroundColor Gray
    Write-Host "  Results Path: $ResultsPath" -ForegroundColor Gray
    Write-Host "  Regression Threshold: ${RegressionThresholdPercent}%" -ForegroundColor Gray
}

<#
.SYNOPSIS
    Loads baseline data for comparison.
#>
function Import-Baseline {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$BaselineName = "baseline"
    )

    $baselineFile = Join-Path $script:BenchmarkConfig.BaselinePath "$BaselineName.json"
    
    if (Test-Path $baselineFile) {
        $script:BaselineData = Get-Content $baselineFile | ConvertFrom-Json -AsHashtable
        Write-Host "Loaded baseline: $BaselineName" -ForegroundColor Green
    } else {
        Write-Warning "Baseline not found: $baselineFile"
        $script:BaselineData = @{}
    }
}

<#
.SYNOPSIS
    Saves current results as new baseline.
#>
function Export-Baseline {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$BaselineName = "baseline",
        
        [Parameter()]
        [object]$Results = $script:BenchmarkResults
    )

    $baselineFile = Join-Path $script:BenchmarkConfig.BaselinePath "$BaselineName.json"
    $baseline = @{}
    
    foreach ($result in $Results) {
        $baseline[$result.Name] = @{
            MeanMilliseconds = $result.Statistics.Mean
            MedianMilliseconds = $result.Statistics.Median
            P95Milliseconds = $result.Statistics.P95
            P99Milliseconds = $result.Statistics.P99
            MeanMemoryMB = $result.MemoryStatistics.Mean
        }
    }

    $baseline | ConvertTo-Json -Depth 10 | Set-Content $baselineFile
    Write-Host "Saved baseline: $baselineFile" -ForegroundColor Green
}

#endregion

#region Core Measurement Functions

<#
.SYNOPSIS
    Measures execution time and memory usage of an operation.
.DESCRIPTION
    Executes a script block multiple times, collecting timing and memory metrics.
#>
function Measure-Operation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        
        [int]$WarmupRuns = $script:BenchmarkConfig.WarmupRuns,
        [int]$BenchmarkRuns = $script:BenchmarkConfig.BenchmarkRuns,
        [hashtable]$Parameters = @{},
        [scriptblock]$Setup = $null,
        [scriptblock]$Teardown = $null,
        [switch]$EnableMemoryTracking = $script:BenchmarkConfig.EnableMemoryTracking
    )

    Write-Host "`nBenchmarking: $Name" -ForegroundColor Cyan
    Write-Host "  Runs: $WarmupRuns warmup + $BenchmarkRuns benchmark" -ForegroundColor Gray

    $results = @()
    $memoryResults = @()
    $process = Get-Process -Id $PID

    # Warmup runs
    if ($WarmupRuns -gt 0) {
        Write-Host "  Running warmup..." -NoNewline -ForegroundColor Gray
        for ($i = 0; $i -lt $WarmupRuns; $i++) {
            if ($Setup) { & $Setup }
            if ($script:BenchmarkConfig.EnableGC) { [GC]::Collect(); [GC]::WaitForPendingFinalizers() }
            $null = & $ScriptBlock @Parameters
            if ($Teardown) { & $Teardown }
        }
        Write-Host " done" -ForegroundColor Green
    }

    # Benchmark runs
    Write-Host "  Running benchmark..." -NoNewline -ForegroundColor Gray
    for ($i = 0; $i -lt $BenchmarkRuns; $i++) {
        if ($Setup) { & $Setup }
        
        if ($script:BenchmarkConfig.EnableGC) { [GC]::Collect(); [GC]::WaitForPendingFinalizers() }
        $startMemory = if ($EnableMemoryTracking) { $process.WorkingSet64 / 1MB } else { 0 }
        
        $sw = [Stopwatch]::StartNew()
        $null = & $ScriptBlock @Parameters
        $sw.Stop()
        
        $endMemory = if ($EnableMemoryTracking) { $process.WorkingSet64 / 1MB } else { 0 }
        
        $results += $sw.Elapsed.TotalMilliseconds
        $memoryResults += [Math]::Max(0, $endMemory - $startMemory)
        
        if ($Teardown) { & $Teardown }
    }
    Write-Host " done" -ForegroundColor Green

    return New-BenchmarkResult -Name $Name -Timings $results -MemoryReadings $memoryResults
}

<#
.SYNOPSIS
    Creates a benchmark result object with statistical analysis.
#>
function New-BenchmarkResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [double[]]$Timings,
        
        [double[]]$MemoryReadings = @()
    )

    $sorted = $Timings | Sort-Object
    $n = $sorted.Count
    $mean = ($sorted | Measure-Object -Average).Average
    $sum = ($sorted | Measure-Object -Sum).Sum
    $sumSquares = ($sorted | ForEach-Object { $_ * $_ } | Measure-Object -Sum).Sum
    $variance = ($sumSquares / $n) - ($mean * $mean)
    $stdDev = [Math]::Sqrt([Math]::Max(0, $variance))

    $result = [PSCustomObject]@{
        Name = $Name
        Timestamp = Get-Date -Format "o"
        Iterations = $n
        Statistics = [PSCustomObject]@{
            Mean = [Math]::Round($mean, 3)
            Median = [Math]::Round($sorted[[int]($n / 2)], 3)
            Min = [Math]::Round($sorted[0], 3)
            Max = [Math]::Round($sorted[-1], 3)
            StdDev = [Math]::Round($stdDev, 3)
            P50 = [Math]::Round($sorted[[int]($n * 0.50)], 3)
            P90 = [Math]::Round($sorted[[int]($n * 0.90)], 3)
            P95 = [Math]::Round($sorted[[int]($n * 0.95)], 3)
            P99 = [Math]::Round($sorted[[int]($n * 0.99)], 3)
        }
        MemoryStatistics = if ($MemoryReadings.Count -gt 0) {
            $memSorted = $MemoryReadings | Sort-Object
            [PSCustomObject]@{
                Mean = [Math]::Round(($memSorted | Measure-Object -Average).Average, 3)
                Median = [Math]::Round($memSorted[[int]($memSorted.Count / 2)], 3)
                Min = [Math]::Round($memSorted[0], 3)
                Max = [Math]::Round($memSorted[-1], 3)
                P95 = [Math]::Round($memSorted[[int]($memSorted.Count * 0.95)], 3)
            }
        } else { $null }
        RawData = @{
            Timings = $Timings
            Memory = $MemoryReadings
        }
    }

    return $result
}

#endregion

#region Comparison and Analysis

<#
.SYNOPSIS
    Compares benchmark result against baseline.
.DESCRIPTION
    Detects performance regressions by comparing current results to stored baselines.
#>
function Compare-BenchmarkResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Result,
        
        [double]$ThresholdPercent = $script:BenchmarkConfig.RegressionThresholdPercent,
        [double]$MemoryThresholdMB = $script:BenchmarkConfig.MemoryRegressionThresholdMB
    )

    begin {
        $comparisons = @()
    }

    process {
        $baseline = $script:BaselineData[$Result.Name]
        $comparison = [PSCustomObject]@{
            Name = $Result.Name
            Baseline = $baseline
            Current = @{
                Mean = $Result.Statistics.Mean
                P95 = $Result.Statistics.P95
                MeanMemory = if ($Result.MemoryStatistics) { $Result.MemoryStatistics.Mean } else { $null }
            }
            IsRegression = $false
            IsImprovement = $false
            Issues = @()
        }

        if ($baseline) {
            # Time regression check
            $timeChange = (($Result.Statistics.Mean - $baseline.MeanMilliseconds) / $baseline.MeanMilliseconds) * 100
            $comparison.TimeChangePercent = [Math]::Round($timeChange, 2)
            
            if ($timeChange -gt $ThresholdPercent) {
                $comparison.IsRegression = $true
                $comparison.Issues += "Time regression: +$([Math]::Round($timeChange, 1))% (threshold: ${ThresholdPercent}%)"
            } elseif ($timeChange -lt -$ThresholdPercent) {
                $comparison.IsImprovement = $true
            }

            # P95 latency regression check
            $p95Change = (($Result.Statistics.P95 - $baseline.P95Milliseconds) / $baseline.P95Milliseconds) * 100
            if ($p95Change -gt $ThresholdPercent * 1.5) {
                $comparison.IsRegression = $true
                $comparison.Issues += "P95 latency regression: +$([Math]::Round($p95Change, 1))%"
            }

            # Memory regression check
            if ($Result.MemoryStatistics -and $baseline.MeanMemory) {
                $memChange = $Result.MemoryStatistics.Mean - $baseline.MeanMemory
                if ($memChange -gt $MemoryThresholdMB) {
                    $comparison.IsRegression = $true
                    $comparison.Issues += "Memory regression: +$([Math]::Round($memChange, 1)) MB"
                }
            }
        } else {
            $comparison.Issues += "No baseline found for comparison"
        }

        $comparisons += $comparison
        Write-Output $comparison
    }

    end {
        # Summary
        $regressions = $comparisons | Where-Object { $_.IsRegression }
        $improvements = $comparisons | Where-Object { $_.IsImprovement }
        
        Write-Host "`nComparison Summary:" -ForegroundColor Cyan
        Write-Host "  Total: $($comparisons.Count)" -ForegroundColor Gray
        Write-Host "  Regressions: $($regressions.Count)" -ForegroundColor $(if ($regressions.Count -gt 0) { 'Red' } else { 'Green' })
        Write-Host "  Improvements: $($improvements.Count)" -ForegroundColor $(if ($improvements.Count -gt 0) { 'Green' } else { 'Gray' })

        if ($regressions.Count -gt 0) {
            Write-Host "`nRegressions Detected:" -ForegroundColor Red
            $regressions | ForEach-Object {
                Write-Host "  ⚠ $($_.Name)" -ForegroundColor Red
                $_.Issues | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkRed }
            }
        }
    }
}

<#
.SYNOPSIS
    Performs trend analysis on historical benchmark data.
#>
function Get-PerformanceTrend {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BenchmarkName,
        
        [int]$HistoryCount = 10
    )

    $pattern = Join-Path $script:BenchmarkConfig.ResultsPath "*.json"
    $historyFiles = Get-ChildItem $pattern | Sort-Object LastWriteTime -Descending | Select-Object -First $HistoryCount

    $trend = @()
    foreach ($file in $historyFiles) {
        $data = Get-Content $file | ConvertFrom-Json
        $result = $data.Results | Where-Object { $_.Name -eq $BenchmarkName }
        if ($result) {
            $trend += [PSCustomObject]@{
                Date = $data.Timestamp
                Mean = $result.Statistics.Mean
                P95 = $result.Statistics.P95
            }
        }
    }

    # Calculate trend direction
    if ($trend.Count -ge 3) {
        $first = ($trend | Select-Object -First 3 | Measure-Object Mean -Average).Average
        $last = ($trend | Select-Object -Last 3 | Measure-Object Mean -Average).Average
        $trendDirection = if ($last -gt $first * 1.05) { "Degrading" } elseif ($last -lt $first * 0.95) { "Improving" } else { "Stable" }
    } else {
        $trendDirection = "Insufficient Data"
    }

    return [PSCustomObject]@{
        Benchmark = $BenchmarkName
        TrendDirection = $trendDirection
        DataPoints = $trend.Count
        History = $trend
    }
}

#endregion

#region Report Generation

<#
.SYNOPSIS
    Exports benchmark results to various formats.
.DESCRIPTION
    Generates HTML, JSON, and Markdown reports from benchmark results.
#>
function Export-BenchmarkReport {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Results = $script:BenchmarkResults,
        
        [Parameter()]
        [object]$Comparisons = $null,
        
        [string]$OutputPath = $script:BenchmarkConfig.ResultsPath,
        [string]$RunName = (Get-Date -Format "yyyyMMdd_HHmmss"),
        [switch]$GenerateHtml,
        [switch]$GenerateJson = $true,
        [switch]$GenerateMarkdown
    )

    $reportBase = Join-Path $OutputPath "benchmark_$RunName"

    # JSON Report (for CI/CD)
    if ($GenerateJson) {
        $jsonPath = "$reportBase.json"
        $reportData = [PSCustomObject]@{
            Timestamp = Get-Date -Format "o"
            RunName = $RunName
            Configuration = $script:BenchmarkConfig
            Results = $Results
            Comparisons = $Comparisons
            Summary = [PSCustomObject]@{
                TotalBenchmarks = $Results.Count
                Regressions = ($Comparisons | Where-Object { $_.IsRegression }).Count
                Improvements = ($Comparisons | Where-Object { $_.IsImprovement }).Count
                OverallMean = ($Results | Measure-Object -Property { $_.Statistics.Mean } -Average).Average
            }
        }
        $reportData | ConvertTo-Json -Depth 10 | Set-Content $jsonPath
        Write-Host "JSON Report: $jsonPath" -ForegroundColor Green
    }

    # HTML Report
    if ($GenerateHtml) {
        & "$PSScriptRoot\ReportGenerator.ps1" -Results $Results -Comparisons $Comparisons -OutputPath "$reportBase.html"
    }

    # Markdown Report
    if ($GenerateMarkdown) {
        & "$PSScriptRoot\ReportGenerator.ps1" -Results $Results -Comparisons $Comparisons -OutputPath "$reportBase.md" -Format Markdown
    }

    return $reportBase
}

#endregion

#region Suite Execution

<#
.SYNOPSIS
    Runs the complete benchmark suite.
.DESCRIPTION
    Executes all benchmark categories and generates comprehensive reports.
#>
function Invoke-BenchmarkSuite {
    [CmdletBinding()]
    param(
        [string[]]$Categories = @('Extraction', 'Retrieval', 'Ingestion'),
        [switch]$CompareToBaseline,
        [string]$BaselineName = "baseline",
        [switch]$UpdateBaseline,
        [switch]$FailOnRegression,
        [hashtable]$CategoryParams = @{}
    )

    $suiteStartTime = Get-Date
    Write-Host "`n=== LLM Workflow Performance Benchmark Suite ===" -ForegroundColor Cyan
    Write-Host "Started: $($suiteStartTime.ToString('yyyy-MM-dd HH:mm:ss'))`n" -ForegroundColor Gray

    # Initialize configuration if not set
    if (-not $script:BenchmarkConfig) {
        Set-BenchmarkConfig
    }

    # Load baseline if requested
    if ($CompareToBaseline -or $UpdateBaseline) {
        Import-Baseline -BaselineName $BaselineName
    }

    # Clear previous results
    $script:BenchmarkResults.Clear()

    # Run category benchmarks
    $categoryResults = @{}
    foreach ($category in $Categories) {
        Write-Host "`n--- Running $category Benchmarks ---" -ForegroundColor Yellow
        $categoryScript = Join-Path $PSScriptRoot "${category}Benchmarks.ps1"
        
        if (Test-Path $categoryScript) {
            try {
                $params = if ($CategoryParams.ContainsKey($category)) { $CategoryParams[$category] } else { @{} }
                $results = & $categoryScript @params
                $categoryResults[$category] = $results
                $script:BenchmarkResults.AddRange($results)
            } catch {
                Write-Warning "Failed to run $category benchmarks: $_"
            }
        } else {
            Write-Warning "Category script not found: $categoryScript"
        }
    }

    # Compare to baseline
    $comparisons = $null
    if ($CompareToBaseline -and $script:BaselineData.Count -gt 0) {
        $comparisons = $script:BenchmarkResults | Compare-BenchmarkResult
    }

    # Generate reports
    Write-Host "`n--- Generating Reports ---" -ForegroundColor Yellow
    $reportPath = Export-BenchmarkReport -Results $script:BenchmarkResults -Comparisons $comparisons -GenerateMarkdown

    # Update baseline if requested
    if ($UpdateBaseline) {
        Export-Baseline -BaselineName $BaselineName -Results $script:BenchmarkResults
    }

    # Summary
    $duration = (Get-Date) - $suiteStartTime
    Write-Host "`n=== Benchmark Suite Complete ===" -ForegroundColor Cyan
    Write-Host "Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor Gray
    Write-Host "Results: $reportPath" -ForegroundColor Gray
    Write-Host "Total Benchmarks: $($script:BenchmarkResults.Count)" -ForegroundColor Gray

    if ($comparisons) {
        $regressionCount = ($comparisons | Where-Object { $_.IsRegression }).Count
        if ($regressionCount -gt 0) {
            Write-Host "Regressions: $regressionCount" -ForegroundColor Red
            if ($FailOnRegression) {
                throw "Performance regressions detected!"
            }
        }
    }

    return [PSCustomObject]@{
        Results = $script:BenchmarkResults
        Comparisons = $comparisons
        ReportPath = $reportPath
        Duration = $duration
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Set-BenchmarkConfig',
    'Import-Baseline',
    'Export-Baseline',
    'Measure-Operation',
    'New-BenchmarkResult',
    'Compare-BenchmarkResult',
    'Get-PerformanceTrend',
    'Export-BenchmarkReport',
    'Invoke-BenchmarkSuite'
)
