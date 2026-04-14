#requires -Version 5.1
<#
.SYNOPSIS
    Confidence and Abstain Policy Module for LLM Workflow Platform - Phase 5 Implementation.

.DESCRIPTION
    Implements Section 15.4 Confidence Policy and Answer Modes for the LLM Workflow platform.
    
    This module provides confidence-based decision making for answer synthesis:
    - **direct**: High confidence (>=0.85), answer directly without caveats
    - **caveat**: Medium confidence (>=0.70), answer with warnings and limitations
    - **dispute**: Multiple conflicting high-authority sources, surface the dispute
    - **abstain**: Low confidence (<0.50), decline to answer with explanation
    - **escalate**: Policy violation or boundary issue, escalate to human review
    
    Confidence Calculation Factors (Section 15.4.1):
    - Evidence relevance scores (0-40%)
    - Source authority/trust (0-30%)
    - Evidence consistency (0-20%)
    - Coverage of required evidence types (0-10%)
    
    Answer Mode Thresholds (Default):
    - direct: >= 0.85
    - caveat: >= 0.70
    - dispute: Multiple high-authority conflicting sources
    - abstain: < 0.50
    - escalate: Policy violation or boundary issue

.NOTES
    File: ConfidencePolicy.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Phase: 5 - Retrieval and Answer Integrity
    Implements: Section 15.4 (Confidence Policy), Section 15.4.1 (Confidence Calculation)

.EXAMPLE
    # Evaluate confidence for answer synthesis
    $evidence = @(
        @{ sourceId = "src1"; relevanceScore = 0.95; authorityScore = 0.90; sourceType = "core-runtime" },
        @{ sourceId = "src2"; relevanceScore = 0.88; authorityScore = 0.85; sourceType = "exemplar-pattern" }
    )
    $confidence = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $plan -Context @{}

.EXAMPLE
    # Get answer mode based on confidence score
    $mode = Get-AnswerMode -ConfidenceScore 0.75 -Policy (Get-DefaultConfidencePolicy) -EvidenceIssues @()
    # Returns: "caveat"

.EXAMPLE
    # Check if should abstain
    $shouldAbstain = Test-ShouldAbstain -ConfidenceScore 0.45 -Evidence $evidence -Policy (Get-DefaultConfidencePolicy)
    # Returns: $true with reason "Confidence below minimum threshold"
#>

Set-StrictMode -Version Latest

function New-CorrelationId {
    return [Guid]::NewGuid().ToString()
}

#===============================================================================
# Configuration and Constants
#===============================================================================

$script:ConfidencePolicySchemaVersion = 1

# Valid answer modes per Section 15.4 specification
$script:ValidAnswerModes = @('direct', 'caveat', 'dispute', 'abstain', 'escalate')

# Default confidence thresholds (can be overridden by policy)
$script:DefaultThresholds = @{
    direct   = 0.85
    caveat   = 0.70
    abstain  = 0.50
}

# Authority role weights for source scoring
$script:AuthorityRoleWeights = @{
    'core-runtime'      = 1.00
    'core-engine'       = 1.00
    'core-blender'      = 1.00
    'private-project'   = 0.95
    'language-binding'  = 0.90
    'deployment-tooling'= 0.85
    'mcp-integration'   = 0.85
    'visual-system'     = 0.80
    'exemplar-pattern'  = 0.75
    'llm-workflow'      = 0.70
    'tooling-analyzer'  = 0.70
    'synth-proc'        = 0.70
    'starter-template'  = 0.65
    'curated-index'     = 0.60
    'reverse-format'    = 0.55
    'physics-extension' = 0.80
    'community'         = 0.50
    'unknown'           = 0.40
}

# Trust tier weights
$script:TrustTierWeights = @{
    'High'        = 1.00
    'Medium-High' = 0.85
    'Medium'      = 0.70
    'Low'         = 0.50
    'Quarantined' = 0.20
}

# Evidence type weights for coverage calculation
$script:EvidenceTypeWeights = @{
    'code-example'         = 1.0
    'api-reference'        = 1.0
    'tutorial'             = 0.9
    'explanation'          = 0.8
    'configuration'        = 0.9
    'schema-definition'    = 1.0
    'dependency-info'      = 0.7
    'version-compatibility'= 0.8
}

#===============================================================================
# Main Confidence Evaluation Function
#===============================================================================

function Test-AnswerConfidence {
    <#
    .SYNOPSIS
        Main confidence evaluation function for answer synthesis.

    .DESCRIPTION
        Evaluates the overall confidence of an answer based on evidence quality,
        source authority, consistency, and coverage of required evidence types.
        Returns a comprehensive confidence decision object.

    .PARAMETER Evidence
        Array of evidence items. Each item should have:
        - sourceId: Unique identifier
        - relevanceScore: 0.0-1.0 relevance to query
        - authorityScore: 0.0-1.0 source authority (optional, computed if missing)
        - sourceType: Authority role (e.g., "core-runtime", "exemplar-pattern")
        - trustTier: Source trust tier (optional)
        - content: Evidence content or reference
        - evidenceType: Type of evidence

    .PARAMETER AnswerPlan
        The answer plan hashtable that defined requirements for this answer.

    .PARAMETER Context
        Additional context for confidence evaluation (optional).

    .OUTPUTS
        System.Collections.Hashtable. Confidence decision with:
        - confidenceScore: Overall confidence (0.0-1.0)
        - answerMode: Recommended answer mode
        - components: Breakdown of confidence components
        - reasoning: Detailed reasoning for the decision
        - shouldAbstain: Boolean indicating if should abstain
        - abstainReason: Reason for abstention (if applicable)
        - evidenceIssues: Array of identified issues
        - timestamp: UTC timestamp of evaluation

    .EXAMPLE
        $evidence = @(
            @{ sourceId = "ev1"; relevanceScore = 0.92; sourceType = "core-runtime"; evidenceType = "code-example" },
            @{ sourceId = "ev2"; relevanceScore = 0.85; sourceType = "exemplar-pattern"; evidenceType = "tutorial" }
        )
        $confidence = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $plan
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [array]$Evidence = @(),

        [Parameter(Mandatory = $true)]
        [hashtable]$AnswerPlan,

        [Parameter()]
        [hashtable]$Context = @{},

        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        $evaluationId = [Guid]::NewGuid().ToString()
        Write-Verbose "[$CorrelationId] [ConfidencePolicy] Starting confidence evaluation [$evaluationId]"
    }

    process {
        try {
            # Ensure Evidence is array for PS 5.1 compatibility
            $evidenceList = @($Evidence)

            # Validate evidence array
            if ($evidenceList.Count -eq 0) {
                return Get-AbstainDecision -CorrelationId $CorrelationId -ConfidenceScore 0.0 `
                    -Reason "No evidence provided for answer synthesis" `
                    -Alternatives @{ suggestion = "Provide relevant evidence items" }
            }

            # Get confidence components
            $components = Get-ConfidenceComponents -Evidence $evidenceList -Context $Context -CorrelationId $CorrelationId

            # Calculate overall confidence score
            $confidenceScore = Calculate-OverallConfidence -Components $components

            # Identify evidence issues - wrap in @() for PS 5.1 compatibility
            $evidenceIssues = @(Get-EvidenceIssues -Evidence $evidenceList -Components $components)

            # Get policy from answer plan or use default
            $policy = if ($AnswerPlan.ContainsKey('confidencePolicy')) {
                Merge-ConfidencePolicy -CustomPolicy $AnswerPlan.confidencePolicy -CorrelationId $CorrelationId
            }
            else {
                Get-DefaultConfidencePolicy -CorrelationId $CorrelationId
            }

            # Determine answer mode
            $answerMode = Get-AnswerMode -ConfidenceScore $confidenceScore `
                -Policy $policy `
                -EvidenceIssues $evidenceIssues `
                -CorrelationId $CorrelationId

            # Build detailed reasoning
            $reasoning = Build-ConfidenceReasoning -Components $components `
                -Score $confidenceScore `
                -AnswerMode $answerMode `
                -Issues $evidenceIssues

            # Check for abstention
            $shouldAbstain = Test-ShouldAbstain -ConfidenceScore $confidenceScore `
                -Evidence $evidenceList `
                -Policy $policy `
                -CorrelationId $CorrelationId

            # Create confidence decision
            $decision = [ordered]@{
                evaluationId     = $evaluationId
                correlationId    = $CorrelationId
                schemaVersion    = $script:ConfidencePolicySchemaVersion
                confidenceScore  = [Math]::Round($confidenceScore, 4)
                answerMode       = $answerMode
                shouldAbstain    = $shouldAbstain
                abstainReason    = if ($shouldAbstain) { $reasoning.PrimaryConcern } else { $null }
                components       = $components
                reasoning        = $reasoning
                evidenceIssues   = $evidenceIssues
                evidenceCount    = $evidenceList.Count
                policyUsed       = $policy.policyName
                evaluatedAt      = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
                metadata         = @{
                    createdBy = [Environment]::UserName
                    createdOn = [Environment]::MachineName
                }
            }

            Write-Verbose "[$CorrelationId] [ConfidencePolicy] Evaluation complete: Score=$confidenceScore, Mode=$answerMode"
            return $decision
        }
        catch {
            Write-Error "[$CorrelationId] [ConfidencePolicy] Confidence evaluation failed: $_"
            
            # Return abstain decision on error
            return Get-AbstainDecision -CorrelationId $CorrelationId -ConfidenceScore 0.0 `
                -Reason "Confidence evaluation error: $($_.Exception.Message)" `
                -Alternatives @{ error = $_.Exception.Message }
        }
    }
}

#===============================================================================
# Confidence Component Evaluation
#===============================================================================

function Get-ConfidenceComponents {
    <#
    .SYNOPSIS
        Evaluates confidence components from evidence.

    .DESCRIPTION
        Calculates the four confidence components per Section 15.4.1:
        1. Evidence relevance (0-40%)
        2. Source authority/trust (0-30%)
        3. Evidence consistency (0-20%)
        4. Coverage of required types (0-10%)

    .PARAMETER Evidence
        Array of evidence items to evaluate.

    .PARAMETER Context
        Additional context for evaluation.

    .OUTPUTS
        System.Collections.Hashtable with component scores and details.

    .EXAMPLE
        $components = Get-ConfidenceComponents -Evidence $evidence -Context @{}
        # Returns: @{ relevance = 0.35; authority = 0.28; consistency = 0.18; coverage = 0.08 }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Evidence,

        [Parameter()]
        [hashtable]$Context = @{},

        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] [ConfidencePolicy] Evaluating confidence components"
    }

    process {
        $components = [ordered]@{
            correlationId = $CorrelationId
            relevance   = Calculate-RelevanceComponent -Evidence $Evidence
            authority   = Calculate-AuthorityComponent -Evidence $Evidence
            consistency = Calculate-ConsistencyComponent -Evidence $Evidence
            coverage    = Calculate-CoverageComponent -Evidence $Evidence -Context $Context
        }

        # Normalize to weights per specification
        $components.relevance.score = [Math]::Min(0.40, $components.relevance.score * 0.40)
        $components.authority.score = [Math]::Min(0.30, $components.authority.score * 0.30)
        $components.consistency.score = [Math]::Min(0.20, $components.consistency.score * 0.20)
        $components.coverage.score = [Math]::Min(0.10, $components.coverage.score * 0.10)

        return $components
    }
}

function Calculate-RelevanceComponent {
    <#
    .SYNOPSIS
        Calculates evidence relevance component (0-40%).
    #>
    [CmdletBinding()]
    param([array]$Evidence)

    $evidenceList = @($Evidence)
    if ($evidenceList.Count -eq 0) { return @{ score = 0.0; details = @() } }

    $scores = @()
    $details = @()

    foreach ($item in $evidenceList) {
        $relevance = if ($item.ContainsKey('relevanceScore')) {
            $item.relevanceScore
        }
        elseif ($item.ContainsKey('score')) {
            $item.score
        }
        else {
            0.5  # Default if not specified
        }

        # Ensure valid range
        $relevance = [Math]::Max(0.0, [Math]::Min(1.0, $relevance))
        $scores += $relevance

        $details += @{
            sourceId = $item.sourceId
            relevanceScore = $relevance
        }
    }

    # Use weighted average - higher relevance items count more
    $weightedSum = 0
    $weightSum = 0
    for ($i = 0; $i -lt $scores.Count; $i++) {
        $weight = $scores[$i]  # Weight by relevance itself
        $weightedSum += $scores[$i] * $weight
        $weightSum += $weight
    }

    $avgScore = if ($weightSum -gt 0) { $weightedSum / $weightSum } else { 0 }

    return @{
        score = [Math]::Round($avgScore, 4)
        details = $details
        topRelevance = ($scores | Measure-Object -Maximum).Maximum
    }
}

function Calculate-AuthorityComponent {
    <#
    .SYNOPSIS
        Calculates source authority component (0-30%).
    #>
    [CmdletBinding()]
    param([array]$Evidence)

    $evidenceList = @($Evidence)
    if ($evidenceList.Count -eq 0) { return @{ score = 0.0; details = @() } }

    $scores = @()
    $details = @()

    foreach ($item in $evidenceList) {
        $authority = 0.5  # Default

        # Check for pre-computed authority score
        if ($item.ContainsKey('authorityScore')) {
            $authority = $item.authorityScore
        }
        # Check for source type/role
        elseif ($item.ContainsKey('sourceType') -or $item.ContainsKey('authorityRole')) {
            $role = if ($item.ContainsKey('sourceType')) { $item.sourceType } else { $item.authorityRole }
            if ($script:AuthorityRoleWeights.ContainsKey($role)) {
                $authority = $script:AuthorityRoleWeights[$role]
            }
        }

        # Apply trust tier if available
        if ($item.ContainsKey('trustTier') -and $script:TrustTierWeights.ContainsKey($item.trustTier)) {
            $authority = $authority * $script:TrustTierWeights[$item.trustTier]
        }

        # Ensure valid range
        $authority = [Math]::Max(0.0, [Math]::Min(1.0, $authority))
        $scores += $authority

        $details += @{
            sourceId = $item.sourceId
            authorityScore = $authority
            role = $item.sourceType
        }
    }

    # Calculate average authority
    $avgAuthority = ($scores | Measure-Object -Average).Average

    # Bonus for multiple high-authority sources
    $highAuthorityCount = @($scores | Where-Object { $_ -ge 0.8 }).Count
    $bonus = [Math]::Min(0.1, $highAuthorityCount * 0.05)

    return @{
        score = [Math]::Round([Math]::Min(1.0, $avgAuthority + $bonus), 4)
        details = $details
        highAuthorityCount = $highAuthorityCount
    }
}

function Calculate-ConsistencyComponent {
    <#
    .SYNOPSIS
        Calculates evidence consistency component (0-20%).
    #>
    [CmdletBinding()]
    param([array]$Evidence)

    $evidenceList = @($Evidence)
    if ($evidenceList.Count -lt 2) {
        return @{
            score = 0.75  # Neutral score for single evidence
            details = @{
                hasContradictions = $false
                contradictionInfo = @{}
                distinctClaims = 1
                consistencyType = "insufficient-evidence"
                note = "Single evidence item"
            }
        }
    }

    # Check for conflicting claims
    $conflicts = @()
    $supports = @()

    # Group evidence by claim/content similarity
    $grouped = @{}
    foreach ($item in $evidenceList) {
        $key = if ($item.ContainsKey('claim')) { $item.claim }
               elseif ($item.ContainsKey('content')) { $item.content.GetHashCode() }
               else { $item.sourceId }
        
        if (-not $grouped.ContainsKey($key)) {
            $grouped[$key] = @()
        }
        $grouped[$key] += $item
    }

    # Check for contradictory evidence
    $hasContradictions = $false
    $contradictionDetails = @()

    if ($grouped.Count -gt 1) {
        # Multiple different claims found
        $largestGroup = $grouped.Values | Sort-Object @{Expression={$_.Count}; Descending=$true} | Select-Object -First 1
        $agreementRatio = $largestGroup.Count / $evidenceList.Count

        if ($agreementRatio -lt 0.6) {
            $hasContradictions = $true
            $contradictionDetails = @{
                agreementRatio = [Math]::Round($agreementRatio, 2)
                distinctClaims = $grouped.Count
            }
        }
    }

    # Calculate consistency score
    if ($hasContradictions) {
        $score = 0.5  # Reduced for contradictions
    }
    else {
        $score = 0.9 + ([Math]::Min(0.1, $evidenceList.Count * 0.02))  # Bonus for consistent evidence
    }

    return @{
        score = [Math]::Round([Math]::Min(1.0, $score), 4)
        details = @{
            hasContradictions = $hasContradictions
            contradictionInfo = $contradictionDetails
            distinctClaims = $grouped.Count
        }
    }
}

function Calculate-CoverageComponent {
    <#
    .SYNOPSIS
        Calculates coverage of required evidence types (0-10%).
    #>
    [CmdletBinding()]
    param(
        [array]$Evidence,
        [hashtable]$Context
    )

    $evidenceList = @($Evidence)

    # Get required evidence types from context
    $requiredTypes = if ($Context -and $Context.ContainsKey('requiredEvidenceTypes')) {
        @($Context.requiredEvidenceTypes)
    }
    else {
        @('code-example', 'api-reference')  # Default requirements
    }

    if ($requiredTypes.Count -eq 0) {
        return @{
            score = 1.0
            details = @{ note = "No specific evidence types required" }
        }
    }

    # Collect evidence types present
    $presentTypes = @()
    $evidenceList = @($Evidence)
    foreach ($item in $evidenceList) {
        if ($item.ContainsKey('evidenceType') -and -not [string]::IsNullOrWhiteSpace($item.evidenceType)) {
            $presentTypes += $item.evidenceType.ToLower()
        }
    }

    # Calculate coverage
    $coveredCount = 0
    $coverageDetails = @()

    foreach ($reqType in $requiredTypes) {
        $reqTypeLower = $reqType.ToString().ToLower()
        $isCovered = $presentTypes -contains $reqTypeLower
        if ($isCovered) { $coveredCount++ }
        
        $coverageDetails += @{
            type = $reqType
            covered = $isCovered
        }
    }

    $coverageRatio = if ($requiredTypes.Count -gt 0) { $coveredCount / $requiredTypes.Count } else { 0 }

    return @{
        score = [Math]::Round($coverageRatio, 4)
        details = @{
            requiredTypes = $requiredTypes
            presentTypes = $presentTypes | Select-Object -Unique
            coverageRatio = [Math]::Round($coverageRatio, 2)
            typeCoverage = $coverageDetails
        }
    }
}

#===============================================================================
# Answer Mode Determination
#===============================================================================

function Get-AnswerMode {
    <#
    .SYNOPSIS
        Determines the answer mode based on confidence score and evidence issues.

    .DESCRIPTION
        Maps confidence scores and evidence issues to answer modes:
        - direct: High confidence (>=0.85), no major issues
        - caveat: Medium confidence (>=0.70), minor issues
        - dispute: Multiple conflicting high-authority sources
        - abstain: Low confidence (<0.50)
        - escalate: Policy violation or boundary issue

    .PARAMETER ConfidenceScore
        The overall confidence score (0.0-1.0).

    .PARAMETER Policy
        The confidence policy hashtable with thresholds.

    .PARAMETER EvidenceIssues
        Array of identified evidence issues.

    .OUTPUTS
        System.String. The determined answer mode.

    .EXAMPLE
        $mode = Get-AnswerMode -ConfidenceScore 0.92 -Policy $policy -EvidenceIssues @()
        # Returns: "direct"

    .EXAMPLE
        $mode = Get-AnswerMode -ConfidenceScore 0.45 -Policy $policy -EvidenceIssues @($issue1)
        # Returns: "abstain"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [double]$ConfidenceScore,

        [Parameter(Mandatory = $true)]
        [hashtable]$Policy,

        [Parameter()]
        [array]$EvidenceIssues = @(),

        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] [ConfidencePolicy] Determining answer mode"
    }

    process {
        # Get thresholds from policy
        $thresholds = if ($Policy.ContainsKey('thresholds')) {
            $Policy.thresholds
        }
        else {
            $script:DefaultThresholds
        }

        # Ensure EvidenceIssues is an array for PS 5.1 compatibility
        $issuesList = @($EvidenceIssues)

        # Check for policy violations that require escalation
        $policyViolations = @($issuesList | Where-Object { 
            $_.severity -eq 'critical' -or $_.type -eq 'policy-violation' 
        })
        if ($policyViolations.Count -gt 0) {
            return 'escalate'
        }

        # Check for boundary issues
        $boundaryIssues = @($issuesList | Where-Object { $_.type -eq 'boundary-issue' })
        if ($boundaryIssues.Count -gt 0) {
            return 'escalate'
        }

        # Check for disputes (multiple conflicting sources)
        $disputeIssues = @($issuesList | Where-Object { 
            $_.type -eq 'source-conflict' -or $_.type -eq 'contradictory-evidence' 
        })
        if ($disputeIssues.Count -gt 0) {
            # Only dispute if conflicting sources are both high-authority
            $highAuthorityConflicts = @($disputeIssues | Where-Object { $_.ContainsKey('authority') -and $_.authority -ge 0.7 })
            if ($highAuthorityConflicts.Count -ge 2) {
                return 'dispute'
            }
        }

        # Determine mode based on confidence score
        if ($ConfidenceScore -ge $thresholds.direct) {
            # Check for issues that prevent direct answer
            $majorIssues = @($issuesList | Where-Object { 
                $_.severity -eq 'high' -or $_.severity -eq 'major' 
            })
            if ($majorIssues.Count -eq 0) {
                return 'direct'
            }
            else {
                return 'caveat'
            }
        }
        elseif ($ConfidenceScore -ge $thresholds.caveat) {
            return 'caveat'
        }
        elseif ($ConfidenceScore -ge $thresholds.abstain) {
            # Borderline - use caveat if we have some evidence
            return 'caveat'
        }
        else {
            return 'abstain'
        }
    }
}

#===============================================================================
# Abstention Functions
#===============================================================================

function Test-ShouldAbstain {
    <#
    .SYNOPSIS
        Determines if the system should abstain from answering.

    .DESCRIPTION
        Evaluates whether confidence is too low or evidence quality is insufficient
        to provide a reliable answer. Returns boolean indicating abstention decision.

    .PARAMETER ConfidenceScore
        The overall confidence score.

    .PARAMETER Evidence
        Array of evidence items.

    .PARAMETER Policy
        The confidence policy hashtable.

    .OUTPUTS
        System.Boolean. True if should abstain, false otherwise.

    .EXAMPLE
        $shouldAbstain = Test-ShouldAbstain -ConfidenceScore 0.45 -Evidence $evidence -Policy $policy
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [double]$ConfidenceScore,

        [Parameter(Mandatory = $true)]
        [array]$Evidence,

        [Parameter(Mandatory = $true)]
        [hashtable]$Policy,

        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] [ConfidencePolicy] Evaluating abstention criteria"
    }

    process {
        # Get abstain threshold
        $abstainThreshold = if ($Policy.ContainsKey('thresholds') -and $Policy.thresholds.ContainsKey('abstain')) {
            $Policy.thresholds.abstain
        }
        else {
            $script:DefaultThresholds.abstain
        }

        # Check minimum evidence count
        $minEvidenceCount = if ($Policy.ContainsKey('minimumEvidenceCount')) {
            $Policy.minimumEvidenceCount
        }
        else {
            1
        }

        # Ensure Evidence is array for PS 5.1 compatibility
        $evidenceList = @($Evidence)

        # Abstain if confidence below threshold
        if ($ConfidenceScore -lt $abstainThreshold) {
            return $true
        }

        # Abstain if insufficient evidence
        if ($evidenceList.Count -lt $minEvidenceCount) {
            return $true
        }

        # Abstain if all evidence is from low-trust sources
        $lowTrustCount = 0
        foreach ($item in $evidenceList) {
            $trustTier = if ($item.ContainsKey('trustTier')) { $item.trustTier } else { 'Medium' }
            if ($trustTier -eq 'Low' -or $trustTier -eq 'Quarantined') {
                $lowTrustCount++
            }
        }
        if ($lowTrustCount -eq $evidenceList.Count -and $evidenceList.Count -gt 0) {
            return $true
        }

        return $false
    }
}

function Get-AbstainDecision {
    <#
    .SYNOPSIS
        Creates an abstain decision with detailed reasoning.

    .DESCRIPTION
        Constructs a complete abstain decision object with confidence score of 0,
        abstention flag, reason, and optional alternatives.

    .PARAMETER ConfidenceScore
        The confidence score (typically 0 or very low).

    .PARAMETER Reason
        The primary reason for abstention.

    .PARAMETER Alternatives
        Optional hashtable of alternatives or suggestions.

    .OUTPUTS
        System.Collections.Hashtable. Complete abstain decision object.

    .EXAMPLE
        $decision = Get-AbstainDecision -ConfidenceScore 0.0 `
            -Reason "Insufficient evidence for reliable answer" `
            -Alternatives @{ suggestion = "Try rephrasing your query" }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [double]$ConfidenceScore = 0.0,

        [Parameter(Mandatory = $true)]
        [string]$Reason,

        [Parameter()]
        [hashtable]$Alternatives = @{},

        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] [ConfidencePolicy] Creating abstain decision"
    }

    process {
        $decision = [ordered]@{
            evaluationId    = [Guid]::NewGuid().ToString()
            correlationId   = $CorrelationId
            schemaVersion   = $script:ConfidencePolicySchemaVersion
            confidenceScore = [Math]::Max(0.0, [Math]::Min(1.0, $ConfidenceScore))
            answerMode      = 'abstain'
            shouldAbstain   = $true
            abstainReason   = $Reason
            components      = @{
                relevance   = @{ score = 0.0 }
                authority   = @{ score = 0.0 }
                consistency = @{ score = 0.0 }
                coverage    = @{ score = 0.0 }
            }
            reasoning       = @{
                PrimaryConcern = $Reason
                Explanation = "The system has determined that answering would not provide reliable information."
                Recommendations = $Alternatives
            }
            evidenceIssues  = @(@{
                type = 'abstention'
                severity = 'high'
                description = $Reason
            })
            alternatives    = $Alternatives
            evaluatedAt     = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            metadata        = @{
                createdBy = [Environment]::UserName
                createdOn = [Environment]::MachineName
            }
        }

        return $decision
    }
}

#===============================================================================
# Escalation Functions
#===============================================================================

function Get-EscalationDecision {
    <#
    .SYNOPSIS
        Creates an escalation decision for human review.

    .DESCRIPTION
        Constructs an escalation decision when the system encounters policy violations,
        boundary issues, or situations requiring human judgment.

    .PARAMETER Reason
        The reason for escalation.

    .PARAMETER EscalationTarget
        Target for escalation (e.g., "human-review", "security-team").

    .PARAMETER Context
        Additional context for the escalation.

    .OUTPUTS
        System.Collections.Hashtable. Complete escalation decision object.

    .EXAMPLE
        $escalation = Get-EscalationDecision -Reason "Potential security boundary violation" `
            -EscalationTarget "security-team" `
            -Context @{ query = $userQuery }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reason,

        [Parameter()]
        [string]$EscalationTarget = 'human-review',

        [Parameter()]
        [hashtable]$Context = @{},

        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] [ConfidencePolicy] Creating escalation decision"
    }

    process {
        $decision = [ordered]@{
            evaluationId      = [Guid]::NewGuid().ToString()
            correlationId     = $CorrelationId
            schemaVersion     = $script:ConfidencePolicySchemaVersion
            confidenceScore   = 0.0
            answerMode        = 'escalate'
            shouldAbstain     = $true
            abstainReason     = $Reason
            escalationTarget  = $EscalationTarget
            escalationContext = $Context
            components        = @{
                relevance   = @{ score = 0.0 }
                authority   = @{ score = 0.0 }
                consistency = @{ score = 0.0 }
                coverage    = @{ score = 0.0 }
            }
            reasoning         = @{
                PrimaryConcern = "Escalation required: $Reason"
                Explanation = "This query has been escalated to $EscalationTarget for human review."
                EscalationReason = $Reason
            }
            evidenceIssues    = @(@{
                type = 'escalation'
                severity = 'critical'
                description = $Reason
                target = $EscalationTarget
            })
            evaluatedAt       = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            metadata          = @{
                createdBy = [Environment]::UserName
                createdOn = [Environment]::MachineName
            }
        }

        return $decision
    }
}

#===============================================================================
# Policy Configuration
#===============================================================================

function Get-DefaultConfidencePolicy {
    <#
    .SYNOPSIS
        Returns the default confidence policy configuration.

    .DESCRIPTION
        Provides the default policy with standard thresholds and settings per
        Section 15.4 of the canonical architecture.

    .OUTPUTS
        System.Collections.Hashtable. Default confidence policy.

    .EXAMPLE
        $policy = Get-DefaultConfidencePolicy
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] [ConfidencePolicy] Returning default confidence policy"
    }

    process {
        $policy = [ordered]@{
            correlationId = $CorrelationId
            policyName = "default"
            schemaVersion = $script:ConfidencePolicySchemaVersion
            description = "Default confidence policy per Section 15.4"
            thresholds = @{
                direct  = 0.85
                caveat  = 0.70
                abstain = 0.50
            }
            minimumEvidenceCount = 1
            requireMultipleSources = $true
            minimumSourceCount = 2
            allowPartialMatch = $false
            escalateOnLowConfidence = $true
            weights = @{
                relevance   = 0.40
                authority   = 0.30
                consistency = 0.20
                coverage    = 0.10
            }
            authorityRoleWeights = $script:AuthorityRoleWeights
            trustTierWeights = $script:TrustTierWeights
            evidenceTypeWeights = $script:EvidenceTypeWeights
            createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }

        return $policy
    }
}

function Merge-ConfidencePolicy {
    <#
    .SYNOPSIS
        Merges a custom policy with default values.

    .DESCRIPTION
        Takes a custom policy and fills in any missing values with defaults.

    .PARAMETER CustomPolicy
        The custom policy hashtable to merge.

    .OUTPUTS
        System.Collections.Hashtable. Merged policy.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$CustomPolicy,

        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] [ConfidencePolicy] Merging confidence policy"
    }

    process {
        $defaults = Get-DefaultConfidencePolicy -CorrelationId $CorrelationId
        # Use ordered hashtable for consistent output - OrderedDictionary doesn't have Clone() in PS 5.1
        $merged = [ordered]@{}
        
        # Copy defaults first
        foreach ($key in $defaults.Keys) {
            $merged[$key] = $defaults[$key]
        }

        # Override with custom values
        foreach ($key in $CustomPolicy.Keys) {
            if ($key -eq 'thresholds' -and $CustomPolicy[$key] -is [hashtable]) {
                # Merge thresholds deeply - create new hashtable to avoid modifying defaults
                $mergedThresholds = [ordered]@{}
                foreach ($tk in $defaults.thresholds.Keys) {
                    $mergedThresholds[$tk] = $defaults.thresholds[$tk]
                }
                foreach ($thresholdKey in $CustomPolicy[$key].Keys) {
                    $mergedThresholds[$thresholdKey] = $CustomPolicy[$key][$thresholdKey]
                }
                $merged[$key] = $mergedThresholds
            }
            else {
                $merged[$key] = $CustomPolicy[$key]
            }
        }

        $merged.policyName = if ($CustomPolicy.ContainsKey('policyName')) {
            $CustomPolicy.policyName
        }
        else {
            "custom-merged"
        }

        $merged['correlationId'] = $CorrelationId
        return $merged
    }
}

#===============================================================================
# Helper Functions
#===============================================================================

function Calculate-OverallConfidence {
    <#
    .SYNOPSIS
        Calculates overall confidence from components.
    #>
    [CmdletBinding()]
    param([hashtable]$Components)

    $total = $Components.relevance.score +
             $Components.authority.score +
             $Components.consistency.score +
             $Components.coverage.score

    # Normalize to 0-1 range (components are already weighted)
    return [Math]::Min(1.0, [Math]::Max(0.0, $total))
}

function Get-EvidenceIssues {
    <#
    .SYNOPSIS
        Identifies issues with the evidence.
    #>
    [CmdletBinding()]
    param(
        [array]$Evidence,
        [hashtable]$Components
    )

    $issues = @()
    $evidenceList = @($Evidence)

    # Check relevance issues
    if ($Components.relevance.score -lt 0.20) {
        $issues += @{
            type = 'low-relevance'
            severity = 'high'
            description = "Evidence has low relevance to query"
            component = 'relevance'
        }
    }
    elseif ($Components.relevance.score -lt 0.30) {
        $issues += @{
            type = 'low-relevance'
            severity = 'medium'
            description = "Evidence relevance could be improved"
            component = 'relevance'
        }
    }

    # Check authority issues
    if ($Components.authority.score -lt 0.15) {
        $issues += @{
            type = 'low-authority'
            severity = 'high'
            description = "Evidence sources have low authority"
            component = 'authority'
        }
    }

    # Check consistency issues
    if ($Components.consistency.details.hasContradictions) {
        $issues += @{
            type = 'contradictory-evidence'
            severity = 'high'
            description = "Evidence contains contradictions"
            component = 'consistency'
            details = $Components.consistency.details.contradictionInfo
        }
    }

    # Check coverage issues
    if ($Components.coverage.score -lt 0.05) {
        $issues += @{
            type = 'insufficient-coverage'
            severity = 'medium'
            description = "Required evidence types not covered"
            component = 'coverage'
            details = $Components.coverage.details
        }
    }

    # Check for individual evidence issues
    $evidenceList = @($Evidence)
    foreach ($item in $evidenceList) {
        if ($item.ContainsKey('isDeprecated') -and $item.isDeprecated) {
            $issues += @{
                type = 'deprecated-evidence'
                severity = 'medium'
                description = "Evidence '$($item.sourceId)' is deprecated"
                sourceId = $item.sourceId
            }
        }

        if ($item.ContainsKey('isExperimental') -and $item.isExperimental) {
            $issues += @{
                type = 'experimental-evidence'
                severity = 'low'
                description = "Evidence '$($item.sourceId)' is experimental"
                sourceId = $item.sourceId
            }
        }
    }

    return $issues
}

function Build-ConfidenceReasoning {
    <#
    .SYNOPSIS
        Builds detailed reasoning for confidence decision.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Components,
        [double]$Score,
        [string]$AnswerMode,
        [array]$Issues
    )

    # Ensure Issues is an array for PS 5.1 compatibility
    $issuesList = @($Issues)

    $reasoning = [ordered]@{
        PrimaryConcern = ""
        ComponentSummary = ""
        Explanation = ""
        Recommendations = @()
    }

    # Build component summary
    $reasoning.ComponentSummary = "Relevance: $([Math]::Round($Components.relevance.score, 2)), " +
                                  "Authority: $([Math]::Round($Components.authority.score, 2)), " +
                                  "Consistency: $([Math]::Round($Components.consistency.score, 2)), " +
                                  "Coverage: $([Math]::Round($Components.coverage.score, 2))"

    # Build explanation based on answer mode
    switch ($AnswerMode) {
        'direct' {
            $reasoning.PrimaryConcern = "High confidence answer"
            $reasoning.Explanation = "Evidence quality is excellent with strong relevance, authority, and consistency."
            $reasoning.Recommendations = @("Proceed with direct answer")
        }
        'caveat' {
            $reasoning.PrimaryConcern = if ($issuesList.Count -gt 0) { $issuesList[0].description } else { "Moderate confidence" }
            $reasoning.Explanation = "Evidence supports answer but with limitations. Include caveats about $($issuesList.Count) identified issues."
            $reasoning.Recommendations = @(
                "Include caveats about evidence limitations",
                "Consider gathering additional evidence"
            )
        }
        'dispute' {
            $reasoning.PrimaryConcern = "Conflicting evidence from multiple sources"
            $reasoning.Explanation = "Multiple high-authority sources provide conflicting information. Surface the dispute for user awareness."
            $reasoning.Recommendations = @(
                "Present multiple viewpoints",
                "Explain the conflict and its sources"
            )
        }
        'abstain' {
            $reasoning.PrimaryConcern = if ($issuesList.Count -gt 0) { $issuesList[0].description } else { "Insufficient confidence" }
            $reasoning.Explanation = "Evidence quality is insufficient for a reliable answer. Confidence score: $([Math]::Round($Score, 2))"
            $reasoning.Recommendations = @(
                "Gather higher quality evidence",
                "Consider escalating to human expert"
            )
        }
        'escalate' {
            $reasoning.PrimaryConcern = if ($issuesList.Count -gt 0) { $issuesList[0].description } else { "Requires human review" }
            $reasoning.Explanation = "This query requires human judgment due to policy or boundary concerns."
            $reasoning.Recommendations = @(
                "Escalate to appropriate team",
                "Do not proceed with automated answer"
            )
        }
    }

    return $reasoning
}

#===============================================================================
# Export Module Members
#===============================================================================

Export-ModuleMember -Function @(
    'Test-AnswerConfidence',
    'Get-AnswerMode',
    'Test-ShouldAbstain',
    'Get-ConfidenceComponents',
    'Get-AbstainDecision',
    'Get-EscalationDecision',
    'Get-DefaultConfidencePolicy',
    'Merge-ConfidencePolicy'
)
