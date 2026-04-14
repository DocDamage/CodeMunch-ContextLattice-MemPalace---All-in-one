#requires -Version 5.1
Set-StrictMode -Version Latest

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


