#Requires -Version 5.1
<#
.SYNOPSIS
    Godot AI Behavior extractor for LLM Workflow.

.DESCRIPTION
    Extracts structured AI behavior patterns from Godot GDScript files.
    Parses behavior trees, state machines, GOAP implementations, and navigation patterns.
    Supports various Godot AI frameworks including LimboAI patterns.

.NOTES
    File Name      : GodotAIBehaviorExtractor.ps1
    Author         : LLM Workflow
    Version        : 1.0.0
    Godot Versions : 3.x, 4.x
#>

Set-StrictMode -Version Latest

# ============================================================================
# Regex Patterns for AI Behavior Parsing
# ============================================================================

$script:AIPatterns = @{
    # Behavior Tree patterns
    BTNodeBase = 'extends\s+(?:BT\w+|Limbo\w+|BehaviorTree\w+)'
    BTTask = 'extends\s+BT\w*Task'
    BTComposite = 'extends\s+BT\w*Composite'
    BTDecorator = 'extends\s+BT\w*Decorator'
    BTCondition = 'extends\s+BT\w*Condition'
    
    # State Machine patterns
    StateMachineBase = 'extends\s+(?:StateMachine|FiniteStateMachine|StateChart)'
    StateNode = 'extends\s+(?:State|State\w+|LimboState)'
    StateTransition = '\.transition\s*\(\s*["''](?<target>\w+)["'']\s*\)'
    StateChange = 'change_state\s*\(\s*["''](?<target>\w+)["'']\s*\)'
    
    # GOAP patterns
    GOAPAction = 'extends\s+(?:GOAPAction|GoapAction)'
    GOAPGoal = 'extends\s+(?:GOAPGoal|GoapGoal)'
    GOAPAgent = 'extends\s+(?:GOAPAgent|GoapAgent)'
    Precondition = '(?:precondition|precondition_|preconditions)\s*\(|@export\s+var\s+preconditions'
    Effect = '(?:effect|effect_|effects)\s*\(|@export\s+var\s+effects'
    
    # Navigation patterns
    NavigationAgent = '@onready\s+var\s+\w+\s*:?\s*=\s*\$\w*NavigationAgent'
    NavigationRegion = 'NavigationRegion\w*'
    NavMesh = 'NavigationMesh|nav_mesh'
    PathFinding = 'get_next_path_position|get_final_position|is_navigation_finished'
    PathQuery = 'navigation_agent\.target_position'
    Avoidance = 'enable_avoidance|avoidance_enabled|set_avoidance_enabled'
    
    # Behavior tree tick/execute
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
    
    # Utility AI patterns
    UtilityConsideration = 'extends\s+Consideration'
    UtilityAction = 'extends\s+UtilityAction|UtilityAIAction'
    UtilityScore = 'func\s+(?:score|get_score|calculate_score)'
    
    # Blackboard patterns
    BlackboardSet = '\.blackboard\.set\s*\(\s*["''](?<key>\w+)["'']\s*,\s*(?<val>[^)]+)\s*\)'
    BlackboardGet = '\.blackboard\.get\s*\(\s*["''](?<key>\w+)["'']\s*\)'
    BlackboardHas = '\.blackboard\.has\s*\(\s*["''](?<key>\w+)["'']\s*\)'
    
    # Sensor patterns
    SensorBase = 'extends\s+Sensor'
    Sense = 'func\s+sense'
    Stimulus = '@export\s+var\s+\w+_stimulus'
}

# ============================================================================
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
    Extracts behavior tree patterns from GDScript files.

.DESCRIPTION
    Parses GDScript files to identify behavior tree nodes and their
    structure including composites, decorators, tasks, and conditions.

.PARAMETER Path
    Path to the GDScript file.

.PARAMETER Content
    GDScript content string (alternative to Path).

.OUTPUTS
    System.Array. Array of behavior tree node objects.

.EXAMPLE
    $btNodes = Get-BehaviorTrees -Path "res://ai/enemy_ai.gd"
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
    
    try {
        # Load content
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Warning "File not found: $Path"
                return @()
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @()
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
            elseif ($line -match $script:AIPatterns.BTNodeBase) {
                $nodeType = 'node'
            }
            
            if ($nodeType) {
                # Extract class name if available
                $className = ''
                if ($trimmed -match 'class_name\s+(\w+)') {
                    $className = $matches[1]
                }
                
                $currentNode = @{
                    type = $nodeType
                    className = $className
                    lineNumber = $lineNumber
                    extends = $line -replace '.*extends\s+', ''
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
                    }
                }
                
                # Detect next function definition as end of current analysis
                if ($line -match '^func\s+\w+\s*\(' -and $lineNumber -gt $currentNode.lineNumber + 20) {
                    # Only add if we found BT-specific methods
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
        
        Write-Verbose "[Get-BehaviorTrees] Extracted $($btNodes.Count) behavior tree nodes"
        return ,$btNodes
    }
    catch {
        Write-Error "[Get-BehaviorTrees] Failed to extract behavior trees: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts state machine patterns from GDScript files.

.DESCRIPTION
    Parses GDScript files to identify state machine implementations,
    states, transitions, and state callbacks.

.PARAMETER Path
    Path to the GDScript file.

.PARAMETER Content
    GDScript content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. State machine structure with states and transitions.

.EXAMPLE
    $sm = Get-StateMachines -Path "res://ai/enemy_states.gd"
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
        
        $stateMachine = @{
            states = @()
            transitions = @()
            isStateMachine = $false
            hasStateChart = $false
        }
        
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        $currentState = $null
        
        foreach ($line in $lines) {
            $lineNumber++
            $trimmed = $line.Trim()
            
            # Check if this is a state machine file
            if ($line -match $script:AIPatterns.StateMachineBase) {
                $stateMachine.isStateMachine = $true
                if ($line -match 'StateChart') {
                    $stateMachine.hasStateChart = $true
                }
            }
            
            # Detect state definitions
            if ($line -match $script:AIPatterns.StateNode) {
                $className = ''
                if ($trimmed -match 'class_name\s+(\w+)') {
                    $className = $matches[1]
                }
                
                $currentState = @{
                    name = $className
                    lineNumber = $lineNumber
                    extends = $line -replace '.*extends\s+', ''
                    callbacks = @{
                        enter = $false
                        exit = $false
                        update = $false
                        physicsUpdate = $false
                        handleInput = $false
                    }
                    transitions = @()
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
                
                # Check for transitions from this state
                if ($line -match $script:AIPatterns.StateTransition) {
                    $currentState.transitions += @{
                        to = $matches['target']
                        lineNumber = $lineNumber
                    }
                    $stateMachine.transitions += @{
                        from = $currentState.name
                        to = $matches['target']
                        lineNumber = $lineNumber
                    }
                }
                if ($line -match $script:AIPatterns.StateChange) {
                    $currentState.transitions += @{
                        to = $matches['target']
                        lineNumber = $lineNumber
                    }
                    $stateMachine.transitions += @{
                        from = $currentState.name
                        to = $matches['target']
                        lineNumber = $lineNumber
                    }
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
        
        Write-Verbose "[Get-StateMachines] Extracted $($stateMachine.states.Count) states, $($stateMachine.transitions.Count) transitions"
        return $stateMachine
    }
    catch {
        Write-Error "[Get-StateMachines] Failed to extract state machines: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Extracts GOAP (Goal-Oriented Action Planning) patterns from GDScript files.

.DESCRIPTION
    Parses GDScript files to identify GOAP implementations including
    actions, goals, agents, preconditions, and effects.

.PARAMETER Path
    Path to the GDScript file.

.PARAMETER Content
    GDScript content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. GOAP structure with actions and goals.

.EXAMPLE
    $goap = Get-GOAPPatterns -Path "res://ai/goap_agent.gd"
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
        
        $goap = @{
            actions = @()
            goals = @()
            agents = @()
            isGOAP = $false
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
                $goap.isGOAP = $true
                $className = ''
                if ($trimmed -match 'class_name\s+(\w+)') {
                    $className = $matches[1]
                }
                $currentElement = @{
                    name = $className
                    type = 'action'
                    lineNumber = $lineNumber
                    preconditions = @()
                    effects = @()
                    methods = @{
                        getCost = $false
                        isValid = $false
                        perform = $false
                    }
                }
            }
            elseif ($line -match $script:AIPatterns.GOAPGoal) {
                $elementType = 'goal'
                $goap.isGOAP = $true
                $className = ''
                if ($trimmed -match 'class_name\s+(\w+)') {
                    $className = $matches[1]
                }
                $currentElement = @{
                    name = $className
                    type = 'goal'
                    lineNumber = $lineNumber
                    priority = $null
                    conditions = @()
                }
            }
            elseif ($line -match $script:AIPatterns.GOAPAgent) {
                $elementType = 'agent'
                $goap.isGOAP = $true
                $className = ''
                if ($trimmed -match 'class_name\s+(\w+)') {
                    $className = $matches[1]
                }
                $currentElement = @{
                    name = $className
                    type = 'agent'
                    lineNumber = $lineNumber
                    availableActions = @()
                    goals = @()
                }
            }
            
            if ($currentElement) {
                # Check for GOAP methods
                if ($line -match $script:AIPatterns.GOAPGetCost) {
                    $currentElement.methods.getCost = $true
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
                
                # End of class
                if ($line -match '^class\s' -or $lineNumber -eq $lines.Count) {
                    switch ($elementType) {
                        'action' { $goap.actions += $currentElement }
                        'goal' { $goap.goals += $currentElement }
                        'agent' { $goap.agents += $currentElement }
                    }
                    $currentElement = $null
                    $elementType = $null
                }
            }
        }
        
        # Add last element
        if ($currentElement) {
            switch ($elementType) {
                'action' { $goap.actions += $currentElement }
                'goal' { $goap.goals += $currentElement }
                'agent' { $goap.agents += $currentElement }
            }
        }
        
        Write-Verbose "[Get-GOAPPatterns] Extracted $($goap.actions.Count) actions, $($goap.goals.Count) goals"
        return $goap
    }
    catch {
        Write-Error "[Get-GOAPPatterns] Failed to extract GOAP patterns: $_"
        return $null
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
        Write-Error "[Get-NavigationPatterns] Failed to extract navigation patterns: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Main entry point for parsing AI behavior from GDScript files.

.DESCRIPTION
    Parses a GDScript file and returns complete structured extraction
    of AI behavior patterns including behavior trees, state machines,
    GOAP, and navigation.

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
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Warning "File not found: $Path"
                return $null
            }
            $filePath = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        else {
            $filePath = 'inline'
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return $null
        }
        
        # Extract all AI patterns
        $btNodes = Get-BehaviorTrees -Content $Content
        $stateMachine = Get-StateMachines -Content $Content
        $goap = Get-GOAPPatterns -Content $Content
        $navigation = Get-NavigationPatterns -Content $Content
        
        # Determine primary AI pattern
        $primaryPattern = 'none'
        if ($btNodes.Count -gt 0) {
            $primaryPattern = 'behavior_tree'
        }
        elseif ($stateMachine.isStateMachine) {
            $primaryPattern = 'state_machine'
        }
        elseif ($goap.isGOAP) {
            $primaryPattern = 'goap'
        }
        elseif ($navigation.hasNavigationAgent) {
            $primaryPattern = 'navigation'
        }
        
        $result = @{
            filePath = $filePath
            fileType = 'gdscript'
            primaryAIPattern = $primaryPattern
            behaviorTrees = $btNodes
            stateMachine = $stateMachine
            goap = $goap
            navigation = $navigation
            statistics = @{
                behaviorTreeNodes = $btNodes.Count
                stateCount = $stateMachine.states.Count
                transitionCount = $stateMachine.transitions.Count
                goapActions = $goap.actions.Count
                goapGoals = $goap.goals.Count
                hasPathfinding = $navigation.usesPathfinding
                hasAvoidance = $navigation.usesAvoidance
            }
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        Write-Verbose "[Invoke-AIBehaviorExtract] Extraction complete: primary pattern is $primaryPattern"
        
        return $result
    }
    catch {
        Write-Error "[Invoke-AIBehaviorExtract] Failed to extract AI behaviors: $_"
        return $null
    }
}

# ============================================================================
# Export Module Members
# ============================================================================

if ($null -ne $MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Get-BehaviorTrees'
        'Get-StateMachines'
        'Get-GOAPPatterns'
        'Get-NavigationPatterns'
        'Invoke-AIBehaviorExtract'
    )
}
