#requires -Version 5.1
<#
.SYNOPSIS
    Health Score system for LLM Workflow platform pack health monitoring.

.DESCRIPTION
    Provides health scoring, health reports, and workspace summaries for packs.
    Implements Part 1 Section 20 of the canonical architecture.

    Health Score Calculation (0-100):
    - Source registry completeness: 20 pts
    - Stale sources (> refresh cadence): -10 per source
    - Failed extractions: -15 per failure
    - Missing lockfile: -20
    - Outdated lockfile (> 30 days): -10
    - Validation errors: -5 per error

    Status Levels:
    - Healthy: >= 80
    - Degraded: 60-79
    - Critical: < 60

.NOTES
    Author: LLM Workflow Platform
    Version: 0.4.0
    Date: 2026-04-12
#>

Set-StrictMode -Version Latest

# Script-level constants for scoring
$script:ScoreWeights = @{
    SourceRegistryComplete = 20
    StaleSourcePenalty = -10
    FailedExtractionPenalty = -15
    MissingLockfilePenalty = -20
    OutdatedLockfilePenalty = -10
    ValidationErrorPenalty = -5
    MaxScore = 100
    MinScore = 0
}

$script:StatusThresholds = @{
    Healthy = 80
    Degraded = 60
}

$script:LockfileStaleDays = 30

<#
.SYNOPSIS
    Calculates health score (0-100) for a pack.

.DESCRIPTION
    Evaluates pack health based on multiple components:
    - Source registry completeness
    - Source freshness (staleness detection)
    - Extraction failure tracking
    - Lockfile presence and freshness
    - Validation error count

    Returns a score from 0-100 with detailed component breakdown.

.PARAMETER PackId
    The pack identifier to evaluate.

.PARAMETER ManifestPath
    Optional path to the pack manifest file. Defaults to packs/manifests/{PackId}.json

.PARAMETER SourceRegistryPath
    Optional path to the source registry file. Defaults to packs/registries/{PackId}.sources.json

.PARAMETER LockfilePath
    Optional path to the compatibility lockfile. Defaults to packs/locks/{PackId}.lock.json

.PARAMETER Explain
    If specified, includes detailed explanation of score calculation.

.PARAMETER RunId
    Optional run ID for provenance. Defaults to current run ID.

.OUTPUTS
    System.Collections.Hashtable containing:
    - score: The overall health score (0-100)
    - components: Detailed breakdown of each scoring component
    - deductions: List of all score deductions applied
    - rawMetrics: Raw values used in calculations

.EXAMPLE
    PS C:\> Get-PackHealthScore -PackId "rpgmaker-mz"

    Calculates health score for the rpgmaker-mz pack.

.EXAMPLE
    PS C:\> Get-PackHealthScore -PackId "rpgmaker-mz" -Explain

    Calculates health score with detailed explanation.
#>
function Get-PackHealthScore {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9-]+$')]
        [string]$PackId,

        [Parameter()]
        [string]$ManifestPath,

        [Parameter()]
        [string]$SourceRegistryPath,

        [Parameter()]
        [string]$LockfilePath,

        [Parameter()]
        [switch]$Explain,

        [Parameter()]
        [string]$RunId
    )

    begin {
        # Get or generate run ID for provenance
        if (-not $RunId) {
            try {
                $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command Get-CurrentRunId
            }
            catch {
                $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command New-RunId
            }
        }

        # Set default paths if not provided
        if (-not $ManifestPath) {
            $ManifestPath = "packs/manifests/$PackId.json"
        }
        if (-not $SourceRegistryPath) {
            $SourceRegistryPath = "packs/registries/$PackId.sources.json"
        }
        if (-not $LockfilePath) {
            $LockfilePath = "packs/locks/$PackId.lock.json"
        }

        $deductions = @()
        $explanations = @()
        $rawMetrics = @{}
        $components = @{}
    }

    process {
        $baseScore = $script:ScoreWeights.MaxScore
        $currentScore = $baseScore

        # 1. Evaluate Source Registry Completeness (20 pts)
        $registryScore = $script:ScoreWeights.SourceRegistryComplete
        $sourceRegistry = $null
        $activeSourceCount = 0
        $totalSourceCount = 0

        if (Test-Path -LiteralPath $SourceRegistryPath) {
            try {
                $sourceRegistry = Get-Content -LiteralPath $SourceRegistryPath -Raw | 
                    ConvertFrom-Json -AsHashtable
                
                if ($sourceRegistry.sources) {
                    $totalSourceCount = $sourceRegistry.sources.Count
                    $activeSourceCount = ($sourceRegistry.sources.GetEnumerator() | 
                        Where-Object { $_.Value.state -eq 'active' }).Count
                    
                    # Registry exists and has sources - full points
                    if ($totalSourceCount -gt 0) {
                        $registryScore = $script:ScoreWeights.SourceRegistryComplete
                        $explanations += "Source registry present with $totalSourceCount source(s) (+$($script:ScoreWeights.SourceRegistryComplete) pts)"
                    }
                    else {
                        $registryScore = [math]::Floor($script:ScoreWeights.SourceRegistryComplete / 2)
                        $explanations += "Source registry present but empty (+$registryScore pts)"
                    }
                }
                else {
                    $registryScore = 0
                    $deductions += "Source registry exists but contains no sources"
                    $explanations += "Source registry present but no sources defined (0 pts)"
                }
            }
            catch {
                $registryScore = 0
                $deductions += "Failed to parse source registry: $_"
                $explanations += "Source registry unreadable (0 pts)"
            }
        }
        else {
            $registryScore = 0
            $deductions += "Source registry file not found: $SourceRegistryPath"
            $explanations += "Source registry missing (0 pts)"
        }

        $components['sources'] = $registryScore
        $currentScore += $registryScore - $script:ScoreWeights.SourceRegistryComplete
        $rawMetrics['totalSources'] = $totalSourceCount
        $rawMetrics['activeSources'] = $activeSourceCount

        # 2. Check for Stale Sources (-10 per source)
        $staleSourcePenalty = 0
        $staleSourceCount = 0

        if ($sourceRegistry -and $sourceRegistry.sources) {
            $now = [DateTime]::UtcNow
            
            foreach ($sourceEntry in $sourceRegistry.sources.GetEnumerator()) {
                $source = $sourceEntry.Value
                
                # Skip non-active sources
                if ($source.state -ne 'active') { continue }

                # Parse refresh cadence (default 30 days)
                $refreshDays = 30
                if ($source.refreshCadence -match '^(\d+)-day$') {
                    $refreshDays = [int]$matches[1]
                }
                elseif ($source.refreshCadence -match '^(\d+)-week$') {
                    $refreshDays = [int]$matches[1] * 7
                }
                elseif ($source.refreshCadence -match '^(\d+)-month$') {
                    $refreshDays = [int]$matches[1] * 30
                }

                # Check last extraction or review date
                $lastDate = $null
                if ($source.lastExtractedUtc) {
                    $lastDate = [DateTime]::Parse($source.lastExtractedUtc)
                }
                elseif ($source.lastReviewedUtc) {
                    $lastDate = [DateTime]::Parse($source.lastReviewedUtc)
                }
                elseif ($source.updatedUtc) {
                    $lastDate = [DateTime]::Parse($source.updatedUtc)
                }

                if ($lastDate) {
                    $daysSinceUpdate = ($now - $lastDate).TotalDays
                    if ($daysSinceUpdate -gt $refreshDays) {
                        $staleSourceCount++
                        $staleSourcePenalty += $script:ScoreWeights.StaleSourcePenalty
                        $deductions += "Stale source '$($source.sourceId)': $([math]::Round($daysSinceUpdate)) days since update (threshold: $refreshDays days)"
                        $explanations += "Stale source '$($source.sourceId)': -$([math]::Abs($script:ScoreWeights.StaleSourcePenalty)) pts"
                    }
                }
                else {
                    # No date information - treat as potentially stale
                    $staleSourceCount++
                    $staleSourcePenalty += $script:ScoreWeights.StaleSourcePenalty
                    $deductions += "Source '$($source.sourceId)': No freshness date available"
                    $explanations += "Source '$($source.sourceId)' missing freshness data: -$([math]::Abs($script:ScoreWeights.StaleSourcePenalty)) pts"
                }
            }
        }

        $components['freshness'] = [math]::Max(0, 20 + $staleSourcePenalty)
        $currentScore += $staleSourcePenalty
        $rawMetrics['staleSources'] = $staleSourceCount

        # 3. Check for Failed Extractions (-15 per failure)
        $failedExtractionPenalty = 0
        $failedExtractionCount = 0

        if ($sourceRegistry -and $sourceRegistry.sources) {
            foreach ($sourceEntry in $sourceRegistry.sources.GetEnumerator()) {
                $source = $sourceEntry.Value
                
                # Check extraction status
                if ($source.extractionStatus -eq 'failed') {
                    $failedExtractionCount++
                    $failedExtractionPenalty += $script:ScoreWeights.FailedExtractionPenalty
                    $deductions += "Failed extraction for source '$($source.sourceId)'"
                    $explanations += "Failed extraction '$($source.sourceId)': -$([math]::Abs($script:ScoreWeights.FailedExtractionPenalty)) pts"
                }
                
                # Check extraction error count
                if ($source.extractionErrors -and $source.extractionErrors -gt 0) {
                    $failedExtractionCount += $source.extractionErrors
                    $penalty = $source.extractionErrors * $script:ScoreWeights.FailedExtractionPenalty
                    $failedExtractionPenalty += $penalty
                    $deductions += "Source '$($source.sourceId)' has $($source.extractionErrors) extraction error(s)"
                    $explanations += "Extraction errors on '$($source.sourceId)': -$([math]::Abs($penalty)) pts"
                }
            }
        }

        $components['extraction'] = [math]::Max(0, 20 + $failedExtractionPenalty)
        $currentScore += $failedExtractionPenalty
        $rawMetrics['failedExtractions'] = $failedExtractionCount

        # 4. Check Lockfile Status
        $lockfileScore = 0
        $lockfileStatus = 'missing'

        if (Test-Path -LiteralPath $LockfilePath) {
            try {
                $lockfile = Get-Content -LiteralPath $LockfilePath -Raw | 
                    ConvertFrom-Json -AsHashtable
                
                $lockfileStatus = 'present'
                
                # Check lockfile age
                $lockfileAge = $null
                if ($lockfile.generatedUtc) {
                    $lockfileDate = [DateTime]::Parse($lockfile.generatedUtc)
                    $lockfileAge = ([DateTime]::UtcNow - $lockfileDate).TotalDays
                    
                    if ($lockfileAge -gt $script:LockfileStaleDays) {
                        $lockfileStatus = 'outdated'
                        $lockfileScore = -[math]::Abs($script:ScoreWeights.OutdatedLockfilePenalty)
                        $deductions += "Lockfile is outdated ($([math]::Round($lockfileAge)) days old, max $script:LockfileStaleDays)"
                        $explanations += "Lockfile outdated: -$([math]::Abs($script:ScoreWeights.OutdatedLockfilePenalty)) pts"
                    }
                    else {
                        $lockfileScore = 20
                        $explanations += "Lockfile present and current (+20 pts)"
                    }
                }
                else {
                    $lockfileScore = 10
                    $explanations += "Lockfile present but no timestamp (+10 pts)"
                }
                
                $rawMetrics['lockfileAgeDays'] = $lockfileAge
            }
            catch {
                $lockfileStatus = 'invalid'
                $lockfileScore = -[math]::Abs($script:ScoreWeights.MissingLockfilePenalty)
                $deductions += "Lockfile exists but is invalid: $_"
                $explanations += "Lockfile unreadable: -$([math]::Abs($script:ScoreWeights.MissingLockfilePenalty)) pts"
            }
        }
        else {
            $lockfileScore = -[math]::Abs($script:ScoreWeights.MissingLockfilePenalty)
            $deductions += "Lockfile not found: $LockfilePath"
            $explanations += "Lockfile missing: -$([math]::Abs($script:ScoreWeights.MissingLockfilePenalty)) pts"
        }

        $components['lockfile'] = [math]::Max(0, 20 + $lockfileScore)
        $currentScore += $lockfileScore - 20  # Adjust because lockfileScore already includes penalty
        $rawMetrics['lockfileStatus'] = $lockfileStatus

        # 5. Check Validation Errors (-5 per error)
        $validationPenalty = 0
        $validationErrorCount = 0

        # Validate manifest if available
        if (Test-Path -LiteralPath $ManifestPath) {
            try {
                $manifest = Get-Content -LiteralPath $ManifestPath -Raw | 
                    ConvertFrom-Json -AsHashtable
                
                # Use Test-PackManifest if available
                $testCmd = Get-Command Test-PackManifest -ErrorAction SilentlyContinue
                if ($testCmd -and $manifest) {
                    $validationResult = & $testCmd -Manifest $manifest
                    if (-not $validationResult.isValid) {
                        $validationErrorCount = $validationResult.errors.Count
                        $validationPenalty = $validationErrorCount * $script:ScoreWeights.ValidationErrorPenalty
                        foreach ($error in $validationResult.errors) {
                            $deductions += "Validation error: $error"
                            $explanations += "Validation: $error (-$([math]::Abs($script:ScoreWeights.ValidationErrorPenalty)) pts)"
                        }
                    }
                    else {
                        $explanations += "Manifest validation passed (+20 pts)"
                    }
                }
                else {
                    # Basic validation
                    $basicErrors = @()
                    if (-not $manifest.packId) { $basicErrors += "Missing packId" }
                    if (-not $manifest.domain) { $basicErrors += "Missing domain" }
                    if (-not $manifest.version) { $basicErrors += "Missing version" }
                    
                    if ($basicErrors.Count -gt 0) {
                        $validationErrorCount = $basicErrors.Count
                        $validationPenalty = $validationErrorCount * $script:ScoreWeights.ValidationErrorPenalty
                        foreach ($error in $basicErrors) {
                            $deductions += "Manifest error: $error"
                            $explanations += "Manifest: $error (-$([math]::Abs($script:ScoreWeights.ValidationErrorPenalty)) pts)"
                        }
                    }
                    else {
                        $explanations += "Basic manifest validation passed (+20 pts)"
                    }
                }
            }
            catch {
                $validationErrorCount = 1
                $validationPenalty = $script:ScoreWeights.ValidationErrorPenalty
                $deductions += "Failed to parse manifest: $_"
                $explanations += "Manifest unreadable: -$([math]::Abs($script:ScoreWeights.ValidationErrorPenalty)) pts"
            }
        }
        else {
            $validationErrorCount = 1
            $validationPenalty = $script:ScoreWeights.ValidationErrorPenalty
            $deductions += "Manifest file not found: $ManifestPath"
            $explanations += "Manifest missing: -$([math]::Abs($script:ScoreWeights.ValidationErrorPenalty)) pts"
        }

        $components['validation'] = [math]::Max(0, 20 + $validationPenalty)
        $currentScore += $validationPenalty
        $rawMetrics['validationErrors'] = $validationErrorCount

        # Calculate final score within bounds
        $finalScore = [math]::Max($script:ScoreWeights.MinScore, 
            [math]::Min($script:ScoreWeights.MaxScore, $currentScore))

        # Build result
        $result = @{
            packId = $PackId
            score = $finalScore
            runId = $RunId
            generatedUtc = [DateTime]::UtcNow.ToString("o")
            components = $components
            deductions = $deductions
            rawMetrics = $rawMetrics
        }

        if ($Explain) {
            $result['explanation'] = @{
                baseScore = $baseScore
                calculations = $explanations
                finalScore = $finalScore
            }
        }

        # Log health score calculation
        try {
            $logCmd = Get-Command New-LogEntry -ErrorAction SilentlyContinue
            if ($logCmd) {
                $logEntry = & $logCmd -Level 'INFO' -Message "Health score calculated for $PackId`: $finalScore" `
                    -RunId $RunId -Source 'Get-PackHealthScore' `
                    -Metadata @{packId = $PackId; score = $finalScore; deductions = $deductions.Count}
                
                $writeCmd = Get-Command Write-StructuredLog -ErrorAction SilentlyContinue
                if ($writeCmd) {
                    & $writeCmd -Entry $logEntry
                }
            }
        }
        catch {
            Write-Verbose "[HealthScore] Failed to write log entry: $_"
        }

        return $result
    }
}

<#
.SYNOPSIS
    Returns detailed health report for a pack.

.DESCRIPTION
    Generates a comprehensive health report including:
    - Overall health score
    - Component-level scores
    - Warnings array
    - Critical issues array
    - Recommended actions

.PARAMETER PackId
    The pack identifier to evaluate.

.PARAMETER ManifestPath
    Optional path to the pack manifest file.

.PARAMETER SourceRegistryPath
    Optional path to the source registry file.

.PARAMETER LockfilePath
    Optional path to the compatibility lockfile.

.PARAMETER RunId
    Optional run ID for provenance.

.OUTPUTS
    System.Collections.Hashtable containing detailed health report.

.EXAMPLE
    PS C:\> Test-PackHealth -PackId "rpgmaker-mz"

    Generates a detailed health report for the pack.
#>
function Test-PackHealth {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9-]+$')]
        [string]$PackId,

        [Parameter()]
        [string]$ManifestPath,

        [Parameter()]
        [string]$SourceRegistryPath,

        [Parameter()]
        [string]$LockfilePath,

        [Parameter()]
        [string]$RunId
    )

    begin {
        # Get run ID
        if (-not $RunId) {
            try {
                $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command Get-CurrentRunId
            }
            catch {
                $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command New-RunId
            }
        }

        $warnings = @()
        $criticalIssues = @()
        $recommendedActions = @()
    }

    process {
        # Get base health score
        $scoreResult = Get-PackHealthScore -PackId $PackId `
            -ManifestPath $ManifestPath `
            -SourceRegistryPath $SourceRegistryPath `
            -LockfilePath $LockfilePath `
            -RunId $RunId

        $score = $scoreResult.score

        # Determine status based on thresholds
        $status = 'Critical'
        $severity = 'Critical'
        if ($score -ge $script:StatusThresholds.Healthy) {
            $status = 'Healthy'
            $severity = 'OK'
        }
        elseif ($score -ge $script:StatusThresholds.Degraded) {
            $status = 'Degraded'
            $severity = 'Warning'
        }

        # Categorize deductions into warnings and critical issues
        foreach ($deduction in $scoreResult.deductions) {
            if ($deduction -match 'missing|not found|failed|invalid|unreadable') {
                $criticalIssues += $deduction
            }
            else {
                $warnings += $deduction
            }
        }

        # Generate recommended actions based on issues
        if ($scoreResult.rawMetrics.lockfileStatus -eq 'missing') {
            $recommendedActions += "Create compatibility lockfile using New-PackLockfile"
        }
        elseif ($scoreResult.rawMetrics.lockfileStatus -eq 'outdated') {
            $recommendedActions += "Refresh compatibility lockfile (stale for $([math]::Round($scoreResult.rawMetrics.lockfileAgeDays)) days)"
        }

        if ($scoreResult.rawMetrics.staleSources -gt 0) {
            $recommendedActions += "Refresh $($scoreResult.rawMetrics.staleSources) stale source(s)"
        }

        if ($scoreResult.rawMetrics.failedExtractions -gt 0) {
            $recommendedActions += "Investigate $($scoreResult.rawMetrics.failedExtractions) extraction failure(s)"
        }

        if ($scoreResult.rawMetrics.validationErrors -gt 0) {
            $recommendedActions += "Fix $($scoreResult.rawMetrics.validationErrors) validation error(s) in manifest"
        }

        if ($scoreResult.rawMetrics.totalSources -eq 0) {
            $recommendedActions += "Add sources to the pack registry"
        }

        # Build comprehensive report
        $report = @{
            schemaVersion = 1
            packId = $PackId
            runId = $RunId
            generatedUtc = [DateTime]::UtcNow.ToString("o")
            overallScore = $score
            status = $status
            severity = $severity
            components = $scoreResult.components
            rawMetrics = $scoreResult.rawMetrics
            warnings = $warnings
            criticalIssues = $criticalIssues
            recommendedActions = $recommendedActions
        }

        # Add status indicator (5-level severity)
        $report['statusIndicator'] = switch ($severity) {
            'OK' { 'OK' }
            'Notice' { 'Notice' }
            'Warning' { 'Warning' }
            'Critical' { 'Critical' }
            default { 'Critical' }
        }

        # Log health test result
        try {
            $logCmd = Get-Command New-LogEntry -ErrorAction SilentlyContinue
            if ($logCmd) {
                $logLevel = if ($severity -eq 'Critical') { 'ERROR' } elseif ($severity -eq 'Warning') { 'WARN' } else { 'INFO' }
                $logEntry = & $logCmd -Level $logLevel -Message "Health test for $PackId`: $status ($score)" `
                    -RunId $RunId -Source 'Test-PackHealth' `
                    -Metadata @{ 
                        packId = $PackId
                        status = $status
                        score = $score
                        warnings = $warnings.Count
                        criticalIssues = $criticalIssues.Count
                    }
                
                $writeCmd = Get-Command Write-StructuredLog -ErrorAction SilentlyContinue
                if ($writeCmd) {
                    & $writeCmd -Entry $logEntry
                }
            }
        }
        catch {
            Write-Verbose "[HealthScore] Failed to write log entry: $_"
        }

        return $report
    }
}

<#
.SYNOPSIS
    Generates a concise health summary for the entire workspace.

.DESCRIPTION
    Provides a quick overview of workspace health including:
    - Active packs count
    - Average health score
    - Critical issues count
    - Last sync status
    - Quick status indicator (Healthy/Degraded/Critical)

.PARAMETER PackIds
    Optional array of pack IDs to include. If not specified, scans for all packs.

.PARAMETER IncludeDetails
    If specified, includes per-pack health summaries.

.PARAMETER RunId
    Optional run ID for provenance.

.OUTPUTS
    System.Collections.Hashtable containing workspace health summary.

.EXAMPLE
    PS C:\> Get-WorkspaceHealthSummary

    Gets a concise health summary for the workspace.

.EXAMPLE
    PS C:\> Get-WorkspaceHealthSummary -IncludeDetails

    Gets summary with per-pack details.
#>
function Get-WorkspaceHealthSummary {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string[]]$PackIds,

        [Parameter()]
        [switch]$IncludeDetails,

        [Parameter()]
        [string]$RunId
    )

    begin {
        # Get run ID
        if (-not $RunId) {
            try {
                $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command Get-CurrentRunId
            }
            catch {
                $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command New-RunId
            }
        }

        $packHealthReports = @()
        $totalScore = 0
        $criticalIssueCount = 0
    }

    process {
        # Discover packs if not specified
        if (-not $PackIds) {
            $manifestDir = "packs/manifests"
            if (Test-Path -LiteralPath $manifestDir) {
                $PackIds = Get-ChildItem -Path $manifestDir -Filter "*.json" | 
                    ForEach-Object { 
                        $content = Get-Content $_.FullName -Raw | ConvertFrom-Json
                        $content.packId
                    } | Where-Object { $_ }
            }
            
            if (-not $PackIds) {
                $PackIds = @()
            }
        }

        # Evaluate each pack
        foreach ($packId in $PackIds) {
            try {
                $healthReport = Test-PackHealth -PackId $packId -RunId $RunId
                $packHealthReports += $healthReport
                $totalScore += $healthReport.overallScore
                $criticalIssueCount += $healthReport.criticalIssues.Count
            }
            catch {
                Write-Warning "[HealthScore] Failed to evaluate pack '$packId': $_"
                # Add placeholder for failed pack
                $packHealthReports += @{
                    packId = $packId
                    overallScore = 0
                    status = 'Critical'
                    severity = 'Critical'
                    error = $_.ToString()
                }
                $criticalIssueCount++
            }
        }

        # Calculate summary statistics
        $activePacks = $PackIds.Count
        $averageScore = if ($activePacks -gt 0) { [math]::Round($totalScore / $activePacks) } else { 0 }

        # Determine overall status
        $overallStatus = 'Critical'
        if ($averageScore -ge $script:StatusThresholds.Healthy -and $criticalIssueCount -eq 0) {
            $overallStatus = 'Healthy'
        }
        elseif ($averageScore -ge $script:StatusThresholds.Degraded) {
            $overallStatus = 'Degraded'
        }

        # Determine last sync status from packs
        $lastSyncStatus = 'Unknown'
        $lastSyncTime = $null
        
        # Check for state file or journal
        $stateFilePath = ".llm-workflow/state/last-sync.json"
        if (Test-Path -LiteralPath $stateFilePath) {
            try {
                $syncState = Get-Content -LiteralPath $stateFilePath -Raw | ConvertFrom-Json
                $lastSyncStatus = $syncState.status
                $lastSyncTime = $syncState.timestamp
            }
            catch {
                $lastSyncStatus = 'Unknown'
            }
        }

        # Build summary
        $summary = @{
            schemaVersion = 1
            runId = $RunId
            generatedUtc = [DateTime]::UtcNow.ToString("o")
            activePacks = $activePacks
            averageHealthScore = $averageScore
            criticalIssuesCount = $criticalIssueCount
            lastSyncStatus = $lastSyncStatus
            lastSyncTime = $lastSyncTime
            overallStatus = $overallStatus
        }

        # Add status breakdown
        $statusCounts = @{
            Healthy = ($packHealthReports | Where-Object { $_.status -eq 'Healthy' }).Count
            Degraded = ($packHealthReports | Where-Object { $_.status -eq 'Degraded' }).Count
            Critical = ($packHealthReports | Where-Object { $_.status -eq 'Critical' }).Count
        }
        $summary['statusBreakdown'] = $statusCounts

        # Add pack summaries if requested
        if ($IncludeDetails) {
            $summary['packs'] = $packHealthReports | ForEach-Object {
                @{
                    packId = $_.packId
                    score = $_.overallScore
                    status = $_.status
                    warnings = $_.warnings.Count
                    criticalIssues = $_.criticalIssues.Count
                }
            }
        }

        # Log summary
        try {
            $logCmd = Get-Command New-LogEntry -ErrorAction SilentlyContinue
            if ($logCmd) {
                $logEntry = & $logCmd -Level 'INFO' -Message "Workspace health summary: $overallStatus (avg: $averageScore)" `
                    -RunId $RunId -Source 'Get-WorkspaceHealthSummary' `
                    -Metadata @{
                        overallStatus = $overallStatus
                        averageScore = $averageScore
                        activePacks = $activePacks
                        criticalIssues = $criticalIssueCount
                    }
                
                $writeCmd = Get-Command Write-StructuredLog -ErrorAction SilentlyContinue
                if ($writeCmd) {
                    & $writeCmd -Entry $logEntry
                }
            }
        }
        catch {
            Write-Verbose "[HealthScore] Failed to write log entry: $_"
        }

        return $summary
    }
}

<#
.SYNOPSIS
    Generates a JSON health report with trending information.

.DESCRIPTION
    Exports a comprehensive health report including:
    - Timestamp and run ID
    - All pack scores
    - Trending information (improving/stable/degrading)
    - Historical comparison if available

.PARAMETER OutputPath
    The path to write the JSON report. Defaults to .llm-workflow/reports/health-report-{timestamp}.json

.PARAMETER PackIds
    Optional array of pack IDs to include. If not specified, scans for all packs.

.PARAMETER CompareWithPrevious
    If specified, compares with previous report to determine trending.

.PARAMETER RunId
    Optional run ID for provenance.

.OUTPUTS
    System.String. The path to the generated report file.

.EXAMPLE
    PS C:\> Export-HealthReport -OutputPath "reports/health.json"

    Exports health report to the specified path.

.EXAMPLE
    PS C:\> Export-HealthReport -CompareWithPrevious

    Exports report with trending comparison.
#>
function Export-HealthReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [string[]]$PackIds,

        [Parameter()]
        [switch]$CompareWithPrevious,

        [Parameter()]
        [string]$RunId
    )

    begin {
        # Get run ID
        if (-not $RunId) {
            try {
                $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command Get-CurrentRunId
            }
            catch {
                $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command New-RunId
            }
        }

        $timestamp = [DateTime]::UtcNow
        $timestampStr = $timestamp.ToString("yyyyMMddTHHmmssZ")

        # Set default output path
        if (-not $OutputPath) {
            $reportDir = ".llm-workflow/reports"
            if (-not (Test-Path -LiteralPath $reportDir)) {
                New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
            }
            $OutputPath = "$reportDir/health-report-$timestampStr.json"
        }

        # Ensure output directory exists
        $outputDir = Split-Path -Parent $OutputPath
        if (-not (Test-Path -LiteralPath $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
    }

    process {
        # Get workspace summary with details
        $workspaceSummary = Get-WorkspaceHealthSummary -PackIds $PackIds `
            -IncludeDetails -RunId $RunId

        # Get detailed health reports for all packs
        $packReports = @()
        $packIdsToProcess = if ($PackIds) { $PackIds } else { 
            $workspaceSummary.packs | ForEach-Object { $_.packId }
        }

        foreach ($packId in $packIdsToProcess) {
            try {
                $healthReport = Test-PackHealth -PackId $packId -RunId $RunId
                $packReports += @{
                    packId = $healthReport.packId
                    score = $healthReport.overallScore
                    status = $healthReport.status
                    severity = $healthReport.severity
                    components = $healthReport.components
                    warnings = $healthReport.warnings
                    criticalIssues = $healthReport.criticalIssues
                    recommendedActions = $healthReport.recommendedActions
                    rawMetrics = $healthReport.rawMetrics
                }
            }
            catch {
                Write-Warning "[HealthScore] Failed to get health report for '$packId': $_"
            }
        }

        # Determine trending
        $trending = 'stable'
        $previousReport = $null
        $scoreChange = 0

        if ($CompareWithPrevious) {
            # Find previous report
            $reportDir = Split-Path -Parent $OutputPath
            if (Test-Path -LiteralPath $reportDir) {
                $previousReports = Get-ChildItem -Path $reportDir -Filter "health-report-*.json" | 
                    Sort-Object LastWriteTime -Descending | 
                    Select-Object -Skip 1 -First 1

                if ($previousReports) {
                    try {
                        $previousReport = Get-Content -LiteralPath $previousReports.FullName -Raw | 
                            ConvertFrom-Json -AsHashtable

                        if ($previousReport -and $previousReport.overallScore) {
                            $previousScore = $previousReport.overallScore
                            $currentScore = $workspaceSummary.averageHealthScore
                            $scoreChange = $currentScore - $previousScore

                            if ($scoreChange -gt 5) {
                                $trending = 'improving'
                            }
                            elseif ($scoreChange -lt -5) {
                                $trending = 'degrading'
                            }
                            else {
                                $trending = 'stable'
                            }
                        }
                    }
                    catch {
                        Write-Verbose "[HealthScore] Failed to load previous report: $_"
                    }
                }
            }
        }

        # Build comprehensive report
        $report = @{
            schemaVersion = 1
            runId = $RunId
            generatedUtc = $timestamp.ToString("o")
            timestamp = $timestampStr
            overallScore = $workspaceSummary.averageHealthScore
            status = $workspaceSummary.overallStatus
            trending = $trending
            activePacks = $workspaceSummary.activePacks
            criticalIssuesCount = $workspaceSummary.criticalIssuesCount
            lastSyncStatus = $workspaceSummary.lastSyncStatus
            statusBreakdown = $workspaceSummary.statusBreakdown
            packs = $packReports
        }

        # Add trending details if comparison was made
        if ($CompareWithPrevious -and $previousReport) {
            $report['trendingDetails'] = @{
                direction = $trending
                scoreChange = $scoreChange
                previousScore = $previousReport.overallScore
                previousRunId = $previousReport.runId
                previousTimestamp = $previousReport.generatedUtc
            }
        }

        # Add provenance
        $report['provenance'] = @{
            generatedBy = 'Export-HealthReport'
            version = '0.4.0'
            runId = $RunId
            timestamp = $timestamp.ToString("o")
        }

        # Write report to file
        $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8

        Write-Verbose "[HealthScore] Health report exported to: $OutputPath"

        # Log export
        try {
            $logCmd = Get-Command New-LogEntry -ErrorAction SilentlyContinue
            if ($logCmd) {
                $logEntry = & $logCmd -Level 'INFO' -Message "Health report exported to $OutputPath" `
                    -RunId $RunId -Source 'Export-HealthReport' `
                    -Metadata @{
                        outputPath = $OutputPath
                        overallScore = $workspaceSummary.averageHealthScore
                        trending = $trending
                        packCount = $packReports.Count
                    }
                
                $writeCmd = Get-Command Write-StructuredLog -ErrorAction SilentlyContinue
                if ($writeCmd) {
                    & $writeCmd -Entry $logEntry
                }
            }
        }
        catch {
            Write-Verbose "[HealthScore] Failed to write log entry: $_"
        }

        return $OutputPath
    }
}

<#
.SYNOPSIS
    Gets the status indicator for a given health score.

.DESCRIPTION
    Helper function to convert a numeric health score to a 5-level
    severity indicator.

.PARAMETER Score
    The health score (0-100).

.OUTPUTS
    System.String. One of: Critical, Warning, Notice, Info, OK

.EXAMPLE
    PS C:\> Get-HealthStatusIndicator -Score 85
    OK
#>
function Get-HealthStatusIndicator {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 100)]
        [int]$Score
    )

    process {
        if ($Score -ge 90) { return 'OK' }
        if ($Score -ge 80) { return 'Info' }
        if ($Score -ge 60) { return 'Notice' }
        if ($Score -ge 40) { return 'Warning' }
        return 'Critical'
    }
}

<#
.SYNOPSIS
    Compares two health scores and determines trending direction.

.DESCRIPTION
    Helper function to compare current score with previous score
    and determine if health is improving, stable, or degrading.

.PARAMETER CurrentScore
    The current health score.

.PARAMETER PreviousScore
    The previous health score for comparison.

.PARAMETER Threshold
    The minimum difference to consider a trend. Default is 5.

.OUTPUTS
    System.String. One of: improving, stable, degrading

.EXAMPLE
    PS C:\> Get-HealthTrend -CurrentScore 85 -PreviousScore 75
    improving
#>
function Get-HealthTrend {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 100)]
        [int]$CurrentScore,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 100)]
        [int]$PreviousScore,

        [Parameter()]
        [int]$Threshold = 5
    )

    process {
        $difference = $CurrentScore - $PreviousScore

        if ($difference -gt $Threshold) { return 'improving' }
        if ($difference -lt -$Threshold) { return 'degrading' }
        return 'stable'
    }
}

# Export-ModuleMember handled by LLMWorkflow.psm1
