#requires -Version 5.1
<#
.SYNOPSIS
    Script runtime extractor for LLM Workflow Structured Extraction Pipeline.

.DESCRIPTION
    Parses game engine scripting source files (C#, Lua, Python, etc.) and extracts structured metadata including:
    - Scripting language bindings (Lua, Python, C# bindings to engine)
    - Script component patterns (script classes, components, behaviors)
    - Script lifecycle hooks (init, update, destroy callbacks)
    - Game loop integration (main loop patterns, update scheduling)
    
    This extractor implements script runtime extraction for sources
    with scripting integrations like TorqueScript, Stingray Lua, 
    Atomic Game Engine JS/C#, and similar patterns.

.NOTES
    File Name      : ScriptRuntimeExtractor.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Pack Support   : engine-reference
#>

Set-StrictMode -Version Latest

# ============================================================================
# Script-level Constants and Patterns
# ============================================================================

# Script runtime pattern detection
$script:ScriptRuntimePatterns = @{
    # Language binding patterns
    LuaBinding = '(?:lua_|luaL_|luaopen_|lua_getglobal|lua_setglobal|lua_pcall)'
    PythonBinding = '(?:Py_|PyObject|PyArg_Parse|Py_BuildValue|pybind11)'
    CSharpBinding = '(?:Mono|mono_|IL2CPP|Assembly|Type|MethodInfo|Invoke)'
    ScriptBridge = '(?:ScriptBridge|ScriptBinding|ScriptInterop|NativeToScript)'
    
    # Script component patterns
    ScriptComponent = '(?:class|struct)\s+(?<name>\w+)(?:Script|Behaviour|Behavior|Component)'
    ScriptClass = '(?:ScriptClass|ScriptObject|ScriptInstance)'
    ScriptProperty = '(?:ScriptProperty|@property|@serialize)'
    ScriptMethod = '(?:ScriptMethod|@expose|SCRIPT_METHOD)'
    
    # Lifecycle hook patterns
    InitHook = '(?:onCreate|onInit|Initialize|Awake|Start|BeginPlay)\s*\('
    UpdateHook = '(?:onUpdate|Update|Tick|onTick|Process|Step)\s*\('
    DestroyHook = '(?:onDestroy|onCleanup|Destroy|EndPlay|Shutdown|Dispose)\s*\('
    EnableHook = '(?:onEnable|OnEnable|Activate|onActivate)\s*\('
    DisableHook = '(?:onDisable|OnDisable|Deactivate|onDeactivate)\s*\('
    
    # Game loop integration patterns
    MainLoop = '(?:mainLoop|RunLoop|GameLoop|while\s*\(\s*running|while\s*\(\s*true)'
    UpdateLoop = '(?:updateLoop|processEvents|processInput|update|fixedUpdate)'
    RenderLoop = '(?:renderLoop|renderFrame|draw|present|swapBuffers)'
    TimeStep = '(?:deltaTime|timeStep|elapsed|frameTime|Time::)'
    Scheduler = '(?:Scheduler|TaskManager|Coroutine|yield|await)'
}

# Language-specific patterns
$script:LanguagePatterns = @{
    CSharp = @{
        ClassDef = '^\s*(?:public|private|protected|internal)?\s*(?:sealed|abstract|static)?\s*class\s+(?<name>\w+)(?:\s*:\s*(?<parent>\w+))?'
        MethodDef = '^\s*(?:public|private|protected|internal)?\s*(?:virtual|override|abstract|static)?\s*(?:async)?\s*(?<ret>\w+)?\s+(?<name>\w+)\s*\((?<params>[^)]*)\)'
        Attribute = '^\s*\[(?<name>\w+)(?:\((?<args>[^)]*)\))?\]'
        PropertyDef = '^\s*(?:public|private|protected)?\s*(?<type>\w+)\s+(?<name>\w+)\s*\{\s*(?:get|set)'
        Namespace = '^\s*namespace\s+(?<name>[\w.]+)'
    }
    Lua = @{
        FunctionDef = '^\s*(?:local\s+)?function\s+(?<name>[\w.:]+)\s*\((?<params>[^)]*)\)'
        TableDef = '^\s*(?:local\s+)?(?<name>\w+)\s*=\s*\{'
        MethodCall = '(?<obj>\w+)[:.](?<method>\w+)\s*\('
        Require = "^\s*local\s+\w+\s*=\s*require\s*\(?[`"\'](?<module>[^`"\']+)[`"\']\)?"
    }
    Python = @{
        ClassDef = '^\s*class\s+(?<name>\w+)(?:\((?<parent>[^)]+)\))?\s*:'
        MethodDef = '^\s*def\s+(?<name>\w+)\s*\((?<params>[^)]*)\)(?:\s*->\s*(?<ret>[^:]+))?:'
        Decorator = '^\s*@(?<name>\w+)(?:\((?<args>[^)]*)\))?'
        PropertyDef = '^\s*(?<name>\w+)\s*:\s*(?<type>[^=#]+)'
    }
}

# ============================================================================
# Private Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Detects the scripting language from file extension or content.
.DESCRIPTION
    Analyzes the file extension and content to determine the scripting language.
.PARAMETER Path
    The file path to analyze.
.PARAMETER Content
    The file content to analyze (optional).
.OUTPUTS
    System.String. Language identifier (csharp, lua, python, unknown).
#>
function Get-ScriptLanguage {
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
        '.cs' { return 'csharp' }
        '.lua' { return 'lua' }
        '.py' { return 'python' }
        '.js' { return 'javascript' }
        '.ts' { return 'typescript' }
        default {
            # Try to detect from content
            if ($Content -match '^(using\s+System|namespace\s+|public\s+class)') {
                return 'csharp'
            }
            if ($Content -match '^(local\s+function|function|require\s*\()') {
                return 'lua'
            }
            if ($Content -match '^(import\s+|from\s+\w+\s+import|def\s+)') {
                return 'python'
            }
            return 'unknown'
        }
    }
}

<#
.SYNOPSIS
    Creates a structured script element object following the output schema.
.DESCRIPTION
    Factory function to create standardized script runtime element objects.
.PARAMETER ElementType
    The type of element (binding, component, lifecycle, gameLoop).
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
function New-ScriptElement {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('binding', 'component', 'lifecycle', 'gameLoop')]
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

# ============================================================================
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
    Main entry point for script runtime extraction.

.DESCRIPTION
    Parses a script source file and returns structured extraction
    with all script patterns (bindings, components, lifecycle, game loop).

.PARAMETER Path
    Path to the source file to parse.

.PARAMETER Content
    Source content string (alternative to Path).

.PARAMETER IncludeRawContent
    If specified, includes the raw file content in the output.

.OUTPUTS
    System.Collections.Hashtable. Complete extraction with elements array and metadata.

.EXAMPLE
    $result = Invoke-ScriptRuntimeExtract -Path "./Scripts/Player.cs"

.EXAMPLE
    $content = Get-Content -Raw "gameplay.lua"
    $result = Invoke-ScriptRuntimeExtract -Content $content
#>
function Invoke-ScriptRuntimeExtract {
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
            Write-Verbose "[Invoke-ScriptRuntimeExtract] Loading file: $Path"
            
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
        
        Write-Verbose "[Invoke-ScriptRuntimeExtract] Parsing script patterns ($($rawContent.Length) chars)"
        
        # Detect language
        $language = Get-ScriptLanguage -Path $filePath -Content $rawContent
        
        # Build elements collection
        $elements = @()
        
        # Extract script language bindings
        $bindings = Get-ScriptLanguageBindings -Content $rawContent -Language $language
        foreach ($binding in $bindings) {
            $elements += New-ScriptElement `
                -ElementType 'binding' `
                -Name $binding.name `
                -PatternSubtype $binding.subtype `
                -LineNumber $binding.lineNumber `
                -Properties $binding.properties `
                -CodeSnippet $binding.codeSnippet `
                -SourceFile $filePath
        }
        
        # Extract script component patterns
        $components = Get-ScriptComponentPatterns -Content $rawContent -Language $language
        foreach ($component in $components) {
            $elements += New-ScriptElement `
                -ElementType 'component' `
                -Name $component.name `
                -PatternSubtype $component.subtype `
                -LineNumber $component.lineNumber `
                -Properties $component.properties `
                -CodeSnippet $component.codeSnippet `
                -SourceFile $filePath
        }
        
        # Extract script lifecycle hooks
        $lifecycles = Get-ScriptLifecycleHooks -Content $rawContent -Language $language
        foreach ($lifecycle in $lifecycles) {
            $elements += New-ScriptElement `
                -ElementType 'lifecycle' `
                -Name $lifecycle.name `
                -PatternSubtype $lifecycle.subtype `
                -LineNumber $lifecycle.lineNumber `
                -Properties $lifecycle.properties `
                -CodeSnippet $lifecycle.codeSnippet `
                -SourceFile $filePath
        }
        
        # Extract game loop integration
        $gameLoops = Get-GameLoopIntegration -Content $rawContent -Language $language
        foreach ($gameLoop in $gameLoops) {
            $elements += New-ScriptElement `
                -ElementType 'gameLoop' `
                -Name $gameLoop.name `
                -PatternSubtype $gameLoop.subtype `
                -LineNumber $gameLoop.lineNumber `
                -Properties $gameLoop.properties `
                -CodeSnippet $gameLoop.codeSnippet `
                -SourceFile $filePath
        }
        
        # Build final result
        $result = @{
            fileType = 'scriptRuntime'
            filePath = $filePath
            language = $language
            elements = $elements
            elementCounts = @{
                binding = ($elements | Where-Object { $_.elementType -eq 'binding' }).Count
                component = ($elements | Where-Object { $_.elementType -eq 'component' }).Count
                lifecycle = ($elements | Where-Object { $_.elementType -eq 'lifecycle' }).Count
                gameLoop = ($elements | Where-Object { $_.elementType -eq 'gameLoop' }).Count
            }
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        if ($IncludeRawContent) {
            $result.rawContent = $rawContent
        }
        
        Write-Verbose "[Invoke-ScriptRuntimeExtract] Extraction complete: $($elements.Count) elements extracted"
        
        return $result
    }
    catch {
        Write-Error "[Invoke-ScriptRuntimeExtract] Failed to extract script patterns: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Extracts script language binding patterns from source content.

.DESCRIPTION
    Parses source code to identify language binding implementations including
    Lua C API usage, Python C API, C# interop, and script bridge patterns.

.PARAMETER Content
    The source content to parse.

.PARAMETER Language
    The programming language (csharp, lua, python, javascript).

.OUTPUTS
    System.Array. Array of binding pattern objects.

.EXAMPLE
    $bindings = Get-ScriptLanguageBindings -Content $csharpContent -Language 'csharp'
#>
function Get-ScriptLanguageBindings {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$Language = 'csharp'
    )
    
    process {
        $bindings = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Lua binding patterns
            if ($line -match $script:ScriptRuntimePatterns.LuaBinding) {
                $bindings += @{
                    name = 'LuaBinding'
                    subtype = 'lua'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'luaCApi'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Python binding patterns
            if ($line -match $script:ScriptRuntimePatterns.PythonBinding) {
                $bindings += @{
                    name = 'PythonBinding'
                    subtype = 'python'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'pythonCApi'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # C# binding patterns
            if ($line -match $script:ScriptRuntimePatterns.CSharpBinding) {
                $bindings += @{
                    name = 'CSharpBinding'
                    subtype = 'csharp'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'monoInterop'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Script bridge patterns
            if ($line -match $script:ScriptRuntimePatterns.ScriptBridge) {
                $bindings += @{
                    name = 'ScriptBridge'
                    subtype = 'bridge'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'scriptInterop'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
        }
        
        Write-Verbose "[Get-ScriptLanguageBindings] Found $($bindings.Count) binding patterns"
        return ,$bindings
    }
}

<#
.SYNOPSIS
    Extracts script component patterns from source content.

.DESCRIPTION
    Parses source code to identify script component implementations including
    script classes, script objects, script properties, and exposed methods.

.PARAMETER Content
    The source content to parse.

.PARAMETER Language
    The programming language (csharp, lua, python, javascript).

.OUTPUTS
    System.Array. Array of script component pattern objects.

.EXAMPLE
    $components = Get-ScriptComponentPatterns -Content $csharpContent -Language 'csharp'
#>
function Get-ScriptComponentPatterns {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$Language = 'csharp'
    )
    
    process {
        $components = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Script component class patterns
            if ($line -match $script:ScriptRuntimePatterns.ScriptComponent) {
                $components += @{
                    name = $matches['name']
                    subtype = 'scriptComponent'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'componentDefinition'
                        isScript = $true
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Script class patterns
            if ($line -match $script:ScriptRuntimePatterns.ScriptClass) {
                $components += @{
                    name = 'ScriptClass'
                    subtype = 'scriptObject'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'scriptClass'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Script property patterns
            if ($line -match $script:ScriptRuntimePatterns.ScriptProperty) {
                $components += @{
                    name = 'ScriptProperty'
                    subtype = 'property'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'exposedProperty'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Script method patterns
            if ($line -match $script:ScriptRuntimePatterns.ScriptMethod) {
                $components += @{
                    name = 'ScriptMethod'
                    subtype = 'method'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'exposedMethod'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
        }
        
        Write-Verbose "[Get-ScriptComponentPatterns] Found $($components.Count) component patterns"
        return ,$components
    }
}

<#
.SYNOPSIS
    Extracts script lifecycle hook patterns from source content.

.DESCRIPTION
    Parses source code to identify script lifecycle hooks including
    initialization, update, destroy, enable, and disable callbacks.

.PARAMETER Content
    The source content to parse.

.PARAMETER Language
    The programming language (csharp, lua, python, javascript).

.OUTPUTS
    System.Array. Array of lifecycle hook pattern objects.

.EXAMPLE
    $lifecycles = Get-ScriptLifecycleHooks -Content $csharpContent -Language 'csharp'
#>
function Get-ScriptLifecycleHooks {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$Language = 'csharp'
    )
    
    process {
        $lifecycles = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Initialize/Create hooks
            if ($line -match $script:ScriptRuntimePatterns.InitHook) {
                $lifecycles += @{
                    name = 'Initialize'
                    subtype = 'init'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'initialization'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Update/Tick hooks
            if ($line -match $script:ScriptRuntimePatterns.UpdateHook) {
                $lifecycles += @{
                    name = 'Update'
                    subtype = 'update'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'updateTick'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Destroy/Cleanup hooks
            if ($line -match $script:ScriptRuntimePatterns.DestroyHook) {
                $lifecycles += @{
                    name = 'Destroy'
                    subtype = 'destroy'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'cleanup'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Enable hooks
            if ($line -match $script:ScriptRuntimePatterns.EnableHook) {
                $lifecycles += @{
                    name = 'Enable'
                    subtype = 'enable'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'activation'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Disable hooks
            if ($line -match $script:ScriptRuntimePatterns.DisableHook) {
                $lifecycles += @{
                    name = 'Disable'
                    subtype = 'disable'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'deactivation'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
        }
        
        Write-Verbose "[Get-ScriptLifecycleHooks] Found $($lifecycles.Count) lifecycle patterns"
        return ,$lifecycles
    }
}

<#
.SYNOPSIS
    Extracts game loop integration patterns from source content.

.DESCRIPTION
    Parses source code to identify game loop integration patterns including
    main loop implementations, update scheduling, render loops, and time management.

.PARAMETER Content
    The source content to parse.

.PARAMETER Language
    The programming language (csharp, lua, python, javascript).

.OUTPUTS
    System.Array. Array of game loop pattern objects.

.EXAMPLE
    $gameLoops = Get-GameLoopIntegration -Content $csharpContent -Language 'csharp'
#>
function Get-GameLoopIntegration {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$Language = 'csharp'
    )
    
    process {
        $gameLoops = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Main loop patterns
            if ($line -match $script:ScriptRuntimePatterns.MainLoop) {
                $gameLoops += @{
                    name = 'MainLoop'
                    subtype = 'mainLoop'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'gameLoopEntry'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Update loop patterns
            if ($line -match $script:ScriptRuntimePatterns.UpdateLoop) {
                $gameLoops += @{
                    name = 'UpdateLoop'
                    subtype = 'updateLoop'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'updateProcessing'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Render loop patterns
            if ($line -match $script:ScriptRuntimePatterns.RenderLoop) {
                $gameLoops += @{
                    name = 'RenderLoop'
                    subtype = 'renderLoop'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'rendering'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Time step patterns
            if ($line -match $script:ScriptRuntimePatterns.TimeStep) {
                $gameLoops += @{
                    name = 'TimeStep'
                    subtype = 'timing'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'deltaTime'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
            
            # Scheduler patterns
            if ($line -match $script:ScriptRuntimePatterns.Scheduler) {
                $gameLoops += @{
                    name = 'Scheduler'
                    subtype = 'scheduling'
                    lineNumber = $lineNumber
                    properties = @{
                        pattern = 'taskScheduling'
                        match = $matches[0]
                    }
                    codeSnippet = $line.Trim()
                }
            }
        }
        
        Write-Verbose "[Get-GameLoopIntegration] Found $($gameLoops.Count) game loop patterns"
        return ,$gameLoops
    }
}
# Public functions exported via module wildcard
