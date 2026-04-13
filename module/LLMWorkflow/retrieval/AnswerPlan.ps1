#requires -Version 5.1
<#
.SYNOPSIS
    Answer Plan and Answer Trace System for LLM Workflow Platform - Phase 5.

.DESCRIPTION
    Implements retrieval and answer integrity for the LLM Workflow platform.
    
    Answer Plan (Section 15.1):
    - Created before synthesis to define search strategy and evidence requirements
    - Specifies retrieval profile, packs to search, evidence types, and confidence policy
    - Enforces private/public boundary checks
    
    Answer Trace (Section 15.2):
    - Created after synthesis to record what evidence was used and why
    - Tracks answer mode, confidence decisions, caveats, and pack versions
    - Supports audit and reproducibility requirements

.NOTES
    File: AnswerPlan.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Phase: 5 - Retrieval and Answer Integrity

.EXAMPLE
    # Create an answer plan
    $plan = New-AnswerPlan -Query "How do I implement a custom battle system?" `
                           -RetrievalProfile "rpgmaker-expert" `
                           -PacksToSearch @("rpgmaker-mz-core", "rpgmaker-mz-plugins")

.EXAMPLE
    # Add evidence requirements and validate
    Add-PlanEvidence -Plan $plan -EvidenceType "code-example" -Required $true
    Test-AnswerPlanCompleteness -Plan $plan

.EXAMPLE
    # Create answer trace after synthesis
    $trace = New-AnswerTrace -Plan $plan -AnswerMode "caveat" -ConfidenceDecision $confidence
    Add-TraceEvidence -Trace $trace -EvidenceId "ev-001" -SourcePack "rpgmaker-mz-core"
    Export-AnswerTrace -Trace $trace
#>

Set-StrictMode -Version Latest

#===============================================================================
# Configuration and Constants
#===============================================================================

$script:AnswerPlanSchemaVersion = 1
$script:AnswerTraceSchemaVersion = 1
$script:DefaultReportsDirectory = ".llm-workflow/reports"
$script:DefaultTracesDirectory = ".llm-workflow/traces"
$script:LatestTraceFileName = "latest-answer-trace.json"

# Valid answer modes per specification
$script:ValidAnswerModes = @('direct', 'caveat', 'dispute', 'abstain', 'escalate')

# Valid evidence types
$script:ValidEvidenceTypes = @(
    'code-example',
    'api-reference',
    'tutorial',
    'explanation',
    'configuration',
    'schema-definition',
    'dependency-info',
    'version-compatibility'
)

# Valid evidence classes to avoid
$script:ValidEvidenceClassesToAvoid = @(
    'deprecated',
    'experimental',
    'unverified',
    'third-party-untested',
    'community-contributed'
)

#===============================================================================
# Answer Plan Functions (Section 15.1)
#===============================================================================

function New-AnswerPlan {
    <#
    .SYNOPSIS
        Creates an answer plan before synthesis.

    .DESCRIPTION
        Initializes an answer plan with all required metadata for retrieval strategy.
        The plan defines what to search, what evidence is required, and what to avoid.
        Must be created before synthesis begins.

    .PARAMETER Query
        The user query being answered.

    .PARAMETER RetrievalProfile
        The retrieval profile to use (e.g., "rpgmaker-expert", "godot-beginner").

    .PARAMETER PacksToSearch
        Array of pack IDs to include in the search.

    .PARAMETER RequiredEvidenceTypes
        Array of evidence types that must be found for a complete answer.

    .PARAMETER EvidenceClassesToAvoid
        Array of evidence classes to exclude from results.

    .PARAMETER ConfidencePolicy
        Hashtable defining confidence thresholds and policies.

    .PARAMETER WorkspaceId
        The workspace context. Uses current workspace if not specified.

    .PARAMETER RunId
        Optional run ID for correlation. Uses current run ID if available.

    .PARAMETER PrivatePublicBoundaryChecked
        Whether private/public boundary has been verified.

    .PARAMETER DryRun
        If specified, returns plan without side effects.

    .OUTPUTS
        System.Collections.Hashtable. The answer plan object.

    .EXAMPLE
        $plan = New-AnswerPlan -Query "How to use PluginManager?" `
                               -RetrievalProfile "rpgmaker-expert" `
                               -PacksToSearch @("rpgmaker-mz-core")
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $true)]
        [string]$RetrievalProfile,

        [Parameter()]
        [string[]]$PacksToSearch = @(),

        [Parameter()]
        [string[]]$RequiredEvidenceTypes = @(),

        [Parameter()]
        [string[]]$EvidenceClassesToAvoid = @(),

        [Parameter()]
        [hashtable]$ConfidencePolicy = @{},

        [Parameter()]
        [string]$WorkspaceId = "",

        [Parameter()]
        [string]$RunId = "",

        [Parameter()]
        [switch]$PrivatePublicBoundaryChecked = $false,

        [Parameter()]
        [switch]$DryRun
    )

    # Get or generate run ID
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        $RunId = Get-AnswerPlanRunId
    }

    # Get workspace context if not provided
    if ([string]::IsNullOrWhiteSpace($WorkspaceId)) {
        $WorkspaceId = Get-CurrentWorkspaceId
    }

    # Validate evidence types
    foreach ($evType in $RequiredEvidenceTypes) {
        if ($script:ValidEvidenceTypes -notcontains $evType) {
            Write-Warning "Unknown evidence type: $evType"
        }
    }

    # Validate evidence classes to avoid
    foreach ($evClass in $EvidenceClassesToAvoid) {
        if ($script:ValidEvidenceClassesToAvoid -notcontains $evClass) {
            Write-Warning "Unknown evidence class to avoid: $evClass"
        }
    }

    # Set default confidence policy if not provided
    $defaultConfidencePolicy = @{
        minimumThreshold = 0.7
        requireMultipleSources = $true
        minimumSourceCount = 2
        allowPartialMatch = $false
        escalateOnLowConfidence = $true
    }

    # Merge provided policy with defaults
    $mergedConfidencePolicy = $defaultConfidencePolicy.Clone()
    if ($ConfidencePolicy) {
        foreach ($key in $ConfidencePolicy.Keys) {
            $mergedConfidencePolicy[$key] = $ConfidencePolicy[$key]
        }
    }

    # Generate plan ID
    $planId = New-AnswerPlanId

    # Create plan object
    $plan = [ordered]@{
        schemaVersion = $script:AnswerPlanSchemaVersion
        planId = $planId
        createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        workspaceId = $WorkspaceId
        runId = $RunId
        query = $Query
        retrievalProfile = $RetrievalProfile
        packsToSearch = $PacksToSearch
        requiredEvidenceTypes = $RequiredEvidenceTypes
        evidenceClassesToAvoid = $EvidenceClassesToAvoid
        privatePublicBoundaryChecked = $PrivatePublicBoundaryChecked.IsPresent
        confidencePolicy = $mergedConfidencePolicy
        evidenceRequirements = [System.Collections.Generic.List[hashtable]]::new()
        dryRun = $DryRun.IsPresent
        metadata = @{
            createdBy = [Environment]::UserName
            createdOn = [Environment]::MachineName
            version = $script:AnswerPlanSchemaVersion
        }
    }

    Write-Verbose "[AnswerPlan] Created plan '$planId' for query: $Query"
    return $plan
}

function Add-PlanEvidence {
    <#
    .SYNOPSIS
        Adds evidence requirements to an answer plan.

    .DESCRIPTION
        Specifies additional evidence requirements with constraints such as
        minimum relevance score, required source packs, and whether the
        evidence is mandatory for answer completeness.

    .PARAMETER Plan
        The answer plan to add evidence requirements to.

    .PARAMETER EvidenceType
        Type of evidence required (e.g., "code-example", "api-reference").

    .PARAMETER Required
        Whether this evidence is mandatory.

    .PARAMETER MinimumRelevance
        Minimum relevance score (0.0-1.0) for evidence to be acceptable.

    .PARAMETER SourcePacks
        Specific packs to source this evidence from.

    .PARAMETER QueryTerms
        Additional query terms for finding this evidence.

    .OUTPUTS
        System.Collections.Hashtable. The added evidence requirement.

    .EXAMPLE
        Add-PlanEvidence -Plan $plan -EvidenceType "code-example" -Required $true -MinimumRelevance 0.8
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Plan,

        [Parameter(Mandatory = $true)]
        [string]$EvidenceType,

        [Parameter()]
        [bool]$Required = $false,

        [Parameter()]
        [double]$MinimumRelevance = 0.5,

        [Parameter()]
        [string[]]$SourcePacks = @(),

        [Parameter()]
        [string[]]$QueryTerms = @()
    )

    if ($MinimumRelevance -lt 0 -or $MinimumRelevance -gt 1) {
        throw "MinimumRelevance must be between 0.0 and 1.0"
    }

    $evidenceReq = [ordered]@{
        evidenceType = $EvidenceType
        required = $Required
        minimumRelevance = $MinimumRelevance
        sourcePacks = $SourcePacks
        queryTerms = $QueryTerms
        addedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    if (-not $Plan.ContainsKey('evidenceRequirements')) {
        $Plan.evidenceRequirements = [System.Collections.Generic.List[hashtable]]::new()
    }

    $Plan.evidenceRequirements.Add($evidenceReq)

    Write-Verbose "[AnswerPlan] Added evidence requirement '$EvidenceType' to plan '$($Plan.planId)'"
    return $evidenceReq
}

function Test-AnswerPlanCompleteness {
    <#
    .SYNOPSIS
        Validates answer plan completeness.

    .DESCRIPTION
        Checks that the answer plan has all required fields and that
        the plan meets minimum requirements for retrieval.

    .PARAMETER Plan
        The answer plan to validate.

    .PARAMETER Strict
        If specified, performs stricter validation (e.g., requires packs).

    .OUTPUTS
        System.Management.Automation.PSCustomObject. Validation result with Valid, Errors, and Warnings.

    .EXAMPLE
        $result = Test-AnswerPlanCompleteness -Plan $plan
        if (-not $result.Valid) { Write-Error $result.Errors }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Plan,

        [Parameter()]
        [switch]$Strict
    )

    $result = [ordered]@{
        Valid = $true
        Errors = [System.Collections.Generic.List[string]]::new()
        Warnings = [System.Collections.Generic.List[string]]::new()
        Checks = @{}
    }

    # Check required fields
    $requiredFields = @('planId', 'createdAt', 'workspaceId', 'query', 'retrievalProfile', 'confidencePolicy')
    foreach ($field in $requiredFields) {
        if (-not $Plan.ContainsKey($field) -or [string]::IsNullOrWhiteSpace($Plan[$field])) {
            $result.Errors.Add("Missing required field: $field")
            $result.Checks[$field] = $false
            $result.Valid = $false
        }
        else {
            $result.Checks[$field] = $true
        }
    }

    # Validate schema version
    if ($Plan.ContainsKey('schemaVersion')) {
        if ($Plan.schemaVersion -gt $script:AnswerPlanSchemaVersion) {
            $result.Warnings.Add("Schema version $($Plan.schemaVersion) is newer than supported version $script:AnswerPlanSchemaVersion")
            $result.Checks['SchemaVersion'] = $false
        }
        else {
            $result.Checks['SchemaVersion'] = $true
        }
    }

    # Check for query content
    if ($Plan.ContainsKey('query') -and $Plan.query.Length -lt 3) {
        $result.Warnings.Add("Query is very short (less than 3 characters)")
        $result.Checks['QueryLength'] = $false
    }
    else {
        $result.Checks['QueryLength'] = $true
    }

    # Strict mode checks
    if ($Strict) {
        if (-not $Plan.packsToSearch -or $Plan.packsToSearch.Count -eq 0) {
            $result.Errors.Add("Strict mode requires at least one pack to search")
            $result.Checks['HasPacks'] = $false
            $result.Valid = $false
        }
        else {
            $result.Checks['HasPacks'] = $true
        }

        if (-not $Plan.requiredEvidenceTypes -or $Plan.requiredEvidenceTypes.Count -eq 0) {
            $result.Warnings.Add("No required evidence types specified in strict mode")
            $result.Checks['HasEvidenceTypes'] = $false
        }
        else {
            $result.Checks['HasEvidenceTypes'] = $true
        }
    }

    # Validate confidence policy
    if ($Plan.ContainsKey('confidencePolicy')) {
        $policy = $Plan.confidencePolicy
        if ($policy.ContainsKey('minimumThreshold')) {
            $threshold = $policy.minimumThreshold
            if ($threshold -lt 0 -or $threshold -gt 1) {
                $result.Errors.Add("Confidence threshold must be between 0.0 and 1.0")
                $result.Checks['ConfidenceThreshold'] = $false
                $result.Valid = $false
            }
            else {
                $result.Checks['ConfidenceThreshold'] = $true
            }
        }
    }

    # Warn if private/public boundary not checked
    if (-not $Plan.privatePublicBoundaryChecked) {
        $result.Warnings.Add("Private/public boundary not checked")
        $result.Checks['BoundaryChecked'] = $false
    }
    else {
        $result.Checks['BoundaryChecked'] = $true
    }

    Write-Verbose "[AnswerPlan] Validated plan '$($Plan.planId)': Valid=$($result.Valid)"
    return [pscustomobject]$result
}

function Export-AnswerPlan {
    <#
    .SYNOPSIS
        Exports an answer plan to JSON.

    .DESCRIPTION
        Serializes the answer plan to JSON and saves it to the specified path
        or to the default traces directory.

    .PARAMETER Plan
        The answer plan to export.

    .PARAMETER Path
        The file path to save to. If not provided, uses default location.

    .PARAMETER ProjectRoot
        The project root directory. Defaults to current directory.

    .PARAMETER UseAtomicWrite
        Use atomic file write for durability.

    .OUTPUTS
        System.String. The path to the exported file.

    .EXAMPLE
        Export-AnswerPlan -Plan $plan -Path "plans/my-plan.json"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Plan,

        [Parameter()]
        [string]$Path = "",

        [Parameter()]
        [string]$ProjectRoot = ".",

        [Parameter()]
        [switch]$UseAtomicWrite = $true
    )

    # Resolve project root
    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) {
        $resolvedRoot = $ProjectRoot
    }

    # Determine export path
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $plansDir = Join-Path $resolvedRoot $script:DefaultTracesDirectory
        $Path = Join-Path $plansDir "$($Plan.planId).json"
    }

    # Ensure directory exists
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Export with schema wrapper
    $export = [ordered]@{
        schemaVersion = $script:AnswerPlanSchemaVersion
        schemaName = "answer-plan"
        exportedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        exportedBy = [Environment]::UserName
        plan = $Plan
    }

    $json = $export | ConvertTo-Json -Depth 10

    try {
        if ($UseAtomicWrite) {
            $atomicCmd = Get-Command Write-AtomicFile -ErrorAction SilentlyContinue
            if ($atomicCmd) {
                & $atomicCmd -Path $Path -Content $json -Format Text | Out-Null
            }
            else {
                $json | Out-File -FilePath $Path -Encoding UTF8 -Force
            }
        }
        else {
            $json | Out-File -FilePath $Path -Encoding UTF8 -Force
        }
    }
    catch {
        throw "Failed to export answer plan: $_"
    }

    Write-Verbose "[AnswerPlan] Exported plan to: $Path"
    return $Path
}

function Import-AnswerPlan {
    <#
    .SYNOPSIS
        Imports an answer plan from JSON.

    .DESCRIPTION
        Loads an answer plan from a JSON file with schema validation.

    .PARAMETER Path
        The file path to load from.

    .PARAMETER ValidateSchema
        Whether to validate schema version.

    .OUTPUTS
        System.Collections.Hashtable. The loaded answer plan.

    .EXAMPLE
        $plan = Import-AnswerPlan -Path "plans/plan-xxx.json"
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [switch]$ValidateSchema = $true
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Answer plan file not found: $Path"
    }

    try {
        $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $wrapper = $content | ConvertFrom-Json -AsHashtable
    }
    catch {
        throw "Failed to parse answer plan: $_"
    }

    # Validate schema
    if ($ValidateSchema) {
        $schemaVersion = $wrapper.schemaVersion
        if ($schemaVersion -and $schemaVersion -gt $script:AnswerPlanSchemaVersion) {
            throw "Answer plan schema version $schemaVersion is newer than supported version $script:AnswerPlanSchemaVersion"
        }
    }

    $plan = $wrapper.plan
    if (-not $plan) {
        # Try loading as raw plan (without wrapper)
        $plan = $wrapper
    }

    Write-Verbose "[AnswerPlan] Imported plan '$($plan.planId)' from: $Path"
    return $plan
}

#===============================================================================
# Answer Trace Functions (Section 15.2)
#===============================================================================

function New-AnswerTrace {
    <#
    .SYNOPSIS
        Creates an answer trace after synthesis.

    .DESCRIPTION
        Initializes an answer trace that records what evidence was used,
        what was excluded and why, confidence decisions, and answer mode.
        Must be created after synthesis completes.

    .PARAMETER Plan
        The answer plan that guided this synthesis.

    .PARAMETER Query
        The original query (if not using a plan).

    .PARAMETER AnswerMode
        The answer mode: direct, caveat, dispute, abstain, or escalate.

    .PARAMETER ConfidenceDecision
        Hashtable with confidence scores and decision rationale.

    .PARAMETER WorkspaceContext
        Workspace context information.

    .PARAMETER Caveats
        Array of caveat strings attached to the answer.

    .PARAMETER AbstainReason
        Reason for abstaining (if AnswerMode is 'abstain').

    .PARAMETER EscalationTarget
        Target for escalation (if AnswerMode is 'escalate').

    .PARAMETER RunId
        Optional run ID for correlation.

    .OUTPUTS
        System.Collections.Hashtable. The answer trace object.

    .EXAMPLE
        $trace = New-AnswerTrace -Plan $plan -AnswerMode "caveat" -ConfidenceDecision $decision
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [hashtable]$Plan = $null,

        [Parameter()]
        [string]$Query = "",

        [Parameter(Mandatory = $true)]
        [ValidateSet('direct', 'caveat', 'dispute', 'abstain', 'escalate')]
        [string]$AnswerMode,

        [Parameter()]
        [hashtable]$ConfidenceDecision = @{},

        [Parameter()]
        [hashtable]$WorkspaceContext = @{},

        [Parameter()]
        [string[]]$Caveats = @(),

        [Parameter()]
        [string]$AbstainReason = "",

        [Parameter()]
        [string]$EscalationTarget = "",

        [Parameter()]
        [string]$RunId = ""
    )

    # Get or generate run ID
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        $RunId = Get-AnswerPlanRunId
    }

    # Get query from plan if not provided
    if ([string]::IsNullOrWhiteSpace($Query) -and $Plan) {
        $Query = $Plan.query
    }

    # Validate answer mode-specific fields
    if ($AnswerMode -eq 'abstain' -and [string]::IsNullOrWhiteSpace($AbstainReason)) {
        Write-Warning "Answer mode is 'abstain' but no reason provided"
    }

    if ($AnswerMode -eq 'escalate' -and [string]::IsNullOrWhiteSpace($EscalationTarget)) {
        Write-Warning "Answer mode is 'escalate' but no target provided"
    }

    # Get workspace context if available
    if ($WorkspaceContext.Count -eq 0) {
        $WorkspaceContext = Get-WorkspaceContextForTrace
    }

    # Generate trace ID
    $traceId = New-AnswerTraceId

    # Create trace object
    $trace = [ordered]@{
        schemaVersion = $script:AnswerTraceSchemaVersion
        traceId = $traceId
        planId = if ($Plan) { $Plan.planId } else { $null }
        runId = $RunId
        createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        query = $Query
        evidenceUsed = [System.Collections.Generic.List[hashtable]]::new()
        evidenceExcluded = [System.Collections.Generic.List[hashtable]]::new()
        answerMode = $AnswerMode
        confidenceDecision = $ConfidenceDecision
        workspaceContext = $WorkspaceContext
        packVersions = @{}  # Populated as evidence is added
        caveats = $Caveats
        abstainDecision = if ($AnswerMode -eq 'abstain') {
            @{
                abstained = $true
                reason = $AbstainReason
                timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            }
        }
        else {
            $null
        }
        escalationDecision = if ($AnswerMode -eq 'escalate') {
            @{
                escalated = $true
                target = $EscalationTarget
                timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            }
        }
        else {
            $null
        }
        metadata = @{
            createdBy = [Environment]::UserName
            createdOn = [Environment]::MachineName
            version = $script:AnswerTraceSchemaVersion
        }
    }

    Write-Verbose "[AnswerTrace] Created trace '$traceId' for query: $Query"
    return $trace
}

function Add-TraceEvidence {
    <#
    .SYNOPSIS
        Adds evidence record to an answer trace.

    .DESCRIPTION
        Records evidence that was used in the answer synthesis,
        including source, relevance score, and content reference.

    .PARAMETER Trace
        The answer trace to add evidence to.

    .PARAMETER EvidenceId
        Unique identifier for this evidence.

    .PARAMETER SourcePack
        Pack ID where evidence was found.

    .PARAMETER SourceType
        Type of source (file, api, doc, etc.).

    .PARAMETER SourcePath
        Path to the source within the pack.

    .PARAMETER RelevanceScore
        Relevance score (0.0-1.0).

    .PARAMETER EvidenceType
        Type of evidence (code-example, api-reference, etc.).

    .PARAMETER ContentHash
        Hash of content for verification.

    .PARAMETER ContentPreview
        Preview of the evidence content.

    .PARAMETER PackVersion
        Version of the pack when evidence was retrieved.

    .OUTPUTS
        System.Collections.Hashtable. The added evidence record.

    .EXAMPLE
        Add-TraceEvidence -Trace $trace -EvidenceId "ev-001" -SourcePack "rpgmaker-mz-core" -RelevanceScore 0.95
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Trace,

        [Parameter(Mandatory = $true)]
        [string]$EvidenceId,

        [Parameter(Mandatory = $true)]
        [string]$SourcePack,

        [Parameter()]
        [string]$SourceType = "file",

        [Parameter()]
        [string]$SourcePath = "",

        [Parameter()]
        [double]$RelevanceScore = 0.0,

        [Parameter()]
        [string]$EvidenceType = "",

        [Parameter()]
        [string]$ContentHash = "",

        [Parameter()]
        [string]$ContentPreview = "",

        [Parameter()]
        [string]$PackVersion = ""
    )

    if ($RelevanceScore -lt 0 -or $RelevanceScore -gt 1) {
        throw "RelevanceScore must be between 0.0 and 1.0"
    }

    $evidence = [ordered]@{
        evidenceId = $EvidenceId
        sourcePack = $SourcePack
        sourceType = $SourceType
        sourcePath = $SourcePath
        relevanceScore = $RelevanceScore
        evidenceType = $EvidenceType
        contentHash = $ContentHash
        contentPreview = $ContentPreview
        packVersion = $PackVersion
        addedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    if (-not $Trace.ContainsKey('evidenceUsed')) {
        $Trace.evidenceUsed = [System.Collections.Generic.List[hashtable]]::new()
    }

    $Trace.evidenceUsed.Add($evidence)

    # Track pack version
    if (-not [string]::IsNullOrWhiteSpace($PackVersion)) {
        if (-not $Trace.packVersions.ContainsKey($SourcePack)) {
            $Trace.packVersions[$SourcePack] = $PackVersion
        }
    }

    Write-Verbose "[AnswerTrace] Added evidence '$EvidenceId' from pack '$SourcePack' to trace '$($Trace.traceId)'"
    return $evidence
}

function Add-TraceExclusion {
    <#
    .SYNOPSIS
        Records why evidence was excluded from the answer.

    .DESCRIPTION
        Documents evidence that was considered but excluded,
        along with the reason for exclusion. Important for audit
        and understanding answer limitations.

    .PARAMETER Trace
        The answer trace to add exclusion to.

    .PARAMETER EvidenceId
        Unique identifier for the excluded evidence.

    .PARAMETER SourcePack
        Pack ID where evidence was found.

    .PARAMETER SourcePath
        Path to the source.

    .PARAMETER ExclusionReason
        Reason for exclusion (e.g., "low-relevance", "deprecated", "boundary-violation").

    .PARAMETER RelevanceScore
        Original relevance score before exclusion.

    .PARAMETER Details
        Additional details about the exclusion.

    .OUTPUTS
        System.Collections.Hashtable. The added exclusion record.

    .EXAMPLE
        Add-TraceExclusion -Trace $trace -EvidenceId "ev-002" -ExclusionReason "deprecated" -Details "Uses deprecated API"
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Trace,

        [Parameter(Mandatory = $true)]
        [string]$EvidenceId,

        [Parameter(Mandatory = $true)]
        [string]$SourcePack,

        [Parameter()]
        [string]$SourcePath = "",

        [Parameter(Mandatory = $true)]
        [string]$ExclusionReason,

        [Parameter()]
        [double]$RelevanceScore = 0.0,

        [Parameter()]
        [string]$Details = ""
    )

    $exclusion = [ordered]@{
        evidenceId = $EvidenceId
        sourcePack = $SourcePack
        sourcePath = $SourcePath
        exclusionReason = $ExclusionReason
        relevanceScore = $RelevanceScore
        details = $Details
        excludedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    if (-not $Trace.ContainsKey('evidenceExcluded')) {
        $Trace.evidenceExcluded = [System.Collections.Generic.List[hashtable]]::new()
    }

    $Trace.evidenceExcluded.Add($exclusion)

    Write-Verbose "[AnswerTrace] Added exclusion '$EvidenceId' (reason: $ExclusionReason) to trace '$($Trace.traceId)'"
    return $exclusion
}

function Export-AnswerTrace {
    <#
    .SYNOPSIS
        Exports answer trace to JSON for audit.

    .DESCRIPTION
        Serializes the answer trace to JSON with file locking and atomic writes.
        Also writes to the latest-answer-trace.json file for quick access.

    .PARAMETER Trace
        The answer trace to export.

    .PARAMETER Path
        The file path to save to. If not provided, uses default location.

    .PARAMETER ProjectRoot
        The project root directory. Defaults to current directory.

    .PARAMETER WriteLatest
        Also write to latest-answer-trace.json.

    .PARAMETER UseLock
        Use file locking for thread safety.

    .OUTPUTS
        System.String. The path to the exported file.

    .EXAMPLE
        Export-AnswerTrace -Trace $trace -WriteLatest
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Trace,

        [Parameter()]
        [string]$Path = "",

        [Parameter()]
        [string]$ProjectRoot = ".",

        [Parameter()]
        [switch]$WriteLatest = $true,

        [Parameter()]
        [switch]$UseLock = $true
    )

    # Resolve project root
    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) {
        $resolvedRoot = $ProjectRoot
    }

    # Determine export path
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $tracesDir = Join-Path $resolvedRoot $script:DefaultTracesDirectory
        $Path = Join-Path $tracesDir "$($Trace.traceId).json"
    }

    # Ensure directory exists
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Export with schema wrapper
    $export = [ordered]@{
        schemaVersion = $script:AnswerTraceSchemaVersion
        schemaName = "answer-trace"
        exportedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        exportedBy = [Environment]::UserName
        trace = $Trace
    }

    $json = $export | ConvertTo-Json -Depth 10

    # Acquire lock if requested
    $lockInfo = $null
    if ($UseLock) {
        $lockCmd = Get-Command Lock-File -ErrorAction SilentlyContinue
        if ($lockCmd) {
            try {
                $lockInfo = & $lockCmd -Name "trace" -TimeoutSeconds 10 -ProjectRoot $resolvedRoot
            }
            catch {
                Write-Warning "Could not acquire lock for trace export: $_"
            }
        }
    }

    try {
        # Use atomic write if available
        $atomicCmd = Get-Command Write-AtomicFile -ErrorAction SilentlyContinue
        if ($atomicCmd) {
            & $atomicCmd -Path $Path -Content $json -Format Text | Out-Null
        }
        else {
            $json | Out-File -FilePath $Path -Encoding UTF8 -Force
        }

        # Write to latest-answer-trace.json if requested
        if ($WriteLatest) {
            $latestPath = Join-Path $resolvedRoot $script:DefaultReportsDirectory $script:LatestTraceFileName
            $latestDir = Split-Path -Parent $latestPath
            if (-not (Test-Path -LiteralPath $latestDir)) {
                New-Item -ItemType Directory -Path $latestDir -Force | Out-Null
            }

            if ($atomicCmd) {
                & $atomicCmd -Path $latestPath -Content $json -Format Text | Out-Null
            }
            else {
                $json | Out-File -FilePath $latestPath -Encoding UTF8 -Force
            }
            Write-Verbose "[AnswerTrace] Also wrote to latest trace: $latestPath"
        }
    }
    finally {
        # Release lock
        if ($lockInfo) {
            $unlockCmd = Get-Command Unlock-File -ErrorAction SilentlyContinue
            if ($unlockCmd) {
                & $unlockCmd -Name "trace" -ProjectRoot $resolvedRoot | Out-Null
            }
        }
    }

    Write-Verbose "[AnswerTrace] Exported trace to: $Path"
    return $Path
}

function Get-AnswerTrace {
    <#
    .SYNOPSIS
        Retrieves an answer trace by ID.

    .DESCRIPTION
        Loads an answer trace from the traces directory by its trace ID.

    .PARAMETER TraceId
        The trace ID to retrieve.

    .PARAMETER ProjectRoot
        The project root directory.

    .PARAMETER IncludeRaw
        Include the raw JSON in the output.

    .OUTPUTS
        System.Collections.Hashtable. The answer trace.

    .EXAMPLE
        $trace = Get-AnswerTrace -TraceId "trace-20260412T..."
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TraceId,

        [Parameter()]
        [string]$ProjectRoot = ".",

        [Parameter()]
        [switch]$IncludeRaw
    )

    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) {
        $resolvedRoot = $ProjectRoot
    }

    $tracesDir = Join-Path $resolvedRoot $script:DefaultTracesDirectory
    $path = Join-Path $tracesDir "$TraceId.json"

    if (-not (Test-Path -LiteralPath $path)) {
        # Try looking for any file containing the trace ID
        $files = Get-ChildItem -Path $tracesDir -Filter "*.json" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*$TraceId*" }
        
        if ($files -and $files.Count -gt 0) {
            $path = $files[0].FullName
        }
        else {
            throw "Answer trace not found: $TraceId"
        }
    }

    try {
        $content = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        $wrapper = $content | ConvertFrom-Json -AsHashtable
    }
    catch {
        throw "Failed to parse answer trace: $_"
    }

    $trace = $wrapper.trace
    if (-not $trace) {
        $trace = $wrapper
    }

    if ($IncludeRaw) {
        $trace._rawJson = $content
    }

    Write-Verbose "[AnswerTrace] Retrieved trace '$TraceId' from: $path"
    return $trace
}

function Get-LatestAnswerTrace {
    <#
    .SYNOPSIS
        Retrieves the latest answer trace from the reports directory.

    .DESCRIPTION
        Loads the most recent answer trace from latest-answer-trace.json.

    .PARAMETER ProjectRoot
        The project root directory.

    .OUTPUTS
        System.Collections.Hashtable. The latest answer trace, or $null if not found.

    .EXAMPLE
        $trace = Get-LatestAnswerTrace
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$ProjectRoot = "."
    )

    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) {
        $resolvedRoot = $ProjectRoot
    }

    $latestPath = Join-Path $resolvedRoot $script:DefaultReportsDirectory $script:LatestTraceFileName

    if (-not (Test-Path -LiteralPath $latestPath)) {
        return $null
    }

    try {
        $content = Get-Content -LiteralPath $latestPath -Raw -ErrorAction Stop
        $wrapper = $content | ConvertFrom-Json -AsHashtable
    }
    catch {
        Write-Warning "Failed to parse latest answer trace: $_"
        return $null
    }

    $trace = $wrapper.trace
    if (-not $trace) {
        $trace = $wrapper
    }

    return $trace
}

#===============================================================================
# Helper Functions
#===============================================================================

function New-AnswerPlanId {
    <#
    .SYNOPSIS
        Generates a unique answer plan ID.
    #>
    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
    $guid = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    return "plan-ans-$timestamp-$guid"
}

function New-AnswerTraceId {
    <#
    .SYNOPSIS
        Generates a unique answer trace ID.
    #>
    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
    $guid = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    return "trace-$timestamp-$guid"
}

function Get-AnswerPlanRunId {
    <#
    .SYNOPSIS
        Gets or generates a run ID for answer plan/trace correlation.
    #>
    # Try to get from RunId.ps1 module
    $runIdCmd = Get-Command Get-CurrentRunId -ErrorAction SilentlyContinue
    if ($runIdCmd) {
        try {
            return & $runIdCmd
        }
        catch {
            # Fall through to generate new
        }
    }

    # Generate new run ID
    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
    $random = -join ((1..4) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
    return "$timestamp-$random"
}

function Get-CurrentWorkspaceId {
    <#
    .SYNOPSIS
        Gets the current workspace ID.
    #>
    # Try to get from environment variable
    $envWorkspace = [Environment]::GetEnvironmentVariable('LLM_WORKFLOW_CURRENT_WORKSPACE')
    if ($envWorkspace) {
        return $envWorkspace
    }

    # Try to get from Workspace.ps1 module
    $workspaceCmd = Get-Command Get-CurrentWorkspace -ErrorAction SilentlyContinue
    if ($workspaceCmd) {
        try {
            $workspace = & $workspaceCmd
            if ($workspace -and $workspace.workspaceId) {
                return $workspace.workspaceId
            }
        }
        catch {
            # Fall through
        }
    }

    return "unknown"
}

function Get-WorkspaceContextForTrace {
    <#
    .SYNOPSIS
        Gets workspace context information for trace.
    #>
    $context = @{
        workspaceId = Get-CurrentWorkspaceId
        capturedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    # Try to get additional workspace info
    $workspaceCmd = Get-Command Get-CurrentWorkspace -ErrorAction SilentlyContinue
    if ($workspaceCmd) {
        try {
            $workspace = & $workspaceCmd
            if ($workspace) {
                $context.type = $workspace.type
                $context.packsEnabled = $workspace.packsEnabled
            }
        }
        catch {
            # Ignore errors
        }
    }

    return $context
}

#===============================================================================
# Module Export
#===============================================================================

Export-ModuleMember -Function @(
    # Answer Plan Functions (Section 15.1)
    'New-AnswerPlan'
    'Add-PlanEvidence'
    'Test-AnswerPlanCompleteness'
    'Export-AnswerPlan'
    'Import-AnswerPlan'
    # Answer Trace Functions (Section 15.2)
    'New-AnswerTrace'
    'Add-TraceEvidence'
    'Add-TraceExclusion'
    'Export-AnswerTrace'
    'Get-AnswerTrace'
    'Get-LatestAnswerTrace'
)
