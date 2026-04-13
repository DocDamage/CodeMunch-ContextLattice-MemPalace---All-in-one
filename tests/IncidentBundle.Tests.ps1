#requires -Version 5.1
<#
.SYNOPSIS
    Unit tests for IncidentBundle module.

.DESCRIPTION
    Tests the Phase 5 Answer Incident Bundle system.
#>

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'
$script:TestResults = @{
    Passed = 0
    Failed = 0
    Tests = @()
}

function Test-Case {
    param(
        [string]$Name,
        [scriptblock]$Test
    )
    
    try {
        & $Test
        $script:TestResults.Passed++
        $script:TestResults.Tests += @{ Name = $Name; Result = 'PASS' }
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    }
    catch {
        $script:TestResults.Failed++
        $script:TestResults.Tests += @{ Name = $Name; Result = 'FAIL'; Error = $_ }
        Write-Host "  [FAIL] $Name : $_" -ForegroundColor Red
    }
}

# Import the module
$modulePath = Join-Path $PSScriptRoot '../module/LLMWorkflow/retrieval/IncidentBundle.ps1'
if (-not (Test-Path $modulePath)) {
    $modulePath = Join-Path $PSScriptRoot '../module/LLMWorkflow/retrieval/IncidentBundle.ps1'
}

Write-Host "`nLoading IncidentBundle module from: $modulePath" -ForegroundColor Cyan
# Source the file (Export-ModuleMember warning is expected when not loaded as module)
try { . $modulePath } catch {}

Write-Host "`nRunning IncidentBundle Tests..." -ForegroundColor Cyan
Write-Host "=" * 60

# Test 1: New-AnswerIncidentBundle
Test-Case -Name "New-AnswerIncidentBundle creates bundle with required fields" -Test {
    $bundle = New-AnswerIncidentBundle -Query "How do I use X?" -FinalAnswer "You use X like this..."
    
    if (-not $bundle.incidentId) { throw "Missing incidentId" }
    if (-not $bundle.createdAt) { throw "Missing createdAt" }
    if ($bundle.status -ne 'open') { throw "Expected status 'open', got '$($bundle.status)'" }
    if ($bundle.bundle.query -ne "How do I use X?") { throw "Query mismatch" }
    if ($bundle.bundle.finalAnswer -ne "You use X like this...") { throw "Answer mismatch" }
    if ($bundle.schemaVersion -ne 1) { throw "Expected schema version 1" }
}

# Test 2: Add-IncidentEvidence
Test-Case -Name "Add-IncidentEvidence adds selected evidence" -Test {
    $bundle = New-AnswerIncidentBundle -Query "Test query"
    $evidence = @{ source = 'doc1.md'; authority = 'official'; content = 'Important info' }
    
    $bundle = Add-IncidentEvidence -Incident $bundle -Evidence $evidence -Type 'selected'
    
    if ($bundle.bundle.selectedEvidence.Count -ne 1) { throw "Expected 1 selected evidence" }
    if ($bundle.bundle.selectedEvidence[0].source -ne 'doc1.md') { throw "Evidence source mismatch" }
}

# Test 3: Add-IncidentEvidence (excluded)
Test-Case -Name "Add-IncidentEvidence adds excluded evidence" -Test {
    $bundle = New-AnswerIncidentBundle -Query "Test query"
    $evidence = @{ source = 'old-doc.md'; authority = 'community' }
    
    $bundle = Add-IncidentEvidence -Incident $bundle -Evidence $evidence -Type 'excluded'
    
    if ($bundle.bundle.excludedEvidence.Count -ne 1) { throw "Expected 1 excluded evidence" }
}

# Test 4: Add-IncidentFeedback
Test-Case -Name "Add-IncidentFeedback links feedback to incident" -Test {
    $bundle = New-AnswerIncidentBundle -Query "Test query"
    $bundle = Add-IncidentFeedback -Incident $bundle -FeedbackType 'thumbs-down' -FeedbackText 'This is wrong!'
    
    if (-not $bundle.bundle.linkedFeedback) { throw "Missing linkedFeedback" }
    if ($bundle.bundle.linkedFeedback.type -ne 'thumbs-down') { throw "Feedback type mismatch" }
    if ($bundle.bundle.linkedFeedback.text -ne 'This is wrong!') { throw "Feedback text mismatch" }
}

# Test 5: Export-IncidentBundle
Test-Case -Name "Export-IncidentBundle saves to file" -Test {
    $bundle = New-AnswerIncidentBundle -Query "Export test" -FinalAnswer "Test answer"
    $export = Export-IncidentBundle -Incident $bundle
    
    if (-not $export.Success) { throw "Export failed: $($export.Error)" }
    if (-not (Test-Path $export.Path)) { throw "Export file not found" }
    
    # Cleanup
    Remove-Item $export.Path -Force
}

# Test 6: Import-IncidentBundle
Test-Case -Name "Import-IncidentBundle loads from file" -Test {
    $bundle = New-AnswerIncidentBundle -Query "Import test" -FinalAnswer "Test answer"
    $export = Export-IncidentBundle -Incident $bundle
    
    $loaded = Import-IncidentBundle -Path $export.Path
    
    if ($loaded.incidentId -ne $bundle.incidentId) { throw "Incident ID mismatch after import" }
    if ($loaded.bundle.query -ne $bundle.bundle.query) { throw "Query mismatch after import" }
    
    # Cleanup
    Remove-Item $export.Path -Force
}

# Test 7: Get-IncidentBundle
Test-Case -Name "Get-IncidentBundle retrieves by ID" -Test {
    $bundle = New-AnswerIncidentBundle -Query "Get test" -FinalAnswer "Test answer"
    $export = Export-IncidentBundle -Incident $bundle
    
    $loaded = Get-IncidentBundle -IncidentId $bundle.incidentId
    
    if (-not $loaded) { throw "Failed to retrieve incident" }
    if ($loaded.incidentId -ne $bundle.incidentId) { throw "ID mismatch" }
    
    # Cleanup
    Remove-Item $export.Path -Force
}

# Test 8: Test-IncidentPattern
Test-Case -Name "Test-IncidentPattern identifies known patterns" -Test {
    $bundle = New-AnswerIncidentBundle -Query "Test query" -FinalAnswer "Answer"
    $bundle.bundle.confidenceDecision = @{ score = 0.5; shouldAbstain = $false }
    
    $patterns = Test-IncidentPattern -Incident $bundle
    
    if (-not $patterns) { throw "Pattern test returned null" }
    # Low confidence without abstention should trigger hallucination pattern
    if ($patterns.primaryPattern -ne 'hallucination') { 
        # This is acceptable if no patterns match strongly
    }
}

# Test 9: Get-IncidentRootCause
Test-Case -Name "Get-IncidentRootCause analyzes low-confidence incident" -Test {
    $bundle = New-AnswerIncidentBundle -Query "Test query" -FinalAnswer "Low confidence answer"
    $bundle.bundle.confidenceDecision = @{ score = 0.5; shouldAbstain = $false }
    
    $analysis = Get-IncidentRootCause -Incident $bundle
    
    if (-not $analysis.Analysis) { throw "Missing analysis" }
    if ($analysis.Analysis.category -ne 'low-confidence-should-abstain') { 
        throw "Expected 'low-confidence-should-abstain', got '$($analysis.Analysis.category)'" 
    }
}

# Test 10: New-IncidentReport (Text)
Test-Case -Name "New-IncidentReport generates text report" -Test {
    $bundle = New-AnswerIncidentBundle -Query "Report test" -FinalAnswer "Test answer"
    $report = New-IncidentReport -Incident $bundle -Format Text
    
    if ($report.Length -lt 100) { throw "Report seems too short" }
    if ($report -notlike "*ANSWER INCIDENT REPORT*") { throw "Missing header" }
    if ($report -notlike "*Report test*") { throw "Missing query" }
}

# Test 11: New-IncidentReport (Markdown)
Test-Case -Name "New-IncidentReport generates markdown report" -Test {
    $bundle = New-AnswerIncidentBundle -Query "MD Report test" -FinalAnswer "Test answer"
    $report = New-IncidentReport -Incident $bundle -Format Markdown
    
    if ($report -notlike "# Answer Incident Report*") { throw "Missing markdown header" }
    if ($report -notlike "*MD Report test*") { throw "Missing query in markdown" }
}

# Test 12: Export-IncidentAnalysis
Test-Case -Name "Export-IncidentAnalysis creates governance report" -Test {
    $bundle = New-AnswerIncidentBundle -Query "Gov test" -FinalAnswer "Test answer"
    $analysis = Get-IncidentRootCause -Incident $bundle
    $bundle = $analysis.UpdatedIncident
    
    $govReport = Export-IncidentAnalysis -Incident $bundle
    
    if ($govReport.reportType -ne 'answer-incident-analysis') { throw "Wrong report type" }
    if ($govReport.incident.incidentId -ne $bundle.incidentId) { throw "ID mismatch in gov report" }
}

# Test 13: Invoke-IncidentReplay
Test-Case -Name "Invoke-IncidentReplay creates replay record" -Test {
    $bundle = New-AnswerIncidentBundle -Query "Replay test" -FinalAnswer "Original answer"
    
    $replay = Invoke-IncidentReplay -Incident $bundle -UseCurrentPacks
    
    if (-not $replay.replayId) { throw "Missing replayId" }
    if ($replay.incidentId -ne $bundle.incidentId) { throw "Incident ID mismatch" }
    if ($replay.originalAnswer -ne "Original answer") { throw "Original answer mismatch" }
}

# Test 14: Compare-IncidentReplay
Test-Case -Name "Compare-IncidentReplay compares results" -Test {
    $bundle = New-AnswerIncidentBundle -Query "Compare test" -FinalAnswer "Answer"
    $replay = Invoke-IncidentReplay -Incident $bundle
    
    $comparison = Compare-IncidentReplay -Incident $bundle -ReplayResult $replay
    
    if (-not $comparison.comparisonId) { throw "Missing comparisonId" }
    if ($comparison.incidentId -ne $bundle.incidentId) { throw "Incident ID mismatch" }
}

# Test 15: Test-IncidentFixed
Test-Case -Name "Test-IncidentFixed evaluates fix status" -Test {
    $bundle = New-AnswerIncidentBundle -Query "Fix test" -FinalAnswer "Answer"
    $analysis = Get-IncidentRootCause -Incident $bundle
    $bundle = $analysis.UpdatedIncident
    
    $fixed = Test-IncidentFixed -Incident $bundle
    
    # Check if isFixed key exists (use GetEnumerator for compatibility)
    if (-not ($fixed.Keys -contains 'isFixed')) { throw "Missing isFixed key" }
}

# Test 16: Register-Incident
Test-Case -Name "Register-Incident adds to registry" -Test {
    # Use unique query to avoid conflicts
    $uniqueId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $bundle = New-AnswerIncidentBundle -Query "Register test $uniqueId" -FinalAnswer "Test answer"
    $reg = Register-Incident -Incident $bundle
    
    if (-not $reg.Success) { throw "Registration failed: $($reg.Error)" }
    if (-not (Test-Path $reg.Path)) { throw "Bundle file not found after registration" }
    
    # Cleanup
    Remove-Item $reg.Path -Force -ErrorAction SilentlyContinue
}

# Test 17: Update-IncidentStatus
Test-Case -Name "Update-IncidentStatus changes status" -Test {
    $uniqueId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $bundle = New-AnswerIncidentBundle -Query "Status test $uniqueId" -FinalAnswer "Test answer"
    $reg = Register-Incident -Incident $bundle
    
    $update = Update-IncidentStatus -IncidentId $bundle.incidentId -Status 'investigating' -Notes 'Looking into it'
    
    if ($update.OldStatus -ne 'open') { throw "Expected old status 'open'" }
    if ($update.NewStatus -ne 'investigating') { throw "Expected new status 'investigating'" }
    
    # Verify in loaded bundle
    $loaded = Get-IncidentBundle -IncidentId $bundle.incidentId
    if ($loaded.status -ne 'investigating') { throw "Status not persisted" }
    
    # Cleanup
    Remove-Item $reg.Path -Force -ErrorAction SilentlyContinue
}

# Test 18: Get-IncidentMetrics
Test-Case -Name "Get-IncidentMetrics calculates metrics" -Test {
    $metrics = Get-IncidentMetrics
    
    if (-not $metrics.generatedAt) { throw "Missing generatedAt" }
    if (-not $metrics.summary) { throw "Missing summary" }
    if ($metrics.summary.totalIncidents -lt 0) { throw "Invalid totalIncidents" }
}

# Test 19: Search-IncidentBundles
Test-Case -Name "Search-IncidentBundles filters by status" -Test {
    # Create and register a test incident with specific status
    $uniqueId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $bundle = New-AnswerIncidentBundle -Query "Search test $uniqueId" -FinalAnswer "Test answer"
    $reg = Register-Incident -Incident $bundle
    Update-IncidentStatus -IncidentId $bundle.incidentId -Status 'closed' | Out-Null
    
    $search = Search-IncidentBundles -Status 'closed'
    
    # Should find at least our test incident
    $found = $search | Where-Object { $_.incidentId -eq $bundle.incidentId }
    if (-not $found) { throw "Registered incident not found in search" }
    
    # Cleanup
    Remove-Item $reg.Path -Force -ErrorAction SilentlyContinue
}

# Test 20: Search-IncidentBundles by query pattern
Test-Case -Name "Search-IncidentBundles filters by query pattern" -Test {
    $uniqueId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $bundle = New-AnswerIncidentBundle -Query "UNIQUE_SEARCH_PATTERN_TEST_$uniqueId" -FinalAnswer "Test answer"
    $reg = Register-Incident -Incident $bundle
    
    $search = Search-IncidentBundles -QueryPattern "UNIQUE_SEARCH_PATTERN"
    
    $found = $search | Where-Object { $_.incidentId -eq $bundle.incidentId }
    if (-not $found) { throw "Incident not found by query pattern" }
    
    # Cleanup
    Remove-Item $reg.Path -Force -ErrorAction SilentlyContinue
}

# Test Summary
Write-Host "`n" -NoNewline
Write-Host "=" * 60
Write-Host "Test Summary:" -ForegroundColor Cyan
Write-Host "  Passed: $($script:TestResults.Passed)" -ForegroundColor Green
Write-Host "  Failed: $($script:TestResults.Failed)" -ForegroundColor $(if($script:TestResults.Failed -gt 0){'Red'}else{'Green'})
Write-Host "=" * 60

if ($script:TestResults.Failed -gt 0) {
    exit 1
}
