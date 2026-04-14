#requires -Version 5.1
Set-StrictMode -Version Latest

#>
function Get-DialogueTrees {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('auto', 'dialogue_manager', 'json', 'gdscript')]
        [string]$Format = 'auto'
    )
    
    $result = if ($PSCmdlet.ParameterSetName -eq 'Path') {
        Extract-DialogueResources -Path $Path -Format $Format
    }
    else {
        Extract-DialogueResources -Content $Content -Format $Format
    }
    
    return $result.nodes
}


#>
function Get-ConversationFlows {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$DialogueNodes
    )
    
    $flows = @{
        linearPaths = @()
        branchPoints = @()
        endPoints = @()
        loops = @()
        totalNodes = $DialogueNodes.Count
        totalChoices = 0
        averageBranchingFactor = 0
        maxDepth = 0
    }
    
    $nodeDict = @{}
    foreach ($node in $DialogueNodes) {
        $nodeDict[$node.id] = $node
    }
    
    # Find branch points (nodes with choices)
    foreach ($node in $DialogueNodes) {
        if ($node.choices -and $node.choices.Count -gt 0) {
            $flows.branchPoints += @{
                nodeId = $node.id
                choiceCount = $node.choices.Count
                lineNumber = $node.lineNumber
            }
            $flows.totalChoices += $node.choices.Count
        }
        
        # Find end points
        if ($node.nextNode -eq 'END' -or (-not $node.nextNode -and (-not $node.choices -or $node.choices.Count -eq 0))) {
            $flows.endPoints += $node.id
        }
    }
    
    # Calculate average branching factor
    if ($flows.branchPoints.Count -gt 0) {
        $flows.averageBranchingFactor = $flows.totalChoices / $flows.branchPoints.Count
    }
    
    return $flows
}


#>
function Get-ConditionChecks {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$DialogueNodes
    )
    
    $conditions = @()
    
    foreach ($node in $DialogueNodes) {
        # Node-level conditions
        foreach ($cond in $node.conditions) {
            $conditions += @{
                nodeId = $node.id
                condition = $cond.condition
                type = $cond.type
                lineNumber = $cond.lineNumber
                context = 'node'
            }
        }
        
        # Choice-level conditions
        foreach ($choice in $node.choices) {
            if ($choice.condition) {
                $conditions += @{
                    nodeId = $node.id
                    choiceText = $choice.text
                    condition = $choice.condition
                    type = 'choice'
                    lineNumber = $choice.lineNumber
                    context = 'choice'
                }
            }
        }
    }
    
    return $conditions
}


#>
function Get-LocalizationPatterns {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Nodes')]
        [array]$DialogueNodes
    )
    
    try {
        $sourceFile = 'inline'
        
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return $null
            }
            $sourceFile = $Path
            $resources = Extract-DialogueResources -Path $Path
            $DialogueNodes = $resources.nodes
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Content') {
            $resources = Extract-DialogueResources -Content $Content
            $DialogueNodes = $resources.nodes
        }
        
        $localization = @{
            hasExplicitKeys = $false
            translationKeys = @()
            variablesUsed = @()
            bbcodeUsed = @()
            characterNames = @()
            suggestedKeys = @()
        }
        
        foreach ($node in $DialogueNodes) {
            # Collect translation keys
            if ($node.translationKey) {
                $localization.hasExplicitKeys = $true
                $localization.translationKeys += $node.translationKey
            }
            elseif ($node.character -and $node.text) {
                $suggestedKey = "$($node.character.ToUpper())_$($node.lineNumber)"
                $localization.suggestedKeys += @{
                    nodeId = $node.id
                    suggestedKey = $suggestedKey
                    originalText = $node.text.Substring(0, [Math]::Min(50, $node.text.Length))
                }
            }
            
            # Collect variables
            if ($node.variables) {
                $localization.variablesUsed += $node.variables
            }
            
            # Collect BBCode
            if ($node.bbcode) {
                foreach ($tag in $node.bbcode) {
                    $localization.bbcodeUsed += $tag.type
                }
            }
            
            # Collect character names
            if ($node.character) {
                $localization.characterNames += $node.character
            }
        }
        
        # Make unique
        $localization.translationKeys = $localization.translationKeys | Select-Object -Unique
        $localization.variablesUsed = $localization.variablesUsed | Select-Object -Unique
        $localization.bbcodeUsed = $localization.bbcodeUsed | Select-Object -Unique
        $localization.characterNames = $localization.characterNames | Select-Object -Unique
        
        return $localization
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract localization patterns: $_"
        return $null
    }
}


#>
function Get-DialogueGraph {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Resources')]
        [hashtable]$Resources,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Nodes')]
        [array]$Nodes,
        
        [Parameter(ParameterSetName = 'Nodes')]
        [array]$Connections = @()
    )
    
    try {
        $sourceFile = 'inline'
        $nodes = @()
        $connections = @()
        
        switch ($PSCmdlet.ParameterSetName) {
            'Path' {
                $resources = Extract-DialogueResources -Path $Path
                $sourceFile = $resources.metadata.sourceFile
                $nodes = $resources.nodes
                $connections = $resources.connections
            }
            'Content' {
                $resources = Extract-DialogueResources -Content $Content
                $sourceFile = $resources.metadata.sourceFile
                $nodes = $resources.nodes
                $connections = $resources.connections
            }
            'Resources' {
                $nodes = $Resources.nodes
                $connections = $Resources.connections
                $sourceFile = $Resources.metadata.sourceFile
            }
            'Nodes' {
                $nodes = $Nodes
                $connections = $Connections
            }
        }
        
        if ($nodes.Count -eq 0) {
            return @{
                graph = $null
                nodes = @()
                edges = @()
                entryPoints = @()
                exitPoints = @()
                cycles = @()
                longestPath = @()
                unreachableNodes = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            }
        }
        
        # Build adjacency list
        $adjacency = @{}
        $reverseAdjacency = @{}
        $nodeDict = @{}
        
        foreach ($node in $nodes) {
            $adjacency[$node.id] = @()
            $reverseAdjacency[$node.id] = @()
            $nodeDict[$node.id] = $node
        }
        
        foreach ($conn in $connections) {
            if ($adjacency.ContainsKey($conn.from)) {
                $adjacency[$conn.from] += $conn.to
            }
            if ($reverseAdjacency.ContainsKey($conn.to)) {
                $reverseAdjacency[$conn.to] += $conn.from
            }
        }
        
        # Find entry points (nodes with no incoming edges)
        $entryPoints = @()
        foreach ($nodeId in $nodeDict.Keys) {
            if ($reverseAdjacency[$nodeId].Count -eq 0) {
                $entryPoints += $nodeId
            }
        }
        
        # If no entry points found, use first node or title nodes
        if ($entryPoints.Count -eq 0) {
            $titleNodes = $nodes | Where-Object { $_.type -eq 'title' -or $_.type -eq 'label' }
            if ($titleNodes.Count -gt 0) {
                $entryPoints = $titleNodes | Select-Object -ExpandProperty id
            }
            else {
                $entryPoints = @($nodes[0].id)
            }
        }
        
        # Find exit points (nodes with no outgoing edges)
        $exitPoints = @()
        foreach ($nodeId in $nodeDict.Keys) {
            if ($adjacency[$nodeId].Count -eq 0) {
                $exitPoints += $nodeId
            }
        }
        
        # DFS to find cycles and compute depths
        $visited = @{}
        $recursionStack = @{}
        $cycles = @()
        $nodeDepths = @{}
        $maxDepth = 0
        $deepestNode = $null
        
        function Test-Cycle {
            param([string]$nodeId, [int]$depth, [array]$path)
            
            $visited[$nodeId] = $true
            $recursionStack[$nodeId] = $true
            
            if (-not $nodeDepths.ContainsKey($nodeId) -or $nodeDepths[$nodeId] -lt $depth) {
                $nodeDepths[$nodeId] = $depth
                if ($depth -gt $maxDepth) {
                    $maxDepth = $depth
                    $deepestNode = $nodeId
                }
            }
            
            $currentPath = $path + @($nodeId)
            
            foreach ($neighbor in $adjacency[$nodeId]) {
                if (-not $visited.ContainsKey($neighbor) -or -not $visited[$neighbor]) {
                    Test-Cycle -nodeId $neighbor -depth ($depth + 1) -path $currentPath
                }
                elseif ($recursionStack.ContainsKey($neighbor) -and $recursionStack[$neighbor]) {
                    # Cycle detected
                    $cycleStart = $currentPath.IndexOf($neighbor)
                    $cycle = $currentPath[$cycleStart..($currentPath.Count - 1)]
                    $cycles += @{
                        nodes = $cycle
                        length = $cycle.Count
                    }
                }
            }
            
            $recursionStack[$nodeId] = $false
        }
        
        foreach ($entry in $entryPoints) {
            $visited.Clear()
            $recursionStack.Clear()
            Test-Cycle -nodeId $entry -depth 0 -path @()
        }
        
        # Find unreachable nodes
        $reachable = @{}
        foreach ($entry in $entryPoints) {
            $stack = [System.Collections.Generic.Stack[string]]::new()
            $stack.Push($entry)
            
            while ($stack.Count -gt 0) {
                $current = $stack.Pop()
                if ($reachable.ContainsKey($current)) { continue }
                $reachable[$current] = $true
                
                foreach ($neighbor in $adjacency[$current]) {
                    if (-not $reachable.ContainsKey($neighbor)) {
                        $stack.Push($neighbor)
                    }
                }
            }
        }
        
        $unreachableNodes = $nodeDict.Keys | Where-Object { -not $reachable.ContainsKey($_) }
        
        # Build longest path
        $longestPath = @()
        if ($deepestNode) {
            $current = $deepestNode
            $path = @($current)
            $safety = 0
            while ($safety -lt 1000) {
                $safety++
                $minDepth = $nodeDepths[$current]
                $prevNode = $null
                foreach ($potential in $reverseAdjacency[$current]) {
                    if ($nodeDepths.ContainsKey($potential) -and $nodeDepths[$potential] -lt $minDepth) {
                        $minDepth = $nodeDepths[$potential]
                        $prevNode = $potential
                    }
                }
                if ($prevNode) {
                    $path = @($prevNode) + $path
                    $current = $prevNode
                }
                else {
                    break
                }
            }
            $longestPath = $path
        }
        
        # Build graph nodes with metadata
        $graphNodes = @()
        foreach ($node in $nodes) {
            $graphNode = @{
                id = $node.id
                type = $node.type
                depth = if ($nodeDepths.ContainsKey($node.id)) { $nodeDepths[$node.id] } else { -1 }
                isEntry = $entryPoints -contains $node.id
                isExit = $exitPoints -contains $node.id
                isReachable = $reachable.ContainsKey($node.id)
                incomingCount = $reverseAdjacency[$node.id].Count
                outgoingCount = $adjacency[$node.id].Count
            }
            $graphNodes += $graphNode
        }
        
        # Calculate average branching factor
        $avgBranching = 0
        if ($graphNodes.Count -gt 0) {
            $totalOutgoing = 0
            foreach ($gn in $graphNodes) {
                $totalOutgoing += $gn.outgoingCount
            }
            $avgBranching = $totalOutgoing / $graphNodes.Count
        }
        
        return @{
            graph = @{
                nodeCount = $nodes.Count
                edgeCount = $connections.Count
                entryPointCount = $entryPoints.Count
                exitPointCount = $exitPoints.Count
                cycleCount = $cycles.Count
                maxDepth = $maxDepth
                averageBranchingFactor = [Math]::Round($avgBranching, 2)
            }
            nodes = $graphNodes
            edges = $connections
            entryPoints = $entryPoints
            exitPoints = $exitPoints
            cycles = $cycles
            longestPath = $longestPath
            unreachableNodes = @($unreachableNodes)
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to build dialogue graph: $_"
        return @{
            graph = $null
            nodes = @()
            edges = @()
            entryPoints = @()
            exitPoints = @()
            cycles = @()
            longestPath = @()
            unreachableNodes = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
        }
    }
}


#>
function Get-DialogueMetrics {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Resources')]
        [hashtable]$Resources,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Graph')]
        [hashtable]$Graph
    )
    
    try {
        $sourceFile = 'inline'
        $nodes = @()
        $graph = $null
        $connections = @()
        $characters = @()
        $variables = @()
        
        switch ($PSCmdlet.ParameterSetName) {
            'Path' {
                $resources = Extract-DialogueResources -Path $Path
                $sourceFile = $resources.metadata.sourceFile
                $nodes = $resources.nodes
                $connections = $resources.connections
                $graph = Get-DialogueGraph -Nodes $nodes -Connections $connections
                $charData = Extract-DialogueCharacters -Resources $resources
                $characters = $charData.characters
                $varData = Export-DialogueVariables -Resources $resources
                $variables = $varData.variables
            }
            'Content' {
                $resources = Extract-DialogueResources -Content $Content
                $sourceFile = $resources.metadata.sourceFile
                $nodes = $resources.nodes
                $connections = $resources.connections
                $graph = Get-DialogueGraph -Nodes $nodes -Connections $connections
                $charData = Extract-DialogueCharacters -Resources $resources
                $characters = $charData.characters
                $varData = Export-DialogueVariables -Resources $resources
                $variables = $varData.variables
            }
            'Resources' {
                $nodes = $Resources.nodes
                $connections = $Resources.connections
                $graph = Get-DialogueGraph -Nodes $nodes -Connections $connections
                $sourceFile = $Resources.metadata.sourceFile
            }
            'Graph' {
                $graph = $Graph
                $sourceFile = 'graph_input'
            }
        }
        
        # Calculate basic metrics
        $totalNodes = $nodes.Count
        $dialogueNodes = $nodes | Where-Object { $_.type -eq 'dialogue' }
        $choiceNodes = $nodes | Where-Object { $_.choices -and $_.choices.Count -gt 0 }
        $conditionNodes = $nodes | Where-Object { $_.conditions -and $_.conditions.Count -gt 0 }
        $actionNodes = $nodes | Where-Object { $_.actions -and $_.actions.Count -gt 0 }
        
        # Calculate text metrics
        $totalTextLength = 0
        $wordCount = 0
        $lineCount = 0
        foreach ($node in $dialogueNodes) {
            if ($node.text) {
                $totalTextLength += $node.text.Length
                $wordCount += ($node.text -split '\s+').Count
                $lineCount++
            }
        }
        
        # Calculate branch metrics
        $branchCount = if ($choiceNodes) { $choiceNodes.Count } else { 0 }
        $totalChoices = 0
        if ($choiceNodes) {
            foreach ($cn in $choiceNodes) {
                if ($cn.choices) { $totalChoices += $cn.choices.Count }
            }
        }
        $averageChoicesPerBranch = if ($branchCount -gt 0) { $totalChoices / $branchCount } else { 0 }
        
        # Calculate complexity score (0-100)
        $complexityScore = 0
        if ($totalNodes -gt 0) {
            $branchComplexity = [Math]::Min(50, ($branchCount / $totalNodes) * 100)
            $conditionComplexity = [Math]::Min(30, ($conditionNodes.Count / $totalNodes) * 100)
            $variableComplexity = [Math]::Min(20, ($variables.Count / [Math]::Max(1, $totalNodes)) * 100)
            $complexityScore = $branchComplexity + $conditionComplexity + $variableComplexity
        }
        
        # Calculate depth metrics
        $maxDepth = if ($graph -and $graph.graph) { $graph.graph.maxDepth } else { 0 }
        $averageDepth = 0
        if ($graph -and $graph.nodes) {
            $depthNodes = $graph.nodes | Where-Object { $_.depth -ge 0 }
            if ($depthNodes) {
                $totalDepth = 0
                $count = 0
                foreach ($dn in $depthNodes) {
                    $totalDepth += $dn.depth
                    $count++
                }
                if ($count -gt 0) { $averageDepth = $totalDepth / $count }
            }
        }
        
        # Translation coverage
        $nodesWithTranslationKeys = @($nodes | Where-Object { $_.translationKey })
        $dialogueNodeCount = if ($dialogueNodes) { $dialogueNodes.Count } else { 0 }
        $translationCoverage = if ($dialogueNodeCount -gt 0) { 
            ($nodesWithTranslationKeys.Count / $dialogueNodeCount) * 100 
        } else { 0 }
        
        # Character balance
        $characterParticipation = @{}
        foreach ($char in $characters) {
            $characterParticipation[$char.name] = @{
                name = $char.name
                lineCount = $char.lineCount
                percentage = if ($lineCount -gt 0) { ($char.lineCount / $lineCount) * 100 } else { 0 }
            }
        }
        
        # Variable density
        $variableDensity = if ($totalNodes -gt 0) { $variables.Count / $totalNodes } else { 0 }
        
        # Quality indicators
        $unreachableCount = if ($graph -and $graph.unreachableNodes) { $graph.unreachableNodes.Count } else { 0 }
        $cycleCount = if ($graph -and $graph.cycles) { $graph.cycles.Count } else { 0 }
        $deadEndCount = if ($graph) { $graph.exitPoints.Count } else { 0 }
        
        $qualityScore = 100
        if ($totalNodes -gt 0) {
            $qualityScore -= ($unreachableCount / $totalNodes) * 20  # Penalty for unreachable nodes
            $qualityScore -= [Math]::Min(20, $cycleCount * 5)  # Penalty for cycles
            $qualityScore -= (100 - $translationCoverage) * 0.2  # Penalty for missing translations
        }
        $qualityScore = [Math]::Max(0, [Math]::Min(100, $qualityScore))
        
        return @{
            metrics = @{
                totalNodes = $totalNodes
                dialogueNodes = $dialogueNodes.Count
                choiceNodes = $choiceNodes.Count
                conditionNodes = $conditionNodes.Count
                actionNodes = $actionNodes.Count
                characterCount = $characters.Count
                variableCount = $variables.Count
                branchCount = $branchCount
                totalChoices = $totalChoices
                averageChoicesPerBranch = [Math]::Round($averageChoicesPerBranch, 2)
                maxDepth = $maxDepth
                averageDepth = [Math]::Round($averageDepth, 2)
                unreachableNodes = $unreachableCount
                cycleCount = $cycleCount
                deadEndCount = $deadEndCount
            }
            textMetrics = @{
                totalCharacters = $totalTextLength
                wordCount = $wordCount
                lineCount = $lineCount
                averageWordsPerLine = if ($lineCount -gt 0) { [Math]::Round($wordCount / $lineCount, 2) } else { 0 }
                averageCharactersPerLine = if ($lineCount -gt 0) { [Math]::Round($totalTextLength / $lineCount, 2) } else { 0 }
            }
            complexity = @{
                overallScore = [Math]::Round($complexityScore, 2)
                branchComplexity = if ($totalNodes -gt 0) { [Math]::Round(($branchCount / $totalNodes) * 100, 2) } else { 0 }
                conditionComplexity = if ($totalNodes -gt 0) { [Math]::Round(($conditionNodes.Count / $totalNodes) * 100, 2) } else { 0 }
                variableDensity = [Math]::Round($variableDensity, 2)
            }
            coverage = @{
                translationCoveragePercent = [Math]::Round($translationCoverage, 2)
                nodesWithTranslations = $nodesWithTranslationKeys.Count
                totalTranslatableNodes = $dialogueNodes.Count
                characterParticipation = $characterParticipation
            }
            quality = @{
                overallScore = [Math]::Round($qualityScore, 2)
                hasUnreachableNodes = $unreachableCount -gt 0
                hasCycles = $cycleCount -gt 0
                hasDeadEnds = $deadEndCount -gt 0
                recommendations = @(
                    if ($unreachableCount -gt 0) { "Remove or connect $unreachableCount unreachable node(s)" }
                    if ($cycleCount -gt 0) { "Review $cycleCount cycle(s) for infinite loop potential" }
                    if ($translationCoverage -lt 100) { "Add translation keys for $(100 - [Math]::Round($translationCoverage, 0))% of dialogue" }
                )
            }
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to calculate dialogue metrics: $_"
        return @{
            metrics = @{}
            textMetrics = @{}
            complexity = @{}
            coverage = @{}
            quality = @{}
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
        }
    }
}


