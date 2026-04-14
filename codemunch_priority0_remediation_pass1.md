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
- empty catch blocks in safe property access paths
- `Write-Host` used in reusable module functions
- `Get-GoldenTaskScore` / `Invoke-PackGoldenTasks` confidence aggregation reading the wrong property path in some cases
- JSON result loading suppressing parse/read failures too quietly

### Patch

```diff
--- a/module/LLMWorkflow/governance/GoldenTasks.ps1
+++ b/module/LLMWorkflow/governance/GoldenTasks.ps1
@@
 if (-not (Test-Path $script:GoldenTaskConfig.SuitesDirectory)) {
     $null = New-Item -ItemType Directory -Path $script:GoldenTaskConfig.SuitesDirectory -Force
 }
+
+function Get-SafeObjectPropertyValue {
+    [CmdletBinding()]
+    param(
+        [Parameter(Mandatory = $true)]
+        $InputObject,
+
+        [Parameter(Mandatory = $true)]
+        [string]$PropertyName,
+
+        [Parameter()]
+        $Default = $null
+    )
+
+    if ($null -eq $InputObject) {
+        return $Default
+    }
+
+    if ($InputObject -is [hashtable]) {
+        if ($InputObject.ContainsKey($PropertyName)) {
+            return $InputObject[$PropertyName]
+        }
+
+        return $Default
+    }
+
+    $property = $InputObject.PSObject.Properties[$PropertyName]
+    if ($null -ne $property) {
+        return $property.Value
+    }
+
+    return $Default
+}
+
+function Write-GoldenTaskSummary {
+    [CmdletBinding()]
+    param(
+        [Parameter(Mandatory = $true)]
+        [hashtable]$Summary
+    )
+
+    $lines = @(
+        '',
+        "Golden Task Summary for '$($Summary.PackId)':",
+        "  Tasks Run: $($Summary.TasksRun)",
+        "  Passed: $($Summary.Passed)",
+        "  Failed: $($Summary.Failed)",
+        "  Pass Rate: $([math]::Round($Summary.PassRate * 100, 2))%",
+        "  Avg Confidence: $($Summary.AverageConfidence)"
+    )
+
+    foreach ($line in $lines) {
+        Write-Information $line -InformationAction Continue
+    }
+}
@@
             if ($t -is [hashtable]) {
                 $taskCategory = $t['category']
                 $taskDifficulty = $t['difficulty']
                 $taskTags = $t['tags']
-            } else {
-                try { $taskCategory = $t.category } catch { }
-                try { $taskDifficulty = $t.difficulty } catch { }
-                try { $taskTags = $t.tags } catch { }
+            }
+            else {
+                $taskCategory = Get-SafeObjectPropertyValue -InputObject $t -PropertyName 'category'
+                $taskDifficulty = Get-SafeObjectPropertyValue -InputObject $t -PropertyName 'difficulty'
+                $taskTags = Get-SafeObjectPropertyValue -InputObject $t -PropertyName 'tags' -Default @()
             }
@@
         $resultFiles = Get-ChildItem -Path $resultsDir -Filter "*.json" -Recurse -ErrorAction SilentlyContinue
+        $resultFiles = Get-ChildItem -Path $resultsDir -Filter "*.json" -Recurse -File
 
         foreach ($file in $resultFiles) {
             try {
-                $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
-                $result = $content | ConvertFrom-Json -ErrorAction SilentlyContinue
+                $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
+                $result = $content | ConvertFrom-Json -ErrorAction Stop
 
                 if ($result) {
                     # Convert to hashtable for consistency
                     $resultObj = ConvertTo-Hashtable -InputObject $result
                     $allResults += $resultObj
                 }
             }
             catch {
-                Write-Verbose "Error loading result file '$($file.Name)': $_"
+                Write-Warning "Failed to load golden-task result file '$($file.Name)': $_"
             }
         }
@@
-                if ($r -is [hashtable]) { $isSucc = $r['Success'] -eq $true } 
-                else { try { $isSucc = $r.Success -eq $true } catch { $isSucc = $false } }
+                if ($r -is [hashtable]) {
+                    $isSucc = $r['Success'] -eq $true
+                }
+                else {
+                    $isSucc = (Get-SafeObjectPropertyValue -InputObject $r -PropertyName 'Success' -Default $false) -eq $true
+                }
                 $isSucc
             })).Count
         }
@@
         if ($resultList.Count -gt 0) {
             $measure = $resultList | Measure-Object -Property { 
                 $conf = 0.0
-                if ($_ -is [hashtable]) { $conf = $_['Confidence'] } 
-                else { try { $conf = $_.Confidence } catch { $conf = 0 } }
+                if ($_ -is [hashtable]) {
+                    if ($_.ContainsKey('Validation') -and $_['Validation'] -is [hashtable]) {
+                        $conf = $_['Validation']['Confidence']
+                    }
+                    elseif ($_.ContainsKey('Confidence')) {
+                        $conf = $_['Confidence']
+                    }
+                }
+                else {
+                    $validation = Get-SafeObjectPropertyValue -InputObject $_ -PropertyName 'Validation'
+                    if ($null -ne $validation) {
+                        $conf = Get-SafeObjectPropertyValue -InputObject $validation -PropertyName 'Confidence' -Default 0.0
+                    }
+                    else {
+                        $conf = Get-SafeObjectPropertyValue -InputObject $_ -PropertyName 'Confidence' -Default 0.0
+                    }
+                }
                 $conf
             } -Average
@@
-        Write-Host "`nGolden Task Summary for '$PackId':" -ForegroundColor Cyan
-        Write-Host "  Tasks Run: $($summary.TasksRun)" -ForegroundColor White
-        Write-Host "  Passed: $($summary.Passed)" -ForegroundColor Green
-        Write-Host "  Failed: $($summary.Failed)" -ForegroundColor Red
-        Write-Host "  Pass Rate: $([math]::Round($summary.PassRate * 100, 2))%" -ForegroundColor Yellow
-        Write-Host "  Avg Confidence: $($summary.AverageConfidence)" -ForegroundColor White
+        Write-GoldenTaskSummary -Summary $summary
 
         return $summary
     }
 }
@@
-            Write-Host "`nGolden Task Suite Summary - '$($Suite.suiteName)'" -ForegroundColor Cyan
-            Write-Host "  Tasks Run: $($summary.TasksRun)" -ForegroundColor White
-            Write-Host "  Passed: $($summary.Passed)" -ForegroundColor Green
-            Write-Host "  Failed: $($summary.Failed)" -ForegroundColor Red
-            Write-Host "  Pass Rate: $($summary.PassRate)%" -ForegroundColor Yellow
-            Write-Host "  Avg Confidence: $($summary.AverageConfidence)" -ForegroundColor White
+            foreach ($line in @(
+                '',
+                "Golden Task Suite Summary - '$($Suite.suiteName)'",
+                "  Tasks Run: $($summary.TasksRun)",
+                "  Passed: $($summary.Passed)",
+                "  Failed: $($summary.Failed)",
+                "  Pass Rate: $($summary.PassRate)%",
+                "  Avg Confidence: $($summary.AverageConfidence)"
+            )) {
+                Write-Information $line -InformationAction Continue
+            }
 
             return $summary
         }
@@
-            Write-Host "`nGolden Task Run Comparison" -ForegroundColor Cyan
-            Write-Host "  Pack: $PackId$(if($TaskId){" / Task: $TaskId"})" -ForegroundColor White
-            Write-Host "  Baseline: $($result.BaselineRun)" -ForegroundColor Gray
-            Write-Host "  Comparison: $($result.ComparisonRun)" -ForegroundColor Gray
-            Write-Host "  Tasks Compared: $($result.Summary.TotalTasksCompared)" -ForegroundColor White
-            
-            if ($result.Summary.CriticalRegressions -gt 0) {
-                Write-Host "  CRITICAL REGRESSIONS: $($result.Summary.CriticalRegressions)" -ForegroundColor Red
-            }
-            if ($result.Summary.TotalRegressions -gt 0) {
-                Write-Host "  Total Regressions: $($result.Summary.TotalRegressions)" -ForegroundColor Yellow
-            }
-            if ($result.Summary.TotalImprovements -gt 0) {
-                Write-Host "  Improvements: $($result.Summary.TotalImprovements)" -ForegroundColor Green
-            }
-            Write-Host "  Status: $($result.Summary.Status)" -ForegroundColor $(if ($hasRegression) { "Red" } else { "Green" })
+            foreach ($line in @(
+                '',
+                'Golden Task Run Comparison',
+                "  Pack: $PackId$(if($TaskId){" / Task: $TaskId"})",
+                "  Baseline: $($result.BaselineRun)",
+                "  Comparison: $($result.ComparisonRun)",
+                "  Tasks Compared: $($result.Summary.TotalTasksCompared)",
+                $(if ($result.Summary.CriticalRegressions -gt 0) { "  CRITICAL REGRESSIONS: $($result.Summary.CriticalRegressions)" }),
+                $(if ($result.Summary.TotalRegressions -gt 0) { "  Total Regressions: $($result.Summary.TotalRegressions)" }),
+                $(if ($result.Summary.TotalImprovements -gt 0) { "  Improvements: $($result.Summary.TotalImprovements)" }),
+                "  Status: $($result.Summary.Status)"
+            ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
+                Write-Information $line -InformationAction Continue
+            }
 
             if ($FailOnRegression -and $hasRegression) {
                 Write-Error "Regressions detected in golden task comparison"
```

### 2) `module/LLMWorkflow/ingestion/DoclingAdapter.ps1`

Problems fixed:
- process-kill failures silently swallowed
- temp cleanup failures silently swallowed

### Patch

```diff
--- a/module/LLMWorkflow/ingestion/DoclingAdapter.ps1
+++ b/module/LLMWorkflow/ingestion/DoclingAdapter.ps1
@@
 $script:ModuleName = 'DoclingAdapter'
 $script:SupportedFormats = @('.pdf', '.docx', '.pptx')
+
+function Write-DoclingSuppressedException {
+    [CmdletBinding()]
+    param(
+        [Parameter(Mandatory = $true)]
+        [string]$Context,
+
+        [Parameter(Mandatory = $true)]
+        [System.Management.Automation.ErrorRecord]$ErrorRecord
+    )
+
+    Write-Verbose "[$script:ModuleName] $Context: $($ErrorRecord.Exception.Message)"
+}
@@
         $null = $process.WaitForExit(15000)
         if (-not $process.HasExited) {
-            try { $process.Kill() } catch { }
+            try {
+                $process.Kill()
+            }
+            catch {
+                Write-DoclingSuppressedException -Context 'Failed to terminate timed-out availability check process' -ErrorRecord $_
+            }
+
             return $false
         }
@@
         $completed = $process.WaitForExit($Adapter.timeoutSeconds * 1000)
         if (-not $completed) {
-            try { $process.Kill() } catch { }
+            try {
+                $process.Kill()
+            }
+            catch {
+                Write-DoclingSuppressedException -Context 'Failed to terminate timed-out extraction process' -ErrorRecord $_
+            }
+
             throw 'Docling extraction timed out.'
         }
@@
     finally {
         if (Test-Path -LiteralPath $tempOutDir) {
-            Remove-Item -LiteralPath $tempOutDir -Recurse -Force -ErrorAction SilentlyContinue
+            try {
+                Remove-Item -LiteralPath $tempOutDir -Recurse -Force -ErrorAction Stop
+            }
+            catch {
+                Write-DoclingSuppressedException -Context "Failed to clean temporary directory '$tempOutDir'" -ErrorRecord $_
+            }
         }
     }
 }
```

### 3) `module/LLMWorkflow/ingestion/ExternalIngestion.ps1`

Problems fixed:
- swallowed link-parsing exceptions during docs-site crawling
- file read failures during secret scanning hidden by `SilentlyContinue`
- cleanup path can fail without signal

### Patch

```diff
--- a/module/LLMWorkflow/ingestion/ExternalIngestion.ps1
+++ b/module/LLMWorkflow/ingestion/ExternalIngestion.ps1
@@
 $script:ModuleName = 'ExternalIngestion'
+
+function Write-ExternalIngestionSuppressedException {
+    [CmdletBinding()]
+    param(
+        [Parameter(Mandatory = $true)]
+        [string]$Context,
+
+        [Parameter(Mandatory = $true)]
+        [System.Management.Automation.ErrorRecord]$ErrorRecord
+    )
+
+    Write-Verbose "[$script:ModuleName] $Context: $($ErrorRecord.Exception.Message)"
+}
@@
 function Extract-LinksFromHtml {
     param([string]$Html, [string]$BaseUrl)
     $links = @()
     $baseUri = [Uri]$BaseUrl
     $matches = [regex]::Matches($Html, 'href=["'']([^"'']+)["'']')
     foreach ($m in $matches) {
         try {
             $uri = New-Object Uri($baseUri, $m.Groups[1].Value)
             if ($uri.Host -eq $baseUri.Host) { $links += $uri.AbsoluteUri }
-        } catch {}
+        }
+        catch {
+            Write-ExternalIngestionSuppressedException -Context "Failed to parse documentation-site link '$($m.Groups[1].Value)' from '$BaseUrl'" -ErrorRecord $_
+        }
     }
     return $links | Select-Object -Unique
 }
@@
                 try {
-                    $content = Get-Content -Path $file -Raw -ErrorAction SilentlyContinue
-                    if (-not $content) { continue }
+                    $content = Get-Content -Path $file -Raw -ErrorAction Stop
+                    if ([string]::IsNullOrWhiteSpace($content)) {
+                        $runResult.warnings += "Skipped empty file during secret scan: $file"
+                        continue
+                    }
 
                     $secrets = Find-Secrets -Content $content -FilePath $file
@@
                 }
                 catch {
                     $runResult.warnings += "Failed to scan: $file - $_"
+                    Write-IngestionLog -Level WARN -Message 'Secret scan failed for file' -JobId $JobId -Metadata @{
+                        file = $file
+                        error = $_.Exception.Message
+                    }
                 }
             }
@@
             if (Test-Path $workDir) {
-                Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
+                try {
+                    Remove-Item -Path $workDir -Recurse -Force -ErrorAction Stop
+                }
+                catch {
+                    $runResult.warnings += "Failed to remove temporary work directory: $workDir - $_"
+                    Write-IngestionLog -Level WARN -Message 'Temporary work directory cleanup failed' -JobId $JobId -Metadata @{
+                        path = $workDir
+                        error = $_.Exception.Message
+                    }
+                }
             }
```

### 4) `module/LLMWorkflow/ingestion/parsers/GeometryNodesParser.ps1`

Problems fixed:
- invalid JSON auto-detection silently swallowed
- JSON fallback in blend-text parsing silently swallowed

### Patch

```diff
--- a/module/LLMWorkflow/ingestion/parsers/GeometryNodesParser.ps1
+++ b/module/LLMWorkflow/ingestion/parsers/GeometryNodesParser.ps1
@@
 Set-StrictMode -Version Latest
+
+function Write-GeometryNodesSuppressedException {
+    [CmdletBinding()]
+    param(
+        [Parameter(Mandatory = $true)]
+        [string]$Context,
+
+        [Parameter(Mandatory = $true)]
+        [System.Management.Automation.ErrorRecord]$ErrorRecord
+    )
+
+    Write-Verbose "[GeometryNodesParser] $Context: $($ErrorRecord.Exception.Message)"
+}
@@
     if (($trimmed.StartsWith('{') -and $trimmed.EndsWith('}')) -or
         ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']'))) {
         try {
             $null = $trimmed | ConvertFrom-Json -ErrorAction Stop
             return 'Json'
         }
         catch {
+            Write-GeometryNodesSuppressedException -Context 'Auto-detect JSON probe failed; continuing with other Geometry Nodes heuristics' -ErrorRecord $_
         }
     }
@@
     if (($trimmed.StartsWith('{') -and $trimmed.EndsWith('}')) -or
         ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']'))) {
         try {
             return Parse-GeometryNodesFromJson -JsonContent $TextContent
         }
         catch {
+            Write-GeometryNodesSuppressedException -Context 'Blend-text JSON parse failed; falling back to Python-style parsing' -ErrorRecord $_
         }
     }
 
     return Parse-GeometryNodesFromPython -PythonContent $TextContent
 }
```

## Why this is the right first pass

This pass does not pretend to solve v1.0.
It removes hidden failure behavior from the places the repo audit already identified as risky, and it does it without broad refactors.

## Highest-value follow-up after this pass

1. Sweep remaining `-ErrorAction SilentlyContinue` in reusable modules and classify each one as either intentional or a bug.
2. Split `ExternalIngestion.ps1` into fetchers, state/persistence, security scan, and orchestration layers.
3. Add explicit tests for failure surfacing:
   - malformed result JSON in `GoldenTasks`
   - timed-out Docling process cleanup path
   - docs-site malformed link handling in `ExternalIngestion`
   - GeometryNodes JSON probe fallback behavior
4. Continue `Write-Host` removal in reusable modules, keeping host-only output limited to entrypoint scripts and user-facing tooling.

## One concrete bug found while doing this pass

`Invoke-PackGoldenTasks` average confidence calculation is using `Confidence` at the wrong level for many results. The result shape produced by `Invoke-GoldenTask` stores confidence under `Validation.Confidence`, so the current summary can under-report or zero-out confidence even when validation succeeded.
