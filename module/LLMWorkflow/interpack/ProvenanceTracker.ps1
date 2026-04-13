#requires -Version 5.1
<#
.SYNOPSIS
    Cross-Pack Provenance Tracker for LLM Workflow platform.

.DESCRIPTION
    Provides comprehensive asset lineage tracking across all pipeline stages:
    - Track asset lineage across packs (Blender, Godot, RPG Maker MZ, AI models)
    - Generate derivation records for all transformations
    - Query provenance chains with graph traversal
    - Export provenance graphs for visualization

    Implements W3C PROV standards for provenance tracking with extensions
    for game development asset workflows.

.NOTES
    File: ProvenanceTracker.ps1
    Version: 0.1.0
    Author: LLM Workflow Team
    Part of: Advanced Inter-Pack Pipeline Implementation

.EXAMPLE
    # Create provenance record
    $prov = New-ProvenanceRecord -AssetId "mesh-001" -SourcePacks @("blender-engine") -TargetPack "godot-engine" -Operation "export"
    
    # Query lineage
    $chain = Get-ProvenanceChain -AssetId "mesh-001" -Depth 5
    
    # Export graph
    Export-ProvenanceGraph -AssetId "mesh-001" -Format "mermaid" -OutputPath "./lineage.md"
#>

Set-StrictMode -Version Latest

#===============================================================================
# Constants and Configuration
#===============================================================================

$script:ProvSchemaVersion = 1
$script:ProvDirectory = ".llm-workflow/interpack/provenance"
$script:ProvGraphDirectory = ".llm-workflow/interpack/provenance/graphs"
$script:ProvIndexFile = ".llm-workflow/interpack/provenance/index.json"

# W3C PROV entity types
$script:EntityTypes = @{
    Asset = 'prov:Entity'
    Activity = 'prov:Activity'
    Agent = 'prov:Agent'
    Collection = 'prov:Collection'
    Bundle = 'prov:Bundle'
}

# Operation types for provenance
$script:OperationTypes = @(
    'create'
    'modify'
    'derive'
    'export'
    'import'
    'transform'
    'generate'
    'compose'
    'decompose'
    'ai-generate'
    'ai-modify'
    'sync'
    'copy'
    'version'
)

# Supported graph export formats
$script:GraphFormats = @{
    'mermaid' = @{
        extension = '.md'
        directed = $true
        nodeShapes = @{ Asset = '[]'; Activity = '()'; Agent = '(())' }
    }
    'dot' = @{
        extension = '.dot'
        directed = $true
        supportsStyling = $true
    }
    'cypher' = @{
        extension = '.cypher'
        database = 'neo4j'
    }
    'json' = @{
        extension = '.json'
        schema = 'prov-json'
    }
    'jsonld' = @{
        extension = '.jsonld'
        schema = 'prov-jsonld'
    }
}

# Exit codes
$script:ExitCodes = @{
    Success = 0
    GeneralFailure = 1
    InvalidAssetId = 2
    RecordNotFound = 3
    ChainBroken = 4
    ExportFailed = 5
    GraphError = 6
}

#===============================================================================
# New Provenance Record
#===============================================================================

function New-ProvenanceRecord {
    <#
    .SYNOPSIS
        Creates a new provenance record for asset tracking.
    .DESCRIPTION
        Records the lineage of an asset including its sources, transformations,
        and relationships to other assets. Follows W3C PROV standard.
    .PARAMETER AssetId
        Unique identifier for the asset.
    .PARAMETER AssetType
        Type of asset (mesh, texture, animation, audio, script, ai-model).
    .PARAMETER SourcePacks
        Source pack(s) where the asset originated.
    .PARAMETER TargetPack
        Target pack where the asset was exported/imported.
    .PARAMETER Operation
        Operation type (create, modify, derive, export, import, transform, etc.).
    .PARAMETER SourceAssets
        Array of source asset IDs that contributed to this asset.
    .PARAMETER Transformation
        Description of transformation applied.
    .PARAMETER Agent
        Agent (user, tool, AI model) that performed the operation.
    .PARAMETER Metadata
        Additional metadata about the operation.
    .PARAMETER ProjectRoot
        Project root directory.
    .PARAMETER RunId
        Run ID for tracking.
    .OUTPUTS
        System.Collections.Hashtable with provenance record.
    .EXAMPLE
        $prov = New-ProvenanceRecord -AssetId "char-mesh-001" -AssetType "mesh" `
            -SourcePacks @("blender-engine") -TargetPack "godot-engine" `
            -Operation "export" -Agent "blender-godot-exporter"
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AssetId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('mesh', 'texture', 'material', 'animation', 'audio', 'script', 'scene', 'ai-model', 'config')]
        [string]$AssetType,

        [Parameter()]
        [string[]]$SourcePacks = @(),

        [Parameter()]
        [string]$TargetPack = '',

        [Parameter(Mandatory = $true)]
        [ValidateSet('create', 'modify', 'derive', 'export', 'import', 'transform', 'generate', 'compose', 'decompose', 'ai-generate', 'ai-modify', 'sync', 'copy', 'version')]
        [string]$Operation,

        [Parameter()]
        [string[]]$SourceAssets = @(),

        [Parameter()]
        [string]$Transformation = '',

        [Parameter()]
        [hashtable]$Agent = @{
            type = 'tool'
            name = 'unknown'
            version = 'unknown'
        },

        [Parameter()]
        [hashtable]$Metadata = @{},

        [Parameter()]
        [string]$ProjectRoot = '.',

        [Parameter()]
        [string]$RunId = ''
    )

    if (-not $RunId) {
        $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
        $random = Get-Random -Minimum 0 -Maximum 65535
        $RunId = "prov-$timestamp-$($random.ToString('x4'))"
    }

    # Initialize directories
    $provDir = Join-Path $ProjectRoot $script:ProvDirectory
    if (-not (Test-Path -LiteralPath $provDir)) {
        New-Item -ItemType Directory -Path $provDir -Force | Out-Null
    }

    # Generate provenance ID
    $provenanceId = "prov-$AssetId-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))"

    # Build W3C PROV compatible record
    $record = [ordered]@{
        # Schema and identification
        schemaVersion = $script:ProvSchemaVersion
        provenanceId = $provenanceId
        provType = $script:EntityTypes.Asset
        
        # Asset identification
        asset = @{
            id = $AssetId
            type = $AssetType
            namespace = if ($TargetPack) { $TargetPack } else { ($SourcePacks | Select-Object -First 1) }
        }
        
        # Activity (operation)
        activity = @{
            type = $Operation
            startedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            endedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            description = $Transformation
        }
        
        # Agent
        agent = $Agent
        
        # Relationships (PROV relations)
        wasGeneratedBy = @{
            activity = $Operation
            time = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        
        wasDerivedFrom = @($SourceAssets | ForEach-Object { @{ entity = $_ } })
        wasAttributedTo = @{ agent = $Agent.name }
        
        # Pack flow
        packFlow = @{
            sources = $SourcePacks
            target = $TargetPack
        }
        
        # Additional metadata
        metadata = [ordered]@{
            runId = $RunId
            createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            createdBy = [Environment]::UserName
            machine = $env:COMPUTERNAME
        }
        
        # Merge custom metadata
        foreach ($key in $Metadata.Keys) {
            $metadata[$key] = $Metadata[$key]
        }
    }

    # Save record
    $recordPath = Join-Path $provDir "$provenanceId.json"
    $record | ConvertTo-Json -Depth 10 | Out-File -FilePath $recordPath -Encoding UTF8

    # Update index
    Update-ProvenanceIndex -Record $record -ProjectRoot $ProjectRoot

    Write-Verbose "[Provenance] Record created: $provenanceId for asset $AssetId"

    return $record
}

#===============================================================================
# Get Provenance Chain
#===============================================================================

function Get-ProvenanceChain {
    <#
    .SYNOPSIS
        Queries the complete lineage chain for an asset.
    .DESCRIPTION
        Traverses provenance records to build the complete derivation
        history of an asset, including all source assets and transformations.
    .PARAMETER AssetId
        Asset ID to query lineage for.
    .PARAMETER Depth
        Maximum depth to traverse (default: 10).
    .PARAMETER IncludeForward
        Include assets derived from this asset (descendants).
    .PARAMETER Direction
        Direction to traverse (backward=ancestors, forward=descendants, both).
    .PARAMETER ProjectRoot
        Project root directory.
    .OUTPUTS
        System.Collections.Hashtable with provenance chain.
    .EXAMPLE
        $chain = Get-ProvenanceChain -AssetId "char-mesh-001" -Depth 5
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AssetId,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$Depth = 10,

        [Parameter()]
        [switch]$IncludeForward,

        [Parameter()]
        [ValidateSet('backward', 'forward', 'both')]
        [string]$Direction = 'backward',

        [Parameter()]
        [string]$ProjectRoot = '.'
    )

    $result = @{
        assetId = $AssetId
        success = $true
        depth = $Depth
        direction = $Direction
        chain = @()
        nodes = @{}
        edges = @()
        statistics = @{}
        errors = @()
        queriedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    try {
        Write-Verbose "[Provenance] Querying chain for $AssetId (depth: $Depth, direction: $Direction)"

        $visited = [System.Collections.Generic.HashSet[string]]::new()
        $queue = [System.Collections.Generic.Queue[object]]::new()
        
        # Load all provenance records
        $allRecords = Get-AllProvenanceRecords -ProjectRoot $ProjectRoot
        
        # Build asset index for lookups
        $assetIndex = @{}
        foreach ($record in $allRecords) {
            if (-not $assetIndex.ContainsKey($record.asset.id)) {
                $assetIndex[$record.asset.id] = @()
            }
            $assetIndex[$record.asset.id] += $record
        }

        # Start traversal
        $queue.Enqueue(@{ assetId = $AssetId; depth = 0; direction = 'backward' })
        if ($Direction -in @('forward', 'both')) {
            $queue.Enqueue(@{ assetId = $AssetId; depth = 0; direction = 'forward' })
        }

        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()
            $currentAssetId = $current.assetId
            $currentDepth = $current.depth
            $currentDirection = $current.direction

            # Skip if already visited at equal or lower depth
            $visitKey = "$currentAssetId-$currentDirection"
            if ($visited.Contains($visitKey)) { continue }
            if ($currentDepth -gt $Depth) { continue }
            
            [void]$visited.Add($visitKey)

            # Find records for this asset
            $records = if ($assetIndex.ContainsKey($currentAssetId)) { $assetIndex[$currentAssetId] } else { @() }

            # Add node to graph
            if (-not $result.nodes.ContainsKey($currentAssetId)) {
                $assetRecords = $records | Select-Object -First 1
                $result.nodes[$currentAssetId] = @{
                    id = $currentAssetId
                    type = if ($assetRecords) { $assetRecords.asset.type } else { 'unknown' }
                    depth = $currentDepth
                    records = $records
                }
            }

            # Process records
            foreach ($record in $records) {
                $chainEntry = @{
                    assetId = $currentAssetId
                    provenanceId = $record.provenanceId
                    operation = $record.activity.type
                    timestamp = $record.activity.startedAt
                    agent = $record.agent.name
                    depth = $currentDepth
                }
                $result.chain += $chainEntry

                # Traverse based on direction
                if ($currentDirection -eq 'backward') {
                    # Follow wasDerivedFrom (ancestors)
                    foreach ($sourceRef in $record.wasDerivedFrom) {
                        $sourceId = $sourceRef.entity
                        if (-not [string]::IsNullOrEmpty($sourceId)) {
                            $result.edges += @{
                                from = $sourceId
                                to = $currentAssetId
                                relation = 'wasDerivedFrom'
                                operation = $record.activity.type
                            }
                            $queue.Enqueue(@{
                                assetId = $sourceId
                                depth = $currentDepth + 1
                                direction = 'backward'
                            })
                        }
                    }
                }
                else {
                    # Find records where this asset is a source (descendants)
                    foreach ($otherRecord in $allRecords) {
                        foreach ($derivedFrom in $otherRecord.wasDerivedFrom) {
                            if ($derivedFrom.entity -eq $currentAssetId) {
                                $descendantId = $otherRecord.asset.id
                                $result.edges += @{
                                    from = $currentAssetId
                                    to = $descendantId
                                    relation = 'wasDerivedFrom'
                                    operation = $otherRecord.activity.type
                                }
                                $queue.Enqueue(@{
                                    assetId = $descendantId
                                    depth = $currentDepth + 1
                                    direction = 'forward'
                                })
                            }
                        }
                    }
                }
            }
        }

        # Calculate statistics
        $result.statistics = @{
            totalNodes = $result.nodes.Count
            totalEdges = $result.edges.Count
            maxDepth = ($result.chain | Measure-Object -Property depth -Maximum).Maximum
            uniqueOperations = ($result.chain | Select-Object -Property operation -Unique | Measure-Object).Count
            operations = $result.chain | Group-Object -Property operation | ForEach-Object { @{ $_.Name = $_.Count } }
        }

        Write-Verbose "[Provenance] Chain query complete. Nodes: $($result.statistics.totalNodes), Edges: $($result.statistics.totalEdges)"
    }
    catch {
        $result.success = $false
        $result.errors += $_.Exception.Message
        Write-Warning "[Provenance] Chain query failed: $_"
    }

    return $result
}

#===============================================================================
# Export Provenance Graph
#===============================================================================

function Export-ProvenanceGraph {
    <#
    .SYNOPSIS
        Exports provenance data as a graph for visualization.
    .DESCRIPTION
        Generates graph representations of asset provenance in various formats:
        Mermaid, Graphviz DOT, Cypher (Neo4j), JSON-LD.
    .PARAMETER AssetId
        Root asset ID for the graph.
    .PARAMETER Format
        Export format (mermaid, dot, cypher, json, jsonld).
    .PARAMETER OutputPath
        Output file path.
    .PARAMETER Depth
        Maximum depth to include.
    .PARAMETER IncludeMetadata
        Include metadata in graph nodes.
    .PARAMETER StyleConfig
        Graph styling configuration.
    .PARAMETER ProjectRoot
        Project root directory.
    .OUTPUTS
        System.Collections.Hashtable with export results.
    .EXAMPLE
        Export-ProvenanceGraph -AssetId "char-mesh-001" -Format "mermaid" -OutputPath "./lineage.md"
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AssetId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('mermaid', 'dot', 'cypher', 'json', 'jsonld')]
        [string]$Format,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$Depth = 10,

        [Parameter()]
        [switch]$IncludeMetadata,

        [Parameter()]
        [hashtable]$StyleConfig = @{},

        [Parameter()]
        [string]$ProjectRoot = '.'
    )

    $result = @{
        success = $false
        assetId = $AssetId
        format = $Format
        outputPath = $OutputPath
        fileSize = 0
        nodeCount = 0
        edgeCount = 0
        errors = @()
        startedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        completedAt = $null
    }

    try {
        Write-Verbose "[Provenance] Exporting graph for $AssetId as $Format..."

        # Get provenance chain
        $chain = Get-ProvenanceChain -AssetId $AssetId -Depth $Depth -Direction 'both' -ProjectRoot $ProjectRoot
        
        if (-not $chain.success) {
            throw "Failed to retrieve provenance chain: $($chain.errors -join ', ')"
        }

        $result.nodeCount = $chain.statistics.totalNodes
        $result.edgeCount = $chain.statistics.totalEdges

        # Generate graph in requested format
        $graphContent = switch ($Format) {
            'mermaid' { ConvertTo-MermaidGraph -Chain $chain -StyleConfig $StyleConfig -IncludeMetadata $IncludeMetadata }
            'dot' { ConvertTo-DotGraph -Chain $chain -StyleConfig $StyleConfig -IncludeMetadata $IncludeMetadata }
            'cypher' { ConvertTo-CypherGraph -Chain $chain }
            'json' { $chain | ConvertTo-Json -Depth 10 }
            'jsonld' { ConvertTo-JsonLdGraph -Chain $chain }
        }

        # Ensure output directory exists
        $outputDir = Split-Path -Parent $OutputPath
        if (-not (Test-Path -LiteralPath $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        # Write output
        if ($graphContent -is [string]) {
            $graphContent | Out-File -FilePath $OutputPath -Encoding UTF8
        }
        else {
            $graphContent | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
        }

        $result.fileSize = (Get-Item -LiteralPath $OutputPath).Length
        $result.success = $true

        Write-Verbose "[Provenance] Graph exported: $OutputPath"
    }
    catch {
        $result.success = $false
        $result.errors += $_.Exception.Message
        Write-Warning "[Provenance] Graph export failed: $_"
    }

    $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    return $result
}

#===============================================================================
# Query Functions
#===============================================================================

function Find-AssetsByProvenance {
    <#
    .SYNOPSIS
        Finds assets based on provenance criteria.
    .DESCRIPTION
        Queries assets by source pack, operation type, agent, or time range.
    .PARAMETER SourcePack
        Filter by source pack.
    .PARAMETER Operation
        Filter by operation type.
    .PARAMETER Agent
        Filter by agent name.
    .PARAMETER FromDate
        Start date for time range.
    .PARAMETER ToDate
        End date for time range.
    .PARAMETER AssetType
        Filter by asset type.
    .PARAMETER ProjectRoot
        Project root directory.
    .OUTPUTS
        Array of matching asset records.
    .EXAMPLE
        Find-AssetsByProvenance -SourcePack "blender-engine" -Operation "export"
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$SourcePack = '',

        [Parameter()]
        [string]$Operation = '',

        [Parameter()]
        [string]$Agent = '',

        [Parameter()]
        [DateTime]$FromDate,

        [Parameter()]
        [DateTime]$ToDate,

        [Parameter()]
        [string]$AssetType = '',

        [Parameter()]
        [string]$ProjectRoot = '.'
    )

    $results = @()

    try {
        $allRecords = Get-AllProvenanceRecords -ProjectRoot $ProjectRoot

        foreach ($record in $allRecords) {
            $match = $true

            if ($SourcePack -and ($record.packFlow.sources -notcontains $SourcePack -and $record.packFlow.target -ne $SourcePack)) {
                $match = $false
            }
            if ($Operation -and $record.activity.type -ne $Operation) {
                $match = $false
            }
            if ($Agent -and $record.agent.name -ne $Agent) {
                $match = $false
            }
            if ($AssetType -and $record.asset.type -ne $AssetType) {
                $match = $false
            }

            $recordDate = [DateTime]::Parse($record.activity.startedAt)
            if ($FromDate -and $recordDate -lt $FromDate) {
                $match = $false
            }
            if ($ToDate -and $recordDate -gt $ToDate) {
                $match = $false
            }

            if ($match) {
                $results += $record
            }
        }
    }
    catch {
        Write-Warning "[Provenance] Query failed: $_"
    }

    return $results
}

function Get-ProvenanceStatistics {
    <#
    .SYNOPSIS
        Gets statistics about provenance records.
    .DESCRIPTION
        Returns aggregate statistics about asset transformations,
        pack flows, and operation types.
    .PARAMETER ProjectRoot
        Project root directory.
    .OUTPUTS
        System.Collections.Hashtable with statistics.
    .EXAMPLE
        $stats = Get-ProvenanceStatistics
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$ProjectRoot = '.'
    )

    $records = Get-AllProvenanceRecords -ProjectRoot $ProjectRoot

    $stats = @{
        totalRecords = $records.Count
        uniqueAssets = ($records | Select-Object -ExpandProperty asset -Property id | Select-Object -Property id -Unique | Measure-Object).Count
        operations = @{}
        assetTypes = @{}
        packFlows = @{}
        agents = @{}
        timeRange = @{
            earliest = $null
            latest = $null
        }
    }

    foreach ($record in $records) {
        # Operation counts
        $op = $record.activity.type
        if (-not $stats.operations.ContainsKey($op)) {
            $stats.operations[$op] = 0
        }
        $stats.operations[$op]++

        # Asset type counts
        $type = $record.asset.type
        if (-not $stats.assetTypes.ContainsKey($type)) {
            $stats.assetTypes[$type] = 0
        }
        $stats.assetTypes[$type]++

        # Pack flows
        $sourcePack = $record.packFlow.sources | Select-Object -First 1
        $targetPack = $record.packFlow.target
        if ($sourcePack -and $targetPack) {
            $flow = "$sourcePack -> $targetPack"
            if (-not $stats.packFlows.ContainsKey($flow)) {
                $stats.packFlows[$flow] = 0
            }
            $stats.packFlows[$flow]++
        }

        # Agents
        $agent = $record.agent.name
        if (-not $stats.agents.ContainsKey($agent)) {
            $stats.agents[$agent] = 0
        }
        $stats.agents[$agent]++

        # Time range
        $recordTime = [DateTime]::Parse($record.activity.startedAt)
        if (-not $stats.timeRange.earliest -or $recordTime -lt $stats.timeRange.earliest) {
            $stats.timeRange.earliest = $recordTime
        }
        if (-not $stats.timeRange.latest -or $recordTime -gt $stats.timeRange.latest) {
            $stats.timeRange.latest = $recordTime
        }
    }

    return $stats
}

#===============================================================================
# Helper Functions
#===============================================================================

function Get-AllProvenanceRecords {
    param(
        [string]$ProjectRoot = '.'
    )

    $provDir = Join-Path $ProjectRoot $script:ProvDirectory
    $records = @()

    if (-not (Test-Path -LiteralPath $provDir)) {
        return $records
    }

    $files = Get-ChildItem -Path $provDir -Filter "prov-*.json" -File -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        try {
            $record = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable
            $records += $record
        }
        catch {
            Write-Verbose "Failed to load provenance file: $($file.Name)"
        }
    }

    return $records
}

function Update-ProvenanceIndex {
    param(
        [hashtable]$Record,
        [string]$ProjectRoot = '.'
    )

    $indexPath = Join-Path $ProjectRoot $script:ProvIndexFile
    $index = @{}

    if (Test-Path -LiteralPath $indexPath) {
        try {
            $index = Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json -AsHashtable
        }
        catch {
            $index = @{}
        }
    }

    if (-not $index.ContainsKey('assets')) {
        $index['assets'] = @{}
    }

    $assetId = $Record.asset.id
    if (-not $index.assets.ContainsKey($assetId)) {
        $index.assets[$assetId] = @{
            provenanceIds = @()
            lastUpdated = $null
        }
    }

    $index.assets[$assetId].provenanceIds += $Record.provenanceId
    $index.assets[$assetId].lastUpdated = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $index.lastUpdated = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Ensure directory exists
    $indexDir = Split-Path -Parent $indexPath
    if (-not (Test-Path -LiteralPath $indexDir)) {
        New-Item -ItemType Directory -Path $indexDir -Force | Out-Null
    }

    $index | ConvertTo-Json -Depth 10 | Out-File -FilePath $indexPath -Encoding UTF8
}

function ConvertTo-MermaidGraph {
    param($Chain, $StyleConfig, $IncludeMetadata)

    $lines = @()
    $lines += "```mermaid"
    $lines += "graph TD"
    $lines += "    %% Provenance Graph for $($Chain.assetId)"
    $lines += "    %% Generated: $([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss'))"
    $lines += ""

    # Node styles by type
    $nodeStyles = @{
        mesh = 'fill:#4a90d9,stroke:#2c5aa0'
        texture = 'fill:#5cb85c,stroke:#449d44'
        material = 'fill:#f0ad4e,stroke:#ec971f'
        animation = 'fill:#d9534f,stroke:#c9302c'
        audio = 'fill:#9b59b6,stroke:#8e44ad'
        script = 'fill:#34495e,stroke:#2c3e50'
        'ai-model' = 'fill:#e74c3c,stroke:#c0392b'
    }

    # Define nodes
    foreach ($nodeId in $Chain.nodes.Keys) {
        $node = $Chain.nodes[$nodeId]
        $style = if ($nodeStyles.ContainsKey($node.type)) { $nodeStyles[$node.type] } else { 'fill:#95a5a6,stroke:#7f8c8d' }
        $displayLabel = if ($nodeId.Length -gt 20) { $nodeId.Substring(0, 17) + "..." } else { $nodeId }
        $lines += "    $nodeId([`"$displayLabel`"]):::$($node.type)"
    }

    $lines += ""

    # Define edges
    foreach ($edge in $Chain.edges) {
        $label = $edge.operation
        $lines += "    $($edge.from) -->|$label| $($edge.to)"
    }

    $lines += ""

    # Style classes
    foreach ($type in $nodeStyles.Keys) {
        $lines += "    classDef $type $($nodeStyles[$type])"
    }

    $lines += "```"

    return ($lines -join "`n")
}

function ConvertTo-DotGraph {
    param($Chain, $StyleConfig, $IncludeMetadata)

    $lines = @()
    $lines += "digraph ProvenanceGraph {"
    $lines += "    rankdir=TB;"
    $lines += "    node [shape=box, style=filled, fontname=Arial];"
    $lines += "    edge [fontname=Arial, fontsize=10];"
    $lines += ""
    $lines += "    label=`"Provenance Graph for $($Chain.assetId)`";"
    $lines += "    labelloc=`"t`";"
    $lines += ""

    # Node colors by type
    $nodeColors = @{
        mesh = '#4a90d9'
        texture = '#5cb85c'
        material = '#f0ad4e'
        animation = '#d9534f'
        audio = '#9b59b6'
        script = '#34495e'
        'ai-model' = '#e74c3c'
    }

    # Define nodes
    foreach ($nodeId in $Chain.nodes.Keys) {
        $node = $Chain.nodes[$nodeId]
        $color = if ($nodeColors.ContainsKey($node.type)) { $nodeColors[$node.type] } else { '#95a5a6' }
        $lines += "    `"$nodeId`" [fillcolor=`"$color`", label=`"$nodeId`"];"
    }

    $lines += ""

    # Define edges
    foreach ($edge in $Chain.edges) {
        $label = $edge.operation
        $lines += "    `"$($edge.from)`" -> `"$($edge.to)`" [label=`"$label`"];"
    }

    $lines += "}"

    return ($lines -join "`n")
}

function ConvertTo-CypherGraph {
    param($Chain)

    $lines = @()
    $lines += "// Provenance Graph for $($Chain.assetId)"
    $lines += "// Generated: $([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss'))"
    $lines += ""

    # Create nodes
    foreach ($nodeId in $Chain.nodes.Keys) {
        $node = $Chain.nodes[$nodeId]
        $lines += "CREATE (a$($nodeId -replace '[^a-zA-Z0-9]', '_'):Asset {id: '$nodeId', type: '$($node.type)'})"
    }

    $lines += ""

    # Create relationships
    $edgeIndex = 0
    foreach ($edge in $Chain.edges) {
        $fromId = $edge.from -replace '[^a-zA-Z0-9]', '_'
        $toId = $edge.to -replace '[^a-zA-Z0-9]', '_'
        $lines += "CREATE (a$fromId)-[:DERIVED_FROM {operation: '$($edge.operation)'}]->(a$toId)"
        $edgeIndex++
    }

    return ($lines -join "`n")
}

function ConvertTo-JsonLdGraph {
    param($Chain)

    $context = @{
        prov = 'http://www.w3.org/ns/prov#'
        xsd = 'http://www.w3.org/2001/XMLSchema#'
        llmwf = 'https://llm-workflow.org/ns/prov/'
        id = '@id'
        type = '@type'
    }

    $graph = @()

    # Add entities (assets)
    foreach ($nodeId in $Chain.nodes.Keys) {
        $node = $Chain.nodes[$nodeId]
        $entity = @{
            id = "urn:llm-workflow:asset:$nodeId"
            type = @('prov:Entity', "llmwf:$($node.type)")
            'llmwf:assetId' = $nodeId
            'llmwf:assetType' = $node.type
        }
        $graph += $entity
    }

    # Add activities and relations
    $activityIndex = 0
    foreach ($edge in $Chain.edges) {
        $activityId = "urn:llm-workflow:activity:$activityIndex"
        
        $activity = @{
            id = $activityId
            type = 'prov:Activity'
            'prov:startedAtTime' = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        $graph += $activity

        $generation = @{
            type = 'prov:Generation'
            'prov:activity' = @{ id = $activityId }
            'prov:entity' = @{ id = "urn:llm-workflow:asset:$($edge.to)" }
        }
        $graph += $generation

        $usage = @{
            type = 'prov:Usage'
            'prov:activity' = @{ id = $activityId }
            'prov:entity' = @{ id = "urn:llm-workflow:asset:$($edge.from)" }
        }
        $graph += $usage

        $derivation = @{
            type = 'prov:Derivation'
            'prov:generatedEntity' = @{ id = "urn:llm-workflow:asset:$($edge.to)" }
            'prov:usedEntity' = @{ id = "urn:llm-workflow:asset:$($edge.from)" }
        }
        $graph += $derivation

        $activityIndex++
    }

    $jsonld = @{
        '@context' = $context
        '@graph' = $graph
    }

    return $jsonld
}

#===============================================================================
# Export Module Members
#===============================================================================

Export-ModuleMember -Function @(
    'New-ProvenanceRecord'
    'Get-ProvenanceChain'
    'Export-ProvenanceGraph'
    'Find-AssetsByProvenance'
    'Get-ProvenanceStatistics'
)
