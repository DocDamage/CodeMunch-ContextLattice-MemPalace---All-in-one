module/LLMWorkflow/extraction/GodotDialogueExtractor.ps1"
#Requires -Version 5.1
<#
.SYNOPSIS
    Godot Dialogue System extractor for LLM Workflow.

.DESCRIPTION
    Extracts structured dialogue data from Godot dialogue systems.
    Supports Godot Dialogue Manager (.dialogue files) and GDScript-based dialogue.
    Extracts dialogue trees, conversation flows, condition checks, and localization.

.NOTES
    File Name      : GodotDialogueExtractor.ps1
    Author         : LLM Workflow
    Version        : 1.0.0
    Supports       : Godot Dialogue Manager, custom GDScript dialogue
#>

Set-StrictMode -Version Latest

# ============================================================================
# Regex Patterns for Dialogue Parsing
# ============================================================================

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
    
    # Choice/option patterns
    ChoiceOption = '^\s*-\s*\[(?<text>[^\]]+)\]\s*=>\s*(?<target>\w+)'
    ChoiceCondition = '^\s*-\s*\[(?<text>[^\]]+)\]\s+if\s+(?<cond>[^\[]+)\s*=>\s*(?<target>\w+)'
    
    # GDScript dialogue patterns
    DialogueDataArray = '@export\s+var\s+dialogue_data\s*:?\s*=\s*\['
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
    
    # Localization CSV patterns
    CsvKey = '^(?<key>[^,]+)'
    CsvSource = ',"(?<source>[^"]*)"'
    CsvTranslation = ',"(?<trans>[^"]*)"'
}

# ============================================================================
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
    Extracts dialogue trees from dialogue files.

.DESCRIPTION
    Parses dialogue files (.dialogue, .json, .gd) and extracts structured
    dialogue trees with nodes, choices, and connections.

.PARAMETER Path
    Path to the dialogue file.

.PARAMETER Content
    Dialogue content string (alternative to Path).

.PARAMETER Format
    Format of the dialogue file (auto, dialogue_manager, json, gdscript).

.OUTPUTS
    System.Array. Array of dialogue node objects.

.EXAMPLE
    $dialogue = Get-DialogueTrees -Path "res://dialogue/npc.dialogue"
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
    
    try {
        # Load content
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Warning "File not found: $Path"
                return @()
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            
            # Auto-detect format from extension
            if ($Format -eq 'auto') {
                $ext = [System.IO.Path]::GetExtension($Path).ToLower()
                switch ($ext) {
                    '.dialogue' { $Format = 'dialogue_manager' }
                    '.json' { $Format = 'json' }
                    '.gd' { $Format = 'gdscript' }
                    default { $Format = 'dialogue_manager' }
                }
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @()
        }
        
        switch ($Format) {
            'dialogue_manager' {
                return Get-DialogueManagerTrees -Content $Content
            }
            'json' {
                return Get-JsonDialogueTrees -Content $Content
            }
            'gdscript' {
                return Get-GDScriptDialogueTrees -Content $Content
            }
            default {
                return Get-DialogueManagerTrees -Content $Content
            }
        }
    }
    catch {
        Write-Error "[Get-DialogueTrees] Failed to extract dialogue trees: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts dialogue trees from Godot Dialogue Manager format.

.DESCRIPTION
    Parses .dialogue files (Godot Dialogue Manager) and extracts
    structured dialogue nodes, titles, choices, and conditions.

.PARAMETER Content
    Dialogue content string.

.OUTPUTS
    System.Array. Array of dialogue node objects.
#>
function Get-DialogueManagerTrees {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    $nodes = @()
    $lines = $Content -split "`r?`n"
    $lineNumber = 0
    $currentNode = $null
    $currentTitle = 'start'
    $inCondition = $false
    $conditionDepth = 0
    
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
            $variables = Get-DialogueVariables -Text $text
            
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
            $inCondition = $true
            $conditionDepth = 1
            
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
    
    return ,$nodes
}

<#
.SYNOPSIS
    Extracts dialogue trees from JSON format.

.DESCRIPTION
    Parses JSON dialogue files and extracts structured dialogue nodes.

.PARAMETER Content
    JSON content string.

.OUTPUTS
    System.Array. Array of dialogue node objects.
#>
function Get-JsonDialogueTrees {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
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
                
                $nodes += $node
            }
        }
        # Handle object format with named nodes
        elseif ($json -is [System.Management.Automation.PSCustomObject]) {
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
        
        return ,$nodes
    }
    catch {
        Write-Warning "[Get-JsonDialogueTrees] Failed to parse JSON: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts dialogue patterns from GDScript files.

.DESCRIPTION
    Parses GDScript files to identify dialogue system implementations
    and embedded dialogue data.

.PARAMETER Content
    GDScript content string.

.OUTPUTS
    System.Array. Array of dialogue structure objects.
#>
function Get-GDScriptDialogueTrees {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    $dialogues = @()
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
                type = 'gdscript_dialogue'
                lineNumber = $lineNumber
                entries = @()
            }
            $braceDepth = 0
            continue
        }
        
        # Track brace depth in dialogue array
        if ($inDialogueArray) {
            $braceDepth += ($line -crep '[^{]').Length - ($line -crep '[^}]').Length
            
            # Try to extract dictionary entries
            if ($trimmed -match '"speaker"\s*:\s*"([^"]*)"') {
                $speaker = $matches[1]
                $text = ''
                
                if ($trimmed -match '"text"\s*:\s*"([^"]*)"') {
                    $text = $matches[1]
                }
                
                $currentDialogue.entries += @{
                    speaker = $speaker
                    text = $text
                    lineNumber = $lineNumber
                }
            }
            
            # End of array
            if ($braceDepth -le 0 -and $line -match '\]') {
                $inDialogueArray = $false
                $dialogues += $currentDialogue
                $currentDialogue = $null
            }
        }
    }
    
    return ,$dialogues
}

<#
.SYNOPSIS
    Extracts BBCode tags from dialogue text.

.DESCRIPTION
    Parses dialogue text and extracts BBCode formatting tags
    like color, bold, wave, shake, wait, speed, etc.

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
    
    # Color tags
    $matches = [regex]::Matches($Text, $script:DialoguePatterns.BBCodeColor)
    foreach ($match in $matches) {
        $tags += @{
            type = 'color'
            text = $match.Groups['text'].Value
        }
    }
    
    # Bold tags
    $matches = [regex]::Matches($Text, $script:DialoguePatterns.BBCodeBold)
    foreach ($match in $matches) {
        $tags += @{
            type = 'bold'
            text = $match.Groups['text'].Value
        }
    }
    
    # Italic tags
    $matches = [regex]::Matches($Text, $script:DialoguePatterns.BBCodeItalic)
    foreach ($match in $matches) {
        $tags += @{
            type = 'italic'
            text = $match.Groups['text'].Value
        }
    }
    
    # Wave tags
    $matches = [regex]::Matches($Text, $script:DialoguePatterns.BBCodeWave)
    foreach ($match in $matches) {
        $tags += @{
            type = 'wave'
            text = $match.Groups['text'].Value
        }
    }
    
    # Shake tags
    $matches = [regex]::Matches($Text, $script:DialoguePatterns.BBCodeShake)
    foreach ($match in $matches) {
        $tags += @{
            type = 'shake'
            text = $match.Groups['text'].Value
        }
    }
    
    # Wait tags
    $matches = [regex]::Matches($Text, $script:DialoguePatterns.BBCodeWait)
    foreach ($match in $matches) {
        $tags += @{
            type = 'wait'
            time = [double]$match.Groups['time'].Value
        }
    }
    
    # Speed tags
    $matches = [regex]::Matches($Text, $script:DialoguePatterns.BBCodeSpeed)
    foreach ($match in $matches) {
        $tags += @{
            type = 'speed'
            speed = [double]$match.Groups['speed'].Value
        }
    }
    
    # Portrait tags
    $matches = [regex]::Matches($Text, $script:DialoguePatterns.BBCodePortrait)
    foreach ($match in $matches) {
        $tags += @{
            type = 'portrait'
            portrait = $match.Groups['portrait'].Value
        }
    }
    
    return ,$tags
}

<#
.SYNOPSIS
    Extracts variable references from dialogue text.

.DESCRIPTION
    Parses dialogue text and extracts variable placeholders
    like {{variable}} or $variable.

.PARAMETER Text
    The dialogue text to parse.

.OUTPUTS
    System.Array. Array of variable names.
#>
function Get-DialogueVariables {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )
    
    $variables = @()
    
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
    
    return $variables | Select-Object -Unique
}

<#
.SYNOPSIS
    Extracts conversation flows from dialogue trees.

.DESCRIPTION
    Analyzes dialogue trees and extracts conversation flow patterns,
    including linear paths, branching paths, and loops.

.PARAMETER DialogueNodes
    Array of dialogue nodes from Get-DialogueTrees.

.OUTPUTS
    System.Collections.Hashtable. Conversation flow analysis.

.EXAMPLE
    $nodes = Get-DialogueTrees -Path "res://dialogue/npc.dialogue"
    $flows = Get-ConversationFlows -DialogueNodes $nodes
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
    
    $visited = @{}
    $nodeDict = @{}
    
    # Build node dictionary
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

.DESCRIPTION
    Analyzes dialogue trees and extracts all conditional checks
    including variable checks and state checks.

.PARAMETER DialogueNodes
    Array of dialogue nodes from Get-DialogueTrees.

.OUTPUTS
    System.Array. Array of condition check objects.

.EXAMPLE
    $nodes = Get-DialogueTrees -Path "res://dialogue/npc.dialogue"
    $conditions = Get-ConditionChecks -DialogueNodes $nodes
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
    
    return ,$conditions
}

<#
.SYNOPSIS
    Extracts localization patterns from dialogue.

.DESCRIPTION
    Analyzes dialogue content and extracts localization-related
    patterns including translation keys, CSV references, etc.

.PARAMETER Path
    Path to the dialogue file.

.PARAMETER Content
    Dialogue content string (alternative to Path).

.PARAMETER DialogueNodes
    Pre-extracted dialogue nodes.

.OUTPUTS
    System.Collections.Hashtable. Localization pattern analysis.

.EXAMPLE
    $loc = Get-LocalizationPatterns -Path "res://dialogue/npc.dialogue"
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
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Warning "File not found: $Path"
                return $null
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        $localization = @{
            hasExplicitKeys = $false
            translationKeys = @()
            variablesUsed = @()
            bbcodeUsed = @()
            characterNames = @()
            suggestedKeys = @()
        }
        
        # Get nodes if not provided
        if ($PSCmdlet.ParameterSetName -ne 'Nodes') {
            $DialogueNodes = Get-DialogueTrees -Content $Content
        }
        
        foreach ($node in $DialogueNodes) {
            # Collect translation keys
            if ($node.translationKey) {
                $localization.hasExplicitKeys = $true
                $localization.translationKeys += $node.translationKey
            }
            elseif ($node.character -and $node.text) {
                # Suggest a key based on character and context
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
        Write-Error "[Get-LocalizationPatterns] Failed to extract localization patterns: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Main entry point for parsing dialogue files.

.DESCRIPTION
    Parses a dialogue file and returns complete structured extraction
    with dialogue trees, flows, conditions, and localization data.

.PARAMETER Path
    Path to the dialogue file.

.PARAMETER Content
    Dialogue content string (alternative to Path).

.PARAMETER Format
    Format of the dialogue file (auto, dialogue_manager, json, gdscript).

.OUTPUTS
    System.Collections.Hashtable. Complete dialogue extraction.

.EXAMPLE
    $result = Invoke-DialogueExtract -Path "res://dialogue/npc.dialogue"
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
        # Load content
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Warning "File not found: $Path"
                return $null
            }
            $filePath = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            
            # Auto-detect format
            if ($Format -eq 'auto') {
                $ext = [System.IO.Path]::GetExtension($Path).ToLower()
                switch ($ext) {
                    '.dialogue' { $Format = 'dialogue_manager' }
                    '.json' { $Format = 'json' }
                    '.gd' { $Format = 'gdscript' }
                    default { $Format = 'dialogue_manager' }
                }
            }
        }
        else {
            $filePath = 'inline'
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return $null
        }
        
        # Extract all components
        $nodes = Get-DialogueTrees -Content $Content -Format $Format
        $flows = Get-ConversationFlows -DialogueNodes $nodes
        $conditions = Get-ConditionChecks -DialogueNodes $nodes
        $localization = Get-LocalizationPatterns -DialogueNodes $nodes
        
        $result = @{
            filePath = $filePath
            fileType = $Format
            nodes = $nodes
            flows = $flows
            conditions = $conditions
            localization = $localization
            statistics = @{
                totalNodes = $nodes.Count
                totalChoices = $flows.totalChoices
                branchPoints = $flows.branchPoints.Count
                endPoints = $flows.endPoints.Count
                conditionChecks = $conditions.Count
                hasExplicitTranslations = $localization.hasExplicitKeys
                characterCount = $localization.characterNames.Count
            }
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        Write-Verbose "[Invoke-DialogueExtract] Extraction complete: $($nodes.Count) nodes, $($conditions.Count) conditions"
        
        return $result
    }
    catch {
        Write-Error "[Invoke-DialogueExtract] Failed to extract dialogue: $_"
        return $null
    }
}

# ============================================================================
# Export Module Members
# ============================================================================

if ($null -ne $MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Get-DialogueTrees'
        'Get-ConversationFlows'
        'Get-ConditionChecks'
        'Get-LocalizationPatterns'
        'Invoke-DialogueExtract'
        'Get-BBCodeTags'
        'Get-DialogueVariables'
    )
}
