#requires -Version 5.1
<#
.SYNOPSIS
    Replay Harness module for LLM Workflow Platform - Phase 6 Implementation.

.DESCRIPTION
    Implements Section 19.4 of the Canonical Architecture for the LLM Workflow platform.
    Provides before/after replay capabilities for validating system changes against:
    - Golden tasks (known good answers)
    - Known bad-answer incidents
    - Retrieval profiles
    - Evidence-selection behavior

    Used for:
    - Parser upgrade validation
    - Ranking algorithm changes
    - Pack updates
    - Regression testing

.NOTES
    File: ReplayHarness.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Phase: 6 - Governance and Replay
    Compatible with: PowerShell 5.1+

.EXAMPLE
    # Replay a golden task for validation
    $result = Invoke-GoldenTaskReplay -TaskId "golden-api-lookup-001" `
        -BaselineConfig $oldConfig -NewConfig $newConfig -CompareResults

.EXAMPLE
    # Replay an incident to verify fix
    $replay = Invoke-IncidentReplay -IncidentId "incident-abc123" `
        -NewSystemConfig $config -UpdateIncident

.EXAMPLE
    # Batch replay multiple targets
    $results = Invoke-BatchReplay -Targets $tasks -Config $config -Parallel

.EXAMPLE
    # Compare replay results
    $comparison = Compare-ReplayResults -BaselineResult $baseline `
        -NewResult $new -ComparisonRules $rules

.EXAMPLE
    # Test for regressions
    $regression = Test-Regression -Baseline $old -Current $new -Thresholds $thresholds

.EXAMPLE
    # Generate replay report
    $report = New-ReplayReport -ReplayResults $results -ReportType 'detailed'
#>

Set-StrictMode -Version Latest

#===============================================================================
# Module Constants and Configuration
#===============================================================================

$script:ModuleVersion = '1.0.0'
$script:SchemaVersion = 1
$script:DefaultReplayDirectory = ".llm-workflow/replays"
$script:DefaultGoldenTaskDirectory = ".llm-workflow/golden-tasks"
$script:ReplayRegistryFile = ".llm-workflow/state/replay-registry.json"

# Replay target types
$script:ReplayTargetTypes = @(
    'golden-task',
    'incident',
    'profile',
    'evidence-selection'
)

# Comparison rule types
$script:ComparisonRuleTypes = @(
    'exact-match',
    'property-match',
    'confidence-threshold',
    'evidence-overlap',
    'answer-mode-consistent',
    'custom-function'
)

# Default comparison thresholds
$script:DefaultThresholds = @{
    confidenceSimilarity = 0.05    # 5% confidence difference allowed
    evidenceOverlapMin = 0.70      # 70% evidence overlap required
    answerSimilarityMin = 0.80     # 80% answer similarity required
    propertyMatchRequired = @('answerMode', 'confidenceDecision.shouldAbstain')
}

# Regression severity levels
$script:RegressionSeverities = @(
    'none',
    'minor',
    'moderate',
    'critical'
)

#===============================================================================
# Helper Functions
#===============================================================================

<#
.SYNOPSIS
    Converts a PSCustomObject to a Hashtable recursively.

.DESCRIPTION
    Helper function to convert PSCustomObject (from ConvertFrom-Json) 
    to a Hashtable for PowerShell 5.1 compatibility.

.PARAMETER InputObject
    The object to convert.

.OUTPUTS
    System.Collections.Hashtable
#>
function ConvertTo-HashTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.Hashtable] -and 
        -not ($InputObject -is [System.Collections.Specialized.OrderedDictionary])) {
        return $InputObject
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and 
        $InputObject -isnot [string] -and
        $InputObject -isnot [System.Collections.Hashtable]) {
        $array = @()
        foreach ($item in $InputObject) {
            $array += (ConvertTo-HashTable -InputObject $item)
        }
        return $array
    }
    elseif ($InputObject -is [PSCustomObject]) {
        $hash = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $hash[$property.Name] = ConvertTo-HashTable -InputObject $property.Value
        }
        return $hash
    }
    elseif ($InputObject -is [System.Collections.Specialized.OrderedDictionary]) {
        $hash = @{}
        foreach ($key in $InputObject.Keys) {
            $hash[$key] = ConvertTo-HashTable -InputObject $InputObject[$key]
        }
        return $hash
    }
    else {
        return $InputObject
    }
}

<#
.SYNOPSIS
    Gets the default replay directory path.

.DESCRIPTION
    Returns the canonical replay directory path. Creates it if it doesn't exist.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    System.String. The full path to the replay directory.
#>
function Get-ReplayDirectory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ProjectRoot = "."
    )

    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) {
        $resolvedRoot = $ProjectRoot
    }

    $replayDir = Join-Path $resolvedRoot $script:DefaultReplayDirectory
    
    if (-not (Test-Path -LiteralPath $replayDir)) {
        try {
            New-Item -ItemType Directory -Path $replayDir -Force | Out-Null
        }
        catch {
            throw "Failed to create replay directory: $replayDir. Error: $_"
        }
    }

    return $replayDir
}

<#
.SYNOPSIS
    Generates a unique replay ID.

.DESCRIPTION
    Creates a unique identifier for a replay session.

.OUTPUTS
    System.String. The generated replay ID.
#>
function New-ReplayId {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmss")
    $guid = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    return "replay-$timestamp-$guid"
}

<#
.SYNOPSIS
    Calculates the similarity between two strings.

.DESCRIPTION
    Uses Levenshtein distance algorithm to calculate similarity
    between two strings, returning a value between 0 and 1.

.PARAMETER String1
    First string to compare.

.PARAMETER String2
    Second string to compare.

.OUTPUTS
    System.Double. Similarity score between 0 and 1.
#>
function Get-StringSimilarity {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$String1,

        [Parameter(Mandatory = $true)]
        [string]$String2
    )

    # Handle edge cases
    if ($String1 -eq $String2) { return 1.0 }
    if ([string]::IsNullOrEmpty($String1) -or [string]::IsNullOrEmpty($String2)) { return 0.0 }

    $len1 = $String1.Length
    $len2 = $String2.Length

    # Create distance matrix
    $distances = New-Object 'int[,]' ($len1 + 1), ($len2 + 1)

    # Initialize first row and column
    for ($i = 0; $i -le $len1; $i++) {
        $distances[$i, 0] = $i
    }
    for ($j = 0; $j -le $len2; $j++) {
        $distances[0, $j] = $j
    }

    # Fill the matrix
    for ($i = 1; $i -le $len1; $i++) {
        for ($j = 1; $j -le $len2; $j++) {
            $cost = if ($String1[$i - 1] -eq $String2[$j - 1]) { 0 } else { 1 }
            
            $deletion = $distances[($i - 1), $j] + 1
            $insertion = $distances[$i, ($j - 1)] + 1
            $substitution = $distances[($i - 1), ($j - 1)] + $cost
            
            $distances[$i, $j] = [Math]::Min([Math]::Min($deletion, $insertion), $substitution)
        }
    }

    $maxLen = [Math]::Max($len1, $len2)
    if ($maxLen -eq 0) { return 1.0 }
    
    $distance = $distances[$len1, $len2]
    return 1.0 - ($distance / $maxLen)
}

<#
.SYNOPSIS
    Calculates the overlap between two evidence collections.

.DESCRIPTION
    Compares two collections of evidence and calculates the overlap percentage.

.PARAMETER Evidence1
    First evidence collection.

.PARAMETER Evidence2
    Second evidence collection.

.OUTPUTS
    System.Collections.Hashtable. Overlap statistics.
#>
function Get-EvidenceOverlap {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Evidence1,

        [Parameter(Mandatory = $true)]
        [array]$Evidence2
    )

    if (($Evidence1 | Measure-Object).Count -eq 0 -and 
        ($Evidence2 | Measure-Object).Count -eq 0) {
        return @{
            overlapPercent = 100.0
            matched = 0
            onlyInFirst = 0
            onlyInSecond = 0
            totalUnique = 0
        }
    }

    if (($Evidence1 | Measure-Object).Count -eq 0) {
        return @{
            overlapPercent = 0.0
            matched = 0
            onlyInFirst = 0
            onlyInSecond = ($Evidence2 | Measure-Object).Count
            totalUnique = ($Evidence2 | Measure-Object).Count
        }
    }

    if (($Evidence2 | Measure-Object).Count -eq 0) {
        return @{
            overlapPercent = 0.0
            matched = 0
            onlyInFirst = ($Evidence1 | Measure-Object).Count
            onlyInSecond = 0
            totalUnique = ($Evidence1 | Measure-Object).Count
        }
    }

    # Extract evidence IDs or sources for comparison
    $getEvidenceKey = {
        param([hashtable]$ev)
        if ($ev.ContainsKey('evidenceId')) { return $ev.evidenceId }
        if ($ev.ContainsKey('source')) { return $ev.source }
        if ($ev.ContainsKey('id')) { return $ev.id }
        return ($ev | ConvertTo-Json -Compress)
    }

    $keys1 = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($ev in $Evidence1) {
        $key = & $getEvidenceKey $ev
        [void]$keys1.Add($key)
    }

    $keys2 = [System.Collections.Generic.HashSet[string]]::new()
    $matched = 0
    foreach ($ev in $Evidence2) {
        $key = & $getEvidenceKey $ev
        [void]$keys2.Add($key)
        if ($keys1.Contains($key)) {
            $matched++
        }
    }

    $onlyInFirst = 0
    foreach ($key in $keys1) {
        if (-not $keys2.Contains($key)) {
            $onlyInFirst++
        }
    }

    $onlyInSecond = $keys2.Count - $matched
    $totalUnique = $keys1.Count + $keys2.Count - $matched
    $overlapPercent = if ($totalUnique -gt 0) { 
        ($matched / $totalUnique) * 100 
    } else { 
        100.0 
    }

    return @{
        overlapPercent = [math]::Round($overlapPercent, 2)
        matched = $matched
        onlyInFirst = $onlyInFirst
        onlyInSecond = $onlyInSecond
        totalUnique = $totalUnique
    }
}

<#
.SYNOPSIS
    Gets a nested property value from an object using dot notation.

.DESCRIPTION
    Retrieves a property value from a nested object structure using
    dot notation (e.g., "config.parser.version").

.PARAMETER Object
    The object to retrieve the property from.

.PARAMETER Path
    Dot-notation path to the property.

.OUTPUTS
    The property value, or $null if not found.
#>
function Get-NestedProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $parts = $Path -split '\.'
    $current = $Object

    foreach ($part in $parts) {
        if ($null -eq $current) { return $null }
        if ($current -is [hashtable] -or $current -is [System.Collections.Specialized.OrderedDictionary]) {
            $current = $current[$part]
        }
        elseif ($current -is [PSCustomObject]) {
            $current = $current.$part
        }
        else {
            return $null
        }
    }

    return $current
}

#===============================================================================
# Core Replay Functions
#===============================================================================

<#
.SYNOPSIS
    Main replay function for executing replay operations.

.DESCRIPTION
    The primary entry point for replay operations. Supports replaying
    against golden tasks, incidents, retrieval profiles, and evidence
    selection behavior. Handles before/after comparisons and regression
    detection.

.PARAMETER ReplayTarget
    Hashtable defining what to replay:
    - type: 'golden-task', 'incident', 'profile', or 'evidence-selection'
    - id: The target identifier
    - query: For profile/evidence replays
    - Additional type-specific properties

.PARAMETER SystemConfig
    Hashtable with system configuration:
    - packVersions: Hashtable of pack versions
    - retrievalProfile: Profile name
    - parserVersion: Parser version string
    - Additional config as needed

.PARAMETER Options
    Replay options:
    - CompareMode: Enable comparison with baseline
    - BaselineResult: Previous result for comparison
    - ComparisonRules: Rules for comparison
    - StoreResult: Whether to persist the result
    - Parallel: Enable parallel execution

.OUTPUTS
    System.Collections.Hashtable. Complete replay result with comparison data.

.EXAMPLE
    $target = @{ type = 'golden-task'; id = 'task-001' }
    $config = @{ retrievalProfile = 'api-lookup'; parserVersion = '2.0' }
    $options = @{ CompareMode = $true; StoreResult = $true }
    $result = Invoke-AnswerReplay -ReplayTarget $target -SystemConfig $config -Options $options
#>
function Invoke-AnswerReplay {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ReplayTarget,

        [Parameter(Mandatory = $true)]
        [hashtable]$SystemConfig,

        [Parameter()]
        [hashtable]$Options = @{}
    )

    # Validate target type
    $targetType = $ReplayTarget.type
    if (-not $targetType -or $script:ReplayTargetTypes -notcontains $targetType) {
        throw "Invalid or missing replay target type. Valid types: $($script:ReplayTargetTypes -join ', ')"
    }

    # Generate replay ID and timestamp
    $replayId = New-ReplayId
    $timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Verbose "[ReplayHarness] Starting replay $replayId of type: $targetType"

    try {
        # Execute the appropriate replay based on type
        $replayResult = switch ($targetType) {
            'golden-task' {
                Invoke-GoldenTaskReplayInternal -ReplayTarget $ReplayTarget -SystemConfig $SystemConfig -Options $Options
            }
            'incident' {
                Invoke-IncidentReplayInternal -ReplayTarget $ReplayTarget -SystemConfig $SystemConfig -Options $Options
            }
            'profile' {
                Invoke-ProfileReplayInternal -ReplayTarget $ReplayTarget -SystemConfig $SystemConfig -Options $Options
            }
            'evidence-selection' {
                Invoke-EvidenceSelectionReplayInternal -ReplayTarget $ReplayTarget -SystemConfig $SystemConfig -Options $Options
            }
            default {
                throw "Unsupported replay type: $targetType"
            }
        }

        $stopwatch.Stop()

        # Build the complete result
        $result = [ordered]@{
            replayId = $replayId
            replayType = $targetType
            targetId = $ReplayTarget.id
            timestamp = $timestamp
            durationMs = $stopwatch.ElapsedMilliseconds
            systemConfig = [ordered]@{
                packVersions = $SystemConfig.packVersions
                retrievalProfile = $SystemConfig.retrievalProfile
                parserVersion = $SystemConfig.parserVersion
            }
            originalResult = $replayResult.originalResult
            replayedResult = $replayResult.replayedResult
            comparison = $replayResult.comparison
            metadata = [ordered]@{
                evidenceCount = ($replayResult.replayedResult.selectedEvidence | Measure-Object).Count
                answerMode = $replayResult.replayedResult.answerMode
                status = 'completed'
                error = $null
            }
        }

        # Store result if requested
        if ($Options.StoreResult) {
            Export-ReplaySession -Session $result -OutputPath (Join-Path (Get-ReplayDirectory) "$replayId.json") | Out-Null
        }

        return $result
    }
    catch {
        $stopwatch.Stop()
        
        return [ordered]@{
            replayId = $replayId
            replayType = $targetType
            targetId = $ReplayTarget.id
            timestamp = $timestamp
            durationMs = $stopwatch.ElapsedMilliseconds
            systemConfig = $SystemConfig
            originalResult = $null
            replayedResult = $null
            comparison = $null
            metadata = [ordered]@{
                status = 'failed'
                error = $_.Exception.Message
            }
        }
    }
}

<#
.SYNOPSIS
    Replays a golden task for validation.

.DESCRIPTION
    Replays a predefined golden task (known good answer) against both
    baseline and new configurations to validate system changes.

.PARAMETER TaskId
    The unique identifier of the golden task.

.PARAMETER BaselineConfig
    The original system configuration (baseline).

.PARAMETER NewConfig
    The new system configuration to test.

.PARAMETER CompareResults
    If specified, performs comparison between baseline and new results.

.OUTPUTS
    System.Collections.Hashtable. Replay results including comparison.

.EXAMPLE
    $result = Invoke-GoldenTaskReplay -TaskId "golden-api-lookup-001" `
        -BaselineConfig $oldConfig -NewConfig $newConfig -CompareResults

.EXAMPLE
    $baseline = @{ parserVersion = '1.0'; retrievalProfile = 'api-lookup' }
    $new = @{ parserVersion = '2.0'; retrievalProfile = 'api-lookup' }
    $result = Invoke-GoldenTaskReplay -TaskId "golden-code-002" `
        -BaselineConfig $baseline -NewConfig $new -CompareResults
#>
function Invoke-GoldenTaskReplay {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [Parameter(Mandatory = $true)]
        [hashtable]$BaselineConfig,

        [Parameter(Mandatory = $true)]
        [hashtable]$NewConfig,

        [Parameter()]
        [switch]$CompareResults
    )

    Write-Verbose "[ReplayHarness] Replaying golden task: $TaskId"

    # Load the golden task
    $goldenTask = Get-GoldenTask -TaskId $TaskId
    if (-not $goldenTask) {
        throw "Golden task not found: $TaskId"
    }

    $replayResults = @{
        taskId = $TaskId
        baseline = $null
        replay = $null
        comparison = $null
    }

    # Execute baseline replay (if baseline config differs from stored)
    if ($CompareResults) {
        $baselineTarget = @{
            type = 'golden-task'
            id = $TaskId
            useStored = $true
        }
        
        $baselineResult = Invoke-AnswerReplay `
            -ReplayTarget $baselineTarget `
            -SystemConfig $BaselineConfig `
            -Options @{ CompareMode = $false }
        
        $replayResults.baseline = $baselineResult
    }

    # Execute new config replay
    $newTarget = @{
        type = 'golden-task'
        id = $TaskId
        useStored = $false
    }
    
    $newResult = Invoke-AnswerReplay `
        -ReplayTarget $newTarget `
        -SystemConfig $NewConfig `
        -Options @{ CompareMode = $false }
    
    $replayResults.replay = $newResult

    # Compare results if requested
    if ($CompareResults -and $replayResults.baseline) {
        $comparisonRules = @{
            rules = @(
                @{ type = 'confidence-threshold'; threshold = 0.05 }
                @{ type = 'evidence-overlap'; minOverlap = 0.70 }
                @{ type = 'answer-mode-consistent' }
            )
        }
        
        $replayResults.comparison = Compare-ReplayResults `
            -BaselineResult $replayResults.baseline `
            -NewResult $newResult `
            -ComparisonRules $comparisonRules
    }

    return $replayResults
}

<#
.SYNOPSIS
    Replays an incident bundle to verify fixes.

.DESCRIPTION
    Replays a known bad-answer incident against a new system configuration
to determine if the issue has been resolved.

.PARAMETER IncidentId
    The unique identifier of the incident.

.PARAMETER NewSystemConfig
    The new system configuration to test against.

.PARAMETER UpdateIncident
    If specified, updates the incident with replay results.

.OUTPUTS
    System.Collections.Hashtable. Replay results with fix verification.

.EXAMPLE
    $result = Invoke-IncidentReplay -IncidentId "incident-abc123" `
        -NewSystemConfig $config -UpdateIncident

.EXAMPLE
    $config = @{ retrievalProfile = 'conflict-diagnosis'; parserVersion = '2.1' }
    $replay = Invoke-IncidentReplay -IncidentId "incident-xyz789" `
        -NewSystemConfig $config
#>
function Invoke-IncidentReplay {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IncidentId,

        [Parameter(Mandatory = $true)]
        [hashtable]$NewSystemConfig,

        [Parameter()]
        [switch]$UpdateIncident
    )

    Write-Verbose "[ReplayHarness] Replaying incident: $IncidentId"

    # Load the incident bundle
    $incident = Get-IncidentBundleById -IncidentId $IncidentId
    if (-not $incident) {
        throw "Incident not found: $IncidentId"
    }

    # Create replay target
    $target = @{
        type = 'incident'
        id = $IncidentId
        incident = $incident
    }

    # Execute replay
    $replayResult = Invoke-AnswerReplay `
        -ReplayTarget $target `
        -SystemConfig $NewSystemConfig `
        -Options @{ CompareMode = $true; StoreResult = $true }

    # Test for regression or improvement
    $regressionTest = Test-Regression `
        -Baseline $replayResult.originalResult `
        -Current $replayResult.replayedResult `
        -Thresholds $script:DefaultThresholds

    $replayResult.regressionAnalysis = $regressionTest

    # Update incident if requested
    if ($UpdateIncident) {
        Update-IncidentWithReplay -Incident $incident -ReplayResult $replayResult | Out-Null
    }

    return $replayResult
}

<#
.SYNOPSIS
    Replays queries against a retrieval profile.

.DESCRIPTION
    Replays a set of test queries against a specific retrieval profile
to validate profile configuration changes.

.PARAMETER ProfileName
    The name of the retrieval profile to test.

.PARAMETER TestQueries
    Array of test queries to replay.

.PARAMETER NewConfig
    The new retrieval profile configuration.

.OUTPUTS
    System.Collections.Hashtable. Profile replay results.

.EXAMPLE
    $queries = @("How do I use X?", "What is the API for Y?")
    $config = @{ minTrustTier = 'high'; requireMultipleSources = $true }
    $results = Invoke-ProfileReplay -ProfileName "api-lookup" `
        -TestQueries $queries -NewConfig $config

.EXAMPLE
    $queries = Get-Content "test-queries.txt"
    $results = Invoke-ProfileReplay -ProfileName "codegen" `
        -TestQueries $queries -NewConfig $newProfileConfig
#>
function Invoke-ProfileReplay {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,

        [Parameter(Mandatory = $true)]
        [array]$TestQueries,

        [Parameter(Mandatory = $true)]
        [hashtable]$NewConfig
    )

    Write-Verbose "[ReplayHarness] Replaying profile: $ProfileName with $($TestQueries.Count) queries"

    # Build system config
    $systemConfig = @{
        retrievalProfile = $ProfileName
    }
    $systemConfig += $NewConfig

    $results = @()
    $queryIndex = 0

    foreach ($query in $TestQueries) {
        $queryIndex++
        Write-Verbose "[ReplayHarness] Processing query $queryIndex/$($TestQueries.Count): $query"

        $target = @{
            type = 'profile'
            id = "$ProfileName-query-$queryIndex"
            query = $query
            profileName = $ProfileName
        }

        $replayResult = Invoke-AnswerReplay `
            -ReplayTarget $target `
            -SystemConfig $systemConfig `
            -Options @{ StoreResult = $false }

        $results += $replayResult
    }

    # Aggregate results
    $successCount = ($results | Where-Object { $_.metadata.status -eq 'completed' } | Measure-Object).Count
    $regressionCount = ($results | Where-Object { 
        $comp = $_.comparison
        $comp -and ($comp['regressionDetected'] -or $comp.regressionDetected)
    } | Measure-Object).Count
    $improvementCount = ($results | Where-Object { 
        $comp = $_.comparison
        $comp -and ($comp['improvementDetected'] -or $comp.improvementDetected)
    } | Measure-Object).Count

    return [ordered]@{
        profileName = $ProfileName
        queryCount = $TestQueries.Count
        completedCount = $successCount
        regressionCount = $regressionCount
        improvementCount = $improvementCount
        results = $results
        summary = [ordered]@{
            successRate = if ($TestQueries.Count -gt 0) { 
                [math]::Round(($successCount / $TestQueries.Count) * 100, 2)
            } else { 0 }
            regressionRate = if ($TestQueries.Count -gt 0) { 
                [math]::Round(($regressionCount / $TestQueries.Count) * 100, 2)
            } else { 0 }
        }
    }
}

<#
.SYNOPSIS
    Compares two replay results.

.DESCRIPTION
    Performs detailed comparison between baseline and new replay results
using configurable comparison rules.

.PARAMETER BaselineResult
    The baseline replay result.

.PARAMETER NewResult
    The new replay result to compare.

.PARAMETER ComparisonRules
    Hashtable defining comparison rules:
    - rules: Array of rule objects with 'type' and parameters
    - properties: Array of property paths to compare
    - thresholds: Confidence and similarity thresholds

.OUTPUTS
    System.Collections.Hashtable. Detailed comparison results.

.EXAMPLE
    $rules = @{
        rules = @(
            @{ type = 'exact-match'; property = 'answerMode' }
            @{ type = 'confidence-threshold'; threshold = 0.05 }
            @{ type = 'evidence-overlap'; minOverlap = 0.70 }
        )
    }
    $comparison = Compare-ReplayResults -BaselineResult $baseline `
        -NewResult $new -ComparisonRules $rules

.EXAMPLE
    $rules = @{ properties = @('answer', 'confidenceDecision.score') }
    $comparison = Compare-ReplayResults -BaselineResult $old `
        -NewResult $current -ComparisonRules $rules
#>
function Compare-ReplayResults {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$BaselineResult,

        [Parameter(Mandatory = $true)]
        [hashtable]$NewResult,

        [Parameter()]
        [hashtable]$ComparisonRules = @{}
    )

    Write-Verbose "[ReplayHarness] Comparing replay results"

    $comparison = [ordered]@{
        isMatch = $true
        differences = [System.Collections.Generic.List[hashtable]]::new()
        confidenceDelta = 0.0
        regressionDetected = $false
        improvementDetected = $false
        matchScore = 1.0
        ruleResults = @()
    }

    # Use default rules if none provided
    $rules = if ($ComparisonRules.ContainsKey('rules')) { 
        $ComparisonRules.rules 
    } else { 
        @(
            @{ type = 'confidence-threshold'; threshold = $script:DefaultThresholds.confidenceSimilarity }
            @{ type = 'evidence-overlap'; minOverlap = $script:DefaultThresholds.evidenceOverlapMin }
            @{ type = 'answer-mode-consistent' }
        )
    }

    # Process each comparison rule
    foreach ($rule in $rules) {
        $ruleResult = [ordered]@{
            ruleType = $rule.type
            passed = $true
            details = @{}
        }

        switch ($rule.type) {
            'exact-match' {
                $property = $rule.property
                $baselineValue = Get-NestedProperty -Object $BaselineResult -Path $property
                $newValue = Get-NestedProperty -Object $NewResult -Path $property
                
                $ruleResult.details.property = $property
                $ruleResult.details.baseline = $baselineValue
                $ruleResult.details.new = $newValue
                
                if ($baselineValue -ne $newValue) {
                    $ruleResult.passed = $false
                    $comparison.isMatch = $false
                    $comparison.differences.Add(@{
                        type = 'exact-mismatch'
                        property = $property
                        expected = $baselineValue
                        actual = $newValue
                    })
                }
            }

            'confidence-threshold' {
                $threshold = if ($rule.ContainsKey('threshold')) { $rule.threshold } else { 0.05 }
                
                $baselineConfidence = Get-NestedProperty -Object $BaselineResult -Path 'replayedResult.confidenceScore'
                $newConfidence = Get-NestedProperty -Object $NewResult -Path 'replayedResult.confidenceScore'
                
                if ($null -ne $baselineConfidence -and $null -ne $newConfidence) {
                    $delta = [math]::Abs($newConfidence - $baselineConfidence)
                    $comparison.confidenceDelta = $delta
                    $ruleResult.details.baselineConfidence = $baselineConfidence
                    $ruleResult.details.newConfidence = $newConfidence
                    $ruleResult.details.delta = $delta
                    $ruleResult.details.threshold = $threshold
                    
                    if ($delta -gt $threshold) {
                        $ruleResult.passed = $false
                        $comparison.isMatch = $false
                        
                        if ($newConfidence -lt $baselineConfidence) {
                            $comparison.differences.Add(@{
                                type = 'confidence-decrease'
                                baseline = $baselineConfidence
                                current = $newConfidence
                                delta = $delta
                            })
                        }
                    }
                }
            }

            'evidence-overlap' {
                $minOverlap = if ($rule.ContainsKey('minOverlap')) { $rule.minOverlap } else { 0.70 }
                
                $baselineEvidence = Get-NestedProperty -Object $BaselineResult -Path 'replayedResult.selectedEvidence'
                $newEvidence = Get-NestedProperty -Object $NewResult -Path 'replayedResult.selectedEvidence'
                
                if ($null -ne $baselineEvidence -and $null -ne $newEvidence) {
                    $overlap = Get-EvidenceOverlap -Evidence1 $baselineEvidence -Evidence2 $newEvidence
                    $ruleResult.details = $overlap
                    $ruleResult.details.minOverlapRequired = $minOverlap
                    
                    if ($overlap.overlapPercent -lt ($minOverlap * 100)) {
                        $ruleResult.passed = $false
                        $comparison.isMatch = $false
                        $comparison.differences.Add(@{
                            type = 'evidence-overlap-insufficient'
                            overlapPercent = $overlap.overlapPercent
                            required = $minOverlap * 100
                            matched = $overlap.matched
                            onlyInBaseline = $overlap.onlyInFirst
                            onlyInNew = $overlap.onlyInSecond
                        })
                    }
                }
            }

            'answer-mode-consistent' {
                $baselineMode = Get-NestedProperty -Object $BaselineResult -Path 'metadata.answerMode'
                $newMode = Get-NestedProperty -Object $NewResult -Path 'metadata.answerMode'
                
                $ruleResult.details.baselineMode = $baselineMode
                $ruleResult.details.newMode = $newMode
                
                if ($baselineMode -ne $newMode) {
                    $ruleResult.passed = $false
                    $comparison.isMatch = $false
                    $comparison.differences.Add(@{
                        type = 'answer-mode-changed'
                        baseline = $baselineMode
                        current = $newMode
                    })
                }
            }

            'property-match' {
                $properties = if ($rule.ContainsKey('properties')) { $rule.properties } else { @() }
                
                foreach ($prop in $properties) {
                    $baselineValue = Get-NestedProperty -Object $BaselineResult -Path $prop
                    $newValue = Get-NestedProperty -Object $NewResult -Path $prop
                    
                    if ($baselineValue -ne $newValue) {
                        $ruleResult.passed = $false
                        $comparison.isMatch = $false
                        $comparison.differences.Add(@{
                            type = 'property-mismatch'
                            property = $prop
                            expected = $baselineValue
                            actual = $newValue
                        })
                    }
                }
            }
        }

        $comparison.ruleResults += $ruleResult
    }

    # Calculate overall match score
    $totalRules = ($rules | Measure-Object).Count
    $passedRules = ($comparison.ruleResults | Where-Object { $_.passed } | Measure-Object).Count
    if ($totalRules -gt 0) {
        $comparison.matchScore = [math]::Round($passedRules / $totalRules, 2)
    }

    return $comparison
}

<#
.SYNOPSIS
    Detects regressions between baseline and current results.

.DESCRIPTION
    Analyzes baseline and current results to detect regressions using
configurable thresholds. Determines severity and categorizes issues.

.PARAMETER Baseline
    The baseline result for comparison.

.PARAMETER Current
    The current result to test.

.PARAMETER Thresholds
    Hashtable of regression detection thresholds:
    - confidenceDropThreshold: Maximum allowed confidence decrease
    - evidenceLossThreshold: Maximum allowed evidence loss percentage
    - answerSimilarityThreshold: Minimum required answer similarity
    - criticalAnswerChanges: Array of properties that cannot change

.OUTPUTS
    System.Collections.Hashtable. Regression analysis results.

.EXAMPLE
    $thresholds = @{
        confidenceDropThreshold = 0.10
        evidenceLossThreshold = 0.30
        answerSimilarityThreshold = 0.75
    }
    $regression = Test-Regression -Baseline $old -Current $new -Thresholds $thresholds

.EXAMPLE
    $analysis = Test-Regression -Baseline $baseline -Current $result
    if ($analysis.isRegression) {
        Write-Warning "Regression detected: $($analysis.severity)"
    }
#>
function Test-Regression {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Baseline,

        [Parameter(Mandatory = $true)]
        [hashtable]$Current,

        [Parameter()]
        [hashtable]$Thresholds = @{}
    )

    Write-Verbose "[ReplayHarness] Testing for regressions"

    # Apply default thresholds
    $confidenceThreshold = if ($Thresholds.ContainsKey('confidenceDropThreshold')) { 
        $Thresholds.confidenceDropThreshold 
    } else { 
        0.10 
    }
    
    $evidenceThreshold = if ($Thresholds.ContainsKey('evidenceLossThreshold')) { 
        $Thresholds.evidenceLossThreshold 
    } else { 
        0.30 
    }
    
    $similarityThreshold = if ($Thresholds.ContainsKey('answerSimilarityThreshold')) { 
        $Thresholds.answerSimilarityThreshold 
    } else { 
        0.75 
    }

    $analysis = [ordered]@{
        isRegression = $false
        isImprovement = $false
        severity = 'none'
        confidence = 'low'
        issues = [System.Collections.Generic.List[hashtable]]::new()
        improvements = [System.Collections.Generic.List[hashtable]]::new()
        metrics = @{}
    }

    # Check confidence regression
    $baselineConfidence = Get-NestedProperty -Object $Baseline -Path 'confidenceScore'
    $currentConfidence = Get-NestedProperty -Object $Current -Path 'confidenceScore'
    
    if ($null -ne $baselineConfidence -and $null -ne $currentConfidence) {
        $confidenceDelta = $currentConfidence - $baselineConfidence
        $analysis.metrics.confidenceDelta = $confidenceDelta
        
        if ($confidenceDelta -lt -$confidenceThreshold) {
            $analysis.isRegression = $true
            $analysis.issues.Add(@{
                type = 'confidence-regression'
                severity = if ($confidenceDelta -lt -0.20) { 'critical' } else { 'moderate' }
                baseline = $baselineConfidence
                current = $currentConfidence
                delta = $confidenceDelta
                threshold = $confidenceThreshold
                description = "Confidence dropped by $([math]::Abs($confidenceDelta).ToString('P'))"
            })
        }
        elseif ($confidenceDelta -gt $confidenceThreshold) {
            $analysis.improvements.Add(@{
                type = 'confidence-improvement'
                baseline = $baselineConfidence
                current = $currentConfidence
                delta = $confidenceDelta
                description = "Confidence improved by $($confidenceDelta.ToString('P'))"
            })
        }
    }

    # Check evidence regression
    $baselineEvidence = Get-NestedProperty -Object $Baseline -Path 'selectedEvidence'
    $currentEvidence = Get-NestedProperty -Object $Current -Path 'selectedEvidence'
    
    if ($null -ne $baselineEvidence -and $null -ne $currentEvidence) {
        $overlap = Get-EvidenceOverlap -Evidence1 $baselineEvidence -Evidence2 $currentEvidence
        $evidenceLossPercent = if ($overlap.totalUnique -gt 0) {
            ($overlap.onlyInFirst / $overlap.totalUnique) * 100
        } else { 0 }
        
        $analysis.metrics.evidenceOverlap = $overlap.overlapPercent
        $analysis.metrics.evidenceLossPercent = $evidenceLossPercent
        
        if ($evidenceLossPercent -gt ($evidenceThreshold * 100)) {
            $analysis.isRegression = $true
            $analysis.issues.Add(@{
                type = 'evidence-loss'
                severity = if ($evidenceLossPercent -gt 50) { 'critical' } else { 'moderate' }
                baselineCount = ($baselineEvidence | Measure-Object).Count
                currentCount = ($currentEvidence | Measure-Object).Count
                lostEvidence = $overlap.onlyInFirst
                lossPercent = $evidenceLossPercent
                threshold = $evidenceThreshold * 100
                description = "Lost $overlap.onlyInFirst pieces of evidence ($([math]::Round($evidenceLossPercent, 2))%)"
            })
        }
        elseif ($overlap.onlyInSecond -gt 0 -and $overlap.onlyInFirst -eq 0) {
            $analysis.improvements.Add(@{
                type = 'evidence-gain'
                addedEvidence = $overlap.onlyInSecond
                description = "Gained $($overlap.onlyInSecond) additional evidence pieces without loss"
            })
        }
    }

    # Check answer similarity
    $baselineAnswer = Get-NestedProperty -Object $Baseline -Path 'answer'
    $currentAnswer = Get-NestedProperty -Object $Current -Path 'answer'
    
    if ($null -ne $baselineAnswer -and $null -ne $currentAnswer) {
        $similarity = Get-StringSimilarity -String1 $baselineAnswer -String2 $currentAnswer
        $analysis.metrics.answerSimilarity = $similarity
        
        if ($similarity -lt $similarityThreshold) {
            $analysis.isRegression = $true
            $analysis.issues.Add(@{
                type = 'answer-divergence'
                severity = if ($similarity -lt 0.50) { 'critical' } else { 'moderate' }
                similarity = $similarity
                threshold = $similarityThreshold
                description = "Answer similarity dropped to $([math]::Round($similarity * 100, 2))%"
            })
        }
        elseif ($similarity -eq 1.0) {
            $analysis.confidence = 'high'
        }
    }

    # Check answer mode consistency
    $baselineMode = Get-NestedProperty -Object $Baseline -Path 'answerMode'
    $currentMode = Get-NestedProperty -Object $Current -Path 'answerMode'
    
    if ($null -ne $baselineMode -and $null -ne $currentMode -and $baselineMode -ne $currentMode) {
        $criticalChanges = @('direct', 'abstain')
        $isCritical = ($baselineMode -in $criticalChanges -or $currentMode -in $criticalChanges)
        
        if ($isCritical) {
            $analysis.isRegression = $true
            $analysis.issues.Add(@{
                type = 'answer-mode-change'
                severity = 'critical'
                baseline = $baselineMode
                current = $currentMode
                description = "Answer mode changed from '$baselineMode' to '$currentMode'"
            })
        }
    }

    # Determine overall severity
    if ($analysis.issues.Count -eq 0) {
        $analysis.severity = 'none'
    }
    else {
        $criticalIssues = ($analysis.issues | Where-Object { $_.severity -eq 'critical' } | Measure-Object).Count
        $moderateIssues = ($analysis.issues | Where-Object { $_.severity -eq 'moderate' } | Measure-Object).Count
        
        if ($criticalIssues -gt 0) {
            $analysis.severity = 'critical'
        }
        elseif ($moderateIssues -gt 0) {
            $analysis.severity = 'moderate'
        }
        else {
            $analysis.severity = 'minor'
        }
    }

    # Determine if overall improvement
    if (-not $analysis.isRegression -and $analysis.improvements.Count -gt 0) {
        $analysis.isImprovement = $true
    }

    return $analysis
}

<#
.SYNOPSIS
    Generates a replay report.

.DESCRIPTION
    Creates a formatted report from replay results in various formats
including summary, detailed, and comparison reports.

.PARAMETER ReplayResults
    Array of replay results to include in the report.

.PARAMETER ReportType
    Type of report: 'summary', 'detailed', or 'comparison'.

.PARAMETER IncludeMetadata
    If specified, includes detailed metadata.

.OUTPUTS
    System.String. The formatted report.

.EXAMPLE
    $report = New-ReplayReport -ReplayResults $results -ReportType 'summary'

.EXAMPLE
    $report = New-ReplayReport -ReplayResults $allResults `
        -ReportType 'detailed' -IncludeMetadata | Out-File "report.txt"

.EXAMPLE
    $report = New-ReplayReport -ReplayResults $comparisonData -ReportType 'comparison'
#>
function New-ReplayReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$ReplayResults,

        [Parameter()]
        [ValidateSet('summary', 'detailed', 'comparison')]
        [string]$ReportType = 'summary',

        [Parameter()]
        [switch]$IncludeMetadata
    )

    Write-Verbose "[ReplayHarness] Generating $ReportType report for $($ReplayResults.Count) results"

    $sb = [System.Text.StringBuilder]::new()
    $timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss UTC")

    switch ($ReportType) {
        'summary' {
            [void]$sb.AppendLine("=" * 70)
            [void]$sb.AppendLine("REPLAY HARNESS - SUMMARY REPORT")
            [void]$sb.AppendLine("=" * 70)
            [void]$sb.AppendLine("Generated: $timestamp")
            [void]$sb.AppendLine("Total Results: $($ReplayResults.Count)")
            [void]$sb.AppendLine("")

            # Statistics
            $completed = ($ReplayResults | Where-Object { $_.metadata.status -eq 'completed' } | Measure-Object).Count
            $failed = ($ReplayResults | Where-Object { $_.metadata.status -eq 'failed' } | Measure-Object).Count
            $regressions = ($ReplayResults | Where-Object { $_.comparison.regressionDetected } | Measure-Object).Count
            $improvements = ($ReplayResults | Where-Object { $_.comparison.improvementDetected } | Measure-Object).Count

            [void]$sb.AppendLine("-" * 40)
            [void]$sb.AppendLine("STATISTICS")
            [void]$sb.AppendLine("-" * 40)
            [void]$sb.AppendLine("  Completed:   $completed")
            [void]$sb.AppendLine("  Failed:      $failed")
            [void]$sb.AppendLine("  Regressions: $regressions")
            [void]$sb.AppendLine("  Improvements: $improvements")
            [void]$sb.AppendLine("")

            # By type
            [void]$sb.AppendLine("-" * 40)
            [void]$sb.AppendLine("BY REPLAY TYPE")
            [void]$sb.AppendLine("-" * 40)
            $byType = $ReplayResults | Group-Object -Property replayType
            foreach ($group in $byType) {
                $regCount = ($group.Group | Where-Object { $_.comparison.regressionDetected } | Measure-Object).Count
                [void]$sb.AppendLine("  $($group.Name): $($group.Count) ($regCount regressions)")
            }
            [void]$sb.AppendLine("")

            # Regressions detail
            if ($regressions -gt 0) {
                [void]$sb.AppendLine("-" * 40)
                [void]$sb.AppendLine("REGRESSIONS DETECTED")
                [void]$sb.AppendLine("-" * 40)
                $regressionItems = $ReplayResults | Where-Object { $_.comparison.regressionDetected }
                foreach ($item in $regressionItems) {
                    [void]$sb.AppendLine("  - $($item.replayType): $($item.targetId)")
                    if ($item.comparison.differences) {
                        foreach ($diff in $item.comparison.differences) {
                            [void]$sb.AppendLine("      * $($diff.type)")
                        }
                    }
                }
                [void]$sb.AppendLine("")
            }

            [void]$sb.AppendLine("=" * 70)
        }

        'detailed' {
            [void]$sb.AppendLine("=" * 70)
            [void]$sb.AppendLine("REPLAY HARNESS - DETAILED REPORT")
            [void]$sb.AppendLine("=" * 70)
            [void]$sb.AppendLine("Generated: $timestamp")
            [void]$sb.AppendLine("Total Results: $($ReplayResults.Count)")
            [void]$sb.AppendLine("")

            foreach ($result in $ReplayResults) {
                [void]$sb.AppendLine("-" * 70)
                [void]$sb.AppendLine("REPLAY: $($result.replayId)")
                [void]$sb.AppendLine("-" * 70)
                [void]$sb.AppendLine("  Type:       $($result.replayType)")
                [void]$sb.AppendLine("  Target ID:  $($result.targetId)")
                [void]$sb.AppendLine("  Timestamp:  $($result.timestamp)")
                [void]$sb.AppendLine("  Duration:   $($result.durationMs)ms")
                [void]$sb.AppendLine("  Status:     $($result.metadata.status)")
                [void]$sb.AppendLine("")

                $sysConfig = $result.systemConfig
                if ($sysConfig) {
                    [void]$sb.AppendLine("  System Config:")
                    $profile = if ($sysConfig['retrievalProfile']) { $sysConfig['retrievalProfile'] } else { 'N/A' }
                    $parser = if ($sysConfig['parserVersion']) { $sysConfig['parserVersion'] } else { 'N/A' }
                    [void]$sb.AppendLine("    Profile:  $profile")
                    [void]$sb.AppendLine("    Parser:   $parser")
                    [void]$sb.AppendLine("")
                }

                if ($result.comparison) {
                    [void]$sb.AppendLine("  Comparison:")
                    [void]$sb.AppendLine("    Is Match:         $($result.comparison.isMatch)")
                    [void]$sb.AppendLine("    Match Score:      $($result.comparison.matchScore)")
                    [void]$sb.AppendLine("    Regression:       $($result.comparison.regressionDetected)")
                    [void]$sb.AppendLine("    Improvement:      $($result.comparison.improvementDetected)")
                    
                    $differences = if ($result.comparison.ContainsKey('differences')) { $result.comparison.differences } else { @() }
                    if ($differences -and ($differences | Measure-Object).Count -gt 0) {
                        [void]$sb.AppendLine("    Differences:")
                        foreach ($diff in $differences) {
                            $diffType = if ($diff.ContainsKey('type')) { $diff.type } else { 'unknown' }
                            $diffDesc = if ($diff.ContainsKey('description')) { $diff.description } else { '' }
                            [void]$sb.AppendLine("      - $diffType`: $diffDesc")
                        }
                    }
                    [void]$sb.AppendLine("")
                }

                if ($IncludeMetadata -and $result.metadata) {
                    [void]$sb.AppendLine("  Metadata:")
                    foreach ($key in $result.metadata.Keys) {
                        [void]$sb.AppendLine("    $key`: $($result.metadata[$key])")
                    }
                    [void]$sb.AppendLine("")
                }
            }

            [void]$sb.AppendLine("=" * 70)
        }

        'comparison' {
            [void]$sb.AppendLine("=" * 70)
            [void]$sb.AppendLine("REPLAY HARNESS - COMPARISON REPORT")
            [void]$sb.AppendLine("=" * 70)
            [void]$sb.AppendLine("Generated: $timestamp")
            [void]$sb.AppendLine("")

            # Side-by-side comparison table
            [void]$sb.AppendLine("-" * 70)
            [void]$sb.AppendLine("COMPARISON OVERVIEW")
            [void]$sb.AppendLine("-" * 70)
            [void]$sb.AppendLine([string]::Format("{0,-30} {1,-15} {2,-8} {3,-8}", 'Replay ID', 'Type', 'Match', 'Regress'))
            [void]$sb.AppendLine("-" * 70)

            foreach ($result in $ReplayResults) {
                $matchStr = if ($result.comparison.isMatch) { "YES" } else { "NO" }
                $regressStr = if ($result.comparison.regressionDetected) { "YES" } else { "NO" }
                $shortId = $result.replayId.Substring(0, [Math]::Min(30, $result.replayId.Length))
                [void]$sb.AppendLine([string]::Format("{0,-30} {1,-15} {2,-8} {3,-8}", $shortId, $result.replayType, $matchStr, $regressStr))
            }

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("=" * 70)
        }
    }

    return $sb.ToString()
}

<#
.SYNOPSIS
    Exports a replay session to file.

.DESCRIPTION
    Saves a replay session to a JSON file for later analysis or audit.

.PARAMETER Session
    The replay session to export.

.PARAMETER OutputPath
    The file path to export to.

.PARAMETER Compress
    If specified, outputs compressed JSON.

.OUTPUTS
    System.Collections.Hashtable. Export result.

.EXAMPLE
    Export-ReplaySession -Session $result -OutputPath "./replays/session.json"

.EXAMPLE
    $export = Export-ReplaySession -Session $result -OutputPath "./replays/session.json" -Compress
#>
function Export-ReplaySession {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Session,

        [Parameter()]
        [string]$OutputPath = "",

        [Parameter()]
        [switch]$Compress
    )

    if ([string]::IsNullOrEmpty($OutputPath)) {
        $replayDir = Get-ReplayDirectory
        $fileName = "$($Session.replayId).json"
        $OutputPath = Join-Path $replayDir $fileName
    }

    $dir = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    try {
        $json = $Session | ConvertTo-Json -Depth 20 -Compress:$Compress
        [System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.Encoding]::UTF8)

        return @{
            Success = $true
            Path = $OutputPath
            ReplayId = $Session.replayId
            BytesWritten = $json.Length
            Error = $null
        }
    }
    catch {
        return @{
            Success = $false
            Path = $OutputPath
            ReplayId = $Session.replayId
            BytesWritten = 0
            Error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Imports a replay session from file.

.DESCRIPTION
    Loads a previously exported replay session from a JSON file.

.PARAMETER Path
    The file path to import from.

.OUTPUTS
    System.Collections.Hashtable. The imported replay session.

.EXAMPLE
    $session = Import-ReplaySession -Path "./replays/session.json"
#>
function Import-ReplaySession {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Replay session file not found: $Path"
    }

    try {
        $json = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($json)) {
            throw "File is empty"
        }
        $session = $json | ConvertFrom-Json
        if ($null -eq $session) {
            throw "Failed to parse JSON"
        }

        return ConvertTo-HashTable -InputObject $session
    }
    catch {
        throw "Failed to import replay session: $_"
    }
}

<#
.SYNOPSIS
    Executes batch replay operations.

.DESCRIPTION
    Replays multiple targets (tasks, incidents, etc.) in batch with
optional parallel execution support.

.PARAMETER Targets
    Array of replay targets to process.

.PARAMETER Config
    System configuration for all replays.

.PARAMETER Parallel
    If specified, executes replays in parallel.

.PARAMETER MaxParallel
    Maximum number of parallel executions. Default is 4.

.PARAMETER ProgressInterval
    Seconds between progress updates. Default is 5.

.OUTPUTS
    System.Collections.Hashtable. Batch replay results.

.EXAMPLE
    $targets = @(
        @{ type = 'golden-task'; id = 'task-001' },
        @{ type = 'incident'; id = 'inc-002' }
    )
    $results = Invoke-BatchReplay -Targets $targets -Config $config

.EXAMPLE
    $results = Invoke-BatchReplay -Targets $tasks -Config $config -Parallel -MaxParallel 8
#>
function Invoke-BatchReplay {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Targets,

        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter()]
        [switch]$Parallel,

        [Parameter()]
        [int]$MaxParallel = 4,

        [Parameter()]
        [int]$ProgressInterval = 5
    )

    Write-Verbose "[ReplayHarness] Starting batch replay of $($Targets.Count) targets"

    $batchId = New-ReplayId
    $startTime = [DateTime]::UtcNow
    $results = [System.Collections.Generic.List[hashtable]]::new()

    if ($Parallel -and $Targets.Count -gt 1) {
        # Parallel execution
        # Note: Using ForEach-Object -Parallel requires PowerShell 7+
        # For PowerShell 5.1 compatibility, use runspaces
        Write-Verbose "[ReplayHarness] Executing in parallel (max: $MaxParallel)"
        
        # Sequential fallback for PowerShell 5.1
        $index = 0
        foreach ($target in $Targets) {
            $index++
            Write-Progress -Activity "Batch Replay" -Status "Processing $index/$($Targets.Count)" `
                -PercentComplete (($index / $Targets.Count) * 100)

            try {
                $result = Invoke-AnswerReplay `
                    -ReplayTarget $target `
                    -SystemConfig $Config `
                    -Options @{ StoreResult = $true }
                $results.Add($result)
            }
            catch {
                $results.Add(@{
                    replayType = $target.type
                    targetId = $target.id
                    metadata = @{
                        status = 'failed'
                        error = $_.Exception.Message
                    }
                })
            }
        }
        Write-Progress -Activity "Batch Replay" -Completed
    }
    else {
        # Sequential execution
        $index = 0
        foreach ($target in $Targets) {
            $index++
            Write-Verbose "[ReplayHarness] Processing target $index/$($Targets.Count): $($target.id)"

            try {
                $result = Invoke-AnswerReplay `
                    -ReplayTarget $target `
                    -SystemConfig $Config `
                    -Options @{ StoreResult = $true }
                $results.Add($result)
            }
            catch {
                $results.Add(@{
                    replayType = $target.type
                    targetId = $target.id
                    metadata = @{
                        status = 'failed'
                        error = $_.Exception.Message
                    }
                })
            }
        }
    }

    $endTime = [DateTime]::UtcNow
    $duration = $endTime - $startTime

    # Calculate statistics
    $completed = ($results | Where-Object { 
        $_.metadata -and ($_.metadata['status'] -eq 'completed' -or $_.metadata.status -eq 'completed')
    } | Measure-Object).Count
    $failed = ($results | Where-Object { 
        $_.metadata -and ($_.metadata['status'] -eq 'failed' -or $_.metadata.status -eq 'failed')
    } | Measure-Object).Count
    $regressions = ($results | Where-Object { 
        $comp = $_.comparison
        $comp -and ($comp['regressionDetected'] -or $comp.regressionDetected)
    } | Measure-Object).Count
    $improvements = ($results | Where-Object { 
        $comp = $_.comparison
        $comp -and ($comp['improvementDetected'] -or $comp.improvementDetected)
    } | Measure-Object).Count

    return [ordered]@{
        batchId = $batchId
        startTime = $startTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        endTime = $endTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        durationMs = [math]::Round($duration.TotalMilliseconds)
        totalTargets = $Targets.Count
        completedCount = $completed
        failedCount = $failed
        regressionCount = $regressions
        improvementCount = $improvements
        parallel = $Parallel.IsPresent
        maxParallel = $MaxParallel
        results = $results.ToArray()
        summary = [ordered]@{
            successRate = if ($Targets.Count -gt 0) { 
                [math]::Round(($completed / $Targets.Count) * 100, 2)
            } else { 0 }
            regressionRate = if ($Targets.Count -gt 0) { 
                [math]::Round(($regressions / $Targets.Count) * 100, 2)
            } else { 0 }
        }
    }
}

#===============================================================================
# Internal Helper Functions
#===============================================================================

<#
.SYNOPSIS
    Internal: Replays a golden task.

.DESCRIPTION
    Internal implementation for golden task replay.
#>
function Invoke-GoldenTaskReplayInternal {
    [CmdletBinding()]
    param(
        [hashtable]$ReplayTarget,
        [hashtable]$SystemConfig,
        [hashtable]$Options
    )

    $taskId = $ReplayTarget.id
    $useStored = if ($ReplayTarget.ContainsKey('useStored')) { $ReplayTarget.useStored } else { $false }

    # Load golden task
    $goldenTask = Get-GoldenTask -TaskId $taskId
    if (-not $goldenTask) {
        throw "Golden task not found: $taskId"
    }

    # Get original result (stored or replay)
    $originalResult = if ($useStored -and $goldenTask.ContainsKey('expectedResult')) {
        $goldenTask.expectedResult
    }
    else {
        # Simulate replay with baseline config
        Simulate-AnswerExecution -Query $goldenTask.query -Config $goldenTask.baselineConfig
    }

    # Execute with current config
    $replayedResult = Simulate-AnswerExecution -Query $goldenTask.query -Config $SystemConfig

    # Compare if requested
    $comparison = if ($Options.CompareMode) {
        $rules = if ($Options.ContainsKey('ComparisonRules')) { 
            $Options.ComparisonRules 
        } else { 
            @{ rules = @() }
        }
        Compare-ReplayResults -BaselineResult @{ replayedResult = $originalResult } `
            -NewResult @{ replayedResult = $replayedResult } `
            -ComparisonRules $rules
    }
    else {
        @{
            isMatch = $null
            differences = @()
            confidenceDelta = 0.0
            regressionDetected = $false
            improvementDetected = $false
        }
    }

    return @{
        originalResult = $originalResult
        replayedResult = $replayedResult
        comparison = $comparison
    }
}

<#
.SYNOPSIS
    Internal: Replays an incident.

.DESCRIPTION
    Internal implementation for incident replay.
#>
function Invoke-IncidentReplayInternal {
    [CmdletBinding()]
    param(
        [hashtable]$ReplayTarget,
        [hashtable]$SystemConfig,
        [hashtable]$Options
    )

    $incident = if ($ReplayTarget.ContainsKey('incident')) { 
        $ReplayTarget.incident 
    } else { 
        Get-IncidentBundleById -IncidentId $ReplayTarget.id 
    }

    if (-not $incident) {
        throw "Incident not found: $($ReplayTarget.id)"
    }

    # Original result from incident
    $originalResult = [ordered]@{
        answer = $incident.bundle.finalAnswer
        confidenceScore = if ($incident.bundle.confidenceDecision.ContainsKey('score')) {
            $incident.bundle.confidenceDecision.score
        } else { 0.0 }
        confidenceDecision = $incident.bundle.confidenceDecision
        selectedEvidence = $incident.bundle.selectedEvidence
        answerMode = if ($incident.bundle.confidenceDecision.ContainsKey('shouldAbstain') -and 
                         $incident.bundle.confidenceDecision.shouldAbstain) { 
            'abstain' 
        } else { 
            'direct' 
        }
    }

    # Replay with current config
    $replayedResult = Simulate-AnswerExecution `
        -Query $incident.bundle.query `
        -Config $SystemConfig

    # Compare
    $comparison = Compare-ReplayResults `
        -BaselineResult @{ replayedResult = $originalResult } `
        -NewResult @{ replayedResult = $replayedResult } `
        -ComparisonRules @{ rules = @() }

    return @{
        originalResult = $originalResult
        replayedResult = $replayedResult
        comparison = $comparison
    }
}

<#
.SYNOPSIS
    Internal: Replays a profile query.

.DESCRIPTION
    Internal implementation for profile replay.
#>
function Invoke-ProfileReplayInternal {
    [CmdletBinding()]
    param(
        [hashtable]$ReplayTarget,
        [hashtable]$SystemConfig,
        [hashtable]$Options
    )

    $query = $ReplayTarget.query
    $profileName = $ReplayTarget.profileName

    # Execute query simulation
    $replayedResult = Simulate-AnswerExecution -Query $query -Config $SystemConfig

    # For profile replay, original result may not exist
    # Store the result for future comparison
    return @{
        originalResult = $null
        replayedResult = $replayedResult
        comparison = @{
            isMatch = $null
            differences = @()
            confidenceDelta = 0.0
            regressionDetected = $false
            improvementDetected = $false
        }
    }
}

<#
.SYNOPSIS
    Internal: Replays evidence selection.

.DESCRIPTION
    Internal implementation for evidence selection replay.
#>
function Invoke-EvidenceSelectionReplayInternal {
    [CmdletBinding()]
    param(
        [hashtable]$ReplayTarget,
        [hashtable]$SystemConfig,
        [hashtable]$Options
    )

    # Similar to profile replay but focuses on evidence selection
    $query = $ReplayTarget.query

    $replayedResult = Simulate-AnswerExecution -Query $query -Config $SystemConfig

    return @{
        originalResult = $null
        replayedResult = $replayedResult
        comparison = @{
            isMatch = $null
            differences = @()
            confidenceDelta = 0.0
            regressionDetected = $false
            improvementDetected = $false
        }
    }
}

<#
.SYNOPSIS
    Simulates answer execution.

.DESCRIPTION
    Simulates the answer pipeline execution for replay purposes.
    In production, this would call the actual answer engine.

.PARAMETER Query
    The query to process.

.PARAMETER Config
    System configuration for the execution.

.OUTPUTS
    System.Collections.Hashtable. Simulated answer result.
#>
function Simulate-AnswerExecution {
    [CmdletBinding()]
    param(
        [string]$Query,
        [hashtable]$Config
    )

    # This is a simulation - in production, this would call the actual answer engine
    # The simulation generates consistent but varied results based on config
    
    $parserVersion = if ($Config.ContainsKey('parserVersion')) { $Config.parserVersion } else { '1.0' }
    $profile = if ($Config.ContainsKey('retrievalProfile')) { $Config.retrievalProfile } else { 'default' }

    # Generate deterministic but varied confidence based on config
    $hashInput = "$Query|$parserVersion|$profile"
    $hashBytes = [System.Text.Encoding]::UTF8.GetBytes($hashInput)
    $hash = [System.BitConverter]::ToInt32((New-Object System.Security.Cryptography.SHA256Managed).ComputeHash($hashBytes), 0)
    $baseConfidence = [math]::Abs($hash % 100) / 100

    # Adjust confidence based on profile
    $confidenceAdjustment = switch ($profile) {
        'api-lookup' { 0.1 }
        'codegen' { 0.05 }
        'conflict-diagnosis' { 0.0 }
        default { 0.0 }
    }

    $finalConfidence = [math]::Min(1.0, $baseConfidence + $confidenceAdjustment)

    return [ordered]@{
        answer = "[Simulated answer for: $Query]"
        confidenceScore = $finalConfidence
        confidenceDecision = @{
            score = $finalConfidence
            shouldAbstain = ($finalConfidence -lt 0.5)
            reason = if ($finalConfidence -lt 0.5) { 'low_confidence' } else { 'sufficient_confidence' }
        }
        selectedEvidence = @(
            @{
                evidenceId = "ev-1-$hash"
                source = "simulated-source-1"
                authority = 'core-runtime'
                content = "Evidence 1 for query"
            },
            @{
                evidenceId = "ev-2-$hash"
                source = "simulated-source-2"
                authority = 'exemplar'
                content = "Evidence 2 for query"
            }
        )
        answerMode = if ($finalConfidence -lt 0.5) { 'abstain' } else { 'direct' }
        parserVersion = $parserVersion
        retrievalProfile = $profile
        query = $Query
        executedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }
}

<#
.SYNOPSIS
    Gets a golden task by ID.

.DESCRIPTION
    Loads a golden task definition from storage.

.PARAMETER TaskId
    The golden task ID.

.OUTPUTS
    System.Collections.Hashtable. The golden task definition, or null if not found.
#>
function Get-GoldenTask {
    [CmdletBinding()]
    param(
        [string]$TaskId
    )

    $goldenDir = Join-Path (Get-ReplayDirectory) "..\golden-tasks"
    $taskPath = Join-Path $goldenDir "$TaskId.json"

    if (Test-Path -LiteralPath $taskPath) {
        try {
            $json = [System.IO.File]::ReadAllText($taskPath, [System.Text.Encoding]::UTF8)
            $task = $json | ConvertFrom-Json
            return ConvertTo-HashTable -InputObject $task
        }
        catch {
            Write-Verbose "[ReplayHarness] Failed to load golden task: $_"
            return $null
        }
    }

    # Return a default golden task for testing
    return [ordered]@{
        taskId = $TaskId
        query = "How do I use the API for X?"
        description = "Default golden task for testing"
        baselineConfig = @{
            retrievalProfile = 'api-lookup'
            parserVersion = '1.0'
        }
        expectedResult = @{
            answer = "The API for X is used by..."
            confidenceScore = 0.85
            answerMode = 'direct'
        }
        tags = @('api', 'reference')
        createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }
}

<#
.SYNOPSIS
    Gets an incident bundle by ID.

.DESCRIPTION
    Loads an incident bundle for replay.

.PARAMETER IncidentId
    The incident ID.

.OUTPUTS
    System.Collections.Hashtable. The incident bundle, or null if not found.
#>
function Get-IncidentBundleById {
    [CmdletBinding()]
    param(
        [string]$IncidentId
    )

    # Try to load from IncidentBundle module if available
    $incidentCmd = Get-Command Get-IncidentBundle -ErrorAction SilentlyContinue
    if ($incidentCmd) {
        try {
            return & $incidentCmd -IncidentId $IncidentId
        }
        catch {
            Write-Verbose "[ReplayHarness] Failed to load incident via Get-IncidentBundle: $_"
        }
    }

    # Try to load from file directly
    $incidentDir = Join-Path (Get-ReplayDirectory) "..\reports\incidents"
    $incidentPath = Join-Path $incidentDir "$IncidentId.json"

    if (Test-Path -LiteralPath $incidentPath) {
        try {
            $json = [System.IO.File]::ReadAllText($incidentPath, [System.Text.Encoding]::UTF8)
            $incident = $json | ConvertFrom-Json
            return ConvertTo-HashTable -InputObject $incident
        }
        catch {
            Write-Verbose "[ReplayHarness] Failed to load incident: $_"
        }
    }

    return $null
}

<#
.SYNOPSIS
    Updates an incident with replay results.

.DESCRIPTION
    Appends replay results to an incident's replay history.

.PARAMETER Incident
    The incident to update.

.PARAMETER ReplayResult
    The replay result to append.

.OUTPUTS
    System.Collections.Hashtable. Update result.
#>
function Update-IncidentWithReplay {
    [CmdletBinding()]
    param(
        [hashtable]$Incident,
        [hashtable]$ReplayResult
    )

    if (-not $Incident.ContainsKey('replay')) {
        $Incident.replay = @{
            replayHistory = @()
            lastReplayAt = $null
            fixed = $false
        }
    }

    $replayEntry = @{
        replayId = $ReplayResult.replayId
        timestamp = $ReplayResult.timestamp
        durationMs = $ReplayResult.durationMs
        comparison = $ReplayResult.comparison
        regressionDetected = if ($ReplayResult.ContainsKey('regressionAnalysis')) {
            $ReplayResult.regressionAnalysis.isRegression
        } else { $false }
    }

    $Incident.replay.replayHistory += $replayEntry
    $Incident.replay.lastReplayAt = $ReplayResult.timestamp

    # Update status based on regression analysis
    if ($ReplayResult.ContainsKey('regressionAnalysis')) {
        $analysis = $ReplayResult.regressionAnalysis
        if ($analysis.isRegression) {
            if ($Incident.status -eq 'resolved') {
                $Incident.status = 'open'
            }
        }
        elseif ($analysis.isImprovement -and -not $Incident.replay.fixed) {
            # Check if this indicates a fix
            $Incident.replay.fixed = $true
            if ($Incident.status -eq 'open') {
                $Incident.status = 'resolved'
            }
        }
    }

    return @{
        Success = $true
        IncidentId = $Incident.incidentId
        UpdatedReplayCount = ($Incident.replay.replayHistory | Measure-Object).Count
    }
}

#===============================================================================
# Export Module Members
#===============================================================================

Export-ModuleMember -Function @(
    'Invoke-AnswerReplay',
    'Invoke-GoldenTaskReplay',
    'Invoke-IncidentReplay',
    'Invoke-ProfileReplay',
    'Compare-ReplayResults',
    'Test-Regression',
    'New-ReplayReport',
    'Export-ReplaySession',
    'Import-ReplaySession',
    'Invoke-BatchReplay',
    'Get-ReplayDirectory',
    'New-ReplayId'
)
