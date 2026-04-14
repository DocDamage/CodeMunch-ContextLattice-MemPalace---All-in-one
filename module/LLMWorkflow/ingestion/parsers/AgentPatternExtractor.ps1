#requires -Version 5.1
<#
.SYNOPSIS
    Agent pattern extractor for LLM Workflow Structured Extraction Pipeline.

.DESCRIPTION
    Parses agent simulation source files and extracts structured metadata including:
    - Agent state models (properties, behavior states, transitions)
    - Multi-agent orchestration logic (communication patterns, coordination)
    - Memory and retrieval patterns (vector stores, RAG implementations)
    - Tool use patterns (function calling, tool definitions)
    - Reasoning patterns (Chain-of-Thought, ReAct, plan-and-execute)
    
    This extractor implements agent simulation pack extraction for sources
    like a16z-infra/ai-town, LangChain, and related ecosystem projects.

.NOTES
    File Name      : AgentPatternExtractor.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Pack Support   : agent-simulation
#>

Set-StrictMode -Version Latest

# ============================================================================
# Script-level Constants and Patterns
# ============================================================================

# Agent pattern detection patterns
$script:AgentPatterns = @{
    # State model patterns
    StateClass = '(?:class|interface)\s+(?<name>\w+)(?:State|Agent|Memory|Behavior)'
    StateProperty = "(?:state|status|mode|phase)\s*[:=]\s*[`"''']?(?<value>\w+)[`"''']?"
    StateTransition = '(?:transition|setState|updateState|changeState)\s*\([^)]*\)'
    
    # Multi-agent patterns
    AgentCommunication = '(?:sendMessage|broadcast|notify|emit)\s*\([^)]*\)'
    AgentCoordination = '(?:coordinator|orchestrator|manager|supervisor)'
    AgentRegistry = '(?:agents|participants|actors)\s*[:=]\s*(?:\[|new\s+(?:Map|Array|List))'
    
    # Memory patterns
    MemoryStore = '(?:memory|recall|remember|store)\s*[:=]'
    VectorSearch = '(?:similaritySearch|vectorSearch|query|embedAndSearch)'
    RetrievalPattern = '(?:retrieve|fetch|query|getContext|getRelevant)'
    
    # Tool use patterns
    ToolDefinition = '(?:tools|functions|capabilities)\s*[:=]\s*(?:\[|{)'
    ToolCall = '(?:callTool|invokeTool|executeFunction|toolCall)'
    FunctionSchema = '(?:parameters|schema|input_schema|args_schema)'
    
    # Reasoning patterns
    ChainOfThought = '(?:thought|reasoning|thinking|chainOfThought)'
    ReActPattern = '(?:Action|Observation|Thought):\s*'
    PlanExecute = '(?:plan|steps|strategy|workflow)\s*[:=]'
}

# Language-specific patterns
$script:LanguagePatterns = @{
    Python = @{
        ClassDef = '^class\s+(?<name>\w+)(?:\((?<parent>[^)]+)\))?\s*:'
        MethodDef = '^\s*def\s+(?<name>\w+)\s*\((?<params>[^)]*)\)(?:\s*->\s*(?<ret>[^:]+))?:'
        PropertyDef = '^\s*(?<name>\w+)\s*:\s*(?<type>[^=#]+)(?:\s*=\s*(?<default>.+))?'
        Decorator = '^\s*@(?<name>\w+)(?:\((?<args>[^)]*)\))?'
        TypedDict = '^class\s+(?<name>\w+)\s*\(\s*(?:TypedDict|dict)\s*\)'
        PydanticModel = '^class\s+(?<name>\w+)\s*\(\s*(?:BaseModel|pydantic\.BaseModel)\s*\)'
    }
    TypeScript = @{
        InterfaceDef = '^\s*interface\s+(?<name>\w+)(?:\s+extends\s+(?<parent>\w+))?\s*{'
        TypeAlias = '^\s*type\s+(?<name>\w+)\s*=\s*{'
        ClassDef = '^\s*class\s+(?<name>\w+)(?:\s+extends\s+(?<parent>\w+))?(?:\s+implements\s+(?<iface>\w+))?\s*{'
        MethodDef = '^\s*(?:async\s+)?(?<name>\w+)\s*\((?<params>[^)]*)\)(?:\s*:\s*(?<ret>[^{]+))?\s*{'
        PropertyDef = '^\s*(?<name>\w+)\s*:\s*(?<type>[^;=]+)(?:\s*=\s*(?<default>.+))?;'
    }
}

# ============================================================================
# Private Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Detects the programming language from file extension or content.
.DESCRIPTION
    Analyzes the file extension and content to determine if it's Python,
    TypeScript, or JavaScript.
.PARAMETER Path
    The file path to analyze.
.PARAMETER Content
    The file content to analyze (optional).
.OUTPUTS
    System.String. Language identifier (python, typescript, javascript).
#>
function Get-AgentSourceLanguage {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter()]
        [string]$Content = ''
    )
    
    $extension = [System.IO.Path]::GetExtension($Path).ToLower()
    
    switch ($extension) {
        '.py' { return 'python' }
        '.ts' { return 'typescript' }
        '.tsx' { return 'typescript' }
        '.js' { return 'javascript' }
        '.jsx' { return 'javascript' }
        default {
            # Try to detect from content
            if ($Content -match '^\s*(import|from)\s+\w+') {
                return 'python'
            }
            if ($Content -match '^\s*(import|export|const|let|var)\s+\w+') {
                return 'typescript'
            }
            return 'unknown'
        }
    }
}

<#
.SYNOPSIS
    Creates a structured agent element object following the output schema.
.DESCRIPTION
    Factory function to create standardized agent pattern element objects.
.PARAMETER ElementType
    The type of element (stateModel, orchestration, memory, toolUse, reasoning).
.PARAMETER Name
    The name of the element.
.PARAMETER PatternSubtype
    The specific pattern subtype.
.PARAMETER LineNumber
    The line number where the element is defined.
.PARAMETER Properties
    Hashtable of element properties.
.PARAMETER CodeSnippet
    Associated code snippet.
.PARAMETER SourceFile
    Path to the source file.
.OUTPUTS
    System.Collections.Hashtable. Structured element object.
#>
function New-AgentElement {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('stateModel', 'orchestration', 'memory', 'toolUse', 'reasoning', 'agent', 'communication')]
        [string]$ElementType,
        
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter()]
        [string]$PatternSubtype = '',
        
        [Parameter()]
        [int]$LineNumber = 0,
        
        [Parameter()]
        [hashtable]$Properties = @{},
        
        [Parameter()]
        [string]$CodeSnippet = '',
        
        [Parameter()]
        [string]$SourceFile = ''
    )
    
    return @{
        elementType = $ElementType
        name = $Name
        patternSubtype = $PatternSubtype
        lineNumber = $LineNumber
        properties = $Properties
        codeSnippet = $CodeSnippet
        sourceFile = $SourceFile
        extractedAt = [DateTime]::UtcNow.ToString("o")
    }
}

<#
.SYNOPSIS
    Extracts Python class definitions from content.
.DESCRIPTION
    Parses Python source code and extracts class definitions including
    inheritance and decorators.
.PARAMETER Content
    The Python source content.
.OUTPUTS
    System.Array. Array of class definition objects.
#>
function Get-PythonClassDefinitions {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    $classes = @()
    $lines = $Content -split "`r?`n"
    $lineNumber = 0
    $pendingDecorators = @()
    
    foreach ($line in $lines) {
        $lineNumber++
        
        # Check for decorator
        if ($line -match $script:LanguagePatterns.Python.Decorator) {
            $pendingDecorators += @{
                name = $matches['name']
                args = $matches['args']
                lineNumber = $lineNumber
            }
            continue
        }
        
        # Check for class definition
        if ($line -match $script:LanguagePatterns.Python.ClassDef) {
            $className = $matches['name']
            $parentClass = if ($matches['parent']) { $matches['parent'] } else { '' }
            
            $classInfo = @{
                name = $className
                parent = $parentClass
                lineNumber = $lineNumber
                decorators = $pendingDecorators
                isTypedDict = $line -match 'TypedDict'
                isPydantic = $line -match 'BaseModel'
                isAgentState = $className -match '(?:State|Agent|Memory|Behavior)'
            }
            
            $classes += $classInfo
            $pendingDecorators = @()
        }
        elseif (-not ($line -match '^\s*$' -or $line -match '^\s*#')) {
            # Reset decorators if we hit non-class, non-blank, non-comment line
            $pendingDecorators = @()
        }
    }
    
    return ,$classes
}

<#
.SYNOPSIS
    Extracts method definitions from content.
.DESCRIPTION
    Parses source code and extracts method/function definitions.
.PARAMETER Content
    The source content.
.PARAMETER Language
    The programming language.
.OUTPUTS
    System.Array. Array of method definition objects.
#>
function Get-MethodDefinitions {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter(Mandatory = $true)]
        [string]$Language
    )
    
    $methods = @()
    $lines = $Content -split "`r?`n"
    $lineNumber = 0
    
    $pattern = if ($Language -eq 'python') {
        $script:LanguagePatterns.Python.MethodDef
    } else {
        $script:LanguagePatterns.TypeScript.MethodDef
    }
    
    foreach ($line in $lines) {
        $lineNumber++
        
        if ($line -match $pattern) {
            $method = @{
                name = $matches['name']
                parameters = $matches['params']
                returnType = if ($matches['ret']) { $matches['ret'].Trim() } else { '' }
                lineNumber = $lineNumber
                isAsync = $line -match '\basync\b'
            }
            $methods += $method
        }
    }
    
    return ,$methods
}

# ============================================================================
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
    Main entry point for agent pattern extraction.

.DESCRIPTION
    Parses an agent simulation source file and returns structured extraction
    with all agent patterns (state models, orchestration, memory, tools, reasoning).

.PARAMETER Path
    Path to the source file to parse.

.PARAMETER Content
    Source content string (alternative to Path).

.PARAMETER IncludeRawContent
    If specified, includes the raw file content in the output.

.OUTPUTS
    System.Collections.Hashtable. Complete extraction with elements array and metadata.

.EXAMPLE
    $result = Invoke-AgentPatternExtract -Path "./agent.py"

.EXAMPLE
    $content = Get-Content -Raw "agent.ts"
    $result = Invoke-AgentPatternExtract -Content $content
#>
function Invoke-AgentPatternExtract {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [Alias('FilePath')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [switch]$IncludeRawContent
    )
    
    try {
        # Load content from file if path provided
        $filePath = ''
        $rawContent = ''
        
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Write-Verbose "[Invoke-AgentPatternExtract] Loading file: $Path"
            
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Warning "File not found: $Path"
                return $null
            }
            
            $filePath = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $rawContent = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
        }
        else {
            $filePath = ''
            $rawContent = $Content
        }
        
        if ([string]::IsNullOrWhiteSpace($rawContent)) {
            Write-Warning "Content is empty"
            return $null
        }
        
        Write-Verbose "[Invoke-AgentPatternExtract] Parsing agent patterns ($($rawContent.Length) chars)"
        
        # Detect language
        $language = Get-AgentSourceLanguage -Path $filePath -Content $rawContent
        
        # Build elements collection
        $elements = @()
        
        # Extract agent state models
        $stateModels = Get-AgentStateModel -Content $rawContent -Language $language
        foreach ($model in $stateModels) {
            $elements += New-AgentElement `
                -ElementType 'stateModel' `
                -Name $model.name `
                -PatternSubtype $model.subtype `
                -LineNumber $model.lineNumber `
                -Properties $model.properties `
                -CodeSnippet $model.codeSnippet `
                -SourceFile $filePath
        }
        
        # Extract multi-agent patterns
        $multiAgentPatterns = Get-MultiAgentPatterns -Content $rawContent -Language $language
        foreach ($pattern in $multiAgentPatterns) {
            $elements += New-AgentElement `
                -ElementType 'orchestration' `
                -Name $pattern.name `
                -PatternSubtype $pattern.subtype `
                -LineNumber $pattern.lineNumber `
                -Properties $pattern.properties `
                -CodeSnippet $pattern.codeSnippet `
                -SourceFile $filePath
        }
        
        # Extract memory patterns
        $memoryPatterns = Get-AgentMemoryPatterns -Content $rawContent -Language $language
        foreach ($pattern in $memoryPatterns) {
            $elements += New-AgentElement `
                -ElementType 'memory' `
                -Name $pattern.name `
                -PatternSubtype $pattern.subtype `
                -LineNumber $pattern.lineNumber `
                -Properties $pattern.properties `
                -CodeSnippet $pattern.codeSnippet `
                -SourceFile $filePath
        }
        
        # Extract tool use patterns
        $toolPatterns = Get-ToolUsePatterns -Content $rawContent -Language $language
        foreach ($pattern in $toolPatterns) {
            $elements += New-AgentElement `
                -ElementType 'toolUse' `
                -Name $pattern.name `
                -PatternSubtype $pattern.subtype `
                -LineNumber $pattern.lineNumber `
                -Properties $pattern.properties `
                -CodeSnippet $pattern.codeSnippet `
                -SourceFile $filePath
        }
        
        # Extract reasoning patterns
        $reasoningPatterns = Get-ReasoningPatterns -Content $rawContent -Language $language
        foreach ($pattern in $reasoningPatterns) {
            $elements += New-AgentElement `
                -ElementType 'reasoning' `
                -Name $pattern.name `
                -PatternSubtype $pattern.subtype `
                -LineNumber $pattern.lineNumber `
                -Properties $pattern.properties `
                -CodeSnippet $pattern.codeSnippet `
                -SourceFile $filePath
        }
        
        # Build final result
        $result = @{
            fileType = 'agent-simulation'
            filePath = $filePath
            language = $language
            elements = $elements
            elementCounts = @{
                stateModel = ($elements | Where-Object { $_.elementType -eq 'stateModel' }).Count
                orchestration = ($elements | Where-Object { $_.elementType -eq 'orchestration' }).Count
                memory = ($elements | Where-Object { $_.elementType -eq 'memory' }).Count
                toolUse = ($elements | Where-Object { $_.elementType -eq 'toolUse' }).Count
                reasoning = ($elements | Where-Object { $_.elementType -eq 'reasoning' }).Count
            }
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        if ($IncludeRawContent) {
            $result.rawContent = $rawContent
        }
        
        Write-Verbose "[Invoke-AgentPatternExtract] Extraction complete: $($elements.Count) elements extracted"
        
        return $result
    }
    catch {
        Write-Error "[Invoke-AgentPatternExtract] Failed to extract agent patterns: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Extracts agent state model definitions from source content.

.DESCRIPTION
    Parses source code to identify agent state models, state properties,
    and state transition patterns. Detects TypedDict, Pydantic models,
    and interface definitions that represent agent states.

.PARAMETER Content
    The source content to parse.

.PARAMETER Language
    The programming language (python, typescript, javascript).

.OUTPUTS
    System.Array. Array of state model objects with name, subtype, properties, etc.

.EXAMPLE
    $stateModels = Get-AgentStateModel -Content $pythonContent -Language 'python'
#>
function Get-AgentStateModel {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$Language = 'python'
    )
    
    process {
        $stateModels = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        $currentClass = $null
        $classStartLine = 0
        $classIndentLevel = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            $indent = ($line -match '^(\s*)')[0].Length
            
            # Detect class definition
            if ($Language -eq 'python' -and $line -match $script:LanguagePatterns.Python.ClassDef) {
                $className = $matches['name']
                $parentClass = if ($matches['parent']) { $matches['parent'] } else { '' }
                
                # Check if it's an agent-related class
                $isAgentClass = $className -match '(?:Agent|State|Memory|Behavior|Actor)' -or
                               $parentClass -match '(?:Agent|BaseModel|TypedDict)'
                
                if ($isAgentClass) {
                    $currentClass = @{
                        name = $className
                        parent = $parentClass
                        lineNumber = $lineNumber
                        indentLevel = $indent
                        properties = @{}
                        subtype = if ($line -match 'TypedDict') { 'typedDict' } 
                                  elseif ($line -match 'BaseModel') { 'pydantic' }
                                  else { 'class' }
                        codeSnippet = $line
                    }
                    $classStartLine = $lineNumber
                    $classIndentLevel = $indent
                }
            }
            # TypeScript interface/class
            elseif (($Language -eq 'typescript' -or $Language -eq 'javascript') -and 
                    ($line -match $script:LanguagePatterns.TypeScript.InterfaceDef -or
                     $line -match $script:LanguagePatterns.TypeScript.ClassDef)) {
                $className = $matches['name']
                
                if ($className -match '(?:Agent|State|Memory|Behavior|Actor)') {
                    $currentClass = @{
                        name = $className
                        parent = if ($matches['parent']) { $matches['parent'] } else { '' }
                        lineNumber = $lineNumber
                        indentLevel = $indent
                        properties = @{}
                        subtype = if ($line -match 'interface') { 'interface' } else { 'class' }
                        codeSnippet = $line
                    }
                    $classStartLine = $lineNumber
                    $classIndentLevel = $indent
                }
            }
            # Extract properties from within class
            elseif ($currentClass -and $indent -gt $classIndentLevel) {
                if ($Language -eq 'python' -and $line -match $script:LanguagePatterns.Python.PropertyDef) {
                    $propName = $matches['name']
                    $propType = $matches['type'].Trim()
                    $currentClass.properties[$propName] = @{
                        type = $propType
                        lineNumber = $lineNumber
                    }
                }
                elseif (($Language -eq 'typescript' -or $Language -eq 'javascript') -and
                        $line -match $script:LanguagePatterns.TypeScript.PropertyDef) {
                    $propName = $matches['name']
                    $propType = $matches['type'].Trim()
                    $currentClass.properties[$propName] = @{
                        type = $propType
                        lineNumber = $lineNumber
                    }
                }
            }
            # End of class (dedent)
            elseif ($currentClass -and $indent -le $classIndentLevel -and $line -match '\S') {
                # Save the class as a state model
                $stateModels += $currentClass
                $currentClass = $null
            }
        }
        
        # Don't forget the last class
        if ($currentClass) {
            $stateModels += $currentClass
        }
        
        Write-Verbose "[Get-AgentStateModel] Found $($stateModels.Count) state models"
        return ,$stateModels
    }
}

<#
.SYNOPSIS
    Extracts multi-agent orchestration patterns from source content.

.DESCRIPTION
    Parses source code to identify multi-agent communication patterns,
    coordination mechanisms, agent registries, and orchestration logic.

.PARAMETER Content
    The source content to parse.

.PARAMETER Language
    The programming language (python, typescript, javascript).

.OUTPUTS
    System.Array. Array of orchestration pattern objects.

.EXAMPLE
    $patterns = Get-MultiAgentPatterns -Content $pythonContent -Language 'python'
#>
function Get-MultiAgentPatterns {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$Language = 'python'
    )
    
    process {
        $patterns = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Agent communication patterns
            if ($line -match $script:AgentPatterns.AgentCommunication) {
                $patterns += @{
                    name = 'AgentCommunication'
                    subtype = 'messagePassing'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'communication'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Agent coordinator patterns
            if ($line -match $script:AgentPatterns.AgentCoordination) {
                $patterns += @{
                    name = 'AgentCoordination'
                    subtype = 'coordinator'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'coordination'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Agent registry patterns
            if ($line -match $script:AgentPatterns.AgentRegistry) {
                $patterns += @{
                    name = 'AgentRegistry'
                    subtype = 'registry'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'registry'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # State transition patterns
            if ($line -match $script:AgentPatterns.StateTransition) {
                $patterns += @{
                    name = 'StateTransition'
                    subtype = 'transition'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'stateTransition'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
        }
        
        Write-Verbose "[Get-MultiAgentPatterns] Found $($patterns.Count) multi-agent patterns"
        return ,$patterns
    }
}

<#
.SYNOPSIS
    Extracts agent memory and retrieval patterns from source content.

.DESCRIPTION
    Parses source code to identify memory storage patterns, vector search
    implementations, and retrieval-augmented generation patterns.

.PARAMETER Content
    The source content to parse.

.PARAMETER Language
    The programming language (python, typescript, javascript).

.OUTPUTS
    System.Array. Array of memory pattern objects.

.EXAMPLE
    $patterns = Get-AgentMemoryPatterns -Content $pythonContent -Language 'python'
#>
function Get-AgentMemoryPatterns {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$Language = 'python'
    )
    
    process {
        $patterns = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Memory store patterns
            if ($line -match $script:AgentPatterns.MemoryStore) {
                $patterns += @{
                    name = 'MemoryStore'
                    subtype = 'storage'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'memoryStorage'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Vector search patterns
            if ($line -match $script:AgentPatterns.VectorSearch) {
                $patterns += @{
                    name = 'VectorSearch'
                    subtype = 'vectorRetrieval'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'vectorSearch'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Retrieval patterns
            if ($line -match $script:AgentPatterns.RetrievalPattern) {
                $patterns += @{
                    name = 'Retrieval'
                    subtype = 'retrieval'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'contextRetrieval'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
        }
        
        Write-Verbose "[Get-AgentMemoryPatterns] Found $($patterns.Count) memory patterns"
        return ,$patterns
    }
}

<#
.SYNOPSIS
    Extracts tool use and function calling patterns from source content.

.DESCRIPTION
    Parses source code to identify tool definitions, tool call implementations,
    and function schema definitions for agent tool use.

.PARAMETER Content
    The source content to parse.

.PARAMETER Language
    The programming language (python, typescript, javascript).

.OUTPUTS
    System.Array. Array of tool use pattern objects.

.EXAMPLE
    $patterns = Get-ToolUsePatterns -Content $pythonContent -Language 'python'
#>
function Get-ToolUsePatterns {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$Language = 'python'
    )
    
    process {
        $patterns = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Tool definition patterns
            if ($line -match $script:AgentPatterns.ToolDefinition) {
                $patterns += @{
                    name = 'ToolDefinition'
                    subtype = 'toolRegistry'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'toolDefinition'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Tool call patterns
            if ($line -match $script:AgentPatterns.ToolCall) {
                $patterns += @{
                    name = 'ToolCall'
                    subtype = 'invocation'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'toolInvocation'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Function schema patterns
            if ($line -match $script:AgentPatterns.FunctionSchema) {
                $patterns += @{
                    name = 'FunctionSchema'
                    subtype = 'schema'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'parameterSchema'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
        }
        
        Write-Verbose "[Get-ToolUsePatterns] Found $($patterns.Count) tool use patterns"
        return ,$patterns
    }
}

<#
.SYNOPSIS
    Extracts reasoning patterns from source content.

.DESCRIPTION
    Parses source code to identify reasoning implementations including
    Chain-of-Thought, ReAct, Plan-and-Execute, and other reasoning patterns.

.PARAMETER Content
    The source content to parse.

.PARAMETER Language
    The programming language (python, typescript, javascript).

.OUTPUTS
    System.Array. Array of reasoning pattern objects.

.EXAMPLE
    $patterns = Get-ReasoningPatterns -Content $pythonContent -Language 'python'
#>
function Get-ReasoningPatterns {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$Language = 'python'
    )
    
    process {
        $patterns = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Chain of thought patterns
            if ($line -match $script:AgentPatterns.ChainOfThought) {
                $patterns += @{
                    name = 'ChainOfThought'
                    subtype = 'reasoning'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'chainOfThought'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # ReAct patterns
            if ($line -match $script:AgentPatterns.ReActPattern) {
                $patterns += @{
                    name = 'ReAct'
                    subtype = 'reasoning'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'react'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Plan and execute patterns
            if ($line -match $script:AgentPatterns.PlanExecute) {
                $patterns += @{
                    name = 'PlanAndExecute'
                    subtype = 'planning'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'planExecute'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
        }
        
        Write-Verbose "[Get-ReasoningPatterns] Found $($patterns.Count) reasoning patterns"
        return ,$patterns
    }
}
# Public functions exported via module wildcard
