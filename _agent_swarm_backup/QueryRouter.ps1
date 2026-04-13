#requires -Version 5.1
<#
.SYNOPSIS
    Query Router Module for LLM Workflow Platform - Phase 5 Implementation

.DESCRIPTION
    Implements Section 14.1 and 14.2 of the LLM Workflow Canonical Architecture.
    Routes queries to appropriate domain packs based on query intent and retrieval profile.
    
    Key Responsibilities:
    - Select retrieval profile based on task type and workspace context
    - Route queries to appropriate packs with intelligent ranking
    - Detect query intent using keyword matching and heuristics
    - Support multiple retrieval profiles for different use cases
    - Provide transparent routing explanations for debugging

.NOTES
    File Name      : QueryRouter.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Date           : 2026-04-12
    Implements     : Section 14.1 (Query Routing), Section 14.2 (Retrieval Profiles)

.RETRIEVAL PROFILES
    api-lookup              - API reference and documentation queries
    plugin-pattern          - Plugin development patterns and best practices
    conflict-diagnosis      - Diagnosing plugin conflicts and compatibility issues
    codegen                 - Code generation tasks and templates
    private-project-first   - Prioritize private project content
    tooling-workflow        - Tooling and workflow questions
    reverse-format          - Reverse engineering and format analysis

.EXAMPLE
    # Route a query using automatic intent detection
    $result = Invoke-QueryRouting -Query "How do I create a custom battle system?"

.EXAMPLE
    # Route with explicit retrieval profile
    $result = Invoke-QueryRouting -Query "GDScript signals documentation" `
                                  -RetrievalProfile "api-lookup" `
                                  -WorkspaceContext @{ projectType = "godot" }

.EXAMPLE
    # Get routing explanation
    $explanation = Get-RoutingExplanation -RoutingResult $result
#>

Set-StrictMode -Version Latest

#region Configuration Data

# Schema version for routing results
$script:QueryRouterSchemaVersion = 1

# Default routing configuration
$script:DefaultRoutingConfig = @{
    maxPacksToRoute = 5
    minRelevanceThreshold = 0.3
    enableIntentDetection = $true
    enableCrossPackArbitration = $true
}

# Query intent detection patterns
$script:IntentPatterns = @{
    'api-lookup' = @{
        keywords = @(
            'api', 'documentation', 'docs', 'reference', 'function', 'method',
            'property', 'class', 'interface', 'enum', 'constant', 'parameter',
            'return', 'signature', 'call', 'usage', 'how to use', 'syntax',
            'gdscript api', 'rmmz api', 'bpy api', 'typescript', 'javascript'
        )
        patterns = @(
            '\b[A-Z][a-zA-Z]+\.[a-zA-Z]+\s*\(',  # Class.Method(
            '\b[A-Z][a-zA-Z]+\s*\(',           # Class(
            '\$[A-Z_]+\.'                       # Global class refs
        )
        priority = 1
    }
    'plugin-pattern' = @{
        keywords = @(
            'plugin', 'addon', 'extension', 'mod', 'middleware',
            'pattern', 'best practice', 'architecture', 'design',
            'structure', 'organization', 'hook', 'mixin', 'inheritance',
            'plugin command', 'notetag', 'meta', 'note field',
            'autoload', 'singleton', 'service locator'
        )
        patterns = @(
            '\.registerPlugin\s*\(',
            '\.addCommand\s*\(',
            '\.on\s*\(',
            'extends\s+Plugin'
        )
        priority = 2
    }
    'conflict-diagnosis' = @{
        keywords = @(
            'conflict', 'error', 'bug', 'issue', 'problem', 'crash',
            'compatibility', 'incompatible', 'version mismatch',
            'override', 'overwrite', 'patch', 'monkey patch',
            'load order', 'initialization', 'startup error',
            'console error', 'stack trace', 'exception',
            'not working', 'broken', 'fails', 'failed'
        )
        patterns = @(
            'TypeError',
            'ReferenceError',
            'undefined is not',
            'cannot read property',
            'conflict\s+with',
            'override\s+.*\.prototype'
        )
        priority = 3
    }
    'codegen' = @{
        keywords = @(
            'generate', 'template', 'scaffold', 'boilerplate',
            'create.*script', 'create.*class', 'create.*plugin',
            'implement', 'write.*code', 'code for',
            'snippet', 'example code', 'sample',
            'from.*generate', 'generate.*from'
        )
        patterns = @(
            '\bfunction\s+\w+\s*\([^)]*\)\s*\{',
            '\bclass\s+\w+',
            '\bexport\s+(default\s+)?\b',
            '\bdef\s+\w+\s*\('
        )
        priority = 4
    }
    'tooling-workflow' = @{
        keywords = @(
            'tool', 'workflow', 'pipeline', 'build', 'deploy',
            'ci/cd', 'automation', 'script', 'batch', 'makefile',
            'docker', 'container', 'kubernetes', 'k8s',
            'git', 'version control', 'repository',
            'lint', 'format', 'test', 'coverage',
            'mcp', 'model context protocol', 'claude', 'cursor'
        )
        patterns = @(
            '\.github/workflows',
            'Dockerfile',
            'docker-compose',
            '\.sh\s*$',
            '\.ps1\s*$'
        )
        priority = 5
    }
    'reverse-format' = @{
        keywords = @(
            'reverse engineer', 'decompile', 'extract', 'parse',
            'file format', 'binary', 'hex', 'structure',
            'header', 'magic number', 'endian', 'byte order',
            'protocol', 'packet', 'serialization',
            'rpgmvp', 'rpgmvm', 'rpgmvo', 'png', 'json', 'binary'
        )
        patterns = @(
            '0x[0-9A-Fa-f]+',
            '\bbyte\[\]',
            'Buffer\.from',
            'struct\.unpack'
        )
        priority = 6
    }
    'private-project-first' = @{
        keywords = @(
            'my project', 'my code', 'my plugin', 'my scene',
            'local file', 'this project', 'current project',
            'our project', 'in my game', 'in our game',
            'custom', 'private', 'internal'
        )
        patterns = @()
        priority = 0  # Special handling - boosted by context
    }
}

# Domain pack mappings
$script:DomainPackMappings = @{
    'rpgmaker' = @('rpgmaker-mz-core', 'rpgmaker-mz-plugins', 'rpgmaker-mv-compat')
    'godot' = @('godot-engine-core', 'godot-gdscript', 'godot-gdextension', 'godot-cpp')
    'blender' = @('blender-core', 'blender-python', 'blender-geometry-nodes', 'blender-shaders')
    'mcp' = @('mcp-core', 'mcp-claude', 'mcp-cursor')
    'private' = @()  # Populated dynamically
}

# Retrieval Profile Definitions (Section 14.2)
$script:RetrievalProfiles = @{
    'api-lookup' = @{
        description = 'API reference and documentation queries'
        packPreferences = @{
            primary = @('core-runtime', 'core-engine', 'language-binding')
            secondary = @('deployment-tooling', 'mcp-integration')
            avoid = @('starter-template', 'curated-index', 'reverse-format')
        }
        evidenceTypes = @('api-reference', 'schema-definition', 'configuration')
        rankingLogic = 'authority-first'
        minAuthorityScore = 0.7
        requireMultipleSources = $false
        boostExactMatches = $true
    }
    'plugin-pattern' = @{
        description = 'Plugin development patterns and best practices'
        packPreferences = @{
            primary = @('exemplar-pattern', 'core-engine', 'private-project')
            secondary = @('core-runtime', 'language-binding')
            avoid = @('reverse-format', 'curated-index')
        }
        evidenceTypes = @('code-example', 'explanation', 'tutorial')
        rankingLogic = 'pattern-quality'
        minAuthorityScore = 0.5
        requireMultipleSources = $true
        boostPrivateProject = $true
    }
    'conflict-diagnosis' = @{
        description = 'Diagnosing plugin conflicts and compatibility issues'
        packPreferences = @{
            primary = @('core-runtime', 'core-engine', 'private-project')
            secondary = @('deployment-tooling', 'llm-workflow')
            avoid = @('starter-template', 'curated-index')
        }
        evidenceTypes = @('dependency-info', 'version-compatibility', 'code-example')
        rankingLogic = 'runtime-authority'
        minAuthorityScore = 0.8
        requireMultipleSources = $true
        boostConflictIndicators = $true
    }
    'codegen' = @{
        description = 'Code generation tasks and templates'
        packPreferences = @{
            primary = @('exemplar-pattern', 'starter-template', 'core-engine')
            secondary = @('language-binding', 'core-runtime')
            avoid = @('reverse-format', 'curated-index')
        }
        evidenceTypes = @('code-example', 'schema-definition', 'tutorial')
        rankingLogic = 'completeness-score'
        minAuthorityScore = 0.4
        requireMultipleSources = $false
        preferCompleteExamples = $true
    }
    'private-project-first' = @{
        description = 'Prioritize private project content'
        packPreferences = @{
            primary = @('private-project')
            secondary = @('core-runtime', 'core-engine', 'exemplar-pattern')
            avoid = @()
        }
        evidenceTypes = @('code-example', 'api-reference', 'explanation', 'configuration')
        rankingLogic = 'project-local-first'
        minAuthorityScore = 0.3
        requireMultipleSources = $false
        boostPrivateProject = $true
        privateProjectBoostFactor = 0.4
    }
    'tooling-workflow' = @{
        description = 'Tooling and workflow questions'
        packPreferences = @{
            primary = @('llm-workflow', 'deployment-tooling', 'mcp-integration')
            secondary = @('core-engine', 'exemplar-pattern')
            avoid = @('reverse-format', 'starter-template')
        }
        evidenceTypes = @('configuration', 'tutorial', 'explanation')
        rankingLogic = 'tooling-relevance'
        minAuthorityScore = 0.5
        requireMultipleSources = $false
        boostToolingKeywords = $true
    }
    'reverse-format' = @{
        description = 'Reverse engineering and format analysis'
        packPreferences = @{
            primary = @('reverse-format', 'core-engine')
            secondary = @('language-binding', 'deployment-tooling')
            avoid = @('starter-template', 'curated-index', 'exemplar-pattern')
        }
        evidenceTypes = @('schema-definition', 'explanation', 'code-example')
        rankingLogic = 'format-authority'
        minAuthorityScore = 0.6
        requireMultipleSources = $true
        preferBinaryFormatDocs = $true
    }
}

# Authority role scores for ranking (synced with CrossPackArbitration)
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

$script:TelemetryTraceLog = [System.Collections.ArrayList]::new()

#endregion

#region Main Router Functions

<#
.SYNOPSIS
    Main query routing function that orchestrates the routing process.

.DESCRIPTION
    Routes a user query to appropriate packs based on detected intent and
    specified retrieval profile. Implements the complete routing pipeline:
    1. Detect query intent if not explicitly specified
    2. Get retrieval profile configuration
    3. Route to appropriate packs
    4. Return routing result with full metadata

.PARAMETER Query
    The user query to route.

.PARAMETER RetrievalProfile
    Optional retrieval profile name. If not specified, intent is auto-detected.

.PARAMETER WorkspaceContext
    Workspace context for private/public boundary checks and project type detection.

.PARAMETER AvailablePacks
    Optional array of available pack manifests. If not provided, uses default discovery.

.PARAMETER EnableArbitration
    Whether to enable cross-pack arbitration. Default: true

.EXAMPLE
    $result = Invoke-QueryRouting -Query "How do I use GDScript signals?"

.EXAMPLE
    $result = Invoke-QueryRouting -Query "Create a battle plugin" `
                                  -RetrievalProfile "codegen" `
                                  -WorkspaceContext @{ projectType = "rpgmaker" }

.OUTPUTS
    Hashtable containing routing result with routingId, profile, intent, 
    selectedPacks, and explanation.
#>
function Invoke-QueryRouting {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Query,

        [Parameter()]
        [string]$RetrievalProfile = '',

        [Parameter()]
        [hashtable]$WorkspaceContext = @{},

        [Parameter()]
        [array]$AvailablePacks = @(),

        [Parameter()]
        [bool]$EnableArbitration = $true,

        [Parameter()]
        [string]$CorrelationId = [Guid]::NewGuid().ToString()
    )

    begin {
        $routingId = [Guid]::NewGuid().ToString()
        $traceAttributes = @{
            Query = $Query
            RetrievalProfile = $RetrievalProfile
            EnableArbitration = $EnableArbitration
        }
        [void](Write-FunctionTelemetry -CorrelationId $CorrelationId -FunctionName 'Invoke-QueryRouting' -Attributes $traceAttributes)
        Write-Verbose "[QueryRouter] Starting query routing [$routingId]: $Query"
        
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    }

    process {
        try {
            # Step 1: Detect query intent if profile not specified
            $detectedIntent = Get-QueryIntent -Query $Query -CorrelationId $CorrelationId
            
            if ([string]::IsNullOrWhiteSpace($RetrievalProfile)) {
                $RetrievalProfile = $detectedIntent.primaryIntent
                Write-Verbose "[QueryRouter] Auto-detected profile: $RetrievalProfile"
            }

            # Step 2: Get retrieval profile configuration
            $profileConfig = Get-RetrievalProfile -ProfileName $RetrievalProfile
            
            if ($null -eq $profileConfig) {
                Write-Warning "[QueryRouter] Unknown retrieval profile '$RetrievalProfile', using default"
                $RetrievalProfile = 'api-lookup'
                $profileConfig = Get-RetrievalProfile -ProfileName $RetrievalProfile
            }

            # Step 3: Route query to packs
            $routingDecision = Route-QueryToPacks `
                -Query $Query `
                -AvailablePacks $AvailablePacks `
                -RetrievalProfile $RetrievalProfile `
                -WorkspaceContext $WorkspaceContext `
                -CorrelationId $CorrelationId

            # Step 4: Apply cross-pack arbitration if enabled
            $arbitrationResult = $null
            if ($EnableArbitration -and $routingDecision.selectedPacks.Count -gt 1) {
                $arbitrateCmd = Get-Command Invoke-CrossPackArbitration -ErrorAction SilentlyContinue
                if ($arbitrateCmd) {
                    $arbitrationResult = & $arbitrateCmd `
                        -Query $Query `
                        -Packs $routingDecision.selectedPacks `
                        -WorkspaceContext $WorkspaceContext `
                        -RetrievalProfile $RetrievalProfile `
                        -CorrelationId $CorrelationId
                }
            }

            # Step 5: Build final routing result
            $result = [ordered]@{
                schemaVersion = $script:QueryRouterSchemaVersion
                routingId = $routingId
                correlationId = $CorrelationId
                query = $Query
                retrievalProfile = $RetrievalProfile
                profileConfig = $profileConfig
                detectedIntent = $detectedIntent
                selectedPacks = $routingDecision.selectedPacks
                packOrder = $routingDecision.packOrder
                primaryPack = $routingDecision.primaryPack
                isCrossPack = if ($arbitrationResult) { $arbitrationResult.isCrossPack } else { $routingDecision.isCrossPack }
                confidence = $routingDecision.confidence
                executionTimeMs = $stopwatch.ElapsedMilliseconds
                createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
                workspaceId = if ($WorkspaceContext.ContainsKey('workspaceId') -and $WorkspaceContext.workspaceId) { $WorkspaceContext.workspaceId } else { $null }
                arbitrationResult = $arbitrationResult
            }

            Write-Verbose "[QueryRouter] Routing complete [$routingId]: Profile=$RetrievalProfile, Packs=$($routingDecision.selectedPacks.Count)"
            
            return $result
        }
        catch {
            Write-Error "[QueryRouter] Routing failed: $_"
            
            # Return graceful failure result
            return [ordered]@{
                schemaVersion = $script:QueryRouterSchemaVersion
                routingId = $routingId
                correlationId = $CorrelationId
                query = $Query
                retrievalProfile = $RetrievalProfile
                profileConfig = $null
                detectedIntent = $null
                error = $_.ToString()
                selectedPacks = @()
                packOrder = @()
                primaryPack = $null
                isCrossPack = $false
                confidence = 0
                executionTimeMs = $stopwatch.ElapsedMilliseconds
                createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            }
        }
    }
}

<#
.SYNOPSIS
    Gets the retrieval profile configuration.

.DESCRIPTION
    Retrieves the configuration for a named retrieval profile including
    pack preferences, evidence types, and ranking logic.

.PARAMETER ProfileName
    Name of the retrieval profile to retrieve.

.EXAMPLE
    $config = Get-RetrievalProfile -ProfileName "api-lookup"

.OUTPUTS
    Hashtable containing profile configuration, or null if not found.
#>
function Get-RetrievalProfile {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    process {
        if ($script:RetrievalProfiles.ContainsKey($ProfileName)) {
            $profile = $script:RetrievalProfiles[$ProfileName].Clone()
            $profile['profileName'] = $ProfileName
            return $profile
        }
        
        Write-Verbose "[QueryRouter] Profile '$ProfileName' not found in available profiles: $($script:RetrievalProfiles.Keys -join ', ')"
        return $null
    }
}

<#
.SYNOPSIS
    Routes a query to appropriate packs based on retrieval profile.

.DESCRIPTION
    Determines which packs should handle a query based on the retrieval
    profile, workspace context, and pack relevance scoring.

.PARAMETER Query
    The user query to route.

.PARAMETER AvailablePacks
    Array of available pack manifests.

.PARAMETER RetrievalProfile
    Name of the retrieval profile to use.

.PARAMETER WorkspaceContext
    Workspace context for private/public boundary and project type.

.EXAMPLE
    $result = Route-QueryToPacks -Query "GDScript signals" `
                                 -AvailablePacks $packs `
                                 -RetrievalProfile "api-lookup"

.OUTPUTS
    Hashtable containing selectedPacks, packOrder, primaryPack, isCrossPack, and confidence.
#>
function Route-QueryToPacks {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Query,

        [Parameter()]
        [array]$AvailablePacks = @(),

        [Parameter(Mandatory = $true)]
        [string]$RetrievalProfile,

        [Parameter()]
        [hashtable]$WorkspaceContext = @{},

        [Parameter()]
        [string]$CorrelationId = [Guid]::NewGuid().ToString()
    )

    process {
        # Get profile configuration
        $profileConfig = Get-RetrievalProfile -ProfileName $RetrievalProfile
        
        if ($null -eq $profileConfig) {
            throw "Unknown retrieval profile: $RetrievalProfile"
        }

        # If no packs provided, use placeholder for demonstration
        # In production, this would query the pack registry
        if ($AvailablePacks.Count -eq 0) {
            $AvailablePacks = Get-DefaultPackList -WorkspaceContext $WorkspaceContext
        }

        # Score and rank packs
        $scoredPacks = @()
        $queryLower = $Query.ToLower()
        $isProjectLocal = Test-ProjectLocalQuery -Query $Query

        foreach ($pack in $AvailablePacks) {
            $packId = if ($pack -is [hashtable]) { $pack.packId } else { $pack.PackId }
            $manifest = if ($pack -is [hashtable]) { $pack } else { @{ packId = $packId } }

            # Calculate base relevance score
            $relevanceScore = Calculate-PackRelevance `
                -Query $Query `
                -PackManifest $manifest `
                -ProfileConfig $profileConfig

            # Apply profile-specific boosts
            $finalScore = Apply-ProfileBoosts `
                -BaseScore $relevanceScore `
                -PackManifest $manifest `
                -ProfileConfig $profileConfig `
                -IsProjectLocal $isProjectLocal

            # Check if pack meets minimum threshold
            $minThreshold = $profileConfig.minAuthorityScore
            if ($finalScore -ge $minThreshold) {
                $scoredPacks += [PSCustomObject]@{
                    packId = $packId
                    score = [Math]::Round($finalScore, 3)
                    relevanceScore = [Math]::Round($relevanceScore, 3)
                    manifest = $manifest
                    reason = Get-PackSelectionReason -Score $finalScore -Manifest $manifest -ProfileConfig $profileConfig
                }
            }
        }

        # Sort by score descending
        $orderedPacks = @($scoredPacks | Sort-Object -Property score -Descending)

        # Determine if this is a cross-pack query
        $isCrossPack = $false
        if ($orderedPacks.Count -ge 2) {
            $scoreDiff = $orderedPacks[0].score - $orderedPacks[1].score
            $isCrossPack = $scoreDiff -lt 0.2  # Close scores indicate cross-pack relevance
        }

        # Select top packs based on profile
        $maxPacks = $script:DefaultRoutingConfig.maxPacksToRoute
        if ($profileConfig.requireMultipleSources -and $maxPacks -lt 2) {
            $maxPacks = 2
        }

        $selectedPacks = @($orderedPacks | Select-Object -First $maxPacks)

        # Calculate overall confidence
        $confidence = if ($selectedPacks.Count -gt 0) { $selectedPacks[0].score } else { 0 }

        $result = [ordered]@{
            selectedPacks = @($selectedPacks | ForEach-Object { $_.packId })
            packOrder = $orderedPacks
            primaryPack = if ($selectedPacks.Count -gt 0) { $selectedPacks[0].packId } else { $null }
            isCrossPack = $isCrossPack
            confidence = [Math]::Round($confidence, 3)
            profileUsed = $RetrievalProfile
            packsConsidered = $AvailablePacks.Count
            packsSelected = $selectedPacks.Count
        }

        return $result
    }
}

<#
.SYNOPSIS
    Detects the intent/type of a query.

.DESCRIPTION
    Analyzes query text to determine the primary and secondary intents
    using keyword matching and pattern recognition.

.PARAMETER Query
    The query to analyze.

.EXAMPLE
    $intent = Get-QueryIntent -Query "How do I create a plugin?"

.OUTPUTS
    Hashtable containing primaryIntent, secondaryIntent, confidence, and matchedKeywords.
#>
function Get-QueryIntent {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Query,

        [Parameter()]
        [string]$CorrelationId = [Guid]::NewGuid().ToString()
    )

    process {
        $traceAttributes = @{
            Query = $Query
        }
        [void](Write-FunctionTelemetry -CorrelationId $CorrelationId -FunctionName 'Get-QueryIntent' -Attributes $traceAttributes)

        $queryLower = $Query.ToLower()
        $intentScores = @{}
        $matchedKeywords = @{}

        # Score each intent type
        foreach ($intentEntry in $script:IntentPatterns.GetEnumerator()) {
            $intentName = $intentEntry.Key
            $intentConfig = $intentEntry.Value
            $score = 0
            $keywordsFound = @()

            # Check keywords
            foreach ($keyword in $intentConfig.keywords) {
                if ($queryLower.Contains($keyword.ToLower())) {
                    $score += 10
                    $keywordsFound += $keyword
                }
            }

            # Check patterns
            foreach ($pattern in $intentConfig.patterns) {
                if ($queryLower -match $pattern) {
                    $score += 15
                }
            }

            # Apply priority weighting
            $priorityWeight = [Math]::Max(1, 10 - $intentConfig.priority)
            $score = $score * $priorityWeight

            $intentScores[$intentName] = $score
            $matchedKeywords[$intentName] = $keywordsFound
        }

        # Diagnostic language should outweigh generic "plugin" wording when both are present.
        if ($queryLower -match '(conflict|error|debug|compatibility|typeerror|exception|issue|problem|crash|broken|fail)') {
            $intentScores['conflict-diagnosis'] += 120
        }

        # Determine primary and secondary intents
        $sortedIntents = $intentScores.GetEnumerator() | Sort-Object -Property Value -Descending
        $primaryIntent = $sortedIntents[0].Key
        $primaryScore = $sortedIntents[0].Value

        # Treat project-local phrasing as a modifier when a more specific intent also matched.
        if ($primaryIntent -eq 'private-project-first') {
            $specificIntent = $sortedIntents | Where-Object {
                $_.Key -ne 'private-project-first' -and $_.Value -gt 0
            } | Select-Object -First 1

            if ($specificIntent) {
                $primaryIntent = $specificIntent.Key
                $primaryScore = $specificIntent.Value
            }
        }
        
        $secondaryIntent = if ($sortedIntents.Count -gt 1 -and $sortedIntents[1].Value -gt 0) { 
            $sortedIntents[1].Key 
        } else { 
            $null 
        }

        # Calculate confidence
        $totalScore = ($intentScores.Values | Measure-Object -Sum).Sum
        $confidence = if ($totalScore -gt 0) { 
            [Math]::Min(1.0, $primaryScore / $totalScore) 
        } else { 
            0.5 
        }

        return [ordered]@{
            primaryIntent = $primaryIntent
            secondaryIntent = $secondaryIntent
            confidence = [Math]::Round($confidence, 3)
            scores = $intentScores
            matchedKeywords = $matchedKeywords
            allIntents = @($sortedIntents | ForEach-Object { $_.Key })
            correlationId = $CorrelationId
        }
    }
}

<#
.SYNOPSIS
    Gets a human-readable explanation of a routing decision.

.DESCRIPTION
    Generates a detailed explanation of why a query was routed to specific
    packs, including intent detection results and profile selection logic.

.PARAMETER RoutingResult
    The routing result hashtable from Invoke-QueryRouting.

.PARAMETER Format
    Output format: 'text' or 'markdown'.

.EXAMPLE
    $explanation = Get-RoutingExplanation -RoutingResult $result

.OUTPUTS
    String containing the routing explanation.
#>
function Get-RoutingExplanation {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$RoutingResult,

        [Parameter()]
        [ValidateSet('text', 'markdown')]
        [string]$Format = 'text'
    )

    process {
        $lines = @()
        $newline = if ($Format -eq 'markdown') { "`n`n" } else { "`n" }
        $bullet = if ($Format -eq 'markdown') { '- ' } else { '  - ' }
        $header = if ($Format -eq 'markdown') { '## ' } else { '' }

        # Header
        $lines += "$header`Query Routing Decision"
        $lines += "Routing ID: $($RoutingResult.routingId)"
        $lines += "Query: $($RoutingResult.query)"
        $lines += ""

        # Profile selection
        $lines += "$header`Retrieval Profile"
        $lines += "Selected Profile: $($RoutingResult.retrievalProfile)"
        if ($RoutingResult.profileConfig -and $RoutingResult.profileConfig.description) {
            $lines += "Description: $($RoutingResult.profileConfig.description)"
        }
        $lines += ""

        # Intent detection
        if ($RoutingResult.detectedIntent) {
            $intent = $RoutingResult.detectedIntent
            $lines += "$header`Intent Detection"
            $lines += "Primary Intent: $($intent.primaryIntent) (confidence: $($intent.confidence))"
            if ($intent.secondaryIntent) {
                $lines += "Secondary Intent: $($intent.secondaryIntent)"
            }
            
            if ($intent.matchedKeywords -and $intent.matchedKeywords[$intent.primaryIntent]) {
                $keywords = $intent.matchedKeywords[$intent.primaryIntent]
                if ($keywords.Count -gt 0) {
                    $lines += "Matched Keywords: $($keywords -join ', ')"
                }
            }
            $lines += ""
        }

        # Pack selection
        $lines += "$header`Pack Selection"
        if ($RoutingResult.primaryPack) {
            $lines += "Primary Pack: $($RoutingResult.primaryPack)"
        }
        
        if ($RoutingResult.packOrder -and $RoutingResult.packOrder.Count -gt 0) {
            $lines += "Selected Packs (in priority order):"
            foreach ($pack in $RoutingResult.packOrder) {
                $packId = if ($pack -is [hashtable]) { $pack.packId } else { $pack.packId }
                $score = if ($pack -is [hashtable]) { $pack.score } else { $pack.score }
                $reason = if ($pack -is [hashtable]) { $pack.reason } else { '' }
                $lines += "$bullet$packId (score: $score)$reason"
            }
        }
        else {
            $lines += "No packs selected."
        }
        $lines += ""

        # Cross-pack information
        $lines += "$header`Cross-Pack Analysis"
        if ($RoutingResult.isCrossPack) {
            $lines += "This is a CROSS-PACK query requiring arbitration."
            $lines += "Multiple packs have similar relevance scores."
        }
        else {
            $lines += "Single-pack query with clear primary source."
        }
        $lines += ""

        # Metadata
        $lines += "$header`Execution Details"
        $lines += "Overall Confidence: $($RoutingResult.confidence)"
        $lines += "Execution Time: $($RoutingResult.executionTimeMs)ms"
        $lines += "Created: $($RoutingResult.createdAt)"

        return $lines -join $newline
    }
}

#endregion

#region Helper Functions

<#
.SYNOPSIS
    Calculates relevance score for a pack based on query and profile.

.DESCRIPTION
    Internal helper that scores pack relevance using domain keywords,
    authority roles, and profile-specific matching logic.

.PARAMETER Query
    The user query.

.PARAMETER PackManifest
    The pack manifest to score.

.PARAMETER ProfileConfig
    The retrieval profile configuration.

.OUTPUTS
    Double representing relevance score (0.0 to 1.0).
#>
function Calculate-PackRelevance {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Query,

        [Parameter(Mandatory = $true)]
        [hashtable]$PackManifest,

        [Parameter()]
        [hashtable]$ProfileConfig = @{}
    )

    process {
        $score = 0.0
        $packId = if ($PackManifest.packId) { $PackManifest.packId } else { 'unknown' }
        $queryLower = $Query.ToLower()

        # 1. Domain keyword matching (0-40 points)
        $domainScore = 0
        $packDomain = if ($PackManifest.domain) { $PackManifest.domain } else { '' }
        
        if ($packDomain -and $script:DomainPackMappings.ContainsKey($packDomain)) {
            $domainKeywords = Get-DomainKeywords -Domain $packDomain
            foreach ($keyword in $domainKeywords) {
                if ($queryLower.Contains($keyword.ToLower())) {
                    $domainScore += 10
                }
            }
        }
        $score += [Math]::Min(40, $domainScore)

        # 2. Authority role scoring (0-30 points)
        $authorityScore = 0
        if ($PackManifest.collections -and $PackManifest.collections.Count -gt 0) {
            $maxAuthority = 0
            foreach ($collection in $PackManifest.collections.Values) {
                $role = if ($collection -is [hashtable]) { $collection.authorityRole } else { $collection.AuthorityRole }
                if ($role -and $script:AuthorityRoleScores.ContainsKey($role)) {
                    $roleScore = $script:AuthorityRoleScores[$role]
                    if ($roleScore -gt $maxAuthority) {
                        $maxAuthority = $roleScore
                    }
                }
            }
            $authorityScore = ($maxAuthority / 100) * 30
        }
        elseif ($packId -match 'core|engine') {
            $authorityScore = 30
        }
        elseif ($packId -match 'runtime|binding|plugin|workflow|tool') {
            $authorityScore = 21
        }
        $score += $authorityScore

        # 3. Profile pack preferences (0-20 points)
        if ($ProfileConfig -and $ProfileConfig.packPreferences) {
            $prefs = $ProfileConfig.packPreferences
            $packIdTokens = @($packId -split '[-_]' | Where-Object { $_ })
            
            # Check primary packs
            foreach ($primary in $prefs.primary) {
                $primaryTokens = @($primary -split '[-_]' | Where-Object { $_ })
                $tokenMatch = @($primaryTokens | Where-Object { $packIdTokens -contains $_ }).Count -gt 0
                if ($packId -match $primary -or $packId -like "*$primary*" -or $tokenMatch) {
                    $score += 20
                    break
                }
            }
            
            # Check secondary packs
            foreach ($secondary in $prefs.secondary) {
                $secondaryTokens = @($secondary -split '[-_]' | Where-Object { $_ })
                $tokenMatch = @($secondaryTokens | Where-Object { $packIdTokens -contains $_ }).Count -gt 0
                if ($packId -match $secondary -or $packId -like "*$secondary*" -or $tokenMatch) {
                    $score += 10
                    break
                }
            }
        }

        # 4. Evidence type matching (0-10 points)
        $supportedEvidenceTypes = @()
        if ($PackManifest.ContainsKey('supportedEvidenceTypes') -and $PackManifest.supportedEvidenceTypes) {
            $supportedEvidenceTypes = @($PackManifest.supportedEvidenceTypes)
        }

        if ($ProfileConfig -and $ProfileConfig.evidenceTypes -and $supportedEvidenceTypes.Count -gt 0) {
            $matchCount = 0
            foreach ($evType in $ProfileConfig.evidenceTypes) {
                if ($supportedEvidenceTypes -contains $evType) {
                    $matchCount++
                }
            }
            $score += ($matchCount / [Math]::Max(1, $ProfileConfig.evidenceTypes.Count)) * 10
        }

        # Normalize to 0.0-1.0 range
        return [Math]::Min(1.0, $score / 100)
    }
}

<#
.SYNOPSIS
    Applies profile-specific score boosts.

.DESCRIPTION
    Adjusts pack relevance scores based on retrieval profile preferences
    and workspace context.

.PARAMETER BaseScore
    The base relevance score.

.PARAMETER PackManifest
    The pack manifest.

.PARAMETER ProfileConfig
    The retrieval profile configuration.

.PARAMETER IsProjectLocal
    Whether the query appears to be project-local.

.OUTPUTS
    Double representing adjusted score.
#>
function Apply-ProfileBoosts {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [double]$BaseScore,

        [Parameter(Mandatory = $true)]
        [hashtable]$PackManifest,

        [Parameter()]
        [hashtable]$ProfileConfig = @{},

        [Parameter()]
        [bool]$IsProjectLocal = $false
    )

    process {
        $adjustedScore = $BaseScore
        $packId = if ($PackManifest.packId) { $PackManifest.packId } else { '' }

        # Boost for private project packs when query is project-local
        if ($IsProjectLocal -and $ProfileConfig.boostPrivateProject) {
            if ($packId -match '_private_|-private-|private_') {
                $boostFactor = if ($ProfileConfig.privateProjectBoostFactor) { 
                    $ProfileConfig.privateProjectBoostFactor 
                } else { 
                    0.3 
                }
                $adjustedScore += $boostFactor
            }
        }

        # Boost for private-project-first profile
        if ($ProfileConfig.profileName -eq 'private-project-first') {
            if ($packId -match '_private_|-private-|private_') {
                $adjustedScore += 0.4
            }
        }

        # Penalty for packs in avoid list
        if ($ProfileConfig.packPreferences -and $ProfileConfig.packPreferences.avoid) {
            foreach ($avoid in $ProfileConfig.packPreferences.avoid) {
                if ($packId -match $avoid -or $packId -like "*$avoid*") {
                    $adjustedScore = [Math]::Max(0, $adjustedScore - 0.3)
                    break
                }
            }
        }

        return [Math]::Min(1.0, [Math]::Max(0, $adjustedScore))
    }
}

<#
.SYNOPSIS
    Gets domain-specific keywords for a domain.

.DESCRIPTION
    Returns the list of keywords associated with a domain for relevance
    scoring.

.PARAMETER Domain
    The domain name.

.OUTPUTS
    Array of keywords.
#>
function Get-DomainKeywords {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    process {
        $keywords = @()
        
        switch ($Domain.ToLower()) {
            'rpgmaker' {
                $keywords = @(
                    'rpg maker', 'rmmz', 'plugin', 'battle system', 'map', 'event',
                    'notetag', 'plugin command', 'rpgmaker', 'mv compatible', 'pixi',
                    'window_', 'scene_', 'sprite_', 'game_', 'actor', 'enemy', 'item',
                    'typescript', 'javascript', 'js plugin', 'rpgmv', 'rpgmz'
                )
            }
            'godot' {
                $keywords = @(
                    'godot', 'gdscript', 'node', 'scene', 'signal', 'gdextension',
                    'autoload', 'singleton', 'tscn', 'tres', 'export var', 'onready',
                    'process', 'physics_process', 'ready', 'tree', 'canvas', 'viewport',
                    'rust', 'gdext', 'godot-cpp', 'c++', 'gdnative', 'steam'
                )
            }
            'blender' {
                $keywords = @(
                    'blender', 'bpy', 'addon', 'geometry nodes', 'shader', 'material',
                    'mesh', 'armature', 'bone', 'rigging', 'animation', 'render',
                    'cycles', 'eevee', 'uv', 'texture', 'procedural', 'python',
                    'synthetic data', 'blenderproc', 'gis', 'mmd'
                )
            }
            'mcp' {
                $keywords = @(
                    'mcp', 'model context protocol', 'claude', 'cursor', 'context',
                    'protocol', 'server', 'client', 'tool', 'resource', 'prompt'
                )
            }
            default {
                $keywords = @()
            }
        }
        
        return $keywords
    }
}

<#
.SYNOPSIS
    Tests if a query appears to be project-local.

.DESCRIPTION
    Analyzes query for indicators that it refers to the user's current
    project rather than general domain questions.

.PARAMETER Query
    The query to analyze.

.OUTPUTS
    Boolean indicating if query is project-local.
#>
function Test-ProjectLocalQuery {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Query
    )

    process {
        $localIndicators = @(
            'my project', 'my code', 'my plugin', 'my scene', 'my script',
            'local file', 'this project', 'current project', 'our project',
            'in my game', 'in our game', 'my addon', 'my mod', 'custom'
        )
        
        $queryLower = $Query.ToLower()
        
        foreach ($indicator in $localIndicators) {
            if ($queryLower.Contains($indicator)) {
                return $true
            }
        }
        
        return $false
    }
}

<#
.SYNOPSIS
    Gets a default list of packs for routing.

.DESCRIPTION
    Returns a placeholder list of pack manifests based on workspace context.
    In production, this would query the pack registry.

.PARAMETER WorkspaceContext
    Workspace context for filtering packs.

.OUTPUTS
    Array of pack manifest hashtables.
#>
function Get-DefaultPackList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [hashtable]$WorkspaceContext = @{}
    )

    process {
        $packs = @()
        $projectType = if ($WorkspaceContext.ContainsKey('projectType') -and $WorkspaceContext.projectType) { $WorkspaceContext.projectType } else { '' }

        # Add domain-specific packs based on project type
        switch ($projectType.ToLower()) {
            'rpgmaker' {
                $packs += @(
                    @{ packId = 'rpgmaker-mz-core'; domain = 'rpgmaker'; collections = @{} }
                    @{ packId = 'rpgmaker-mz-plugins'; domain = 'rpgmaker'; collections = @{} }
                )
            }
            'godot' {
                $packs += @(
                    @{ packId = 'godot-engine-core'; domain = 'godot'; collections = @{} }
                    @{ packId = 'godot-gdscript'; domain = 'godot'; collections = @{} }
                )
            }
            'blender' {
                $packs += @(
                    @{ packId = 'blender-core'; domain = 'blender'; collections = @{} }
                    @{ packId = 'blender-python'; domain = 'blender'; collections = @{} }
                )
            }
        }

        # Always add core workflow packs
        $packs += @(
            @{ packId = 'llm-workflow-core'; domain = 'workflow'; collections = @{} }
            @{ packId = 'mcp-integration'; domain = 'mcp'; collections = @{} }
        )

        # Add private project pack if available
        if ($WorkspaceContext.ContainsKey('workspaceId') -and $WorkspaceContext.workspaceId) {
            $packs += @{
                packId = "$($WorkspaceContext.workspaceId)_private"
                domain = 'private'
                collections = @{}
            }
        }

        return $packs
    }
}

<#
.SYNOPSIS
    Gets the reason for pack selection.

.DESCRIPTION
    Generates a human-readable reason for why a pack was selected.

.PARAMETER Score
    The pack's relevance score.

.PARAMETER Manifest
    The pack manifest.

.PARAMETER ProfileConfig
    The retrieval profile configuration.

.OUTPUTS
    String explaining the selection reason.
#>
function Get-PackSelectionReason {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [double]$Score,

        [Parameter(Mandatory = $true)]
        [hashtable]$Manifest,

        [Parameter()]
        [hashtable]$ProfileConfig = @{}
    )

    process {
        $reasons = @()
        $packId = if ($Manifest.packId) { $Manifest.packId } else { 'unknown' }

        if ($Score -ge 0.9) {
            $reasons += 'High authority match'
        }
        elseif ($Score -ge 0.7) {
            $reasons += 'Strong relevance'
        }
        elseif ($Score -ge 0.5) {
            $reasons += 'Moderate relevance'
        }
        else {
            $reasons += 'Low relevance fallback'
        }

        if ($packId -match '_private_|-private-|private_') {
            $reasons += 'Private project pack'
        }

        if ($ProfileConfig.packPreferences) {
            foreach ($primary in $ProfileConfig.packPreferences.primary) {
                if ($packId -match $primary) {
                    $reasons += 'Profile primary preference'
                    break
                }
            }
        }

        return " [$($reasons -join ', ')]"
    }
}

#endregion

#region List and Discovery Functions

<#
.SYNOPSIS
    Lists all available retrieval profiles.

.DESCRIPTION
    Returns a list of all configured retrieval profiles with their
    descriptions and key settings.

.EXAMPLE
    $profiles = Get-RetrievalProfileList

.OUTPUTS
    Array of profile information objects.
#>
function Get-RetrievalProfileList {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    process {
        $profiles = @()
        
        foreach ($entry in $script:RetrievalProfiles.GetEnumerator()) {
            $profileName = $entry.Key
            $config = $entry.Value
            
            $profiles += [PSCustomObject]@{
                profileName = $profileName
                description = $config.description
                minAuthorityScore = $config.minAuthorityScore
                requireMultipleSources = $config.requireMultipleSources
                primaryPreferences = $config.packPreferences.primary
                evidenceTypes = $config.evidenceTypes
            }
        }
        
        return $profiles | Sort-Object -Property profileName
    }
}

<#
.SYNOPSIS
    Lists all supported query intents.

.DESCRIPTION
    Returns a list of all query intent types with their keywords
    and detection patterns.

.EXAMPLE
    $intents = Get-QueryIntentList

.OUTPUTS
    Array of intent information objects.
#>
function Get-QueryIntentList {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    process {
        $intents = @()
        
        foreach ($entry in $script:IntentPatterns.GetEnumerator()) {
            $intentName = $entry.Key
            $config = $entry.Value
            
            $intents += [PSCustomObject]@{
                intentName = $intentName
                priority = $config.priority
                keywordCount = $config.keywords.Count
                patternCount = $config.patterns.Count
                sampleKeywords = $config.keywords | Select-Object -First 5
            }
        }
        
        return $intents | Sort-Object -Property priority
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Invoke-QueryRouting',
    'Get-RetrievalProfile',
    'Route-QueryToPacks',
    'Get-QueryIntent',
    'Get-RoutingExplanation',
    'Get-RetrievalProfileList',
    'Get-QueryIntentList'
)
