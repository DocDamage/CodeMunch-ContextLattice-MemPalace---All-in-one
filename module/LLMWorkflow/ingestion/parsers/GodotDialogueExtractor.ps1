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

<#
.SYNOPSIS
    Parses Dialogic format (.dtl files).

<#
.SYNOPSIS
    Parses DialogueQuest format.

<#
.SYNOPSIS
    Parses JSON dialogue format.

<#
.SYNOPSIS
    Parses GDScript-based dialogue data.

# ============================================================================
# Legacy Compatibility Functions
# ============================================================================

<#
.SYNOPSIS
    Extracts dialogue trees from dialogue files.
    
    DEPRECATED: Use Extract-DialogueResources instead.

<#
.SYNOPSIS
    Extracts conversation flows from dialogue trees.
    
    DEPRECATED: Use Extract-DialogueTimelines instead.

<#
.SYNOPSIS
    Extracts condition checks from dialogue trees.
    
    DEPRECATED: Use Extract-DialogueVariables instead.

<#
.SYNOPSIS
    Extracts localization patterns from dialogue.
    
    DEPRECATED: Use Extract-DialogueResources with localization analysis.

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
