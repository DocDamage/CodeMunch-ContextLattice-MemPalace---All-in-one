#requires -Version 5.1
<#
.SYNOPSIS
    Answer Incident Bundle system for LLM Workflow platform.

.DESCRIPTION
    Provides reproducible bad-answer investigations through incident bundles.
    Implements Section 15.6 of the canonical architecture for tracking,
    analyzing, and replaying answer quality incidents.

    Key capabilities:
    - Create and manage incident bundles with full context
    - Add evidence and feedback to incidents
    - Export/import bundles for investigation and replay
    - Root cause analysis with predefined categories
    - Incident replay for regression testing
    - Metrics and SLO tracking

.NOTES
    File Name      : IncidentBundle.ps1
    Author         : LLM Workflow Team
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT

.EXAMPLE
    # Create a new incident bundle
    $bundle = New-AnswerIncidentBundle -Query "How do I use X?" -WorkspaceContext $ctx

.EXAMPLE
    # Register and analyze an incident
    Register-Incident -Incident $bundle
    $analysis = Get-IncidentRootCause -IncidentId $bundle.incidentId

.EXAMPLE
    # Replay and verify fix
    $replay = Invoke-IncidentReplay -IncidentId $bundle.incidentId
    $fixed = Test-IncidentFixed -IncidentId $bundle.incidentId -ReplayResult $replay
#>

Set-StrictMode -Version Latest

# Script-level constants
$script:IncidentSchemaVersion = 1
$script:IncidentSchemaName = "answer-incident-bundle"
$script:DefaultIncidentsDirectory = ".llm-workflow/reports/incidents"
$script:IncidentRegistryFile = ".llm-workflow/state/incident-registry.json"

# Root cause categories per Section 15.6
$script:RootCauseCategories = @(
    'bad-retrieval',
    'wrong-authority-level',
    'contradiction-not-surfaced',
    'low-confidence-should-abstain',
    'missing-source',
    'extraction-bug',
    'ranking-bug',
    'privacy-boundary-issue'
)

# Incident severity levels
$script:SeverityLevels = @('low', 'medium', 'high', 'critical')

# Incident status values
$script:IncidentStatuses = @('open', 'investigating', 'resolved', 'closed')

# Pattern definitions for incident classification
$script:KnownPatterns = @{
    'hallucination' = @{
        description = 'Answer contains fabricated information not in evidence'
        indicators = @('no_evidence_match', 'confident_but_unsourced')
    }
    'outdated-information' = @{
        description = 'Answer relies on deprecated or outdated sources'
        indicators = @('old_pack_version', 'deprecated_api_usage')
    }
    'contradiction-ignored' = @{
        description = 'Contradictory evidence was not surfaced'
        indicators = @('conflicting_sources', 'ignored_dispute_markers')
    }
    'wrong-authority' = @{
        description = 'Used low-authority evidence for authoritative answer'
        indicators = @('translation_used_as_primary', 'community_over_official')
    }
    'incomplete-retrieval' = @{
        description = 'Relevant evidence was not retrieved'
        indicators = @('missing_key_source', 'false_negative_ranking')
    }
    'privacy-leak' = @{
        description = 'Sensitive information was included in answer'
        indicators = @('pii_exposed', 'credential_mentioned')
    }
}
<#
.SYNOPSIS
    Gets the default incidents directory path.

.DESCRIPTION
    Returns the canonical incidents directory path. Creates it if it doesn't exist.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    System.String. The full path to the incidents directory.
#>
function Get-IncidentsDirectory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ProjectRoot = "."
    )

    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) {
        $resolvedRoot = $ProjectRoot
    }

    $incidentsDir = Join-Path $resolvedRoot $script:DefaultIncidentsDirectory
    
    if (-not (Test-Path -LiteralPath $incidentsDir)) {
        try {
            New-Item -ItemType Directory -Path $incidentsDir -Force | Out-Null
        }
        catch {
            throw "Failed to create incidents directory: $incidentsDir. Error: $_"
        }
    }

    return $incidentsDir
}

<#
.SYNOPSIS
    Creates a new Answer Incident Bundle.

.DESCRIPTION
    Creates a comprehensive incident bundle containing all context needed
    for reproducible bad-answer investigations per Section 15.6.

.PARAMETER Query
    The user query that triggered the incident.

.PARAMETER WorkspaceContext
    The workspace context at the time of the incident.

.PARAMETER RetrievalProfile
    The retrieval profile used.

.PARAMETER AnswerPlan
    The answer plan that was generated.

.PARAMETER AnswerTrace
    The answer trace for explainability.

.PARAMETER PackVersions
    Dictionary of pack versions at the time of the incident.

.PARAMETER SelectedEvidence
    Array of evidence that was selected for the answer.

.PARAMETER ExcludedEvidence
    Array of evidence that was excluded from the answer.

.PARAMETER ConfidenceDecision
    The confidence decision object.

.PARAMETER FinalAnswer
    The final answer text that was provided.

.PARAMETER RunId
    Optional run ID for provenance.

.OUTPUTS
    System.Collections.Hashtable. The complete incident bundle object.

.EXAMPLE
    $bundle = New-AnswerIncidentBundle -Query "How do I use X?" `
        -WorkspaceContext $ctx -RetrievalProfile "default" `
        -AnswerPlan $plan -AnswerTrace $trace
#>
function New-AnswerIncidentBundle {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter()]
        [hashtable]$WorkspaceContext = @{},

        [Parameter()]
        [string]$RetrievalProfile = "default",

        [Parameter()]
        [hashtable]$AnswerPlan = @{},

        [Parameter()]
        [hashtable]$AnswerTrace = @{},

        [Parameter()]
        [hashtable]$PackVersions = @{},

        [Parameter()]
        [array]$SelectedEvidence = @(),

        [Parameter()]
        [array]$ExcludedEvidence = @(),

        [Parameter()]
        [hashtable]$ConfidenceDecision = @{},

        [Parameter()]
        [string]$FinalAnswer = "",

        [Parameter()]
        [string]$RunId = ""
    )

    # Generate incident ID
    $incidentId = [Guid]::NewGuid().ToString('N')
    
    # Get current timestamp
    $createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ", 
        [System.Globalization.CultureInfo]::InvariantCulture)

    # Get run ID if not provided
    if ([string]::IsNullOrEmpty($RunId)) {
        try {
            $runIdCmd = Get-Command Get-CurrentRunId -ErrorAction SilentlyContinue
            if ($runIdCmd) {
                $RunId = & $runIdCmd -ErrorAction SilentlyContinue
            }
        }
        catch {
            $RunId = "unknown"
        }
        if ([string]::IsNullOrEmpty($RunId)) {
            $RunId = "unknown"
        }
    }

    # Build pack versions if not provided
    if ($PackVersions.Count -eq 0) {
        $PackVersions = Get-CurrentPackVersions
    }

    # Create the bundle
    $bundle = [ordered]@{
        incidentId = $incidentId
        createdAt = $createdAt
        status = "open"
        runId = $RunId
        schemaVersion = $script:IncidentSchemaVersion
        bundle = [ordered]@{
            query = $Query
            workspaceContext = $WorkspaceContext
            retrievalProfile = $RetrievalProfile
            answerPlan = $AnswerPlan
            answerTrace = $AnswerTrace
            packVersions = $PackVersions
            selectedEvidence = $SelectedEvidence
            excludedEvidence = $ExcludedEvidence
            confidenceDecision = $ConfidenceDecision
            finalAnswer = $FinalAnswer
            linkedFeedback = $null
        }
        analysis = [ordered]@{
            rootCause = $null
            category = $null
            severity = $null
            pattern = $null
            notes = @()
            analyzedAt = $null
            analyzedBy = $null
        }
        replay = [ordered]@{
            replayHistory = @()
            lastReplayAt = $null
            fixed = $false
        }
        metadata = [ordered]@{
            createdBy = [Environment]::UserName
            host = [Environment]::MachineName.ToLowerInvariant()
            pid = $PID
        }
    }

    Write-Verbose "[IncidentBundle] Created incident bundle: $incidentId"
    
    return $bundle
}

<#
.SYNOPSIS
    Adds evidence to an incident bundle.

.DESCRIPTION
    Adds new evidence (selected or excluded) to an existing incident bundle.

.PARAMETER Incident
    The incident bundle to modify.

.PARAMETER Evidence
    The evidence to add.

.PARAMETER Type
    Whether the evidence was 'selected' or 'excluded'.

.OUTPUTS
    System.Collections.Hashtable. The modified incident bundle.
#>
function Add-IncidentEvidence {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Incident,

        [Parameter(Mandatory = $true)]
        [hashtable]$Evidence,

        [Parameter(Mandatory = $true)]
        [ValidateSet('selected', 'excluded')]
        [string]$Type
    )

    if (-not $Evidence.ContainsKey('evidenceId')) {
        $Evidence['evidenceId'] = [Guid]::NewGuid().ToString('N')
    }

    if (-not $Evidence.ContainsKey('addedAt')) {
        $Evidence['addedAt'] = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }

    if ($Type -eq 'selected') {
        if (-not $Incident.bundle.selectedEvidence) {
            $Incident.bundle.selectedEvidence = @()
        }
        $Incident.bundle.selectedEvidence += $Evidence
    }
    else {
        if (-not $Incident.bundle.excludedEvidence) {
            $Incident.bundle.excludedEvidence = @()
        }
        $Incident.bundle.excludedEvidence += $Evidence
    }

    Write-Verbose "[IncidentBundle] Added $Type evidence to incident: $($Incident.incidentId)"
    
    return $Incident
}

<#
.SYNOPSIS
    Links feedback to an incident bundle.

.DESCRIPTION
    Associates user feedback with an incident bundle for investigation.

.PARAMETER Incident
    The incident bundle to modify.

.PARAMETER Feedback
    The feedback object to link.

.PARAMETER FeedbackType
    Type of feedback: thumbs-down, correction, report, etc.

.PARAMETER FeedbackText
    Optional text feedback from user.

.PARAMETER ReportedBy
    Who reported the issue.

.OUTPUTS
    System.Collections.Hashtable. The modified incident bundle.
#>
function Add-IncidentFeedback {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Incident,

        [Parameter()]
        [hashtable]$Feedback = @{},

        [Parameter()]
        [string]$FeedbackType = "report",

        [Parameter()]
        [string]$FeedbackText = "",

        [Parameter()]
        [string]$ReportedBy = ""
    )

    $linkedFeedback = [ordered]@{
        feedbackId = [Guid]::NewGuid().ToString('N')
        type = $FeedbackType
        text = $FeedbackText
        reportedBy = if ($ReportedBy) { $ReportedBy } else { [Environment]::UserName }
        reportedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        data = $Feedback
    }

    $Incident.bundle.linkedFeedback = $linkedFeedback

    Write-Verbose "[IncidentBundle] Added feedback to incident: $($Incident.incidentId)"
    
    return $Incident
}

<#
.SYNOPSIS
    Exports an incident bundle to JSON file.

.DESCRIPTION
    Exports a complete incident bundle to a JSON file for storage,
    sharing, or governance review. Uses atomic writes for safety.

.PARAMETER Incident
    The incident bundle to export.

.PARAMETER OutputPath
    Optional output path. Defaults to incidents directory.

.PARAMETER Compress
    If specified, outputs compressed JSON.

.OUTPUTS
    System.Collections.Hashtable. Export result with Success, Path, IncidentId.

.EXAMPLE
    Export-IncidentBundle -Incident $bundle
    Export-IncidentBundle -Incident $bundle -OutputPath "./my-incident.json"
#>
function Export-IncidentBundle {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Incident,

        [Parameter()]
        [string]$OutputPath = "",

        [switch]$Compress
    )

    # Determine output path
    if ([string]::IsNullOrEmpty($OutputPath)) {
        $incidentsDir = Get-IncidentsDirectory
        $fileName = "$($Incident.incidentId).json"
        $OutputPath = Join-Path $incidentsDir $fileName
    }

    # Ensure directory exists
    $dir = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    try {
        # Convert to JSON
        $json = $Incident | ConvertTo-Json -Depth 20 -Compress:$Compress

        # Write atomically using temp file + rename
        $tempPath = "$OutputPath.tmp.$PID.$([Guid]::NewGuid().ToString('N'))"
        [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.Encoding]::UTF8)
        # Use Move-Item for compatibility, remove existing file first
        if (Test-Path -LiteralPath $OutputPath) {
            Remove-Item -LiteralPath $OutputPath -Force
        }
        Move-Item -LiteralPath $tempPath -Destination $OutputPath -Force

        Write-Verbose "[IncidentBundle] Exported incident to: $OutputPath"

        return @{
            Success = $true
            Path = $OutputPath
            IncidentId = $Incident.incidentId
            BytesWritten = $json.Length
            Error = $null
        }
    }
    catch {
        # Clean up temp file on failure
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }

        return @{
            Success = $false
            Path = $OutputPath
            IncidentId = $Incident.incidentId
            BytesWritten = 0
            Error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Imports an incident bundle from JSON file.

.DESCRIPTION
    Imports an incident bundle from a JSON file for investigation or replay.

.PARAMETER Path
    Path to the JSON file to import.

.PARAMETER ValidateSchema
    If specified, validates schema version.

.OUTPUTS
    System.Collections.Hashtable. The imported incident bundle.

.EXAMPLE
    $bundle = Import-IncidentBundle -Path "./incident-123.json"
#>
function Import-IncidentBundle {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$ValidateSchema
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Incident bundle file not found: $Path"
    }

    try {
        $json = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($json)) {
            throw "File is empty"
        }
        $bundle = $json | ConvertFrom-Json
        if ($null -eq $bundle) {
            throw "Failed to parse JSON"
        }
        # Convert PSCustomObject to Hashtable for compatibility
        $bundleHash = ConvertTo-HashTable -InputObject $bundle

        if ($ValidateSchema) {
            if ($bundleHash.schemaVersion -ne $script:IncidentSchemaVersion) {
                throw "Schema version mismatch: expected $($script:IncidentSchemaVersion), got $($bundleHash.schemaVersion)"
            }
        }

        Write-Verbose "[IncidentBundle] Imported incident: $($bundleHash.incidentId)"
        
        return $bundleHash
    }
    catch {
        throw "Failed to import incident bundle: $_"
    }
}

<#
.SYNOPSIS
    Retrieves an incident bundle by ID.

.DESCRIPTION
    Loads an incident bundle from the incidents directory by its ID.

.PARAMETER IncidentId
    The incident ID to retrieve.

.PARAMETER IncidentsDirectory
    Optional directory to search. Defaults to canonical location.

.OUTPUTS
    System.Collections.Hashtable. The incident bundle, or null if not found.

.EXAMPLE
    $bundle = Get-IncidentBundle -IncidentId "abc123..."
#>
function Get-IncidentBundle {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IncidentId,

        [Parameter()]
        [string]$IncidentsDirectory = ""
    )

    if ([string]::IsNullOrEmpty($IncidentsDirectory)) {
        $IncidentsDirectory = Get-IncidentsDirectory
    }

    # Try exact match first
    $exactPath = Join-Path $IncidentsDirectory "$IncidentId.json"
    if (Test-Path -LiteralPath $exactPath) {
        return Import-IncidentBundle -Path $exactPath
    }

    # Search for partial match
    $pattern = "*$IncidentId*.json"
    $fileMatches = @(Get-ChildItem -Path $IncidentsDirectory -Filter $pattern -File -ErrorAction SilentlyContinue)
    
    if ($fileMatches.Count -eq 1) {
        return Import-IncidentBundle -Path $fileMatches[0].FullName
    }
    elseif ($fileMatches.Count -gt 1) {
        Write-Warning "Multiple incidents match '$IncidentId'. Use full ID for exact match."
        return $null
    }

    return $null
}

<#
.SYNOPSIS
    Searches incident bundles by criteria.

.DESCRIPTION
    Searches for incidents matching various criteria like status, category,
    severity, date range, etc.

.PARAMETER Status
    Filter by status: open, investigating, resolved, closed.

.PARAMETER Category
    Filter by root cause category.

.PARAMETER Severity
    Filter by severity: low, medium, high, critical.

.PARAMETER Pattern
    Filter by pattern type.

.PARAMETER FromDate
    Filter incidents created on or after this date.

.PARAMETER ToDate
    Filter incidents created on or before this date.

.PARAMETER QueryPattern
    Filter by text pattern in the query.

.PARAMETER IncidentsDirectory
    Optional directory to search.

.OUTPUTS
    System.Array. Array of matching incident bundles.

.EXAMPLE
    Search-IncidentBundles -Status "open" -Severity "high"
    Search-IncidentBundles -FromDate (Get-Date).AddDays(-7) -Category "bad-retrieval"
#>
function Search-IncidentBundles {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [ValidateSet('open', 'investigating', 'resolved', 'closed')]
        [string]$Status,

        [Parameter()]
        [string]$Category,

        [Parameter()]
        [ValidateSet('low', 'medium', 'high', 'critical')]
        [string]$Severity,

        [Parameter()]
        [string]$Pattern,

        [Parameter()]
        [DateTime]$FromDate,

        [Parameter()]
        [DateTime]$ToDate,

        [Parameter()]
        [string]$QueryPattern,

        [Parameter()]
        [string]$IncidentsDirectory = ""
    )

    if ([string]::IsNullOrEmpty($IncidentsDirectory)) {
        $IncidentsDirectory = Get-IncidentsDirectory
    }

    if (-not (Test-Path -LiteralPath $IncidentsDirectory)) {
        return @()
    }

    $files = @(Get-ChildItem -Path $IncidentsDirectory -Filter "*.json" -File -ErrorAction SilentlyContinue)
    $results = @()

    foreach ($file in $files) {
        try {
            $incident = Import-IncidentBundle -Path $file.FullName
            $include = $true

            # Apply filters
            if ($Status -and $incident.status -ne $Status) {
                $include = $false
            }

            if ($Category -and $incident.analysis.category -ne $Category) {
                $include = $false
            }

            if ($Severity -and $incident.analysis.severity -ne $Severity) {
                $include = $false
            }

            if ($Pattern -and $incident.analysis.pattern -ne $Pattern) {
                $include = $false
            }

            if ($FromDate) {
                $createdAt = [DateTime]::Parse($incident.createdAt)
                if ($createdAt -lt $FromDate) {
                    $include = $false
                }
            }

            if ($ToDate) {
                $createdAt = [DateTime]::Parse($incident.createdAt)
                if ($createdAt -gt $ToDate) {
                    $include = $false
                }
            }

            if ($QueryPattern) {
                if ($incident.bundle.query -notlike "*$QueryPattern*") {
                    $include = $false
                }
            }

            if ($include) {
                $results += $incident
            }
        }
        catch {
            Write-Verbose "[IncidentBundle] Failed to parse $($file.Name): $_"
        }
    }

    return $results | Sort-Object { $_.createdAt } -Descending
}

<#
.SYNOPSIS
    Tests if an incident matches known patterns.

.DESCRIPTION
    Analyzes an incident against known problem patterns to help
    classify and understand the issue.

.PARAMETER Incident
    The incident bundle to analyze.

.PARAMETER PatternName
    Optional specific pattern to test. Tests all if not specified.

.OUTPUTS
    System.Collections.Hashtable. Pattern match results.

.EXAMPLE
    $patterns = Test-IncidentPattern -Incident $bundle
#>
function Test-IncidentPattern {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Incident,

        [Parameter()]
        [string]$PatternName = ""
    )

    $results = @{
        matches = @()
        scores = @{}
        primaryPattern = $null
    }

    $patternsToTest = if ($PatternName) { 
        @{ $PatternName = $script:KnownPatterns[$PatternName] }
    } else { 
        $script:KnownPatterns 
    }

    foreach ($patternEntry in $patternsToTest.GetEnumerator()) {
        $name = $patternEntry.Key
        $pattern = $patternEntry.Value
        $score = 0
        $matchedIndicators = @()

        # Check evidence indicators
        if ($Incident.bundle.selectedEvidence) {
            foreach ($evidence in $Incident.bundle.selectedEvidence) {
                if ($evidence.indicators) {
                    foreach ($indicator in $pattern.indicators) {
                        if ($evidence.indicators -contains $indicator) {
                            $score += 1
                            $matchedIndicators += $indicator
                        }
                    }
                }
            }
        }

        # Check confidence decision
        if ($Incident.bundle.confidenceDecision) {
            $confidence = $Incident.bundle.confidenceDecision
            
            # Low confidence but answered anyway
            if ($name -eq 'hallucination' -and $confidence.ContainsKey('score') -and 
                $confidence.score -lt 0.7 -and $confidence.ContainsKey('shouldAbstain') -and
                -not $confidence.shouldAbstain) {
                $score += 2
            }

            # Contradiction markers present
            if ($name -eq 'contradiction-ignored' -and $confidence.ContainsKey('hasContradictions') -and
                $confidence.hasContradictions) {
                $score += 3
            }
        }

        # Check answer trace for authority issues
        if ($Incident.bundle.answerTrace -and $name -eq 'wrong-authority') {
            $trace = $Incident.bundle.answerTrace
            if ($trace.ContainsKey('evidenceAuthority')) {
                $authorities = $trace.evidenceAuthority
                if ($authorities -contains 'translation' -or $authorities -contains 'community') {
                    $score += 2
                }
            }
        }

        if ($score -gt 0) {
            $results.matches += @{
                pattern = $name
                description = $pattern.description
                score = $score
                indicators = $matchedIndicators
            }
            $results.scores[$name] = $score
        }
    }

    # Determine primary pattern (highest score)
    if ($results.scores.Count -gt 0) {
        $sorted = $results.scores.GetEnumerator() | Sort-Object Value -Descending
        $results.primaryPattern = $sorted[0].Key
    }

    return $results
}

<#
.SYNOPSIS
    Analyzes the root cause of an incident.

.DESCRIPTION
    Performs root cause analysis on an incident, categorizing it into
    one of the predefined categories per Section 15.6:
    - bad-retrieval
    - wrong-authority-level
    - contradiction-not-surfaced
    - low-confidence-should-abstain
    - missing-source
    - extraction-bug
    - ranking-bug
    - privacy-boundary-issue

.PARAMETER Incident
    The incident bundle to analyze.

.PARAMETER IncidentId
    Alternative: the incident ID to load and analyze.

.PARAMETER Notes
    Optional analysis notes.

.PARAMETER Severity
    Optional severity override.

.OUTPUTS
    System.Collections.Hashtable. Analysis result with root cause, category, etc.

.EXAMPLE
    $analysis = Get-IncidentRootCause -Incident $bundle
    $analysis = Get-IncidentRootCause -IncidentId "abc123..."
#>
function Get-IncidentRootCause {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByIncident')]
        [hashtable]$Incident,

        [Parameter(Mandatory = $true, ParameterSetName = 'ById')]
        [string]$IncidentId,

        [Parameter()]
        [string]$Notes = "",

        [Parameter()]
        [ValidateSet('low', 'medium', 'high', 'critical')]
        [string]$Severity = ""
    )

    # Load incident if ID provided
    if ($IncidentId) {
        $Incident = Get-IncidentBundle -IncidentId $IncidentId
        if (-not $Incident) {
            throw "Incident not found: $IncidentId"
        }
    }

    # Test for known patterns
    $patternResults = Test-IncidentPattern -Incident $Incident

    # Determine root cause category based on evidence and patterns
    $category = "unknown"
    $rootCause = "Unknown - requires manual investigation"

    if ($patternResults.primaryPattern) {
        switch ($patternResults.primaryPattern) {
            'hallucination' {
                $category = 'missing-source'
                $rootCause = "Answer contains unsourced claims (hallucination)"
            }
            'outdated-information' {
                $category = 'bad-retrieval'
                $rootCause = "Retrieved outdated or deprecated information"
            }
            'contradiction-ignored' {
                $category = 'contradiction-not-surfaced'
                $rootCause = "Contradictory evidence was present but not surfaced"
            }
            'wrong-authority' {
                $category = 'wrong-authority-level'
                $rootCause = "Low-authority evidence used as primary source"
            }
            'incomplete-retrieval' {
                $category = 'bad-retrieval'
                $rootCause = "Relevant evidence was not retrieved"
            }
            'privacy-leak' {
                $category = 'privacy-boundary-issue'
                $rootCause = "Sensitive information crossed privacy boundary"
            }
        }
    }

    # Check confidence decision for abstention issues
    if ($Incident.bundle.confidenceDecision) {
        $confidence = $Incident.bundle.confidenceDecision
        if ($confidence.ContainsKey('score') -and $confidence.score -lt 0.6 -and 
            $confidence.ContainsKey('shouldAbstain') -and -not $confidence.shouldAbstain) {
            $category = 'low-confidence-should-abstain'
            $rootCause = "Low confidence answer should have abstained"
        }
    }

    # Check evidence for extraction/ranking issues
    if ($Incident.bundle.excludedEvidence) {
        foreach ($evidence in $Incident.bundle.excludedEvidence) {
            if ($evidence.ContainsKey('extractionError') -and $evidence.extractionError) {
                $category = 'extraction-bug'
                $rootCause = "Evidence extraction failure: $($evidence.extractionError)"
                break
            }
            if ($evidence.ContainsKey('rankingError') -and $evidence.rankingError) {
                $category = 'ranking-bug'
                $rootCause = "Evidence ranking error: $($evidence.rankingError)"
                break
            }
        }
    }

    # Determine severity if not provided
    if (-not $Severity) {
        $Severity = 'medium'
        
        # Critical: privacy leaks, authoritative wrong answers
        if ($category -eq 'privacy-boundary-issue') {
            $Severity = 'critical'
        }
        # High: wrong authority, missed contradictions on important topics
        elseif ($category -in @('wrong-authority-level', 'contradiction-not-surfaced')) {
            $Severity = 'high'
        }
        # Low: minor retrieval issues where abstention would be acceptable
        elseif ($category -eq 'low-confidence-should-abstain') {
            $Severity = 'low'
        }
    }

    # Build analysis result
    $analysis = [ordered]@{
        rootCause = $rootCause
        category = $category
        severity = $Severity
        pattern = $patternResults.primaryPattern
        patternDetails = $patternResults
        notes = if ($Notes) { @($Notes) } else { @() }
        analyzedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        analyzedBy = [Environment]::UserName
    }

    # Update incident with analysis
    $Incident.analysis = $analysis

    return @{
        IncidentId = $Incident.incidentId
        Analysis = $analysis
        UpdatedIncident = $Incident
    }
}

<#
.SYNOPSIS
    Generates a human-readable incident report.

.DESCRIPTION
    Creates a formatted, human-readable report of an incident suitable
    for review, email, or documentation.

.PARAMETER Incident
    The incident to report on.

.PARAMETER IncidentId
    Alternative: the incident ID to load and report on.

.PARAMETER Format
    Output format: Text (default) or Markdown.

.PARAMETER IncludeEvidence
    If specified, includes full evidence details.

.OUTPUTS
    System.String. The formatted report.

.EXAMPLE
    $report = New-IncidentReport -Incident $bundle
    $report | Out-File "incident-report.txt"
#>
function New-IncidentReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByIncident')]
        [hashtable]$Incident,

        [Parameter(Mandatory = $true, ParameterSetName = 'ById')]
        [string]$IncidentId,

        [Parameter()]
        [ValidateSet('Text', 'Markdown')]
        [string]$Format = 'Text',

        [switch]$IncludeEvidence
    )

    # Load incident if ID provided
    if ($IncidentId) {
        $Incident = Get-IncidentBundle -IncidentId $IncidentId
        if (-not $Incident) {
            throw "Incident not found: $IncidentId"
        }
    }

    $sb = [System.Text.StringBuilder]::new()

    if ($Format -eq 'Markdown') {
        # Markdown format
        [void]$sb.AppendLine("# Answer Incident Report")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## Incident Details")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("- **Incident ID:** ``$($Incident.incidentId)``")
        [void]$sb.AppendLine("- **Status:** $($Incident.status)")
        [void]$sb.AppendLine("- **Created:** $($Incident.createdAt)")
        [void]$sb.AppendLine("- **Run ID:** ``$($Incident.runId)``")
        [void]$sb.AppendLine("")

        [void]$sb.AppendLine("## User Query")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine('```')
        [void]$sb.AppendLine($Incident.bundle.query)
        [void]$sb.AppendLine('```')
        [void]$sb.AppendLine("")

        [void]$sb.AppendLine("## Final Answer")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine('```')
        [void]$sb.AppendLine($Incident.bundle.finalAnswer)
        [void]$sb.AppendLine('```')
        [void]$sb.AppendLine("")

        if ($Incident.analysis.category) {
            [void]$sb.AppendLine("## Analysis")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("- **Category:** $($Incident.analysis.category)")
            [void]$sb.AppendLine("- **Severity:** $($Incident.analysis.severity)")
            [void]$sb.AppendLine("- **Root Cause:** $($Incident.analysis.rootCause)")
            [void]$sb.AppendLine("- **Pattern:** $($Incident.analysis.pattern)")
            [void]$sb.AppendLine("- **Analyzed:** $($Incident.analysis.analyzedAt) by $($Incident.analysis.analyzedBy)")
            [void]$sb.AppendLine("")
        }

        if ($IncludeEvidence -and $Incident.bundle.selectedEvidence) {
            [void]$sb.AppendLine("## Selected Evidence")
            [void]$sb.AppendLine("")
            foreach ($ev in $Incident.bundle.selectedEvidence) {
                [void]$sb.AppendLine("- ``$($ev.source)`` - $($ev.authority) authority")
            }
            [void]$sb.AppendLine("")
        }

        if ($Incident.bundle.linkedFeedback) {
            [void]$sb.AppendLine("## User Feedback")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("- **Type:** $($Incident.bundle.linkedFeedback.type)")
            [void]$sb.AppendLine("- **Reported by:** $($Incident.bundle.linkedFeedback.reportedBy)")
            if ($Incident.bundle.linkedFeedback.text) {
                [void]$sb.AppendLine("- **Text:** $($Incident.bundle.linkedFeedback.text)")
            }
            [void]$sb.AppendLine("")
        }
    }
    else {
        # Text format
        [void]$sb.AppendLine("=" * 60)
        [void]$sb.AppendLine("ANSWER INCIDENT REPORT")
        [void]$sb.AppendLine("=" * 60)
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Incident ID: $($Incident.incidentId)")
        [void]$sb.AppendLine("Status:      $($Incident.status.ToUpper())")
        [void]$sb.AppendLine("Created:     $($Incident.createdAt)")
        [void]$sb.AppendLine("Run ID:      $($Incident.runId)")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("-" * 40)
        [void]$sb.AppendLine("USER QUERY")
        [void]$sb.AppendLine("-" * 40)
        [void]$sb.AppendLine($Incident.bundle.query)
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("-" * 40)
        [void]$sb.AppendLine("FINAL ANSWER")
        [void]$sb.AppendLine("-" * 40)
        [void]$sb.AppendLine($Incident.bundle.finalAnswer)
        [void]$sb.AppendLine("")

        if ($Incident.analysis.category) {
            [void]$sb.AppendLine("-" * 40)
            [void]$sb.AppendLine("ANALYSIS")
            [void]$sb.AppendLine("-" * 40)
            [void]$sb.AppendLine("Category:    $($Incident.analysis.category)")
            [void]$sb.AppendLine("Severity:    $($Incident.analysis.severity.ToUpper())")
            [void]$sb.AppendLine("Root Cause:  $($Incident.analysis.rootCause)")
            [void]$sb.AppendLine("Pattern:     $($Incident.analysis.pattern)")
            [void]$sb.AppendLine("Analyzed:    $($Incident.analysis.analyzedAt)")
            [void]$sb.AppendLine("By:          $($Incident.analysis.analyzedBy)")
            [void]$sb.AppendLine("")
        }

        if ($IncludeEvidence -and $Incident.bundle.selectedEvidence) {
            [void]$sb.AppendLine("-" * 40)
            [void]$sb.AppendLine("SELECTED EVIDENCE ($($Incident.bundle.selectedEvidence.Count) items)")
            [void]$sb.AppendLine("-" * 40)
            foreach ($ev in $Incident.bundle.selectedEvidence) {
                [void]$sb.AppendLine("- [$($ev.authority)] $($ev.source)")
            }
            [void]$sb.AppendLine("")
        }

        if ($Incident.bundle.linkedFeedback) {
            [void]$sb.AppendLine("-" * 40)
            [void]$sb.AppendLine("USER FEEDBACK")
            [void]$sb.AppendLine("-" * 40)
            [void]$sb.AppendLine("Type: $($Incident.bundle.linkedFeedback.type)")
            [void]$sb.AppendLine("From: $($Incident.bundle.linkedFeedback.reportedBy)")
            if ($Incident.bundle.linkedFeedback.text) {
                [void]$sb.AppendLine("Text: $($Incident.bundle.linkedFeedback.text)")
            }
            [void]$sb.AppendLine("")
        }

        [void]$sb.AppendLine("=" * 60)
    }

    return $sb.ToString()
}

<#
.SYNOPSIS
    Exports incident analysis for governance review.

.DESCRIPTION
    Exports incident analysis in a standardized format suitable for
    governance review, compliance reporting, or external sharing.

.PARAMETER Incident
    The incident to export.

.PARAMETER IncidentId
    Alternative: the incident ID to load.

.PARAMETER OutputPath
    Output file path. If not specified, returns the JSON.

.PARAMETER IncludeFullBundle
    If specified, includes the complete bundle (large).

.OUTPUTS
    System.String or System.Collections.Hashtable. The analysis export.

.EXAMPLE
    Export-IncidentAnalysis -IncidentId "abc123..." -OutputPath "governance-report.json"
#>
function Export-IncidentAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByIncident')]
        [hashtable]$Incident,

        [Parameter(Mandatory = $true, ParameterSetName = 'ById')]
        [string]$IncidentId,

        [Parameter()]
        [string]$OutputPath = "",

        [switch]$IncludeFullBundle
    )

    # Load incident if ID provided
    if ($IncidentId) {
        $Incident = Get-IncidentBundle -IncidentId $IncidentId
        if (-not $Incident) {
            throw "Incident not found: $IncidentId"
        }
    }

    # Build governance report
    $governanceReport = [ordered]@{
        reportType = "answer-incident-analysis"
        generatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        generatedBy = [Environment]::UserName
        incident = [ordered]@{
            incidentId = $Incident.incidentId
            createdAt = $Incident.createdAt
            status = $Incident.status
            runId = $Incident.runId
        }
        summary = [ordered]@{
            query = $Incident.bundle.query
            finalAnswer = if ($Incident.bundle.finalAnswer.Length -gt 500) { 
                $Incident.bundle.finalAnswer.Substring(0, 500) + "..." 
            } else { 
                $Incident.bundle.finalAnswer 
            }
            retrievalProfile = $Incident.bundle.retrievalProfile
        }
        analysis = $Incident.analysis
        metrics = [ordered]@{
            evidenceCount = if ($Incident.bundle.selectedEvidence) { 
                $Incident.bundle.selectedEvidence.Count 
            } else { 0 }
            excludedCount = if ($Incident.bundle.excludedEvidence) { 
                $Incident.bundle.excludedEvidence.Count 
            } else { 0 }
        }
    }

    if ($IncludeFullBundle) {
        $governanceReport.bundle = $Incident.bundle
    }

    $json = $governanceReport | ConvertTo-Json -Depth 15

    if ($OutputPath) {
        [System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.Encoding]::UTF8)
        return @{
            Success = $true
            Path = $OutputPath
            Report = $governanceReport
        }
    }

    return $governanceReport
}

<#
.SYNOPSIS
    Compares a replay result to the original incident.

.DESCRIPTION
    Performs a detailed comparison between a replay result and the
    original incident to identify changes and improvements.

.PARAMETER Incident
    The original incident.

.PARAMETER ReplayResult
    The replay result from Invoke-IncidentReplay.

.OUTPUTS
    System.Collections.Hashtable. Comparison results.

.EXAMPLE
    $comparison = Compare-IncidentReplay -Incident $bundle -ReplayResult $replay
#>
function Compare-IncidentReplay {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Incident,

        [Parameter(Mandatory = $true)]
        [hashtable]$ReplayResult
    )

    $comparison = [ordered]@{
        comparisonId = [Guid]::NewGuid().ToString('N')
        incidentId = $Incident.incidentId
        replayId = $ReplayResult.replayId
        comparedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        answerComparison = [ordered]@{
            identical = $false
            similarity = 0.0
            keyDifferences = @()
        }
        evidenceComparison = [ordered]@{
            originalCount = if ($Incident.bundle.selectedEvidence) { 
                $Incident.bundle.selectedEvidence.Count 
            } else { 0 }
            replayCount = 0  # Would be populated from replay
            added = @()
            removed = @()
            changed = @()
        }
        confidenceComparison = [ordered]@{
            original = $Incident.bundle.confidenceDecision
            replay = $null
            improved = $false
        }
        verdict = [ordered]@{
            improved = $false
            regressed = $false
            unchanged = $true
            confidence = "low"
        }
    }

    # Compare answers (would use actual text comparison in production)
    $originalAnswer = $Incident.bundle.finalAnswer
    $replayAnswer = $ReplayResult.replayAnswer

    $comparison.answerComparison.identical = ($originalAnswer -eq $replayAnswer)
    
    # Simple similarity calculation (would use more sophisticated method)
    if ($originalAnswer.Length -gt 0 -and $replayAnswer.Length -gt 0) {
        # Placeholder: would use string similarity algorithm
        $comparison.answerComparison.similarity = 0.75
    }

    # Determine verdict
    if ($comparison.answerComparison.identical -and 
        -not $ReplayResult.evidenceChanged) {
        $comparison.verdict.unchanged = $true
        $comparison.verdict.confidence = "high"
    }
    elseif ($ReplayResult.answerChanged -and $ReplayResult.evidenceChanged) {
        $comparison.verdict.improved = $true
        $comparison.verdict.unchanged = $false
    }

    return $comparison
}

<#
.SYNOPSIS
    Determines if an incident has been fixed.

.DESCRIPTION
    Evaluates whether an incident issue has been resolved based on
    replay results and comparison data.

.PARAMETER IncidentId
    The incident ID to check.

.PARAMETER Incident
    Alternative: the incident object.

.PARAMETER ReplayResult
    Optional replay result to use for determination.

.PARAMETER Comparison
    Optional comparison result to use.

.OUTPUTS
    System.Collections.Hashtable. Fix determination result.

.EXAMPLE
    $fixed = Test-IncidentFixed -IncidentId "abc123..."
#>
function Test-IncidentFixed {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ById')]
        [string]$IncidentId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByIncident')]
        [hashtable]$Incident,

        [Parameter()]
        [hashtable]$ReplayResult,

        [Parameter()]
        [hashtable]$Comparison
    )

    # Load incident if ID provided
    if ($IncidentId) {
        $Incident = Get-IncidentBundle -IncidentId $IncidentId
        if (-not $Incident) {
            throw "Incident not found: $IncidentId"
        }
    }

    # Run replay if not provided
    if (-not $ReplayResult) {
        $ReplayResult = Invoke-IncidentReplay -Incident $Incident -UseCurrentPacks
    }

    # Run comparison if not provided
    if (-not $Comparison) {
        $Comparison = Compare-IncidentReplay -Incident $Incident -ReplayResult $ReplayResult
    }

    # Determine if fixed based on category and comparison
    $isFixed = $false
    $fixConfidence = "low"
    $reasoning = @()

    switch ($Incident.analysis.category) {
        'low-confidence-should-abstain' {
            # Fixed if now abstains or has higher confidence
            $isFixed = $ReplayResult.confidenceImproved -or $ReplayResult.nowAbstains
            $fixConfidence = if ($ReplayResult.nowAbstains) { "high" } else { "medium" }
            $reasoning += "Confidence-based incident: checking abstention behavior"
        }
        'missing-source' {
            # Fixed if evidence now includes sources
            $isFixed = $ReplayResult.evidenceChanged -and $ReplayResult.hasSources
            $fixConfidence = if ($isFixed) { "high" } else { "low" }
            $reasoning += "Missing source incident: checking evidence sourcing"
        }
        'bad-retrieval' {
            # Fixed if evidence changed significantly
            $isFixed = $Comparison.evidenceComparison.added.Count -gt 0
            $fixConfidence = "medium"
            $reasoning += "Retrieval issue: checking for new evidence"
        }
        default {
            # Default: fixed if answer changed
            $isFixed = $ReplayResult.answerChanged
            $fixConfidence = "low"
            $reasoning += "General incident: checking answer change"
        }
    }

    # Update incident status if fixed
    if ($isFixed -and $Incident.status -eq 'open') {
        $Incident.status = 'resolved'
        $Incident.replay.fixed = $true
    }

    return [ordered]@{
        incidentId = $Incident.incidentId
        isFixed = $isFixed
        confidence = $fixConfidence
        reasoning = $reasoning
        testedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        replayId = $ReplayResult.replayId
        comparisonId = $Comparison.comparisonId
        updatedIncident = $Incident
    }
}

<#
.SYNOPSIS
    Registers an incident in the tracking system.

.DESCRIPTION
    Registers a new incident in the incident registry and saves the
    bundle to the incidents directory.

.PARAMETER Incident
    The incident to register.

.PARAMETER AutoAnalyze
    If specified, automatically runs root cause analysis.

.OUTPUTS
    System.Collections.Hashtable. Registration result.

.EXAMPLE
    Register-Incident -Incident $bundle
    Register-Incident -Incident $bundle -AutoAnalyze
#>
function Register-Incident {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Incident,

        [switch]$AutoAnalyze
    )

    # Run auto-analysis if requested
    if ($AutoAnalyze -and -not $Incident.analysis.category) {
        $analysisResult = Get-IncidentRootCause -Incident $Incident
        $Incident = $analysisResult.UpdatedIncident
    }

    # Export the incident bundle
    $exportResult = Export-IncidentBundle -Incident $Incident
    if (-not $exportResult.Success) {
        throw "Failed to export incident bundle: $($exportResult.Error)"
    }

    # Update registry
    $registryPath = $script:IncidentRegistryFile
    $registry = @{ incidents = @() }

    if (Test-Path -LiteralPath $registryPath) {
        try {
            $json = [System.IO.File]::ReadAllText($registryPath, [System.Text.Encoding]::UTF8)
            if ([string]::IsNullOrWhiteSpace($json)) {
                throw "Registry file is empty"
            }
            $existing = $json | ConvertFrom-Json
            if ($null -eq $existing) {
                throw "Failed to parse registry JSON"
            }
            $registry = ConvertTo-HashTable -InputObject $existing
            if ($null -eq $registry -or -not $registry.ContainsKey('incidents')) {
                $registry = @{ incidents = @() }
            }
            elseif ($null -ne $registry.incidents -and $registry.incidents -isnot [array]) {
                $registry.incidents = @($registry.incidents)
            }
        }
        catch {
            Write-Warning "[IncidentBundle] Failed to load existing registry, creating new: $_"
            $registry = @{ incidents = @() }
        }
    }

    # Add to registry
    $registryEntry = [ordered]@{
        incidentId = $Incident.incidentId
        createdAt = $Incident.createdAt
        status = $Incident.status
        category = $Incident.analysis.category
        severity = $Incident.analysis.severity
        query = if ($Incident.bundle.query.Length -gt 100) { 
            $Incident.bundle.query.Substring(0, 100) + "..." 
        } else { 
            $Incident.bundle.query 
        }
        path = $exportResult.Path
    }

    $registry.incidents += $registryEntry

    # Save registry
    $registryDir = Split-Path -Parent $registryPath
    if (-not (Test-Path -LiteralPath $registryDir)) {
        New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    }

    $registryJson = $registry | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($registryPath, $registryJson, [System.Text.Encoding]::UTF8)

    Write-Verbose "[IncidentBundle] Registered incident: $($Incident.incidentId)"

    return @{
        Success = $true
        IncidentId = $Incident.incidentId
        Path = $exportResult.Path
        RegistryPath = $registryPath
        AutoAnalyzed = $AutoAnalyze.IsPresent
    }
}

<#
.SYNOPSIS
    Updates the status of an incident.

.DESCRIPTION
    Updates the status of an incident (open, investigating, resolved, closed)
    and persists the change.

.PARAMETER IncidentId
    The incident ID to update.

.PARAMETER Status
    The new status: open, investigating, resolved, closed.

.PARAMETER Notes
    Optional notes about the status change.

.OUTPUTS
    System.Collections.Hashtable. Update result.

.EXAMPLE
    Update-IncidentStatus -IncidentId "abc123..." -Status "resolved"
#>
function Update-IncidentStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IncidentId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('open', 'investigating', 'resolved', 'closed')]
        [string]$Status,

        [Parameter()]
        [string]$Notes = ""
    )

    # Load the incident
    $incident = Get-IncidentBundle -IncidentId $IncidentId
    if (-not $incident) {
        throw "Incident not found: $IncidentId"
    }

    $oldStatus = $incident.status
    $incident.status = $Status

    # Add status change to analysis notes
    if (-not $incident.analysis.notes) {
        $incident.analysis.notes = @()
    }
    $statusNote = "Status changed from '$oldStatus' to '$Status' at $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
    if ($Notes) {
        $statusNote += " - $Notes"
    }
    $incident.analysis.notes += $statusNote

    # Save the updated incident
    $exportResult = Export-IncidentBundle -Incident $incident

    # Update registry
    $registryPath = $script:IncidentRegistryFile
    if (Test-Path -LiteralPath $registryPath) {
        $json = [System.IO.File]::ReadAllText($registryPath, [System.Text.Encoding]::UTF8)
        $parsed = $json | ConvertFrom-Json
        $registry = ConvertTo-HashTable -InputObject $parsed
        if ($null -ne $registry.incidents -and $registry.incidents -isnot [array]) {
            $registry.incidents = @($registry.incidents)
        }

        $entry = $registry.incidents | Where-Object { $_.incidentId -eq $IncidentId }
        if ($entry) {
            $entry.status = $Status
            $registryJson = $registry | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($registryPath, $registryJson, [System.Text.Encoding]::UTF8)
        }
    }

    Write-Verbose "[IncidentBundle] Updated incident $IncidentId status: $oldStatus -> $Status"

    return @{
        Success = $exportResult.Success
        IncidentId = $IncidentId
        OldStatus = $oldStatus
        NewStatus = $Status
        Path = $exportResult.Path
    }
}

<#
.SYNOPSIS
    Gets incident metrics for SLO tracking.

.DESCRIPTION
    Calculates various metrics for incident tracking and SLO compliance:
    - Total incidents by status
    - Average time to resolution
    - Incidents by category and severity
    - Trends over time

.PARAMETER FromDate
    Start date for metrics calculation.

.PARAMETER ToDate
    End date for metrics calculation.

.PARAMETER Category
    Filter by specific category.

.PARAMETER IncidentsDirectory
    Optional directory to search.

.OUTPUTS
    System.Collections.Hashtable. Metrics data.

.EXAMPLE
    $metrics = Get-IncidentMetrics
    $weeklyMetrics = Get-IncidentMetrics -FromDate (Get-Date).AddDays(-7)
#>
function Get-IncidentMetrics {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [DateTime]$FromDate = [DateTime]::MinValue,

        [Parameter()]
        [DateTime]$ToDate = [DateTime]::MaxValue,

        [Parameter()]
        [string]$Category = "",

        [Parameter()]
        [string]$IncidentsDirectory = ""
    )

    if ([string]::IsNullOrEmpty($IncidentsDirectory)) {
        $IncidentsDirectory = Get-IncidentsDirectory
    }

    # Search for incidents in date range
    $incidents = @(Search-IncidentBundles -FromDate $FromDate -ToDate $ToDate)

    if ($Category) {
        $incidents = @($incidents | Where-Object { $_.analysis.category -eq $Category })
    }

    # Calculate metrics
    $totalCount = $incidents.Count
    
    $byStatus = @{
        open = 0
        investigating = 0
        resolved = 0
        closed = 0
    }

    $byCategory = @{}
    $bySeverity = @{
        low = 0
        medium = 0
        high = 0
        critical = 0
    }

    $resolutionTimes = @()

    foreach ($inc in $incidents) {
        # Count by status
        if ($byStatus.ContainsKey($inc.status)) {
            $byStatus[$inc.status]++
        }

        # Count by category
        $cat = if ($inc.analysis.category) { $inc.analysis.category } else { 'unknown' }
        if (-not $byCategory.ContainsKey($cat)) {
            $byCategory[$cat] = 0
        }
        $byCategory[$cat]++

        # Count by severity
        $sev = if ($inc.analysis.severity) { $inc.analysis.severity } else { 'unknown' }
        if ($bySeverity.ContainsKey($sev)) {
            $bySeverity[$sev]++
        }

        # Calculate resolution time if resolved
        if ($inc.status -in @('resolved', 'closed') -and $inc.replay.replayHistory) {
            $created = [DateTime]::Parse($inc.createdAt)
            $lastReplay = [DateTime]::Parse($inc.replay.lastReplayAt)
            $resolutionTime = $lastReplay - $created
            $resolutionTimes += $resolutionTime.TotalHours
        }
    }

    $avgResolutionHours = if ($resolutionTimes.Count -gt 0) { 
        [math]::Round(($resolutionTimes | Measure-Object -Average).Average, 2)
    } else { 
        0 
    }

    # Calculate rates
    $openCount = $byStatus.open + $byStatus.investigating
    $resolvedCount = $byStatus.resolved + $byStatus.closed
    $resolutionRate = if ($totalCount -gt 0) { 
        [math]::Round($resolvedCount / $totalCount * 100, 2)
    } else { 
        0 
    }

    return [ordered]@{
        generatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        period = @{
            from = $FromDate.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            to = $ToDate.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
        summary = [ordered]@{
            totalIncidents = $totalCount
            openCount = $openCount
            resolvedCount = $resolvedCount
            resolutionRatePercent = $resolutionRate
            averageResolutionHours = $avgResolutionHours
        }
        byStatus = $byStatus
        byCategory = $byCategory
        bySeverity = $bySeverity
        sloMetrics = [ordered]@{
            # Example SLOs - adjust thresholds as needed
            meetsResolutionRateSlo = $resolutionRate -ge 80  # 80% resolution rate target
            meetsTimeToResolutionSlo = $avgResolutionHours -le 72  # 72 hour target
            openCriticalCount = $bySeverity.critical
            meetsCriticalResponseSlo = $bySeverity.critical -eq 0  # No open critical incidents
        }
    }
}

<#
.SYNOPSIS
    Helper function to get current pack versions.

.DESCRIPTION
    Retrieves the current versions of all installed packs.

.OUTPUTS
    System.Collections.Hashtable. Pack name -> version mapping.
#>
function Get-CurrentPackVersions {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $versions = @{}

    # Look for packs directory
    $packsDir = "packs"
    if (Test-Path -LiteralPath $packsDir) {
        $manifestDir = Join-Path $packsDir "manifests"
        if (Test-Path -LiteralPath $manifestDir) {
            $manifests = Get-ChildItem -Path $manifestDir -Filter "*.json" -File
            foreach ($manifest in $manifests) {
                try {
                    $json = [System.IO.File]::ReadAllText($manifest.FullName, [System.Text.Encoding]::UTF8)
                    $parsed = $json | ConvertFrom-Json
                    $content = ConvertTo-HashTable -InputObject $parsed
                    $packName = [System.IO.Path]::GetFileNameWithoutExtension($manifest.Name)
                    $versions[$packName] = if ($content.ContainsKey('version')) { $content.version } else { "unknown" }
                }
                catch {
                    Write-Verbose "[IncidentBundle] Failed to read manifest: $($manifest.Name)"
                }
            }
        }
    }

    return $versions
}

# Export all public functions
Export-ModuleMember -Function @(
    'New-AnswerIncidentBundle',
    'Add-IncidentEvidence',
    'Add-IncidentFeedback',
    'Export-IncidentBundle',
    'Import-IncidentBundle',
    'Get-IncidentBundle',
    'Search-IncidentBundles',
    'Test-IncidentPattern',
    'Get-IncidentRootCause',
    'New-IncidentReport',
    'Export-IncidentAnalysis',
    'Invoke-IncidentReplay',
    'Compare-IncidentReplay',
    'Test-IncidentFixed',
    'Register-Incident',
    'Update-IncidentStatus',
    'Get-IncidentMetrics'
)
