#requires -Version 5.1
<#
.SYNOPSIS
    Answer Evidence Policy Module for LLM Workflow Platform - Phase 5 Implementation

.DESCRIPTION
    Implements Section 15.3 Evidence Policy rules for the LLM Workflow platform.
    
    Evidence Policy Rules:
    1. Foundational claims prefer core/authoritative sources
    2. Plugin repos are examples unless marked otherwise
    3. Translation-only evidence cannot carry high confidence
    4. Conflict diagnosis should include multi-source structural evidence
    5. Public examples must not override project-local evidence in local workspace contexts

    This module provides functions to:
    - Validate evidence against policy rules
    - Calculate evidence quality scores
    - Check authority requirements
    - Filter evidence by policy
    - Identify policy violations
    - Detect translation-only evidence
    - Prioritize foundational sources
    - Enforce private-project precedence

.NOTES
    File: EvidencePolicy.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Phase: 5 - Retrieval and Answer Integrity
    Implements: Section 15.3 (Evidence Policy)

.EXAMPLE
    # Get default policy
    $policy = Get-DefaultEvidencePolicy

.EXAMPLE
    # Validate evidence against policy
    $result = Test-EvidencePolicy -Evidence $evidence -Policy $policy -Context $context

.EXAMPLE
    # Get evidence quality score
    $score = Get-EvidenceQuality -Evidence $evidence

.EXAMPLE
    # Filter evidence by policy
    $filtered = Filter-EvidenceByPolicy -Evidence $evidenceList -Policy $policy
#>

Set-StrictMode -Version Latest

#===============================================================================
# Configuration and Constants
#===============================================================================

$script:EvidencePolicySchemaVersion = 1

# Source authority tier hierarchy (higher = more authoritative)
$script:SourceAuthorityTiers = @{
    'foundational' = 100   # Core engine/runtime sources
    'authoritative' = 80   # Official docs, high-trust registries
    'exemplar' = 60        # Working code examples from reputable sources
    'community' = 40       # Community-contributed patterns
    'translation' = 20     # Translated or second-hand information
}

# Valid source classification values
$script:ValidSourceClassifications = @(
    'foundational',
    'authoritative',
    'exemplar',
    'community',
    'translation'
)

# Authority role to classification mapping
$script:AuthorityRoleToClassification = @{
    # Foundational roles
    'core-engine' = 'foundational'
    'core-runtime' = 'foundational'
    'core-blender' = 'foundational'
    # Authoritative roles
    'private-project' = 'authoritative'
    'language-binding' = 'authoritative'
    'deployment-tooling' = 'authoritative'
    'mcp-integration' = 'authoritative'
    'visual-system' = 'authoritative'
    # Exemplar roles
    'exemplar-pattern' = 'exemplar'
    'llm-workflow' = 'exemplar'
    'tooling-analyzer' = 'exemplar'
    'synth-proc' = 'exemplar'
    # Community roles
    'starter-template' = 'community'
    'curated-index' = 'community'
    'reverse-format' = 'community'
    'physics-extension' = 'community'
}

# Evidence quality weight factors
$script:QualityWeights = @{
    sourceAuthorityTier = 0.30
    provenanceCompleteness = 0.20
    recency = 0.15
    verificationStatus = 0.20
    usageSuccess = 0.15
}

# Default policy configuration
$script:DefaultEvidencePolicy = @{
    schemaVersion = $script:EvidencePolicySchemaVersion
    requireFoundationalForClaims = $true
    pluginRepoAsExampleOnly = $true
    translationOnlyMaxConfidence = 0.5
    requireMultiSourceForConflict = $true
    privateProjectOverridesPublic = $true
    minSourceAuthority = 'medium'  # 'high', 'medium', 'any'
    excludedSourceTypes = @('quarantined', 'deprecated', 'retired')
    preferredAuthorityRoles = @('core-engine', 'core-runtime', 'core-blender', 'private-project')
    maxEvidenceAgeDays = 365
    requireVerifiedEvidence = $false
    allowCommunityEvidence = $true
}

# Authority requirement mappings
$script:AuthorityRequirementMapping = @{
    'high' = @('foundational', 'authoritative')
    'medium' = @('foundational', 'authoritative', 'exemplar')
    'any' = @('foundational', 'authoritative', 'exemplar', 'community', 'translation')
}

#===============================================================================
# Core Policy Functions
#===============================================================================

function Test-EvidencePolicy {
    <#
    .SYNOPSIS
        Validates evidence against policy rules.

    .DESCRIPTION
        Validates a collection of evidence items against the specified policy rules.
        Returns a comprehensive validation result indicating compliance status,
        violations found, and overall quality assessment.

    .PARAMETER Evidence
        Array of evidence items to validate.

    .PARAMETER Policy
        Policy hashtable defining validation rules. Uses defaults if not specified.

    .PARAMETER Context
        Context hashtable with workspace and query information for contextual validation.

    .OUTPUTS
        PSCustomObject containing validation results:
        - IsValid: Boolean indicating overall compliance
        - Violations: Array of policy violations
        - Warnings: Array of warning messages
        - QualityScore: Overall evidence quality score (0.0-1.0)
        - ValidatedEvidence: Array of evidence that passed validation
        - RejectedEvidence: Array of evidence that failed validation

    .EXAMPLE
        $result = Test-EvidencePolicy -Evidence $evidence -Policy $policy -Context $context
        if (-not $result.IsValid) { Write-Warning $result.Violations }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Evidence,

        [Parameter()]
        [hashtable]$Policy = $null,

        [Parameter()]
        [hashtable]$Context = @{}
    )

    begin {
        # Use default policy if none provided
        if (-not $Policy) {
            $Policy = Get-DefaultEvidencePolicy
        }

        $violations = [System.Collections.Generic.List[hashtable]]::new()
        $warnings = [System.Collections.Generic.List[string]]::new()
        $validatedEvidence = [System.Collections.Generic.List[hashtable]]::new()
        $rejectedEvidence = [System.Collections.Generic.List[hashtable]]::new()
        $totalQualityScore = 0.0
    }

    process {
        Write-Verbose "[EvidencePolicy] Validating $($Evidence.Count) evidence items against policy"

        # Check for translation-only evidence
        $translationOnly = Test-TranslationOnlyEvidence -Evidence $Evidence
        if ($translationOnly -and $Policy.translationOnlyMaxConfidence -lt 0.7) {
            $violations.Add(@{
                rule = 'translation-only'
                severity = 'high'
                message = 'Evidence collection contains only translation sources'
                details = 'Cannot achieve high confidence with translation-only evidence'
            })
        }

        # Validate each evidence item
        foreach ($item in $Evidence) {
            $itemValid = $true
            $itemViolations = @()

            # Check excluded source types
            $itemHasSourceType = $item.ContainsKey('sourceType') -and $item.sourceType
            if ($itemHasSourceType -and $Policy.excludedSourceTypes -contains $item.sourceType) {
                $itemValid = $false
                $itemViolations += "Source type '$($item.sourceType)' is excluded by policy"
            }

            # Check source state
            $itemHasSourceState = $item.ContainsKey('sourceState') -and $item.sourceState
            if ($itemHasSourceState -and $Policy.excludedSourceTypes -contains $item.sourceState) {
                $itemValid = $false
                $itemViolations += "Source state '$($item.sourceState)' is excluded by policy"
            }

            # Check minimum authority requirement
            if ($Policy.minSourceAuthority -ne 'any') {
                $authorityValid = Test-EvidenceAuthority -Evidence $item -RequiredAuthority $Policy.minSourceAuthority
                if (-not $authorityValid) {
                    $itemValid = $false
                    $itemViolations += "Evidence does not meet minimum authority requirement '$($Policy.minSourceAuthority)'"
                }
            }

            # Check foundational requirement for claims
            $itemSupportsClaim = $item.ContainsKey('supportsClaim') -and $item.supportsClaim
            $itemClassification = if ($item.ContainsKey('classification')) { $item.classification } else { '' }
            if ($Policy.requireFoundationalForClaims -and $itemSupportsClaim -and $itemClassification -ne 'foundational') {
                $evidenceId = if ($item.ContainsKey('evidenceId')) { $item.evidenceId } else { 'unknown' }
                $warnings.Add("Evidence '$evidenceId' supports a claim but is not from foundational source")
            }

            # Calculate item quality score
            $qualityScore = Get-EvidenceQuality -Evidence $item
            $totalQualityScore += $qualityScore

            # Categorize evidence
            if ($itemValid) {
                $validatedEvidence.Add($item)
            }
            else {
                $rejectedEvidence.Add(@{
                    evidence = $item
                    violations = $itemViolations
                })
                foreach ($v in $itemViolations) {
                    $violations.Add(@{
                        rule = 'individual-evidence'
                        severity = 'medium'
                        evidenceId = $item.evidenceId
                        message = $v
                    })
                }
            }
        }

        # Check private project precedence
        $contextIsLocalWorkspace = $Context.ContainsKey('isLocalWorkspace') -and $Context.isLocalWorkspace
        if ($Policy.privateProjectOverridesPublic -and $contextIsLocalWorkspace) {
            $precedenceResult = Assert-PrivateProjectPrecedence -Evidence $Evidence -Context $Context
            if (-not $precedenceResult.compliant) {
                $violations.Add(@{
                    rule = 'private-project-precedence'
                    severity = 'high'
                    message = 'Public evidence overrides private-project evidence in local workspace'
                    details = $precedenceResult.issues
                })
            }
        }

        # Check multi-source requirement for conflicts
        $contextHasConflict = $Context.ContainsKey('hasConflict') -and $Context.hasConflict
        if ($Policy.requireMultiSourceForConflict -and $contextHasConflict) {
            $foundationalCount = ($Evidence | Where-Object { 
                $class = Get-EvidenceClassification -Evidence $_
                $class -eq 'foundational'
            }).Count
            $authoritativeCount = ($Evidence | Where-Object { 
                $class = Get-EvidenceClassification -Evidence $_
                $class -eq 'authoritative'
            }).Count

            if (($foundationalCount + $authoritativeCount) -lt 2) {
                $violations.Add(@{
                    rule = 'multi-source-conflict'
                    severity = 'medium'
                    message = 'Conflict diagnosis requires multi-source structural evidence'
                    details = "Found $foundationalCount foundational and $authoritativeCount authoritative sources"
                })
            }
        }

        # Calculate overall quality score
        $avgQualityScore = if ($Evidence.Count -gt 0) { $totalQualityScore / $Evidence.Count } else { 0.0 }

        # Determine overall validity
        $highSeverityViolations = @($violations | Where-Object { $_.severity -eq 'high' })
        $isValid = $highSeverityViolations.Count -eq 0

        # Build result
        $result = [PSCustomObject]@{
            IsValid = $isValid
            Violations = $violations.ToArray()
            Warnings = $warnings.ToArray()
            QualityScore = [Math]::Round($avgQualityScore, 3)
            ValidatedEvidence = $validatedEvidence.ToArray()
            RejectedEvidence = $rejectedEvidence.ToArray()
            ValidatedCount = $validatedEvidence.Count
            RejectedCount = $rejectedEvidence.Count
            TotalCount = $Evidence.Count
            PolicyVersion = $Policy.schemaVersion
            ValidatedAt = [DateTime]::UtcNow.ToString("o")
        }

        Write-Verbose "[EvidencePolicy] Validation complete: Valid=$isValid, Quality=$($result.QualityScore)"
        return $result
    }
}

function Get-EvidenceQuality {
    <#
    .SYNOPSIS
        Gets the evidence quality score.

    .DESCRIPTION
        Calculates a quality score (0.0-1.0) for a single evidence item based on:
        - Source authority tier (30%)
        - Provenance completeness (20%)
        - Recency (15%)
        - Verification status (20%)
        - Usage in successful answers (15%)

    .PARAMETER Evidence
        The evidence item to score.

    .OUTPUTS
        Double between 0.0 and 1.0 representing quality score.

    .EXAMPLE
        $score = Get-EvidenceQuality -Evidence $evidence
        if ($score -gt 0.8) { "High quality evidence" }
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Evidence
    )

    process {
        $score = 0.0

        # Factor 1: Source authority tier (30%)
        $classification = Get-EvidenceClassification -Evidence $Evidence
        $tierScore = $script:SourceAuthorityTiers[$classification] / 100.0
        $score += $tierScore * $script:QualityWeights.sourceAuthorityTier

        # Factor 2: Provenance completeness (20%)
        $provenanceScore = 0.0
        if ($Evidence.ContainsKey('provenance') -and $Evidence.provenance) {
            $requiredFields = @('sourceUrl', 'retrievedAt', 'sourceVersion')
            $presentFields = 0
            foreach ($field in $requiredFields) {
                if ($Evidence.provenance[$field]) { $presentFields++ }
            }
            $provenanceScore = $presentFields / $requiredFields.Count
        }
        elseif ($Evidence.ContainsKey('sourceUrl') -and $Evidence.ContainsKey('retrievedAt')) {
            $provenanceScore = 0.66  # Partial provenance
        }
        $score += $provenanceScore * $script:QualityWeights.provenanceCompleteness

        # Factor 3: Recency (15%)
        $recencyScore = 0.5  # Default neutral score
        $hasRetrievedAt = $Evidence.ContainsKey('retrievedAt') -and $Evidence.retrievedAt
        $hasLastUpdated = $Evidence.ContainsKey('lastUpdated') -and $Evidence.lastUpdated
        if ($hasRetrievedAt -or $hasLastUpdated) {
            $dateStr = if ($hasRetrievedAt) { $Evidence.retrievedAt } else { $Evidence.lastUpdated }
            try {
                $date = [DateTime]::Parse($dateStr)
                $age = ([DateTime]::UtcNow - $date).TotalDays
                if ($age -lt 30) { $recencyScore = 1.0 }
                elseif ($age -lt 90) { $recencyScore = 0.8 }
                elseif ($age -lt 180) { $recencyScore = 0.6 }
                elseif ($age -lt 365) { $recencyScore = 0.4 }
                else { $recencyScore = 0.2 }
            }
            catch {
                $recencyScore = 0.5  # Unknown recency
            }
        }
        $score += $recencyScore * $script:QualityWeights.recency

        # Factor 4: Verification status (20%)
        $verificationScore = 0.0
        if ($Evidence.ContainsKey('verificationStatus') -and $Evidence.verificationStatus) {
            switch ($Evidence.verificationStatus.ToLower()) {
                'verified' { $verificationScore = 1.0 }
                'partially-verified' { $verificationScore = 0.6 }
                'unverified' { $verificationScore = 0.3 }
                'disputed' { $verificationScore = 0.1 }
                default { $verificationScore = 0.0 }
            }
        }
        elseif ($Evidence.ContainsKey('isVerified') -and $Evidence.isVerified) {
            $verificationScore = 1.0
        }
        $score += $verificationScore * $script:QualityWeights.verificationStatus

        # Factor 5: Usage in successful answers (15%)
        $usageScore = 0.0
        if ($Evidence.ContainsKey('successfulUsageCount') -and $Evidence.successfulUsageCount) {
            if ($Evidence.successfulUsageCount -ge 10) { $usageScore = 1.0 }
            elseif ($Evidence.successfulUsageCount -ge 5) { $usageScore = 0.8 }
            elseif ($Evidence.successfulUsageCount -ge 2) { $usageScore = 0.6 }
            else { $usageScore = 0.4 }
        }
        elseif ($Evidence.ContainsKey('usageCount') -and $Evidence.usageCount) {
            $successRate = if ($Evidence.ContainsKey('successRate') -and $Evidence.successRate) { $Evidence.successRate } else { 0.5 }
            $usageScore = [Math]::Min(1.0, ($Evidence.usageCount / 10.0) * $successRate)
        }
        $score += $usageScore * $script:QualityWeights.usageSuccess

        return [Math]::Round([Math]::Max(0.0, [Math]::Min(1.0, $score)), 3)
    }
}

function Test-EvidenceAuthority {
    <#
    .SYNOPSIS
        Checks if evidence meets authority requirements.

    .DESCRIPTION
        Validates that an evidence item meets the specified authority requirement.
        Authority levels:
        - 'high': Requires foundational or authoritative sources
        - 'medium': Requires foundational, authoritative, or exemplar sources
        - 'any': Any source classification is acceptable

    .PARAMETER Evidence
        The evidence item to check.

    .PARAMETER RequiredAuthority
        The required authority level: 'high', 'medium', or 'any'.

    .OUTPUTS
        Boolean indicating whether the evidence meets the authority requirement.

    .EXAMPLE
        $meetsAuthority = Test-EvidenceAuthority -Evidence $evidence -RequiredAuthority 'high'
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Evidence,

        [Parameter(Mandatory = $true)]
        [ValidateSet('high', 'medium', 'any')]
        [string]$RequiredAuthority
    )

    process {
        $classification = Get-EvidenceClassification -Evidence $Evidence
        $allowedClassifications = $script:AuthorityRequirementMapping[$RequiredAuthority]

        return $allowedClassifications -contains $classification
    }
}

function Filter-EvidenceByPolicy {
    <#
    .SYNOPSIS
        Filters evidence by policy rules.

    .DESCRIPTION
        Filters an array of evidence items based on policy rules,
        returning only evidence that meets all policy requirements.
        Optionally returns excluded evidence with reasons.

    .PARAMETER Evidence
        Array of evidence items to filter.

    .PARAMETER Policy
        Policy hashtable defining filter rules.

    .PARAMETER IncludeExcluded
        If specified, also returns excluded evidence with exclusion reasons.

    .OUTPUTS
        Array of evidence items that pass policy filtering.
        If IncludeExcluded is specified, returns a hashtable with 'Included' and 'Excluded' keys.

    .EXAMPLE
        $filtered = Filter-EvidenceByPolicy -Evidence $evidence -Policy $policy

    .EXAMPLE
        $result = Filter-EvidenceByPolicy -Evidence $evidence -Policy $policy -IncludeExcluded
        $included = $result.Included
        $excluded = $result.Excluded
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Evidence,

        [Parameter()]
        [hashtable]$Policy = $null,

        [Parameter()]
        [switch]$IncludeExcluded
    )

    begin {
        if (-not $Policy) {
            $Policy = Get-DefaultEvidencePolicy
        }

        $included = [System.Collections.Generic.List[hashtable]]::new()
        $excluded = [System.Collections.Generic.List[hashtable]]::new()
    }

    process {
        Write-Verbose "[EvidencePolicy] Filtering $($Evidence.Count) evidence items"

        foreach ($item in $Evidence) {
            $excludedReasons = @()

            # Check excluded source types
            $hasSourceType = $item.ContainsKey('sourceType') -and $item.sourceType
            if ($hasSourceType -and $Policy.excludedSourceTypes -contains $item.sourceType) {
                $excludedReasons += "Source type '$($item.sourceType)' excluded by policy"
            }

            # Check excluded source states
            $hasSourceState = $item.ContainsKey('sourceState') -and $item.sourceState
            if ($hasSourceState -and $Policy.excludedSourceTypes -contains $item.sourceState) {
                $excludedReasons += "Source state '$($item.sourceState)' excluded by policy"
            }

            # Check minimum authority
            if ($Policy.minSourceAuthority -ne 'any') {
                $authorityValid = Test-EvidenceAuthority -Evidence $item -RequiredAuthority $Policy.minSourceAuthority
                if (-not $authorityValid) {
                    $excludedReasons += "Does not meet minimum authority '$($Policy.minSourceAuthority)'"
                }
            }

            # Check age limit
            if ($Policy.maxEvidenceAgeDays) {
                $hasRetrievedAt = $item.ContainsKey('retrievedAt') -and $item.retrievedAt
                $hasLastUpdated = $item.ContainsKey('lastUpdated') -and $item.lastUpdated
                if ($hasRetrievedAt -or $hasLastUpdated) {
                    $dateStr = if ($hasRetrievedAt) { $item.retrievedAt } else { $item.lastUpdated }
                    try {
                        $date = [DateTime]::Parse($dateStr)
                        $age = ([DateTime]::UtcNow - $date).TotalDays
                        if ($age -gt $Policy.maxEvidenceAgeDays) {
                            $excludedReasons += "Evidence age ($([Math]::Round($age,0)) days) exceeds maximum ($($Policy.maxEvidenceAgeDays))"
                        }
                    }
                    catch {
                        Write-Verbose "[EvidencePolicy] Could not parse date: $dateStr"
                    }
                }
            }

            # Check verification requirement
            if ($Policy.requireVerifiedEvidence) {
                $verificationStatus = if ($item.ContainsKey('verificationStatus')) { $item.verificationStatus } else { '' }
                $isVerifiedFlag = $item.ContainsKey('isVerified') -and $item.isVerified
                $isVerified = ($verificationStatus -eq 'verified') -or $isVerifiedFlag
                if (-not $isVerified) {
                    $excludedReasons += "Verification required but evidence is not verified"
                }
            }

            # Categorize
            if ($excludedReasons.Count -eq 0) {
                $included.Add($item)
            }
            else {
                $excluded.Add(@{
                    evidence = $item
                    reasons = $excludedReasons
                })
            }
        }

        Write-Verbose "[EvidencePolicy] Filtered: $($included.Count) included, $($excluded.Count) excluded"

        if ($IncludeExcluded) {
            return @{
                Included = $included.ToArray()
                Excluded = $excluded.ToArray()
                IncludedCount = $included.Count
                ExcludedCount = $excluded.Count
                TotalCount = $Evidence.Count
            }
        }

        return $included.ToArray()
    }
}

function Get-EvidencePolicyViolations {
    <#
    .SYNOPSIS
        Gets policy violations for evidence collection.

    .DESCRIPTION
        Analyzes evidence against policy and returns detailed violation information.
        Does not filter evidence - only identifies violations.

    .PARAMETER Evidence
        Array of evidence items to analyze.

    .PARAMETER Policy
        Policy hashtable defining validation rules.

    .PARAMETER Context
        Context hashtable with workspace and query information.

    .OUTPUTS
        Array of violation hashtables with rule, severity, message, and details.

    .EXAMPLE
        $violations = Get-EvidencePolicyViolations -Evidence $evidence -Policy $policy -Context $context
        foreach ($v in $violations) { Write-Warning "$($v.rule): $($v.message)" }
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Evidence,

        [Parameter()]
        [hashtable]$Policy = $null,

        [Parameter()]
        [hashtable]$Context = @{}
    )

    begin {
        if (-not $Policy) {
            $Policy = Get-DefaultEvidencePolicy
        }

        $violations = [System.Collections.Generic.List[hashtable]]::new()
    }

    process {
        # Check translation-only
        $translationOnly = Test-TranslationOnlyEvidence -Evidence $Evidence
        if ($translationOnly) {
            $violations.Add(@{
                rule = 'translation-only'
                severity = 'high'
                message = 'Evidence collection contains only translation sources'
                recommendation = 'Add foundational or authoritative sources to increase confidence'
            })
        }

        # Check foundational for claims
        if ($Policy.requireFoundationalForClaims) {
            $foundationalItems = @($Evidence | Where-Object { 
                (Get-EvidenceClassification -Evidence $_) -eq 'foundational' 
            })

            if ($foundationalItems.Count -eq 0) {
                $violations.Add(@{
                    rule = 'foundational-claims'
                    severity = 'medium'
                    message = 'No foundational sources for claims'
                    recommendation = 'Add core engine/runtime sources for foundational claims'
                })
            }
        }

        # Check plugin repo as example only
        if ($Policy.pluginRepoAsExampleOnly) {
            $pluginRepos = @($Evidence | Where-Object { 
                $hasType = $_.ContainsKey('sourceType') -and $_.sourceType
                $hasType -and $_.sourceType -eq 'plugin-repo' -and (Get-EvidenceClassification -Evidence $_) -ne 'exemplar'
            })

            foreach ($repo in $pluginRepos) {
                $evId = if ($repo.ContainsKey('evidenceId')) { $repo.evidenceId } else { 'unknown' }
                $violations.Add(@{
                    rule = 'plugin-repo-classification'
                    severity = 'low'
                    message = "Plugin repo '$evId' not classified as exemplar"
                    evidenceId = $evId
                    recommendation = 'Classify plugin repos as exemplar unless explicitly marked otherwise'
                })
            }
        }

        # Check multi-source for conflict
        $contextHasConflict = $Context.ContainsKey('hasConflict') -and $Context.hasConflict
        if ($Policy.requireMultiSourceForConflict -and $contextHasConflict) {
            $highAuthorityItems = @($Evidence | Where-Object { 
                $class = Get-EvidenceClassification -Evidence $_
                $class -eq 'foundational' -or $class -eq 'authoritative'
            })

            if ($highAuthorityItems.Count -lt 2) {
                $violations.Add(@{
                    rule = 'multi-source-conflict'
                    severity = 'high'
                    message = 'Conflict diagnosis requires multi-source structural evidence'
                    details = "Only $($highAuthorityItems.Count) high-authority source(s) found"
                    recommendation = 'Include evidence from multiple foundational or authoritative sources'
                })
            }
        }

        # Check private project precedence
        $contextIsLocalWorkspace = $Context.ContainsKey('isLocalWorkspace') -and $Context.isLocalWorkspace
        if ($Policy.privateProjectOverridesPublic -and $contextIsLocalWorkspace) {
            $precedenceResult = Assert-PrivateProjectPrecedence -Evidence $Evidence -Context $Context
            if (-not $precedenceResult.compliant) {
                foreach ($issue in $precedenceResult.issues) {
                    $violations.Add(@{
                        rule = 'private-project-precedence'
                        severity = 'medium'
                        message = $issue
                        recommendation = 'Prioritize private-project evidence over public examples in local workspace'
                    })
                }
            }
        }

        # Check confidence cap for translation-only
        $translationHighConfidence = @($Evidence | Where-Object { 
            $hasConfidence = $_.ContainsKey('confidence') -and $_.confidence
            (Get-EvidenceClassification -Evidence $_) -eq 'translation' -and 
            $hasConfidence -and $_.confidence -gt $Policy.translationOnlyMaxConfidence
        })

        foreach ($trans in $translationHighConfidence) {
            $evId = if ($trans.ContainsKey('evidenceId')) { $trans.evidenceId } else { 'unknown' }
            $confidence = $trans.confidence
            $violations.Add(@{
                rule = 'translation-confidence-cap'
                severity = 'medium'
                message = "Translation source '$evId' has confidence $confidence exceeding cap ($($Policy.translationOnlyMaxConfidence))"
                evidenceId = $evId
                recommendation = 'Reduce confidence for translation-only evidence'
            })
        }

        return $violations.ToArray()
    }
}

function Test-TranslationOnlyEvidence {
    <#
    .SYNOPSIS
        Checks if evidence collection is translation-only.

    .DESCRIPTION
        Determines if the evidence collection contains only translation sources
        (no foundational, authoritative, or exemplar sources).

    .PARAMETER Evidence
        Array of evidence items to check.

    .OUTPUTS
        Boolean indicating whether evidence is translation-only.

    .EXAMPLE
        if (Test-TranslationOnlyEvidence -Evidence $evidence) { 
            Write-Warning "Translation-only evidence cannot carry high confidence" 
        }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Evidence
    )

    process {
        if ($Evidence.Count -eq 0) {
            return $false
        }

        foreach ($item in $Evidence) {
            $classification = Get-EvidenceClassification -Evidence $item
            if ($classification -ne 'translation') {
                return $false
            }
        }

        return $true
    }
}

function Sort-BySourceAuthority {
    <#
    .SYNOPSIS
        Prioritizes foundational sources in evidence collection.

    .DESCRIPTION
        Sorts evidence by source authority tier (foundational first, then authoritative,
        exemplar, community, translation). Within each tier, sorts by quality score.

    .PARAMETER Evidence
        Array of evidence items to sort.

    .PARAMETER Descending
        If specified, sorts in descending order (highest authority first).

    .OUTPUTS
        Array of evidence items sorted by source authority.

    .EXAMPLE
        $sorted = Sort-BySourceAuthority -Evidence $evidence
        $topEvidence = $sorted | Select-Object -First 5
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Evidence,

        [Parameter()]
        [switch]$Descending = $true
    )

    process {
        # Create ordered list of classifications
        $classificationOrder = @('foundational', 'authoritative', 'exemplar', 'community', 'translation')

        $scoredEvidence = $Evidence | ForEach-Object {
            $classification = Get-EvidenceClassification -Evidence $_
            $qualityScore = Get-EvidenceQuality -Evidence $_
            $authorityRank = $classificationOrder.IndexOf($classification)

            [PSCustomObject]@{
                Evidence = $_
                AuthorityRank = $authorityRank
                QualityScore = $qualityScore
            }
        }

        $sorted = if ($Descending) {
            $scoredEvidence | Sort-Object -Property AuthorityRank, QualityScore -Descending
        }
        else {
            $scoredEvidence | Sort-Object -Property AuthorityRank, QualityScore
        }

        return $sorted | ForEach-Object { $_.Evidence }
    }
}

function Assert-PrivateProjectPrecedence {
    <#
    .SYNOPSIS
        Asserts that private-project evidence takes precedence in local workspace.

    .DESCRIPTION
        Validates that private-project evidence is not overridden by public examples
        in local workspace contexts. Returns compliance status and any issues found.

    .PARAMETER Evidence
        Array of evidence items to check.

    .PARAMETER Context
        Context hashtable with workspace information including isLocalWorkspace flag.

    .OUTPUTS
        PSCustomObject with compliant status and issues array.

    .EXAMPLE
        $result = Assert-PrivateProjectPrecedence -Evidence $evidence -Context @{ isLocalWorkspace = $true }
        if (-not $result.compliant) { Write-Warning $result.issues }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Evidence,

        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    process {
        $issues = [System.Collections.Generic.List[string]]::new()

        # Only check in local workspace context
        $contextIsLocal = $Context.ContainsKey('isLocalWorkspace') -and $Context.isLocalWorkspace
        if (-not $contextIsLocal) {
            return [PSCustomObject]@{
                compliant = $true
                issues = @()
                message = 'Not in local workspace context - precedence check not applicable'
            }
        }

        # Find private-project evidence
        $privateProjectEvidence = @($Evidence | Where-Object { 
            $hasAuthRole = $_.ContainsKey('authorityRole') -and $_.authorityRole
            $hasClass = $_.ContainsKey('classification') -and $_.classification
            ($hasAuthRole -and $_.authorityRole -eq 'private-project') -or 
            ($hasClass -and $_.classification -eq 'private-project')
        })

        if ($privateProjectEvidence.Count -eq 0) {
            return [PSCustomObject]@{
                compliant = $true
                issues = @()
                message = 'No private-project evidence in collection'
            }
        }

        # Find public examples that might override private-project evidence
        $publicExamples = @($Evidence | Where-Object { 
            $hasSourceType = $_.ContainsKey('sourceType') -and $_.sourceType
            $hasClass = $_.ContainsKey('classification') -and $_.classification
            $hasAuthRole = $_.ContainsKey('authorityRole') -and $_.authorityRole
            
            ($hasSourceType -and $_.sourceType -eq 'public-example') -or 
            (($hasClass -and $_.classification -in @('exemplar', 'community')) -and 
             (-not $hasAuthRole -or $_.authorityRole -ne 'private-project'))
        })

        # Check if any public example is ranked higher than private-project evidence
        # Only compare if both have rank property
        $privateWithRank = @($privateProjectEvidence | Where-Object { $_.ContainsKey('rank') })
        $publicWithRank = @($publicExamples | Where-Object { $_.ContainsKey('rank') })
        
        if ($privateWithRank.Count -gt 0 -and $publicWithRank.Count -gt 0) {
            $privateMaxRank = ($privateWithRank | Measure-Object -Property rank -Maximum).Maximum
            $publicMinRank = ($publicWithRank | Measure-Object -Property rank -Minimum).Minimum

            if ($publicMinRank -lt $privateMaxRank) {
                $overridingPublic = $publicWithRank | Where-Object { $_.rank -lt $privateMaxRank }
                foreach ($pub in $overridingPublic) {
                    $pubId = if ($pub.ContainsKey('evidenceId')) { $pub.evidenceId } else { 'unknown' }
                    $issues.Add("Public example '$pubId' may override private-project evidence")
                }
            }
        }

        return [PSCustomObject]@{
            compliant = $issues.Count -eq 0
            issues = $issues.ToArray()
            privateProjectCount = $privateProjectEvidence.Count
            publicExampleCount = $publicExamples.Count
        }
    }
}

function Get-DefaultEvidencePolicy {
    <#
    .SYNOPSIS
        Gets the default evidence policy.

    .DESCRIPTION
        Returns the default evidence policy configuration with all standard rules.
        This policy can be customized using New-EvidencePolicy.

    .OUTPUTS
        Hashtable containing default policy configuration.

    .EXAMPLE
        $policy = Get-DefaultEvidencePolicy
        $policy.requireFoundationalForClaims = $false  # Modify as needed
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    process {
        # Return a deep copy to prevent modification of defaults
        $defaultPolicy = $script:DefaultEvidencePolicy.Clone()
        $defaultPolicy.excludedSourceTypes = $script:DefaultEvidencePolicy.excludedSourceTypes.Clone()
        $defaultPolicy.preferredAuthorityRoles = $script:DefaultEvidencePolicy.preferredAuthorityRoles.Clone()

        return $defaultPolicy
    }
}

function New-EvidencePolicy {
    <#
    .SYNOPSIS
        Creates a custom evidence policy.

    .DESCRIPTION
        Creates a new evidence policy by merging custom rules with defaults.
        Only specified rules are overridden; unspecified rules use defaults.

    .PARAMETER Rules
        Hashtable of custom policy rules to apply.

    .PARAMETER BasePolicy
        Base policy to extend. Uses default policy if not specified.

    .OUTPUTS
        Hashtable containing the custom policy configuration.

    .EXAMPLE
        $customRules = @{
            requireFoundationalForClaims = $false
            minSourceAuthority = 'high'
        }
        $policy = New-EvidencePolicy -Rules $customRules

    .EXAMPLE
        $strictPolicy = New-EvidencePolicy -Rules @{
            requireVerifiedEvidence = $true
            maxEvidenceAgeDays = 90
        }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Rules,

        [Parameter()]
        [hashtable]$BasePolicy = $null
    )

    process {
        # Start with base policy
        if (-not $BasePolicy) {
            $BasePolicy = Get-DefaultEvidencePolicy
        }

        # Create new policy by cloning base
        $newPolicy = $BasePolicy.Clone()

        # Merge custom rules
        foreach ($key in $Rules.Keys) {
            $newPolicy[$key] = $Rules[$key]
        }

        # Ensure schema version is set
        if (-not $newPolicy.schemaVersion) {
            $newPolicy.schemaVersion = $script:EvidencePolicySchemaVersion
        }

        # Ensure arrays are cloned
        if ($Rules.ContainsKey('excludedSourceTypes')) {
            $newPolicy.excludedSourceTypes = $Rules.excludedSourceTypes.Clone()
        }
        if ($Rules.ContainsKey('preferredAuthorityRoles')) {
            $newPolicy.preferredAuthorityRoles = $Rules.preferredAuthorityRoles.Clone()
        }

        Write-Verbose "[EvidencePolicy] Created custom policy with $($Rules.Count) custom rules"
        return $newPolicy
    }
}

#===============================================================================
# Helper Functions
#===============================================================================

function Get-EvidenceClassification {
    <#
    .SYNOPSIS
        Gets the classification for an evidence item.

    .DESCRIPTION
        Determines the source classification (foundational, authoritative, exemplar,
        community, translation) based on evidence properties.

    .PARAMETER Evidence
        The evidence item to classify.

    .OUTPUTS
        String classification value.

    .EXAMPLE
        $classification = Get-EvidenceClassification -Evidence $evidence
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Evidence
    )

    process {
        # Check explicit classification first
        $hasClassification = $Evidence.ContainsKey('classification') -and $Evidence.classification
        if ($hasClassification -and $script:ValidSourceClassifications -contains $Evidence.classification) {
            return $Evidence.classification
        }

        # Map from authority role
        $hasAuthorityRole = $Evidence.ContainsKey('authorityRole') -and $Evidence.authorityRole
        if ($hasAuthorityRole -and $script:AuthorityRoleToClassification.ContainsKey($Evidence.authorityRole)) {
            return $script:AuthorityRoleToClassification[$Evidence.authorityRole]
        }

        # Map from source type
        $sourceType = if ($Evidence.ContainsKey('sourceType')) { $Evidence.sourceType } else { '' }
        switch ($sourceType) {
            'core-engine' { return 'foundational' }
            'core-runtime' { return 'foundational' }
            'official-doc' { return 'authoritative' }
            'high-trust-registry' { return 'authoritative' }
            'verified-example' { return 'exemplar' }
            'community-pattern' { return 'community' }
            'translation' { return 'translation' }
            'second-hand' { return 'translation' }
        }

        # Default to community if unknown
        return 'community'
    }
}

function Test-EvidenceIsFoundational {
    <#
    .SYNOPSIS
        Tests if evidence is from a foundational source.

    .DESCRIPTION
        Determines if an evidence item is classified as foundational
        (core engine/runtime sources).

    .PARAMETER Evidence
        The evidence item to test.

    .OUTPUTS
        Boolean indicating if evidence is foundational.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Evidence
    )

    process {
        return (Get-EvidenceClassification -Evidence $Evidence) -eq 'foundational'
    }
}

function Test-EvidenceIsAuthoritative {
    <#
    .SYNOPSIS
        Tests if evidence is from an authoritative source.

    .DESCRIPTION
        Determines if an evidence item is classified as authoritative
        (official docs, high-trust registries).

    .PARAMETER Evidence
        The evidence item to test.

    .OUTPUTS
        Boolean indicating if evidence is authoritative.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Evidence
    )

    process {
        return (Get-EvidenceClassification -Evidence $Evidence) -eq 'authoritative'
    }
}

function Get-EvidenceAuthorityTier {
    <#
    .SYNOPSIS
        Gets the authority tier score for evidence.

    .DESCRIPTION
        Returns the numeric authority tier score (0-100) for an evidence item.

    .PARAMETER Evidence
        The evidence item to score.

    .OUTPUTS
        Integer authority tier score.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Evidence
    )

    process {
        $classification = Get-EvidenceClassification -Evidence $Evidence
        return $script:SourceAuthorityTiers[$classification]
    }
}

function Export-EvidencePolicy {
    <#
    .SYNOPSIS
        Exports an evidence policy to JSON.

    .DESCRIPTION
        Serializes an evidence policy to JSON for storage or sharing.

    .PARAMETER Policy
        The policy to export.

    .PARAMETER Path
        The file path to save to.

    .OUTPUTS
        String path to the exported file.

    .EXAMPLE
        Export-EvidencePolicy -Policy $policy -Path "policy.json"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Policy,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    process {
        $export = @{
            schemaVersion = $script:EvidencePolicySchemaVersion
            exportedAt = [DateTime]::UtcNow.ToString("o")
            policy = $Policy
        }

        $dir = Split-Path -Parent $Path
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $export | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding UTF8
        Write-Verbose "[EvidencePolicy] Exported policy to: $Path"
        return $Path
    }
}

function Import-EvidencePolicy {
    <#
    .SYNOPSIS
        Imports an evidence policy from JSON.

    .DESCRIPTION
        Loads an evidence policy from a JSON file.

    .PARAMETER Path
        The file path to load from.

    .OUTPUTS
        Hashtable containing the policy configuration.

    .EXAMPLE
        $policy = Import-EvidencePolicy -Path "policy.json"
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    process {
        if (-not (Test-Path $Path)) {
            throw "Policy file not found: $Path"
        }

        $content = Get-Content $Path -Raw | ConvertFrom-Json -AsHashtable
        $policy = $content.policy

        if (-not $policy) {
            # Try loading as raw policy
            $policy = $content
        }

        Write-Verbose "[EvidencePolicy] Imported policy from: $Path"
        return $policy
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Test-EvidencePolicy',
    'Get-EvidenceQuality',
    'Test-EvidenceAuthority',
    'Filter-EvidenceByPolicy',
    'Get-EvidencePolicyViolations',
    'Test-TranslationOnlyEvidence',
    'Sort-BySourceAuthority',
    'Assert-PrivateProjectPrecedence',
    'Get-DefaultEvidencePolicy',
    'New-EvidencePolicy',
    'Get-EvidenceClassification',
    'Test-EvidenceIsFoundational',
    'Test-EvidenceIsAuthoritative',
    'Get-EvidenceAuthorityTier',
    'Export-EvidencePolicy',
    'Import-EvidencePolicy'
)
