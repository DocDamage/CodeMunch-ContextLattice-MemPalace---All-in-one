#requires -Version 7.0
<#
.SYNOPSIS
    Ingestion Performance Benchmarks
.DESCRIPTION
    Performance tests for data ingestion operations:
    - Git ingestion
    - HTTP ingestion
    - API ingestion
    - Incremental vs full ingestion
    - Throughput measurement (files/hour)
.NOTES
    Version: 1.0.0
#>

param(
    [int]$WarmupRuns = 1,
    [int]$BenchmarkRuns = 5,
    [string]$TestDataPath = "$PSScriptRoot\testdata",
    [string]$TestRepoUrl = "https://github.com/godotengine/godot-demo-projects",
    [int]$SmallFileCount = 100,
    [int]$MediumFileCount = 1000,
    [int]$LargeFileCount = 10000
)

# Import benchmark suite
. "$PSScriptRoot\BenchmarkSuite.ps1"

# Results collection
$results = [System.Collections.Generic.List[object]]::new()

#region Simulated Ingestion Components

# Mock git repository data
$script:MockRepoFiles = @{}
$script:MockHttpFiles = @{}
$script:MockApiData = @{}
$script:IngestedFiles = [System.Collections.Generic.HashSet[string]]::new()
$script:LastIngestionTime = $null

function Initialize-MockData {
    param([int]$FileCount)
    
    $extensions = @('.gd', '.cs', '.py', '.tscn', '.tres', '.md', '.json', '.yaml')
    $sizes = @('small', 'medium', 'large')
    $sizeBytes = @{ 'small' = 1024; 'medium' = 10240; 'large' = 102400 }
    
    for ($i = 0; $i -lt $FileCount; $i++) {
        $ext = $extensions[$i % $extensions.Count]
        $size = $sizes[$i % $sizes.Count]
        $path = "src/$(($i % 20))/file_$i$ext"
        
        $script:MockRepoFiles[$path] = [PSCustomObject]@{
            Path = $path
            Size = $sizeBytes[$size]
            Content = 'x' * $sizeBytes[$size]
            LastModified = (Get-Date).AddMinutes(-$i)
            Hash = [Convert]::ToBase64String([BitConverter]::GetBytes($path.GetHashCode()))
        }
    }
}

function Invoke-GitClone {
    param(
        [string]$Url,
        [string]$Branch = "main",
        [int]$Depth = 0
    )
    # Simulate git clone latency
    $latency = 500 + (Get-Random -Minimum 100 -Maximum 500)
    if ($Depth -gt 0) { $latency = $latency * 0.6 }
    Start-Sleep -Milliseconds $latency
    
    return [PSCustomObject]@{
        Url = $Url
        Branch = $Branch
        FileCount = $script:MockRepoFiles.Count
        TotalSize = ($script:MockRepoFiles.Values | Measure-Object -Property Size -Sum).Sum
    }
}

function Invoke-GitFetch {
    param([string]$Path)
    # Simulate fetch latency
    Start-Sleep -Milliseconds (100 + (Get-Random -Minimum 50 -Maximum 200))
    return @{ Changes = (Get-Random -Minimum 0 -Maximum 20) }
}

function Get-GitChangedFiles {
    param(
        [string]$Since,
        [string]$Path = "."
    )
    # Return files changed since last ingestion
    $changed = @()
    if ($Since) {
        $sinceDate = [DateTime]$Since
        $changed = $script:MockRepoFiles.Values | 
            Where-Object { $_.LastModified -gt $sinceDate } | 
            Select-Object -First (Get-Random -Minimum 1 -Maximum 50)
    }
    return $changed
}

function Invoke-HttpDownload {
    param(
        [string]$Url,
        [hashtable]$Headers = @{},
        [string]$Method = "GET"
    )
    # Simulate HTTP latency
    $baseLatency = switch -Regex ($Url) {
        'github\.com' { 200 }
        'gitlab\.com' { 250 }
        'bitbucket' { 300 }
        default { 150 }
    }
    $latency = $baseLatency + (Get-Random -Minimum 50 -Maximum 150)
    Start-Sleep -Milliseconds $latency
    
    return [PSCustomObject]@{
        Url = $Url
        StatusCode = 200
        Content = 'x' * (Get-Random -Minimum 1000 -Maximum 10000)
        Headers = @{ 'Content-Type' = 'application/octet-stream' }
    }
}

function Invoke-ApiRequest {
    param(
        [string]$Endpoint,
        [hashtable]$Body = @{},
        [string]$Method = "POST"
    )
    # Simulate API latency
    $latency = switch -Regex ($Endpoint) {
        'batch' { 300 + (Get-Random -Minimum 50 -Maximum 200) }
        'upload' { 500 + (Get-Random -Minimum 100 -Maximum 400) }
        'ingest' { 200 + (Get-Random -Minimum 50 -Maximum 150) }
        default { 150 + (Get-Random -Minimum 50 -Maximum 100) }
    }
    Start-Sleep -Milliseconds $latency
    
    return [PSCustomObject]@{
        Endpoint = $Endpoint
        Success = $true
        Processed = if ($Body.ContainsKey('files')) { $Body.files.Count } else { 1 }
    }
}

function Invoke-FileIngestion {
    param(
        [array]$Files,
        [switch]$Incremental,
        [hashtable]$Options = @{
            ExtractMetadata = $true
            GenerateEmbeddings = $true
            ValidateContent = $true
        }
    )
    
    $processed = 0
    $skipped = 0
    
    foreach ($file in $Files) {
        # Simulate processing time based on file size
        $processTime = [Math]::Max(1, $file.Size / 10000)
        Start-Sleep -Milliseconds $processTime
        
        if ($Incremental -and $script:IngestedFiles.Contains($file.Path)) {
            $skipped++
            continue
        }
        
        # Simulate extraction and embedding generation
        if ($Options.ExtractMetadata) { Start-Sleep -Milliseconds 5 }
        if ($Options.GenerateEmbeddings) { Start-Sleep -Milliseconds 15 }
        if ($Options.ValidateContent) { Start-Sleep -Milliseconds 3 }
        
        $script:IngestedFiles.Add($file.Path) | Out-Null
        $processed++
    }
    
    $script:LastIngestionTime = Get-Date
    
    return [PSCustomObject]@{
        Processed = $processed
        Skipped = $skipped
        Total = $Files.Count
        Duration = ($processed * $processTime) / 1000
    }
}

#endregion

#region Benchmark Definitions

function Invoke-GitIngestionBenchmarks {
    Write-Host "`n--- Git Ingestion Benchmarks ---" -ForegroundColor Yellow

    $repoSizes = @(
        @{ Name = "Small"; FileCount = $SmallFileCount; Desc = "100 files" }
        @{ Name = "Medium"; FileCount = $MediumFileCount; Desc = "1000 files" }
        @{ Name = "Large"; FileCount = $LargeFileCount; Desc = "10000 files" }
    )

    foreach ($size in $repoSizes) {
        Initialize-MockData -FileCount $size.FileCount
        
        # Full clone benchmark
        $result = Measure-Operation -Name "Ingestion.Git.FullClone.$($size.Name)" `
            -Setup { $script:MockRepoFiles.Clear() } `
            -ScriptBlock { Invoke-GitClone -Url $url } `
            -Parameters @{ url = $TestRepoUrl } `
            -WarmupRuns 0 `
            -BenchmarkRuns $BenchmarkRuns
        $result | Add-Member -NotePropertyName "FileCount" -NotePropertyValue $size.FileCount -Force
        $results.Add($result)

        # Shallow clone benchmark
        $result = Measure-Operation -Name "Ingestion.Git.ShallowClone.$($size.Name)" `
            -ScriptBlock { Invoke-GitClone -Url $url -Depth 1 } `
            -Parameters @{ url = $TestRepoUrl } `
            -WarmupRuns 0 `
            -BenchmarkRuns $BenchmarkRuns
        $result | Add-Member -NotePropertyName "FileCount" -NotePropertyValue $size.FileCount -Force
        $results.Add($result)

        # Full ingestion benchmark
        $files = $script:MockRepoFiles.Values
        $result = Measure-Operation -Name "Ingestion.Git.FullIngestion.$($size.Name)" `
            -Setup { $script:IngestedFiles.Clear() } `
            -ScriptBlock { Invoke-FileIngestion -Files $f } `
            -Parameters @{ f = $files } `
            -WarmupRuns 0 `
            -BenchmarkRuns [Math]::Max(1, [int]($BenchmarkRuns / 2))
        
        # Calculate throughput (files/hour)
        $durationHours = $result.Statistics.Mean / 3600000
        $throughput = if ($durationHours -gt 0) { [Math]::Round($size.FileCount / $durationHours, 2) } else { 0 }
        $result | Add-Member -NotePropertyName "ThroughputMetric" -NotePropertyValue "files/hour" -Force
        $result | Add-Member -NotePropertyName "Throughput" -NotePropertyValue $throughput -Force
        $result | Add-Member -NotePropertyName "FileCount" -NotePropertyValue $size.FileCount -Force
        $results.Add($result)

        # Incremental ingestion benchmark (simulate changes)
        $changedFiles = Get-GitChangedFiles -Since (Get-Date).AddMinutes(-10).ToString()
        $result = Measure-Operation -Name "Ingestion.Git.Incremental.$($size.Name)" `
            -ScriptBlock { Invoke-FileIngestion -Files $f -Incremental } `
            -Parameters @{ f = $changedFiles } `
            -WarmupRuns 0 `
            -BenchmarkRuns $BenchmarkRuns
        $result | Add-Member -NotePropertyName "ChangedFiles" -NotePropertyValue $changedFiles.Count -Force
        $results.Add($result)
    }
}

function Invoke-HttpIngestionBenchmarks {
    Write-Host "`n--- HTTP Ingestion Benchmarks ---" -ForegroundColor Yellow

    $urls = @(
        @{ Name = "GitHub_Raw"; Url = "https://github.com/user/repo/raw/main/file.gd" }
        @{ Name = "GitLab_Raw"; Url = "https://gitlab.com/user/repo/-/raw/main/file.gd" }
        @{ Name = "Generic_HTTP"; Url = "https://example.com/api/file.gd" }
    )

    foreach ($url in $urls) {
        # Single file download
        $result = Measure-Operation -Name "Ingestion.HTTP.SingleFile.$($url.Name)" `
            -ScriptBlock { Invoke-HttpDownload -Url $u } `
            -Parameters @{ u = $url.Url } `
            -WarmupRuns $WarmupRuns `
            -BenchmarkRuns $BenchmarkRuns
        $results.Add($result)
    }

    # Batch downloads
    $batchSizes = @(10, 50, 100)
    foreach ($batchSize in $batchSizes) {
        $batchUrls = @()
        for ($i = 0; $i -lt $batchSize; $i++) {
            $batchUrls += "https://github.com/user/repo/raw/main/file_$i.gd"
        }

        $result = Measure-Operation -Name "Ingestion.HTTP.Batch_$batchSize" `
            -ScriptBlock {
                foreach ($url in $urls) {
                    Invoke-HttpDownload -Url $url | Out-Null
                }
            } `
            -Parameters @{ urls = $batchUrls } `
            -WarmupRuns 1 `
            -BenchmarkRuns [Math]::Max(2, [int]($BenchmarkRuns / 2))
        $result | Add-Member -NotePropertyName "BatchSize" -NotePropertyValue $batchSize -Force
        
        # Calculate throughput
        $durationHours = $result.Statistics.Mean / 3600000
        $throughput = if ($durationHours -gt 0) { [Math]::Round($batchSize / $durationHours, 2) } else { 0 }
        $result | Add-Member -NotePropertyName "ThroughputMetric" -NotePropertyValue "files/hour" -Force
        $result | Add-Member -NotePropertyName "Throughput" -NotePropertyValue $throughput -Force
        $results.Add($result)
    }

    # Parallel downloads
    $result = Measure-Operation -Name "Ingestion.HTTP.Parallel_50" `
        -ScriptBlock {
            $urls | ForEach-Object -Parallel {
                # Simulate async download
                Start-Sleep -Milliseconds (200 + (Get-Random -Minimum 50 -Maximum 150))
            } -ThrottleLimit 10
        } `
        -Parameters @{ urls = $batchUrls } `
        -WarmupRuns 1 `
        -BenchmarkRuns [Math]::Max(2, [int]($BenchmarkRuns / 2))
    $result | Add-Member -NotePropertyName "ParallelJobs" -NotePropertyValue 10 -Force
    $results.Add($result)
}

function Invoke-ApiIngestionBenchmarks {
    Write-Host "`n--- API Ingestion Benchmarks ---" -ForegroundColor Yellow

    # Single file upload
    $result = Measure-Operation -Name "Ingestion.API.SingleUpload" `
        -ScriptBlock {
            Invoke-ApiRequest -Endpoint "/api/v1/upload" -Method POST `
                -Body @{ filename = "test.gd"; content = "# test" }
        } `
        -WarmupRuns $WarmupRuns `
        -BenchmarkRuns $BenchmarkRuns
    $results.Add($result)

    # Batch ingestion endpoints
    $batchSizes = @(10, 100, 500)
    foreach ($batchSize in $batchSizes) {
        $files = @()
        for ($i = 0; $i -lt $batchSize; $i++) {
            $files += @{ path = "file_$i.gd"; content = "# content $i" }
        }

        $result = Measure-Operation -Name "Ingestion.API.Batch_$batchSize" `
            -ScriptBlock {
                Invoke-ApiRequest -Endpoint "/api/v1/ingest/batch" -Method POST `
                    -Body @{ files = $f }
            } `
            -Parameters @{ f = $files } `
            -WarmupRuns 1 `
            -BenchmarkRuns [Math]::Max(2, [int]($BenchmarkRuns / 2))
        $result | Add-Member -NotePropertyName "BatchSize" -NotePropertyValue $batchSize -Force
        
        # Calculate throughput
        $durationHours = $result.Statistics.Mean / 3600000
        $throughput = if ($durationHours -gt 0) { [Math]::Round($batchSize / $durationHours, 2) } else { 0 }
        $result | Add-Member -NotePropertyName "ThroughputMetric" -NotePropertyValue "files/hour" -Force
        $result | Add-Member -NotePropertyName "Throughput" -NotePropertyValue $throughput -Force
        $results.Add($result)
    }

    # Streaming ingestion
    $result = Measure-Operation -Name "Ingestion.API.Streaming" `
        -ScriptBlock {
            # Simulate streaming 1000 files in chunks
            $chunkSize = 100
            for ($i = 0; $i -lt 1000; $i += $chunkSize) {
                $chunk = @()
                for ($j = 0; $j -lt $chunkSize; $j++) {
                    $chunk += @{ id = $i + $j; data = "x" * 1000 }
                }
                Invoke-ApiRequest -Endpoint "/api/v1/ingest/stream" `
                    -Body @{ chunk = $chunk; sequence = $i / $chunkSize } | Out-Null
            }
        } `
        -WarmupRuns 0 `
        -BenchmarkRuns [Math]::Max(1, [int]($BenchmarkRuns / 3))
    $result | Add-Member -NotePropertyName "TotalFiles" -NotePropertyValue 1000 -Force
    $results.Add($result)
}

function Invoke-ComparisonBenchmarks {
    Write-Host "`n--- Incremental vs Full Comparison ---" -ForegroundColor Yellow

    # Prepare test data
    Initialize-MockData -FileCount 1000
    $allFiles = $script:MockRepoFiles.Values

    # Full ingestion (no prior state)
    $script:IngestedFiles.Clear()
    $result = Measure-Operation -Name "Ingestion.Compare.Full_NoState" `
        -ScriptBlock { Invoke-FileIngestion -Files $f } `
        -Parameters @{ f = $allFiles } `
        -WarmupRuns 0 `
        -BenchmarkRuns [Math]::Max(1, [int]($BenchmarkRuns / 2))
    $result | Add-Member -NotePropertyName "Type" -NotePropertyValue "Full (cold)" -Force
    $results.Add($result)

    # Incremental (all files already ingested)
    $result = Measure-Operation -Name "Ingestion.Compare.Incremental_NoChanges" `
        -ScriptBlock { Invoke-FileIngestion -Files $f -Incremental } `
        -Parameters @{ f = $allFiles } `
        -WarmupRuns 0 `
        -BenchmarkRuns $BenchmarkRuns
    $result | Add-Member -NotePropertyName "Type" -NotePropertyValue "Incremental (no changes)" -Force
    $results.Add($result)

    # Simulate 10% changes
    $changedFiles = $allFiles | Get-Random -Count 100
    $changedFiles | ForEach-Object { $script:IngestedFiles.Remove($_.Path) | Out-Null }
    
    $result = Measure-Operation -Name "Ingestion.Compare.Incremental_10Percent" `
        -ScriptBlock { Invoke-FileIngestion -Files $f -Incremental } `
        -Parameters @{ f = $changedFiles } `
        -WarmupRuns 0 `
        -BenchmarkRuns $BenchmarkRuns
    $result | Add-Member -NotePropertyName "Type" -NotePropertyValue "Incremental (10% changes)" -Force
    $result | Add-Member -NotePropertyName "ChangedCount" -NotePropertyValue 100 -Force
    $results.Add($result)
}

function Invoke-ThroughputBenchmarks {
    Write-Host "`n--- Throughput Benchmarks ---" -ForegroundColor Yellow

    # Measure sustained throughput over time
    $durations = @(1, 5, 10)  # minutes

    foreach ($durationMinutes in $durations) {
        $result = Measure-Operation -Name "Ingestion.Throughput.Sustained_${durationMinutes}min" `
            -ScriptBlock {
                $processed = 0
                $start = Get-Date
                while (((Get-Date) - $start).TotalMinutes -lt $duration) {
                    # Simulate processing a file
                    Start-Sleep -Milliseconds (50 + (Get-Random -Minimum -20 -Maximum 20))
                    $processed++
                }
                $processed
            } `
            -Parameters @{ duration = $durationMinutes } `
            -WarmupRuns 0 `
            -BenchmarkRuns 1
        
        # Calculate actual throughput
        $actualDuration = $result.Statistics.Mean / 60000  # convert ms to minutes
        $filesProcessed = $result.RawData.Timings[0]  # single run value
        $throughput = if ($actualDuration -gt 0) { [Math]::Round($filesProcessed / $actualDuration * 60, 2) } else { 0 }
        
        $result | Add-Member -NotePropertyName "ThroughputMetric" -NotePropertyValue "files/hour" -Force
        $result | Add-Member -NotePropertyName "Throughput" -NotePropertyValue $throughput -Force
        $result | Add-Member -NotePropertyName "DurationMinutes" -NotePropertyValue $durationMinutes -Force
        $results.Add($result)
    }

    # Peak throughput test
    $result = Measure-Operation -Name "Ingestion.Throughput.Peak" `
        -ScriptBlock {
            $batchSize = 50
            $processed = 0
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sw.ElapsedMilliseconds -lt 60000) {
                # Process batch
                for ($i = 0; $i -lt $batchSize; $i++) {
                    Start-Sleep -Milliseconds 10
                }
                $processed += $batchSize
            }
            $processed
        } `
        -WarmupRuns 0 `
        -BenchmarkRuns 2
    
    $throughput = $result.RawData.Timings[0]  # files in 1 minute
    $result | Add-Member -NotePropertyName "ThroughputMetric" -NotePropertyValue "files/hour" -Force
    $result | Add-Member -NotePropertyName "Throughput" -NotePropertyValue ($throughput * 60) -Force
    $results.Add($result)
}

#endregion

#region Main Execution

Write-Host "`n=== Running Ingestion Benchmarks ===" -ForegroundColor Cyan

# Run all benchmark categories
Invoke-GitIngestionBenchmarks
Invoke-HttpIngestionBenchmarks
Invoke-ApiIngestionBenchmarks
Invoke-ComparisonBenchmarks
Invoke-ThroughputBenchmarks

# Summary
Write-Host "`n=== Ingestion Benchmarks Complete ===" -ForegroundColor Cyan
Write-Host "Total benchmarks: $($results.Count)" -ForegroundColor Gray

# Return results
return $results

#endregion
