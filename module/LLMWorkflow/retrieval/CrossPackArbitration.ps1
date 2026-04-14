<#
.SYNOPSIS
    Cross-Pack Arbitration Module for LLM Workflow Platform - Phase 5 Implementation

.DESCRIPTION
    Implements Section 14.3 Cross-Pack Arbitration and Section 13.2 Dispute Sets.
    Handles queries that span multiple domain packs (rpgmaker-mz, godot-engine, blender-engine)
    with proper authority scoring, conflict resolution, and answer labeling.

.NOTES
    Author: LLM Workflow Platform
    Version: 1.0.0
    Date: 2026-04-12
    Implements: Section 14.3 (Cross-Pack Arbitration), Section 13.2 (Dispute Sets)

.ARBITRATION RULES
    1. Prefer domain-specific authoritative pack over generic pack
    2. Prefer private-project pack when query is project-local
    3. Mark cross-pack answers clearly
    4. Do not let generic dev/reference packs drown out domain-specific evidence
#>

#requires -Version 5.1
Set-StrictMode -Version Latest

$script:TelemetryTraceLog = [System.Collections.ArrayList]::new()

#region Configuration Data

# Domain-specific keywords for pack relevance scoring
$script:DomainKeywords = @{
    'rpgmaker-mz' = @(
        'rpg maker', 'rmmz', 'plugin', 'battle system', 'map', 'event', 
        'notetag', 'plugin command', 'rpgmaker', 'mv compatible', 'pixi',
        'window_', 'scene_', 'sprite_', 'game_', 'actor', 'enemy', 'item',
        'typescript', 'javascript', 'js plugin'
    )
    'godot-engine' = @(
        'godot', 'gdscript', 'node', 'scene', 'signal', 'gdextension',
        'autoload', 'singleton', 'tscn', 'tres', 'export var', 'onready',
        'process', 'physics_process', 'ready', 'tree', 'canvas', 'viewport',
        'rust', 'gdext', 'godot-cpp', 'c++', 'gdnative', 'steam'
    )
    'blender-engine' = @(
        'blender', 'bpy', 'addon', 'geometry nodes', 'shader', 'material',
        'mesh', 'armature', 'bone', 'rigging', 'animation', 'render',
        'cycles', 'eevee', 'uv', 'texture', 'procedural', 'python',
        'synthetic data', 'blenderproc', 'gis', 'mmd'
    )
}

# Authority role scores (higher = more authoritative)
$script:AuthorityRoleScores = @{
    'core-runtime' = 100
    'core-engine' = 100
    'core-blender' = 100
    'private-project' = 90
    'language-binding' = 70
    'deployment-tooling' = 65
    'mcp-integration' = 60
    'visual-system' = 55
    'exemplar-pattern' = 50
    'llm-workflow' = 45
    'tooling-analyzer' = 45
    'synth-proc' = 50
    'starter-template' = 40
    'curated-index' = 35
    'reverse-format' = 30
    'physics-extension' = 55
}

# Project-local query indicators
$script:ProjectLocalIndicators = @(
    'my project', 'my code', 'my plugin', 'my scene', 'my script',
    'local file', 'this project', 'current project', 'our project',
    'in my game', 'in our game', 'my addon', 'my mod'
)

# Generic pack identifiers (lower priority)
$script:GenericPackPatterns = @(
    'reference', 'generic', 'common', 'standard', 'base-',
    '_core_', '-core-', 'dev-guide', 'best-practice'
)

# Cross-pack trigger phrases (indicates comparison or pipeline query)
$script:CrossPackTriggers = @(
    'compare', 'vs', 'versus', 'difference between', 'similar to',
    'like in', 'export from', 'import to', 'pipeline', 'workflow',
    'transfer', 'convert', 'migrate'
)

#endregion

#region Core Arbitration Functions (Section 14.3)

<#
.SYNOPSIS
    Main cross-pack arbitration logic for multi-pack queries.

.DESCRIPTION
    Determines the optimal pack order and handling strategy for queries that may
    span multiple domain packs. Implements Section 14.3 arbitration rules:
    - Prefer domain-specific authoritative pack over generic pack
    - Prefer private-project pack when query is project-local
    - Mark cross-pack answers clearly
    - Prevent generic dev/reference packs from drowning domain-specific evidence

.PARAMETER Query
    The user query to arbitrate.

.PARAMETER Packs
    Array of pack manifests to consider for arbitration.

.PARAMETER WorkspaceContext
    Current workspace context for visibility and access checks.

.PARAMETER RetrievalProfile
    Optional retrieval profile name to guide pack selection.

.EXAMPLE
    $result = Invoke-CrossPackArbitration -Query "How do I create a plugin?" `
        -Packs $packManifests -WorkspaceContext $workspace

.OUTPUTS
    PSCustomObject containing arbitration result with packOrder, primaryPack, 
    isCrossPack flag, and requiresLabeling flag.
#>
function Invoke-CrossPackArbitration {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $true)]
        [array]$Packs,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$WorkspaceContext,

        [Parameter()]
        [string]$RetrievalProfile = '',

        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration Invoke-CrossPackArbitration"
        $arbitrationId = [Guid]::NewGuid().ToString()
        $traceAttributes = @{
            Query = $Query
            RetrievalProfile = $RetrievalProfile
        }
        [void](Write-FunctionTelemetry -CorrelationId $CorrelationId -FunctionName 'Invoke-CrossPackArbitration' -Attributes $traceAttributes)
        Write-Verbose "Starting cross-pack arbitration [$arbitrationId] for query: $Query"
    }

    process {
        # Test if this is a cross-pack query
        $isCrossPack = Test-CrossPackAnswer -Query $Query -Packs $Packs
        
        # Get ordered pack list with scores
        $packOrder = Get-ArbitratedPackOrder -Query $Query -Packs $Packs `
            -WorkspaceContext $WorkspaceContext -RetrievalProfile $RetrievalProfile

        # Determine primary pack (highest scored)
        $primaryPack = if ($packOrder.Count -gt 0) { $packOrder[0].packId } else { $null }

        # Determine if labeling is required
        $requiresLabeling = $isCrossPack -or ($packOrder.Count -gt 1 -and $packOrder[0].score - $packOrder[1].score -lt 20)

        # Check for project-local context
        $isProjectLocal = Test-ProjectLocalContext -Query $Query

        # Resolve any conflicts between packs
        $disputes = Resolve-PackConflicts -Query $Query -PackOrder $packOrder -Packs $Packs

        # Create result object
        $result = New-PackArbitrationResult `
            -ArbitrationId $arbitrationId `
            -Query $Query `
            -PackOrder $packOrder `
            -PrimaryPack $primaryPack `
            -IsCrossPack $isCrossPack `
            -RequiresLabeling $requiresLabeling `
            -Disputes $disputes `
            -IsProjectLocal $isProjectLocal

        return $result
    }
}

<#
.SYNOPSIS
    Scores pack relevance to a given query.

.DESCRIPTION
    Calculates a relevance score (0.0 to 1.0) indicating how well a pack matches
    the query based on domain keywords, authority roles, and retrieval profiles.

.PARAMETER Query
    The query to score against.

.PARAMETER PackManifest
    The pack manifest to score.

.PARAMETER RetrievalProfile
    Optional retrieval profile for context-aware scoring.

.EXAMPLE
    $score = Test-PackRelevance -Query "GDScript signals" -PackManifest $godotPack

.OUTPUTS
    Double between 0.0 and 1.0 representing relevance score.
#>
function Test-PackRelevance {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $true)]
        [hashtable]$PackManifest,

        [Parameter()]
        [string]$RetrievalProfile = '',
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration Test-PackRelevance"
    }

    process {
        $score = 0.0
        $packId = $PackManifest.packId
        $queryLower = $Query.ToLower()

        # 1. Domain keyword matching (0-40 points)
        if ($script:DomainKeywords.ContainsKey($packId)) {
            $keywords = $script:DomainKeywords[$packId]
            $matches = 0
            foreach ($keyword in $keywords) {
                if ($queryLower.Contains($keyword.ToLower())) {
                    $matches++
                }
            }
            $score += [Math]::Min(40, $matches * 10)
        }

        # 2. Authority role scoring (0-30 points)
        if ($PackManifest.collections) {
            $maxAuthority = 0
            foreach ($collection in $PackManifest.collections.Values) {
                if ($collection.authorityRole -and $script:AuthorityRoleScores.ContainsKey($collection.authorityRole)) {
                    $roleScore = $script:AuthorityRoleScores[$collection.authorityRole]
                    if ($roleScore -gt $maxAuthority) {
                        $maxAuthority = $roleScore
                    }
                }
            }
            $score += ($maxAuthority / 100) * 30
        }

        # 3. Retrieval profile match (0-20 points)
        if ($RetrievalProfile -and $PackManifest.retrievalProfiles) {
            if ($PackManifest.retrievalProfiles.ContainsKey($RetrievalProfile)) {
                $score += 20
            }
        }

        # 4. Generic pack penalty (reduces score for generic packs)
        foreach ($pattern in $script:GenericPackPatterns) {
            if ($packId -match $pattern) {
                $score -= 15
                break
            }
        }

        # Normalize to 0.0-1.0 range
        $normalizedScore = [Math]::Max(0.0, [Math]::Min(1.0, $score / 100))
        return [double]$normalizedScore
    }
}

<#
.SYNOPSIS
    Returns ordered pack list for query based on arbitration rules.

.DESCRIPTION
    Generates a priority-ordered list of packs with relevance scores,
    applying Section 14.3 arbitration rules for domain specificity and
    project-local context.

.PARAMETER Query
    The user query.

.PARAMETER Packs
    Array of pack manifests to order.

.PARAMETER WorkspaceContext
    Current workspace context.

.PARAMETER RetrievalProfile
    Optional retrieval profile.

.EXAMPLE
    $orderedPacks = Get-ArbitratedPackOrder -Query "GDScript node" -Packs $packs

.OUTPUTS
    Array of PSCustomObject with packId, score, and reason properties.
#>
function Get-ArbitratedPackOrder {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $true)]
        [array]$Packs,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$WorkspaceContext,

        [Parameter()]
        [string]$RetrievalProfile = '',
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration Get-ArbitratedPackOrder"
    }

    process {
        $scoredPacks = @()
        $isProjectLocal = Test-ProjectLocalContext -Query $Query

        foreach ($pack in $Packs) {
            $packId = if ($pack -is [hashtable]) { $pack.packId } else { $pack.PackId }
            $manifest = if ($pack -is [hashtable]) { $pack } else { $pack }

            # Get base relevance score
            $baseScore = Test-PackRelevance -Query $Query -PackManifest $manifest -RetrievalProfile $RetrievalProfile

            # Get authority score
            $authorityScore = Get-PackAuthorityScore -PackManifest $manifest

            # Calculate final score
            $finalScore = ($baseScore * 0.6) + ($authorityScore * 0.4)

            # Boost for project-local queries with private packs
            if ($isProjectLocal -and $packId -match '_private_|-private-') {
                $finalScore += 0.25
                $reason = 'Private-project pack (project-local query)'
            }
            # Boost for domain-specific packs
            elseif (Test-DomainSpecificity -Query $Query -PackManifest $manifest) {
                $finalScore += 0.15
                $reason = 'Domain-specific match'
            }
            else {
                $reason = 'General relevance'
            }

            # Penalty for generic packs when domain-specific packs match
            if ($finalScore -lt 0.5) {
                foreach ($pattern in $script:GenericPackPatterns) {
                    if ($packId -match $pattern) {
                        $finalScore = [Math]::Max(0, $finalScore - 0.2)
                        $reason = 'Generic pack (lower priority)'
                        break
                    }
                }
            }

            $scoredPacks += [PSCustomObject]@{
                packId = $packId
                score = [Math]::Round($finalScore, 3)
                reason = $reason
                baseScore = [Math]::Round($baseScore, 3)
                authorityScore = [Math]::Round($authorityScore, 3)
            }
        }

        # Sort by score descending
        $orderedPacks = $scoredPacks | Sort-Object -Property score -Descending

        return $orderedPacks
    }
}

<#
.SYNOPSIS
    Creates a standardized arbitration result object.

.DESCRIPTION
    Creates a result object conforming to the Arbitration Result schema
    with arbitrationId, query, packOrder, primaryPack, isCrossPack,
    requiresLabeling, and disputes fields.

.EXAMPLE
    $result = New-PackArbitrationResult -ArbitrationId $id -Query $query `
        -PackOrder $order -PrimaryPack 'godot-engine' -IsCrossPack $true

.OUTPUTS
    PSCustomObject conforming to Arbitration Result schema.
#>
function New-PackArbitrationResult {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArbitrationId,

        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $true)]
        [array]$PackOrder,

        [Parameter()]
        [string]$PrimaryPack = '',

        [Parameter()]
        [bool]$IsCrossPack = $false,

        [Parameter()]
        [bool]$RequiresLabeling = $false,

        [Parameter()]
        [array]$Disputes = @(),

        [Parameter()]
        [bool]$IsProjectLocal = $false,
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration New-PackArbitrationResult"
    }

    process {
        $result = [PSCustomObject]@{
            arbitrationId = $ArbitrationId
            query = $Query
            packOrder = $PackOrder
            primaryPack = $PrimaryPack
            isCrossPack = $IsCrossPack
            requiresLabeling = $RequiresLabeling
            isProjectLocal = $IsProjectLocal
            disputes = $Disputes
            createdUtc = [DateTime]::UtcNow.ToString("o")
        }

        return $result
    }
}

<#
.SYNOPSIS
    Exports arbitration result for tracing and audit.

.DESCRIPTION
    Saves the arbitration result to a JSON file for later analysis,
    debugging, and compliance auditing.

.PARAMETER ArbitrationResult
    The arbitration result object to export.

.PARAMETER OutputPath
    Path to save the exported result. Defaults to .llm-workflow/arbitration/

.PARAMETER Format
    Output format: 'json' or 'compact'.

.EXAMPLE
    Export-ArbitrationResult -ArbitrationResult $result -OutputPath './logs/'

.OUTPUTS
    String path to the exported file.
#>
function Export-ArbitrationResult {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$ArbitrationResult,

        [Parameter()]
        [string]$OutputPath = '',

        [Parameter()]
        [ValidateSet('json', 'compact')]
        [string]$Format = 'json',
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration Export-ArbitrationResult"
    }

    process {
        if ([string]::IsNullOrEmpty($OutputPath)) {
            $OutputPath = Join-Path $PWD '.llm-workflow/arbitration'
        }

        # Ensure directory exists
        if (-not (Test-Path -LiteralPath $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        $filename = "arbitration-$($ArbitrationResult.arbitrationId).json"
        $fullPath = Join-Path $OutputPath $filename

        if ($Format -eq 'compact') {
            $ArbitrationResult | ConvertTo-Json -Depth 5 -Compress | Out-File -FilePath $fullPath -Encoding UTF8
        }
        else {
            $ArbitrationResult | ConvertTo-Json -Depth 5 | Out-File -FilePath $fullPath -Encoding UTF8
        }

        Write-Verbose "Arbitration result exported to: $fullPath"
        return $fullPath
    }
}

#endregion

#region Arbitration Rule Functions

<#
.SYNOPSIS
    Determines if a pack is domain-specific for the given query.

.DESCRIPTION
    Analyzes the query for domain-specific keywords that match the pack's
    declared domain expertise. Returns true if the pack has clear domain
    relevance to the query.

.PARAMETER Query
    The user query.

.PARAMETER PackManifest
    The pack manifest to test.

.EXAMPLE
    $isDomainSpecific = Test-DomainSpecificity -Query "GDScript signals" -PackManifest $godotPack

.OUTPUTS
    Boolean indicating domain specificity.
#>
function Test-DomainSpecificity {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $true)]
        [hashtable]$PackManifest,
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration Test-DomainSpecificity"
    }

    process {
        $packId = $PackManifest.packId
        $queryLower = $Query.ToLower()

        # Check if pack has domain keywords defined
        if ($script:DomainKeywords.ContainsKey($packId)) {
            $keywords = $script:DomainKeywords[$packId]
            foreach ($keyword in $keywords) {
                if ($queryLower.Contains($keyword.ToLower())) {
                    return $true
                }
            }
        }

        # Check pack scope includes
        if ($PackManifest.ContainsKey('scope') -and $PackManifest.scope -and $PackManifest.scope.includes) {
            foreach ($include in $PackManifest.scope.includes) {
                $includeWords = $include.ToLower().Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
                $matchCount = 0
                foreach ($word in $includeWords) {
                    if ($word.Length -gt 3 -and $queryLower.Contains($word)) {
                        $matchCount++
                    }
                }
                if ($matchCount -ge 2) {
                    return $true
                }
            }
        }

        return $false
    }
}

<#
.SYNOPSIS
    Determines if a query is project-local.

.DESCRIPTION
    Analyzes the query for indicators that it refers to the user's
    current project rather than general domain questions.

.PARAMETER Query
    The user query to analyze.

.EXAMPLE
    $isLocal = Test-ProjectLocalContext -Query "How do I fix my plugin?"

.OUTPUTS
    Boolean indicating if query is project-local.
#>
function Test-ProjectLocalContext {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration Test-ProjectLocalContext"
    }

    process {
        $queryLower = $Query.ToLower()
        
        foreach ($indicator in $script:ProjectLocalIndicators) {
            if ($queryLower.Contains($indicator.ToLower())) {
                return $true
            }
        }

        return $false
    }
}

<#
.SYNOPSIS
    Calculates authority score for a pack.

.DESCRIPTION
    Computes an authority score (0.0 to 1.0) based on the pack's collections,
    authority roles, trust tiers, and lifecycle status.

.PARAMETER PackManifest
    The pack manifest to score.

.EXAMPLE
    $authorityScore = Get-PackAuthorityScore -PackManifest $pack

.OUTPUTS
    Double between 0.0 and 1.0 representing authority score.
#>
function Get-PackAuthorityScore {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$PackManifest,
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration Get-PackAuthorityScore"
    }

    process {
        $score = 0.5  # Base score

        # Factor 1: Collections and their authority roles
        if ($PackManifest.collections) {
            $totalWeight = 0
            $weightedSum = 0

            foreach ($collection in $PackManifest.collections.Values) {
                if ($collection.authorityRole -and $script:AuthorityRoleScores.ContainsKey($collection.authorityRole)) {
                    $roleScore = $script:AuthorityRoleScores[$collection.authorityRole]
                    $weightedSum += $roleScore
                    $totalWeight++
                }
            }

            if ($totalWeight -gt 0) {
                $score = ($weightedSum / $totalWeight) / 100
            }
        }

        # Factor 2: Lifecycle status adjustment
        $statusMultipliers = @{
            'promoted' = 1.2
            'validated' = 1.1
            'staged' = 1.0
            'building' = 0.9
            'draft' = 0.8
        }

        $status = if ($PackManifest.ContainsKey('status')) { $PackManifest.status } else { $null }
        if ($status -and $statusMultipliers.ContainsKey($status)) {
            $score *= $statusMultipliers[$status]
        }

        # Factor 3: Channel quality
        $channelMultipliers = @{
            'stable' = 1.1
            'candidate' = 1.05
            'draft' = 1.0
            'frozen' = 0.95
        }

        $channel = if ($PackManifest.ContainsKey('channel')) { $PackManifest.channel } else { $null }
        if ($channel -and $channelMultipliers.ContainsKey($channel)) {
            $score *= $channelMultipliers[$channel]
        }

        return [Math]::Min(1.0, [Math]::Max(0.0, $score))
    }
}

<#
.SYNOPSIS
    Detects if answer requires cross-pack labeling.

.DESCRIPTION
    Analyzes the query and available packs to determine if this is
    a cross-pack query that requires explicit source labeling.

.PARAMETER Query
    The user query.

.PARAMETER Packs
    Array of packs to consider.

.EXAMPLE
    $requiresLabeling = Test-CrossPackAnswer -Query "Compare Godot and RPG Maker" -Packs $packs

.OUTPUTS
    Boolean indicating if cross-pack labeling is required.
#>
function Test-CrossPackAnswer {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $true)]
        [array]$Packs,
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration Test-CrossPackAnswer"
    }

    process {
        $queryLower = $Query.ToLower()

        # Check for explicit cross-pack trigger phrases
        foreach ($trigger in $script:CrossPackTriggers) {
            if ($queryLower.Contains($trigger.ToLower())) {
                return $true
            }
        }

        # Check if multiple packs are highly relevant
        $relevantPackCount = 0
        foreach ($pack in $Packs) {
            $manifest = if ($pack -is [hashtable]) { $pack } else { $pack }
            $relevance = Test-PackRelevance -Query $Query -PackManifest $manifest
            if ($relevance -gt 0.4) {
                $relevantPackCount++
            }
        }

        # If 2+ packs are highly relevant, it's a cross-pack query
        if ($relevantPackCount -ge 2) {
            return $true
        }

        return $false
    }
}

<#
.SYNOPSIS
    Adds cross-pack labels to answers.

.DESCRIPTION
    Annotates answer content with appropriate source labels when
    content comes from multiple packs or requires explicit attribution.

.PARAMETER Answer
    The answer content to label.

.PARAMETER SourcePacks
    Array of pack IDs that contributed to the answer.

.PARAMETER IsCrossPack
    Whether this is explicitly a cross-pack answer.

.PARAMETER PrimaryPack
    The primary pack ID for the answer.

.EXAMPLE
    $labeledAnswer = Add-CrossPackLabel -Answer $content -SourcePacks @('godot-engine') -PrimaryPack 'godot-engine'

.OUTPUTS
    String with cross-pack labels added.
#>
function Add-CrossPackLabel {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Answer,

        [Parameter(Mandatory = $true)]
        [string[]]$SourcePacks,

        [Parameter()]
        [bool]$IsCrossPack = $false,

        [Parameter()]
        [string]$PrimaryPack = '',
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration Add-CrossPackLabel"
    }

    process {
        $labels = @()

        # Add primary source label
        if ($PrimaryPack) {
            $labels += "[Source: $PrimaryPack]"
        }

        # Add cross-pack indicator if multiple sources
        if ($IsCrossPack -or $SourcePacks.Count -gt 1) {
            $otherPacks = $SourcePacks | Where-Object { $_ -ne $PrimaryPack }
            if ($otherPacks) {
                $labels += "[Cross-pack: Also references $($otherPacks -join ', ')]"
            }
        }

        # Add warning for mixed domain content
        if ($IsCrossPack) {
            $labels += "[Note: This answer combines information from multiple domains. Verify applicability to your specific context.]"
        }

        # Combine labels with answer
        if ($labels.Count -gt 0) {
            return ($labels -join ' ') + "`n`n$Answer"
        }

        return $Answer
    }
}

#endregion

#region Conflict Resolution (Section 13.2)

<#
.SYNOPSIS
    Handles conflicting evidence across packs.

.DESCRIPTION
    Identifies and resolves conflicts between packs for a given query.
    Creates dispute sets when contradictory claims are detected.

.PARAMETER Query
    The user query.

.PARAMETER PackOrder
    Ordered list of packs with scores.

.PARAMETER Packs
    Array of pack manifests.

.EXAMPLE
    $disputes = Resolve-PackConflicts -Query "best plugin pattern" -PackOrder $order -Packs $packs

.OUTPUTS
    Array of dispute set objects.
#>
function Resolve-PackConflicts {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $true)]
        [array]$PackOrder,

        [Parameter(Mandatory = $true)]
        [array]$Packs,
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration Resolve-PackConflicts"
    }

    process {
        $disputes = @()

        # If multiple packs have similar high scores, there might be conflicting approaches
        if ($PackOrder.Count -ge 2) {
            $topPacks = $PackOrder | Select-Object -First 2
            $scoreDiff = $topPacks[0].score - $topPacks[1].score

            # If scores are close (< 0.15 difference), flag potential conflict
            if ($scoreDiff -lt 0.15 -and $topPacks[0].packId -ne $topPacks[1].packId) {
                # Check if packs are from different domains
                $pack1 = $Packs | Where-Object { 
                    $id = if ($_ -is [hashtable]) { $_.packId } else { $_.PackId }
                    $id -eq $topPacks[0].packId 
                } | Select-Object -First 1

                $pack2 = $Packs | Where-Object { 
                    $id = if ($_ -is [hashtable]) { $_.packId } else { $_.PackId }
                    $id -eq $topPacks[1].packId 
                } | Select-Object -First 1

                $domain1 = if ($pack1 -is [hashtable]) {
                    if ($pack1.ContainsKey('domain')) { $pack1.domain } else { $null }
                } else {
                    if ($pack1.PSObject.Properties['Domain']) { $pack1.Domain } else { $null }
                }
                $domain2 = if ($pack2 -is [hashtable]) {
                    if ($pack2.ContainsKey('domain')) { $pack2.domain } else { $null }
                } else {
                    if ($pack2.PSObject.Properties['Domain']) { $pack2.Domain } else { $null }
                }

                if ($domain1 -ne $domain2) {
                    # Create a dispute set for cross-domain conflict
                    $dispute = New-DisputeSet -DisputedEntity $Query -Status 'open'
                    
                    $dispute = Add-DisputeClaim -DisputeSet $dispute `
                        -ClaimSource $topPacks[0].packId `
                        -ClaimContent "Domain-specific approach from $domain1" `
                        -TrustLevel 'High' `
                        -Reasoning "Score: $($topPacks[0].score), Reason: $($topPacks[0].reason)"

                    $dispute = Add-DisputeClaim -DisputeSet $dispute `
                        -ClaimSource $topPacks[1].packId `
                        -ClaimContent "Alternative approach from $domain2" `
                        -TrustLevel 'High' `
                        -Reasoning "Score: $($topPacks[1].score), Reason: $($topPacks[1].reason)"

                    $disputes += $dispute
                }
            }
        }

        return $disputes
    }
}

<#
.SYNOPSIS
    Creates a dispute set for contradictory claims (Section 13.2).

.DESCRIPTION
    Creates a new dispute set object conforming to the Dispute Set schema
    with disputeId, disputedEntity, competingClaims, status, and preferredSource fields.

.PARAMETER DisputedEntity
    The entity or topic under dispute.

.PARAMETER Status
    Status: open, resolved, or local-override.

.PARAMETER PreferredSource
    The preferred source if adjudicated.

.EXAMPLE
    $dispute = New-DisputeSet -DisputedEntity "Best plugin pattern" -Status 'open'

.OUTPUTS
    PSCustomObject conforming to Dispute Set schema.
#>
function New-DisputeSet {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DisputedEntity,

        [Parameter()]
        [ValidateSet('open', 'resolved', 'local-override')]
        [string]$Status = 'open',

        [Parameter()]
        [string]$PreferredSource = '',
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration New-DisputeSet"
    }

    process {
        $disputeSet = [PSCustomObject]@{
            disputeId = [Guid]::NewGuid().ToString()
            disputedEntity = $DisputedEntity
            competingClaims = @()
            status = $Status
            preferredSource = $PreferredSource
            resolution = ''
            createdUtc = [DateTime]::UtcNow.ToString("o")
            updatedUtc = [DateTime]::UtcNow.ToString("o")
        }

        return $disputeSet
    }
}

<#
.SYNOPSIS
    Adds a competing claim to a dispute set.

.DESCRIPTION
    Adds a claim from a specific source to an existing dispute set
    with trust level and reasoning.

.PARAMETER DisputeSet
    The dispute set to add the claim to.

.PARAMETER ClaimSource
    The source pack ID making the claim.

.PARAMETER ClaimContent
    The content of the claim.

.PARAMETER TrustLevel
    Trust level: High, Medium-High, Medium, Low, or Quarantined.

.PARAMETER Reasoning
    Optional reasoning for the claim.

.EXAMPLE
    $dispute = Add-DisputeClaim -DisputeSet $dispute -ClaimSource 'godot-engine' `
        -ClaimContent 'Use signals for decoupling' -TrustLevel 'High'

.OUTPUTS
    Updated PSCustomObject dispute set.
#>
function Add-DisputeClaim {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$DisputeSet,

        [Parameter(Mandatory = $true)]
        [string]$ClaimSource,

        [Parameter(Mandatory = $true)]
        [string]$ClaimContent,

        [Parameter()]
        [ValidateSet('High', 'Medium-High', 'Medium', 'Low', 'Quarantined')]
        [string]$TrustLevel = 'Medium',

        [Parameter()]
        [string]$Reasoning = '',
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration Add-DisputeClaim"
    }

    process {
        $claim = [PSCustomObject]@{
            source = $ClaimSource
            content = $ClaimContent
            trustLevel = $TrustLevel
            reasoning = $Reasoning
            timestamp = [DateTime]::UtcNow.ToString("o")
        }

        $DisputeSet.competingClaims += $claim
        $DisputeSet.updatedUtc = [DateTime]::UtcNow.ToString("o")

        return $DisputeSet
    }
}

<#
.SYNOPSIS
    Exports a dispute set for audit.

.DESCRIPTION
    Saves a dispute set to a JSON file for compliance auditing
    and later analysis.

.PARAMETER DisputeSet
    The dispute set to export.

.PARAMETER OutputPath
    Path to save the exported dispute set.

.EXAMPLE
    Export-DisputeSet -DisputeSet $dispute -OutputPath './disputes/'

.OUTPUTS
    String path to the exported file.
#>
function Export-DisputeSet {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$DisputeSet,

        [Parameter()]
        [string]$OutputPath = '',
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration Export-DisputeSet"
    }

    process {
        if ([string]::IsNullOrEmpty($OutputPath)) {
            $OutputPath = Join-Path $PWD '.llm-workflow/disputes'
        }

        # Ensure directory exists
        if (-not (Test-Path -LiteralPath $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        $filename = "dispute-$($DisputeSet.disputeId).json"
        $fullPath = Join-Path $OutputPath $filename

        $DisputeSet | ConvertTo-Json -Depth 5 | Out-File -FilePath $fullPath -Encoding UTF8

        Write-Verbose "Dispute set exported to: $fullPath"
        return $fullPath
    }
}

#endregion

#region Utility Functions

<#
.SYNOPSIS
    Loads all available pack manifests.

.DESCRIPTION
    Loads all pack manifests from the packs/manifests directory.

.PARAMETER ManifestPath
    Path to the manifests directory.

.EXAMPLE
    $packs = Get-AvailablePacks -ManifestPath './packs/manifests'

.OUTPUTS
    Array of pack manifest hashtables.
#>
function Get-AvailablePacks {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [string]$ManifestPath = 'packs/manifests',
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration Get-AvailablePacks"
    }

    process {
        $packs = @()

        if (-not (Test-Path -LiteralPath $ManifestPath)) {
            Write-Warning "Manifest path not found: $ManifestPath"
            return $packs
        }

        $manifestFiles = Get-ChildItem -Path $ManifestPath -Filter '*.json'
        foreach ($file in $manifestFiles) {
            try {
                $content = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable
                $packs += $content
            }
            catch {
                Write-Warning "Failed to load manifest: $($file.FullName)"
            }
        }

        return $packs
    }
}

<#
.SYNOPSIS
    Gets retrieval profile for a pack.

.DESCRIPTION
    Retrieves a specific retrieval profile from a pack manifest.

.PARAMETER PackManifest
    The pack manifest.

.PARAMETER ProfileName
    Name of the retrieval profile.

.EXAMPLE
    $profile = Get-PackRetrievalProfile -PackManifest $pack -ProfileName 'api-lookup'

.OUTPUTS
    Hashtable containing the retrieval profile, or $null if not found.
#>
function Get-PackRetrievalProfile {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$PackManifest,

        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration Get-PackRetrievalProfile"
    }

    process {
        if ($PackManifest.retrievalProfiles -and $PackManifest.retrievalProfiles.ContainsKey($ProfileName)) {
            return $PackManifest.retrievalProfiles[$ProfileName]
        }
        return $null
    }
}

<#
.SYNOPSIS
    Tests if a pack supports a retrieval profile.

.DESCRIPTION
    Checks if a pack manifest contains a specific retrieval profile.

.PARAMETER PackManifest
    The pack manifest to check.

.PARAMETER ProfileName
    Name of the retrieval profile.

.EXAMPLE
    $supported = Test-PackRetrievalProfile -PackManifest $pack -ProfileName 'codegen'

.OUTPUTS
    Boolean indicating if the profile is supported.
#>
function Test-PackRetrievalProfile {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$PackManifest,

        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration Test-PackRetrievalProfile"
    }

    process {
        return ($PackManifest.retrievalProfiles -and 
                $PackManifest.retrievalProfiles.ContainsKey($ProfileName))
    }
}

<#
.SYNOPSIS
    Sets the preferred source in a dispute set.

.DESCRIPTION
    Adjudicates a dispute by setting the preferred source and
    updating the status to 'resolved'.

.PARAMETER DisputeSet
    The dispute set to adjudicate.

.PARAMETER PreferredSource
    The pack ID to set as preferred.

.PARAMETER Resolution
    Optional resolution notes.

.EXAMPLE
    $resolved = Set-DisputePreferredSource -DisputeSet $dispute -PreferredSource 'godot-engine'

.OUTPUTS
    Updated PSCustomObject dispute set.
#>
function Set-DisputePreferredSource {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$DisputeSet,

        [Parameter(Mandatory = $true)]
        [string]$PreferredSource,

        [Parameter()]
        [string]$Resolution = '',
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration Set-DisputePreferredSource"
    }

    process {
        $DisputeSet.preferredSource = $PreferredSource
        $DisputeSet.status = 'resolved'
        $DisputeSet.resolution = $Resolution
        $DisputeSet.updatedUtc = [DateTime]::UtcNow.ToString("o")

        return $DisputeSet
    }
}

<#
.SYNOPSIS
    Gets a summary of arbitration statistics.

.DESCRIPTION
    Analyzes arbitration results directory and returns statistics
    about cross-pack queries and disputes.

.PARAMETER ArbitrationPath
    Path to the arbitration results directory.

.EXAMPLE
    $stats = Get-ArbitrationStatistics -ArbitrationPath './.llm-workflow/arbitration'

.OUTPUTS
    PSCustomObject with arbitration statistics.
#>
function Get-ArbitrationStatistics {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$ArbitrationPath = '.llm-workflow/arbitration',
        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = New-CorrelationId }
        Write-Verbose "[$CorrelationId] CrossPackArbitration Get-ArbitrationStatistics"
    }

    process {
        $stats = [PSCustomObject]@{
            totalArbitrations = 0
            crossPackQueries = 0
            projectLocalQueries = 0
            labeledAnswers = 0
            disputesCreated = 0
            avgPacksConsidered = 0
            primaryPackDistribution = @{}
        }

        if (-not (Test-Path -LiteralPath $ArbitrationPath)) {
            return $stats
        }

        $files = Get-ChildItem -Path $ArbitrationPath -Filter 'arbitration-*.json'
        $packCounts = @()
        $primaryPacks = @{}

        foreach ($file in $files) {
            try {
                $result = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
                $stats.totalArbitrations++

                if ($result.isCrossPack) { $stats.crossPackQueries++ }
                if ($result.isProjectLocal) { $stats.projectLocalQueries++ }
                if ($result.requiresLabeling) { $stats.labeledAnswers++ }
                if ($result.disputes -and $result.disputes.Count -gt 0) { 
                    $stats.disputesCreated += $result.disputes.Count 
                }

                if ($result.packOrder) {
                    $packCounts += $result.packOrder.Count
                }

                if ($result.primaryPack) {
                    if (-not $primaryPacks.ContainsKey($result.primaryPack)) {
                        $primaryPacks[$result.primaryPack] = 0
                    }
                    $primaryPacks[$result.primaryPack]++
                }
            }
            catch {
                Write-Verbose "Failed to parse arbitration file: $($file.FullName)"
            }
        }

        if ($packCounts.Count -gt 0) {
            $stats.avgPacksConsidered = [Math]::Round(($packCounts | Measure-Object -Average).Average, 2)
        }

        $stats.primaryPackDistribution = $primaryPacks

        return $stats
    }
}

#endregion
