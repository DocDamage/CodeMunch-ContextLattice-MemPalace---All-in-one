#requires -Version 7.0
<#
.SYNOPSIS
    Benchmark Report Generator
.DESCRIPTION
    Generates comprehensive benchmark reports in multiple formats:
    - HTML reports with interactive charts
    - JSON for CI/CD integration
    - Markdown summaries for documentation
    - Trend analysis and regression detection
.NOTES
    Version: 1.0.0
#>

param(
    [Parameter(Mandatory)]
    [object]$Results,
    
    [Parameter()]
    [object]$Comparisons = $null,
    
    [Parameter()]
    [string]$OutputPath,
    
    [Parameter()]
    [ValidateSet('HTML', 'JSON', 'Markdown', 'All')]
    [string]$Format = 'All',
    
    [string]$Title = "LLM Workflow Performance Report",
    [string]$RunName = (Get-Date -Format "yyyy-MM-dd HH:mm"),
    [switch]$IncludeTrends,
    [int]$TrendHistoryCount = 10
)

#region HTML Report Generation

function Export-HtmlReport {
    param(
        [object]$Results,
        [object]$Comparisons,
        [string]$Path,
        [string]$Title,
        [string]$RunName
    )

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$([System.Web.HttpUtility]::HtmlEncode($Title))</title>
    <style>
        :root {
            --bg-primary: #0d1117;
            --bg-secondary: #161b22;
            --bg-tertiary: #21262d;
            --text-primary: #c9d1d9;
            --text-secondary: #8b949e;
            --accent-blue: #58a6ff;
            --accent-green: #3fb950;
            --accent-yellow: #d29922;
            --accent-red: #f85149;
            --border: #30363d;
        }
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            margin: 0;
            padding: 20px;
            line-height: 1.6;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 { color: var(--text-primary); border-bottom: 2px solid var(--accent-blue); padding-bottom: 10px; }
        h2 { color: var(--accent-blue); margin-top: 30px; }
        h3 { color: var(--text-secondary); font-size: 1.1em; }
        .metadata { 
            background: var(--bg-secondary); 
            padding: 15px; 
            border-radius: 8px; 
            margin-bottom: 20px;
            border: 1px solid var(--border);
        }
        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 30px;
        }
        .summary-card {
            background: var(--bg-secondary);
            padding: 20px;
            border-radius: 8px;
            border: 1px solid var(--border);
            text-align: center;
        }
        .summary-card .value {
            font-size: 2em;
            font-weight: bold;
            color: var(--accent-blue);
        }
        .summary-card .label {
            color: var(--text-secondary);
            font-size: 0.9em;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            background: var(--bg-secondary);
            border-radius: 8px;
            overflow: hidden;
            margin-bottom: 20px;
        }
        th, td {
            padding: 12px 15px;
            text-align: left;
            border-bottom: 1px solid var(--border);
        }
        th {
            background: var(--bg-tertiary);
            color: var(--accent-blue);
            font-weight: 600;
        }
        tr:hover { background: rgba(88, 166, 255, 0.1); }
        .metric { font-family: 'Consolas', monospace; font-size: 0.95em; }
        .regression { color: var(--accent-red); }
        .improvement { color: var(--accent-green); }
        .neutral { color: var(--text-secondary); }
        .latency-p50 { color: var(--text-secondary); }
        .latency-p95 { color: var(--accent-yellow); }
        .latency-p99 { color: var(--accent-red); }
        .chart-container {
            background: var(--bg-secondary);
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
            border: 1px solid var(--border);
        }
        .bar-chart {
            display: flex;
            align-items: flex-end;
            height: 200px;
            gap: 5px;
            padding: 10px 0;
        }
        .bar {
            flex: 1;
            background: var(--accent-blue);
            min-height: 5px;
            border-radius: 3px 3px 0 0;
            position: relative;
            transition: opacity 0.2s;
        }
        .bar:hover { opacity: 0.8; }
        .bar:hover::after {
            content: attr(data-value) ' ms';
            position: absolute;
            bottom: 100%;
            left: 50%;
            transform: translateX(-50%);
            background: var(--bg-tertiary);
            padding: 5px 10px;
            border-radius: 4px;
            font-size: 0.8em;
            white-space: nowrap;
        }
        .status-badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 0.85em;
            font-weight: 500;
        }
        .status-pass { background: rgba(63, 185, 80, 0.2); color: var(--accent-green); }
        .status-fail { background: rgba(248, 81, 73, 0.2); color: var(--accent-red); }
        .status-warn { background: rgba(210, 153, 34, 0.2); color: var(--accent-yellow); }
        .section { margin-bottom: 40px; }
        .trend-up { color: var(--accent-red); }
        .trend-down { color: var(--accent-green); }
        .trend-stable { color: var(--text-secondary); }
    </style>
</head>
<body>
    <div class="container">
        <h1>$([System.Web.HttpUtility]::HtmlEncode($Title))</h1>
        
        <div class="metadata">
            <strong>Run:</strong> $([System.Web.HttpUtility]::HtmlEncode($RunName))<br>
            <strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")<br>
            <strong>Total Benchmarks:</strong> $($Results.Count)
        </div>

        <div class="summary-grid">
            <div class="summary-card">
                <div class="value">$($Results.Count)</div>
                <div class="label">Total Benchmarks</div>
            </div>
            <div class="summary-card">
                <div class="value">$('{0:N1}' -f (($Results | Measure-Object -Property { $_.Statistics.Mean } -Average).Average))</div>
                <div class="label">Avg Mean Time (ms)</div>
            </div>
            <div class="summary-card">
                <div class="value">$(if ($Comparisons) { ($Comparisons | Where-Object { $_.IsRegression }).Count } else { '-' })</div>
                <div class="label">Regressions</div>
            </div>
            <div class="summary-card">
                <div class="value">$(if ($Comparisons) { ($Comparisons | Where-Object { $_.IsImprovement }).Count } else { '-' })</div>
                <div class="label">Improvements</div>
            </div>
        </div>
"@

    # Benchmark Results Table
    $html += @"

        <div class="section">
            <h2>📊 Benchmark Results</h2>
            <table>
                <thead>
                    <tr>
                        <th>Benchmark</th>
                        <th>Mean</th>
                        <th>Median</th>
                        <th>P95</th>
                        <th>P99</th>
                        <th>StdDev</th>
                        <th>Iterations</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
"@

    foreach ($result in ($Results | Sort-Object Name)) {
        $stats = $result.Statistics
        $status = if ($Comparisons) {
            $comp = $Comparisons | Where-Object { $_.Name -eq $result.Name }
            if ($comp -and $comp.IsRegression) { '<span class="status-badge status-fail">Regression</span>' }
            elseif ($comp -and $comp.IsImprovement) { '<span class="status-badge status-pass">Improved</span>' }
            else { '<span class="status-badge status-pass">OK</span>' }
        } else { '<span class="status-badge status-pass">OK</span>' }
        
        $html += @"
                    <tr>
                        <td>$([System.Web.HttpUtility]::HtmlEncode($result.Name))</td>
                        <td class="metric">$('{0:N2}' -f $stats.Mean)</td>
                        <td class="metric">$('{0:N2}' -f $stats.Median)</td>
                        <td class="metric latency-p95">$('{0:N2}' -f $stats.P95)</td>
                        <td class="metric latency-p99">$('{0:N2}' -f $stats.P99)</td>
                        <td class="metric">±$('{0:N2}' -f $stats.StdDev)</td>
                        <td>$($result.Iterations)</td>
                        <td>$status</td>
                    </tr>
"@
    }

    $html += @"
                </tbody>
            </table>
        </div>
"@

    # Comparison Section
    if ($Comparisons -and $Comparisons.Count -gt 0) {
        $html += @"

        <div class="section">
            <h2>⚠️ Baseline Comparison</h2>
            <table>
                <thead>
                    <tr>
                        <th>Benchmark</th>
                        <th>Baseline (ms)</th>
                        <th>Current (ms)</th>
                        <th>Change</th>
                        <th>Issues</th>
                    </tr>
                </thead>
                <tbody>
"@
        
        foreach ($comp in ($Comparisons | Sort-Object Name)) {
            $changeClass = if ($comp.IsRegression) { 'regression' } elseif ($comp.IsImprovement) { 'improvement' } else { 'neutral' }
            $changeSymbol = if ($comp.TimeChangePercent -gt 0) { '↑' } elseif ($comp.TimeChangePercent -lt 0) { '↓' } else { '→' }
            $changeText = if ($comp.TimeChangePercent) { "$changeSymbol $('{0:N1}' -f $comp.TimeChangePercent)%" } else { 'N/A' }
            $issues = ($comp.Issues -join '<br>') -replace 'Regression', '<strong class="regression">Regression</strong>'
            
            $html += @"
                    <tr>
                        <td>$([System.Web.HttpUtility]::HtmlEncode($comp.Name))</td>
                        <td class="metric">$(if ($comp.Baseline) { '{0:N2}' -f $comp.Baseline.MeanMilliseconds } else { '-' })</td>
                        <td class="metric">$('{0:N2}' -f $comp.Current.Mean)</td>
                        <td class="$changeClass">$changeText</td>
                        <td>$issues</td>
                    </tr>
"@
        }
        
        $html += @"
                </tbody>
            </table>
        </div>
"@
    }

    # Latency Distribution Charts
    $html += @"

        <div class="section">
            <h2>📈 Latency Distribution</h2>
"@

    $categories = $Results | Group-Object { $_.Name.Split('.')[0] }
    foreach ($cat in $categories) {
        $catResults = $cat.Group | Sort-Object { $_.Statistics.Mean } | Select-Object -First 10
        $maxValue = ($catResults | Measure-Object -Property { $_.Statistics.P99 } -Maximum).Maximum
        
        $html += @"
            <div class="chart-container">
                <h3>$($cat.Name) - P99 Latencies</h3>
                <div class="bar-chart">
"@
        foreach ($r in $catResults) {
            $height = [Math]::Min(100, [Math]::Max(5, ($r.Statistics.P99 / $maxValue) * 100))
            $html += @"
                    <div class="bar" style="height: $height%;" data-value="$($r.Statistics.P99)"></div>
"@
        }
        $html += @"
                </div>
            </div>
"@
    }

    $html += @"
        </div>

        <div class="section">
            <h2>📋 Detailed Statistics</h2>
            <table>
                <thead>
                    <tr>
                        <th>Benchmark</th>
                        <th>Min</th>
                        <th>Max</th>
                        <th>P50</th>
                        <th>P90</th>
                        <th>Throughput</th>
                    </tr>
                </thead>
                <tbody>
"@

    foreach ($result in ($Results | Sort-Object Name)) {
        $stats = $result.Statistics
        $throughput = if ($result.Throughput) { "$($result.Throughput) $($result.ThroughputMetric)" } else { '-' }
        
        $html += @"
                    <tr>
                        <td>$([System.Web.HttpUtility]::HtmlEncode($result.Name))</td>
                        <td class="metric">$('{0:N2}' -f $stats.Min)</td>
                        <td class="metric">$('{0:N2}' -f $stats.Max)</td>
                        <td class="metric latency-p50">$('{0:N2}' -f $stats.P50)</td>
                        <td class="metric">$('{0:N2}' -f $stats.P90)</td>
                        <td>$throughput</td>
                    </tr>
"@
    }

    $html += @"
                </tbody>
            </table>
        </div>

        <footer style="text-align: center; color: var(--text-secondary); margin-top: 40px; padding-top: 20px; border-top: 1px solid var(--border);">
            <p>Generated by LLM Workflow Performance Benchmark Suite</p>
        </footer>
    </div>
</body>
</html>
"@

    $html | Set-Content $Path -Encoding UTF8
    Write-Host "HTML Report: $Path" -ForegroundColor Green
}

#endregion

#region JSON Report Generation

function Export-JsonReport {
    param(
        [object]$Results,
        [object]$Comparisons,
        [string]$Path
    )

    $report = [ordered]@{
        metadata = [ordered]@{
            generatedAt = Get-Date -Format "o"
            version = "1.0.0"
            totalBenchmarks = $Results.Count
        }
        summary = [ordered]@{
            overallMean = ($Results | Measure-Object -Property { $_.Statistics.Mean } -Average).Average
            overallP95 = ($Results | Measure-Object -Property { $_.Statistics.P95 } -Average).Average
            regressionCount = if ($Comparisons) { ($Comparisons | Where-Object { $_.IsRegression }).Count } else { 0 }
            improvementCount = if ($Comparisons) { ($Comparisons | Where-Object { $_.IsImprovement }).Count } else { 0 }
        }
        benchmarks = @()
        comparisons = @()
    }

    foreach ($result in $Results) {
        $benchmark = [ordered]@{
            name = $result.Name
            timestamp = $result.Timestamp
            iterations = $result.Iterations
            statistics = @{
                mean = $result.Statistics.Mean
                median = $result.Statistics.Median
                min = $result.Statistics.Min
                max = $result.Statistics.Max
                stdDev = $result.Statistics.StdDev
                p50 = $result.Statistics.P50
                p90 = $result.Statistics.P90
                p95 = $result.Statistics.P95
                p99 = $result.Statistics.P99
            }
        }
        if ($result.Throughput) {
            $benchmark.throughput = @{
                value = $result.Throughput
                unit = $result.ThroughputMetric
            }
        }
        $report.benchmarks += $benchmark
    }

    if ($Comparisons) {
        foreach ($comp in $Comparisons) {
            $comparison = [ordered]@{
                name = $comp.Name
                isRegression = $comp.IsRegression
                isImprovement = $comp.IsImprovement
                timeChangePercent = $comp.TimeChangePercent
                issues = $comp.Issues
            }
            if ($comp.Baseline) {
                $comparison.baseline = $comp.Baseline
            }
            $report.comparisons += $comparison
        }
    }

    $report | ConvertTo-Json -Depth 10 | Set-Content $Path -Encoding UTF8
    Write-Host "JSON Report: $Path" -ForegroundColor Green
}

#endregion

#region Markdown Report Generation

function Export-MarkdownReport {
    param(
        [object]$Results,
        [object]$Comparisons,
        [string]$Path,
        [string]$Title,
        [string]$RunName
    )

    $md = @"
# $Title

**Run:** $RunName  
**Generated:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")  
**Total Benchmarks:** $($Results.Count)

## Summary

| Metric | Value |
|--------|-------|
| Total Benchmarks | $($Results.Count) |
| Average Mean Time | $('{0:N2}' -f (($Results | Measure-Object -Property { $_.Statistics.Mean } -Average).Average)) ms |
| Average P95 Time | $('{0:N2}' -f (($Results | Measure-Object -Property { $_.Statistics.P95 } -Average).Average)) ms |
| Regressions | $(if ($Comparisons) { ($Comparisons | Where-Object { $_.IsRegression }).Count } else { 0 }) |
| Improvements | $(if ($Comparisons) { ($Comparisons | Where-Object { $_.IsImprovement }).Count } else { 0 }) |

## Benchmark Results

| Benchmark | Mean (ms) | Median (ms) | P95 (ms) | P99 (ms) | StdDev | Status |
|-----------|-----------|-------------|----------|----------|--------|--------|
"@

    foreach ($result in ($Results | Sort-Object Name)) {
        $stats = $result.Statistics
        $status = if ($Comparisons) {
            $comp = $Comparisons | Where-Object { $_.Name -eq $result.Name }
            if ($comp -and $comp.IsRegression) { '🔴 Regression' }
            elseif ($comp -and $comp.IsImprovement) { '🟢 Improved' }
            else { '🟢 OK' }
        } else { '🟢 OK' }
        
        $md += @"
| $($result.Name) | $('{0:N2}' -f $stats.Mean) | $('{0:N2}' -f $stats.Median) | $('{0:N2}' -f $stats.P95) | $('{0:N2}' -f $stats.P99) | $('{0:N2}' -f $stats.StdDev) | $status |
"@
    }

    if ($Comparisons -and $Comparisons.Count -gt 0) {
        $md += @"

## Baseline Comparison

| Benchmark | Baseline (ms) | Current (ms) | Change | Status |
|-----------|---------------|--------------|--------|--------|
"@
        foreach ($comp in ($Comparisons | Sort-Object Name)) {
            $change = if ($comp.TimeChangePercent -gt 0) { "+ $('{0:N1}' -f $comp.TimeChangePercent)% 📈" } 
                      elseif ($comp.TimeChangePercent -lt 0) { " $('{0:N1}' -f $comp.TimeChangePercent)% 📉" }
                      else { "0% ➡️" }
            $status = if ($comp.IsRegression) { '🔴 REGRESSION' } elseif ($comp.IsImprovement) { '🟢 IMPROVED' } else { '⚪ Stable' }
            
            $md += @"
| $($comp.Name) | $(if ($comp.Baseline) { '{0:N2}' -f $comp.Baseline.MeanMilliseconds } else { '-' }) | $('{0:N2}' -f $comp.Current.Mean) | $change | $status |
"@
        }

        if (($Comparisons | Where-Object { $_.IsRegression }).Count -gt 0) {
            $md += @"

### ⚠️ Regressions Detected

"@
            $Comparisons | Where-Object { $_.IsRegression } | ForEach-Object {
                $md += @"
- **$($_.Name)**
"@
                $_.Issues | ForEach-Object { $md += @"
  - $_
"@ }
            }
        }
    }

    $md += @"

## Detailed Statistics

| Benchmark | Min | Max | P50 | P90 | Throughput |
|-----------|-----|-----|-----|-----|------------|
"@

    foreach ($result in ($Results | Sort-Object Name)) {
        $stats = $result.Statistics
        $throughput = if ($result.Throughput) { "$($result.Throughput) $($result.ThroughputMetric)" } else { '-' }
        $md += @"
| $($result.Name) | $('{0:N2}' -f $stats.Min) | $('{0:N2}' -f $stats.Max) | $('{0:N2}' -f $stats.P50) | $('{0:N2}' -f $stats.P90) | $throughput |
"@
    }

    $md += @"

## Category Breakdown

"@

    $categories = $Results | Group-Object { $_.Name.Split('.')[0] }
    foreach ($cat in $categories) {
        $catStats = $cat.Group | Measure-Object -Property { $_.Statistics.Mean } -Average -Maximum -Minimum
        $md += @"
### $($cat.Name)

- **Benchmarks:** $($cat.Group.Count)
- **Mean Range:** $('{0:N2}' -f $catStats.Minimum) - $('{0:N2}' -f $catStats.Maximum) ms
- **Average Mean:** $('{0:N2}' -f $catStats.Average) ms

"@
    }

    $md += @"

---

*Generated by LLM Workflow Performance Benchmark Suite*
"@

    $md | Set-Content $Path -Encoding UTF8
    Write-Host "Markdown Report: $Path" -ForegroundColor Green
}

#endregion

#region Trend Analysis

function Get-PerformanceTrends {
    param(
        [string]$ResultsPath,
        [int]$HistoryCount = 10
    )

    $pattern = Join-Path $ResultsPath "benchmark_*.json"
    $historyFiles = Get-ChildItem $pattern | Sort-Object LastWriteTime -Descending | Select-Object -First $HistoryCount

    $trends = @{}
    foreach ($file in $historyFiles) {
        $data = Get-Content $file | ConvertFrom-Json
        $date = [DateTime]$data.metadata.generatedAt
        
        foreach ($benchmark in $data.benchmarks) {
            if (-not $trends.ContainsKey($benchmark.name)) {
                $trends[$benchmark.name] = @()
            }
            $trends[$benchmark.name] += [PSCustomObject]@{
                Date = $date
                Mean = $benchmark.statistics.mean
                P95 = $benchmark.statistics.p95
            }
        }
    }

    return $trends
}

#endregion

#region Main Execution

# Generate reports based on format
switch ($Format) {
    'HTML' { 
        Export-HtmlReport -Results $Results -Comparisons $Comparisons -Path $OutputPath -Title $Title -RunName $RunName 
    }
    'JSON' { 
        Export-JsonReport -Results $Results -Comparisons $Comparisons -Path $OutputPath 
    }
    'Markdown' { 
        Export-MarkdownReport -Results $Results -Comparisons $Comparisons -Path $OutputPath -Title $Title -RunName $RunName 
    }
    'All' {
        $basePath = $OutputPath -replace '\.[^.]+$', ''
        Export-HtmlReport -Results $Results -Comparisons $Comparisons -Path "$basePath.html" -Title $Title -RunName $RunName
        Export-JsonReport -Results $Results -Comparisons $Comparisons -Path "$basePath.json"
        Export-MarkdownReport -Results $Results -Comparisons $Comparisons -Path "$basePath.md" -Title $Title -RunName $RunName
    }
}

if ($IncludeTrends) {
    $trends = Get-PerformanceTrends -ResultsPath (Split-Path $OutputPath) -HistoryCount $TrendHistoryCount
    $trends | ConvertTo-Json -Depth 5 | Set-Content "$basePath.trends.json"
    Write-Host "Trends Analysis: $basePath.trends.json" -ForegroundColor Green
}

#endregion
