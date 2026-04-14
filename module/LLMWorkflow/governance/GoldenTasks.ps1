#Requires -Version 5.1
<#
.SYNOPSIS
    Golden Tasks Evaluation Module for LLM Workflow Platform - Phase 6

.DESCRIPTION
    Implements property-based evaluation of LLM workflow tasks against known-good
    reference tasks ("golden tasks"). This module provides:
    
    - Golden task definition and management
    - Property-based validation (not exact text matching)
    - Historical result tracking and trending
    - Pack-specific predefined golden tasks (30 total: 10 per pack)
    - Suite management for batch evaluation
    
    Golden tasks reflect real work scenarios:
    - Generate minimal plugin skeleton with one command and one parameter
    - Diagnose whether two plugins conflict and cite touched methods
    - Answer how a project-local plugin patches a specific engine surface
    - Extract all notetags from a source repo
    - Compare a public pattern to a private project implementation

    Predefined Tasks by Pack:
    
    RPG Maker MZ (10 tasks):
    - Plugin skeleton generation
    - Plugin conflict diagnosis
    - Notetag extraction
    - Engine surface patch analysis
    - Command alias detection
    - Plugin parameter validation
    - Event script conversion
    - Animation sequence generation
    - Save system customization
    - Menu scene extension
    
    Godot Engine (10 tasks):
    - GDScript class generation
    - Signal connection setup
    - Autoload (singleton) setup
    - Scene inheritance pattern
    - Resource preloading
    - Custom node creation
    - Editor plugin development
    - Shader material setup
    - Input action mapping
    - Multiplayer networking pattern
    
    Blender Engine (10 tasks):
    - Operator registration
    - Geometry nodes code
    - Addon manifest creation
    - Panel layout design
    - Property group definition
    - Material node setup
    - Rigging automation
    - Render pipeline configuration
    - Import/export operator
    - Custom keymap binding

    API Reverse Tooling Pack (10 tasks):
    - API endpoint discovery
    - Schema inference from traffic
    - OpenAPI spec generation
    - Authentication pattern detection
    - GraphQL introspection
    - gRPC proto reconstruction
    - Response validation
    - Rate limit analysis
    - Error pattern recognition
    - API changelog detection

    Notebook/Data Workflow Pack (10 tasks):
    - Notebook version control
    - Cell output caching
    - Data lineage tracking
    - Pipeline dependency graph
    - Data validation rules
    - Visualization generation
    - Dataset profiling
    - Feature engineering pipeline
    - Model training tracking
    - Experiment comparison

    Agent Simulation Pack (10 tasks):
    - Multi-agent setup
    - Reward function design
    - Trajectory analysis
    - A/B testing framework
    - Environment configuration
    - Agent behavior validation
    - Policy optimization
    - Simulation replay
    - Metrics collection
    - Agent collaboration patterns

.NOTES
    Version:        1.0.0
    Author:         LLM Workflow Platform
    Creation Date:  2026-04-12
    License:        MIT

.EXAMPLE
    # Create a new golden task
    $task = New-GoldenTask -TaskId "gt-rpgmaker-001" -Name "Plugin skeleton" `
        -PackId "rpgmaker-mz" -Query "Generate a plugin..." `
        -ExpectedResult @{ containsCommand = "HealAll" }

.EXAMPLE
    # Run all golden tasks for a pack
    Invoke-PackGoldenTasks -PackId "rpgmaker-mz" -Parallel

.EXAMPLE
    # Get golden task score
    $score = Get-GoldenTaskScore -PackId "godot" -TimeRange "7d"

.LINK
    https://github.com/llm-workflow/platform/wiki/GoldenTasks
#>

# Import modular components
. "$PSScriptRoot/GoldenTaskDefinitions.ps1"
. "$PSScriptRoot/GoldenTaskHelpers.ps1"

#region Configuration

# Module-level configuration
$script:GoldenTaskConfig = @{
    Version = '1.0.0'
    ResultsDirectory = Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'data') 'golden-tasks'
    SuitesDirectory = Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'data') 'golden-suites'
    DefaultMinConfidence = 0.8
    MaxParallelJobs = 4
    HistoryRetentionDays = 365
}

# Ensure directories exist
if (-not (Test-Path $script:GoldenTaskConfig.ResultsDirectory)) {
    $null = New-Item -ItemType Directory -Path $script:GoldenTaskConfig.ResultsDirectory -Force
}
if (-not (Test-Path $script:GoldenTaskConfig.SuitesDirectory)) {
    $null = New-Item -ItemType Directory -Path $script:GoldenTaskConfig.SuitesDirectory -Force
}

function Get-SafeObjectPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [Parameter()]
        $Default = $null
    )

    if ($null -eq $InputObject) {
        return $Default
    }

    if ($InputObject -is [hashtable]) {
        if ($InputObject.ContainsKey($PropertyName)) {
            return $InputObject[$PropertyName]
        }

        return $Default
    }

    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -ne $property) {
        return $property.Value
    }

    return $Default
}

function Write-GoldenTaskSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Summary
    )

    $lines = @(
        '',
        "Golden Task Summary for '$($Summary.PackId)':",
        "  Tasks Run: $($Summary.TasksRun)",
        "  Passed: $($Summary.Passed)",
        "  Failed: $($Summary.Failed)",
        "  Pass Rate: $([math]::Round($Summary.PassRate * 100, 2))%",
        "  Avg Confidence: $($Summary.AverageConfidence)"
    )

    foreach ($line in $lines) {
        Write-Information $line -InformationAction Continue
    }
}

#endregion

#region New-GoldenTask

<#
.SYNOPSIS
    Defines a new golden task for evaluating LLM workflow responses.

.DESCRIPTION
    Creates a golden task structure that defines an evaluation criteria for
    testing LLM workflow responses. Uses property-based validation instead
    of exact text matching to allow for reasonable variations in output.

.PARAMETER TaskId
    Unique identifier for this golden task (e.g., "gt-rpgmaker-001")

.PARAMETER Name
    Human-readable name for the task

.PARAMETER Description
    Detailed description of what the task evaluates

.PARAMETER PackId
    The pack this golden task belongs to (e.g., "rpgmaker-mz", "godot", "blender")

.PARAMETER Query
    The query/prompt to test against

.PARAMETER ExpectedResult
    Hashtable of expected properties and their expected values

.PARAMETER RequiredEvidence
    Array of evidence sources that must be present in the response

.PARAMETER ValidationRules
    Hashtable defining how to validate the answer (confidence thresholds, etc.)

.PARAMETER Category
    Task category (codegen, analysis, extraction, comparison, diagnosis)

.PARAMETER Difficulty
    Task difficulty level (easy, medium, hard)

.PARAMETER Tags
    Array of tags for categorization

.EXAMPLE
    $task = New-GoldenTask `
        -TaskId "gt-rpgmaker-001" `
        -Name "Plugin skeleton generation" `
        -Description "Generate minimal plugin with one command and parameter" `
        -PackId "rpgmaker-mz" `
        -Query "Generate a plugin skeleton with one command called 'HealAll'" `
        -ExpectedResult @{
            containsCommand = "HealAll"
            hasJSDocHeader = $true
        } `
        -Category "codegen" `
        -Difficulty "easy"

.OUTPUTS
    [hashtable] The configured golden task object
#>
function New-GoldenTask {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^gt-[a-z0-9-]+-\d+$')]
        [string]$TaskId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$Description = "",

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9-]+$')]
        [string]$PackId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Query,

        [Parameter(Mandatory = $false)]
        [hashtable]$ExpectedResult = @{},

        [Parameter(Mandatory = $false)]
        [array]$RequiredEvidence = @(),

        [Parameter(Mandatory = $false)]
        [hashtable]$ValidationRules = @{},

        [Parameter(Mandatory = $false)]
        [ValidateSet('codegen', 'analysis', 'extraction', 'comparison', 'diagnosis', 'integration', 'validation')]
        [string]$Category = 'codegen',

        [Parameter(Mandatory = $false)]
        [ValidateSet('easy', 'medium', 'hard')]
        [string]$Difficulty = 'medium',

        [Parameter(Mandatory = $false)]
        [string[]]$Tags = @()
    )

    begin {
        Write-Verbose "Creating golden task: $TaskId"
    }

    process {
        # Validate task ID format (gt-{pack}-###)
        $expectedPrefix = "gt-$PackId-"
        if (-not $TaskId.StartsWith($expectedPrefix)) {
            Write-Warning "TaskId '$TaskId' does not follow convention 'gt-{pack}-###'. Expected prefix: '$expectedPrefix'"
        }

        # Set default validation rules
        $defaultValidationRules = @{
            propertyBased = $true
            requiredProperties = @($ExpectedResult.Keys)
            forbiddenPatterns = @()
            minConfidence = $script:GoldenTaskConfig.DefaultMinConfidence
            allowPartialMatch = $true
        }

        # Merge with provided rules
        $mergedRules = $defaultValidationRules.Clone()
        foreach ($key in $ValidationRules.Keys) {
            $mergedRules[$key] = $ValidationRules[$key]
        }

        $task = @{
            taskId = $TaskId
            name = $Name
            description = $Description
            packId = $PackId
            query = $Query
            expectedResult = $ExpectedResult
            requiredEvidence = $RequiredEvidence
            validationRules = $mergedRules
            category = $Category
            difficulty = $Difficulty
            tags = $Tags
            createdAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            version = $script:GoldenTaskConfig.Version
        }

        Write-Verbose "Golden task '$TaskId' created successfully"
        return $task
    }
}

#endregion

#region Test-PropertyBasedExpectation

<#
.SYNOPSIS
    Validates actual results against expected properties using flexible matching.

.DESCRIPTION
    Performs property-based validation where each expected property is checked
    against the actual result. Supports:
    - Exact value matching
    - Type checking (using [type] values)
    - Pattern matching (using regex strings)
    - Presence checking ($true checks if property exists and is not null/empty)
    - Range checking (using @{ min = x; max = y })
    - Collection containment (using arrays)

.PARAMETER Expected
    Hashtable of expected properties and their expected values/patterns

.PARAMETER Actual
    Hashtable of actual properties from the LLM response

.EXAMPLE
    $expected = @{ 
        containsCommand = "HealAll"
        hasJSDocHeader = $true
        lineCount = @{ min = 10; max = 50 }
    }
    $actual = @{ containsCommand = "HealAll"; hasJSDocHeader = $true; lineCount = 25 }
    Test-PropertyBasedExpectation -Expected $expected -Actual $actual

.OUTPUTS
    [hashtable] Validation result with properties: Success, PassedProperties, FailedProperties, Confidence
#>
# Moved to GoldenTaskHelpers.ps1

#endregion

#region Test-GoldenTaskResult

<#
.SYNOPSIS
    Validates an actual answer against a golden task definition.

.DESCRIPTION
    Tests whether an LLM response satisfies the requirements of a golden task.
    Performs property-based validation, evidence checking, and forbidden pattern
    detection. Returns detailed validation results with confidence scoring.

.PARAMETER Task
    The golden task hashtable to validate against

.PARAMETER ActualResult
    Hashtable of extracted properties from the actual LLM response

.PARAMETER AnswerText
    The raw text of the LLM response (for evidence and pattern checking)

.EXAMPLE
    $task = Get-PredefinedGoldenTasks -PackId "rpgmaker-mz" | Select-Object -First 1
    $actual = @{ containsCommand = "HealAll"; hasJSDocHeader = $true }
    Test-GoldenTaskResult -Task $task -ActualResult $actual -AnswerText $llmResponse

.OUTPUTS
    [hashtable] Detailed validation result with Success, Confidence, Evidence, and Errors
#>
function Test-GoldenTaskResult {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Task,

        [Parameter(Mandatory = $true)]
        [hashtable]$ActualResult,

        [Parameter(Mandatory = $false)]
        [string]$AnswerText = ""
    )

    begin {
        Write-Verbose "Validating golden task result: $($Task.taskId)"
        $validationErrors = @()
        $evidenceFound = @()
        $forbiddenFound = @()
    }

    process {
        # 1. Property-based validation
        $propertyValidation = Test-PropertyBasedExpectation `
            -Expected $Task.expectedResult `
            -Actual $ActualResult

        # 2. Required evidence checking
        $evidenceErrors = @()
        foreach ($evidence in $Task.requiredEvidence) {
            $evidenceFoundFlag = $false
            
            if ($AnswerText) {
                switch ($evidence.type) {
                    'plugin-pattern' {
                        # Look for plugin-related patterns
                        if ($AnswerText -match 'PluginManager\.(register|commands)') {
                            $evidenceFoundFlag = $true
                        }
                    }
                    'source-reference' {
                        # Look for source file references
                        if ($AnswerText -match '\.js|\.gd|\.py') {
                            $evidenceFoundFlag = $true
                        }
                    }
                    'method-citation' {
                        # Look for method citations
                        if ($AnswerText -match '\.[a-zA-Z_]+\s*\(|function\s+\w+|def\s+\w+') {
                            $evidenceFoundFlag = $true
                        }
                    }
                    'notetag' {
                        # Look for notetag patterns
                        if ($AnswerText -match '<[A-Za-z_]+[\w\s]*>') {
                            $evidenceFoundFlag = $true
                        }
                    }
                    'signal-pattern' {
                        # Look for Godot signal patterns
                        if ($AnswerText -match '(signal\s+\w+|emit_signal|connect\s*\()') {
                            $evidenceFoundFlag = $true
                        }
                    }
                    'bpy-pattern' {
                        # Look for Blender bpy patterns
                        if ($AnswerText -match '(bpy\.(ops|context|data)|bl_idname|bl_label)') {
                            $evidenceFoundFlag = $true
                        }
                    }
                    default {
                        # Generic pattern matching
                        if ($evidence -is [hashtable]) {
                            if ($evidence.ContainsKey('pattern') -and $AnswerText -match $evidence.pattern) {
                                $evidenceFoundFlag = $true
                            }
                        }
                        elseif ($evidence.PSObject.Properties['pattern'] -and $AnswerText -match $evidence.pattern) {
                            # Fallback for PSCustomObject or other objects
                            $evidenceFoundFlag = $true
                        }
                    }
                }
            }

            if ($evidenceFoundFlag) {
                $evidenceFound += $evidence
            }
            else {
                $evidenceErrors += "Missing evidence: $($evidence.source) [$($evidence.type)]"
            }
        }

        # 3. Forbidden pattern detection
        $forbiddenPatterns = $Task.validationRules.forbiddenPatterns
        if ($forbiddenPatterns -and $AnswerText) {
            foreach ($pattern in $forbiddenPatterns) {
                if ($AnswerText -match $pattern) {
                    $forbiddenFound += $pattern
                    $validationErrors += "Forbidden pattern detected: $pattern"
                }
            }
        }

        # 4. Evidence requirement validation
        $evidenceSatisfied = $Task.requiredEvidence.Count -eq 0 -or $evidenceErrors.Count -eq 0
        if (-not $evidenceSatisfied) {
            $validationErrors += $evidenceErrors
        }

        # Add property validation errors
        foreach ($failedProp in $propertyValidation.FailedProperties) {
            $propDetails = $propertyValidation.Details[$failedProp]
            $validationErrors += "Property validation failed for '$failedProp': Expected $($propDetails.Expected), got $($propDetails.Actual)"
        }

        # 5. Calculate overall result
        $minConfidence = $Task.validationRules.minConfidence
        $confidenceSufficient = $propertyValidation.Confidence -ge $minConfidence

        $overallSuccess = $propertyValidation.Success -and 
                         $evidenceSatisfied -and 
                         $forbiddenFound.Count -eq 0 -and
                         $confidenceSufficient

        # 6. Build result object
        $result = @{
            TaskId = $Task.taskId
            TaskName = $Task.name
            Success = $overallSuccess
            Confidence = $propertyValidation.Confidence
            MinConfidenceRequired = $minConfidence
            ConfidenceSufficient = $confidenceSufficient
            PropertyValidation = $propertyValidation
            Evidence = @{
                Required = $Task.requiredEvidence
                Found = $evidenceFound
                MissingCount = $Task.requiredEvidence.Count - $evidenceFound.Count
                Satisfied = $evidenceSatisfied
            }
            ForbiddenPatterns = @{
                Patterns = $forbiddenPatterns
                Found = $forbiddenFound
                Violations = $forbiddenFound.Count
            }
            Errors = $validationErrors
            ValidatedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        }

        Write-Verbose "Validation complete for '$($Task.taskId)': Success=$overallSuccess, Confidence=$($propertyValidation.Confidence)"
        return $result
    }
}

#endregion

#region Invoke-GoldenTask

<#
.SYNOPSIS
    Runs a golden task evaluation against the current system.

.DESCRIPTION
    Executes a golden task by querying the LLM workflow system and validating
    the response against the task's expected results. Supports result recording
    for historical tracking and trending analysis.

.PARAMETER Task
    The golden task hashtable to evaluate

.PARAMETER SystemConfig
    Current system configuration (optional, for context-aware evaluation)

.PARAMETER RecordResults
    Switch to record results to the golden task history database

.PARAMETER LLMProvider
    The LLM provider to use for evaluation (defaults to system default)

.PARAMETER TimeoutSeconds
    Timeout for the LLM query in seconds

.EXAMPLE
    $task = Get-PredefinedGoldenTasks -PackId "rpgmaker-mz" | Select-Object -First 1
    Invoke-GoldenTask -Task $task -RecordResults

.OUTPUTS
    [hashtable] Evaluation result including the LLM response and validation outcome
#>
function Invoke-GoldenTask {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Task,

        [Parameter(Mandatory = $false)]
        [hashtable]$SystemConfig = @{},

        [Parameter(Mandatory = $false)]
        [switch]$RecordResults,

        [Parameter(Mandatory = $false)]
        [string]$LLMProvider = "default",

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 120
    )

    begin {
        Write-Verbose "Starting golden task evaluation: $($Task.taskId)"
        $startTime = Get-Date
    }

    process {
        try {
            # Validate task structure
            if (-not $Task.query) {
                throw "Task '$($Task.taskId)' is missing required 'query' field"
            }

            # Simulate or perform actual LLM query
            # In production, this would call the actual LLM workflow system
            $llmResponse = Invoke-LLMQuery -Query $Task.query -Provider $LLMProvider -Timeout $TimeoutSeconds

            # Extract properties from LLM response
            $extractedProperties = Extract-ResponseProperties -Response $llmResponse -Task $Task

            # Validate the result
            $validation = Test-GoldenTaskResult `
                -Task $Task `
                -ActualResult $extractedProperties `
                -AnswerText $llmResponse.content

            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds

            # Build evaluation result
            $evalResult = @{
                EvaluationId = [Guid]::NewGuid().ToString()
                Task = @{
                    TaskId = $Task.taskId
                    Name = $Task.name
                    PackId = $Task.packId
                    Category = $Task.category
                    Difficulty = $Task.difficulty
                }
                Success = $validation.Success
                Query = $Task.query
                LLMResponse = $llmResponse
                ExtractedProperties = $extractedProperties
                Validation = $validation
                Timing = @{
                    StartedAt = $startTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    CompletedAt = $endTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    DurationSeconds = [math]::Round($duration, 2)
                }
                SystemConfig = $SystemConfig
            }

            # Record results if requested
            if ($RecordResults) {
                Save-GoldenTaskResult -Result $evalResult
                Write-Verbose "Results recorded for task '$($Task.taskId)'"
            }

            return $evalResult
        }
        catch {
            $errorResult = @{
                EvaluationId = [Guid]::NewGuid().ToString()
                Task = @{
                    TaskId = $Task.taskId
                    Name = $Task.name
                    PackId = $Task.packId
                }
                Success = $false
                Error = $_.ToString()
                Timing = @{
                    StartedAt = $startTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    FailedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
            }

            if ($RecordResults) {
                Save-GoldenTaskResult -Result $errorResult
            }

            Write-Error "Golden task evaluation failed: $_"
            return $errorResult
        }
    }
}

#endregion

#region Get-GoldenTaskScore

<#
.SYNOPSIS
    Calculates pass/fail score for golden tasks.

.DESCRIPTION
    Calculates a score based on golden task results for a pack.
    Returns percentage of passed tasks and aggregate confidence score.

.PARAMETER PackId
    The pack ID to calculate score for

.PARAMETER TimeRange
    Time range for results to include ('24h', '7d', '30d', '90d')

.PARAMETER Category
    Filter by task category

.PARAMETER Difficulty
    Filter by task difficulty

.PARAMETER ProjectRoot
    The project root directory

.EXAMPLE
    $score = Get-GoldenTaskScore -PackId "rpgmaker-mz" -TimeRange "7d"
    Write-Host "Pass rate: $($score.PassRate)%"

.OUTPUTS
    [hashtable] Score summary with PassRate, AverageConfidence, TotalTasks, PassedTasks, FailedTasks
#>
function Get-GoldenTaskScore {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter(Mandatory = $false)]
        [ValidateSet('24h', '7d', '30d', '90d', 'all')]
        [string]$TimeRange = '7d',

        [Parameter(Mandatory = $false)]
        [string]$Category = '',

        [Parameter(Mandatory = $false)]
        [string]$Difficulty = '',

        [Parameter(Mandatory = $false)]
        [string]$ProjectRoot = '.'
    )

    # Calculate cutoff date
    $cutoff = switch ($TimeRange) {
        '24h' { (Get-Date).AddHours(-24) }
        '7d' { (Get-Date).AddDays(-7) }
        '30d' { (Get-Date).AddDays(-30) }
        '90d' { (Get-Date).AddDays(-90) }
        'all' { [DateTime]::MinValue }
        default { (Get-Date).AddDays(-7) }
    }

    # Get results
    $results = Get-GoldenTaskResults -PackId $PackId -FromDate $cutoff

    # Apply filters
    if ($Category) {
        $results = $results | Where-Object { $_.Task.Category -eq $Category }
    }
    if ($Difficulty) {
        $results = $results | Where-Object { $_.Task.Difficulty -eq $Difficulty }
    }

    # Calculate latest result per task
    $latestResults = @{}
    foreach ($result in $results) {
        $taskId = $result.Task.TaskId
        if (-not $latestResults.ContainsKey($taskId) -or 
            $result.Timing.CompletedAt -gt $latestResults[$taskId].Timing.CompletedAt) {
            $latestResults[$taskId] = $result
        }
    }

    $evaluatedResults = $latestResults.Values

    if ($evaluatedResults.Count -eq 0) {
        return @{
            PackId = $PackId
            TimeRange = $TimeRange
            PassRate = 0
            AverageConfidence = 0
            TotalTasks = 0
            PassedTasks = 0
            FailedTasks = 0
            Score = 0
            Grade = 'N/A'
            Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        }
    }

    $passed = ($evaluatedResults | Where-Object { $_.Validation.Success }).Count
    $failed = $evaluatedResults.Count - $passed
    $passRate = [math]::Round(($passed / $evaluatedResults.Count) * 100, 2)

    $avgConfidence = 0
    $confidenceSum = 0
    foreach ($result in $evaluatedResults) {
        if ($result.Validation -and $result.Validation.Confidence) {
            $confidenceSum += $result.Validation.Confidence
        }
    }
    $avgConfidence = [math]::Round($confidenceSum / $evaluatedResults.Count, 4)

    # Calculate overall score (weighted average of pass rate and confidence)
    $score = [math]::Round(($passRate * 0.6) + ($avgConfidence * 100 * 0.4), 2)

    # Determine grade
    $grade = switch ($score) {
        { $_ -ge 95 } { 'A+' }
        { $_ -ge 90 } { 'A' }
        { $_ -ge 85 } { 'B+' }
        { $_ -ge 80 } { 'B' }
        { $_ -ge 70 } { 'C' }
        { $_ -ge 60 } { 'D' }
        default { 'F' }
    }

    return @{
        PackId = $PackId
        TimeRange = $TimeRange
        PassRate = $passRate
        AverageConfidence = $avgConfidence
        TotalTasks = $evaluatedResults.Count
        PassedTasks = $passed
        FailedTasks = $failed
        Score = $score
        Grade = $grade
        Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        TaskBreakdown = @{
            Easy = ($evaluatedResults | Where-Object { $_.Task.Difficulty -eq 'easy' }).Count
            Medium = ($evaluatedResults | Where-Object { $_.Task.Difficulty -eq 'medium' }).Count
            Hard = ($evaluatedResults | Where-Object { $_.Task.Difficulty -eq 'hard' }).Count
        }
    }
}

#endregion

#region Export-GoldenTaskReport

<#
.SYNOPSIS
    Exports a golden task evaluation report.

.DESCRIPTION
    Generates and exports a comprehensive golden task evaluation report
    in multiple formats (JSON, HTML, Markdown).

.PARAMETER PackId
    The pack ID to generate report for

.PARAMETER OutputPath
    Path to save the report

.PARAMETER Format
    Report format: json, html, markdown

.PARAMETER TimeRange
    Time range for report data

.PARAMETER IncludeDetails
    Include detailed task results in report

.PARAMETER ProjectRoot
    The project root directory

.EXAMPLE
    Export-GoldenTaskReport -PackId "rpgmaker-mz" -OutputPath "./report.html" -Format html

.OUTPUTS
    [System.IO.FileInfo] The exported report file
#>
function Export-GoldenTaskReport {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [ValidateSet('json', 'html', 'markdown')]
        [string]$Format = 'json',

        [Parameter(Mandatory = $false)]
        [ValidateSet('24h', '7d', '30d', '90d', 'all')]
        [string]$TimeRange = '30d',

        [Parameter(Mandatory = $false)]
        [switch]$IncludeDetails,

        [Parameter(Mandatory = $false)]
        [string]$ProjectRoot = '.'
    )

    begin {
        Write-Verbose "Generating golden task report for pack: $PackId"
    }

    process {
        try {
            # Get score summary
            $score = Get-GoldenTaskScore -PackId $PackId -TimeRange $TimeRange

            # Get detailed results if requested
            $details = @()
            if ($IncludeDetails) {
                $cutoff = switch ($TimeRange) {
                    '24h' { (Get-Date).AddHours(-24) }
                    '7d' { (Get-Date).AddDays(-7) }
                    '30d' { (Get-Date).AddDays(-30) }
                    '90d' { (Get-Date).AddDays(-90) }
                    'all' { [DateTime]::MinValue }
                    default { (Get-Date).AddDays(-7) }
                }
                $details = Get-GoldenTaskResults -PackId $PackId -FromDate $cutoff
            }

            # Build report object
            $report = @{
                ReportMetadata = @{
                    Title = "Golden Task Evaluation Report - $PackId"
                    GeneratedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
                    TimeRange = $TimeRange
                    Format = $Format
                    Version = $script:GoldenTaskConfig.Version
                }
                Summary = $score
                Details = $details
            }

            # Generate output based on format
            switch ($Format) {
                'json' {
                    $content = $report | ConvertTo-Json -Depth 20 -Compress:$false
                }
                'html' {
                    $content = ConvertTo-GoldenTaskHtmlReport -Report $report
                }
                'markdown' {
                    $content = ConvertTo-GoldenTaskMarkdownReport -Report $report
                }
            }

            # Ensure output directory exists
            $outputDir = Split-Path -Parent $OutputPath
            if ($outputDir -and -not (Test-Path $outputDir)) {
                $null = New-Item -ItemType Directory -Path $outputDir -Force
            }

            # Write report
            $content | Out-File -FilePath $OutputPath -Encoding UTF8
            $fileInfo = Get-Item $OutputPath

            Write-Verbose "Report exported to: $OutputPath"
            return $fileInfo
        }
        catch {
            Write-Error "Failed to export golden task report: $_"
            throw
        }
    }
}

#endregion

#region Invoke-PackGoldenTasks

<#
.SYNOPSIS
    Runs all golden tasks for a specific pack.

.DESCRIPTION
    Executes the complete golden task suite for a given pack. Supports filtering
    by category, difficulty, and tags. Can run tasks in parallel for faster
    evaluation.

.PARAMETER PackId
    The pack ID to run golden tasks for

.PARAMETER Filter
    Hashtable of filters (category, difficulty, tags, excludeTags)

.PARAMETER Parallel
    Switch to run tasks in parallel using background jobs

.PARAMETER MaxParallelJobs
    Maximum number of parallel jobs (default: 4)

.PARAMETER RecordResults
    Switch to record all results to history

.PARAMETER FailFast
    Switch to stop on first failure

.EXAMPLE
    # Run all golden tasks for RPG Maker MZ
    Invoke-PackGoldenTasks -PackId "rpgmaker-mz" -RecordResults

.EXAMPLE
    # Run only easy codegen tasks
    Invoke-PackGoldenTasks -PackId "godot" -Filter @{ difficulty = "easy"; category = "codegen" }

.OUTPUTS
    [hashtable] Summary of all task results including pass/fail counts and statistics
#>
function Invoke-PackGoldenTasks {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter(Mandatory = $false)]
        [hashtable]$Filter = @{},

        [Parameter(Mandatory = $false)]
        [switch]$Parallel,

        [Parameter(Mandatory = $false)]
        [int]$MaxParallelJobs = $script:GoldenTaskConfig.MaxParallelJobs,

        [Parameter(Mandatory = $false)]
        [switch]$RecordResults,

        [Parameter(Mandatory = $false)]
        [switch]$FailFast
    )

    begin {
        Write-Verbose "Loading golden tasks for pack: $PackId"
        $allTasks = Get-PredefinedGoldenTasks -PackId $PackId

        if (-not $allTasks -or $allTasks.Count -eq 0) {
            Write-Warning "No golden tasks found for pack: $PackId"
            return @{ PackId = $PackId; TasksRun = 0; Passed = 0; Failed = 0; Tasks = @(); Summary = "No tasks found" }
        }

        Write-Verbose "Found $($allTasks.Count) golden tasks"

        # Apply filters
        $filteredTasks = $allTasks | Where-Object {
            $t = $_
            $include = $true

            # Safe property access for strict mode (handles hashtable or pscustomobject)
            $taskCategory = $null
            $taskDifficulty = $null
            $taskTags = $null

            if ($t -is [hashtable]) {
                $taskCategory = $t['category']
                $taskDifficulty = $t['difficulty']
                $taskTags = $t['tags']
            }
            else {
                $taskCategory = Get-SafeObjectPropertyValue -InputObject $t -PropertyName 'category'
                $taskDifficulty = Get-SafeObjectPropertyValue -InputObject $t -PropertyName 'difficulty'
                $taskTags = Get-SafeObjectPropertyValue -InputObject $t -PropertyName 'tags' -Default @()
            }

            if ($Filter.ContainsKey('category') -and $Filter.category -and $taskCategory -ne $Filter.category) { $include = $false }
            if ($Filter.ContainsKey('difficulty') -and $Filter.difficulty -and $taskDifficulty -ne $Filter.difficulty) { $include = $false }
            if ($Filter.ContainsKey('tags') -and $Filter.tags) {
                foreach ($tag in $Filter.tags) {
                    if ($taskTags -notcontains $tag) { $include = $false; break }
                }
            }
            if ($Filter.ContainsKey('excludeTags') -and $Filter.excludeTags) {
                foreach ($tag in $Filter.excludeTags) {
                    if ($taskTags -contains $tag) { $include = $false; break }
                }
            }

            $include
        }

        $tasksToRun = @($filteredTasks)
        Write-Verbose "Running $($tasksToRun.Count) tasks after filtering"

        $startTime = Get-Date
        $results = @()
    }

    process {
        if (-not $allTasks -or $allTasks.Count -eq 0) {
            return
        }

        if ($Parallel -and $tasksToRun.Count -gt 1) {
            # Run in parallel using runspaces
            $results = Invoke-ParallelGoldenTasks -Tasks $tasksToRun -MaxParallelJobs $MaxParallelJobs -RecordResults:$RecordResults -FailFast:$FailFast
        }
        else {
            # Run sequentially
            foreach ($task in $tasksToRun) {
                Write-Verbose "Running task: $($task.taskId)"
                $result = Invoke-GoldenTask -Task $task -RecordResults:$RecordResults
                $results += $result

                if ($FailFast -and $result -and $result.Validation -and -not $result.Validation.Success) {
                    Write-Warning "Task '$($task.taskId)' failed and FailFast is enabled. Stopping."
                    break
                }
            }
        }

        $endTime = Get-Date
        $duration = 0
        if ($null -ne $startTime) {
            $duration = ($endTime - $startTime).TotalSeconds
        }

        # Calculate statistics
        $passed = 0
        $resultList = @($results)
        if ($resultList.Count -gt 0) {
            # Safely check for Success property on either hashtable or pscustomobject
            $passed = (@($resultList | Where-Object { 
                $r = $_
                $isSucc = $false
                if ($r -is [hashtable]) {
                    $isSucc = $r['Success'] -eq $true
                }
                else {
                    $isSucc = (Get-SafeObjectPropertyValue -InputObject $r -PropertyName 'Success' -Default $false) -eq $true
                }
                $isSucc
            })).Count
        }
        $failed = $resultList.Count - $passed
        $avgConfidence = 0.0
        if ($resultList.Count -gt 0) {
            $measure = $resultList | Measure-Object -Property { 
                $conf = 0.0
                if ($_ -is [hashtable]) {
                    if ($_.ContainsKey('Validation') -and $_['Validation'] -is [hashtable]) {
                        $conf = $_['Validation']['Confidence']
                    }
                    elseif ($_.ContainsKey('Confidence')) {
                        $conf = $_['Confidence']
                    }
                }
                else {
                    $validation = Get-SafeObjectPropertyValue -InputObject $_ -PropertyName 'Validation'
                    if ($null -ne $validation) {
                        $conf = Get-SafeObjectPropertyValue -InputObject $validation -PropertyName 'Confidence' -Default 0.0
                    }
                    else {
                        $conf = Get-SafeObjectPropertyValue -InputObject $_ -PropertyName 'Confidence' -Default 0.0
                    }
                }
                $conf
            } -Average
            # Use safe property check for strict mode
            if ($measure.PSObject.Properties['Average'] -and $measure.Average -ne $null) {
                $avgConfidence = $measure.Average
            }
        }

        $categoryStats = @{}
        foreach ($res in $results) {
            # Find the original task if possible, or use ID
            $cat = "General"
            if ($res -is [hashtable]) { 
                # In Invoke-PackGoldenTasks, we might have stored the category in the result or we look it up
                # Actually, the result doesn't have Category currently. 
                # Let's assume it might be in TaskName or we can lookup from $allTasks
                $taskMatch = $allTasks | Where-Object { 
                    if ($_ -is [hashtable]) { $_['taskId'] -eq $res['TaskId'] } else { $_.taskId -eq $res.TaskId }
                }
                if ($taskMatch) { $cat = if ($taskMatch -is [hashtable]) { $taskMatch['category'] } else { $taskMatch.category } }
            }
            
            if (-not $categoryStats.ContainsKey($cat)) {
                $categoryStats[$cat] = @{ Passed = 0; Failed = 0; Total = 0 }
            }
            $categoryStats[$cat].Total++
            $isSuccess = if ($res -is [hashtable]) { $res['Success'] } else { try { $res.Success } catch { $false } }
            if ($isSuccess) {
                $categoryStats[$cat].Passed++
            }
            else {
                $categoryStats[$cat].Failed++
            }
        }

        $difficultyStats = @{}
        foreach ($res in $results) {
            $diff = "Medium"
            $taskMatch = $allTasks | Where-Object { 
                if ($_ -is [hashtable]) { $_['taskId'] -eq $res['TaskId'] } else { $_.taskId -eq $res.TaskId }
            }
            if ($taskMatch) { $diff = if ($taskMatch -is [hashtable]) { $taskMatch['difficulty'] } else { $taskMatch.difficulty } }
            
            if (-not $difficultyStats.ContainsKey($diff)) {
                $difficultyStats[$diff] = @{ Passed = 0; Failed = 0; Total = 0 }
            }
            $difficultyStats[$diff].Total++
            $isSuccess = if ($res -is [hashtable]) { $res['Success'] } else { try { $res.Success } catch { $false } }
            if ($isSuccess) {
                $difficultyStats[$diff].Passed++
            }
            else {
                $difficultyStats[$diff].Failed++
            }
        }

        $summary = @{
            PackId = $PackId
            TasksRun = $results.Count
            Passed = $passed
            Failed = $failed
            PassRate = if ($results.Count -gt 0) { [math]::Round($passed / $results.Count, 4) } else { 0 }
            AverageConfidence = [math]::Round($avgConfidence, 4)
            DurationSeconds = [math]::Round($duration, 2)
            CategoryBreakdown = $categoryStats
            DifficultyBreakdown = $difficultyStats
            Filter = $Filter
            Tasks = $results
            StartedAt = $startTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
            CompletedAt = $endTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }

        Write-GoldenTaskSummary -Summary $summary

        return $summary
    }
}

#endregion

#region Get-GoldenTaskResults

<#
.SYNOPSIS
    Retrieves golden task results and history.

.DESCRIPTION
    Queries the golden task result database for historical evaluation data.
    Supports filtering by task ID, pack ID, and date range. Useful for
    trending analysis and regression detection.

.PARAMETER TaskId
    Filter by specific task ID

.PARAMETER PackId
    Filter by pack ID

.PARAMETER FromDate
    Start date for the query range

.PARAMETER ToDate
    End date for the query range

.PARAMETER SuccessOnly
    Return only successful results

.PARAMETER FailedOnly
    Return only failed results

.PARAMETER Last
    Return only the most recent N results

.EXAMPLE
    # Get all results for a specific task
    Get-GoldenTaskResults -TaskId "gt-rpgmaker-001"

.EXAMPLE
    # Get last 30 days of results for a pack
    Get-GoldenTaskResults -PackId "rpgmaker-mz" -FromDate (Get-Date).AddDays(-30)

.EXAMPLE
    # Get trending data (last 10 results) for a task
    Get-GoldenTaskResults -TaskId "gt-rpgmaker-001" -Last 10

.OUTPUTS
    [array] Collection of golden task results
#>
function Get-GoldenTaskResults {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TaskId,

        [Parameter(Mandatory = $false)]
        [string]$PackId,

        [Parameter(Mandatory = $false)]
        [DateTime]$FromDate,

        [Parameter(Mandatory = $false)]
        [DateTime]$ToDate,

        [Parameter(Mandatory = $false)]
        [switch]$SuccessOnly,

        [Parameter(Mandatory = $false)]
        [switch]$FailedOnly,

        [Parameter(Mandatory = $false)]
        [int]$Last = 0
    )

    begin {
        Write-Verbose "Retrieving golden task results"
        $resultsDir = $script:GoldenTaskConfig.ResultsDirectory
        
        if (-not (Test-Path $resultsDir)) {
            Write-Verbose "Results directory does not exist: $resultsDir"
            return @()
        }

        $allResults = @()
    }

    process {
        # Load all result files
        $resultFiles = Get-ChildItem -Path $resultsDir -Filter "*.json" -Recurse -File

        foreach ($file in $resultFiles) {
            try {
                $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                $result = $content | ConvertFrom-Json -ErrorAction Stop

                if ($result) {
                    # Convert to hashtable for consistency
                    $resultObj = ConvertTo-Hashtable -InputObject $result
                    $allResults += $resultObj
                }
            }
            catch {
                Write-Warning "Failed to load golden-task result file '$($file.Name)': $_"
            }
        }

        # Apply filters
        $filteredResults = $allResults

        if ($TaskId) {
            $filteredResults = $filteredResults | Where-Object { $_.Task.TaskId -eq $TaskId }
        }

        if ($PackId) {
            $filteredResults = $filteredResults | Where-Object { $_.Task.PackId -eq $PackId }
        }

        if ($FromDate) {
            $fromStr = $FromDate.ToString("yyyy-MM-dd")
            $filteredResults = $filteredResults | Where-Object { 
                $_.Timing.StartedAt -and $_.Timing.StartedAt.Substring(0,10) -ge $fromStr 
            }
        }

        if ($ToDate) {
            $toStr = $ToDate.ToString("yyyy-MM-dd")
            $filteredResults = $filteredResults | Where-Object { 
                $_.Timing.StartedAt -and $_.Timing.StartedAt.Substring(0,10) -le $toStr 
            }
        }

        if ($SuccessOnly) {
            $filteredResults = $filteredResults | Where-Object { $_.Validation.Success -eq $true }
        }

        if ($FailedOnly) {
            $filteredResults = $filteredResults | Where-Object { $_.Validation.Success -eq $false }
        }

        # Sort by date (newest first)
        $sortedResults = $filteredResults | Sort-Object { $_.Timing.StartedAt } -Descending

        # Limit results if specified
        if ($Last -gt 0 -and $sortedResults.Count -gt $Last) {
            $sortedResults = $sortedResults | Select-Object -First $Last
        }

        Write-Verbose "Retrieved $($sortedResults.Count) results"
        return $sortedResults
    }
}

#endregion

# Moved to GoldenTaskDefinitions.ps1

#endregion

#region Golden Task Suite Management

<#
.SYNOPSIS
    Creates a new golden task suite for batch evaluation.

.DESCRIPTION
    Groups multiple golden tasks into a suite for organized evaluation.
    Suites can be exported, imported, and versioned.

.PARAMETER SuiteName
    Name of the golden task suite

.PARAMETER Tasks
    Array of golden task hashtables to include in the suite

.PARAMETER Description
    Optional description of the suite

.PARAMETER Version
    Suite version (default: 1.0.0)

.EXAMPLE
    $tasks = Get-PredefinedGoldenTasks -PackId "rpgmaker-mz"
    $suite = New-GoldenTaskSuite -SuiteName "RPG Maker Regression Tests" -Tasks $tasks

.OUTPUTS
    [hashtable] The created suite object
#>
function New-GoldenTaskSuite {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SuiteName,

        [Parameter(Mandatory = $true)]
        [array]$Tasks,

        [Parameter(Mandatory = $false)]
        [string]$Description = "",

        [Parameter(Mandatory = $false)]
        [string]$Version = "1.0.0"
    )

    begin {
        Write-Verbose "Creating golden task suite: $SuiteName"
    }

    process {
        $suite = @{
            suiteName = $SuiteName
            description = $Description
            version = $Version
            createdAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            taskCount = $Tasks.Count
            tasks = $Tasks
            metadata = @{
                schemaVersion = "1.0"
                compatibleWith = @("1.0.0")
            }
        }

        Write-Verbose "Suite '$SuiteName' created with $($Tasks.Count) tasks"
        return $suite
    }
}

<#
.SYNOPSIS
    Exports a golden task suite to a JSON file.

.DESCRIPTION
    Saves a golden task suite to disk for sharing, version control,
    or later import.

.PARAMETER OutputPath
    Path to save the suite JSON file

.PARAMETER Suite
    The suite hashtable to export

.PARAMETER Compress
    Switch to minimize JSON output

.EXAMPLE
    $suite = New-GoldenTaskSuite -SuiteName "Test Suite" -Tasks $tasks
    Export-GoldenTaskSuite -OutputPath "./suites/test-suite.json" -Suite $suite

.OUTPUTS
    [System.IO.FileInfo] The exported file
#>
function Export-GoldenTaskSuite {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Suite,

        [Parameter(Mandatory = $false)]
        [switch]$Compress
    )

    begin {
        Write-Verbose "Exporting golden task suite to: $OutputPath"
    }

    process {
        try {
            $jsonParams = @{
                Depth = 10
            }
            if ($Compress) {
                $jsonParams.Compress = $true
            }

            $json = $Suite | ConvertTo-Json @jsonParams

            # Ensure directory exists
            $directory = Split-Path -Parent $OutputPath
            if ($directory -and -not (Test-Path $directory)) {
                $null = New-Item -ItemType Directory -Path $directory -Force
            }

            $json | Out-File -FilePath $OutputPath -Encoding UTF8
            $fileInfo = Get-Item $OutputPath

            Write-Verbose "Suite exported successfully to: $OutputPath"
            return $fileInfo
        }
        catch {
            Write-Error "Failed to export suite: $_"
            throw
        }
    }
}

<#
.SYNOPSIS
    Imports a golden task suite from a JSON file.

.DESCRIPTION
    Loads a previously exported golden task suite from disk.
    Validates the suite structure during import.

.PARAMETER Path
    Path to the suite JSON file

.PARAMETER ValidateOnly
    Switch to only validate without loading tasks

.EXAMPLE
    $suite = Import-GoldenTaskSuite -Path "./suites/test-suite.json"

.OUTPUTS
    [hashtable] The imported suite object
#>
function Import-GoldenTaskSuite {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$ValidateOnly
    )

    begin {
        Write-Verbose "Importing golden task suite from: $Path"
    }

    process {
        try {
            if (-not (Test-Path $Path)) {
                throw "Suite file not found: $Path"
            }

            $content = Get-Content -Path $Path -Raw -Encoding UTF8
            $suite = $content | ConvertFrom-Json

            # Convert to hashtable recursively
            $suiteObj = ConvertTo-Hashtable -InputObject $suite

            # Validate structure
            $requiredFields = @('suiteName', 'tasks', 'version')
            foreach ($field in $requiredFields) {
                if (-not $suiteObj.ContainsKey($field)) {
                    throw "Invalid suite: missing required field '$field'"
                }
            }

            if ($ValidateOnly) {
                Write-Verbose "Suite validation passed"
                return @{ Valid = $true; SuiteName = $suiteObj.suiteName }
            }

            Write-Verbose "Suite '$($suiteObj.suiteName)' imported successfully with $($suiteObj.tasks.Count) tasks"
            return $suiteObj
        }
        catch {
            Write-Error "Failed to import suite: $_"
            throw
        }
    }
}

#endregion

#region Helper Functions

<#
.SYNOPSIS
    Internal: Simulates an LLM query (placeholder for actual implementation).

.DESCRIPTION
    Placeholder function that simulates LLM query execution.
    In production, this would call the actual LLM workflow system.
#>
# Helper functions moved to GoldenTaskHelpers.ps1

#region Export-GoldenTaskResults

<#
.SYNOPSIS
    Exports golden task results to various formats for analysis.

.DESCRIPTION
    Exports raw golden task evaluation results to JSON, CSV, or Excel format
    for external analysis. Supports filtering by date range, pack, and task status.
    Unlike Export-GoldenTaskReport which generates summary reports, this function
    exports the raw result data.

.PARAMETER OutputPath
    Path to save the exported results

.PARAMETER Format
    Export format: json, csv, excel (default: json)

.PARAMETER PackId
    Filter by pack ID

.PARAMETER TaskId
    Filter by specific task ID

.PARAMETER FromDate
    Start date for results to include

.PARAMETER ToDate
    End date for results to include

.PARAMETER SuccessOnly
    Export only successful results

.PARAMETER FailedOnly
    Export only failed results

.PARAMETER IncludeProperties
    Include detailed property validation results

.EXAMPLE
    Export-GoldenTaskResults -OutputPath "./results.json" -PackId "rpgmaker-mz"

.EXAMPLE
    Export-GoldenTaskResults -OutputPath "./results.csv" -Format csv -FromDate (Get-Date).AddDays(-7)

.OUTPUTS
    [System.IO.FileInfo] The exported file
#>
function Export-GoldenTaskResults {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [ValidateSet('json', 'csv')]
        [string]$Format = 'json',

        [Parameter(Mandatory = $false)]
        [string]$PackId,

        [Parameter(Mandatory = $false)]
        [string]$TaskId,

        [Parameter(Mandatory = $false)]
        [DateTime]$FromDate,

        [Parameter(Mandatory = $false)]
        [DateTime]$ToDate,

        [Parameter(Mandatory = $false)]
        [switch]$SuccessOnly,

        [Parameter(Mandatory = $false)]
        [switch]$FailedOnly,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeProperties
    )

    begin {
        Write-Verbose "Exporting golden task results to: $OutputPath"
    }

    process {
        try {
            # Get results with filters
            $params = @{}
            if ($PackId) { $params['PackId'] = $PackId }
            if ($TaskId) { $params['TaskId'] = $TaskId }
            if ($FromDate) { $params['FromDate'] = $FromDate }
            if ($ToDate) { $params['ToDate'] = $ToDate }
            if ($SuccessOnly) { $params['SuccessOnly'] = $true }
            if ($FailedOnly) { $params['FailedOnly'] = $true }

            $results = Get-GoldenTaskResults @params

            if ($results.Count -eq 0) {
                Write-Warning "No results found matching the specified criteria"
                return $null
            }

            # Process results for export
            $exportData = $results | ForEach-Object {
                $row = [ordered]@{
                    EvaluationId = $_.EvaluationId
                    TaskId = $_.Task.TaskId
                    TaskName = $_.Task.Name
                    PackId = $_.Task.PackId
                    Category = $_.Task.Category
                    Difficulty = $_.Task.Difficulty
                    Success = $_.Validation.Success
                    Confidence = $_.Validation.Confidence
                    MinConfidenceRequired = $_.Validation.MinConfidenceRequired
                    PassedProperties = ($_.Validation.PropertyValidation.PassedProperties -join ';')
                    FailedProperties = ($_.Validation.PropertyValidation.FailedProperties -join ';')
                    EvidenceSatisfied = $_.Validation.Evidence.Satisfied
                    EvidenceMissing = $_.Validation.Evidence.MissingCount
                    ForbiddenViolations = $_.Validation.ForbiddenPatterns.Violations
                    Errors = ($_.Validation.Errors -join ';')
                    StartedAt = $_.Timing.StartedAt
                    CompletedAt = $_.Timing.CompletedAt
                    DurationSeconds = $_.Timing.DurationSeconds
                }

                if ($IncludeProperties -and $_.Validation.PropertyValidation.Details) {
                    foreach ($prop in $_.Validation.PropertyValidation.Details.Keys) {
                        $row["Prop_$prop"] = $_.Validation.PropertyValidation.Details[$prop].Match
                    }
                }

                [PSCustomObject]$row
            }

            # Ensure output directory exists
            $outputDir = Split-Path -Parent $OutputPath
            if ($outputDir -and -not (Test-Path $outputDir)) {
                $null = New-Item -ItemType Directory -Path $outputDir -Force
            }

            # Export based on format
            switch ($Format) {
                'json' {
                    $exportData | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputPath -Encoding UTF8
                }
                'csv' {
                    $exportData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
                }
            }

            $fileInfo = Get-Item $OutputPath
            Write-Verbose "Exported $($results.Count) results to: $OutputPath"
            return $fileInfo
        }
        catch {
            Write-Error "Failed to export golden task results: $_"
            throw
        }
    }
}

#endregion

#region Get-GoldenTaskMetrics

<#
.SYNOPSIS
    Calculates detailed pass/fail metrics for golden task evaluation.

.DESCRIPTION
    Calculates comprehensive metrics for golden task results including:
    - Pass/fail counts and rates by various dimensions
    - Confidence score statistics
    - Regression indicators
    - Trend analysis
    - Score calculation with weighted components

.PARAMETER PackId
    The pack ID to calculate metrics for

.PARAMETER TaskId
    Specific task ID for detailed metrics

.PARAMETER TimeRange
    Time range for results to include ('24h', '7d', '30d', '90d', 'all')

.PARAMETER Category
    Filter by task category

.PARAMETER Difficulty
    Filter by task difficulty

.PARAMETER CompareToPrevious
    Include comparison with previous run for regression detection

.EXAMPLE
    $metrics = Get-GoldenTaskMetrics -PackId "rpgmaker-mz" -TimeRange "7d"
    Write-Host "Pass Rate: $($metrics.Summary.PassRate)%"
    Write-Host "Regression Detected: $($metrics.Regression.RegressionDetected)"

.OUTPUTS
    [hashtable] Comprehensive metrics including summary, breakdowns, trends, and regression status
#>
function Get-GoldenTaskMetrics {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter(Mandatory = $false)]
        [string]$TaskId,

        [Parameter(Mandatory = $false)]
        [ValidateSet('24h', '7d', '30d', '90d', 'all')]
        [string]$TimeRange = '7d',

        [Parameter(Mandatory = $false)]
        [string]$Category = '',

        [Parameter(Mandatory = $false)]
        [string]$Difficulty = '',

        [Parameter(Mandatory = $false)]
        [switch]$CompareToPrevious
    )

    begin {
        Write-Verbose "Calculating golden task metrics for pack: $PackId"
    }

    process {
        # Calculate cutoff date
        $cutoff = switch ($TimeRange) {
            '24h' { (Get-Date).AddHours(-24) }
            '7d' { (Get-Date).AddDays(-7) }
            '30d' { (Get-Date).AddDays(-30) }
            '90d' { (Get-Date).AddDays(-90) }
            'all' { [DateTime]::MinValue }
            default { (Get-Date).AddDays(-7) }
        }

        # Get results
        $params = @{ PackId = $PackId; FromDate = $cutoff }
        if ($TaskId) { $params['TaskId'] = $TaskId }
        $results = Get-GoldenTaskResults @params

        # Apply filters
        if ($Category) {
            $results = $results | Where-Object { $_.Task.Category -eq $Category }
        }
        if ($Difficulty) {
            $results = $results | Where-Object { $_.Task.Difficulty -eq $Difficulty }
        }

        if ($results.Count -eq 0) {
            return @{
                PackId = $PackId
                TimeRange = $TimeRange
                Summary = @{
                    TotalTasks = 0
                    PassedTasks = 0
                    FailedTasks = 0
                    PassRate = 0
                    AverageConfidence = 0
                    Score = 0
                    Grade = 'N/A'
                }
                Breakdowns = @{}
                Trends = @{}
                Regression = @{ RegressionDetected = $false }
                Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            }
        }

        # Get latest result per task
        $latestResults = @{}
        foreach ($result in $results) {
            $tid = $result.Task.TaskId
            if (-not $latestResults.ContainsKey($tid) -or 
                $result.Timing.CompletedAt -gt $latestResults[$tid].Timing.CompletedAt) {
                $latestResults[$tid] = $result
            }
        }
        $evaluatedResults = $latestResults.Values

        # Summary metrics
        $passed = ($evaluatedResults | Where-Object { $_.Validation.Success }).Count
        $failed = $evaluatedResults.Count - $passed
        $passRate = if ($evaluatedResults.Count -gt 0) { ($passed / $evaluatedResults.Count) * 100 } else { 0 }
        
        $confidenceValues = $evaluatedResults | ForEach-Object { $_.Validation.Confidence }
        $avgConfidence = if ($confidenceValues.Count -gt 0) { 
            ($confidenceValues | Measure-Object -Average).Average 
        } else { 0 }

        # Calculate weighted score
        $difficultyWeights = @{ easy = 1.0; medium = 1.5; hard = 2.0 }
        $weightedScore = 0
        $totalWeight = 0
        foreach ($result in $evaluatedResults) {
            $weight = $difficultyWeights[$result.Task.Difficulty]
            if ($result.Validation.Success) {
                $weightedScore += $weight * $result.Validation.Confidence * 100
            }
            $totalWeight += $weight
        }
        $finalScore = if ($totalWeight -gt 0) { ($weightedScore / $totalWeight) } else { 0 }

        # Category breakdown
        $categoryBreakdown = @{}
        foreach ($cat in ($evaluatedResults | Select-Object -ExpandProperty Task | Select-Object -ExpandProperty Category -Unique)) {
            $catResults = $evaluatedResults | Where-Object { $_.Task.Category -eq $cat }
            $catPassed = ($catResults | Where-Object { $_.Validation.Success }).Count
            $categoryBreakdown[$cat] = @{
                Total = $catResults.Count
                Passed = $catPassed
                Failed = $catResults.Count - $catPassed
                PassRate = if ($catResults.Count -gt 0) { ($catPassed / $catResults.Count) * 100 } else { 0 }
            }
        }

        # Difficulty breakdown
        $difficultyBreakdown = @{}
        foreach ($diff in ($evaluatedResults | Select-Object -ExpandProperty Task | Select-Object -ExpandProperty Difficulty -Unique)) {
            $diffResults = $evaluatedResults | Where-Object { $_.Task.Difficulty -eq $diff }
            $diffPassed = ($diffResults | Where-Object { $_.Validation.Success }).Count
            $difficultyBreakdown[$diff] = @{
                Total = $diffResults.Count
                Passed = $diffPassed
                Failed = $diffResults.Count - $diffPassed
                PassRate = if ($diffResults.Count -gt 0) { ($diffPassed / $diffResults.Count) * 100 } else { 0 }
            }
        }

        # Tag breakdown
        $tagBreakdown = @{}
        foreach ($result in $evaluatedResults) {
            foreach ($tag in $result.Task.Tags) {
                if (-not $tagBreakdown.ContainsKey($tag)) {
                    $tagBreakdown[$tag] = @{ Total = 0; Passed = 0; Failed = 0 }
                }
                $tagBreakdown[$tag].Total++
                if ($result.Validation.Success) {
                    $tagBreakdown[$tag].Passed++
                } else {
                    $tagBreakdown[$tag].Failed++
                }
            }
        }
        foreach ($tag in $tagBreakdown.Keys) {
            $tagBreakdown[$tag].PassRate = if ($tagBreakdown[$tag].Total -gt 0) { 
                ($tagBreakdown[$tag].Passed / $tagBreakdown[$tag].Total) * 100 
            } else { 0 }
        }

        # Trend analysis (if multiple results per task)
        $trends = @{
            Improving = @()
            Declining = @()
            Stable = @()
        }
        if ($CompareToPrevious) {
            $previousCutoff = $cutoff.AddDays(-($cutoff - [DateTime]::MinValue).Days / 2)
            $previousParams = @{ PackId = $PackId; FromDate = $previousCutoff; ToDate = $cutoff }
            if ($TaskId) { $previousParams['TaskId'] = $TaskId }
            $previousResults = Get-GoldenTaskResults @previousParams

            foreach ($taskId in $latestResults.Keys) {
                $current = $latestResults[$taskId]
                $previous = $previousResults | Where-Object { $_.Task.TaskId -eq $taskId } | 
                    Sort-Object { $_.Timing.CompletedAt } -Descending | Select-Object -First 1

                if ($previous) {
                    $currentSuccess = $current.Validation.Success
                    $previousSuccess = $previous.Validation.Success
                    $currentConf = $current.Validation.Confidence
                    $previousConf = $previous.Validation.Confidence

                    if ($currentSuccess -and -not $previousSuccess) {
                        $trends.Improving += $taskId
                    } elseif (-not $currentSuccess -and $previousSuccess) {
                        $trends.Declining += $taskId
                    } elseif ([Math]::Abs($currentConf - $previousConf) -lt 0.05) {
                        $trends.Stable += $taskId
                    } elseif ($currentConf -gt $previousConf) {
                        $trends.Improving += $taskId
                    } else {
                        $trends.Declining += $taskId
                    }
                }
            }
        }

        # Regression detection
        $regression = @{
            RegressionDetected = $trends.Declining.Count -gt 0
            NewFailures = $trends.Declining
            TasksBelowThreshold = @()
            ConfidenceDrops = @()
        }

        foreach ($result in $evaluatedResults) {
            if (-not $result.Validation.Success -or 
                $result.Validation.Confidence -lt $result.Validation.MinConfidenceRequired) {
                $regression.TasksBelowThreshold += @{
                    TaskId = $result.Task.TaskId
                    Confidence = $result.Validation.Confidence
                    Required = $result.Validation.MinConfidenceRequired
                }
            }
        }

        # Determine grade
        $grade = switch ($finalScore) {
            { $_ -ge 95 } { 'A+' }
            { $_ -ge 90 } { 'A' }
            { $_ -ge 85 } { 'B+' }
            { $_ -ge 80 } { 'B' }
            { $_ -ge 70 } { 'C' }
            { $_ -ge 60 } { 'D' }
            default { 'F' }
        }

        return @{
            PackId = $PackId
            TimeRange = $TimeRange
            Summary = @{
                TotalTasks = $evaluatedResults.Count
                PassedTasks = $passed
                FailedTasks = $failed
                PassRate = [math]::Round($passRate, 2)
                AverageConfidence = [math]::Round($avgConfidence, 4)
                WeightedScore = [math]::Round($finalScore, 2)
                Grade = $grade
            }
            Breakdowns = @{
                ByCategory = $categoryBreakdown
                ByDifficulty = $difficultyBreakdown
                ByTag = $tagBreakdown
            }
            Trends = $trends
            Regression = $regression
            Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        }
    }
}

#endregion

#region Invoke-GoldenTaskSuite

<#
.SYNOPSIS
    Runs all tasks in a golden task suite.

.DESCRIPTION
    Executes all golden tasks within a defined suite. Supports filtering,
    parallel execution, and result recording. This is the suite-level
    equivalent of Invoke-PackGoldenTasks but operates on a suite object.

.PARAMETER Suite
    The golden task suite to run (hashtable from New-GoldenTaskSuite or Import-GoldenTaskSuite)

.PARAMETER SuitePath
    Path to a suite JSON file to load and run

.PARAMETER Filter
    Hashtable of filters (category, difficulty, tags, excludeTags)

.PARAMETER Parallel
    Run tasks in parallel

.PARAMETER MaxParallelJobs
    Maximum parallel jobs (default: 4)

.PARAMETER RecordResults
    Record results to history

.PARAMETER FailFast
    Stop on first failure

.PARAMETER ExportResults
    Export results after completion

.PARAMETER ExportPath
    Path for exported results

.PARAMETER ExportFormat
    Format for exported results (json, csv)

.EXAMPLE
    $suite = New-GoldenTaskSuite -SuiteName "Regression Tests" -Tasks $tasks
    Invoke-GoldenTaskSuite -Suite $suite -RecordResults

.EXAMPLE
    Invoke-GoldenTaskSuite -SuitePath "./suites/test-suite.json" -Parallel

.OUTPUTS
    [hashtable] Suite execution results including summary and individual task results
#>
function Invoke-GoldenTaskSuite {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'SuiteObject')]
        [hashtable]$Suite,

        [Parameter(Mandatory = $true, ParameterSetName = 'SuitePath')]
        [string]$SuitePath,

        [Parameter(Mandatory = $false)]
        [hashtable]$Filter = @{},

        [Parameter(Mandatory = $false)]
        [switch]$Parallel,

        [Parameter(Mandatory = $false)]
        [int]$MaxParallelJobs = $script:GoldenTaskConfig.MaxParallelJobs,

        [Parameter(Mandatory = $false)]
        [switch]$RecordResults,

        [Parameter(Mandatory = $false)]
        [switch]$FailFast,

        [Parameter(Mandatory = $false)]
        [switch]$ExportResults,

        [Parameter(Mandatory = $false)]
        [string]$ExportPath = "",

        [Parameter(Mandatory = $false)]
        [ValidateSet('json', 'csv')]
        [string]$ExportFormat = 'json'
    )

    begin {
        Write-Verbose "Starting golden task suite execution"

        # Load suite if path provided
        if ($SuitePath) {
            $Suite = Import-GoldenTaskSuite -Path $SuitePath
        }

        Write-Verbose "Suite: $($Suite.suiteName) with $($Suite.tasks.Count) tasks"
    }

    process {
        try {
            $startTime = Get-Date
            $allTasks = $Suite.tasks

            # Apply filters
            $filteredTasks = $allTasks | Where-Object {
                $task = $_
                $include = $true

                if ($Filter.category -and $task.category -ne $Filter.category) { $include = $false }
                if ($Filter.difficulty -and $task.difficulty -ne $Filter.difficulty) { $include = $false }
                if ($Filter.tags) {
                    foreach ($tag in $Filter.tags) {
                        if ($task.tags -notcontains $tag) { $include = $false; break }
                    }
                }
                if ($Filter.excludeTags) {
                    foreach ($tag in $Filter.excludeTags) {
                        if ($task.tags -contains $tag) { $include = $false; break }
                    }
                }

                $include
            }

            $tasksToRun = @($filteredTasks)
            Write-Verbose "Running $($tasksToRun.Count) tasks after filtering"

            # Run tasks
            $results = @()
            if ($Parallel -and $tasksToRun.Count -gt 1) {
                $results = Invoke-ParallelGoldenTasks -Tasks $tasksToRun -MaxParallelJobs $MaxParallelJobs `
                    -RecordResults:$RecordResults -FailFast:$FailFast
            } else {
                foreach ($task in $tasksToRun) {
                    Write-Verbose "Running task: $($task.taskId)"
                    $result = Invoke-GoldenTask -Task $task -RecordResults:$RecordResults
                    $results += $result

                    if ($FailFast -and -not $result.Validation.Success) {
                        Write-Warning "Task '$($task.taskId)' failed and FailFast is enabled. Stopping."
                        break
                    }
                }
            }

            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds

            # Calculate statistics
            $passed = ($results | Where-Object { $_.Validation.Success }).Count
            $failed = $results.Count - $passed
            $passRate = if ($results.Count -gt 0) { ($passed / $results.Count) * 100 } else { 0 }
            $avgConfidence = if ($results.Count -gt 0) {
                ($results | Measure-Object -Property { $_.Validation.Confidence } -Average).Average
            } else { 0 }

            # Category breakdown
            $categoryStats = @{}
            foreach ($result in $results) {
                $cat = $result.Task.Category
                if (-not $categoryStats.ContainsKey($cat)) {
                    $categoryStats[$cat] = @{ Passed = 0; Failed = 0; Total = 0 }
                }
                $categoryStats[$cat].Total++
                if ($result.Validation.Success) {
                    $categoryStats[$cat].Passed++
                } else {
                    $categoryStats[$cat].Failed++
                }
            }

            # Difficulty breakdown
            $difficultyStats = @{}
            foreach ($result in $results) {
                $diff = $result.Task.Difficulty
                if (-not $difficultyStats.ContainsKey($diff)) {
                    $difficultyStats[$diff] = @{ Passed = 0; Failed = 0; Total = 0 }
                }
                $difficultyStats[$diff].Total++
                if ($result.Validation.Success) {
                    $difficultyStats[$diff].Passed++
                } else {
                    $difficultyStats[$diff].Failed++
                }
            }

            $summary = @{
                SuiteName = $Suite.suiteName
                SuiteVersion = $Suite.version
                TasksRun = $results.Count
                Passed = $passed
                Failed = $failed
                PassRate = [math]::Round($passRate, 2)
                AverageConfidence = [math]::Round($avgConfidence, 4)
                DurationSeconds = [math]::Round($duration, 2)
                CategoryBreakdown = $categoryStats
                DifficultyBreakdown = $difficultyStats
                Filter = $Filter
                Tasks = $results
                StartedAt = $startTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
                CompletedAt = $endTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
            }

            # Export results if requested
            if ($ExportResults) {
                if (-not $ExportPath) {
                    $ExportPath = Join-Path $script:GoldenTaskConfig.ResultsDirectory `
                        "suite-$($Suite.suiteName)-$(Get-Date -Format 'yyyyMMdd-HHmmss').$ExportFormat"
                }
                Export-GoldenTaskResults -OutputPath $ExportPath -Format $ExportFormat
                $summary.ExportPath = $ExportPath
            }

            foreach ($line in @(
                '',
                "Golden Task Suite Summary - '$($Suite.suiteName)'",
                "  Tasks Run: $($summary.TasksRun)",
                "  Passed: $($summary.Passed)",
                "  Failed: $($summary.Failed)",
                "  Pass Rate: $($summary.PassRate)%",
                "  Avg Confidence: $($summary.AverageConfidence)"
            )) {
                Write-Information $line -InformationAction Continue
            }

            return $summary
        }
        catch {
            Write-Error "Suite execution failed: $_"
            throw
        }
    }
}

#endregion

#region Compare-GoldenTaskRuns

<#
.SYNOPSIS
    Compares golden task results across multiple runs for regression detection.

.DESCRIPTION
    Compares golden task evaluation results between two or more runs to detect
    regressions, improvements, and stability issues. Generates a detailed
    comparison report showing changes in pass/fail status, confidence scores,
    and execution times.

.PARAMETER PackId
    Pack ID to compare

.PARAMETER BaselineRun
    Date/time of the baseline run to compare against

.PARAMETER ComparisonRun
    Date/time of the comparison run (default: most recent)

.PARAMETER TaskId
    Specific task ID to compare

.PARAMETER Threshold
    Confidence difference threshold for flagging changes (default: 0.05)

.PARAMETER FailOnRegression
    Return non-success status if regressions are detected

.EXAMPLE
    $comparison = Compare-GoldenTaskRuns -PackId "rpgmaker-mz" -BaselineRun (Get-Date).AddDays(-7)

.EXAMPLE
    Compare-GoldenTaskRuns -TaskId "gt-rpgmaker-mz-001" -BaselineRun "2026-04-01" -FailOnRegression

.OUTPUTS
    [hashtable] Comparison results including regressions, improvements, and summary statistics
#>
function Compare-GoldenTaskRuns {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'PackCompare')]
        [string]$PackId,

        [Parameter(Mandatory = $true, ParameterSetName = 'TaskCompare')]
        [string]$TaskId,

        [Parameter(Mandatory = $true)]
        [DateTime]$BaselineRun,

        [Parameter(Mandatory = $false)]
        [DateTime]$ComparisonRun = (Get-Date),

        [Parameter(Mandatory = $false)]
        [double]$Threshold = 0.05,

        [Parameter(Mandatory = $false)]
        [switch]$FailOnRegression
    )

    begin {
        Write-Verbose "Comparing golden task runs"
        Write-Verbose "Baseline: $BaselineRun"
        Write-Verbose "Comparison: $ComparisonRun"
    }

    process {
        try {
            # Get baseline results
            $baselineParams = @{
                FromDate = $BaselineRun.Date
                ToDate = $BaselineRun.Date.AddDays(1)
            }
            if ($PackId) { $baselineParams['PackId'] = $PackId }
            if ($TaskId) { $baselineParams['TaskId'] = $TaskId }
            
            $baselineResults = Get-GoldenTaskResults @baselineParams | 
                Group-Object { $_.Task.TaskId } | 
                ForEach-Object { $_.Group | Sort-Object { $_.Timing.CompletedAt } -Descending | Select-Object -First 1 }

            # Get comparison results
            $comparisonParams = @{
                FromDate = $ComparisonRun.Date.AddDays(-7)
                ToDate = $ComparisonRun
            }
            if ($PackId) { $comparisonParams['PackId'] = $PackId }
            if ($TaskId) { $comparisonParams['TaskId'] = $TaskId }
            
            $comparisonResults = Get-GoldenTaskResults @comparisonParams | 
                Group-Object { $_.Task.TaskId } | 
                ForEach-Object { $_.Group | Sort-Object { $_.Timing.CompletedAt } -Descending | Select-Object -First 1 }

            # Initialize comparison collections
            $regressions = @()
            $improvements = @()
            $stable = @()
            $newTasks = @()
            $missingTasks = @()

            # Create lookup dictionaries
            $baselineLookup = @{}
            foreach ($result in $baselineResults) {
                $baselineLookup[$result.Task.TaskId] = $result
            }

            $comparisonLookup = @{}
            foreach ($result in $comparisonResults) {
                $comparisonLookup[$result.Task.TaskId] = $result
            }

            # Compare all tasks from comparison run
            foreach ($taskId in $comparisonLookup.Keys) {
                $current = $comparisonLookup[$taskId]
                
                if (-not $baselineLookup.ContainsKey($taskId)) {
                    $newTasks += @{
                        TaskId = $taskId
                        TaskName = $current.Task.Name
                        CurrentStatus = if ($current.Validation.Success) { "PASSED" } else { "FAILED" }
                        CurrentConfidence = $current.Validation.Confidence
                    }
                    continue
                }

                $baseline = $baselineLookup[$taskId]
                
                $baselineSuccess = $baseline.Validation.Success
                $currentSuccess = $current.Validation.Success
                $baselineConfidence = $baseline.Validation.Confidence
                $currentConfidence = $current.Validation.Confidence
                $confidenceDelta = $currentConfidence - $baselineConfidence

                $comparisonItem = @{
                    TaskId = $taskId
                    TaskName = $current.Task.Name
                    BaselineStatus = if ($baselineSuccess) { "PASSED" } else { "FAILED" }
                    CurrentStatus = if ($currentSuccess) { "PASSED" } else { "FAILED" }
                    BaselineConfidence = [math]::Round($baselineConfidence, 4)
                    CurrentConfidence = [math]::Round($currentConfidence, 4)
                    ConfidenceDelta = [math]::Round($confidenceDelta, 4)
                    BaselineDuration = $baseline.Timing.DurationSeconds
                    CurrentDuration = $current.Timing.DurationSeconds
                    DurationDelta = [math]::Round($current.Timing.DurationSeconds - $baseline.Timing.DurationSeconds, 2)
                }

                # Detect regression (was passing, now failing)
                if ($baselineSuccess -and -not $currentSuccess) {
                    $comparisonItem.RegressionType = "CRITICAL - Pass to Fail"
                    $regressions += $comparisonItem
                }
                # Detect pass but confidence drop below threshold
                elseif ($baselineSuccess -and $currentSuccess -and $confidenceDelta -lt -$Threshold) {
                    $comparisonItem.RegressionType = "WARNING - Confidence Drop"
                    $regressions += $comparisonItem
                }
                # Detect improvement (was failing, now passing)
                elseif (-not $baselineSuccess -and $currentSuccess) {
                    $comparisonItem.ImprovementType = "RECOVERED - Fail to Pass"
                    $improvements += $comparisonItem
                }
                # Detect confidence improvement above threshold
                elseif ($baselineSuccess -and $currentSuccess -and $confidenceDelta -gt $Threshold) {
                    $comparisonItem.ImprovementType = "ENHANCED - Confidence Gain"
                    $improvements += $comparisonItem
                }
                else {
                    $stable += $comparisonItem
                }
            }

            # Find missing tasks (in baseline but not in current)
            foreach ($taskId in $baselineLookup.Keys) {
                if (-not $comparisonLookup.ContainsKey($taskId)) {
                    $baseline = $baselineLookup[$taskId]
                    $missingTasks += @{
                        TaskId = $taskId
                        TaskName = $baseline.Task.Name
                        BaselineStatus = if ($baseline.Validation.Success) { "PASSED" } else { "FAILED" }
                        BaselineConfidence = $baseline.Validation.Confidence
                    }
                }
            }

            # Calculate statistics
            $totalCompared = $regressions.Count + $improvements.Count + $stable.Count
            $regressionRate = if ($totalCompared -gt 0) { ($regressions.Count / $totalCompared) * 100 } else { 0 }
            $improvementRate = if ($totalCompared -gt 0) { ($improvements.Count / $totalCompared) * 100 } else { 0 }

            # Determine overall status
            $criticalRegressions = ($regressions | Where-Object { $_.RegressionType -eq "CRITICAL - Pass to Fail" }).Count
            $hasRegression = $criticalRegressions -gt 0

            $result = @{
                PackId = $PackId
                TaskId = $TaskId
                BaselineRun = $BaselineRun.ToString("yyyy-MM-ddTHH:mm:ssZ")
                ComparisonRun = $ComparisonRun.ToString("yyyy-MM-ddTHH:mm:ssZ")
                Summary = @{
                    TotalTasksCompared = $totalCompared
                    TotalRegressions = $regressions.Count
                    CriticalRegressions = $criticalRegressions
                    TotalImprovements = $improvements.Count
                    StableTasks = $stable.Count
                    NewTasks = $newTasks.Count
                    MissingTasks = $missingTasks.Count
                    RegressionRate = [math]::Round($regressionRate, 2)
                    ImprovementRate = [math]::Round($improvementRate, 2)
                    HasRegression = $hasRegression
                    Status = if ($hasRegression) { "REGRESSION_DETECTED" } elseif ($improvements.Count -gt 0) { "IMPROVED" } else { "STABLE" }
                }
                Regressions = $regressions
                Improvements = $improvements
                Stable = $stable
                NewTasks = $newTasks
                MissingTasks = $missingTasks
                Threshold = $Threshold
                GeneratedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            }

            # Output summary
            foreach ($line in @(
                '',
                'Golden Task Run Comparison',
                "  Pack: $PackId$(if($TaskId){" / Task: $TaskId"})",
                "  Baseline: $($result.BaselineRun)",
                "  Comparison: $($result.ComparisonRun)",
                "  Tasks Compared: $($result.Summary.TotalTasksCompared)",
                $(if ($result.Summary.CriticalRegressions -gt 0) { "  CRITICAL REGRESSIONS: $($result.Summary.CriticalRegressions)" }),
                $(if ($result.Summary.TotalRegressions -gt 0) { "  Total Regressions: $($result.Summary.TotalRegressions)" }),
                $(if ($result.Summary.TotalImprovements -gt 0) { "  Improvements: $($result.Summary.TotalImprovements)" }),
                "  Status: $($result.Summary.Status)"
            ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
                Write-Information $line -InformationAction Continue
            }

            if ($FailOnRegression -and $hasRegression) {
                Write-Error "Regressions detected in golden task comparison"
            }

            return $result
        }
        catch {
            Write-Error "Failed to compare golden task runs: $_"
            throw
        }
    }
}

#endregion

#region Module Export

# Export all public functions
Export-ModuleMember -Function @(
    # Core golden task functions
    'New-GoldenTask'
    'Invoke-GoldenTask'
    'Test-GoldenTaskResult'
    'Get-GoldenTaskScore'
    'Get-GoldenTaskMetrics'
    'Export-GoldenTaskReport'
    'Export-GoldenTaskResults'
    
    # Pack evaluation
    'Invoke-PackGoldenTasks'
    'Get-PredefinedGoldenTasks'
    
    # Results and history
    'Get-GoldenTaskResults'
    
    # Suite management
    'New-GoldenTaskSuite'
    'Export-GoldenTaskSuite'
    'Import-GoldenTaskSuite'
    'Invoke-GoldenTaskSuite'
    
    # Comparison and regression
    'Compare-GoldenTaskRuns'
    
    # Validation helpers
    'Test-PropertyBasedExpectation'
)

#endregion
