# CodeMunch / LLMWorkflow Priority 0 Remediation Pass 1

Scope: first implementation pass against the post-0.9.6 strategic plan.

This pass targets the highest-value Priority 0 issues:
- empty or effectively silent exception handling
- console-only output inside reusable module functions
- hidden signal loss in ingestion/governance paths
- one concrete correctness bug in golden-task scoring

## What this pass fixes

### 1) `module/LLMWorkflow/governance/GoldenTasks.ps1`

Problems fixed:
- empty `catch {}` blocks inside strict-mode-safe property access
- `Write-Host` usage inside reusable module functions
- incorrect average-confidence aggregation path in `Invoke-PackGoldenTasks`

#### Exact changes

##### A. Replace silent property-access catches with explicit null-safe checks

Current pattern:

```powershell
if ($t -is [hashtable]) {
    $taskCategory = $t['category']
    $taskDifficulty = $t['difficulty']
    $taskTags = $t['tags']
} else {
    try { $taskCategory = $t.category } catch { }
    try { $taskDifficulty = $t.difficulty } catch { }
    try { $taskTags = $t.tags } catch { }
}
```

Replace with:

```powershell
if ($t -is [hashtable]) {
    $taskCategory = $t['category']
    $taskDifficulty = $t['difficulty']
    $taskTags = $t['tags']
}
else {
    if ($t.PSObject.Properties['category']) {
        $taskCategory = $t.category
    }
    if ($t.PSObject.Properties['difficulty']) {
        $taskDifficulty = $t.difficulty
    }
    if ($t.PSObject.Properties['tags']) {
        $taskTags = $t.tags
    }
}
```

Reason:
- removes silent exception swallowing
- preserves strict-mode safety
- makes missing properties an expected branch instead of an ignored failure

##### B. Fix confidence aggregation bug in `Invoke-PackGoldenTasks`

Current code:

```powershell
$measure = $resultList | Measure-Object -Property {
    $conf = 0.0
    if ($_ -is [hashtable]) { $conf = $_['Confidence'] }
    else { try { $conf = $_.Confidence } catch { $conf = 0 } }
    $conf
} -Average
```

Problem:
- `Invoke-GoldenTask` returns `Success` at the top level, but confidence lives under `Validation.Confidence`
- summary output can therefore under-report or flatten confidence to zero

Replace with:

```powershell
$measure = $resultList | Measure-Object -Property {
    $conf = 0.0
    if ($_ -is [hashtable]) {
        if ($_['Validation'] -and $_['Validation']['Confidence'] -ne $null) {
            $conf = $_['Validation']['Confidence']
        }
    }
    else {
        if ($_.PSObject.Properties['Validation'] -and $_.Validation -and
            $_.Validation.PSObject.Properties['Confidence'] -and
            $_.Validation.Confidence -ne $null) {
            $conf = $_.Validation.Confidence
        }
    }
    $conf
} -Average
```

Reason:
- fixes a real correctness issue in governance summary reporting
- improves release-signal trustworthiness

##### C. Replace `Write-Host` summary output with information stream

Current code:

```powershell
Write-Host "`nGolden Task Summary for '$PackId':" -ForegroundColor Cyan
Write-Host "  Tasks Run: $($summary.TasksRun)" -ForegroundColor White
Write-Host "  Passed: $($summary.Passed)" -ForegroundColor Green
Write-Host "  Failed: $($summary.Failed)" -ForegroundColor Red
Write-Host "  Pass Rate: $([math]::Round($summary.PassRate * 100, 2))%" -ForegroundColor Yellow
Write-Host "  Avg Confidence: $($summary.AverageConfidence)" -ForegroundColor White
```

Replace with:

```powershell
Write-Information "Golden Task Summary for '$PackId':"
Write-Information "  Tasks Run: $($summary.TasksRun)"
Write-Information "  Passed: $($summary.Passed)"
Write-Information "  Failed: $($summary.Failed)"
Write-Information "  Pass Rate: $([math]::Round($summary.PassRate * 100, 2))%"
Write-Information "  Avg Confidence: $($summary.AverageConfidence)"
```

Apply the same change to:
- `Invoke-GoldenTaskSuite`
- `Compare-GoldenTaskRuns`

Reason:
- keeps module output pipeline-safe
- preserves operator visibility without hardwiring console UI behavior

---

### 2) `module/LLMWorkflow/ingestion/DoclingAdapter.ps1`

Problems fixed:
- silently ignored process-kill failure during timeout handling
- silently ignored temp-directory cleanup failure

#### Exact changes

##### A. Surface timeout kill failure as a warning

Current code:

```powershell
if (-not $process.HasExited) {
    try { $process.Kill() } catch { }
    return $false
}
```

Replace with:

```powershell
if (-not $process.HasExited) {
    try {
        $process.Kill()
    }
    catch {
        Write-Warning "[$script:ModuleName] Failed to terminate timed-out Docling availability check process: $($_.Exception.Message)"
    }
    return $false
}
```

##### B. Surface timed-out extraction kill failure

Current code:

```powershell
if (-not $completed) {
    try { $process.Kill() } catch { }
    throw 'Docling extraction timed out.'
}
```

Replace with:

```powershell
if (-not $completed) {
    try {
        $process.Kill()
    }
    catch {
        Write-Warning "[$script:ModuleName] Failed to terminate timed-out Docling extraction process: $($_.Exception.Message)"
    }
    throw 'Docling extraction timed out.'
}
```

##### C. Surface cleanup failure

Current code:

```powershell
finally {
    if (Test-Path -LiteralPath $tempOutDir) {
        Remove-Item -LiteralPath $tempOutDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
```

Replace with:

```powershell
finally {
    if (Test-Path -LiteralPath $tempOutDir) {
        try {
            Remove-Item -LiteralPath $tempOutDir -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "[$script:ModuleName] Failed to remove temporary output directory '$tempOutDir': $($_.Exception.Message)"
        }
    }
}
```

Reason:
- cleanup is still non-fatal
- operators now get visible signal when environment hygiene is breaking

---

### 3) `module/LLMWorkflow/ingestion/ExternalIngestion.ps1`

Problems fixed:
- silent link-extraction failures during docs-site crawl
- hidden file-read failures during secret scan
- silent temp cleanup failure after ingestion runs

#### Exact changes

##### A. Surface HTML link parse failures

Current code:

```powershell
foreach ($m in $matches) {
    try {
        $uri = New-Object Uri($baseUri, $m.Groups[1].Value)
        if ($uri.Host -eq $baseUri.Host) { $links += $uri.AbsoluteUri }
    } catch {}
}
```

Replace with:

```powershell
foreach ($m in $matches) {
    try {
        $uri = New-Object Uri($baseUri, $m.Groups[1].Value)
        if ($uri.Host -eq $baseUri.Host) {
            $links += $uri.AbsoluteUri
        }
    }
    catch {
        Write-Verbose "[$script:ModuleName] Skipping malformed documentation link '$($m.Groups[1].Value)': $($_.Exception.Message)"
    }
}
```

Reason:
- malformed links are not fatal
- crawl blind spots stop being invisible

##### B. Surface secret-scan file read failures explicitly

Current code:

```powershell
catch {
    $runResult.warnings += "Failed to scan: $file - $_"
}
```

Replace with:

```powershell
catch {
    $message = "Failed to scan '$file' for secrets: $($_.Exception.Message)"
    $runResult.warnings += $message
    Write-IngestionLog -Level WARN -Message $message -JobId $JobId -Metadata @{ file = $file }
}
```

Reason:
- pushes failures into the structured ingestion log
- improves diagnosability for Priority 0 failure visibility

##### C. Surface work-dir cleanup failure

Current code:

```powershell
if (Test-Path $workDir) {
    Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
}
```

Replace with:

```powershell
if (Test-Path $workDir) {
    try {
        Remove-Item -Path $workDir -Recurse -Force -ErrorAction Stop
    }
    catch {
        $cleanupMessage = "Failed to remove ingestion work directory '$workDir': $($_.Exception.Message)"
        $runResult.warnings += $cleanupMessage
        Write-IngestionLog -Level WARN -Message $cleanupMessage -JobId $JobId -Metadata @{ workDir = $workDir }
    }
}
```

Reason:
- preserves non-fatal behavior
- stops disk-hygiene failures from disappearing

---

### 4) `module/LLMWorkflow/ingestion/parsers/GeometryNodesParser.ps1`

Problems fixed:
- silent JSON-probe failure during input-type detection
- silent fallback failure in blend-text parser

#### Exact changes

##### A. Surface JSON probe failure in input detection

Current code:

```powershell
if (($trimmed.StartsWith('{') -and $trimmed.EndsWith('}')) -or
    ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']'))) {
    try {
        $null = $trimmed | ConvertFrom-Json -ErrorAction Stop
        return 'Json'
    }
    catch {
    }
}
```

Replace with:

```powershell
if (($trimmed.StartsWith('{') -and $trimmed.EndsWith('}')) -or
    ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']'))) {
    try {
        $null = $trimmed | ConvertFrom-Json -ErrorAction Stop
        return 'Json'
    }
    catch {
        Write-Verbose "[GeometryNodesParser] JSON probe failed during input-type detection: $($_.Exception.Message)"
    }
}
```

##### B. Surface JSON fallback failure in blend-text parsing

Current code:

```powershell
if (($trimmed.StartsWith('{') -and $trimmed.EndsWith('}')) -or
    ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']'))) {
    try {
        return Parse-GeometryNodesFromJson -JsonContent $TextContent
    }
    catch {
    }
}
```

Replace with:

```powershell
if (($trimmed.StartsWith('{') -and $trimmed.EndsWith('}')) -or
    ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']'))) {
    try {
        return Parse-GeometryNodesFromJson -JsonContent $TextContent
    }
    catch {
        Write-Verbose "[GeometryNodesParser] Blend-text JSON parse failed, falling back to Python-style parsing: $($_.Exception.Message)"
    }
}
```

Reason:
- keeps intended fallback behavior
- exposes why the parser changed interpretation path

---

## Recommended small follow-up tests

### `tests/Governance.Tests.ps1`

Add coverage for the fixed confidence aggregation path:

```powershell
It "Uses Validation.Confidence when summarizing pack golden task runs" {
    $testTasks = @(
        New-GoldenTask -TaskId "gt-test-pack-001" -Name "Task 1" -PackId "test-pack" -Query "Query 1" -ExpectedResult @{ result = "success" },
        New-GoldenTask -TaskId "gt-test-pack-002" -Name "Task 2" -PackId "test-pack" -Query "Query 2" -ExpectedResult @{ result = "success" }
    )

    Mock Get-PredefinedGoldenTasks { return $testTasks }
    Mock Invoke-GoldenTask {
        return @{
            Task = @{ TaskId = "gt-test-pack-001" }
            Success = $true
            Validation = @{ Success = $true; Confidence = 0.9 }
        }
    }

    $result = Invoke-PackGoldenTasks -PackId "test-pack"
    $result.AverageConfidence | Should -BeGreaterThan 0
}
```

### `tests/DocumentIngestion.Tests.ps1`

Add non-fatal cleanup visibility tests where practical by mocking temp cleanup or process timeout behavior.

---

## Why this pass is worth landing first

This is not cosmetic cleanup.

It improves:
- operator visibility
- CI debuggability
- governance signal accuracy
- ingestion-path observability
- strict-mode-safe behavior without exception suppression

That matches the remediation plan’s first release priority:
- failure visibility and unsafe execution cleanup

## Next pass after this one

The next highest-value pass should be:
1. broader `Write-Host` reduction in reusable modules
2. `-ErrorAction SilentlyContinue` triage in core and retrieval paths
3. contract hygiene on new ingestion modules (`[CmdletBinding()]`, `.SYNOPSIS`, `[OutputType()]` consistency)
4. release-gate tests for foundational runtime behavior
