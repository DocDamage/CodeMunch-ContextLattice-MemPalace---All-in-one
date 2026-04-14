#Requires -Version 5.1
<#
.SYNOPSIS
    Godot AI Behavior extractor for LLM Workflow Extraction Pipeline.

.DESCRIPTION
    Extracts structured AI behavior patterns from Godot GDScript files and scene files.
    Parses behavior trees, state machines, AI actions, and blackboard schemas.
    Supports various Godot AI frameworks including LimboAI and Godot-FiniteStateMachine.

    This parser implements Section 25.6 of the canonical architecture for the
    Godot Engine pack's structured extraction pipeline.

.REQUIRED FUNCTIONS
    - Extract-BehaviorTreeNodes: Extract behavior tree node definitions
    - Extract-StateMachineStates: Extract FSM states and transitions
    - Extract-AIActionDefinitions: Extract AI action patterns
    - Extract-BlackboardSchema: Extract blackboard variable schemas

.PARAMETER Path
    Path to the GDScript file (.gd) or scene file (.tscn) to parse.

.PARAMETER Content
    File content string (alternative to Path).

.OUTPUTS
    JSON with behavior definitions, state transitions, action mappings,
    and provenance metadata (source file, extraction timestamp, parser version).

.NOTES
    File Name      : GodotAIBehaviorExtractor.ps1
    Author         : LLM Workflow Team
    Version        : 2.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Engine Support : Godot 4.x (with Godot 3.x compatibility)
    Pack           : godot-engine
#>

Set-StrictMode -Version Latest

# ============================================================================
# Module Constants and Version
# ============================================================================

$script:ParserVersion = '2.0.0'
$script:ParserName = 'GodotAIBehaviorExtractor'

# Supported AI framework patterns
$script:AIPatterns = @{
    # Behavior Tree patterns (LimboAI)
    BTNodeBase = 'extends\s+(?:BT\w+|Limbo\w+|BehaviorTree\w+)'
    BTTask = 'extends\s+BT\w*Task'
    BTComposite = 'extends\s+BT\w*Composite'
    BTDecorator = 'extends\s+BT\w*Decorator'
    BTCondition = 'extends\s+BT\w*Condition'
    BTAction = 'extends\s+BT\w*Action'
    
    # State Machine patterns (Godot-FiniteStateMachine, LimboState)
    StateMachineBase = 'extends\s+(?:StateMachine|FiniteStateMachine|StateChart|LimboHSM)'
    StateNode = 'extends\s+(?:State|State\w+|LimboState)'
    StateTransition = '\.transition\s*\(\s*["''](?<target>\w+)["'']\s*\)'
    StateChange = 'change_state\s*\(\s*["''](?<target>\w+)["'']\s*\)'
    StatePush = 'push_state\s*\(\s*["''](?<target>\w+)["'']\s*\)'
    StatePop = 'pop_state\s*\(\s*\)'
    
    # GOAP patterns
    GOAPAction = 'extends\s+(?:GOAPAction|GoapAction)'
    GOAPGoal = 'extends\s+(?:GOAPGoal|GoapGoal)'
    GOAPAgent = 'extends\s+(?:GOAPAgent|GoapAgent)'
    Precondition = '(?:precondition|precondition_|preconditions)\s*\(|@export\s+var\s+preconditions'
    Effect = '(?:effect|effect_|effects)\s*\(|@export\s+var\s+effects'
    
    # Behavior tree lifecycle methods
    BTTick = 'func\s+_tick\s*\([^)]*\)'
    BTEnter = 'func\s+_enter\s*\('
    BTExit = 'func\s+_exit\s*\('
    BTSetup = 'func\s+_setup\s*\('
    
    # State callbacks
    StateEnter = 'func\s+(?:enter|_enter|_on_enter)'
    StateExit = 'func\s+(?:exit|_exit|_on_exit)'
    StateUpdate = 'func\s+(?:update|_update|_process|_physics_process)'
    StateInput = 'func\s+(?:handle_input|_input|_unhandled_input)'
    
    # GOAP methods
    GOAPGetCost = 'func\s+get_cost'
    GOAPIsValid = 'func\s+is_valid'
    GOAPPerform = 'func\s+perform'
    GOAPGetWorldState = 'func\s+get_world_state'
    GOAPCreatePlan = 'func\s+create_plan|make_plan'
    
    # Blackboard patterns
    BlackboardSet = '\.blackboard\.set\s*\(\s*["''](?<key>\w+)["'']\s*,\s*(?<val>[^)]+)\s*\)'
    BlackboardGet = '\.blackboard\.get\s*\(\s*["''](?<key>\w+)["'']\s*\)'
    BlackboardHas = '\.blackboard\.has\s*\(\s*["''](?<key>\w+)["'']\s*\)'
    BlackboardExport = '@export\s+var\s+\w+_blackboard|@export\s+var\s+blackboard'
    
    # Utility AI patterns
    UtilityConsideration = 'extends\s+Consideration'
    UtilityAction = 'extends\s+UtilityAction|UtilityAIAction'
    UtilityScore = 'func\s+(?:score|get_score|calculate_score)'
    
    # Sensor patterns
    SensorBase = 'extends\s+Sensor'
    Sense = 'func\s+sense'
    Stimulus = '@export\s+var\s+\w+_stimulus'
    
    # Scene file patterns for behavior trees
    BTSceneNode = 'type="BT\w+"'
    StateSceneNode = 'type="State\w+"|type="LimboState"'
    NodeNameAttr = 'name="(?<name>[^"]+)"'
    NodeTypeAttr = 'type="(?<type>[^"]+)"'
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
    Gets file metadata for extraction context.
.DESCRIPTION
    Collects file information including size, line count, and modification time.
.PARAMETER Path
    Path to the file.
.OUTPUTS
    System.Collections.Hashtable. File metadata object.
#>
function Get-FileMetadata {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        $fileInfo = Get-Item -LiteralPath $Path
        $content = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
        $lineCount = if ($content) { @($content -split "`r?`n").Count } else { 0 }
        
        return @{
            fileSize = $fileInfo.Length
            lineCount = $lineCount
            lastModified = $fileInfo.LastWriteTimeUtc.ToString("o")
            extension = $fileInfo.Extension
        }
    }
    catch {
        return @{
            fileSize = 0
            lineCount = 0
            lastModified = $null
            extension = [System.IO.Path]::GetExtension($Path)
        }
    }
}

# ============================================================================
# Public API Functions - Required by Canonical Document Section 25.6
# ============================================================================

<#
.SYNOPSIS
    Extracts behavior tree node definitions from Godot files.

.DESCRIPTION
    Parses GDScript files (.gd) or scene files (.tscn) to identify behavior tree 
    node definitions including composites, decorators, tasks, conditions, and actions.
    Supports LimboAI and Godot Behavior Tree frameworks.

.PARAMETER Path
    Path to the GDScript file or scene file.

.PARAMETER Content
    File content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - nodes: Array of behavior tree node objects
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $btNodes = Extract-BehaviorTreeNodes -Path "res://ai/enemy_ai.gd"
    
    $btNodes = Extract-BehaviorTreeNodes -Content $gdscriptContent
#>
function Extract-BehaviorTreeNodes {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    nodes = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ totalNodes = 0; byType = @{} }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                nodes = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ totalNodes = 0; byType = @{} }
            }
        }
        
        $btNodes = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        $currentNode = $null
        $inClass = $false
        
        foreach ($line in $lines) {
            $lineNumber++
            $trimmed = $line.Trim()
            
            # Detect behavior tree node types
            $nodeType = $null
            if ($line -match $script:AIPatterns.BTTask) {
                $nodeType = 'task'
            }
            elseif ($line -match $script:AIPatterns.BTComposite) {
                $nodeType = 'composite'
            }
            elseif ($line -match $script:AIPatterns.BTDecorator) {
                $nodeType = 'decorator'
            }
            elseif ($line -match $script:AIPatterns.BTCondition) {
                $nodeType = 'condition'
            }
            elseif ($line -match $script:AIPatterns.BTAction) {
                $nodeType = 'action'
            }
            elseif ($line -match $script:AIPatterns.BTNodeBase) {
                $nodeType = 'node'
            }
            
            if ($nodeType) {
                # Extract class name if available
                $className = ''
                if ($trimmed -match 'class_name\s+(\w+)') {
                    $className = $matches[1]
                }
                
                # Extract parent class
                $extends = ''
                if ($line -match 'extends\s+(\w+)') {
                    $extends = $matches[1]
                }
                
                $currentNode = @{
                    id = [System.Guid]::NewGuid().ToString()
                    type = $nodeType
                    className = $className
                    extends = $extends
                    lineNumber = $lineNumber
                    methods = @{
                        tick = $false
                        enter = $false
                        exit = $false
                        setup = $false
                    }
                    blackboardAccess = @{
                        reads = @()
                        writes = @()
                    }
                    children = @()
                    properties = @()
                }
                $inClass = $true
            }
            
            if ($currentNode -and $inClass) {
                # Check for lifecycle methods
                if ($line -match $script:AIPatterns.BTTick) {
                    $currentNode.methods.tick = $true
                }
                if ($line -match $script:AIPatterns.BTEnter) {
                    $currentNode.methods.enter = $true
                }
                if ($line -match $script:AIPatterns.BTExit) {
                    $currentNode.methods.exit = $true
                }
                if ($line -match $script:AIPatterns.BTSetup) {
                    $currentNode.methods.setup = $true
                }
                
                # Check for blackboard access
                if ($line -match $script:AIPatterns.BlackboardGet -or 
                    $line -match $script:AIPatterns.BlackboardHas) {
                    $currentNode.blackboardAccess.reads += $matches['key']
                }
                if ($line -match $script:AIPatterns.BlackboardSet) {
                    $currentNode.blackboardAccess.writes += @{
                        key = $matches['key']
                        value = $matches['val'].Trim()
                        lineNumber = $lineNumber
                    }
                }
                
                # Check for @export properties
                if ($line -match '^\s*@export\s+var\s+(\w+)') {
                    $currentNode.properties += @{
                        name = $matches[1]
                        lineNumber = $lineNumber
                    }
                }
                
                # Detect next function definition as end of current analysis
                if ($line -match '^func\s+\w+\s*\(' -and $lineNumber -gt $currentNode.lineNumber + 20) {
                    if ($currentNode.methods.tick -or $currentNode.methods.enter) {
                        $btNodes += $currentNode
                    }
                    $currentNode = $null
                    $inClass = $false
                }
                
                # Detect class end
                if ($line -match '^class\s' -or $lineNumber -eq $lines.Count) {
                    if ($currentNode.methods.tick -or $currentNode.methods.enter) {
                        $btNodes += $currentNode
                    }
                    $currentNode = $null
                    $inClass = $false
                }
            }
        }
        
        # Add last node
        if ($currentNode -and ($currentNode.methods.tick -or $currentNode.methods.enter)) {
            $btNodes += $currentNode
        }
        
        # Calculate statistics
        $byType = @{}
        foreach ($node in $btNodes) {
            if (-not $byType.ContainsKey($node.type)) {
                $byType[$node.type] = 0
            }
            $byType[$node.type]++
        }
        
        Write-Verbose "[$script:ParserName] Extracted $($btNodes.Count) behavior tree nodes"
        
        return @{
            nodes = $btNodes
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                totalNodes = $btNodes.Count
                byType = $byType
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract behavior tree nodes: $_"
        return @{
            nodes = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ totalNodes = 0; byType = @{} }
        }
    }
}

<#
.SYNOPSIS
    Extracts FSM (Finite State Machine) states and transitions from Godot files.

.DESCRIPTION
    Parses GDScript files or scene files to identify state machine implementations,
    states, transitions, and state callbacks. Supports Godot-FiniteStateMachine,
    LimboState, and StateChart frameworks.

.PARAMETER Path
    Path to the GDScript file or scene file.

.PARAMETER Content
    File content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - states: Array of state definitions
    - transitions: Array of transition definitions
    - isStateMachine: Whether the file contains a state machine
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $fsm = Extract-StateMachineStates -Path "res://ai/enemy_states.gd"
    
    $fsm = Extract-StateMachineStates -Content $gdscriptContent
#>
function Extract-StateMachineStates {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    states = @()
                    transitions = @()
                    isStateMachine = $false
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ stateCount = 0; transitionCount = 0 }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                states = @()
                transitions = @()
                isStateMachine = $false
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ stateCount = 0; transitionCount = 0 }
            }
        }
        
        $stateMachine = @{
            states = @()
            transitions = @()
            isStateMachine = $false
            hasStateChart = $false
            machineType = 'none'
        }
        
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        $currentState = $null
        $stateTransitions = @()
        
        foreach ($line in $lines) {
            $lineNumber++
            $trimmed = $line.Trim()
            
            # Check if this is a state machine file
            if ($line -match $script:AIPatterns.StateMachineBase) {
                $stateMachine.isStateMachine = $true
                if ($line -match 'LimboHSM') {
                    $stateMachine.machineType = 'limbo_hsm'
                }
                elseif ($line -match 'StateChart') {
                    $stateMachine.hasStateChart = $true
                    $stateMachine.machineType = 'statechart'
                }
                else {
                    $stateMachine.machineType = 'fsm'
                }
            }
            
            # Detect state definitions
            if ($line -match $script:AIPatterns.StateNode) {
                $className = ''
                if ($trimmed -match 'class_name\s+(\w+)') {
                    $className = $matches[1]
                }
                
                $extends = ''
                if ($line -match 'extends\s+(\w+)') {
                    $extends = $matches[1]
                }
                
                $currentState = @{
                    id = [System.Guid]::NewGuid().ToString()
                    name = $className
                    lineNumber = $lineNumber
                    extends = $extends
                    callbacks = @{
                        enter = $false
                        exit = $false
                        update = $false
                        physicsUpdate = $false
                        handleInput = $false
                    }
                    transitions = @()
                    properties = @()
                }
            }
            
            if ($currentState) {
                # Check for state callbacks
                if ($line -match $script:AIPatterns.StateEnter) {
                    $currentState.callbacks.enter = $true
                }
                if ($line -match $script:AIPatterns.StateExit) {
                    $currentState.callbacks.exit = $true
                }
                if ($line -match $script:AIPatterns.StateUpdate) {
                    if ($line -match '_physics_process') {
                        $currentState.callbacks.physicsUpdate = $true
                    }
                    else {
                        $currentState.callbacks.update = $true
                    }
                }
                if ($line -match $script:AIPatterns.StateInput) {
                    $currentState.callbacks.handleInput = $true
                }
                
                # Check for @export properties
                if ($line -match '^\s*@export\s+var\s+(\w+)') {
                    $currentState.properties += @{
                        name = $matches[1]
                        lineNumber = $lineNumber
                    }
                }
                
                # Check for transitions from this state
                if ($line -match $script:AIPatterns.StateTransition) {
                    $transition = @{
                        id = [System.Guid]::NewGuid().ToString()
                        to = $matches['target']
                        from = $currentState.name
                        lineNumber = $lineNumber
                        type = 'transition'
                    }
                    $currentState.transitions += $transition
                    $stateMachine.transitions += $transition
                }
                if ($line -match $script:AIPatterns.StateChange) {
                    $transition = @{
                        id = [System.Guid]::NewGuid().ToString()
                        to = $matches['target']
                        from = $currentState.name
                        lineNumber = $lineNumber
                        type = 'change'
                    }
                    $currentState.transitions += $transition
                    $stateMachine.transitions += $transition
                }
                if ($line -match $script:AIPatterns.StatePush) {
                    $transition = @{
                        id = [System.Guid]::NewGuid().ToString()
                        to = $matches['target']
                        from = $currentState.name
                        lineNumber = $lineNumber
                        type = 'push'
                    }
                    $currentState.transitions += $transition
                    $stateMachine.transitions += $transition
                }
                if ($line -match $script:AIPatterns.StatePop) {
                    $transition = @{
                        id = [System.Guid]::NewGuid().ToString()
                        to = 'POP'
                        from = $currentState.name
                        lineNumber = $lineNumber
                        type = 'pop'
                    }
                    $currentState.transitions += $transition
                    $stateMachine.transitions += $transition
                }
                
                # End of state class (next class or EOF)
                if ($line -match '^class\s' -or $lineNumber -eq $lines.Count) {
                    $stateMachine.states += $currentState
                    $currentState = $null
                }
            }
        }
        
        # Add last state
        if ($currentState) {
            $stateMachine.states += $currentState
        }
        
        Write-Verbose "[$script:ParserName] Extracted $($stateMachine.states.Count) states, $($stateMachine.transitions.Count) transitions"
        
        return @{
            states = $stateMachine.states
            transitions = $stateMachine.transitions
            isStateMachine = $stateMachine.isStateMachine
            hasStateChart = $stateMachine.hasStateChart
            machineType = $stateMachine.machineType
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                stateCount = $stateMachine.states.Count
                transitionCount = $stateMachine.transitions.Count
                transitionTypes = ($stateMachine.transitions | Group-Object -Property type | ForEach-Object { @{ type = $_.Name; count = $_.Count } })
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract state machine states: $_"
        return @{
            states = @()
            transitions = @()
            isStateMachine = $false
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ stateCount = 0; transitionCount = 0 }
        }
    }
}

<#
.SYNOPSIS
    Extracts AI action definitions from Godot files.

.DESCRIPTION
    Parses GDScript files to identify AI action patterns including GOAP actions,
    utility AI actions, and behavior tree actions. Extracts action metadata,
    preconditions, effects, and scoring methods.

.PARAMETER Path
    Path to the GDScript file.

.PARAMETER Content
    GDScript content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - actions: Array of AI action definitions
    - goals: Array of GOAP goals (if applicable)
    - agents: Array of GOAP agents (if applicable)
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $actions = Extract-AIActionDefinitions -Path "res://ai/goap_agent.gd"
    
    $actions = Extract-AIActionDefinitions -Content $gdscriptContent
#>
function Extract-AIActionDefinitions {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    actions = @()
                    goals = @()
                    agents = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ actionCount = 0; goalCount = 0; agentCount = 0 }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                actions = @()
                goals = @()
                agents = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ actionCount = 0; goalCount = 0; agentCount = 0 }
            }
        }
        
        $result = @{
            actions = @()
            goals = @()
            agents = @()
            isGOAP = $false
            isUtilityAI = $false
        }
        
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        $currentElement = $null
        $elementType = $null
        
        foreach ($line in $lines) {
            $lineNumber++
            $trimmed = $line.Trim()
            
            # Detect GOAP element types
            if ($line -match $script:AIPatterns.GOAPAction) {
                $elementType = 'action'
                $result.isGOAP = $true
                $className = ''
                if ($trimmed -match 'class_name\s+(\w+)') {
                    $className = $matches[1]
                }
                $currentElement = @{
                    id = [System.Guid]::NewGuid().ToString()
                    name = $className
                    type = 'goap_action'
                    lineNumber = $lineNumber
                    preconditions = @()
                    effects = @()
                    methods = @{
                        getCost = $false
                        isValid = $false
                        perform = $false
                    }
                    cost = 1
                }
            }
            elseif ($line -match $script:AIPatterns.GOAPGoal) {
                $elementType = 'goal'
                $result.isGOAP = $true
                $className = ''
                if ($trimmed -match 'class_name\s+(\w+)') {
                    $className = $matches[1]
                }
                $currentElement = @{
                    id = [System.Guid]::NewGuid().ToString()
                    name = $className
                    type = 'goap_goal'
                    lineNumber = $lineNumber
                    priority = $null
                    conditions = @()
                }
            }
            elseif ($line -match $script:AIPatterns.GOAPAgent) {
                $elementType = 'agent'
                $result.isGOAP = $true
                $className = ''
                if ($trimmed -match 'class_name\s+(\w+)') {
                    $className = $matches[1]
                }
                $currentElement = @{
                    id = [System.Guid]::NewGuid().ToString()
                    name = $className
                    type = 'goap_agent'
                    lineNumber = $lineNumber
                    availableActions = @()
                    goals = @()
                }
            }
            elseif ($line -match $script:AIPatterns.UtilityAction) {
                $elementType = 'utility_action'
                $result.isUtilityAI = $true
                $className = ''
                if ($trimmed -match 'class_name\s+(\w+)') {
                    $className = $matches[1]
                }
                $currentElement = @{
                    id = [System.Guid]::NewGuid().ToString()
                    name = $className
                    type = 'utility_action'
                    lineNumber = $lineNumber
                    scoreMethod = $false
                    considerations = @()
                }
            }
            
            if ($currentElement) {
                # Check for GOAP methods
                if ($line -match $script:AIPatterns.GOAPGetCost) {
                    $currentElement.methods.getCost = $true
                    # Try to extract constant cost
                    if ($line -match 'return\s+(\d+)') {
                        $currentElement.cost = [int]$matches[1]
                    }
                }
                if ($line -match $script:AIPatterns.GOAPIsValid) {
                    $currentElement.methods.isValid = $true
                }
                if ($line -match $script:AIPatterns.GOAPPerform) {
                    $currentElement.methods.perform = $true
                }
                if ($line -match $script:AIPatterns.GOAPGetWorldState) {
                    $currentElement.methods.getWorldState = $true
                }
                if ($line -match $script:AIPatterns.GOAPCreatePlan) {
                    $currentElement.methods.createPlan = $true
                }
                
                # Extract preconditions
                if ($line -match $script:AIPatterns.Precondition) {
                    # Try to extract precondition key-value
                    if ($line -match '["''](\w+)["'']\s*:\s*([^,\]]+)') {
                        $currentElement.preconditions += @{
                            key = $matches[1]
                            value = $matches[2].Trim()
                            lineNumber = $lineNumber
                        }
                    }
                }
                
                # Extract effects
                if ($line -match $script:AIPatterns.Effect) {
                    # Try to extract effect key-value
                    if ($line -match '["''](\w+)["'']\s*:\s*([^,\]]+)') {
                        $currentElement.effects += @{
                            key = $matches[1]
                            value = $matches[2].Trim()
                            lineNumber = $lineNumber
                        }
                    }
                }
                
                # Check for utility scoring
                if ($line -match $script:AIPatterns.UtilityScore) {
                    $currentElement.scoreMethod = $true
                }
                
                # End of class
                if ($line -match '^class\s' -or $lineNumber -eq $lines.Count) {
                    switch ($elementType) {
                        'action' { $result.actions += $currentElement }
                        'goal' { $result.goals += $currentElement }
                        'agent' { $result.agents += $currentElement }
                        'utility_action' { $result.actions += $currentElement }
                    }
                    $currentElement = $null
                    $elementType = $null
                }
            }
        }
        
        # Add last element
        if ($currentElement) {
            switch ($elementType) {
                'action' { $result.actions += $currentElement }
                'goal' { $result.goals += $currentElement }
                'agent' { $result.agents += $currentElement }
                'utility_action' { $result.actions += $currentElement }
            }
        }
        
        Write-Verbose "[$script:ParserName] Extracted $($result.actions.Count) actions, $($result.goals.Count) goals"
        
        return @{
            actions = $result.actions
            goals = $result.goals
            agents = $result.agents
            isGOAP = $result.isGOAP
            isUtilityAI = $result.isUtilityAI
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                actionCount = $result.actions.Count
                goalCount = $result.goals.Count
                agentCount = $result.agents.Count
                isGOAP = $result.isGOAP
                isUtilityAI = $result.isUtilityAI
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract AI action definitions: $_"
        return @{
            actions = @()
            goals = @()
            agents = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ actionCount = 0; goalCount = 0; agentCount = 0 }
        }
    }
}

<#
.SYNOPSIS
    Extracts blackboard variable schemas from Godot files.

.DESCRIPTION
    Parses GDScript files to identify blackboard variable definitions,
    including exports, type annotations, and access patterns. Supports
    LimboAI blackboards and custom blackboard implementations.

.PARAMETER Path
    Path to the GDScript file.

.PARAMETER Content
    GDScript content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - schema: Array of blackboard variable definitions
    - accessPatterns: Array of blackboard access patterns (read/write)
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $blackboard = Extract-BlackboardSchema -Path "res://ai/enemy_ai.gd"
    
    $blackboard = Extract-BlackboardSchema -Content $gdscriptContent
#>
function Extract-BlackboardSchema {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    schema = @()
                    accessPatterns = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ variableCount = 0; readCount = 0; writeCount = 0 }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                schema = @()
                accessPatterns = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ variableCount = 0; readCount = 0; writeCount = 0 }
            }
        }
        
        $schema = @{
            variables = @()
            accessPatterns = @()
            hasBlackboard = $false
        }
        
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        $seenVariables = @{}
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Check for blackboard export
            if ($line -match $script:AIPatterns.BlackboardExport) {
                $schema.hasBlackboard = $true
            }
            
            # Extract blackboard reads (get/has)
            if ($line -match $script:AIPatterns.BlackboardGet) {
                $schema.hasBlackboard = $true
                $key = $matches['key']
                if (-not $seenVariables.ContainsKey($key)) {
                    $seenVariables[$key] = @{
                        key = $key
                        type = 'unknown'
                        accessType = 'read'
                        lineNumbers = @()
                    }
                }
                $seenVariables[$key].lineNumbers += $lineNumber
                $seenVariables[$key].accessType = 'read'
                
                $schema.accessPatterns += @{
                    variable = $key
                    accessType = 'read'
                    operation = 'get'
                    lineNumber = $lineNumber
                    code = $line.Trim()
                }
            }
            
            if ($line -match $script:AIPatterns.BlackboardHas) {
                $schema.hasBlackboard = $true
                $key = $matches['key']
                $schema.accessPatterns += @{
                    variable = $key
                    accessType = 'read'
                    operation = 'has'
                    lineNumber = $lineNumber
                    code = $line.Trim()
                }
            }
            
            # Extract blackboard writes (set)
            if ($line -match $script:AIPatterns.BlackboardSet) {
                $schema.hasBlackboard = $true
                $key = $matches['key']
                $value = $matches['val'].Trim()
                
                if (-not $seenVariables.ContainsKey($key)) {
                    $seenVariables[$key] = @{
                        key = $key
                        type = 'unknown'
                        accessType = 'write'
                        lineNumbers = @()
                    }
                }
                $seenVariables[$key].lineNumbers += $lineNumber
                $seenVariables[$key].accessType = 'write'
                
                # Infer type from value
                $inferredType = 'unknown'
                if ($value -match '^\d+$') {
                    $inferredType = 'int'
                }
                elseif ($value -match '^[\d.]+$') {
                    $inferredType = 'float'
                }
                elseif ($value -match '^["\'']') {
                    $inferredType = 'String'
                }
                elseif ($value -match '^(true|false)$') {
                    $inferredType = 'bool'
                }
                elseif ($value -match '^Vector[23]') {
                    $inferredType = 'Vector'
                }
                elseif ($value -match '^\$') {
                    $inferredType = 'Node'
                }
                
                $schema.accessPatterns += @{
                    variable = $key
                    accessType = 'write'
                    operation = 'set'
                    lineNumber = $lineNumber
                    value = $value
                    inferredType = $inferredType
                    code = $line.Trim()
                }
            }
        }
        
        # Build variable schema
        foreach ($key in $seenVariables.Keys) {
            $var = $seenVariables[$key]
            
            # Find type annotations in the code
            $typeHint = 'Variant'
            foreach ($line in $lines) {
                # Look for type hints in comments or nearby code
                if ($line -match "#\s*$key\s*:\s*(\w+)" -or 
                    $line -match "##\s*$key\s*:\s*(\w+)") {
                    $typeHint = $matches[1]
                    break
                }
            }
            
            $schema.variables += @{
                key = $key
                type = $typeHint
                accessType = $var.accessType
                lineNumbers = $var.lineNumbers
            }
        }
        
        # Calculate statistics
        $readCount = ($schema.accessPatterns | Where-Object { $_.accessType -eq 'read' }).Count
        $writeCount = ($schema.accessPatterns | Where-Object { $_.accessType -eq 'write' }).Count
        
        Write-Verbose "[$script:ParserName] Extracted $($schema.variables.Count) blackboard variables"
        
        return @{
            schema = $schema.variables
            accessPatterns = $schema.accessPatterns
            hasBlackboard = $schema.hasBlackboard
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                variableCount = $schema.variables.Count
                readCount = $readCount
                writeCount = $writeCount
                hasBlackboard = $schema.hasBlackboard
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract blackboard schema: $_"
        return @{
            schema = @()
            accessPatterns = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ variableCount = 0; readCount = 0; writeCount = 0 }
        }
    }
}

# ============================================================================
# Legacy/Compatibility Functions
# ============================================================================

<#
.SYNOPSIS
    Main entry point for parsing AI behavior from Godot files.

.DESCRIPTION
    Parses a GDScript file and returns complete structured extraction
    of AI behavior patterns including behavior trees, state machines,
    AI actions, and blackboard schemas.

.PARAMETER Path
    Path to the GDScript file.

.PARAMETER Content
    GDScript content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Complete AI behavior extraction.

.EXAMPLE
    $result = Invoke-AIBehaviorExtract -Path "res://ai/enemy_ai.gd"
#>
function Invoke-AIBehaviorExtract {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        # Load content
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
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        else {
            $sourceFile = 'inline'
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                filePath = $sourceFile
                success = $false
                error = "Content is empty"
            }
        }
        
        # Get file metadata
        $fileMetadata = @{}
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $fileMetadata = Get-FileMetadata -Path $Path
        }
        
        # Extract all AI patterns using the canonical functions
        $btNodes = Extract-BehaviorTreeNodes -Content $Content
        $stateMachine = Extract-StateMachineStates -Content $Content
        $actions = Extract-AIActionDefinitions -Content $Content
        $blackboard = Extract-BlackboardSchema -Content $Content
        
        # Determine primary AI pattern
        $primaryPattern = 'none'
        if ($btNodes.statistics.totalNodes -gt 0) {
            $primaryPattern = 'behavior_tree'
        }
        elseif ($stateMachine.isStateMachine) {
            $primaryPattern = 'state_machine'
        }
        elseif ($actions.isGOAP) {
            $primaryPattern = 'goap'
        }
        elseif ($actions.isUtilityAI) {
            $primaryPattern = 'utility_ai'
        }
        elseif ($blackboard.hasBlackboard) {
            $primaryPattern = 'blackboard'
        }
        
        $result = @{
            filePath = $sourceFile
            fileType = 'gdscript'
            fileMetadata = $fileMetadata
            primaryAIPattern = $primaryPattern
            behaviorTrees = $btNodes
            stateMachine = $stateMachine
            actions = $actions
            blackboard = $blackboard
            statistics = @{
                behaviorTreeNodes = $btNodes.statistics.totalNodes
                stateCount = $stateMachine.statistics.stateCount
                transitionCount = $stateMachine.statistics.transitionCount
                actionCount = $actions.statistics.actionCount
                goalCount = $actions.statistics.goalCount
                blackboardVariables = $blackboard.statistics.variableCount
            }
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
        }
        
        Write-Verbose "[$script:ParserName] Extraction complete: primary pattern is $primaryPattern"
        
        return $result
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract AI behaviors: $_"
        return @{
            filePath = $sourceFile
            success = $false
            error = $_.ToString()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
        }
    }
}

<#
.SYNOPSIS
    Extracts behavior tree patterns from GDScript files.
    
    DEPRECATED: Use Extract-BehaviorTreeNodes instead.

.DESCRIPTION
    Legacy function for compatibility. Delegates to Extract-BehaviorTreeNodes.
#>
function Get-BehaviorTrees {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    $result = if ($PSCmdlet.ParameterSetName -eq 'Path') {
        Extract-BehaviorTreeNodes -Path $Path
    }
    else {
        Extract-BehaviorTreeNodes -Content $Content
    }
    
    return $result.nodes
}

<#
.SYNOPSIS
    Extracts state machine patterns from GDScript files.
    
    DEPRECATED: Use Extract-StateMachineStates instead.

.DESCRIPTION
    Legacy function for compatibility. Delegates to Extract-StateMachineStates.
#>
function Get-StateMachines {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    $result = if ($PSCmdlet.ParameterSetName -eq 'Path') {
        Extract-StateMachineStates -Path $Path
    }
    else {
        Extract-StateMachineStates -Content $Content
    }
    
    return @{
        states = $result.states
        transitions = $result.transitions
        isStateMachine = $result.isStateMachine
        hasStateChart = $result.hasStateChart
    }
}

<#
.SYNOPSIS
    Extracts GOAP (Goal-Oriented Action Planning) patterns from GDScript files.
    
    DEPRECATED: Use Extract-AIActionDefinitions instead.

.DESCRIPTION
    Legacy function for compatibility. Delegates to Extract-AIActionDefinitions.
#>
function Get-GOAPPatterns {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    $result = if ($PSCmdlet.ParameterSetName -eq 'Path') {
        Extract-AIActionDefinitions -Path $Path
    }
    else {
        Extract-AIActionDefinitions -Content $Content
    }
    
    return @{
        actions = $result.actions
        goals = $result.goals
        agents = $result.agents
        isGOAP = $result.isGOAP
    }
}

<#
.SYNOPSIS
    Extracts navigation mesh usage patterns from GDScript files.

.DESCRIPTION
    Parses GDScript files to identify navigation system usage including
    NavigationAgents, pathfinding calls, avoidance settings, and region setup.

.PARAMETER Path
    Path to the GDScript file.

.PARAMETER Content
    GDScript content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Navigation usage patterns.

.EXAMPLE
    $nav = Get-NavigationPatterns -Path "res://ai/enemy_movement.gd"
#>
function Get-NavigationPatterns {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        # Load content
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Warning "File not found: $Path"
                return $null
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return $null
        }
        
        $navigation = @{
            hasNavigationAgent = $false
            hasNavigationRegion = $false
            usesPathfinding = $false
            usesAvoidance = $false
            agentVariables = @()
            pathQueries = @()
            avoidanceSettings = @()
        }
        
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Check for NavigationAgent
            if ($line -match $script:AIPatterns.NavigationAgent) {
                $navigation.hasNavigationAgent = $true
                if ($line -match 'var\s+(\w+)') {
                    $navigation.agentVariables += $matches[1]
                }
            }
            
            # Check for NavigationRegion
            if ($line -match $script:AIPatterns.NavigationRegion) {
                $navigation.hasNavigationRegion = $true
            }
            
            # Check for pathfinding usage
            if ($line -match $script:AIPatterns.PathFinding) {
                $navigation.usesPathfinding = $true
            }
            if ($line -match $script:AIPatterns.PathQuery) {
                $navigation.pathQueries += @{
                    line = $line.Trim()
                    lineNumber = $lineNumber
                }
            }
            
            # Check for avoidance
            if ($line -match $script:AIPatterns.Avoidance) {
                $navigation.usesAvoidance = $true
                $navigation.avoidanceSettings += @{
                    line = $line.Trim()
                    lineNumber = $lineNumber
                }
            }
        }
        
        return $navigation
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract navigation patterns: $_"
        return $null
    }
}

# ============================================================================
# Public Export Functions - Required API
# ============================================================================

<#
.SYNOPSIS
    Exports behavior tree structure from LimboAI or similar Godot AI frameworks.

.DESCRIPTION
    Extracts and exports behavior tree node definitions, hierarchy, and configuration
    from GDScript files or .tres resource files. Supports LimboAI behavior trees
    and custom BT implementations.

.PARAMETER Path
    Path to the GDScript file (.gd) or resource file (.tres) containing behavior tree definitions.

.PARAMETER OutputPath
    Optional path to write the exported JSON file. If not specified, returns the object.

.PARAMETER IncludeHierarchy
    If specified, includes the full parent-child hierarchy of composite nodes.

.OUTPUTS
    System.Collections.Hashtable. Behavior tree export containing:
    - treeId: Unique identifier for the tree
    - rootNode: The root behavior tree node
    - nodes: Array of all BT nodes with their types and configurations
    - blackboardBindings: Variables bound to the blackboard
    - metadata: Provenance and extraction metadata

.EXAMPLE
    $bt = Export-GodotBehaviorTree -Path "res://ai/enemy_bt.gd"
    
    Export-GodotBehaviorTree -Path "res://ai/player_ai.tres" -OutputPath "./exports/player_bt.json"
#>
function Export-GodotBehaviorTree {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter()]
        [string]$OutputPath,
        
        [Parameter()]
        [switch]$IncludeHierarchy
    )
    
    try {
        Write-Verbose "[$script:ParserName] Exporting behavior tree from: $Path"
        
        # Extract behavior tree nodes using the core function
        $extraction = Extract-BehaviorTreeNodes -Path $Path
        
        if (-not $extraction.metadata.success) {
            Write-Warning "[$script:ParserName] Failed to extract behavior tree: $($extraction.metadata.errors -join '; ')"
            return $extraction
        }
        
        # Build export structure
        $export = @{
            treeId = [System.Guid]::NewGuid().ToString()
            sourceFile = $Path
            exportVersion = $script:ParserVersion
            exportTimestamp = [DateTime]::UtcNow.ToString("o")
            rootNode = $null
            nodes = $extraction.nodes
            hierarchy = @()
            blackboardBindings = @()
            metrics = @{
                totalNodes = $extraction.statistics.totalNodes
                byType = $extraction.statistics.byType
                maxDepth = 0
                leafNodes = 0
                compositeNodes = 0
            }
        }
        
        # Find root node (typically the first node with no parent or a specific root type)
        if ($extraction.nodes.Count -gt 0) {
            $rootCandidates = $extraction.nodes | Where-Object { $_.type -eq 'composite' -or $_.extends -match 'Root' }
            if ($rootCandidates) {
                $export.rootNode = $rootCandidates | Select-Object -First 1
            }
            else {
                $export.rootNode = $extraction.nodes | Select-Object -First 1
            }
        }
        
        # Calculate metrics
        $export.metrics.leafNodes = ($extraction.nodes | Where-Object { 
            $_.type -in @('action', 'condition', 'task') 
        }).Count
        
        $export.metrics.compositeNodes = ($extraction.nodes | Where-Object { 
            $_.type -eq 'composite' 
        }).Count
        
        # Extract blackboard bindings from properties
        foreach ($node in $extraction.nodes) {
            foreach ($prop in $node.properties) {
                if ($prop.name -match 'blackboard|bb_|bb_var') {
                    $export.blackboardBindings += @{
                        nodeId = $node.id
                        nodeName = $node.className
                        variable = $prop.name
                        lineNumber = $prop.lineNumber
                    }
                }
            }
        }
        
        # Write to file if output path specified
        if ($OutputPath) {
            $export | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Verbose "[$script:ParserName] Behavior tree exported to: $OutputPath"
        }
        
        return $export
    }
    catch {
        Write-Error "[$script:ParserName] Failed to export behavior tree: $_"
        return @{
            treeId = $null
            sourceFile = $Path
            success = $false
            error = $_.ToString()
            metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @($_.ToString())
        }
    }
}

<#
.SYNOPSIS
    Exports state machine from Godot-FiniteStateMachine or similar Godot FSM frameworks.

.DESCRIPTION
    Extracts and exports state machine definitions, states, transitions, and callbacks
    from GDScript files or scene files. Supports Godot-FiniteStateMachine, LimboHSM,
    StateChart, and custom FSM implementations.

.PARAMETER Path
    Path to the GDScript file (.gd) or scene file (.tscn) containing state machine definitions.

.PARAMETER OutputPath
    Optional path to write the exported JSON file. If not specified, returns the object.

.PARAMETER IncludeCallbacks
    If specified, includes detailed callback method signatures for each state.

.OUTPUTS
    System.Collections.Hashtable. State machine export containing:
    - machineId: Unique identifier for the state machine
    - machineType: Type of state machine (fsm, limbo_hsm, statechart)
    - states: Array of state definitions with callbacks
    - transitions: Array of transition definitions
    - initialState: The initial state if detected
    - metadata: Provenance and extraction metadata

.EXAMPLE
    $fsm = Export-GodotStateMachine -Path "res://ai/enemy_states.gd"
    
    Export-GodotStateMachine -Path "res://ai/player_fsm.tscn" -OutputPath "./exports/player_fsm.json"
#>
function Export-GodotStateMachine {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter()]
        [string]$OutputPath,
        
        [Parameter()]
        [switch]$IncludeCallbacks
    )
    
    try {
        Write-Verbose "[$script:ParserName] Exporting state machine from: $Path"
        
        # Extract state machine using the core function
        $extraction = Extract-StateMachineStates -Path $Path
        
        if (-not $extraction.metadata.success) {
            Write-Warning "[$script:ParserName] Failed to extract state machine: $($extraction.metadata.errors -join '; ')"
            return $extraction
        }
        
        # Build export structure
        $export = @{
            machineId = [System.Guid]::NewGuid().ToString()
            sourceFile = $Path
            exportVersion = $script:ParserVersion
            exportTimestamp = [DateTime]::UtcNow.ToString("o")
            machineType = $extraction.machineType
            isStateMachine = $extraction.isStateMachine
            hasStateChart = $extraction.hasStateChart
            initialState = $null
            states = $extraction.states
            transitions = $extraction.transitions
            transitionGraph = @()
            metrics = @{
                stateCount = $extraction.statistics.stateCount
                transitionCount = $extraction.statistics.transitionCount
                transitionTypes = $extraction.statistics.transitionTypes
                avgTransitionsPerState = 0
                isHierarchical = $false
            }
        }
        
        # Try to detect initial state (commonly named 'Idle', 'Start', or first state)
        if ($extraction.states.Count -gt 0) {
            $initialCandidates = $extraction.states | Where-Object { 
                $_.name -in @('Idle', 'Start', 'Initial', 'Begin', 'Default') 
            }
            if ($initialCandidates) {
                $export.initialState = $initialCandidates | Select-Object -First 1
            }
            else {
                $export.initialState = $extraction.states | Select-Object -First 1
            }
        }
        
        # Calculate average transitions per state
        if ($extraction.statistics.stateCount -gt 0) {
            $export.metrics.avgTransitionsPerState = [math]::Round(
                $extraction.statistics.transitionCount / $extraction.statistics.stateCount, 
                2
            )
        }
        
        # Detect hierarchical state machine (push/pop transitions)
        $export.metrics.isHierarchical = ($extraction.transitions | Where-Object { 
            $_.type -in @('push', 'pop') 
        }).Count -gt 0
        
        # Build transition graph for visualization
        $transitionGroups = $extraction.transitions | Group-Object -Property from
        foreach ($group in $transitionGroups) {
            $export.transitionGraph += @{
                fromState = $group.Name
                transitions = @($group.Group | ForEach-Object { 
                    @{
                        to = $_.to
                        type = $_.type
                        lineNumber = $_.lineNumber
                    }
                })
            }
        }
        
        # Write to file if output path specified
        if ($OutputPath) {
            $export | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Verbose "[$script:ParserName] State machine exported to: $OutputPath"
        }
        
        return $export
    }
    catch {
        Write-Error "[$script:ParserName] Failed to export state machine: $_"
        return @{
            machineId = $null
            sourceFile = $Path
            success = $false
            error = $_.ToString()
            metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @($_.ToString())
        }
    }
}

<#
.SYNOPSIS
    Exports blackboard/variables configuration from Godot AI files.

.DESCRIPTION
    Extracts and exports blackboard variable schemas, access patterns, and type definitions
    from GDScript files. Supports LimboAI blackboards and custom blackboard implementations.

.PARAMETER Path
    Path to the GDScript file (.gd) containing blackboard definitions.

.PARAMETER OutputPath
    Optional path to write the exported JSON file. If not specified, returns the object.

.PARAMETER IncludeAccessPatterns
    If specified, includes detailed read/write access patterns for each variable.

.OUTPUTS
    System.Collections.Hashtable. Blackboard export containing:
    - blackboardId: Unique identifier for the blackboard configuration
    - variables: Array of variable definitions with types
    - accessPatterns: Read/write access patterns
    - typedSchema: Variables with inferred or explicit types
    - metadata: Provenance and extraction metadata

.EXAMPLE
    $bb = Export-GodotBlackboard -Path "res://ai/enemy_ai.gd"
    
    Export-GodotBlackboard -Path "res://ai/shared_blackboard.gd" -OutputPath "./exports/blackboard.json"
#>
function Export-GodotBlackboard {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter()]
        [string]$OutputPath,
        
        [Parameter()]
        [switch]$IncludeAccessPatterns
    )
    
    try {
        Write-Verbose "[$script:ParserName] Exporting blackboard from: $Path"
        
        # Extract blackboard schema using the core function
        $extraction = Extract-BlackboardSchema -Path $Path
        
        if (-not $extraction.metadata.success) {
            Write-Warning "[$script:ParserName] Failed to extract blackboard: $($extraction.metadata.errors -join '; ')"
            return $extraction
        }
        
        # Build export structure
        $export = @{
            blackboardId = [System.Guid]::NewGuid().ToString()
            sourceFile = $Path
            exportVersion = $script:ParserVersion
            exportTimestamp = [DateTime]::UtcNow.ToString("o")
            hasBlackboard = $extraction.hasBlackboard
            variables = $extraction.schema
            typedSchema = @()
            accessPatterns = if ($IncludeAccessPatterns) { $extraction.accessPatterns } else { @() }
            metrics = @{
                variableCount = $extraction.statistics.variableCount
                readCount = $extraction.statistics.readCount
                writeCount = $extraction.statistics.writeCount
                readWriteRatio = 0
                mostAccessedVariable = $null
            }
        }
        
        # Build typed schema
        foreach ($var in $extraction.schema) {
            $reads = ($extraction.accessPatterns | Where-Object { 
                $_.variable -eq $var.key -and $_.accessType -eq 'read' 
            }).Count
            $writes = ($extraction.accessPatterns | Where-Object { 
                $_.variable -eq $var.key -and $_.accessType -eq 'write' 
            }).Count
            
            $export.typedSchema += @{
                key = $var.key
                type = $var.type
                accessType = $var.accessType
                accessCount = $reads + $writes
                readCount = $reads
                writeCount = $writes
                lineNumbers = $var.lineNumbers
            }
        }
        
        # Calculate read/write ratio
        if ($extraction.statistics.writeCount -gt 0) {
            $export.metrics.readWriteRatio = [math]::Round(
                $extraction.statistics.readCount / $extraction.statistics.writeCount, 
                2
            )
        }
        
        # Find most accessed variable
        $mostAccessed = $export.typedSchema | Sort-Object -Property accessCount -Descending | Select-Object -First 1
        if ($mostAccessed) {
            $export.metrics.mostAccessedVariable = $mostAccessed.key
        }
        
        # Write to file if output path specified
        if ($OutputPath) {
            $export | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Verbose "[$script:ParserName] Blackboard exported to: $OutputPath"
        }
        
        return $export
    }
    catch {
        Write-Error "[$script:ParserName] Failed to export blackboard: $_"
        return @{
            blackboardId = $null
            sourceFile = $Path
            success = $false
            error = $_.ToString()
            metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @($_.ToString())
        }
    }
}

<#
.SYNOPSIS
    Calculates metrics about AI behaviors from extracted data.

.DESCRIPTION
    Analyzes extracted AI behavior data (behavior trees, state machines, blackboards)
    and calculates comprehensive metrics for quality assessment and complexity analysis.

.PARAMETER BehaviorData
    Hashtable containing extracted AI behavior data from Export-GodotBehaviorTree,
    Export-GodotStateMachine, or Export-GodotBlackboard.

.PARAMETER Path
    Path to the GDScript file to analyze directly.

.PARAMETER MetricTypes
    Array of metric categories to calculate: 'complexity', 'coupling', 'cohesion', 'all'.

.OUTPUTS
    System.Collections.Hashtable. Metrics including:
    - complexity: Cyclomatic complexity, nesting depth, node count
    - coupling: Inter-state dependencies, blackboard coupling
    - cohesion: State/action cohesion scores
    - quality: Maintainability, testability indicators

.EXAMPLE
    $bt = Export-GodotBehaviorTree -Path "res://ai/enemy_bt.gd"
    $metrics = Get-GodotAIBehaviorMetrics -BehaviorData $bt
    
    $metrics = Get-GodotAIBehaviorMetrics -Path "res://ai/complex_ai.gd" -MetricTypes @('complexity', 'coupling')
#>
function Get-GodotAIBehaviorMetrics {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(ParameterSetName = 'Data')]
        [hashtable]$BehaviorData,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter()]
        [ValidateSet('complexity', 'coupling', 'cohesion', 'coverage', 'all')]
        [string[]]$MetricTypes = @('all')
    )
    
    try {
        # If path provided, extract data first
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Write-Verbose "[$script:ParserName] Extracting AI behavior data from: $Path"
            $BehaviorData = Invoke-AIBehaviorExtract -Path $Path
        }
        
        if (-not $BehaviorData) {
            Write-Warning "[$script:ParserName] No behavior data provided"
            return $null
        }
        
        $metrics = @{
            sourceFile = if ($BehaviorData.filePath) { $BehaviorData.filePath } else { 'unknown' }
            primaryPattern = $BehaviorData.primaryAIPattern
            metricTypes = $MetricTypes
            timestamp = [DateTime]::UtcNow.ToString("o")
            complexity = @{}
            coupling = @{}
            cohesion = @{}
            coverage = @{}
            overall = @{}
        }
        
        # Calculate complexity metrics
        if ('all' -in $MetricTypes -or 'complexity' -in $MetricTypes) {
            $btMetrics = $BehaviorData.behaviorTrees.statistics
            $fsmMetrics = $BehaviorData.stateMachine.statistics
            $bbMetrics = $BehaviorData.blackboard.statistics
            
            $metrics.complexity = @{
                # Behavior tree complexity
                behaviorTreeNodes = $btMetrics.totalNodes
                behaviorTreeTypes = if ($btMetrics.byType) { $btMetrics.byType.Count } else { 0 }
                
                # State machine complexity
                stateCount = $fsmMetrics.stateCount
                transitionCount = $fsmMetrics.transitionCount
                avgTransitionsPerState = if ($fsmMetrics.stateCount -gt 0) { 
                    [math]::Round($fsmMetrics.transitionCount / $fsmMetrics.stateCount, 2) 
                } else { 0 }
                
                # McCabe-style cyclomatic complexity for FSM
                fsmCyclomaticComplexity = $fsmMetrics.transitionCount - $fsmMetrics.stateCount + 2
                
                # Blackboard complexity
                blackboardVariableCount = $bbMetrics.variableCount
                blackboardAccessDensity = if ($bbMetrics.variableCount -gt 0) {
                    [math]::Round(($bbMetrics.readCount + $bbMetrics.writeCount) / $bbMetrics.variableCount, 2)
                } else { 0 }
                
                # Overall complexity score (lower is simpler)
                overallComplexityScore = 0
            }
            
            # Calculate overall complexity score
            $complexityScore = 0
            $complexityScore += $metrics.complexity.behaviorTreeNodes * 2
            $complexityScore += $metrics.complexity.stateCount * 3
            $complexityScore += $metrics.complexity.transitionCount
            $complexityScore += $metrics.complexity.blackboardVariableCount * 1.5
            $metrics.complexity.overallComplexityScore = [math]::Round($complexityScore, 2)
        }
        
        # Calculate coupling metrics
        if ('all' -in $MetricTypes -or 'coupling' -in $MetricTypes) {
            $transitions = $BehaviorData.stateMachine.transitions
            $bbAccess = $BehaviorData.blackboard.accessPatterns
            
            # State coupling (how interconnected states are)
            $stateNames = $BehaviorData.stateMachine.states | ForEach-Object { $_.name }
            $externalTransitions = 0
            foreach ($transition in $transitions) {
                if ($transition.from -and $transition.to -and 
                    ($transition.from -notin $stateNames -or $transition.to -notin $stateNames)) {
                    $externalTransitions++
                }
            }
            
            $metrics.coupling = @{
                stateCoupling = if ($stateNames.Count -gt 0) { 
                    [math]::Round($transitions.Count / $stateNames.Count, 2) 
                } else { 0 }
                externalTransitions = $externalTransitions
                blackboardReadCoupling = ($bbAccess | Where-Object { $_.accessType -eq 'read' }).Count
                blackboardWriteCoupling = ($bbAccess | Where-Object { $_.accessType -eq 'write' }).Count
                couplingScore = 0
            }
            
            # Calculate coupling score (lower is better)
            $couplingScore = $metrics.coupling.stateCoupling * 10
            $couplingScore += $externalTransitions * 5
            $couplingScore += ($metrics.coupling.blackboardReadCoupling + $metrics.coupling.blackboardWriteCoupling) * 0.5
            $metrics.coupling.couplingScore = [math]::Round($couplingScore, 2)
        }
        
        # Calculate cohesion metrics
        if ('all' -in $MetricTypes -or 'cohesion' -in $MetricTypes) {
            $states = $BehaviorData.stateMachine.states
            $actions = $BehaviorData.actions.actions
            
            # Calculate state callback cohesion
            $stateCallbackCounts = @()
            foreach ($state in $states) {
                $callbackCount = 0
                if ($state.callbacks.enter) { $callbackCount++ }
                if ($state.callbacks.exit) { $callbackCount++ }
                if ($state.callbacks.update) { $callbackCount++ }
                if ($state.callbacks.physicsUpdate) { $callbackCount++ }
                if ($state.callbacks.handleInput) { $callbackCount++ }
                $stateCallbackCounts += $callbackCount
            }
            
            $avgCallbacks = if ($stateCallbackCounts.Count -gt 0) { 
                ($stateCallbackCounts | Measure-Object -Average).Average 
            } else { 0 }
            
            $metrics.cohesion = @{
                avgStateCallbacks = [math]::Round($avgCallbacks, 2)
                statesWithAllCallbacks = ($stateCallbackCounts | Where-Object { $_ -ge 4 }).Count
                actionPreconditionCoverage = 0
                actionEffectCoverage = 0
                cohesionScore = 0
            }
            
            # Calculate action cohesion (actions with both preconditions and effects)
            if ($actions.Count -gt 0) {
                $withPreconditions = ($actions | Where-Object { $_.preconditions.Count -gt 0 }).Count
                $withEffects = ($actions | Where-Object { $_.effects.Count -gt 0 }).Count
                $withBoth = ($actions | Where-Object { $_.preconditions.Count -gt 0 -and $_.effects.Count -gt 0 }).Count
                
                $metrics.cohesion.actionPreconditionCoverage = [math]::Round($withPreconditions / $actions.Count * 100, 2)
                $metrics.cohesion.actionEffectCoverage = [math]::Round($withEffects / $actions.Count * 100, 2)
                $metrics.cohesion.cohesionScore = [math]::Round($withBoth / $actions.Count * 100, 2)
            }
        }
        
        # Calculate coverage metrics
        if ('all' -in $MetricTypes -or 'coverage' -in $MetricTypes) {
            $btNodes = $BehaviorData.behaviorTree.nodes
            $states = $BehaviorData.stateMachine.states
            
            # Check for common AI lifecycle methods
            $lifecycleMethods = @('enter', 'exit', 'update', 'physicsUpdate', 'handleInput', 'tick')
            $implementedMethods = @()
            
            foreach ($state in $states) {
                if ($state.callbacks.enter) { $implementedMethods += 'enter' }
                if ($state.callbacks.exit) { $implementedMethods += 'exit' }
                if ($state.callbacks.update) { $implementedMethods += 'update' }
                if ($state.callbacks.physicsUpdate) { $implementedMethods += 'physicsUpdate' }
                if ($state.callbacks.handleInput) { $implementedMethods += 'handleInput' }
            }
            
            foreach ($node in $btNodes) {
                if ($node.methods.tick) { $implementedMethods += 'tick' }
                if ($node.methods.enter) { $implementedMethods += 'enter' }
                if ($node.methods.exit) { $implementedMethods += 'exit' }
            }
            
            $uniqueImplemented = $implementedMethods | Select-Object -Unique
            
            $metrics.coverage = @{
                lifecycleMethodCoverage = [math]::Round(($uniqueImplemented.Count / $lifecycleMethods.Count) * 100, 2)
                statesWithTransitions = ($states | Where-Object { $_.transitions.Count -gt 0 }).Count
                behaviorTreesWithTick = ($btNodes | Where-Object { $_.methods.tick }).Count
                errorHandlingDetected = $false  # Would need deeper analysis
            }
        }
        
        # Calculate overall quality indicators
        $metrics.overall = @{
            maintainabilityIndex = 0
            testabilityScore = 0
            recommendedRefactors = @()
        }
        
        # Simple maintainability index calculation
        $complexityWeight = if ($metrics.complexity.overallComplexityScore) { $metrics.complexity.overallComplexityScore } else { 0 }
        $couplingWeight = if ($metrics.coupling.couplingScore) { $metrics.coupling.couplingScore } else { 0 }
        $metrics.overall.maintainabilityIndex = [math]::Max(0, 100 - ($complexityWeight * 0.5) - ($couplingWeight * 2))
        
        # Testability based on state/action coverage
        $stateCount = $BehaviorData.stateMachine.statistics.stateCount
        $actionCount = $BehaviorData.actions.statistics.actionCount
        $metrics.overall.testabilityScore = [math]::Min(100, ($stateCount * 5) + ($actionCount * 3))
        
        # Generate refactoring recommendations
        if ($metrics.complexity.overallComplexityScore -gt 50) {
            $metrics.overall.recommendedRefactors += 'Consider splitting complex AI into sub-behaviors'
        }
        if ($metrics.coupling.couplingScore -gt 30) {
            $metrics.overall.recommendedRefactors += 'High coupling detected - reduce direct state transitions'
        }
        if ($stateCount -gt 10 -and $metrics.coupling.stateCoupling -gt 2) {
            $metrics.overall.recommendedRefactors += 'Consider hierarchical state machine for better organization'
        }
        
        Write-Verbose "[$script:ParserName] Calculated metrics for: $($metrics.sourceFile)"
        
        return $metrics
    }
    catch {
        Write-Error "[$script:ParserName] Failed to calculate AI behavior metrics: $_"
        return @{
            success = $false
            error = $_.ToString()
            timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
}

<#
.SYNOPSIS
    Converts AI behavior data to a graph representation for visualization.

.DESCRIPTION
    Transforms extracted AI behavior data (behavior trees, state machines, blackboards)
    into a graph structure suitable for visualization libraries like D3.js, Cytoscape.js,
    or Graphviz DOT format.

.PARAMETER BehaviorData
    Hashtable containing extracted AI behavior data.

.PARAMETER GraphType
    Type of graph to generate: 'statemachine', 'behaviortree', 'blackboard', 'combined'.

.PARAMETER OutputFormat
    Output format: 'json' (Cytoscape-compatible), 'dot' (Graphviz), or 'd3' (D3.js force graph).

.PARAMETER OutputPath
    Optional path to write the graph file.

.OUTPUTS
    System.Collections.Hashtable or String. Graph representation in the requested format.

.EXAMPLE
    $fsm = Export-GodotStateMachine -Path "res://ai/enemy_fsm.gd"
    $graph = Convert-ToBehaviorGraph -BehaviorData $fsm -GraphType 'statemachine' -OutputFormat 'json'
    
    Convert-ToBehaviorGraph -BehaviorData $fsm -GraphType 'statemachine' -OutputFormat 'dot' -OutputPath "./graphs/enemy_fsm.dot"
#>
function Convert-ToBehaviorGraph {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$BehaviorData,
        
        [Parameter()]
        [ValidateSet('statemachine', 'behaviortree', 'blackboard', 'combined')]
        [string]$GraphType = 'combined',
        
        [Parameter()]
        [ValidateSet('json', 'dot', 'd3')]
        [string]$OutputFormat = 'json',
        
        [Parameter()]
        [string]$OutputPath
    )
    
    try {
        Write-Verbose "[$script:ParserName] Converting to behavior graph: $GraphType ($OutputFormat)"
        
        $graph = @{
            type = $GraphType
            format = $OutputFormat
            generatedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        switch ($OutputFormat) {
            'json' {
                # Cytoscape.js compatible format
                $graph.elements = @{
                    nodes = @()
                    edges = @()
                }
            }
            'd3' {
                # D3.js force graph format
                $graph.nodes = @()
                $graph.links = @()
            }
            'dot' {
                # Graphviz DOT format
                $graph.dot = ''
            }
        }
        
        # Build state machine graph
        if ($GraphType -in @('statemachine', 'combined')) {
            $states = if ($BehaviorData.states) { $BehaviorData.states } else { @() }
            $transitions = if ($BehaviorData.transitions) { $BehaviorData.transitions } else { @() }
            
            # Also check nested structure from Invoke-AIBehaviorExtract
            if ($BehaviorData.stateMachine) {
                $states = $BehaviorData.stateMachine.states
                $transitions = $BehaviorData.stateMachine.transitions
            }
            
            foreach ($state in $states) {
                $nodeId = "state_$($state.name)"
                $nodeData = @{
                    id = $nodeId
                    name = $state.name
                    type = 'state'
                    extends = $state.extends
                    callbacks = $state.callbacks
                }
                
                switch ($OutputFormat) {
                    'json' {
                        $graph.elements.nodes += @{
                            data = $nodeData
                        }
                    }
                    'd3' {
                        $graph.nodes += @{
                            id = $nodeId
                            name = $state.name
                            group = 1
                            type = 'state'
                        }
                    }
                }
            }
            
            foreach ($transition in $transitions) {
                $edgeId = "transition_$([System.Guid]::NewGuid().ToString().Substring(0,8))"
                $sourceId = "state_$($transition.from)"
                $targetId = "state_$($transition.to)"
                
                switch ($OutputFormat) {
                    'json' {
                        $graph.elements.edges += @{
                            data = @{
                                id = $edgeId
                                source = $sourceId
                                target = $targetId
                                type = $transition.type
                                label = $transition.type
                            }
                        }
                    }
                    'd3' {
                        $graph.links += @{
                            source = $sourceId
                            target = $targetId
                            type = $transition.type
                            value = 1
                        }
                    }
                }
            }
        }
        
        # Build behavior tree graph
        if ($GraphType -in @('behaviortree', 'combined')) {
            $btNodes = if ($BehaviorData.nodes) { $BehaviorData.nodes } else { @() }
            
            # Also check nested structure
            if ($BehaviorData.behaviorTrees) {
                $btNodes = $BehaviorData.behaviorTrees.nodes
            }
            
            foreach ($node in $btNodes) {
                $nodeId = "bt_$($node.id)"
                
                switch ($OutputFormat) {
                    'json' {
                        $graph.elements.nodes += @{
                            data = @{
                                id = $nodeId
                                name = $node.className
                                type = "bt_$($node.type)"
                                extends = $node.extends
                                properties = $node.properties
                            }
                        }
                    }
                    'd3' {
                        $graph.nodes += @{
                            id = $nodeId
                            name = $node.className
                            group = 2
                            type = $node.type
                        }
                    }
                }
                
                # Add edges for children (hierarchy)
                foreach ($childId in $node.children) {
                    switch ($OutputFormat) {
                        'json' {
                            $graph.elements.edges += @{
                                data = @{
                                    id = "bt_edge_$([System.Guid]::NewGuid().ToString().Substring(0,8))"
                                    source = $nodeId
                                    target = "bt_$childId"
                                    type = 'child'
                                }
                            }
                        }
                        'd3' {
                            $graph.links += @{
                                source = $nodeId
                                target = "bt_$childId"
                                type = 'child'
                                value = 2
                            }
                        }
                    }
                }
            }
        }
        
        # Build blackboard graph
        if ($GraphType -in @('blackboard', 'combined')) {
            $bbVariables = if ($BehaviorData.variables) { $BehaviorData.variables } else { @() }
            $bbAccess = if ($BehaviorData.accessPatterns) { $BehaviorData.accessPatterns } else { @() }
            
            # Also check nested structure
            if ($BehaviorData.blackboard) {
                $bbVariables = $BehaviorData.blackboard.schema
                $bbAccess = $BehaviorData.blackboard.accessPatterns
            }
            
            # Add blackboard as a central node
            $bbNodeId = "blackboard_root"
            switch ($OutputFormat) {
                'json' {
                    $graph.elements.nodes += @{
                        data = @{
                            id = $bbNodeId
                            name = 'Blackboard'
                            type = 'blackboard'
                            variableCount = $bbVariables.Count
                        }
                    }
                }
                'd3' {
                    $graph.nodes += @{
                        id = $bbNodeId
                        name = 'Blackboard'
                        group = 3
                        type = 'blackboard'
                    }
                }
            }
            
            foreach ($var in $bbVariables) {
                $varNodeId = "bb_var_$($var.key)"
                
                switch ($OutputFormat) {
                    'json' {
                        $graph.elements.nodes += @{
                            data = @{
                                id = $varNodeId
                                name = $var.key
                                type = 'bb_variable'
                                varType = $var.type
                            }
                        }
                        $graph.elements.edges += @{
                            data = @{
                                id = "bb_edge_$([System.Guid]::NewGuid().ToString().Substring(0,8))"
                                source = $bbNodeId
                                target = $varNodeId
                                type = 'contains'
                            }
                        }
                    }
                    'd3' {
                        $graph.nodes += @{
                            id = $varNodeId
                            name = $var.key
                            group = 4
                            type = 'bb_variable'
                        }
                        $graph.links += @{
                            source = $bbNodeId
                            target = $varNodeId
                            type = 'contains'
                            value = 1
                        }
                    }
                }
            }
        }
        
        # Generate DOT format
        if ($OutputFormat -eq 'dot') {
            $dotLines = @('digraph AIBehavior {')
            $dotLines += '    rankdir=TB;'
            $dotLines += '    node [shape=box, style=rounded];'
            
            # Add nodes
            foreach ($node in $graph.nodes) {
                $shape = switch ($node.type) {
                    'state' { 'ellipse' }
                    'blackboard' { 'diamond' }
                    'bb_variable' { 'box' }
                    default { 'box' }
                }
                $color = switch ($node.group) {
                    1 { 'lightblue' }  # states
                    2 { 'lightgreen' } # BT nodes
                    3 { 'lightyellow' } # blackboard
                    4 { 'lightpink' }  # BB variables
                    default { 'white' }
                }
                $dotLines += '    "{0}" [label="{1}", shape={2}, fillcolor={3}, style=filled];' -f 
                    $node.id, $node.name, $shape, $color
            }
            
            # Add edges
            foreach ($link in $graph.links) {
                $style = if ($link.type -eq 'child') { ' [style=bold]' } else { '' }
                $dotLines += '    "{0}" -> "{1}"{2};' -f $link.source, $link.target, $style
            }
            
            $dotLines += '}'
            $graph.dot = $dotLines -join "`n"
            
            # Clean up temporary arrays for DOT output
            $graph.Remove('nodes')
            $graph.Remove('links')
        }
        
        # Write to file if output path specified
        if ($OutputPath) {
            $outputContent = switch ($OutputFormat) {
                'dot' { $graph.dot }
                default { $graph | ConvertTo-Json -Depth 10 }
            }
            $outputContent | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Verbose "[$script:ParserName] Graph exported to: $OutputPath"
        }
        
        return $graph
    }
    catch {
        Write-Error "[$script:ParserName] Failed to convert to behavior graph: $_"
        return @{
            success = $false
            error = $_.ToString()
            timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
}

# ============================================================================
# Export Module Members
# ============================================================================

if ($null -ne $MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        # New Export Functions (User Requested)
        'Export-GodotBehaviorTree'
        'Export-GodotStateMachine'
        'Export-GodotBlackboard'
        'Get-GodotAIBehaviorMetrics'
        'Convert-ToBehaviorGraph'
        # Canonical functions (Section 25.6)
        'Extract-BehaviorTreeNodes'
        'Extract-StateMachineStates'
        'Extract-AIActionDefinitions'
        'Extract-BlackboardSchema'
        # Legacy compatibility functions
        'Get-BehaviorTrees'
        'Get-StateMachines'
        'Get-GOAPPatterns'
        'Get-NavigationPatterns'
        'Invoke-AIBehaviorExtract'
    )
}
