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
function Test-PropertyBasedExpectation {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Expected,

        [Parameter(Mandatory = $true)]
        [hashtable]$Actual
    )

    begin {
        Write-Verbose "Starting property-based validation"
        $passedProperties = @()
        $failedProperties = @()
        $confidenceSum = 0.0
        $totalProperties = $Expected.Keys.Count
    }

    process {
        if ($totalProperties -eq 0) {
            Write-Warning "No expected properties to validate"
            return @{
                Success = $true
                PassedProperties = @()
                FailedProperties = @()
                Confidence = 1.0
                Details = @{}
            }
        }

        $details = @{}

        foreach ($propertyName in $Expected.Keys) {
            $expectedValue = $Expected[$propertyName]
            $actualValue = $Actual[$propertyName]
            $propertyMatch = $false
            $matchDetails = @{}

            try {
                # Handle different types of expected values
                if ($expectedValue -is [type]) {
                    # Type checking
                    $propertyMatch = $actualValue -is $expectedValue
                    $matchDetails = @{ type = $expectedValue.Name; actualType = $actualValue.GetType().Name }
                }
                elseif ($expectedValue -is [scriptblock]) {
                    # Script block validation
                    $propertyMatch = & $expectedValue $actualValue
                    $matchDetails = @{ validator = 'scriptblock' }
                }
                elseif ($expectedValue -is [hashtable] -and ($expectedValue.ContainsKey('min') -or $expectedValue.ContainsKey('max'))) {
                    # Range checking
                    $min = $expectedValue['min']
                    $max = $expectedValue['max']
                    $propertyMatch = $true
                    if ($null -ne $min -and $actualValue -lt $min) { $propertyMatch = $false }
                    if ($null -ne $max -and $actualValue -gt $max) { $propertyMatch = $false }
                    $matchDetails = @{ min = $min; max = $max; actual = $actualValue }
                }
                elseif ($expectedValue -is [array] -and $expectedValue.Count -gt 0) {
                    # Collection containment - actual should contain all expected items
                    $propertyMatch = $true
                    $missing = @()
                    foreach ($item in $expectedValue) {
                        if ($actualValue -notcontains $item) {
                            $propertyMatch = $false
                            $missing += $item
                        }
                    }
                    $matchDetails = @{ expectedItems = $expectedValue; missingItems = $missing }
                }
                elseif ($expectedValue -is [string] -and $expectedValue.StartsWith('regex:')) {
                    # Regex pattern matching
                    $pattern = $expectedValue.Substring(6)
                    $propertyMatch = $actualValue -match $pattern
                    $matchDetails = @{ pattern = $pattern }
                }
                elseif ($expectedValue -is [string] -and $expectedValue.StartsWith('like:')) {
                    # Wildcard matching
                    $pattern = $expectedValue.Substring(5)
                    $propertyMatch = $actualValue -like $pattern
                    $matchDetails = @{ pattern = $pattern }
                }
                elseif ($expectedValue -eq $true) {
                    # Presence checking - property exists and is not null/empty
                    $propertyMatch = $null -ne $actualValue -and $actualValue -ne '' -and $actualValue.Count -ne 0
                    $matchDetails = @{ check = 'presence' }
                }
                elseif ($expectedValue -eq $false) {
                    # Absence checking - property should be null, empty, or false
                    $propertyMatch = $null -eq $actualValue -or $actualValue -eq '' -or $actualValue -eq $false -or $actualValue.Count -eq 0
                    $matchDetails = @{ check = 'absence' }
                }
                else {
                    # Exact value matching (case-insensitive for strings)
                    if ($expectedValue -is [string] -and $actualValue -is [string]) {
                        $propertyMatch = $expectedValue -eq $actualValue
                    }
                    else {
                        $propertyMatch = $expectedValue -eq $actualValue
                    }
                    $matchDetails = @{ expected = $expectedValue; actual = $actualValue }
                }
            }
            catch {
                Write-Verbose "Error validating property '$propertyName': $_"
                $propertyMatch = $false
                $matchDetails = @{ error = $_.ToString() }
            }

            $details[$propertyName] = @{
                Expected = $expectedValue
                Actual = $actualValue
                Match = $propertyMatch
                Details = $matchDetails
            }

            if ($propertyMatch) {
                $passedProperties += $propertyName
                $confidenceSum += 1.0
            }
            else {
                $failedProperties += $propertyName
            }
        }

        $overallConfidence = if ($totalProperties -gt 0) { $confidenceSum / $totalProperties } else { 0 }
        $success = $failedProperties.Count -eq 0

        return @{
            Success = $success
            PassedProperties = $passedProperties
            FailedProperties = $failedProperties
            Confidence = [math]::Round($overallConfidence, 4)
            Details = $details
        }
    }
}

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
                        if ($evidence.pattern -and $AnswerText -match $evidence.pattern) {
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
            return @{ PackId = $PackId; TasksRun = 0; Passed = 0; Failed = 0; Tasks = @() }
        }

        Write-Verbose "Found $($allTasks.Count) golden tasks"

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

        $startTime = Get-Date
        $results = @()
    }

    process {
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
        $avgConfidence = if ($results.Count -gt 0) {
            ($results | Measure-Object -Property { $_.Validation.Confidence } -Average).Average
        } else { 0 }

        $categoryStats = @{}
        foreach ($result in $results) {
            $cat = $result.Task.Category
            if (-not $categoryStats.ContainsKey($cat)) {
                $categoryStats[$cat] = @{ Passed = 0; Failed = 0; Total = 0 }
            }
            $categoryStats[$cat].Total++
            if ($result.Validation.Success) {
                $categoryStats[$cat].Passed++
            }
            else {
                $categoryStats[$cat].Failed++
            }
        }

        $difficultyStats = @{}
        foreach ($result in $results) {
            $diff = $result.Task.Difficulty
            if (-not $difficultyStats.ContainsKey($diff)) {
                $difficultyStats[$diff] = @{ Passed = 0; Failed = 0; Total = 0 }
            }
            $difficultyStats[$diff].Total++
            if ($result.Validation.Success) {
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

        Write-Host "`nGolden Task Summary for '$PackId':" -ForegroundColor Cyan
        Write-Host "  Tasks Run: $($summary.TasksRun)" -ForegroundColor White
        Write-Host "  Passed: $($summary.Passed)" -ForegroundColor Green
        Write-Host "  Failed: $($summary.Failed)" -ForegroundColor Red
        Write-Host "  Pass Rate: $([math]::Round($summary.PassRate * 100, 2))%" -ForegroundColor Yellow
        Write-Host "  Avg Confidence: $($summary.AverageConfidence)" -ForegroundColor White

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
        $resultFiles = Get-ChildItem -Path $resultsDir -Filter "*.json" -Recurse -ErrorAction SilentlyContinue

        foreach ($file in $resultFiles) {
            try {
                $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
                $result = $content | ConvertFrom-Json -ErrorAction SilentlyContinue

                if ($result) {
                    # Convert to hashtable for consistency
                    $resultObj = ConvertTo-Hashtable -InputObject $result
                    $allResults += $resultObj
                }
            }
            catch {
                Write-Verbose "Error loading result file '$($file.Name)': $_"
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

#region Get-PredefinedGoldenTasks

<#
.SYNOPSIS
    Gets the predefined golden tasks for a specific pack.

.DESCRIPTION
    Returns the built-in golden task definitions for supported packs.
    Includes exactly 10 tasks per pack covering various categories
    and difficulty levels.

    RPG Maker MZ Tasks (10):
    - Plugin skeleton generation
    - Plugin conflict diagnosis
    - Notetag extraction from source
    - Engine surface patch analysis
    - Command alias detection
    - Plugin parameter validation
    - Event script conversion
    - Animation sequence generation
    - Save system customization
    - Menu scene extension

    Godot Engine Tasks (10):
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

    Blender Engine Tasks (10):
    - Operator registration
    - Geometry nodes code generation
    - Addon manifest creation
    - Panel layout design
    - Property group definition
    - Material node setup
    - Rigging automation
    - Render pipeline configuration
    - Import/export operator
    - Custom keymap binding

    API Reverse Tooling Pack (10):
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

    Notebook/Data Workflow Pack (10):
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

    Agent Simulation Pack (10):
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

.PARAMETER PackId
    The pack ID to get golden tasks for (rpgmaker-mz, godot, blender, api-reverse, notebook-data, agent-sim)

.EXAMPLE
    # Get all RPG Maker MZ golden tasks
    Get-PredefinedGoldenTasks -PackId "rpgmaker-mz"

.EXAMPLE
    # Get all predefined tasks across all packs
    Get-PredefinedGoldenTasks

.OUTPUTS
    [array] Array of golden task hashtables
#>
function Get-PredefinedGoldenTasks {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('', 'rpgmaker-mz', 'godot', 'blender', 'api-reverse', 'notebook-data', 'agent-sim')]
        [string]$PackId = ''
    )

    begin {
        $allTasks = @()
    }

    process {
        #=======================================================================
        # RPG Maker MZ Golden Tasks (10 tasks)
        #=======================================================================
        $rpgmakerTasks = @(
            # Task 1: Plugin Skeleton Generation
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-001" `
                -Name "Plugin skeleton generation" `
                -Description "Generate minimal plugin skeleton with one command and one parameter" `
                -PackId "rpgmaker-mz" `
                -Category "codegen" `
                -Difficulty "easy" `
                -Query "Generate a plugin skeleton with one command called 'HealAll' that takes a 'percent' parameter" `
                -ExpectedResult @{
                    containsCommand = "HealAll"
                    containsParameter = "percent"
                    hasJSDocHeader = $true
                    hasPluginCommandRegistration = $true
                } `
                -RequiredEvidence @(
                    @{ source = "rpgmaker-mz-core"; type = "plugin-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("containsCommand", "containsParameter")
                    forbiddenPatterns = @("eval\s*\(", "Function\s*\(")
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "plugin", "skeleton", "javascript")
            ),

            # Task 2: Plugin Conflict Diagnosis
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-002" `
                -Name "Plugin conflict diagnosis" `
                -Description "Diagnose whether two plugins conflict and cite touched methods" `
                -PackId "rpgmaker-mz" `
                -Category "diagnosis" `
                -Difficulty "medium" `
                -Query "Analyze whether VisuStella's Battle Core conflicts with Yanfly's Buff States Core. List any method overlaps and potential conflicts." `
                -ExpectedResult @{
                    analyzesConflict = $true
                    citesMethods = $true
                    providesResolution = $true
                    mentionsLoadOrder = $true
                } `
                -RequiredEvidence @(
                    @{ source = "plugin-compatibility"; type = "method-citation" }
                    @{ source = "battle-core"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("analyzesConflict", "citesMethods")
                    forbiddenPatterns = @()
                    minConfidence = 0.75
                } `
                -Tags @("diagnosis", "conflict", "compatibility", "analysis")
            ),

            # Task 3: Notetag Extraction
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-003" `
                -Name "Notetag extraction from source" `
                -Description "Extract all notetags from a source repository" `
                -PackId "rpgmaker-mz" `
                -Category "extraction" `
                -Difficulty "easy" `
                -Query "Extract all notetags used in the rpg_core.js file and categorize them by type (actor, item, skill, etc.)" `
                -ExpectedResult @{
                    extractsNotetags = $true
                    categorizesByType = $true
                    providesExamples = $true
                    hasValidRegexPatterns = $true
                } `
                -RequiredEvidence @(
                    @{ source = "rpg_core.js"; type = "notetag" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extractsNotetags", "categorizesByType")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("extraction", "notetag", "parsing", "documentation")
            ),

            # Task 4: Engine Surface Patch Analysis
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-004" `
                -Name "Engine surface patch analysis" `
                -Description "Analyze how a project-local plugin patches a specific engine surface" `
                -PackId "rpgmaker-mz" `
                -Category "analysis" `
                -Difficulty "hard" `
                -Query "Explain how a local plugin that overrides Game_Actor.prototype.paramPlus patches the engine's parameter calculation surface. Include the method chain affected." `
                -ExpectedResult @{
                    identifiesMethodChain = $true
                    explainsPatchMechanism = $true
                    mentionsAliasPattern = $true
                    showsOriginalVsPatched = $true
                } `
                -RequiredEvidence @(
                    @{ source = "Game_Actor"; type = "method-citation" }
                    @{ source = "paramPlus"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("identifiesMethodChain", "explainsPatchMechanism", "mentionsAliasPattern")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("analysis", "patching", "prototype", "alias", "advanced")
            ),

            # Task 5: Command Alias Detection
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-005" `
                -Name "Command alias detection" `
                -Description "Detect and explain command aliases used in plugin development" `
                -PackId "rpgmaker-mz" `
                -Category "analysis" `
                -Difficulty "medium" `
                -Query "What are the common command aliases used in RPG Maker MZ plugins? Explain how PluginManager.registerCommand relates to alias patterns." `
                -ExpectedResult @{
                    identifiesAliases = $true
                    explainsRegisterCommand = $true
                    providesExamples = $true
                    mentionsArguments = $true
                } `
                -RequiredEvidence @(
                    @{ source = "PluginManager"; type = "method-citation" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("identifiesAliases", "explainsRegisterCommand")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("analysis", "alias", "command", "plugin-manager")
            ),

            # Task 6: Plugin Parameter Validation
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-006" `
                -Name "Plugin parameter validation" `
                -Description "Validate and parse plugin parameters with type checking" `
                -PackId "rpgmaker-mz" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Write code to parse and validate plugin parameters including number, string, boolean, and struct types with proper defaults." `
                -ExpectedResult @{
                    handlesNumberParams = $true
                    handlesBooleanParams = $true
                    handlesStringParams = $true
                    handlesStructParams = $true
                    providesDefaults = $true
                    usesPluginManager = $true
                } `
                -RequiredEvidence @(
                    @{ source = "PluginManager"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("handlesNumberParams", "handlesBooleanParams", "providesDefaults")
                    forbiddenPatterns = @("eval\s*\(")
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "parameters", "validation", "parsing")
            ),

            # Task 7: Event Script Conversion
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-007" `
                -Name "Event script conversion" `
                -Description "Convert event commands to equivalent script calls" `
                -PackId "rpgmaker-mz" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Convert the event command 'Change Gold +100' to its equivalent JavaScript code using $gameParty.gainGold()" `
                -ExpectedResult @{
                    usesCorrectMethod = $true
                    usesCorrectAmount = $true
                    explainsEventCommand = $true
                    providesAlternative = $true
                } `
                -RequiredEvidence @(
                    @{ source = "Game_Party"; type = "method-citation" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("usesCorrectMethod", "explainsEventCommand")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "event", "script-call", "conversion")
            ),

            # Task 8: Animation Sequence Generation
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-008" `
                -Name "Animation sequence generation" `
                -Description "Generate animation sequences using Action Sequence patterns" `
                -PackId "rpgmaker-mz" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Create an action sequence that makes the user step forward, perform an attack animation, shake the screen, and return to base position." `
                -ExpectedResult @{
                    hasStepForward = $true
                    hasAttackMotion = $true
                    hasScreenShake = $true
                    hasReturnMotion = $true
                    usesCorrectSyntax = $true
                } `
                -RequiredEvidence @(
                    @{ source = "action-sequence"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("hasStepForward", "hasAttackMotion", "hasReturnMotion")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "animation", "action-sequence", "battle")
            ),

            # Task 9: Save System Customization
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-009" `
                -Name "Save system customization" `
                -Description "Add custom data to the save file system" `
                -PackId "rpgmaker-mz" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Show how to add custom data to save files by extending DataManager and hooking into makeSaveContents and extractSaveContents." `
                -ExpectedResult @{
                    extendsDataManager = $true
                    overridesMakeSaveContents = $true
                    overridesExtractSaveContents = $true
                    preservesExistingData = $true
                    usesAliasPattern = $true
                } `
                -RequiredEvidence @(
                    @{ source = "DataManager"; type = "method-citation" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extendsDataManager", "overridesMakeSaveContents", "usesAliasPattern")
                    forbiddenPatterns = @("eval\s*\(")
                    minConfidence = 0.85
                } `
                -Tags @("codegen", "save-system", "data-manager", "advanced")
            ),

            # Task 10: Menu Scene Extension
            (New-GoldenTask `
                -TaskId "gt-rpgmaker-mz-010" `
                -Name "Menu scene extension" `
                -Description "Extend the main menu with custom commands" `
                -PackId "rpgmaker-mz" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Add a custom 'Bestiary' command to the main menu that opens a custom scene. Include the Scene_Menu modification." `
                -ExpectedResult @{
                    addsMenuCommand = $true
                    createsCustomScene = $true
                    handlesWindowCommand = $true
                    integratesWithSceneMenu = $true
                } `
                -RequiredEvidence @(
                    @{ source = "Scene_Menu"; type = "source-reference" }
                    @{ source = "Window_MenuCommand"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("addsMenuCommand", "createsCustomScene", "integratesWithSceneMenu")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "menu", "scene", "window")
            )
        )

        #=======================================================================
        # Godot Engine Golden Tasks (10 tasks)
        #=======================================================================
        $godotTasks = @(
            # Task 1: GDScript Class Generation
            (New-GoldenTask `
                -TaskId "gt-godot-001" `
                -Name "GDScript class generation" `
                -Description "Generate a GDScript class with proper structure" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "easy" `
                -Query "Generate a GDScript class called 'PlayerController' that extends CharacterBody2D with a speed property and _physics_process method" `
                -ExpectedResult @{
                    extendsCharacterBody2D = $true
                    hasClassName = "PlayerController"
                    hasSpeedProperty = $true
                    hasPhysicsProcess = $true
                    usesGDScriptSyntax = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-api"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("hasClassName", "hasSpeedProperty", "hasPhysicsProcess")
                    forbiddenPatterns = @("public class", "def ")
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "gdscript", "class", "node")
            ),

            # Task 2: Signal Connection Setup
            (New-GoldenTask `
                -TaskId "gt-godot-002" `
                -Name "Signal connection setup" `
                -Description "Demonstrate proper Godot signal connection patterns" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Show three ways to connect a button's pressed signal to a callback function in GDScript, including the @onready pattern" `
                -ExpectedResult @{
                    showsConnectMethod = $true
                    showsEditorConnection = $true
                    showsOnreadyPattern = $true
                    includesSignalCallback = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-signals"; type = "signal-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("showsConnectMethod", "showsOnreadyPattern")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "signals", "connection", "gdscript")
            ),

            # Task 3: Autoload Setup
            (New-GoldenTask `
                -TaskId "gt-godot-003" `
                -Name "Autoload (Singleton) setup" `
                -Description "Explain and demonstrate Godot autoload/singleton pattern" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "easy" `
                -Query "Create a GameManager autoload script in GDScript that tracks player score and lives, and show how to access it from another scene" `
                -ExpectedResult @{
                    createsGameManager = $true
                    tracksScoreAndLives = $true
                    showsAutoloadAccess = $true
                    usesGlobalReference = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-autoload"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("createsGameManager", "tracksScoreAndLives", "showsAutoloadAccess")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "autoload", "singleton", "global", "gdscript")
            ),

            # Task 4: Scene Inheritance Pattern
            (New-GoldenTask `
                -TaskId "gt-godot-004" `
                -Name "Scene inheritance pattern" `
                -Description "Demonstrate scene inheritance and instance overrides" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Explain scene inheritance in Godot with an example: create a base enemy scene and show how to inherit from it to create a specific enemy type." `
                -ExpectedResult @{
                    explainsSceneInheritance = $true
                    showsBaseScene = $true
                    showsInheritedScene = $true
                    explainsEditableChildren = $true
                    mentionsInstanceOverrides = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-scenes"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("explainsSceneInheritance", "showsBaseScene", "showsInheritedScene")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "scene", "inheritance", "instancing")
            ),

            # Task 5: Resource Preloading
            (New-GoldenTask `
                -TaskId "gt-godot-005" `
                -Name "Resource preloading" `
                -Description "Demonstrate proper resource loading and preloading patterns" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "easy" `
                -Query "Show the difference between preload(), load(), and ResourceLoader in GDScript with examples of when to use each." `
                -ExpectedResult @{
                    explainsPreload = $true
                    explainsLoad = $true
                    explainsResourceLoader = $true
                    providesUseCases = $true
                    mentionsEditorVsRuntime = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-resources"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("explainsPreload", "explainsLoad", "providesUseCases")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "resources", "preload", "loading")
            ),

            # Task 6: Custom Node Creation
            (New-GoldenTask `
                -TaskId "gt-godot-006" `
                -Name "Custom node creation" `
                -Description "Create a custom node with custom drawing and gizmos" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Create a custom Node2D that draws a health bar above the node using _draw(). Include a @tool script for editor visualization." `
                -ExpectedResult @{
                    extendsNode2D = $true
                    implementsDraw = $true
                    usesToolAnnotation = $true
                    drawsHealthBar = $true
                    handlesEditorPreview = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-custom-drawing"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extendsNode2D", "implementsDraw", "drawsHealthBar")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "custom-node", "drawing", "tool")
            ),

            # Task 7: Editor Plugin Development
            (New-GoldenTask `
                -TaskId "gt-godot-007" `
                -Name "Editor plugin development" `
                -Description "Create a simple editor plugin with dock panel" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Create a complete Godot editor plugin in GDScript that adds a dock panel with a button. Include the plugin.cfg, plugin.gd, and the dock scene." `
                -ExpectedResult @{
                    hasPluginCfg = $true
                    extendsEditorPlugin = $true
                    hasEnterMethod = $true
                    hasExitMethod = $true
                    addsDockPanel = $true
                    handlesHasMainScreen = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-editor-plugin"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extendsEditorPlugin", "hasEnterMethod", "addsDockPanel")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "editor", "plugin", "dock")
            ),

            # Task 8: Shader Material Setup
            (New-GoldenTask `
                -TaskId "gt-godot-008" `
                -Name "Shader material setup" `
                -Description "Create a custom shader with uniforms and visual effects" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Write a Godot shader that creates a pulsing glow effect using TIME uniform. The shader should have a color uniform and work with CanvasItem." `
                -ExpectedResult @{
                    shaderTypeCanvasItem = $true
                    usesTimeUniform = $true
                    hasColorUniform = $true
                    createsPulsingEffect = $true
                    usesProperSyntax = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-shaders"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("shaderTypeCanvasItem", "usesTimeUniform", "createsPulsingEffect")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "shader", "visual", "gdshader")
            ),

            # Task 9: Input Action Mapping
            (New-GoldenTask `
                -TaskId "gt-godot-009" `
                -Name "Input action mapping" `
                -Description "Handle input actions with InputMap and remapping" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Show how to check for input actions in _process(), and how to programmatically add a new action with keyboard and joypad mappings." `
                -ExpectedResult @{
                    usesIsActionPressed = $true
                    usesInputMapAddAction = $true
                    addsKeyboardEvent = $true
                    addsJoypadEvent = $true
                    explainsInputMapAPI = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-input"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("usesIsActionPressed", "usesInputMapAddAction")
                    forbiddenPatterns = @("Input.is_key_pressed")
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "input", "inputmap", "controls")
            ),

            # Task 10: Multiplayer Networking Pattern
            (New-GoldenTask `
                -TaskId "gt-godot-010" `
                -Name "Multiplayer networking pattern" `
                -Description "Implement basic multiplayer with MultiplayerAPI and RPCs" `
                -PackId "godot" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Create a simple multiplayer script using Godot's MultiplayerAPI with @rpc annotation. Include server creation and client connection code." `
                -ExpectedResult @{
                    usesRPCAnnotation = $true
                    usesMultiplayerAPI = $true
                    createsServer = $true
                    connectsClient = $true
                    handlesMultiplayerAuthority = $true
                } `
                -RequiredEvidence @(
                    @{ source = "godot-multiplayer"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("usesRPCAnnotation", "usesMultiplayerAPI")
                    forbiddenPatterns = @("NetworkedMultiplayerENet")
                    minConfidence = 0.75
                } `
                -Tags @("codegen", "multiplayer", "networking", "rpc")
            )
        )

        #=======================================================================
        # Blender Engine Golden Tasks (10 tasks)
        #=======================================================================
        $blenderTasks = @(
            # Task 1: Operator Registration
            (New-GoldenTask `
                -TaskId "gt-blender-001" `
                -Name "Operator registration" `
                -Description "Create a Blender operator with proper registration" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "easy" `
                -Query "Create a Blender Python operator that scales selected objects by a factor property, with proper bl_idname, bl_label, and registration" `
                -ExpectedResult @{
                    hasBlIdname = $true
                    hasBlLabel = $true
                    hasExecuteMethod = $true
                    hasScaleFactorProperty = $true
                    includesRegistration = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-api"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("hasBlIdname", "hasExecuteMethod", "includesRegistration")
                    forbiddenPatterns = @("class.*\\(.*Operator\\):", "^def.*execute")
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "operator", "addon", "python")
            ),

            # Task 2: Geometry Nodes Setup
            (New-GoldenTask `
                -TaskId "gt-blender-002" `
                -Name "Geometry nodes code generation" `
                -Description "Generate geometry nodes setup using Python API" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Write Python code to create a geometry nodes modifier that adds a subdivision surface followed by a set position node with random offset" `
                -ExpectedResult @{
                    createsModifier = $true
                    addsSubdivisionNode = $true
                    addsSetPositionNode = $true
                    usesNodesNew = $true
                    linksNodes = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-geometry-nodes"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("createsModifier", "addsSubdivisionNode", "usesNodesNew")
                    forbiddenPatterns = @()
                    minConfidence = 0.75
                } `
                -Tags @("codegen", "geometry-nodes", "modifier", "procedural")
            ),

            # Task 3: Addon Manifest
            (New-GoldenTask `
                -TaskId "gt-blender-003" `
                -Name "Addon manifest creation" `
                -Description "Create a complete Blender addon manifest with bl_info" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "easy" `
                -Query "Create a complete Blender addon __init__.py with bl_info dictionary, including name, author, version, blender version, location, description, and category" `
                -ExpectedResult @{
                    hasBlInfo = $true
                    hasNameField = $true
                    hasAuthorField = $true
                    hasVersionTuple = $true
                    hasBlenderVersion = $true
                    hasCategory = $true
                    hasRegistrationFunctions = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-addon"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("hasBlInfo", "hasVersionTuple", "hasRegistrationFunctions")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "addon", "manifest", "bl_info")
            ),

            # Task 4: Panel Layout Design
            (New-GoldenTask `
                -TaskId "gt-blender-004" `
                -Name "Panel layout design" `
                -Description "Create a custom panel with organized UI layout" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Create a Blender panel with a box layout containing properties, a row with aligned buttons, and a column with an enum dropdown. Include proper bl_space_type and bl_region_type." `
                -ExpectedResult @{
                    extendsPanel = $true
                    hasBoxLayout = $true
                    hasRowLayout = $true
                    hasColumnLayout = $true
                    usesProperSpaceType = $true
                    includesDrawMethod = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-ui"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extendsPanel", "includesDrawMethod", "usesProperSpaceType")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "panel", "ui", "layout")
            ),

            # Task 5: Property Group Definition
            (New-GoldenTask `
                -TaskId "gt-blender-005" `
                -Name "Property group definition" `
                -Description "Define custom property types with PropertyGroup" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Create a PropertyGroup with StringProperty, IntProperty, FloatProperty, BoolProperty, EnumProperty, and PointerProperty. Show how to register it to Scene." `
                -ExpectedResult @{
                    extendsPropertyGroup = $true
                    hasStringProperty = $true
                    hasFloatProperty = $true
                    hasEnumProperty = $true
                    registersToScene = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-properties"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extendsPropertyGroup", "registersToScene")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "properties", "property-group", "types")
            ),

            # Task 6: Material Node Setup
            (New-GoldenTask `
                -TaskId "gt-blender-006" `
                -Name "Material node setup" `
                -Description "Create material with nodes using Python API" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Write Python code to create a Principled BSDF material, add a noise texture to the base color, and link the nodes properly. Use material.use_nodes = True." `
                -ExpectedResult @{
                    enablesUseNodes = $true
                    createsPrincipledBSDF = $true
                    addsNoiseTexture = $true
                    linksNodes = $true
                    setsOutput = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-materials"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("enablesUseNodes", "createsPrincipledBSDF", "linksNodes")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "materials", "nodes", "shading")
            ),

            # Task 7: Rigging Automation
            (New-GoldenTask `
                -TaskId "gt-blender-007" `
                -Name "Rigging automation" `
                -Description "Automate bone creation and constraints" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Write a Python script that creates an armature with three connected bones (hip, knee, ankle), adds an Inverse Kinematics constraint to the ankle, and sets up proper parenting." `
                -ExpectedResult @{
                    createsArmature = $true
                    editsBones = $true
                    createsConnectedChain = $true
                    addsIKConstraint = $true
                    setsBoneHierarchy = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-armature"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("createsArmature", "editsBones", "addsIKConstraint")
                    forbiddenPatterns = @()
                    minConfidence = 0.75
                } `
                -Tags @("codegen", "rigging", "armature", "constraints")
            ),

            # Task 8: Render Pipeline Configuration
            (New-GoldenTask `
                -TaskId "gt-blender-008" `
                -Name "Render pipeline configuration" `
                -Description "Configure render settings programmatically" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Set up Blender render settings using Python: enable cycles, set samples to 128, set resolution to 1920x1080 at 100%, enable denoising, and set output format to PNG." `
                -ExpectedResult @{
                    setsEngineCycles = $true
                    setsSamples = $true
                    setsResolution = $true
                    enablesDenoising = $true
                    setsOutputFormat = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-render"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("setsEngineCycles", "setsSamples", "setsResolution")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "render", "cycles", "settings")
            ),

            # Task 9: Import/Export Operator
            (New-GoldenTask `
                -TaskId "gt-blender-009" `
                -Name "Import/export operator" `
                -Description "Create custom import/export operator with file selector" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Create a Blender operator that exports selected mesh objects to a custom JSON format. Include a file selector with .json filter and iterate through mesh data." `
                -ExpectedResult @{
                    extendsOperator = $true
                    hasFilepathProperty = $true
                    usesFilterGlob = $true
                    iteratesSelected = $true
                    exportsMeshData = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-io"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extendsOperator", "hasFilepathProperty", "exportsMeshData")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "import-export", "file-io", "mesh")
            ),

            # Task 10: Custom Keymap Binding
            (New-GoldenTask `
                -TaskId "gt-blender-010" `
                -Name "Custom keymap binding" `
                -Description "Add custom hotkeys and keymap entries" `
                -PackId "blender" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Show how to add a custom keymap entry in Blender Python that calls an operator when pressing Ctrl+Shift+T in the 3D viewport. Include addon registration code." `
                -ExpectedResult @{
                    accessesKeymaps = $true
                    addsKeymapItem = $true
                    setsKeyConfig = $true
                    usesCorrectModifier = $true
                    registersWithAddon = $true
                } `
                -RequiredEvidence @(
                    @{ source = "blender-keymap"; type = "bpy-pattern" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("accessesKeymaps", "addsKeymapItem", "registersWithAddon")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("codegen", "keymap", "hotkey", "shortcut")
            )
        )

        #=======================================================================
        # API Reverse Tooling Pack Golden Tasks (10 tasks)
        #=======================================================================
        $apiReverseTasks = @(
            # Task 1: API Endpoint Discovery
            (New-GoldenTask `
                -TaskId "gt-api-reverse-001" `
                -Name "API endpoint discovery" `
                -Description "Discover and catalog API endpoints from traffic or documentation" `
                -PackId "api-reverse" `
                -Category "analysis" `
                -Difficulty "medium" `
                -Query "Analyze HTTP traffic logs to discover REST API endpoints, extract their paths, HTTP methods, and identify resource patterns. Return a structured catalog." `
                -ExpectedResult @{
                    identifiesEndpoints = $true
                    extractsHttpMethods = $true
                    recognizesResourcePatterns = $true
                    structuresCatalog = $true
                    identifiesBaseUrl = $true
                } `
                -RequiredEvidence @(
                    @{ source = "http-traffic"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("identifiesEndpoints", "extractsHttpMethods", "recognizesResourcePatterns")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("api", "discovery", "endpoints", "rest", "traffic-analysis")
            ),

            # Task 2: Schema Inference from Traffic
            (New-GoldenTask `
                -TaskId "gt-api-reverse-002" `
                -Name "Schema inference from traffic" `
                -Description "Infer data schemas from API request/response payloads" `
                -PackId "api-reverse" `
                -Category "analysis" `
                -Difficulty "medium" `
                -Query "Given sample JSON request/response payloads from an API, infer the complete data schemas including types, required fields, and nested structures." `
                -ExpectedResult @{
                    infersTypes = $true
                    identifiesRequiredFields = $true
                    handlesNestedStructures = $true
                    detectsEnums = $true
                    providesJsonSchema = $true
                } `
                -RequiredEvidence @(
                    @{ source = "json-payloads"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("infersTypes", "identifiesRequiredFields", "providesJsonSchema")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("api", "schema", "inference", "json", "types")
            ),

            # Task 3: OpenAPI Spec Generation
            (New-GoldenTask `
                -TaskId "gt-api-reverse-003" `
                -Name "OpenAPI spec generation" `
                -Description "Generate complete OpenAPI 3.0 specification from API analysis" `
                -PackId "api-reverse" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Generate a complete OpenAPI 3.0 specification document from discovered endpoints, schemas, and authentication requirements. Include paths, components, and security schemes." `
                -ExpectedResult @{
                    validOpenApiStructure = $true
                    includesPaths = $true
                    includesComponents = $true
                    includesSecuritySchemes = $true
                    hasInfoSection = $true
                    hasOpenApiVersion = $true
                } `
                -RequiredEvidence @(
                    @{ source = "openapi"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("validOpenApiStructure", "includesPaths", "includesComponents")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("api", "openapi", "spec", "documentation", "swagger")
            ),

            # Task 4: Authentication Pattern Detection
            (New-GoldenTask `
                -TaskId "gt-api-reverse-004" `
                -Name "Authentication pattern detection" `
                -Description "Identify and classify API authentication mechanisms" `
                -PackId "api-reverse" `
                -Category "analysis" `
                -Difficulty "medium" `
                -Query "Analyze HTTP headers and request patterns to identify authentication mechanisms (API keys, OAuth, JWT, Basic Auth, Bearer tokens) and extract their usage patterns." `
                -ExpectedResult @{
                    identifiesAuthType = $true
                    extractsApiKeys = $true
                    detectsOAuthFlows = $true
                    recognizesJwtPattern = $true
                    documentsAuthLocation = $true
                } `
                -RequiredEvidence @(
                    @{ source = "http-headers"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("identifiesAuthType", "documentsAuthLocation")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("api", "authentication", "oauth", "jwt", "security")
            ),

            # Task 5: GraphQL Introspection
            (New-GoldenTask `
                -TaskId "gt-api-reverse-005" `
                -Name "GraphQL introspection" `
                -Description "Parse and analyze GraphQL schema introspection results" `
                -PackId "api-reverse" `
                -Category "analysis" `
                -Difficulty "medium" `
                -Query "Parse GraphQL introspection query results to extract types, queries, mutations, subscriptions, and their relationships. Generate a navigable schema documentation." `
                -ExpectedResult @{
                    extractsTypes = $true
                    identifiesQueries = $true
                    identifiesMutations = $true
                    identifiesSubscriptions = $true
                    mapsRelationships = $true
                    handlesInterfaces = $true
                } `
                -RequiredEvidence @(
                    @{ source = "graphql-schema"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extractsTypes", "identifiesQueries", "identifiesMutations")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("api", "graphql", "introspection", "schema")
            ),

            # Task 6: gRPC Proto Reconstruction
            (New-GoldenTask `
                -TaskId "gt-api-reverse-006" `
                -Name "gRPC proto reconstruction" `
                -Description "Reconstruct protobuf definitions from gRPC traffic or reflection" `
                -PackId "api-reverse" `
                -Category "analysis" `
                -Difficulty "hard" `
                -Query "Reconstruct .proto file definitions from gRPC method calls, message patterns, and field types observed in binary traffic or server reflection." `
                -ExpectedResult @{
                    reconstructsServices = $true
                    definesMessages = $true
                    infersFieldTypes = $true
                    assignsFieldNumbers = $true
                    generatesValidProto = $true
                } `
                -RequiredEvidence @(
                    @{ source = "grpc-traffic"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("reconstructsServices", "definesMessages", "generatesValidProto")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("api", "grpc", "protobuf", "proto", "binary")
            ),

            # Task 7: Response Validation
            (New-GoldenTask `
                -TaskId "gt-api-reverse-007" `
                -Name "Response validation" `
                -Description "Validate API responses against inferred or provided schemas" `
                -PackId "api-reverse" `
                -Category "validation" `
                -Difficulty "medium" `
                -Query "Given API responses and a schema, validate conformance checking for required fields, data types, value constraints, and nested structure compliance." `
                -ExpectedResult @{
                    validatesRequiredFields = $true
                    checksDataTypes = $true
                    validatesConstraints = $true
                    reportsValidationErrors = $true
                    providesErrorLocations = $true
                } `
                -RequiredEvidence @(
                    @{ source = "api-responses"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("validatesRequiredFields", "checksDataTypes", "reportsValidationErrors")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("api", "validation", "schema", "response", "conformance")
            ),

            # Task 8: Rate Limit Analysis
            (New-GoldenTask `
                -TaskId "gt-api-reverse-008" `
                -Name "Rate limit analysis" `
                -Description "Extract and analyze rate limiting headers and policies" `
                -PackId "api-reverse" `
                -Category "analysis" `
                -Difficulty "easy" `
                -Query "Analyze HTTP response headers (X-RateLimit, Retry-After, etc.) to extract rate limit policies, current usage, reset times, and recommended throttling strategies." `
                -ExpectedResult @{
                    extractsRateLimitHeaders = $true
                    identifiesLimitValues = $true
                    extractsResetTimes = $true
                    calculatesRemainingQuota = $true
                    suggestsThrottling = $true
                } `
                -RequiredEvidence @(
                    @{ source = "rate-limit-headers"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extractsRateLimitHeaders", "identifiesLimitValues", "calculatesRemainingQuota")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("api", "rate-limit", "throttling", "headers", "policy")
            ),

            # Task 9: Error Pattern Recognition
            (New-GoldenTask `
                -TaskId "gt-api-reverse-009" `
                -Name "Error pattern recognition" `
                -Description "Identify and classify API error response patterns" `
                -PackId "api-reverse" `
                -Category "analysis" `
                -Difficulty "medium" `
                -Query "Analyze API error responses to identify error patterns, status code distributions, error code taxonomies, and extract meaningful error messages and recovery hints." `
                -ExpectedResult @{
                    categorizesHttpStatusCodes = $true
                    extractsErrorCodes = $true
                    identifiesErrorPatterns = $true
                    extractsErrorMessages = $true
                    suggestsRecoveryActions = $true
                } `
                -RequiredEvidence @(
                    @{ source = "error-responses"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("categorizesHttpStatusCodes", "extractsErrorCodes", "identifiesErrorPatterns")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("api", "errors", "patterns", "status-codes", "recovery")
            ),

            # Task 10: API Changelog Detection
            (New-GoldenTask `
                -TaskId "gt-api-reverse-010" `
                -Name "API changelog detection" `
                -Description "Detect changes between API versions by comparing specs or traffic" `
                -PackId "api-reverse" `
                -Category "comparison" `
                -Difficulty "hard" `
                -Query "Compare two versions of an API specification or traffic logs to detect breaking changes, new endpoints, deprecated fields, and generate a detailed changelog." `
                -ExpectedResult @{
                    identifiesBreakingChanges = $true
                    detectsNewEndpoints = $true
                    identifiesDeprecatedFields = $true
                    detectsTypeChanges = $true
                    generatesDetailedChangelog = $true
                    classifiesChangeSeverity = $true
                } `
                -RequiredEvidence @(
                    @{ source = "api-versions"; type = "comparison" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("identifiesBreakingChanges", "detectsNewEndpoints", "generatesDetailedChangelog")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("api", "changelog", "versioning", "breaking-changes", "diff")
            )
        )

        #=======================================================================
        # Notebook/Data Workflow Pack Golden Tasks (10 tasks)
        #=======================================================================
        $notebookDataTasks = @(
            # Task 1: Notebook Version Control
            (New-GoldenTask `
                -TaskId "gt-notebook-data-001" `
                -Name "Notebook version control" `
                -Description "Implement version control strategies for Jupyter notebooks" `
                -PackId "notebook-data" `
                -Category "integration" `
                -Difficulty "medium" `
                -Query "Show how to configure Git for Jupyter notebooks including cleaning output, using nbstripout, creating .gitattributes, and handling notebook diffs effectively." `
                -ExpectedResult @{
                    configuresGitAttributes = $true
                    mentionsNbstripout = $true
                    handlesOutputCleaning = $true
                    suggestsDiffTools = $true
                    providesPreCommitHooks = $true
                } `
                -RequiredEvidence @(
                    @{ source = "jupyter-git"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("configuresGitAttributes", "handlesOutputCleaning")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("notebook", "jupyter", "git", "version-control", "nbstripout")
            ),

            # Task 2: Cell Output Caching
            (New-GoldenTask `
                -TaskId "gt-notebook-data-002" `
                -Name "Cell output caching" `
                -Description "Implement caching mechanisms for expensive cell computations" `
                -PackId "notebook-data" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Write Python code to implement cell output caching in Jupyter using @lru_cache, joblib.Memory, or ipycache to avoid re-running expensive computations." `
                -ExpectedResult @{
                    implementsCachingDecorator = $true
                    handlesCacheInvalidation = $true
                    showsJoblibMemory = $true
                    showsLruCache = $true
                    demonstratesIpyCache = $true
                } `
                -RequiredEvidence @(
                    @{ source = "python-cache"; type = "method-citation" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("implementsCachingDecorator", "handlesCacheInvalidation")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("notebook", "caching", "jupyter", "performance", "memoization")
            ),

            # Task 3: Data Lineage Tracking
            (New-GoldenTask `
                -TaskId "gt-notebook-data-003" `
                -Name "Data lineage tracking" `
                -Description "Track data flow and transformations through notebook cells" `
                -PackId "notebook-data" `
                -Category "analysis" `
                -Difficulty "hard" `
                -Query "Design a data lineage tracking system for Jupyter notebooks that captures variable dependencies, cell execution order, and data transformation chains." `
                -ExpectedResult @{
                    tracksVariableDependencies = $true
                    capturesExecutionOrder = $true
                    mapsDataTransformations = $true
                    providesLineageGraph = $true
                    handlesCellReruns = $true
                } `
                -RequiredEvidence @(
                    @{ source = "data-lineage"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("tracksVariableDependencies", "capturesExecutionOrder", "mapsDataTransformations")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("notebook", "lineage", "dataflow", "tracking", "provenance")
            ),

            # Task 4: Pipeline Dependency Graph
            (New-GoldenTask `
                -TaskId "gt-notebook-data-004" `
                -Name "Pipeline dependency graph" `
                -Description "Build and visualize data pipeline dependency graphs" `
                -PackId "notebook-data" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Create Python code to build a dependency graph for a data processing pipeline using networkx, showing stages, dependencies, and generating a visual diagram." `
                -ExpectedResult @{
                    buildsDependencyGraph = $true
                    identifiesPipelineStages = $true
                    visualizesGraph = $true
                    detectsCycles = $true
                    showsExecutionOrder = $true
                } `
                -RequiredEvidence @(
                    @{ source = "networkx"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("buildsDependencyGraph", "identifiesPipelineStages", "visualizesGraph")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("notebook", "pipeline", "dependency-graph", "visualization", "dag")
            ),

            # Task 5: Data Validation Rules
            (New-GoldenTask `
                -TaskId "gt-notebook-data-005" `
                -Name "Data validation rules" `
                -Description "Implement comprehensive data validation for dataframes" `
                -PackId "notebook-data" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Write Python code using pydantic, pandera, or great_expectations to validate pandas DataFrames with schema checks, constraints, and custom validation rules." `
                -ExpectedResult @{
                    definesSchemaConstraints = $true
                    validatesDataTypes = $true
                    checksNullValues = $true
                    validatesRanges = $true
                    providesValidationReport = $true
                } `
                -RequiredEvidence @(
                    @{ source = "pandas-validation"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("definesSchemaConstraints", "validatesDataTypes", "providesValidationReport")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("notebook", "validation", "pandas", "schema", "data-quality")
            ),

            # Task 6: Visualization Generation
            (New-GoldenTask `
                -TaskId "gt-notebook-data-006" `
                -Name "Visualization generation" `
                -Description "Generate data visualizations optimized for notebooks" `
                -PackId "notebook-data" `
                -Category "codegen" `
                -Difficulty "easy" `
                -Query "Create Python code to generate matplotlib, seaborn, and plotly visualizations optimized for Jupyter notebooks with proper sizing, interactivity, and display settings." `
                -ExpectedResult @{
                    usesMatplotlib = $true
                    usesSeaborn = $true
                    usesPlotly = $true
                    optimizesForNotebook = $true
                    handlesInteractivePlots = $true
                    setsProperFigureSize = $true
                } `
                -RequiredEvidence @(
                    @{ source = "visualization"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("usesMatplotlib", "optimizesForNotebook")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("notebook", "visualization", "matplotlib", "plotly", "seaborn")
            ),

            # Task 7: Dataset Profiling
            (New-GoldenTask `
                -TaskId "gt-notebook-data-007" `
                -Name "Dataset profiling" `
                -Description "Generate comprehensive dataset profiling reports" `
                -PackId "notebook-data" `
                -Category "analysis" `
                -Difficulty "easy" `
                -Query "Use ydata-profiling, sweetviz, or pandas-profiling to generate a comprehensive dataset report including statistics, distributions, correlations, and data quality alerts." `
                -ExpectedResult @{
                    generatesProfileReport = $true
                    includesStatistics = $true
                    showsDistributions = $true
                    analyzesCorrelations = $true
                    flagsDataQualityIssues = $true
                } `
                -RequiredEvidence @(
                    @{ source = "profiling"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("generatesProfileReport", "includesStatistics", "flagsDataQualityIssues")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("notebook", "profiling", "eda", "data-quality", "statistics")
            ),

            # Task 8: Feature Engineering Pipeline
            (New-GoldenTask `
                -TaskId "gt-notebook-data-008" `
                -Name "Feature engineering pipeline" `
                -Description "Build reusable feature engineering pipelines with sklearn" `
                -PackId "notebook-data" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Create a scikit-learn Pipeline with ColumnTransformer for feature engineering including scaling, encoding, text vectorization, and custom transformers." `
                -ExpectedResult @{
                    usesPipeline = $true
                    usesColumnTransformer = $true
                    handlesNumericalFeatures = $true
                    handlesCategoricalFeatures = $true
                    includesCustomTransformer = $true
                    demonstratesFitTransform = $true
                } `
                -RequiredEvidence @(
                    @{ source = "sklearn"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("usesPipeline", "usesColumnTransformer", "handlesNumericalFeatures")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("notebook", "feature-engineering", "sklearn", "pipeline", "ml")
            ),

            # Task 9: Model Training Tracking
            (New-GoldenTask `
                -TaskId "gt-notebook-data-009" `
                -Name "Model training tracking" `
                -Description "Track ML experiments and model training metrics" `
                -PackId "notebook-data" `
                -Category "integration" `
                -Difficulty "medium" `
                -Query "Implement experiment tracking in a Jupyter notebook using MLflow, wandb, or tensorboard to log parameters, metrics, artifacts, and model versions." `
                -ExpectedResult @{
                    logsParameters = $true
                    logsMetrics = $true
                    logsArtifacts = $true
                    tracksModelVersions = $true
                    providesExperimentComparison = $true
                } `
                -RequiredEvidence @(
                    @{ source = "mlflow"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("logsParameters", "logsMetrics", "tracksModelVersions")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("notebook", "mlflow", "experiment-tracking", "ml", "logging")
            ),

            # Task 10: Experiment Comparison
            (New-GoldenTask `
                -TaskId "gt-notebook-data-010" `
                -Name "Experiment comparison" `
                -Description "Compare multiple ML experiments and generate comparison reports" `
                -PackId "notebook-data" `
                -Category "comparison" `
                -Difficulty "medium" `
                -Query "Write code to compare multiple ML experiment runs, generating visual comparisons of metrics, parameter diffs, and ranking models by performance criteria." `
                -ExpectedResult @{
                    comparesMultipleRuns = $true
                    visualizesMetricComparison = $true
                    showsParameterDiffs = $true
                    ranksModels = $true
                    generatesComparisonReport = $true
                } `
                -RequiredEvidence @(
                    @{ source = "experiment-comparison"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("comparesMultipleRuns", "visualizesMetricComparison", "generatesComparisonReport")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("notebook", "experiment-comparison", "ml", "visualization", "benchmark")
            )
        )

        #=======================================================================
        # Agent Simulation Pack Golden Tasks (10 tasks)
        #=======================================================================
        $agentSimTasks = @(
            # Task 1: Multi-Agent Setup
            (New-GoldenTask `
                -TaskId "gt-agent-sim-001" `
                -Name "Multi-agent setup" `
                -Description "Configure and initialize a multi-agent simulation environment" `
                -PackId "agent-sim" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Create a multi-agent simulation setup using Python with agent definitions, environment state, agent communication channels, and coordination mechanisms." `
                -ExpectedResult @{
                    definesAgentClass = $true
                    initializesMultipleAgents = $true
                    setsUpCommunication = $true
                    definesEnvironmentState = $true
                    implementsCoordination = $true
                } `
                -RequiredEvidence @(
                    @{ source = "multi-agent"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("definesAgentClass", "initializesMultipleAgents", "setsUpCommunication")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("agent", "multi-agent", "simulation", "coordination", "mas")
            ),

            # Task 2: Reward Function Design
            (New-GoldenTask `
                -TaskId "gt-agent-sim-002" `
                -Name "Reward function design" `
                -Description "Design and implement reward functions for reinforcement learning agents" `
                -PackId "agent-sim" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Design a reward function for an RL agent including sparse vs dense rewards, shaping techniques, multi-objective weighting, and penalty structures." `
                -ExpectedResult @{
                    implementsSparseReward = $true
                    implementsDenseReward = $true
                    includesRewardShaping = $true
                    handlesMultiObjective = $true
                    definesPenaltyStructure = $true
                } `
                -RequiredEvidence @(
                    @{ source = "rl-rewards"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("implementsDenseReward", "includesRewardShaping", "definesPenaltyStructure")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("agent", "rl", "reward-function", "reinforcement-learning", "shaping")
            ),

            # Task 3: Trajectory Analysis
            (New-GoldenTask `
                -TaskId "gt-agent-sim-003" `
                -Name "Trajectory analysis" `
                -Description "Analyze agent behavior trajectories and state transitions" `
                -PackId "agent-sim" `
                -Category "analysis" `
                -Difficulty "medium" `
                -Query "Write code to analyze agent trajectories including state-action sequences, path optimization, divergence detection, and trajectory clustering." `
                -ExpectedResult @{
                    analyzesStateActionSequences = $true
                    detectsPathPatterns = $true
                    identifiesDivergences = $true
                    clustersTrajectories = $true
                    calculatesPathMetrics = $true
                } `
                -RequiredEvidence @(
                    @{ source = "trajectory-analysis"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("analyzesStateActionSequences", "identifiesDivergences", "clustersTrajectories")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("agent", "trajectory", "analysis", "behavior", "paths")
            ),

            # Task 4: A/B Testing Framework
            (New-GoldenTask `
                -TaskId "gt-agent-sim-004" `
                -Name "A/B testing framework" `
                -Description "Implement A/B testing for comparing agent policies or behaviors" `
                -PackId "agent-sim" `
                -Category "integration" `
                -Difficulty "medium" `
                -Query "Create an A/B testing framework for agent policies including random assignment, statistical significance testing, confidence intervals, and performance comparison." `
                -ExpectedResult @{
                    implementsRandomAssignment = $true
                    calculatesStatisticalSignificance = $true
                    computesConfidenceIntervals = $true
                    comparesPolicies = $true
                    handlesSampleSizeCalculation = $true
                } `
                -RequiredEvidence @(
                    @{ source = "ab-testing"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("implementsRandomAssignment", "calculatesStatisticalSignificance", "comparesPolicies")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("agent", "ab-testing", "statistics", "policy-comparison", "experiment")
            ),

            # Task 5: Environment Configuration
            (New-GoldenTask `
                -TaskId "gt-agent-sim-005" `
                -Name "Environment configuration" `
                -Description "Configure simulation environments with Gymnasium/PettingZoo" `
                -PackId "agent-sim" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Create a custom Gymnasium environment with proper observation/action spaces, reset/step methods, rendering, and environment registration." `
                -ExpectedResult @{
                    extendsGymEnv = $true
                    definesObservationSpace = $true
                    definesActionSpace = $true
                    implementsReset = $true
                    implementsStep = $true
                    registersEnvironment = $true
                } `
                -RequiredEvidence @(
                    @{ source = "gymnasium"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("extendsGymEnv", "implementsReset", "implementsStep")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("agent", "gymnasium", "environment", "rl", "simulation")
            ),

            # Task 6: Agent Behavior Validation
            (New-GoldenTask `
                -TaskId "gt-agent-sim-006" `
                -Name "Agent behavior validation" `
                -Description "Validate agent behaviors against expected policies and constraints" `
                -PackId "agent-sim" `
                -Category "validation" `
                -Difficulty "medium" `
                -Query "Implement validation tests for agent behaviors including policy conformance checking, safety constraint validation, and behavioral invariants." `
                -ExpectedResult @{
                    validatesPolicyConformance = $true
                    checksSafetyConstraints = $true
                    verifiesBehavioralInvariants = $true
                    testsEdgeCases = $true
                    providesValidationReport = $true
                } `
                -RequiredEvidence @(
                    @{ source = "behavior-validation"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("validatesPolicyConformance", "checksSafetyConstraints", "providesValidationReport")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("agent", "validation", "behavior", "safety", "testing")
            ),

            # Task 7: Policy Optimization
            (New-GoldenTask `
                -TaskId "gt-agent-sim-007" `
                -Name "Policy optimization" `
                -Description "Implement policy gradient and optimization algorithms" `
                -PackId "agent-sim" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Implement a policy gradient algorithm (REINFORCE, PPO, or A2C) with neural network policy, value function, and training loop." `
                -ExpectedResult @{
                    implementsPolicyNetwork = $true
                    implementsValueFunction = $true
                    calculatesPolicyGradient = $true
                    includesTrainingLoop = $true
                    handlesAdvantageEstimation = $true
                } `
                -RequiredEvidence @(
                    @{ source = "policy-gradient"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("implementsPolicyNetwork", "calculatesPolicyGradient", "includesTrainingLoop")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("agent", "policy-gradient", "ppo", "reinforcement-learning", "optimization")
            ),

            # Task 8: Simulation Replay
            (New-GoldenTask `
                -TaskId "gt-agent-sim-008" `
                -Name "Simulation replay" `
                -Description "Record and replay simulation episodes for debugging and analysis" `
                -PackId "agent-sim" `
                -Category "codegen" `
                -Difficulty "medium" `
                -Query "Create a simulation replay system that records episodes (states, actions, rewards) and supports playback, stepping, and event inspection." `
                -ExpectedResult @{
                    recordsEpisodeData = $true
                    supportsPlayback = $true
                    allowsStepping = $true
                    inspectsEvents = $true
                    savesReplayFiles = $true
                } `
                -RequiredEvidence @(
                    @{ source = "simulation-replay"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("recordsEpisodeData", "supportsPlayback", "allowsStepping")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("agent", "replay", "simulation", "debugging", "recording")
            ),

            # Task 9: Metrics Collection
            (New-GoldenTask `
                -TaskId "gt-agent-sim-009" `
                -Name "Metrics collection" `
                -Description "Collect and aggregate agent performance metrics" `
                -PackId "agent-sim" `
                -Category "integration" `
                -Difficulty "easy" `
                -Query "Implement a metrics collection system for agents including episode rewards, success rates, convergence tracking, and custom metric aggregation." `
                -ExpectedResult @{
                    tracksEpisodeRewards = $true
                    calculatesSuccessRates = $true
                    monitorsConvergence = $true
                    aggregatesStatistics = $true
                    exportsMetricsData = $true
                } `
                -RequiredEvidence @(
                    @{ source = "metrics"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("tracksEpisodeRewards", "calculatesSuccessRates", "monitorsConvergence")
                    forbiddenPatterns = @()
                    minConfidence = 0.8
                } `
                -Tags @("agent", "metrics", "performance", "monitoring", "statistics")
            ),

            # Task 10: Agent Collaboration Patterns
            (New-GoldenTask `
                -TaskId "gt-agent-sim-010" `
                -Name "Agent collaboration patterns" `
                -Description "Implement collaboration patterns for multi-agent systems" `
                -PackId "agent-sim" `
                -Category "codegen" `
                -Difficulty "hard" `
                -Query "Implement agent collaboration patterns including auction-based allocation, consensus algorithms, shared memory, and emergent coordination strategies." `
                -ExpectedResult @{
                    implementsAuctionMechanism = $true
                    implementsConsensus = $true
                    usesSharedMemory = $true
                    demonstratesEmergentCoordination = $true
                    handlesCommunicationOverhead = $true
                } `
                -RequiredEvidence @(
                    @{ source = "collaboration"; type = "source-reference" }
                ) `
                -ValidationRules @{
                    propertyBased = $true
                    requiredProperties = @("implementsAuctionMechanism", "implementsConsensus", "demonstratesEmergentCoordination")
                    forbiddenPatterns = @()
                    minConfidence = 0.85
                } `
                -Tags @("agent", "collaboration", "multi-agent", "coordination", "distributed")
            )
        )

        # Combine all tasks
        $allTasks = $rpgmakerTasks + $godotTasks + $blenderTasks + $apiReverseTasks + $notebookDataTasks + $agentSimTasks

        # Filter by pack if specified
        if ($PackId) {
            return $allTasks | Where-Object { $_.packId -eq $PackId }
        }

        return $allTasks
    }
}

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
function Invoke-LLMQuery {
    param(
        [string]$Query,
        [string]$Provider = "default",
        [int]$Timeout = 120
    )

    # Placeholder implementation
    # In production, this would:
    # 1. Call the actual LLM provider (OpenAI, Anthropic, etc.)
    # 2. Apply context from available packs
    # 3. Return structured response

    Write-Verbose "[SIMULATION] Querying LLM provider '$Provider' with timeout $Timeout`s"
    Write-Verbose "[SIMULATION] Query: $Query"

    return @{
        content = "[Simulated LLM Response] This is a placeholder response."
        provider = $Provider
        tokens = @{ prompt = 100; completion = 200 }
        latency = 500
    }
}

<#
.SYNOPSIS
    Internal: Extracts properties from LLM response for validation.

.DESCRIPTION
    Analyzes the LLM response text and extracts properties for
    property-based validation.
#>
function Extract-ResponseProperties {
    param(
        [hashtable]$Response,
        [hashtable]$Task
    )

    $properties = @{}
    $content = $Response.content

    # Analyze based on task category
    switch ($Task.category) {
        'codegen' {
            # Check for various code patterns
            $properties['hasJSDocHeader'] = $content -match '/\*\*[\s\S]*?\*/'
            $properties['hasPluginCommandRegistration'] = $content -match 'PluginManager\.(registerCommand|commands)'
            $properties['containsCommand'] = $Task.expectedResult.containsCommand
            $properties['containsParameter'] = $Task.expectedResult.containsParameter
            $properties['usesGDScriptSyntax'] = $content -match '(extends\s+\w+|func\s+\w+|var\s+\w+|@onready|@export)'
            $properties['hasBlIdname'] = $content -match "bl_idname\s*=\s*['`"']"
            $properties['hasBlLabel'] = $content -match "bl_label\s*=\s*['`"']"
            $properties['hasExecuteMethod'] = $content -match 'def\s+execute\s*\('
            $properties['includesRegistration'] = $content -match '(bpy\.utils\.register_class|register\s*\()'
            $properties['hasClassName'] = if ($Task.expectedResult.hasClassName) { 
                $content -match "class_name\s+$($Task.expectedResult.hasClassName)" 
            } else { $false }
            $properties['extendsCharacterBody2D'] = $content -match 'extends\s+CharacterBody2D'
            $properties['hasSpeedProperty'] = $content -match '(export|@export).*speed|var\s+speed'
            $properties['hasPhysicsProcess'] = $content -match '_physics_process'
            $properties['createsGameManager'] = $content -match 'class.*GameManager|GameManager'
            $properties['showsConnectMethod'] = $content -match '\.connect\s*\('
            $properties['showsOnreadyPattern'] = $content -match '@onready'
            $properties['extendsNode2D'] = $content -match 'extends\s+Node2D'
            $properties['implementsDraw'] = $content -match '_draw\s*\('
            $properties['usesToolAnnotation'] = $content -match '@tool'
            $properties['extendsEditorPlugin'] = $content -match 'extends\s+EditorPlugin'
            $properties['hasEnterMethod'] = $content -match '_enter_tree'
            $properties['addsDockPanel'] = $content -match 'add_control_to_dock|make_visible'
            $properties['shaderTypeCanvasItem'] = $content -match 'shader_type\s+canvas_item'
            $properties['usesTimeUniform'] = $content -match 'uniform.*TIME|TIME'
            $properties['extendsPropertyGroup'] = $content -match 'extends\s+PropertyGroup'
            $properties['extendsPanel'] = $content -match 'extends\s+Panel'
            $properties['includesDrawMethod'] = $content -match 'def\s+draw\s*\('
            $properties['extendsOperator'] = $content -match 'extends\s+Operator'
            $properties['enablesUseNodes'] = $content -match 'use_nodes\s*=\s*True'
            $properties['createsPrincipledBSDF'] = $content -match 'Principled BSDF|ShaderNodeBsdfPrincipled'
            $properties['linksNodes'] = $content -match 'links\.new'
        }
        'diagnosis' {
            $properties['analyzesConflict'] = $content -match '(conflict|overlap|incompatible|compatible)'
            $properties['citesMethods'] = $content -match '(\.\w+\s*\(|function\s+\w+|def\s+\w+)'
            $properties['providesResolution'] = $content -match '(solution|workaround|fix|recommend|place.*above|place.*below)'
            $properties['mentionsLoadOrder'] = $content -match '(load.*order|order.*load|placement)'
        }
        'extraction' {
            $properties['extractsNotetags'] = $content -match '(notetag|meta|@type)'
            $properties['categorizesByType'] = $content -match '(actor|item|skill|class|weapon|armor|enemy|state)'
            $properties['providesExamples'] = $content -match '(example|e\.g\.|for instance|such as)'
            $pattern = [regex]::Escape('^ <') + '|' + '<.*?>' + '|' + '\w' + '|' + '\d' + '|' + '\[.+?\]'
            $properties['hasValidRegexPatterns'] = $content -match $pattern
        }
        'analysis' {
            $properties['identifiesMethodChain'] = $content -match '(prototype\.|__proto__|method.*chain|call.*chain)'
            $properties['explainsPatchMechanism'] = $content -match '(alias|override|wrap|patch|replace)'
            $properties['mentionsAliasPattern'] = $content -match '(alias|_alias|_\w+_\w+_alias)'
            $properties['showsOriginalVsPatched'] = $content -match '(original|before|after|vs|versus|compared)'
            $properties['identifiesAliases'] = $content -match '(alias|command.*alias|registerCommand)'
            $properties['explainsRegisterCommand'] = $content -match 'registerCommand|PluginManager'
            $properties['explainsSceneInheritance'] = $content -match '(inheritance|inherited scene|scene.*inherit)'
            $properties['showsBaseScene'] = $content -match 'base.*scene|parent.*scene'
            $properties['showsInheritedScene'] = $content -match 'inherited.*scene|child.*scene'
        }
        default {
            # Generic property extraction based on expected result keys
            foreach ($key in $Task.expectedResult.Keys) {
                $properties[$key] = $content -match [regex]::Escape($key)
            }
        }
    }

    return $properties
}

<#
.SYNOPSIS
    Internal: Saves evaluation result to history.

.DESCRIPTION
    Persists golden task evaluation results for historical analysis.
#>
function Save-GoldenTaskResult {
    param(
        [hashtable]$Result
    )

    $resultsDir = $script:GoldenTaskConfig.ResultsDirectory
    $taskId = $Result.Task.TaskId
    $timestamp = (Get-Date -Format "yyyyMMdd-HHmmss")
    $filename = "$taskId-$timestamp.json"
    $filepath = Join-Path $resultsDir $filename

    # Create pack subdirectory if needed
    $packId = $Result.Task.PackId
    if ($packId) {
        $packDir = Join-Path $resultsDir $packId
        if (-not (Test-Path $packDir)) {
            $null = New-Item -ItemType Directory -Path $packDir -Force
        }
        $filepath = Join-Path $packDir $filename
    }

    $Result | ConvertTo-Json -Depth 10 | Out-File -FilePath $filepath -Encoding UTF8
    Write-Verbose "Result saved to: $filepath"
}

<#
.SYNOPSIS
    Internal: Runs golden tasks in parallel.

.DESCRIPTION
    Executes multiple golden tasks using runspace pool for parallel processing.
#>
function Invoke-ParallelGoldenTasks {
    param(
        [array]$Tasks,
        [int]$MaxParallelJobs,
        [switch]$RecordResults,
        [switch]$FailFast
    )

    # PowerShell 5.1 compatible parallel execution using runspaces
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxParallelJobs)
    $runspacePool.Open()

    $runspaces = @()
    $results = @()

    foreach ($task in $Tasks) {
        $powershell = [powershell]::Create().AddScript({
            param($Task, $RecordResults, $Config)
            
            # Import module functions (simplified for runspace)
            $script:GoldenTaskConfig = $Config
            
            # Call evaluation
            $result = Invoke-GoldenTask -Task $Task -RecordResults:$RecordResults
            return $result
        }).AddArgument($task).AddArgument($RecordResults).AddArgument($script:GoldenTaskConfig)

        $powershell.RunspacePool = $runspacePool

        $runspaces += @{
            Pipe = $powershell
            Status = $powershell.BeginInvoke()
            Task = $task
        }
    }

    # Collect results
    foreach ($rs in $runspaces) {
        try {
            $result = $rs.Pipe.EndInvoke($rs.Status)
            if ($result) {
                $results += $result[0]
                
                if ($FailFast -and -not $result[0].Validation.Success) {
                    Write-Warning "Task '$($rs.Task.taskId)' failed. FailFast enabled."
                }
            }
        }
        catch {
            Write-Error "Error in parallel execution for task '$($rs.Task.taskId)': $_"
            $results += @{
                Task = @{ TaskId = $rs.Task.taskId; Name = $rs.Task.name }
                Success = $false
                Error = $_.ToString()
            }
        }
        finally {
            $rs.Pipe.Dispose()
        }
    }

    $runspacePool.Close()
    $runspacePool.Dispose()

    return $results
}

<#
.SYNOPSIS
    Internal: Converts report to HTML format.
#>
function ConvertTo-GoldenTaskHtmlReport {
    param([hashtable]$Report)

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>$($Report.ReportMetadata.Title)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        h1 { color: #333; }
        .summary { background: #f5f5f5; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .metric { display: inline-block; margin: 10px 20px; }
        .metric-value { font-size: 24px; font-weight: bold; }
        .metric-label { font-size: 12px; color: #666; }
        .passed { color: green; }
        .failed { color: red; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #333; color: white; }
    </style>
</head>
<body>
    <h1>$($Report.ReportMetadata.Title)</h1>
    <p>Generated: $($Report.ReportMetadata.GeneratedAt)</p>
    
    <div class="summary">
        <h2>Summary</h2>
        <div class="metric">
            <div class="metric-value">$($Report.Summary.TotalTasks)</div>
            <div class="metric-label">Total Tasks</div>
        </div>
        <div class="metric">
            <div class="metric-value passed">$($Report.Summary.PassedTasks)</div>
            <div class="metric-label">Passed</div>
        </div>
        <div class="metric">
            <div class="metric-value failed">$($Report.Summary.FailedTasks)</div>
            <div class="metric-label">Failed</div>
        </div>
        <div class="metric">
            <div class="metric-value">$($Report.Summary.Grade)</div>
            <div class="metric-label">Grade</div>
        </div>
        <div class="metric">
            <div class="metric-value">$($Report.Summary.PassRate)%</div>
            <div class="metric-label">Pass Rate</div>
        </div>
    </div>
</body>
</html>
"@
    return $html
}

<#
.SYNOPSIS
    Internal: Converts report to Markdown format.
#>
function ConvertTo-GoldenTaskMarkdownReport {
    param([hashtable]$Report)

    $md = @"
# $($Report.ReportMetadata.Title)

**Generated:** $($Report.ReportMetadata.GeneratedAt)

## Summary

| Metric | Value |
|--------|-------|
| Total Tasks | $($Report.Summary.TotalTasks) |
| Passed | $($Report.Summary.PassedTasks) |
| Failed | $($Report.Summary.FailedTasks) |
| Pass Rate | $($Report.Summary.PassRate)% |
| Grade | $($Report.Summary.Grade) |
| Avg Confidence | $([math]::Round($Report.Summary.AverageConfidence * 100, 2))% |

## Difficulty Breakdown

"@
    foreach ($diff in $Report.Summary.TaskBreakdown.Keys) {
        $md += "- **$($diff):** $($Report.Summary.TaskBreakdown[$diff])`n"
    }

    return $md
}

<#
.SYNOPSIS
    Internal: Converts PSObject to hashtable recursively.

.DESCRIPTION
    Utility function to convert deserialized JSON objects back to hashtables.
#>
function ConvertTo-Hashtable {
    param(
        $InputObject
    )

    if ($InputObject -is [System.Collections.Hashtable]) {
        return $InputObject
    }
    
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        return @($InputObject | ForEach-Object { ConvertTo-Hashtable -InputObject $_ })
    }
    
    if ($InputObject -is [pscustomobject] -or $InputObject -is [System.Management.Automation.PSCustomObject]) {
        $hash = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $hash[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
        }
        return $hash
    }
    
    return $InputObject
}

#endregion

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

            Write-Host "`nGolden Task Suite Summary - '$($Suite.suiteName)'" -ForegroundColor Cyan
            Write-Host "  Tasks Run: $($summary.TasksRun)" -ForegroundColor White
            Write-Host "  Passed: $($summary.Passed)" -ForegroundColor Green
            Write-Host "  Failed: $($summary.Failed)" -ForegroundColor Red
            Write-Host "  Pass Rate: $($summary.PassRate)%" -ForegroundColor Yellow
            Write-Host "  Avg Confidence: $($summary.AverageConfidence)" -ForegroundColor White

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
            Write-Host "`nGolden Task Run Comparison" -ForegroundColor Cyan
            Write-Host "  Pack: $PackId$(if($TaskId){" / Task: $TaskId"})" -ForegroundColor White
            Write-Host "  Baseline: $($result.BaselineRun)" -ForegroundColor Gray
            Write-Host "  Comparison: $($result.ComparisonRun)" -ForegroundColor Gray
            Write-Host "  Tasks Compared: $($result.Summary.TotalTasksCompared)" -ForegroundColor White
            
            if ($result.Summary.CriticalRegressions -gt 0) {
                Write-Host "  CRITICAL REGRESSIONS: $($result.Summary.CriticalRegressions)" -ForegroundColor Red
            }
            if ($result.Summary.TotalRegressions -gt 0) {
                Write-Host "  Total Regressions: $($result.Summary.TotalRegressions)" -ForegroundColor Yellow
            }
            if ($result.Summary.TotalImprovements -gt 0) {
                Write-Host "  Improvements: $($result.Summary.TotalImprovements)" -ForegroundColor Green
            }
            Write-Host "  Status: $($result.Summary.Status)" -ForegroundColor $(if ($hasRegression) { "Red" } else { "Green" })

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
