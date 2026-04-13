#Requires -Version 5.1
<#
.SYNOPSIS
    Godot Dialogue System extractor for LLM Workflow Extraction Pipeline.

.DESCRIPTION
    Extracts structured dialogue data from Godot dialogue systems.
    Supports multiple dialogue frameworks including Dialogic (v1 and v2),
    DialogueQuest, and Godot Dialogue Manager.
    
    Extracts dialogue resources, characters, timelines, and variables from:
    - .dialogue files (Godot Dialogue Manager)
    - .dtl files (Dialogic timelines)
    - .json dialogue resources
    - .tres character definitions
    - .cfg or .json character configurations
    
    This parser implements Section 25.6 of the canonical architecture for the
    Godot Engine pack's structured extraction pipeline.

.REQUIRED FUNCTIONS
    - Extract-DialogueResources: Extract dialogue resource files
    - Extract-DialogueCharacters: Extract character definitions
    - Extract-DialogueTimelines: Extract dialogue timeline structures
    - Extract-DialogueVariables: Extract variable/state definitions

.PARAMETER Path
    Path to the dialogue file to parse.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER Format
    Format of the dialogue file (auto, dialogue_manager, dialogic, dialogue_quest, json).

.OUTPUTS
    JSON with dialogue trees, character mappings, variable schemas,
    and provenance metadata (source file, extraction timestamp, parser version).

.NOTES
    File Name      : GodotDialogueExtractor.ps1
    Author         : LLM Workflow Team
    Version        : 2.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Pack           : godot-engine
#>

Set-StrictMode -Version Latest

# ============================================================================
# Module Constants and Version
# ============================================================================

$script:ParserVersion = '2.0.0'
$script:ParserName = 'GodotDialogueExtractor'

# Supported file formats
$script:SupportedFormats = @('auto', 'dialogue_manager', 'dialogic', 'dialogue_quest', 'json', 'gdscript')

# Regex Patterns for Dialogue Parsing
$script:DialoguePatterns = @{
    # Godot Dialogue Manager patterns
    DialogueCharacter = '^\s*-\s*(?<char>\w+)\s*:\s*(?<text>.*)$'
    DialogueResponse = '^\s*=>\s*(?<target>\w+)\s*$'
    DialogueGoto = '^\s*=>\s*<(?<target>[^>]+)>'
    DialogueTitle = '^\s*~\s*(?<title>\w+)\s*$'
    DialogueCondition = '^\s*if\s+(?<cond>[^:]+):'
    DialogueElse = '^\s*else\s*:'
    DialogueSet = '^\s*set\s+(?<var>\w+)\s*=\s*(?<val>.+)'
    DialogueDo = '^\s*do\s+(?<action>.+)'
    DialogueJump = '^\s*jump\s+(?<target>\w+)'
    DialogueEnd = '^\s*end'
    
    # Dialogic patterns (.dtl files)
    DialogicCharacter = '^\s*character\s*:\s*(?<char>\w+)'
    DialogicText = '^\s*text\s*:\s*["''](?<text>[^"'']+)["'']'
    DialogicEvent = '^\s*-\s*(?<event>\w+)'
    DialogicJoin = '^\s*join\s+(?<char>\w+)'
    DialogicLeave = '^\s*leave\s+(?<char>\w+)'
    DialogicChoice = '^\s*-\s*\[(?<text>[^\]]+)\]'
    DialogicCondition = '^\s*if\s+(?<cond>.+):'
    DialogicSet = '^\s*set\s*\{\s*(?<var>\w+)\s*[=:]\s*(?<val>[^}]+)\}'
    DialogicLabel = '^\s*label\s+(?<name>\w+)'
    
    # DialogueQuest patterns
    QuestNode = '^\s*node\s+(?<id>\w+)'
    QuestDialogue = '^\s*dialogue\s*:\s*(?<text>.*)'
    QuestSpeaker = '^\s*speaker\s*:\s*(?<char>\w+)'
    QuestOption = '^\s*option\s*:\s*(?<text>.*)'
    QuestCondition = '^\s*condition\s*:\s*(?<cond>.+)'
    QuestAction = '^\s*action\s*:\s*(?<action>.+)'
    QuestNext = '^\s*next\s*:\s*(?<target>\w+)'
    
    # Translation keys
    TranslationKey = '\[ID\:\s*(?<key>[^\]]+)\]'
    TranslationHint = '\%\s*(?<key>\w+)'
    
    # BBCode patterns
    BBCodeColor = '\[color\s*=\s*[^\]]*\](?<text>[^\[]*)\[/color\]'
    BBCodeBold = '\[b\](?<text>[^\[]*)\[/b\]'
    BBCodeItalic = '\[i\](?<text>[^\[]*)\[/i\]'
    BBCodeWave = '\[wave\s*[^\]]*\](?<text>[^\[]*)\[/wave\]'
    BBCodeShake = '\[shake\s*[^\]]*\](?<text>[^\[]*)\[/shake\]'
    BBCodeWait = '\[wait\s*=\s*(?<time>[\d.]+)\]'
    BBCodeSpeed = '\[speed\s*=\s*(?<speed>[\d.]+)\]'
    BBCodePortrait = '\[portrait\s*=\s*(?<portrait>[^\]]+)\]'
    BBCodeEmotion = '\[emotion\s*=\s*(?<emotion>[^\]]+)\]'
    
    # Variable interpolation
    VariableRef = '\{\{(?<var>[^}]+)\}\}'
    VariableRefOld = '\$(?<var>\w+)'
    DialogicVariable = '\{(?<var>\w+)\}'
    
    # Choice/option patterns
    ChoiceOption = '^\s*-\s*\[(?<text>[^\]]+)\]\s*=>\s*(?<target>\w+)'
    ChoiceCondition = '^\s*-\s*\[(?<text>[^\]]+)\]\s+if\s+(?<cond>[^\[]+)\s*=>\s*(?<target>\w+)'
    
    # GDScript dialogue patterns
    DialogueDataArray = '@export\s+var\s+dialogue_data\s*:\s*\['
    DialogueResource = 'DialogueResource|DialogueLine|DialogueChoice'
    DialogueStart = 'func\s+start_dialogue|start_conversation|show_dialogue'
    DialogueAdvance = 'next\(\)|advance\(\)|get_next\(\)'
    
    # JSON dialogue (common format)
    JsonDialogueEntry = '"speaker"\s*:\s*"(?<char>[^"]*)"'
    JsonDialogueText = '"text"\s*:\s*"(?<text>[^"]*)"'
    JsonDialogueId = '"id"\s*:\s*"(?<id>[^"]*)"'
    JsonNextId = '"next"\s*:\s*"(?<next>[^"]*)"'
    JsonChoices = '"choices"\s*:\s*\['
    JsonCondition = '"condition"\s*:\s*"(?<cond>[^"]*)"'
    JsonCharacterName = '"name"\s*:\s*"(?<name>[^"]*)"'
    JsonCharacterColor = '"color"\s*:\s*"(?<color>[^"]*)"'
    
    # Localization CSV patterns
    CsvKey = '^(?<key>[^,]+)'
    CsvSource = ',"(?<source>[^"]*)"'
    CsvTranslation = ',"(?<trans>[^"]*)"'
}

# ============================================================================
# Private Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Creates provenance metadata for extraction results.
.DESCRIPTION
    Generates standardized metadata including source file, extraction timestamp,
    and parser version for tracking extraction provenance.
.PARAMETER SourceFile
    Path to the source file being parsed.
.PARAMETER Success
    Whether the extraction was successful.
.PARAMETER Errors
    Array of error messages.
.OUTPUTS
    System.Collections.Hashtable. Provenance metadata object.
#>
function New-ProvenanceMetadata {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,
        
        [Parameter()]
        [bool]$Success = $true,
        
        [Parameter()]
        [array]$Errors = @()
    )
    
    return @{
        sourceFile = $SourceFile
        extractionTimestamp = [DateTime]::UtcNow.ToString("o")
        parserName = $script:ParserName
        parserVersion = $script:ParserVersion
        success = $Success
        errors = $Errors
    }
}

<#
.SYNOPSIS
    Detects the dialogue format from file content.
.DESCRIPTION
    Analyzes the content to determine the dialogue file format.
.PARAMETER Content
    The file content to analyze.
.PARAMETER Extension
    The file extension.
.OUTPUTS
    System.String. The detected format.
#>
function Get-DialogueFormat {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$Extension = ''
    )
    
    # Check extension first
    switch ($Extension.ToLower()) {
        '.dialogue' { return 'dialogue_manager' }
        '.dtl' { return 'dialogic' }
        '.tres' { return 'dialogic' }
        '.cfg' { return 'dialogic' }
        '.json' { 
            # Need to check content for JSON dialogue
            if ($Content -match '"speaker"' -or $Content -match '"dialogue"') {
                return 'json'
            }
        }
        '.gd' { return 'gdscript' }
    }
    
    # Check content patterns
    if ($Content -match '^\s*~\s*\w+') {
        return 'dialogue_manager'
    }
    if ($Content -match '^\s*-\s*character\s*:') {
        return 'dialogic'
    }
    if ($Content -match '^\s*node\s+\w+') {
        return 'dialogue_quest'
    }
    if ($Content -match '"nodes"\s*:' -or $Content -match '"speaker"\s*:') {
        return 'json'
    }
    
    return 'dialogue_manager'
}

<#
.SYNOPSIS
    Extracts BBCode tags from dialogue text.
.DESCRIPTION
    Parses dialogue text and extracts BBCode formatting tags.
.PARAMETER Text
    The dialogue text to parse.
.OUTPUTS
    System.Array. Array of BBCode tag objects.
#>
function Get-BBCodeTags {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )
    
    $tags = @()
    
    $tagPatterns = @(
        @{ Pattern = $script:DialoguePatterns.BBCodeColor; Type = 'color' }
        @{ Pattern = $script:DialoguePatterns.BBCodeBold; Type = 'bold' }
        @{ Pattern = $script:DialoguePatterns.BBCodeItalic; Type = 'italic' }
        @{ Pattern = $script:DialoguePatterns.BBCodeWave; Type = 'wave' }
        @{ Pattern = $script:DialoguePatterns.BBCodeShake; Type = 'shake' }
        @{ Pattern = $script:DialoguePatterns.BBCodeWait; Type = 'wait'; HasValue = $true; ValueGroup = 'time' }
        @{ Pattern = $script:DialoguePatterns.BBCodeSpeed; Type = 'speed'; HasValue = $true; ValueGroup = 'speed' }
        @{ Pattern = $script:DialoguePatterns.BBCodePortrait; Type = 'portrait'; HasValue = $true; ValueGroup = 'portrait' }
    )
    
    foreach ($tagPattern in $tagPatterns) {
        $matches = [regex]::Matches($Text, $tagPattern.Pattern)
        foreach ($match in $matches) {
            $tag = @{
                type = $tagPattern.Type
            }
            if ($tagPattern.HasValue) {
                $tag.value = $match.Groups[$tagPattern.ValueGroup].Value
            }
            else {
                $tag.text = $match.Groups['text'].Value
            }
            $tags += $tag
        }
    }
    
    return $tags
}

<#
.SYNOPSIS
    Extracts variable references from dialogue text.
.DESCRIPTION
    Parses dialogue text and extracts variable placeholders.
.PARAMETER Text
    The dialogue text to parse.
.PARAMETER Format
    The dialogue format to use for variable detection.
.OUTPUTS
    System.Array. Array of variable names.
#>
function Get-DialogueVariables {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        
        [Parameter()]
        [string]$Format = 'dialogue_manager'
    )
    
    $variables = @()
    
    switch ($Format) {
        'dialogic' {
            $matches = [regex]::Matches($Text, $script:DialoguePatterns.DialogicVariable)
            foreach ($match in $matches) {
                $variables += $match.Groups['var'].Value
            }
        }
        default {
            # {{variable}} format
            $matches = [regex]::Matches($Text, $script:DialoguePatterns.VariableRef)
            foreach ($match in $matches) {
                $variables += $match.Groups['var'].Value.Trim()
            }
            
            # $variable format
            $matches = [regex]::Matches($Text, $script:DialoguePatterns.VariableRefOld)
            foreach ($match in $matches) {
                $variables += $match.Groups['var'].Value
            }
        }
    }
    
    return $variables | Select-Object -Unique
}

# ============================================================================
# Public API Functions - Required by Canonical Document Section 25.6
# ============================================================================

<#
.SYNOPSIS
    Extracts dialogue resource files.

.DESCRIPTION
    Parses dialogue resource files (.dialogue, .dtl, .json, .tres) and extracts
    structured dialogue resources including nodes, choices, connections, and
    metadata.

.PARAMETER Path
    Path to the dialogue resource file.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER Format
    Format of the dialogue file (auto, dialogue_manager, dialogic, dialogue_quest, json).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - resources: Array of dialogue resource objects
    - nodes: Array of dialogue nodes
    - connections: Array of node connections
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $resources = Extract-DialogueResources -Path "res://dialogue/npc.dialogue"
    
    $resources = Extract-DialogueResources -Content $dialogueContent -Format "dialogic"
#>
function Extract-DialogueResources {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('auto', 'dialogue_manager', 'dialogic', 'dialogue_quest', 'json', 'gdscript')]
        [string]$Format = 'auto'
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    resources = @()
                    nodes = @()
                    connections = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ nodeCount = 0; connectionCount = 0 }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            
            # Auto-detect format from extension
            if ($Format -eq 'auto') {
                $ext = [System.IO.Path]::GetExtension($Path).ToLower()
                $Format = Get-DialogueFormat -Content $Content -Extension $ext
            }
        }
        else {
            if ($Format -eq 'auto') {
                $Format = Get-DialogueFormat -Content $Content
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                resources = @()
                nodes = @()
                connections = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ nodeCount = 0; connectionCount = 0 }
            }
        }
        
        $resources = @()
        $nodes = @()
        $connections = @()
        
        switch ($Format) {
            'dialogue_manager' {
                $result = Get-DialogueManagerResources -Content $Content
                $nodes = $result.nodes
                $connections = $result.connections
            }
            'dialogic' {
                $result = Get-DialogicResources -Content $Content
                $nodes = $result.nodes
                $connections = $result.connections
            }
            'dialogue_quest' {
                $result = Get-DialogueQuestResources -Content $Content
                $nodes = $result.nodes
                $connections = $result.connections
            }
            'json' {
                $result = Get-JsonDialogueResources -Content $Content
                $nodes = $result.nodes
                $connections = $result.connections
            }
            'gdscript' {
                $result = Get-GDScriptDialogueResources -Content $Content
                $nodes = $result.nodes
            }
        }
        
        # Build connections from node data
        foreach ($node in $nodes) {
            if ($node.nextNode) {
                $connections += @{
                    from = $node.id
                    to = $node.nextNode
                    type = 'next'
                }
            }
            foreach ($choice in $node.choices) {
                if ($choice.target) {
                    $connections += @{
                        from = $node.id
                        to = $choice.target
                        type = 'choice'
                        choiceText = $choice.text
                    }
                }
            }
        }
        
        return @{
            resources = $nodes  # Resources are the nodes themselves
            nodes = $nodes
            connections = $connections
            format = $Format
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                nodeCount = $nodes.Count
                connectionCount = $connections.Count
                format = $Format
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract dialogue resources: $_"
        return @{
            resources = @()
            nodes = @()
            connections = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ nodeCount = 0; connectionCount = 0 }
        }
    }
}

<#
.SYNOPSIS
    Extracts character definitions from dialogue files.

.DESCRIPTION
    Parses dialogue resource files and extracts character definitions including
    names, colors, portraits, and metadata. Supports Dialogic character files
    (.tres, .json) and inline character definitions.

.PARAMETER Path
    Path to the dialogue or character definition file.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER Resources
    Pre-extracted dialogue resources (optional).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - characters: Array of character definition objects
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $characters = Extract-DialogueCharacters -Path "res://dialogue/characters.json"
    
    $characters = Extract-DialogueCharacters -Resources $resources
#>
function Extract-DialogueCharacters {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Resources')]
        [hashtable]$Resources
    )
    
    try {
        $sourceFile = 'inline'
        $nodes = @()
        
        switch ($PSCmdlet.ParameterSetName) {
            'Path' {
                if (-not (Test-Path -LiteralPath $Path)) {
                    return @{
                        characters = @()
                        metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                        statistics = @{ characterCount = 0 }
                    }
                }
                $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
                $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
                
                # Try to parse as JSON character file
                try {
                    $json = $Content | ConvertFrom-Json
                    if ($json.characters) {
                        $characters = @()
                        foreach ($char in $json.characters) {
                            $characters += @{
                                id = $char.id -or $char.name
                                name = $char.name
                                displayName = $char.display_name -or $char.displayName -or $char.name
                                color = $char.color
                                portraits = $char.portraits
                                defaultPortrait = $char.default_portrait -or $char.defaultPortrait
                                description = $char.description
                            }
                        }
                        return @{
                            characters = $characters
                            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
                            statistics = @{ characterCount = $characters.Count }
                        }
                    }
                }
                catch {
                    # Not JSON, continue with dialogue extraction
                }
                
                $resources = Extract-DialogueResources -Path $Path
                $nodes = $resources.nodes
            }
            'Content' {
                $resources = Extract-DialogueResources -Content $Content
                $nodes = $resources.nodes
            }
            'Resources' {
                $nodes = $Resources.nodes
                $sourceFile = $Resources.metadata.sourceFile
            }
        }
        
        # Extract unique characters from dialogue nodes
        $characters = @{}
        foreach ($node in $nodes) {
            if ($node.character -and -not $characters.ContainsKey($node.character)) {
                $characters[$node.character] = @{
                    id = $node.character.ToLower()
                    name = $node.character
                    displayName = $node.character
                    firstAppearance = $node.id
                    lineCount = 0
                    colors = @()
                    portraits = @()
                }
            }
            if ($node.character) {
                $characters[$node.character].lineCount++
            }
        }
        
        # Check for color/portrait information in BBCode
        foreach ($node in $nodes) {
            if ($node.bbcode) {
                foreach ($tag in $node.bbcode) {
                    if ($tag.type -eq 'color' -and $node.character) {
                        $characters[$node.character].colors += $tag
                    }
                    if ($tag.type -eq 'portrait' -and $node.character) {
                        $characters[$node.character].portraits += $tag.portrait
                    }
                }
            }
        }
        
        $totalLines = 0
        foreach ($char in $characters.Values) {
            $totalLines += $char.lineCount
        }
        
        return @{
            characters = @($characters.Values)
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                characterCount = $characters.Count
                totalLines = $totalLines
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract dialogue characters: $_"
        return @{
            characters = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ characterCount = 0 }
        }
    }
}

<#
.SYNOPSIS
    Extracts dialogue timeline structures from dialogue files.

.DESCRIPTION
    Parses dialogue files and extracts timeline structures including
    linear paths, branch points, loops, and end points. Supports all
    dialogue formats including Dialogic timelines.

.PARAMETER Path
    Path to the dialogue file.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER Resources
    Pre-extracted dialogue resources (optional).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - timelines: Array of timeline structures
    - flows: Conversation flow analysis
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $timelines = Extract-DialogueTimelines -Path "res://dialogue/story.dialogue"
    
    $timelines = Extract-DialogueTimelines -Resources $resources
#>
function Extract-DialogueTimelines {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Resources')]
        [hashtable]$Resources
    )
    
    try {
        $sourceFile = 'inline'
        $nodes = @()
        
        switch ($PSCmdlet.ParameterSetName) {
            'Path' {
                $resources = Extract-DialogueResources -Path $Path
                $sourceFile = $resources.metadata.sourceFile
                $nodes = $resources.nodes
            }
            'Content' {
                $resources = Extract-DialogueResources -Content $Content
                $sourceFile = $resources.metadata.sourceFile
                $nodes = $resources.nodes
            }
            'Resources' {
                $nodes = $Resources.nodes
                $sourceFile = $Resources.metadata.sourceFile
            }
        }
        
        # Build node lookup
        $nodeDict = @{}
        foreach ($node in $nodes) {
            $nodeDict[$node.id] = $node
        }
        
        # Analyze flows
        $flows = @{
            linearPaths = @()
            branchPoints = @()
            endPoints = @()
            loops = @()
            totalNodes = $nodes.Count
            totalChoices = 0
            averageBranchingFactor = 0
            maxDepth = 0
        }
        
        $visited = @{}
        
        # Find branch points (nodes with choices)
        foreach ($node in $nodes) {
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
        
        # Extract timelines (sequences from start points to end points)
        $timelines = @()
        $startNodes = $nodes | Where-Object { $_.type -eq 'title' -or $_.id -eq 'start' }
        if ($startNodes.Count -eq 0 -and $nodes.Count -gt 0) {
            $startNodes = @($nodes[0])
        }
        
        foreach ($startNode in $startNodes) {
            $timeline = @{
                id = $startNode.id
                startNode = $startNode.id
                nodes = @()
                length = 0
                hasChoices = $false
            }
            
            $current = $startNode
            $visitedNodes = @{}
            $depth = 0
            $maxDepth = 50  # Prevent infinite loops
            
            while ($current -and $depth -lt $maxDepth) {
                if ($visitedNodes.ContainsKey($current.id)) {
                    # Loop detected
                    $timeline.hasLoop = $true
                    break
                }
                
                $visitedNodes[$current.id] = $true
                $timeline.nodes += $current.id
                $timeline.length++
                
                if ($current.choices -and $current.choices.Count -gt 0) {
                    $timeline.hasChoices = $true
                    break  # Timeline branches, stop linear traversal
                }
                
                if ($current.nextNode -and $current.nextNode -ne 'END') {
                    if ($nodeDict.ContainsKey($current.nextNode)) {
                        $current = $nodeDict[$current.nextNode]
                    }
                    else {
                        $timeline.incomplete = $true
                        break
                    }
                }
                else {
                    break
                }
                
                $depth++
            }
            
            $timelines += $timeline
        }
        
        return @{
            timelines = $timelines
            flows = $flows
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                timelineCount = $timelines.Count
                totalNodes = $nodes.Count
                branchPointCount = $flows.branchPoints.Count
                endPointCount = $flows.endPoints.Count
                averageBranchingFactor = [math]::Round($flows.averageBranchingFactor, 2)
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract dialogue timelines: $_"
        return @{
            timelines = @()
            flows = @{}
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ timelineCount = 0; totalNodes = 0 }
        }
    }
}

<#
.SYNOPSIS
    Extracts variable/state definitions from dialogue files.

.DESCRIPTION
    Parses dialogue files and extracts variable definitions, state tracking,
    and condition checks. Includes variable usage patterns and default values.

.PARAMETER Path
    Path to the dialogue file.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER Resources
    Pre-extracted dialogue resources (optional).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - variables: Array of variable definition objects
    - conditions: Array of condition check objects
    - actions: Array of variable action objects (set/do)
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $variables = Extract-DialogueVariables -Path "res://dialogue/quest.dialogue"
    
    $variables = Extract-DialogueVariables -Resources $resources
#>
function Extract-DialogueVariables {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Resources')]
        [hashtable]$Resources
    )
    
    try {
        $sourceFile = 'inline'
        $nodes = @()
        $format = 'dialogue_manager'
        
        switch ($PSCmdlet.ParameterSetName) {
            'Path' {
                $resources = Extract-DialogueResources -Path $Path
                $sourceFile = $resources.metadata.sourceFile
                $nodes = $resources.nodes
                $format = $resources.format
            }
            'Content' {
                $resources = Extract-DialogueResources -Content $Content
                $sourceFile = $resources.metadata.sourceFile
                $nodes = $resources.nodes
                $format = $resources.format
            }
            'Resources' {
                $nodes = $Resources.nodes
                $sourceFile = $Resources.metadata.sourceFile
            }
        }
        
        $variables = @{}
        $conditions = @()
        $actions = @()
        
        # Extract from nodes
        foreach ($node in $nodes) {
            # Extract variables from text
            $textVars = Get-DialogueVariables -Text $node.text -Format $format
            foreach ($var in $textVars) {
                if (-not $variables.ContainsKey($var)) {
                    $variables[$var] = @{
                        name = $var
                        type = 'string'  # Default type
                        usedInText = $true
                        lineNumbers = @()
                    }
                }
                $variables[$var].lineNumbers += $node.lineNumber
            }
            
            # Extract from conditions
            foreach ($cond in $node.conditions) {
                $conditions += @{
                    nodeId = $node.id
                    condition = $cond.condition
                    type = $cond.type
                    lineNumber = $cond.lineNumber
                    context = 'node'
                }
                
                # Extract variables from condition
                $condVars = Get-DialogueVariables -Text $cond.condition -Format $format
                foreach ($var in $condVars) {
                    if (-not $variables.ContainsKey($var)) {
                        $variables[$var] = @{
                            name = $var
                            type = 'bool'
                            usedInCondition = $true
                            lineNumbers = @()
                        }
                    }
                    else {
                        $variables[$var].usedInCondition = $true
                    }
                    $variables[$var].lineNumbers += $cond.lineNumber
                }
            }
            
            # Extract from actions
            foreach ($action in $node.actions) {
                $actions += @{
                    nodeId = $node.id
                    type = $action.type
                    variable = $action.variable
                    value = $action.value
                    lineNumber = $action.lineNumber
                }
                
                if ($action.variable) {
                    $var = $action.variable
                    if (-not $variables.ContainsKey($var)) {
                        $variables[$var] = @{
                            name = $var
                            type = 'unknown'
                            modified = $true
                            lineNumbers = @()
                        }
                    }
                    else {
                        $variables[$var].modified = $true
                    }
                    $variables[$var].lineNumbers += $action.lineNumber
                }
            }
            
            # Extract from choices
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
                    
                    $condVars = Get-DialogueVariables -Text $choice.condition -Format $format
                    foreach ($var in $condVars) {
                        if (-not $variables.ContainsKey($var)) {
                            $variables[$var] = @{
                                name = $var
                                type = 'bool'
                                usedInCondition = $true
                                lineNumbers = @()
                            }
                        }
                        else {
                            $variables[$var].usedInCondition = $true
                        }
                    }
                }
            }
        }
        
        return @{
            variables = @($variables.Values)
            conditions = $conditions
            actions = $actions
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                variableCount = $variables.Count
                conditionCount = $conditions.Count
                actionCount = $actions.Count
                readOnlyVars = ($variables.Values | Where-Object { -not $_.modified }).Count
                modifiedVars = ($variables.Values | Where-Object { $_.modified }).Count
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract dialogue variables: $_"
        return @{
            variables = @()
            conditions = @()
            actions = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ variableCount = 0; conditionCount = 0; actionCount = 0 }
        }
    }
}

# ============================================================================
# Format-Specific Parser Functions
# ============================================================================

<#
.SYNOPSIS
    Parses Godot Dialogue Manager format.
#>
function Get-DialogueManagerResources {
    [CmdletBinding()]
    param([string]$Content)
    
    $nodes = @()
    $lines = $Content -split "`r?`n"
    $lineNumber = 0
    $currentNode = $null
    $currentTitle = 'start'
    
    foreach ($line in $lines) {
        $lineNumber++
        $trimmed = $line.Trim()
        
        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
            continue
        }
        
        # Title definition
        if ($trimmed -match $script:DialoguePatterns.DialogueTitle) {
            $currentTitle = $matches['title']
            $currentNode = @{
                id = $currentTitle
                type = 'title'
                lineNumber = $lineNumber
                character = $null
                text = $null
                choices = @()
                conditions = @()
                actions = @()
                nextNode = $null
                bbcode = @()
                variables = @()
            }
            $nodes += $currentNode
            continue
        }
        
        # Character dialogue line
        if ($trimmed -match $script:DialoguePatterns.DialogueCharacter) {
            $character = $matches['char']
            $text = $matches['text']
            
            # Extract BBCode
            $bbcode = Get-BBCodeTags -Text $text
            
            # Extract variables
            $variables = Get-DialogueVariables -Text $text -Format 'dialogue_manager'
            
            # Extract translation key
            $translationKey = $null
            if ($text -match $script:DialoguePatterns.TranslationKey) {
                $translationKey = $matches['key']
            }
            
            $dialogueNode = @{
                id = "${currentTitle}_$lineNumber"
                type = 'dialogue'
                lineNumber = $lineNumber
                character = $character
                text = $text
                translationKey = $translationKey
                bbcode = $bbcode
                variables = $variables
                choices = @()
                conditions = @()
                actions = @()
                nextNode = $null
            }
            
            if ($currentNode -and $currentNode.type -eq 'title') {
                # First dialogue after title
                $currentNode.character = $character
                $currentNode.text = $text
                $currentNode.type = 'dialogue'
                $currentNode.id = "${currentTitle}_line"
                $currentNode.bbcode = $bbcode
                $currentNode.variables = $variables
                $currentNode.translationKey = $translationKey
            }
            else {
                $nodes += $dialogueNode
                $currentNode = $dialogueNode
            }
            continue
        }
        
        # Choice/Response option
        if ($trimmed -match $script:DialoguePatterns.ChoiceOption) {
            $choiceText = $matches['text']
            $target = $matches['target']
            
            $choice = @{
                text = $choiceText
                target = $target
                lineNumber = $lineNumber
                condition = $null
            }
            
            if ($currentNode) {
                $currentNode.choices += $choice
            }
            continue
        }
        
        # Choice with condition
        if ($trimmed -match $script:DialoguePatterns.ChoiceCondition) {
            $choiceText = $matches['text']
            $condition = $matches['cond'].Trim()
            $target = $matches['target']
            
            $choice = @{
                text = $choiceText
                target = $target
                lineNumber = $lineNumber
                condition = $condition
            }
            
            if ($currentNode) {
                $currentNode.choices += $choice
            }
            continue
        }
        
        # Goto/Jump to another title
        if ($trimmed -match $script:DialoguePatterns.DialogueGoto) {
            $target = $matches['target']
            if ($currentNode) {
                $currentNode.nextNode = $target
            }
            continue
        }
        
        # Jump command
        if ($trimmed -match $script:DialoguePatterns.DialogueJump) {
            $target = $matches['target']
            if ($currentNode) {
                $currentNode.nextNode = $target
            }
            continue
        }
        
        # Condition start
        if ($trimmed -match $script:DialoguePatterns.DialogueCondition) {
            $condition = $matches['cond'].Trim()
            
            if ($currentNode) {
                $currentNode.conditions += @{
                    condition = $condition
                    lineNumber = $lineNumber
                    type = 'if'
                }
            }
            continue
        }
        
        # Else clause
        if ($trimmed -match $script:DialoguePatterns.DialogueElse) {
            if ($currentNode -and $currentNode.conditions.Count -gt 0) {
                $currentNode.conditions += @{
                    condition = 'else'
                    lineNumber = $lineNumber
                    type = 'else'
                }
            }
            continue
        }
        
        # Set variable
        if ($trimmed -match $script:DialoguePatterns.DialogueSet) {
            $varName = $matches['var']
            $value = $matches['val'].Trim()
            
            if ($currentNode) {
                $currentNode.actions += @{
                    type = 'set'
                    variable = $varName
                    value = $value
                    lineNumber = $lineNumber
                }
            }
            continue
        }
        
        # Do action
        if ($trimmed -match $script:DialoguePatterns.DialogueDo) {
            $action = $matches['action'].Trim()
            
            if ($currentNode) {
                $currentNode.actions += @{
                    type = 'do'
                    action = $action
                    lineNumber = $lineNumber
                }
            }
            continue
        }
        
        # End dialogue
        if ($trimmed -match $script:DialoguePatterns.DialogueEnd) {
            if ($currentNode) {
                $currentNode.nextNode = 'END'
            }
            continue
        }
    }
    
    return @{
        nodes = $nodes
        connections = @()
    }
}

<#
.SYNOPSIS
    Parses Dialogic format (.dtl files).
#>
function Get-DialogicResources {
    [CmdletBinding()]
    param([string]$Content)
    
    $nodes = @()
    $lines = $Content -split "`r?`n"
    $lineNumber = 0
    $currentNode = $null
    
    foreach ($line in $lines) {
        $lineNumber++
        $trimmed = $line.Trim()
        
        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
            continue
        }
        
        # Character definition
        if ($trimmed -match $script:DialoguePatterns.DialogicCharacter) {
            $character = $matches['char']
            if (-not $currentNode -or $currentNode.character -ne $character) {
                $currentNode = @{
                    id = "line_$lineNumber"
                    type = 'dialogue'
                    lineNumber = $lineNumber
                    character = $character
                    text = ''
                    choices = @()
                    conditions = @()
                    actions = @()
                    nextNode = $null
                    bbcode = @()
                    variables = @()
                }
                $nodes += $currentNode
            }
            continue
        }
        
        # Text line
        if ($trimmed -match $script:DialoguePatterns.DialogicText) {
            if ($currentNode) {
                $currentNode.text += ($matches['text'] + ' ')
                $currentNode.variables = Get-DialogueVariables -Text $currentNode.text -Format 'dialogic'
            }
            continue
        }
        
        # Choice
        if ($trimmed -match $script:DialoguePatterns.DialogicChoice) {
            $choiceText = $matches['text']
            if ($currentNode) {
                $currentNode.choices += @{
                    text = $choiceText
                    target = $null
                    lineNumber = $lineNumber
                    condition = $null
                }
            }
            continue
        }
        
        # Join/Leave events
        if ($trimmed -match $script:DialoguePatterns.DialogicJoin) {
            $nodes += @{
                id = "event_$lineNumber"
                type = 'event'
                eventType = 'join'
                character = $matches['char']
                lineNumber = $lineNumber
            }
        }
        if ($trimmed -match $script:DialoguePatterns.DialogicLeave) {
            $nodes += @{
                id = "event_$lineNumber"
                type = 'event'
                eventType = 'leave'
                character = $matches['char']
                lineNumber = $lineNumber
            }
        }
        
        # Condition
        if ($trimmed -match $script:DialoguePatterns.DialogicCondition) {
            $condition = $matches['cond'].Trim()
            if ($currentNode) {
                $currentNode.conditions += @{
                    condition = $condition
                    lineNumber = $lineNumber
                    type = 'if'
                }
            }
            continue
        }
        
        # Set variable
        if ($trimmed -match $script:DialoguePatterns.DialogicSet) {
            $varName = $matches['var']
            $value = $matches['val'].Trim()
            if ($currentNode) {
                $currentNode.actions += @{
                    type = 'set'
                    variable = $varName
                    value = $value
                    lineNumber = $lineNumber
                }
            }
            continue
        }
        
        # Label
        if ($trimmed -match $script:DialoguePatterns.DialogicLabel) {
            $nodes += @{
                id = $matches['name']
                type = 'label'
                lineNumber = $lineNumber
            }
        }
    }
    
    return @{
        nodes = $nodes
        connections = @()
    }
}

<#
.SYNOPSIS
    Parses DialogueQuest format.
#>
function Get-DialogueQuestResources {
    [CmdletBinding()]
    param([string]$Content)
    
    $nodes = @()
    $lines = $Content -split "`r?`n"
    $lineNumber = 0
    $currentNode = $null
    
    foreach ($line in $lines) {
        $lineNumber++
        $trimmed = $line.Trim()
        
        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
            continue
        }
        
        # Node definition
        if ($trimmed -match $script:DialoguePatterns.QuestNode) {
            $currentNode = @{
                id = $matches['id']
                type = 'node'
                lineNumber = $lineNumber
                text = ''
                speaker = ''
                choices = @()
                conditions = @()
                actions = @()
                nextNode = $null
            }
            $nodes += $currentNode
            continue
        }
        
        if ($currentNode) {
            # Dialogue text
            if ($trimmed -match $script:DialoguePatterns.QuestDialogue) {
                $currentNode.text = $matches['text']
                continue
            }
            
            # Speaker
            if ($trimmed -match $script:DialoguePatterns.QuestSpeaker) {
                $currentNode.speaker = $matches['char']
                continue
            }
            
            # Option
            if ($trimmed -match $script:DialoguePatterns.QuestOption) {
                $currentNode.choices += @{
                    text = $matches['text']
                    target = $null
                    lineNumber = $lineNumber
                }
                continue
            }
            
            # Condition
            if ($trimmed -match $script:DialoguePatterns.QuestCondition) {
                $currentNode.conditions += @{
                    condition = $matches['cond']
                    lineNumber = $lineNumber
                    type = 'if'
                }
                continue
            }
            
            # Action
            if ($trimmed -match $script:DialoguePatterns.QuestAction) {
                $currentNode.actions += @{
                    type = 'do'
                    action = $matches['action']
                    lineNumber = $lineNumber
                }
                continue
            }
            
            # Next node
            if ($trimmed -match $script:DialoguePatterns.QuestNext) {
                $currentNode.nextNode = $matches['target']
                continue
            }
        }
    }
    
    return @{
        nodes = $nodes
        connections = @()
    }
}

<#
.SYNOPSIS
    Parses JSON dialogue format.
#>
function Get-JsonDialogueResources {
    [CmdletBinding()]
    param([string]$Content)
    
    try {
        $json = $Content | ConvertFrom-Json -ErrorAction Stop
        $nodes = @()
        
        # Handle array format
        if ($json -is [array]) {
            foreach ($entry in $json) {
                $node = @{
                    id = $entry.id
                    type = 'dialogue'
                    character = $entry.speaker
                    text = $entry.text
                    choices = @()
                    nextNode = $entry.next
                    conditions = @()
                    actions = @()
                    bbcode = @()
                    variables = @()
                }
                
                if ($entry.choices) {
                    foreach ($choice in $entry.choices) {
                        $node.choices += @{
                            text = $choice.text
                            target = $choice.next
                            condition = $choice.condition
                        }
                    }
                }
                
                if ($entry.condition) {
                    $node.conditions += @{
                        condition = $entry.condition
                        type = 'if'
                    }
                }
                
                # Extract BBCode and variables from text
                if ($node.text) {
                    $node.bbcode = Get-BBCodeTags -Text $node.text
                    $node.variables = Get-DialogueVariables -Text $node.text
                }
                
                $nodes += $node
            }
        }
        # Handle object format with named nodes
        elseif ($json -is [System.Management.Automation.PSCustomObject]) {
            # Check for Dialogic-style format
            if ($json.dialogue) {
                foreach ($entry in $json.dialogue) {
                    $nodes += @{
                        id = $entry.id
                        type = 'dialogue'
                        character = $entry.speaker
                        text = $entry.text
                        choices = @()
                        nextNode = $entry.next
                        conditions = @()
                        actions = @()
                    }
                }
            }
            # Check for nodes array format
            elseif ($json.nodes) {
                foreach ($entry in $json.nodes) {
                    $nodes += @{
                        id = $entry.id
                        type = $entry.type -or 'dialogue'
                        character = $entry.character -or $entry.speaker
                        text = $entry.text
                        choices = $entry.choices -or @()
                        nextNode = $entry.next
                        conditions = @()
                        actions = @()
                    }
                }
            }
            # Simple key-value format
            else {
                foreach ($prop in $json.PSObject.Properties) {
                    $entry = $prop.Value
                    $node = @{
                        id = $prop.Name
                        type = 'dialogue'
                        character = $entry.speaker
                        text = $entry.text
                        choices = @()
                        nextNode = $entry.next
                        conditions = @()
                        actions = @()
                    }
                    
                    if ($entry.choices) {
                        foreach ($choice in $entry.choices) {
                            $node.choices += @{
                                text = $choice.text
                                target = $choice.next
                                condition = $choice.condition
                            }
                        }
                    }
                    
                    $nodes += $node
                }
            }
        }
        
        return @{
            nodes = $nodes
            connections = @()
        }
    }
    catch {
        Write-Warning "[$script:ParserName] Failed to parse JSON: $_"
        return @{
            nodes = @()
            connections = @()
        }
    }
}

<#
.SYNOPSIS
    Parses GDScript-based dialogue data.
#>
function Get-GDScriptDialogueResources {
    [CmdletBinding()]
    param([string]$Content)
    
    $nodes = @()
    $lines = $Content -split "`r?`n"
    $lineNumber = 0
    $inDialogueArray = $false
    $braceDepth = 0
    $currentDialogue = $null
    
    foreach ($line in $lines) {
        $lineNumber++
        $trimmed = $line.Trim()
        
        # Check for dialogue data export
        if ($line -match $script:DialoguePatterns.DialogueDataArray) {
            $inDialogueArray = $true
            $currentDialogue = @{
                id = "gdscript_dialogue_$lineNumber"
                type = 'gdscript_dialogue'
                lineNumber = $lineNumber
                entries = @()
            }
            $braceDepth = 0
            continue
        }
        
        # Track brace depth in dialogue array
        if ($inDialogueArray) {
            $braceDepth += (($line -creplace '[^{]').Length) - (($line -creplace '[^}]').Length)
            
            # Try to extract dictionary entries
            if ($trimmed -match '"speaker"\s*:\s*"([^"]*)"') {
                $speaker = $matches[1]
                $text = ''
                
                if ($trimmed -match '"text"\s*:\s*"([^"]*)"') {
                    $text = $matches[1]
                }
                
                $entry = @{
                    speaker = $speaker
                    text = $text
                    lineNumber = $lineNumber
                }
                
                if ($trimmed -match '"next"\s*:\s*"([^"]*)"') {
                    $entry.next = $matches[1]
                }
                
                $currentDialogue.entries += $entry
            }
            
            # End of array
            if ($braceDepth -le 0 -and $line -match '\]') {
                $inDialogueArray = $false
                $nodes += $currentDialogue
                $currentDialogue = $null
            }
        }
    }
    
    return @{
        nodes = $nodes
        connections = @()
    }
}

# ============================================================================
# Legacy Compatibility Functions
# ============================================================================

<#
.SYNOPSIS
    Extracts dialogue trees from dialogue files.
    
    DEPRECATED: Use Extract-DialogueResources instead.
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

<#
.SYNOPSIS
    Extracts conversation flows from dialogue trees.
    
    DEPRECATED: Use Extract-DialogueTimelines instead.
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

<#
.SYNOPSIS
    Extracts condition checks from dialogue trees.
    
    DEPRECATED: Use Extract-DialogueVariables instead.
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

<#
.SYNOPSIS
    Extracts localization patterns from dialogue.
    
    DEPRECATED: Use Extract-DialogueResources with localization analysis.
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

<#
.SYNOPSIS
    Main entry point for parsing dialogue files.
    
    DEPRECATED: Use the specific Extract-* functions instead.

.DESCRIPTION
    Legacy entry point that delegates to the canonical extraction functions.
#>
function Invoke-DialogueExtract {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('auto', 'dialogue_manager', 'json', 'gdscript')]
        [string]$Format = 'auto'
    )
    
    try {
        $sourceFile = 'inline'
        
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    filePath = $Path
                    success = $false
                    error = "File not found: $Path"
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $resources = Extract-DialogueResources -Path $Path -Format $Format
        }
        else {
            $resources = Extract-DialogueResources -Content $Content -Format $Format
        }
        
        $characters = Extract-DialogueCharacters -Resources $resources
        $timelines = Extract-DialogueTimelines -Resources $resources
        $variables = Extract-DialogueVariables -Resources $resources
        
        return @{
            filePath = $sourceFile
            fileType = $resources.format
            nodes = $resources.nodes
            connections = $resources.connections
            characters = $characters.characters
            timelines = $timelines.timelines
            flows = $timelines.flows
            variables = $variables.variables
            conditions = $variables.conditions
            actions = $variables.actions
            statistics = @{
                totalNodes = $resources.statistics.nodeCount
                totalChoices = $timelines.statistics.branchPointCount
                branchPoints = $timelines.flows.branchPoints.Count
                endPoints = $timelines.flows.endPoints.Count
                conditionChecks = $variables.statistics.conditionCount
                hasExplicitTranslations = $resources.nodes | Where-Object { $_.translationKey } | Measure-Object | Select-Object -ExpandProperty Count
                characterCount = $characters.statistics.characterCount
            }
            metadata = $resources.metadata
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract dialogue: $_"
        return @{
            filePath = $sourceFile
            success = $false
            error = $_.ToString()
        }
    }
}

# ============================================================================
# Public API Functions - Dialogic 2.0 Specific (Section 25.6.1)
# ============================================================================

<#
.SYNOPSIS
    Extracts Dialogic 2.0 timeline files (.dtl).

.DESCRIPTION
    Parses Dialogic 2.0 timeline files and extracts timeline structures,
    events, character entries, text events, choices, conditions, and variables.
    Supports Dialogic's YAML-like timeline format.

.PARAMETER Path
    Path to the .dtl file.

.PARAMETER Content
    File content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - timeline: Timeline metadata and events
    - events: Array of timeline events
    - characters: Characters referenced in timeline
    - labels: Label definitions for jumps
    - metadata: Provenance metadata

.EXAMPLE
    $timeline = Export-DialogicTimeline -Path "res://dialogue/intro.dtl"
#>
function Export-DialogicTimeline {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        $sourceFile = 'inline'
        
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    timeline = $null
                    events = @()
                    characters = @()
                    labels = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        $resources = Get-DialogicResources -Content $Content
        $nodes = $resources.nodes
        
        $events = @()
        $characters = @{}
        $labels = @()
        $timelineName = [System.IO.Path]::GetFileNameWithoutExtension($sourceFile)
        
        foreach ($node in $nodes) {
            # Convert node to Dialogic event format
            $event = @{
                type = $node.type
                lineNumber = $node.lineNumber
            }
            
            switch ($node.type) {
                'dialogue' {
                    $event.character = $node.character
                    $event.text = $node.text
                    $event.variables = $node.variables
                    
                    # Track character
                    if ($node.character -and -not $characters.ContainsKey($node.character)) {
                        $characters[$node.character] = @{
                            id = $node.character.ToLower()
                            name = $node.character
                            firstAppearance = $node.lineNumber
                        }
                    }
                }
                'event' {
                    $event.eventType = $node.eventType
                    $event.character = $node.character
                }
                'label' {
                    $event.label = $node.id
                    $labels += $node.id
                }
            }
            
            # Add conditions if present
            if ($node.conditions) {
                $event.conditions = $node.conditions
            }
            
            # Add actions if present
            if ($node.actions) {
                $event.actions = $node.actions
            }
            
            # Add choices if present
            if ($node.choices) {
                $event.choices = $node.choices
            }
            
            $events += $event
        }
        
        return @{
            timeline = @{
                name = $timelineName
                format = 'dialogic_2.0'
                eventCount = $events.Count
            }
            events = $events
            characters = @($characters.Values)
            labels = $labels
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to export Dialogic timeline: $_"
        return @{
            timeline = $null
            events = @()
            characters = @()
            labels = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
        }
    }
}

<#
.SYNOPSIS
    Extracts Dialogic 2.0 character definitions (.dch files).

.DESCRIPTION
    Parses Dialogic character files and extracts character metadata including
    name, display name, color, portraits, default portrait, and nicknames.

.PARAMETER Path
    Path to the .dch or .tres character file.

.PARAMETER Content
    File content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - character: Character definition object
    - portraits: Array of portrait definitions
    - metadata: Provenance metadata

.EXAMPLE
    $char = Export-DialogicCharacter -Path "res://dialogue/characters/player.dch"
#>
function Export-DialogicCharacter {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        $sourceFile = 'inline'
        
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    character = $null
                    portraits = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        $character = @{
            id = ''
            name = ''
            displayName = ''
            color = ''
            description = ''
            defaultPortrait = ''
            nicknames = @()
        }
        
        $portraits = @()
        
        # Parse Dialogic character file format
        $lines = $Content -split "`r?`n"
        $inPortraitSection = $false
        $currentPortrait = $null
        
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            
            # Skip comments and empty lines
            if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
                continue
            }
            
            # Character ID
            if ($trimmed -match '^\s*id\s*[=:]\s*"?([^"\n]+)"?') {
                $character.id = $matches[1].Trim().Trim('"')
            }
            
            # Character name
            if ($trimmed -match '^\s*name\s*[=:]\s*"?([^"\n]+)"?') {
                $character.name = $matches[1].Trim().Trim('"')
            }
            
            # Display name
            if ($trimmed -match '^\s*display_name\s*[=:]\s*"?([^"\n]+)"?') {
                $character.displayName = $matches[1].Trim().Trim('"')
            }
            
            # Color
            if ($trimmed -match '^\s*color\s*[=:]\s*"?([^"\n]+)"?') {
                $character.color = $matches[1].Trim().Trim('"')
            }
            
            # Description
            if ($trimmed -match '^\s*description\s*[=:]\s*"?([^"\n]+)"?') {
                $character.description = $matches[1].Trim().Trim('"')
            }
            
            # Default portrait
            if ($trimmed -match '^\s*default_portrait\s*[=:]\s*"?([^"\n]+)"?') {
                $character.defaultPortrait = $matches[1].Trim().Trim('"')
            }
            
            # Nicknames (array)
            if ($trimmed -match '^\s*nicknames\s*[=:]\s*\[') {
                if ($trimmed -match '\[(.*?)\]') {
                    $nickStr = $matches[1]
                    $character.nicknames = $nickStr -split ',' | ForEach-Object { $_.Trim().Trim('"') }
                }
            }
            
            # Portrait section
            if ($trimmed -match '^\s*portraits\s*:') {
                $inPortraitSection = $true
                continue
            }
            
            # Portrait entry
            if ($inPortraitSection -and $trimmed -match '^\s*-\s*(\w+)\s*:') {
                if ($currentPortrait) {
                    $portraits += $currentPortrait
                }
                $currentPortrait = @{
                    name = $matches[1]
                    path = ''
                    scale = 1.0
                    offset = @{ x = 0; y = 0 }
                }
            }
            
            # Portrait path
            if ($currentPortrait -and $trimmed -match '^\s*path\s*[=:]\s*"?([^"\n]+)"?') {
                $currentPortrait.path = $matches[1].Trim().Trim('"')
            }
            
            # Portrait scale
            if ($currentPortrait -and $trimmed -match '^\s*scale\s*[=:]\s*([\d.]+)') {
                $currentPortrait.scale = [double]$matches[1]
            }
        }
        
        # Add last portrait
        if ($currentPortrait) {
            $portraits += $currentPortrait
        }
        
        # If no ID, derive from filename
        if ([string]::IsNullOrWhiteSpace($character.id)) {
            $character.id = [System.IO.Path]::GetFileNameWithoutExtension($sourceFile).ToLower()
        }
        
        # If no name, use ID
        if ([string]::IsNullOrWhiteSpace($character.name)) {
            $character.name = $character.id
        }
        
        # If no display name, use name
        if ([string]::IsNullOrWhiteSpace($character.displayName)) {
            $character.displayName = $character.name
        }
        
        return @{
            character = $character
            portraits = $portraits
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to export Dialogic character: $_"
        return @{
            character = $null
            portraits = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
        }
    }
}

<#
.SYNOPSIS
    Extracts DialogueQuest dialogue data from JSON files.

.DESCRIPTION
    Parses DialogueQuest JSON dialogue files and extracts complete dialogue
    structures including nodes, connections, speakers, conditions, and actions.

.PARAMETER Path
    Path to the DialogueQuest JSON file.

.PARAMETER Content
    JSON content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - dialogue: Dialogue metadata
    - nodes: Array of dialogue nodes
    - connections: Node connections/edges
    - speakers: Unique speakers in the dialogue
    - variables: Variables used in conditions
    - metadata: Provenance metadata

.EXAMPLE
    $dialogue = Export-DialogueQuestDialogue -Path "res://quests/quest1_dialogue.json"
#>
function Export-DialogueQuestDialogue {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        $sourceFile = 'inline'
        
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    dialogue = $null
                    nodes = @()
                    connections = @()
                    speakers = @()
                    variables = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        $json = $Content | ConvertFrom-Json -ErrorAction Stop
        
        $nodes = @()
        $connections = @()
        $speakers = @{}
        $variables = @{}
        
        $dialogueName = if ($json.name) { $json.name } elseif ($json.id) { $json.id } else { 
            [System.IO.Path]::GetFileNameWithoutExtension($sourceFile) 
        }
        
        # Parse DialogueQuest format
        if ($json.nodes) {
            $nodeIndex = 0
            foreach ($nodeEntry in $json.nodes) {
                $nodeId = if ($nodeEntry.id) { $nodeEntry.id } else { "node_$nodeIndex" }
                $nodeType = if ($nodeEntry.type) { $nodeEntry.type } else { 'dialogue' }
                $nodeText = if ($nodeEntry.text) { $nodeEntry.text } elseif ($nodeEntry.dialogue) { $nodeEntry.dialogue } else { '' }
                $nodeSpeaker = if ($nodeEntry.speaker) { $nodeEntry.speaker } elseif ($nodeEntry.character) { $nodeEntry.character } else { '' }
                $node = @{
                    id = $nodeId
                    type = $nodeType
                    text = $nodeText
                    speaker = $nodeSpeaker
                    choices = @()
                    conditions = @()
                    actions = @()
                    position = $nodeEntry.position
                }
                
                # Track speaker
                if ($node.speaker -and -not $speakers.ContainsKey($node.speaker)) {
                    $speakers[$node.speaker] = @{
                        name = $node.speaker
                        nodeCount = 0
                    }
                }
                if ($node.speaker) {
                    $speakers[$node.speaker].nodeCount++
                }
                
                # Parse choices/options
                if ($nodeEntry.choices) {
                    $choiceIndex = 0
                    foreach ($choice in $nodeEntry.choices) {
                        $choiceText = if ($choice.text) { $choice.text } else { '' }
                        $choiceTarget = if ($choice.next) { $choice.next } elseif ($choice.target) { $choice.target } elseif ($choice.node) { $choice.node } else { $null }
                        $choiceCondition = if ($choice.condition) { $choice.condition } else { $null }
                        $choiceObj = @{
                            id = "choice_${nodeIndex}_$choiceIndex"
                            text = $choiceText
                            target = $choiceTarget
                            condition = $choiceCondition
                        }
                        $node.choices += $choiceObj
                        
                        # Create connection
                        if ($choiceObj.target) {
                            $connections += @{
                                from = $node.id
                                to = $choiceObj.target
                                type = 'choice'
                                choiceText = $choiceObj.text
                                condition = $choiceObj.condition
                            }
                        }
                        
                        # Extract variables from condition
                        if ($choice.condition) {
                            $condVars = Get-DialogueVariables -Text $choice.condition
                            foreach ($var in $condVars) {
                                $variables[$var] = @{ name = $var; usedIn = 'choice' }
                            }
                        }
                        
                        $choiceIndex++
                    }
                }
                
                # Parse direct next connection
                if ($nodeEntry.next -and -not $nodeEntry.choices) {
                    $connections += @{
                        from = $node.id
                        to = $nodeEntry.next
                        type = 'next'
                    }
                }
                
                # Parse conditions
                if ($nodeEntry.conditions) {
                    foreach ($cond in $nodeEntry.conditions) {
                        $condExpr = if ($cond.expression) { $cond.expression } elseif ($cond.condition) { $cond.condition } else { $cond }
                        $condType = if ($cond.type) { $cond.type } else { 'if' }
                        $node.conditions += @{
                            expression = $condExpr
                            type = $condType
                        }
                        
                        # Extract variables
                        $condVars = Get-DialogueVariables -Text $condExpr
                        foreach ($var in $condVars) {
                            $variables[$var] = @{ name = $var; usedIn = 'condition' }
                        }
                    }
                }
                
                # Parse actions
                if ($nodeEntry.actions) {
                    foreach ($action in $nodeEntry.actions) {
                        $actionType = if ($action.type) { $action.type } else { 'do' }
                        $actionCommand = if ($action.command) { $action.command } elseif ($action.action) { $action.action } else { $action }
                        $node.actions += @{
                            type = $actionType
                            command = $actionCommand
                        }
                    }
                }
                
                $nodes += $node
                $nodeIndex++
            }
        }
        
        return @{
            dialogue = @{
                name = $dialogueName
                format = 'dialogue_quest'
                nodeCount = $nodes.Count
                connectionCount = $connections.Count
            }
            nodes = $nodes
            connections = $connections
            speakers = @($speakers.Values)
            variables = @($variables.Values)
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to export DialogueQuest dialogue: $_"
        return @{
            dialogue = $null
            nodes = @()
            connections = @()
            speakers = @()
            variables = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
        }
    }
}

<#
.SYNOPSIS
    Builds a conversation graph from dialogue data.

.DESCRIPTION
    Analyzes dialogue nodes and connections to build a complete conversation
    graph including entry points, dead ends, loops, and path analysis.

.PARAMETER Path
    Path to the dialogue file.

.PARAMETER Content
    Dialogue content string.

.PARAMETER Resources
    Pre-extracted dialogue resources.

.PARAMETER Nodes
    Array of dialogue nodes.

.PARAMETER Connections
    Array of node connections.

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - graph: Graph metadata
    - nodes: Graph nodes (with depth, paths)
    - edges: Graph edges
    - entryPoints: Starting nodes
    - exitPoints: Terminal nodes
    - cycles: Detected loops
    - longestPath: Longest conversation path
    - unreachableNodes: Nodes not reachable from entry

.EXAMPLE
    $graph = Get-DialogueGraph -Path "res://dialogue/story.dialogue"
    
    $graph = Get-DialogueGraph -Nodes $nodes -Connections $connections
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

<#
.SYNOPSIS
    Extracts dialogue variables and conditions with detailed analysis.

.DESCRIPTION
    Comprehensive variable extraction that identifies variable definitions,
    usage patterns, conditions, assignments, and type inference from dialogue files.

.PARAMETER Path
    Path to the dialogue file.

.PARAMETER Content
    Dialogue content string.

.PARAMETER Resources
    Pre-extracted dialogue resources.

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - variables: Array of variable objects with type inference
    - conditions: All condition expressions
    - assignments: Variable assignments/sets
    - usagePatterns: How variables are used
    - dependencies: Variable interdependencies
    - metadata: Provenance metadata

.EXAMPLE
    $vars = Export-DialogueVariables -Path "res://dialogue/quest.dialogue"
#>
function Export-DialogueVariables {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Resources')]
        [hashtable]$Resources
    )
    
    try {
        $sourceFile = 'inline'
        $nodes = @()
        
        switch ($PSCmdlet.ParameterSetName) {
            'Path' {
                $resources = Extract-DialogueResources -Path $Path
                $sourceFile = $resources.metadata.sourceFile
                $nodes = $resources.nodes
            }
            'Content' {
                $resources = Extract-DialogueResources -Content $Content
                $sourceFile = $resources.metadata.sourceFile
                $nodes = $resources.nodes
            }
            'Resources' {
                $nodes = $Resources.nodes
                $sourceFile = $Resources.metadata.sourceFile
            }
        }
        
        $variables = @{}
        $conditions = @()
        $assignments = @()
        $usagePatterns = @{}
        
        foreach ($node in $nodes) {
            # Extract from text
            if ($node.text) {
                $textVars = Get-DialogueVariables -Text $node.text
                foreach ($var in $textVars) {
                    if (-not $variables.ContainsKey($var)) {
                        $variables[$var] = @{
                            name = $var
                            type = 'string'
                            inferredType = 'string'
                            definedAt = @()
                            usedAt = @()
                            conditions = @()
                            assignments = @()
                            usagePattern = 'interpolation'
                        }
                    }
                    $variables[$var].usedAt += @{
                        nodeId = $node.id
                        context = 'text'
                        lineNumber = $node.lineNumber
                    }
                    $variables[$var].usagePattern = 'interpolation'
                }
            }
            
            # Extract from conditions
            if ($node.conditions) {
                foreach ($cond in $node.conditions) {
                    $condExpr = $cond.condition
                    $conditions += @{
                        expression = $condExpr
                        nodeId = $node.id
                        type = $cond.type
                        lineNumber = $cond.lineNumber
                    }
                    
                    $condVars = Get-DialogueVariables -Text $condExpr
                    foreach ($var in $condVars) {
                        if (-not $variables.ContainsKey($var)) {
                            $variables[$var] = @{
                                name = $var
                                type = 'bool'
                                inferredType = 'bool'
                                definedAt = @()
                                usedAt = @()
                                conditions = @()
                                assignments = @()
                                usagePattern = 'condition'
                            }
                        }
                        $variables[$var].conditions += @{
                            expression = $condExpr
                            nodeId = $node.id
                            lineNumber = $cond.lineNumber
                        }
                        if ($variables[$var].usagePattern -ne 'assignment') {
                            $variables[$var].usagePattern = 'condition'
                        }
                    }
                }
            }
            
            # Extract from choices
            if ($node.choices) {
                foreach ($choice in $node.choices) {
                    if ($choice.condition) {
                        $conditions += @{
                            expression = $choice.condition
                            nodeId = $node.id
                            context = 'choice'
                            choiceText = $choice.text
                            lineNumber = $choice.lineNumber
                        }
                        
                        $choiceVars = Get-DialogueVariables -Text $choice.condition
                        foreach ($var in $choiceVars) {
                            if (-not $variables.ContainsKey($var)) {
                                $variables[$var] = @{
                                    name = $var
                                    type = 'bool'
                                    inferredType = 'bool'
                                    definedAt = @()
                                    usedAt = @()
                                    conditions = @()
                                    assignments = @()
                                    usagePattern = 'condition'
                                }
                            }
                            $variables[$var].conditions += @{
                                expression = $choice.condition
                                nodeId = $node.id
                                context = 'choice'
                                lineNumber = $choice.lineNumber
                            }
                        }
                    }
                }
            }
            
            # Extract from actions (assignments)
            if ($node.actions) {
                foreach ($action in $node.actions) {
                    if ($action.type -eq 'set' -or $action.variable) {
                        $varName = $action.variable
                        $assignments += @{
                            variable = $varName
                            value = $action.value
                            nodeId = $node.id
                            lineNumber = $action.lineNumber
                        }
                        
                        if (-not $variables.ContainsKey($varName)) {
                            # Infer type from value
                            $inferredType = 'string'
                            $value = $action.value
                            if ($value -match '^\d+$') { $inferredType = 'int' }
                            elseif ($value -match '^[\d.]+$') { $inferredType = 'float' }
                            elseif ($value -match '^(true|false)$') { $inferredType = 'bool' }
                            
                            $variables[$varName] = @{
                                name = $varName
                                type = $inferredType
                                inferredType = $inferredType
                                definedAt = @()
                                usedAt = @()
                                conditions = @()
                                assignments = @()
                                usagePattern = 'assignment'
                            }
                        }
                        $variables[$varName].assignments += @{
                            value = $action.value
                            nodeId = $node.id
                            lineNumber = $action.lineNumber
                        }
                        $variables[$varName].usagePattern = 'assignment'
                    }
                }
            }
        }
        
        # Calculate dependencies
        $dependencies = @()
        foreach ($varName in $variables.Keys) {
            $var = $variables[$varName]
            # Find variables that depend on this one
            foreach ($otherVar in $variables.Keys) {
                if ($varName -eq $otherVar) { continue }
                $other = $variables[$otherVar]
                foreach ($cond in $other.conditions) {
                    if ($cond.expression -match "\b$([regex]::Escape($varName))\b") {
                        $dependencies += @{
                            from = $varName
                            to = $otherVar
                            type = 'condition_dependency'
                        }
                    }
                }
            }
        }
        
        # Build output variables with safe count handling
        $outputVars = @()
        foreach ($var in $variables.Values) {
            $condCount = if ($var.conditions) { $var.conditions.Count } else { 0 }
            $assignCount = if ($var.assignments) { $var.assignments.Count } else { 0 }
            $usedCount = if ($var.usedAt) { $var.usedAt.Count } else { 0 }
            $outputVars += @{
                name = $var.name
                type = $var.type
                inferredType = $var.inferredType
                usagePattern = $var.usagePattern
                conditionCount = $condCount
                assignmentCount = $assignCount
                usageCount = $usedCount + $condCount + $assignCount
            }
        }
        
        # Count usage patterns
        $interpCount = 0; $condPatCount = 0; $assignPatCount = 0
        foreach ($var in $variables.Values) {
            if ($var.usagePattern -eq 'interpolation') { $interpCount++ }
            if ($var.usagePattern -eq 'condition') { $condPatCount++ }
            if ($var.usagePattern -eq 'assignment') { $assignPatCount++ }
        }
        
        return @{
            variables = $outputVars
            conditions = $conditions
            assignments = $assignments
            usagePatterns = @{
                interpolation = $interpCount
                condition = $condPatCount
                assignment = $assignPatCount
            }
            dependencies = $dependencies
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to export dialogue variables: $_"
        return @{
            variables = @()
            conditions = @()
            assignments = @()
            usagePatterns = @{}
            dependencies = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
        }
    }
}

<#
.SYNOPSIS
    Calculates comprehensive dialogue metrics and statistics.

.DESCRIPTION
    Analyzes dialogue structures and calculates various metrics including:
    - Branch count and complexity
    - Dialogue depth and path lengths
    - Character participation
    - Variable usage density
    - Translation coverage
    - Readability metrics

.PARAMETER Path
    Path to the dialogue file.

.PARAMETER Content
    Dialogue content string.

.PARAMETER Resources
    Pre-extracted dialogue resources.

.PARAMETER Graph
    Pre-computed dialogue graph.

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - metrics: Comprehensive metrics object
    - complexity: Complexity scores
    - coverage: Coverage statistics
    - quality: Quality indicators
    - metadata: Provenance metadata

.EXAMPLE
    $metrics = Get-DialogueMetrics -Path "res://dialogue/story.dialogue"
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

# ============================================================================
# Export Module Members
# ============================================================================

if ($null -ne $MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        # Canonical functions (Section 25.6)
        'Extract-DialogueResources'
        'Extract-DialogueCharacters'
        'Extract-DialogueTimelines'
        'Extract-DialogueVariables'
        # New Dialogic 2.0 functions
        'Export-DialogicTimeline'
        'Export-DialogicCharacter'
        'Export-DialogueQuestDialogue'
        'Get-DialogueGraph'
        'Export-DialogueVariables'
        'Get-DialogueMetrics'
        # Legacy compatibility functions
        'Get-DialogueTrees'
        'Get-ConversationFlows'
        'Get-ConditionChecks'
        'Get-LocalizationPatterns'
        'Invoke-DialogueExtract'
        'Get-BBCodeTags'
        'Get-DialogueVariables'
    )
}
