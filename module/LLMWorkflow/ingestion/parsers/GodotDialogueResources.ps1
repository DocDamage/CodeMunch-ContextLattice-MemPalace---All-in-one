#requires -Version 5.1
Set-StrictMode -Version Latest

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


