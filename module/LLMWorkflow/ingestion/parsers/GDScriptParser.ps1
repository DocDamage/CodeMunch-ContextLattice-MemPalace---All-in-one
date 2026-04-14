#requires -Version 5.1
<#
.SYNOPSIS
    GDScript parser for LLM Workflow Structured Extraction Pipeline.

.DESCRIPTION
    Parses GDScript source files (.gd) and extracts structured metadata including:
    - Class inheritance (extends, class_name)
    - Annotations (@tool, @icon, @export, @onready, @export_group, @export_category)
    - Signal definitions with typed parameters
    - Exported properties with types and defaults
    - Function signatures with parameters and return types
    - Variable declarations with type information
    - Comment blocks for documentation
    - Autoload registrations from project.godot
    - Input actions from InputMap references
    - Scene inheritance references
    - GDExtension manifest fields
    - plugin.cfg addon metadata
    
    This parser implements Section 25.15.1 of the canonical architecture
    for the Godot Engine pack's structured extraction pipeline.

.NOTES
    File Name      : GDScriptParser.ps1
    Author         : LLM Workflow Team
    Version        : 2.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Engine Support : Godot 3.x, Godot 4.x
#>

Set-StrictMode -Version Latest

# ============================================================================
# Script-level Constants and Patterns
# ============================================================================

# GDScript built-in types (Godot 4.x)
$script:GDScriptBuiltInTypes = @(
    'void', 'bool', 'int', 'float', 'String', 'Vector2', 'Vector2i', 'Vector3', 
    'Vector3i', 'Vector4', 'Vector4i', 'Color', 'Rect2', 'Rect2i', 'Transform2D',
    'Transform3D', 'Plane', 'Quaternion', 'AABB', 'Basis', 'Projection',
    'NodePath', 'RID', 'Object', 'Callable', 'Signal', 'Dictionary', 'Array',
    'PackedByteArray', 'PackedInt32Array', 'PackedInt64Array', 'PackedFloat32Array',
    'PackedFloat64Array', 'PackedStringArray', 'PackedVector2Array', 'PackedVector3Array',
    'PackedColorArray', 'Variant'
)

# Regex patterns for GDScript parsing
$script:Patterns = @{
    # Class metadata
    Extends = '^\s*extends\s+(?<class>[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)'
    ClassName = '^\s*class_name\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)'
    
    # Annotations
    Tool = '^\s*@tool\b'
    Icon = '^\s*@icon\s*\(\s*["''](?<path>[^"'']+)["'']\s*\)'
    ExportVariant = '^\s*@export_\w+\s*\((?<hint>[^)]+)\)\s*var\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*(?<type>[^=]+))?\s*(?:=\s*(?<default>.+))?'
    Export = '^\s*@export\s*(?:\((?<hint>[^)]+)\))?\s*var\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*(?<type>[^=]+))?\s*(?:=\s*(?<default>.+))?'
    ExportGroup = '^\s*@export_group\s*\(\s*["''](?<name>[^"'']+)["'']\s*(?:,\s*["''](?<prefix>[^"'']+)["''])?\s*\)'
    ExportCategory = '^\s*@export_category\s*\(\s*["''](?<name>[^"'']+)["'']\s*\)'
    OnReady = '^\s*@onready\s+var\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*(?<type>[^=]+))?\s*(?:=\s*(?<value>.+))?'
    
    # Signals
    Signal = '^\s*signal\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?:\((?<params>[^)]*)\))?'
    
    # Variables (Godot 4)
    TypedVar = '^\s*var\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?<type>[^=]+)(?:\s*=\s*(?<default>.+))?'
    InferredVar = '^\s*var\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?<value>.+)'
    Const = '^\s*const\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*(?<type>[^=]+))?\s*=\s*(?<value>.+)'
    Enum = '^\s*enum\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?:\{(?<values>[^}]*)\})?'
    
    # Variables (Godot 3 legacy)
    Godot3Export = '^\s*export\s*(?:\((?<hint>[^)]*)\))?\s*var\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?:=\s*(?<default>.+))?'
    Godot3OnReady = '^\s*onready\s+var\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?:=\s*(?<value>.+))?'
    
    # Functions - captures params more carefully, supports generic return types
    Function = '^\s*func\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*\((?<params>.*?)\)(?:\s*->\s*(?<ret>[^:]+))?\s*:'
    StaticFunc = '^\s*static\s+func\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*\((?<params>.*?)\)(?:\s*->\s*(?<ret>[^:]+))?\s*:'
    
    # Comments
    DocComment = '^\s*##\s*(?<text>.*)$'
    Comment = '^\s*#.*$'
    
    # Node paths and signal connections (simplified patterns)
    NodePath = '\$[A-Za-z_][A-Za-z0-9_]*|\$["''][^"'']+["'']|\$/[A-Za-z_][A-Za-z0-9_/]*'
    SignalConnect = '\.connect\s*\([^)]+\)'
    
    # Engine detection
    Godot4Indicator = '@(onready|export|tool|icon|export_group|export_category)\b|->\s*\w+\s*:$|:\s*\w+\s*='
    Godot3Indicator = '\bonready\b\s+var|\bexport\b\s*\(|func\s+\w+\s*\([^)]*\)\s*:'
}

# ============================================================================
# Private Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Normalizes a type string by trimming whitespace.
.DESCRIPTION
    Internal helper to clean up type annotations extracted from GDScript code.
.PARAMETER TypeString
    The type string to normalize.
.OUTPUTS
    System.String. Normalized type string.
#>
function ConvertTo-NormalizedType {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeString
    )
    
    return $TypeString.Trim() -replace '\s+', ' '
}

<#
.SYNOPSIS
    Parses a parameter list string into structured objects.
.DESCRIPTION
    Converts a GDScript parameter string like "new_health: int, max_health: int"
    into an array of parameter objects with name, type, and default value.
.PARAMETER ParamString
    The parameter string from a function or signal definition.
.OUTPUTS
    System.Array. Array of parameter objects.
#>
function ConvertFrom-GDScriptParams {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ParamString
    )
    
    $params = @()
    
    if ([string]::IsNullOrWhiteSpace($ParamString)) {
        return $params
    }
    
    # Handle nested generics by counting brackets
    $depth = 0
    $currentParam = ''
    $chars = $ParamString.ToCharArray()
    
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $char = $chars[$i]
        
        if ($char -eq '<' -or $char -eq '[' -or $char -eq '(') {
            $depth++
            $currentParam += $char
        }
        elseif ($char -eq '>' -or $char -eq ']' -or $char -eq ')') {
            $depth--
            $currentParam += $char
        }
        elseif ($char -eq ',' -and $depth -eq 0) {
            # Parameter separator at top level
            $param = ConvertTo-ParamObject -ParamText $currentParam.Trim()
            if ($param) {
                $params += $param
            }
            $currentParam = ''
        }
        else {
            $currentParam += $char
        }
    }
    
    # Process final parameter
    if ($currentParam.Trim()) {
        $param = ConvertTo-ParamObject -ParamText $currentParam.Trim()
        if ($param) {
            $params += $param
        }
    }
    
    return $params
}

<#
.SYNOPSIS
    Converts a single parameter text into a structured object.
.DESCRIPTION
    Internal helper to parse a single parameter like "health: int = 100"
    into its constituent parts.
.PARAMETER ParamText
    The parameter text to parse.
.OUTPUTS
    System.Collections.Hashtable. Parameter object or $null.
#>
function ConvertTo-ParamObject {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ParamText
    )
    
    if ([string]::IsNullOrWhiteSpace($ParamText)) {
        return $null
    }
    
    # Pattern: name: Type = default
    # Pattern: name: Type
    # Pattern: name = default
    # Pattern: name
    
    $result = @{
        name = ''
        type = 'Variant'
        default = $null
    }
    
    # Check for default value
    $defaultMatch = $ParamText -match '^(?<before>.+?)\s*=\s*(?<default>.+)$'
    if ($defaultMatch) {
        $result.default = $matches['default'].Trim()
        $ParamText = $matches['before'].Trim()
    }
    
    # Check for type annotation
    $typeMatch = $ParamText -match '^(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?<type>.+)$'
    if ($typeMatch) {
        $result.name = $matches['name'].Trim()
        $result.type = ConvertTo-NormalizedType -TypeString $matches['type'].Trim()
    }
    else {
        # No type, just name
        $result.name = $ParamText.Trim()
    }
    
    return $result
}

<#
.SYNOPSIS
    Detects the Godot engine version from GDScript content.
.DESCRIPTION
    Analyzes the script content to determine if it's Godot 3 or Godot 4.
    Uses patterns like @onready (Godot 4) vs onready (Godot 3).
.PARAMETER Content
    The GDScript content to analyze.
.OUTPUTS
    System.String. "4.x", "3.x", or "Unknown".
#>
function Get-GDScriptEngineVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    $godot4Score = 0
    $godot3Score = 0
    
    # Check for Godot 4 patterns
    if ($Content -match $script:Patterns.Godot4Indicator) {
        $godot4Score += 5
    }
    
    # Check for typed return syntax (Godot 4 style)
    if ($Content -match '->\s*\w+\s*:') {
        $godot4Score += 3
    }
    
    # Check for @ annotations (Godot 4)
    $atAnnotations = [regex]::Matches($Content, '@(export|onready|tool|icon|export_group|export_category)\b').Count
    $godot4Score += $atAnnotations * 2
    
    # Check for Godot 3 patterns
    $oldOnReady = [regex]::Matches($Content, '\bonready\s+var\b').Count
    $godot3Score += $oldOnReady * 3
    
    # Check for old export syntax
    $oldExport = [regex]::Matches($Content, '\bexport\s*\([^)]*\)\s*var\b').Count
    $godot3Score += $oldExport * 3
    
    # Check for functions without return type (neutral, but common in Godot 3)
    $noRetType = [regex]::Matches($Content, '^\s*func\s+\w+\s*\([^)]*\)\s*:[^->]').Count
    $godot3Score += $noRetType
    
    if ($godot4Score -gt $godot3Score) {
        return "4.x"
    }
    elseif ($godot3Score -gt $godot4Score) {
        return "3.x"
    }
    else {
        return "Unknown"
    }
}

<#
.SYNOPSIS
    Extracts documentation comments from GDScript content.
.DESCRIPTION
    Finds documentation comments (##) and associates them with
the next non-comment code element.
.PARAMETER Content
    The GDScript content to analyze.
.OUTPUTS
    System.Array. Array of documentation block objects.
#>
function Get-GDScriptDocumentation {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    $docs = @()
    
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return ,$docs
    }
    
    $lines = $Content -split "`r?`n"
    $currentDoc = @()
    $lineNumber = 0
    
    foreach ($line in $lines) {
        $lineNumber++
        $docMatch = $line -match $script:Patterns.DocComment
        
        if ($docMatch) {
            $currentDoc += $matches['text']
        }
        elseif ($currentDoc.Count -gt 0 -and $line -notmatch $script:Patterns.Comment) {
            # End of doc block, store with line number
            $docs += @{
                lineNumber = $lineNumber
                text = $currentDoc -join "`n"
            }
            $currentDoc = @()
        }
    }
    
    return ,$docs
}

<#
.SYNOPSIS
    Finds the documentation comment associated with a specific line.
.DESCRIPTION
    Searches through extracted documentation blocks to find the one
    that immediately precedes the given line number.
.PARAMETER LineNumber
    The line number to find documentation for.
.PARAMETER DocumentationBlocks
    Array of documentation block objects from Get-GDScriptDocumentation.
.OUTPUTS
    System.String. The documentation text or $null.
#>
function Get-DocCommentForLine {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$LineNumber,
        
        [Parameter()]
        [array]$DocumentationBlocks = @()
    )
    
    if ($null -eq $DocumentationBlocks -or $DocumentationBlocks.Count -eq 0) {
        return $null
    }
    
    $closestDoc = $null
    $closestDistance = [int]::MaxValue
    
    foreach ($doc in $DocumentationBlocks) {
        $distance = $LineNumber - $doc.lineNumber
        if ($distance -gt 0 -and $distance -lt $closestDistance) {
            $closestDistance = $distance
            $closestDoc = $doc.text
        }
    }
    
    return $closestDoc
}

<#
.SYNOPSIS
    Creates a structured element object following the output schema.
.DESCRIPTION
    Factory function to create standardized element objects.
.PARAMETER ElementType
    The type of element (class, signal, property, method, annotation).
.PARAMETER Name
    The name of the element.
.PARAMETER LineNumber
    The line number where the element is defined.
.PARAMETER Extends
    The parent class (for class elements).
.PARAMETER ClassName
    The class name (for elements within a class).
.PARAMETER Parameters
    Array of parameter objects.
.PARAMETER ReturnType
    The return type (for methods).
.PARAMETER Annotations
    Array of annotation strings.
.PARAMETER DocComment
    Associated documentation comment.
.PARAMETER SourceFile
    Path to the source file.
.OUTPUTS
    System.Collections.Hashtable. Structured element object.
#>
function New-GDScriptElement {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('class', 'signal', 'property', 'method', 'annotation', 'enum')]
        [string]$ElementType,
        
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter()]
        [int]$LineNumber = 0,
        
        [Parameter()]
        [string]$Extends = $null,
        
        [Parameter()]
        [string]$ClassName = $null,
        
        [Parameter()]
        [array]$Parameters = @(),
        
        [Parameter()]
        [string]$ReturnType = $null,
        
        [Parameter()]
        [array]$Annotations = @(),
        
        [Parameter()]
        [string]$DocComment = $null,
        
        [Parameter()]
        [string]$SourceFile = ''
    )
    
    return @{
        elementType = $ElementType
        name = $Name
        lineNumber = $LineNumber
        extends = $Extends
        className = $ClassName
        parameters = $Parameters
        returnType = $ReturnType
        annotations = $Annotations
        docComment = $DocComment
        sourceFile = $SourceFile
    }
}

# ============================================================================
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
    Main entry point for parsing GDScript files.

.DESCRIPTION
    Parses a GDScript file and returns a complete structured extraction
    with all elements (class, signals, properties, methods, annotations)
    following the Phase 4 Structured Extraction Pipeline schema.

.PARAMETER Path
    Path to the GDScript file to parse.

.PARAMETER Content
    GDScript content string (alternative to Path).

.PARAMETER IncludeRawContent
    If specified, includes the raw file content in the output.

.OUTPUTS
    System.Collections.Hashtable. Complete extraction with elements array and metadata.

.EXAMPLE
    $result = Invoke-GDScriptParse -Path "res://player.gd"

.EXAMPLE
    $content = Get-Content -Raw "player.gd"
    $result = Invoke-GDScriptParse -Content $content
#>
function Invoke-GDScriptParse {
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
            Write-Verbose "[Invoke-GDScriptParse] Loading file: $Path"
            
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
        
        Write-Verbose "[Invoke-GDScriptParse] Parsing GDScript content ($($rawContent.Length) chars)"
        
        # Extract documentation blocks first
        $docBlocks = Get-GDScriptDocumentation -Content $rawContent
        
        # Get class info for context
        $classInfo = Get-GDScriptClassInfo -Content $rawContent
        $className = $classInfo.className
        $extends = $classInfo.extends
        
        # Build elements collection
        $elements = @()
        
        # Add class element if we have class info
        if (-not [string]::IsNullOrEmpty($className) -or -not [string]::IsNullOrEmpty($extends)) {
            $classAnnotations = @()
            if ($classInfo.isTool) { $classAnnotations += '@tool' }
            if (-not [string]::IsNullOrEmpty($classInfo.icon)) { $classAnnotations += "@icon(`"$($classInfo.icon)`")" }
            
            $classDisplayName = if ($className) { $className } else { 'Anonymous' }
            
            $elements += New-GDScriptElement `
                -ElementType 'class' `
                -Name $classDisplayName `
                -LineNumber 0 `
                -Extends $extends `
                -ClassName $className `
                -Annotations $classAnnotations `
                -SourceFile $filePath
        }
        
        # Extract signals
        $signals = Get-GDScriptSignals -Content $rawContent
        foreach ($signal in $signals) {
            $docComment = Get-DocCommentForLine -LineNumber $signal.lineNumber -DocumentationBlocks $docBlocks
            $elements += New-GDScriptElement `
                -ElementType 'signal' `
                -Name $signal.name `
                -LineNumber $signal.lineNumber `
                -Extends $extends `
                -ClassName $className `
                -Parameters $signal.parameters `
                -DocComment $docComment `
                -SourceFile $filePath
        }
        
        # Extract properties (exports and onready)
        $properties = Get-GDScriptProperties -Content $rawContent
        foreach ($prop in $properties) {
            $docComment = Get-DocCommentForLine -LineNumber $prop.lineNumber -DocumentationBlocks $docBlocks
            $annotations = @()
            if ($prop.isExport) { $annotations += '@export' }
            if ($prop.isOnReady) { $annotations += '@onready' }
            if (-not [string]::IsNullOrEmpty($prop.exportVariant)) { $annotations += "@export_$($prop.exportVariant)" }
            
            $paramObj = @()
            $defaultVal = if ($prop.defaultValue) { $prop.defaultValue } elseif ($prop.value) { $prop.value } else { $null }
            if ($defaultVal) {
                $paramObj = @(@{
                    name = 'default'
                    type = $prop.type
                    default = $defaultVal
                })
            }
            
            $elements += New-GDScriptElement `
                -ElementType 'property' `
                -Name $prop.name `
                -LineNumber $prop.lineNumber `
                -Extends $extends `
                -ClassName $className `
                -Parameters $paramObj `
                -Annotations $annotations `
                -DocComment $docComment `
                -SourceFile $filePath
        }
        
        # Extract methods
        $methods = Get-GDScriptMethods -Content $rawContent
        foreach ($method in $methods) {
            $docComment = Get-DocCommentForLine -LineNumber $method.lineNumber -DocumentationBlocks $docBlocks
            $annotations = @()
            if ($method.isStatic) { $annotations += '@static' }
            
            $elements += New-GDScriptElement `
                -ElementType 'method' `
                -Name $method.name `
                -LineNumber $method.lineNumber `
                -Extends $extends `
                -ClassName $className `
                -Parameters $method.parameters `
                -ReturnType $method.returnType `
                -Annotations $annotations `
                -DocComment $docComment `
                -SourceFile $filePath
        }
        
        # Extract annotations
        $annotations = Get-GDScriptAnnotations -Content $rawContent
        foreach ($annotation in $annotations) {
            # Skip annotations already captured in other elements
            $alreadyCaptured = $elements | Where-Object { 
                $_.elementType -ne 'annotation' -and 
                $_.lineNumber -eq $annotation.lineNumber 
            }
            if (-not $alreadyCaptured) {
                $elements += New-GDScriptElement `
                    -ElementType 'annotation' `
                    -Name $annotation.name `
                    -LineNumber $annotation.lineNumber `
                    -Extends $extends `
                    -ClassName $className `
                    -Annotations @($annotation.fullText) `
                    -SourceFile $filePath
            }
        }
        
        # Build final result
        $result = @{
            fileType = 'gdscript'
            filePath = $filePath
            engineTarget = Get-GDScriptEngineVersion -Content $rawContent
            className = $className
            extends = $extends
            isTool = $classInfo.isTool
            icon = $classInfo.icon
            elements = $elements
            elementCounts = @{
                class = ($elements | Where-Object { $_.elementType -eq 'class' }).Count
                signal = ($elements | Where-Object { $_.elementType -eq 'signal' }).Count
                property = ($elements | Where-Object { $_.elementType -eq 'property' }).Count
                method = ($elements | Where-Object { $_.elementType -eq 'method' }).Count
                annotation = ($elements | Where-Object { $_.elementType -eq 'annotation' }).Count
            }
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        if ($IncludeRawContent) {
            $result.rawContent = $rawContent
        }
        
        Write-Verbose "[Invoke-GDScriptParse] Parsing complete: $($elements.Count) elements extracted"
        
        return $result
    }
    catch {
        Write-Error "[Invoke-GDScriptParse] Failed to parse GDScript: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Extracts class-level metadata from GDScript content.

.DESCRIPTION
    Parses class-level information including:
    - extends (parent class)
    - class_name (class name)
    - @tool annotation
    - @icon annotation

.PARAMETER Content
    The GDScript content to parse.

.OUTPUTS
    System.Collections.Hashtable. Class metadata object with className, extends, isTool, icon properties.

.EXAMPLE
    $classInfo = Get-GDScriptClassInfo -Content $gdscriptContent
#>
function Get-GDScriptClassInfo {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        $result = @{
            className = ''
            extends = ''
            isTool = $false
            icon = ''
        }
        
        $lines = $Content -split "`r?`n"
        
        foreach ($line in $lines) {
            # Check for extends
            if ($line -match $script:Patterns.Extends) {
                $result.extends = $matches['class']
                Write-Verbose "[Get-GDScriptClassInfo] Found extends: $($result.extends)"
            }
            
            # Check for class_name
            if ($line -match $script:Patterns.ClassName) {
                $result.className = $matches['name']
                Write-Verbose "[Get-GDScriptClassInfo] Found class_name: $($result.className)"
            }
            
            # Check for @tool
            if ($line -match $script:Patterns.Tool) {
                $result.isTool = $true
                Write-Verbose "[Get-GDScriptClassInfo] Found @tool annotation"
            }
            
            # Check for @icon
            if ($line -match $script:Patterns.Icon) {
                $result.icon = $matches['path']
                Write-Verbose "[Get-GDScriptClassInfo] Found @icon: $($result.icon)"
            }
        }
        
        return $result
    }
}

<#
.SYNOPSIS
    Extracts signal definitions from GDScript content.

.DESCRIPTION
    Parses signal declarations including signal name and parameters
    with their types.

.PARAMETER Content
    The GDScript content to parse.

.OUTPUTS
    System.Array. Array of signal objects with name, parameters, and lineNumber properties.

.EXAMPLE
    $signals = Get-GDScriptSignals -Content $gdscriptContent
#>
function Get-GDScriptSignals {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        $signals = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            if ($line -match $script:Patterns.Signal) {
                $signal = @{
                    name = $matches['name']
                    parameters = @()
                    lineNumber = $lineNumber
                }
                
                if ($matches['params']) {
                    $signal.parameters = ConvertFrom-GDScriptParams -ParamString $matches['params']
                }
                
                $signals += $signal
                Write-Verbose "[Get-GDScriptSignals] Found signal: $($signal.name) with $($signal.parameters.Count) parameters"
            }
        }
        
        return ,$signals
    }
}

<#
.SYNOPSIS
    Extracts properties from GDScript content.

.DESCRIPTION
    Parses property declarations including:
    - @export variables with types and defaults
    - @onready variables with types and values
    - Typed and inferred var declarations
    - const declarations

    This combines exports, onready, and regular variables into a unified property list.

.PARAMETER Content
    The GDScript content to parse.

.OUTPUTS
    System.Array. Array of property objects.

.EXAMPLE
    $properties = Get-GDScriptProperties -Content $gdscriptContent
#>
function Get-GDScriptProperties {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        $properties = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            $matched = $false
            
            # Skip @export_group and @export_category (handled in annotations)
            if ($line -match $script:Patterns.ExportGroup) {
                continue
            }
            if ($line -match $script:Patterns.ExportCategory) {
                continue
            }
            
            # Check for @export_variant patterns first (e.g., @export_range, @export_file) - Godot 4
            if ($line -match $script:Patterns.ExportVariant) {
                $matched = $true
                $variantMatch = [regex]::Match($line, '^\s*@export_(\w+)')
                $variantType = if ($variantMatch.Success) { $variantMatch.Groups[1].Value } else { '' }
                
                $prop = @{
                    name = $matches['name']
                    type = if ($matches['type']) { ConvertTo-NormalizedType -TypeString $matches['type'] } else { 'Variant' }
                    defaultValue = if ($matches['default']) { $matches['default'].Trim() } else { $null }
                    value = $null
                    isExport = $true
                    isOnReady = $false
                    exportVariant = $variantType
                    exportHint = if ($matches['hint']) { $matches['hint'].Trim() } else { '' }
                    isConst = $false
                    isGodot3Syntax = $false
                    lineNumber = $lineNumber
                }
                $properties += $prop
                Write-Verbose "[Get-GDScriptProperties] Found @export_$variantType`: $($prop.name)"
            }
            # Check for standard @export - Godot 4
            elseif ($line -match $script:Patterns.Export) {
                $matched = $true
                
                $prop = @{
                    name = $matches['name']
                    type = if ($matches['type']) { ConvertTo-NormalizedType -TypeString $matches['type'] } else { 'Variant' }
                    defaultValue = if ($matches['default']) { $matches['default'].Trim() } else { $null }
                    value = $null
                    isExport = $true
                    isOnReady = $false
                    exportVariant = ''
                    exportHint = if ($matches['hint']) { $matches['hint'].Trim() } else { '' }
                    isConst = $false
                    isGodot3Syntax = $false
                    lineNumber = $lineNumber
                }
                $properties += $prop
                Write-Verbose "[Get-GDScriptProperties] Found @export: $($prop.name)"
            }
            # Check for Godot 3 export(...) syntax
            elseif ($line -match $script:Patterns.Godot3Export) {
                $matched = $true
                
                $prop = @{
                    name = $matches['name']
                    type = 'Variant'
                    defaultValue = if ($matches['default']) { $matches['default'].Trim() } else { $null }
                    value = $null
                    isExport = $true
                    isOnReady = $false
                    exportVariant = ''
                    exportHint = if ($matches['hint']) { $matches['hint'].Trim() } else { '' }
                    isConst = $false
                    isGodot3Syntax = $true
                    lineNumber = $lineNumber
                }
                
                # Infer type from Godot 3 export hint if available
                if ($prop.exportHint -and $prop.exportHint -match '^\s*(\w+)\s*$') {
                    $prop.type = $matches[1]
                }
                
                $properties += $prop
                Write-Verbose "[Get-GDScriptProperties] Found export(...): $($prop.name)"
            }
            # Check for @onready (Godot 4)
            elseif ($line -match $script:Patterns.OnReady) {
                $matched = $true
                
                $prop = @{
                    name = $matches['name']
                    type = if ($matches['type']) { ConvertTo-NormalizedType -TypeString $matches['type'] } else { 'Variant' }
                    defaultValue = $null
                    value = if ($matches['value']) { $matches['value'].Trim() } else { $null }
                    isExport = $false
                    isOnReady = $true
                    exportVariant = ''
                    exportHint = ''
                    isConst = $false
                    isGodot3Syntax = $false
                    lineNumber = $lineNumber
                }
                $properties += $prop
                Write-Verbose "[Get-GDScriptProperties] Found @onready: $($prop.name)"
            }
            # Check for Godot 3 onready
            elseif ($line -match $script:Patterns.Godot3OnReady) {
                $matched = $true
                
                $prop = @{
                    name = $matches['name']
                    type = 'Variant'
                    defaultValue = $null
                    value = if ($matches['value']) { $matches['value'].Trim() } else { $null }
                    isExport = $false
                    isOnReady = $true
                    exportVariant = ''
                    exportHint = ''
                    isConst = $false
                    isGodot3Syntax = $true
                    lineNumber = $lineNumber
                }
                $properties += $prop
                Write-Verbose "[Get-GDScriptProperties] Found onready: $($prop.name)"
            }
            # Check for const
            elseif ($line -match $script:Patterns.Const) {
                $matched = $true
                
                $prop = @{
                    name = $matches['name']
                    type = if ($matches['type']) { ConvertTo-NormalizedType -TypeString $matches['type'] } else { 'Variant' }
                    defaultValue = $null
                    value = $matches['value'].Trim()
                    isExport = $false
                    isOnReady = $false
                    exportVariant = ''
                    exportHint = ''
                    isConst = $true
                    isGodot3Syntax = $false
                    lineNumber = $lineNumber
                }
                $properties += $prop
                Write-Verbose "[Get-GDScriptProperties] Found const: $($prop.name)"
            }
            # Check for typed var (not export/onready)
            elseif ($line -match $script:Patterns.TypedVar) {
                $matched = $true
                
                $prop = @{
                    name = $matches['name']
                    type = ConvertTo-NormalizedType -TypeString $matches['type']
                    defaultValue = if ($matches['default']) { $matches['default'].Trim() } else { $null }
                    value = $null
                    isExport = $false
                    isOnReady = $false
                    exportVariant = ''
                    exportHint = ''
                    isConst = $false
                    isGodot3Syntax = $false
                    lineNumber = $lineNumber
                }
                $properties += $prop
                Write-Verbose "[Get-GDScriptProperties] Found typed var: $($prop.name)"
            }
            # Check for inferred var
            elseif ($line -match $script:Patterns.InferredVar) {
                $matched = $true
                
                $prop = @{
                    name = $matches['name']
                    type = 'inferred'
                    defaultValue = $null
                    value = $matches['value'].Trim()
                    isExport = $false
                    isOnReady = $false
                    exportVariant = ''
                    exportHint = ''
                    isConst = $false
                    isGodot3Syntax = $false
                    lineNumber = $lineNumber
                }
                $properties += $prop
                Write-Verbose "[Get-GDScriptProperties] Found inferred var: $($prop.name)"
            }
        }
        
        return ,$properties
    }
}

<#
.SYNOPSIS
    Extracts method definitions from GDScript content.

.DESCRIPTION
    Parses function declarations including:
    - Function name
    - Parameters with types and defaults
    - Return type annotation
    - Static modifier

.PARAMETER Content
    The GDScript content to parse.

.OUTPUTS
    System.Array. Array of method objects.

.EXAMPLE
    $methods = Get-GDScriptMethods -Content $gdscriptContent
#>
function Get-GDScriptMethods {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        $functions = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            $isStatic = $false
            $matched = $false
            
            # Check for static function
            if ($line -match $script:Patterns.StaticFunc) {
                $isStatic = $true
                $matched = $true
            }
            # Check for regular function
            elseif ($line -match $script:Patterns.Function) {
                $matched = $true
            }
            
            if ($matched) {
                $func = @{
                    name = $matches['name']
                    parameters = @()
                    returnType = 'void'
                    isStatic = $isStatic
                    lineNumber = $lineNumber
                }
                
                if ($matches['params']) {
                    $func.parameters = ConvertFrom-GDScriptParams -ParamString $matches['params']
                }
                
                if ($matches['ret']) {
                    $func.returnType = ConvertTo-NormalizedType -TypeString $matches['ret']
                }
                
                $functions += $func
                Write-Verbose "[Get-GDScriptMethods] Found function: $($func.name)($($func.parameters.Count) params) -> $($func.returnType)"
            }
        }
        
        return ,$functions
    }
}

<#
.SYNOPSIS
    Extracts all GDScript annotations from content.

.DESCRIPTION
    Parses all annotation declarations including:
    - @tool
    - @icon
    - @export and variants (@export_range, @export_file, etc.)
    - @onready
    - @export_group
    - @export_category

.PARAMETER Content
    The GDScript content to parse.

.OUTPUTS
    System.Array. Array of annotation objects.

.EXAMPLE
    $annotations = Get-GDScriptAnnotations -Content $gdscriptContent
#>
function Get-GDScriptAnnotations {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        $annotations = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Match @ annotations
            if ($line -match '^\s*(@\w+)') {
                $annotationName = $matches[1]
                
                # Skip if it's part of a variable or function declaration
                # These are handled in properties and methods
                if ($line -match '^\s*@export\s' -or 
                    $line -match '^\s*@export_\w+' -or 
                    $line -match '^\s*@onready\s') {
                    continue
                }
                
                $annotation = @{
                    name = $annotationName
                    fullText = $line.Trim()
                    lineNumber = $lineNumber
                }
                
                # Extract arguments if present
                if ($line -match '^\s*@\w+\s*\(([^)]*)\)') {
                    $annotation.arguments = $matches[1].Trim()
                }
                
                $annotations += $annotation
                Write-Verbose "[Get-GDScriptAnnotations] Found annotation: $annotationName"
            }
        }
        
        return ,$annotations
    }
}

# ============================================================================
# Additional Utility Functions for Phase 4 Pipeline
# ============================================================================

<#
.SYNOPSIS
    Parses project.godot file to extract autoload registrations.

.DESCRIPTION
    Extracts autoload node registrations from a Godot project file.

.PARAMETER Path
    Path to the project.godot file.

.OUTPUTS
    System.Array. Array of autoload objects with name, path, and isSingleton properties.

.EXAMPLE
    $autoloads = Get-GDScriptAutoloads -Path "project.godot"
#>
function Get-GDScriptAutoloads {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Warning "Project file not found: $Path"
            return @()
        }
        
        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $autoloads = @()
        
        # Match autoload entries: Name="*path"
        $pattern = '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"\*?([^"]+)"'
        $lines = $content -split "`r?`n"
        $inAutoloadSection = $false
        
        foreach ($line in $lines) {
            # Check for section headers
            if ($line -match '^\s*\[autoload\]') {
                $inAutoloadSection = $true
                continue
            }
            if ($line -match '^\s*\[' -and $inAutoloadSection) {
                $inAutoloadSection = $false
                continue
            }
            
            if ($inAutoloadSection -and $line -match $pattern) {
                $autoloads += @{
                    name = $matches[1]
                    path = $matches[2]
                    isSingleton = $line -match '^\s*\*'
                }
            }
        }
        
        Write-Verbose "[Get-GDScriptAutoloads] Found $($autoloads.Count) autoloads"
        return $autoloads
    }
    catch {
        Write-Error "[Get-GDScriptAutoloads] Failed to parse autoloads: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Parses project.godot file to extract input actions.

.DESCRIPTION
    Extracts InputMap action definitions from a Godot project file.

.PARAMETER Path
    Path to the project.godot file.

.OUTPUTS
    System.Array. Array of input action objects.

.EXAMPLE
    $inputActions = Get-GDScriptInputActions -Path "project.godot"
#>
function Get-GDScriptInputActions {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Warning "Project file not found: $Path"
            return @()
        }
        
        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $actions = @()
        
        # Match input action entries
        $lines = $content -split "`r?`n"
        $inInputSection = $false
        $currentAction = $null
        
        foreach ($line in $lines) {
            # Check for section headers
            if ($line -match '^\s*\[input\]') {
                $inInputSection = $true
                continue
            }
            if ($line -match '^\s*\[' -and $inInputSection) {
                $inInputSection = $false
                continue
            }
            
            if ($inInputSection) {
                # New action: action_name={...}
                if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{') {
                    $currentAction = @{
                        name = $matches[1]
                        events = @()
                    }
                }
                # Event within action
                elseif ($currentAction -and $line -match '"device"') {
                    # Parse event details
                    if ($line -match '"physical_keycode"\s*:\s*(\d+)') {
                        $currentAction.events += @{ type = 'key'; scancode = $matches[1] }
                    }
                    elseif ($line -match '"button_index"\s*:\s*(\d+)') {
                        $currentAction.events += @{ type = 'mouse'; button = $matches[1] }
                    }
                }
                # End of action
                elseif ($currentAction -and $line -match '^\s*\}') {
                    $actions += $currentAction
                    $currentAction = $null
                }
            }
        }
        
        Write-Verbose "[Get-GDScriptInputActions] Found $($actions.Count) input actions"
        return $actions
    }
    catch {
        Write-Error "[Get-GDScriptInputActions] Failed to parse input actions: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Parses plugin.cfg file to extract addon metadata.

.DESCRIPTION
    Extracts addon metadata from a Godot plugin.cfg file.

.PARAMETER Path
    Path to the plugin.cfg file.

.OUTPUTS
    System.Collections.Hashtable. Addon metadata object.

.EXAMPLE
    $addon = Get-GDScriptAddonMetadata -Path "addons/MyAddon/plugin.cfg"
#>
function Get-GDScriptAddonMetadata {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Warning "Plugin.cfg not found: $Path"
            return @{}
        }
        
        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $metadata = @{
            name = ''
            description = ''
            author = ''
            version = ''
            script = ''
            installType = 'addon'
        }
        
        # Parse plugin.cfg entries
        if ($content -match '^\s*name\s*=\s*"([^"]+)"' -or $content -match "^\s*name\s*=\s*'([^']+)'") {
            $metadata.name = $matches[1]
        }
        if ($content -match '^\s*description\s*=\s*"([^"]*)"' -or $content -match "^\s*description\s*=\s*'([^']*)'") {
            $metadata.description = $matches[1]
        }
        if ($content -match '^\s*author\s*=\s*"([^"]+)"' -or $content -match "^\s*author\s*=\s*'([^']+)'") {
            $metadata.author = $matches[1]
        }
        if ($content -match '^\s*version\s*=\s*"([^"]+)"' -or $content -match "^\s*version\s*=\s*'([^']+)'") {
            $metadata.version = $matches[1]
        }
        if ($content -match '^\s*script\s*=\s*"([^"]+)"' -or $content -match "^\s*script\s*=\s*'([^']+)'") {
            $metadata.script = $matches[1]
        }
        
        Write-Verbose "[Get-GDScriptAddonMetadata] Parsed addon: $($metadata.name)"
        return $metadata
    }
    catch {
        Write-Error "[Get-GDScriptAddonMetadata] Failed to parse plugin.cfg: $_"
        return @{}
    }
}

<#
.SYNOPSIS
    Parses GDExtension manifest (gdextension file).

.DESCRIPTION
    Extracts GDExtension library configuration from a .gdextension file.

.PARAMETER Path
    Path to the .gdextension file.

.OUTPUTS
    System.Collections.Hashtable. GDExtension manifest object.

.EXAMPLE
    $manifest = Get-GDExtensionManifest -Path "my_extension.gdextension"
#>
function Get-GDExtensionManifest {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Warning "GDExtension file not found: $Path"
            return @{}
        }
        
        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $manifest = @{
            entrySymbol = ''
            compatibilityMinimum = ''
            libraries = @()
            dependencies = @()
        }
        
        # Parse entry symbol
        if ($content -match '^\s*entry_symbol\s*=\s*"([^"]+)"') {
            $manifest.entrySymbol = $matches[1]
        }
        
        # Parse compatibility minimum
        if ($content -match '^\s*compatibility_minimum\s*=\s*"([^"]+)"') {
            $manifest.compatibilityMinimum = $matches[1]
        }
        
        # Parse libraries
        $lines = $content -split "`r?`n"
        foreach ($line in $lines) {
            if ($line -match '^\s*(\w+)\s*=\s*"res://([^"]+)"') {
                $manifest.libraries += @{
                    platform = $matches[1]
                    path = "res://$($matches[2])"
                }
            }
        }
        
        Write-Verbose "[Get-GDExtensionManifest] Parsed GDExtension: $($manifest.entrySymbol)"
        return $manifest
    }
    catch {
        Write-Error "[Get-GDExtensionManifest] Failed to parse gdextension: $_"
        return @{}
    }
}

<#
.SYNOPSIS
    Converts parsed GDScript AST to a summary object.

.DESCRIPTION
    Creates a condensed summary of the parsed GDScript suitable for
    indexing and retrieval in the LLM Workflow platform.

.PARAMETER Ast
    The parsed AST object from Invoke-GDScriptParse.

.OUTPUTS
    System.Collections.Hashtable. Summary object.

.EXAMPLE
    $result = Invoke-GDScriptParse -Path "player.gd"
    $summary = ConvertTo-GDScriptSummary -Ast $result
#>
function ConvertTo-GDScriptSummary {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$Ast
    )
    
    process {
        $signalNames = $Ast.elements | Where-Object { $_.elementType -eq 'signal' } | ForEach-Object { $_.name }
        $exportProps = $Ast.elements | Where-Object { $_.elementType -eq 'property' -and $_.annotations -contains '@export' } | ForEach-Object { "$($_.name)" }
        $functionSigs = $Ast.elements | Where-Object { $_.elementType -eq 'method' } | ForEach-Object { 
            $params = $_.parameters | ForEach-Object { "$($_.name):$($_.type)" }
            "$($_.name)($($params -join ', ')) -> $($_.returnType)"
        }
        
        return @{
            fileType = $Ast.fileType
            engineTarget = $Ast.engineTarget
            className = $Ast.className
            extends = $Ast.extends
            isTool = $Ast.isTool
            icon = $Ast.icon
            signalCount = ($Ast.elements | Where-Object { $_.elementType -eq 'signal' }).Count
            signals = $signalNames
            exportCount = ($Ast.elements | Where-Object { $_.elementType -eq 'property' -and $_.annotations -contains '@export' }).Count
            exports = $exportProps
            functionCount = ($Ast.elements | Where-Object { $_.elementType -eq 'method' }).Count
            functions = $functionSigs
            propertyCount = ($Ast.elements | Where-Object { $_.elementType -eq 'property' }).Count
            parsedAt = $Ast.parsedAt
        }
    }
}

# ============================================================================
# Module Exports
# ============================================================================

# Only export if running as a module (not when dot-sourced)
if ($MyInvocation.InvocationName -eq 'Import-Module' -or $MyInvocation.Line -match 'Import-Module') {
    Export-ModuleMember -Function @(
        # Main entry point
        'Invoke-GDScriptParse'
        
        # Core extraction functions
        'Get-GDScriptClassInfo'
        'Get-GDScriptSignals'
        'Get-GDScriptProperties'
        'Get-GDScriptMethods'
        'Get-GDScriptAnnotations'
        
        # Utility functions
        'Get-GDScriptEngineVersion'
        'Get-GDScriptDocumentation'
        'ConvertTo-GDScriptSummary'
        
        # Project-level functions
        'Get-GDScriptAutoloads'
        'Get-GDScriptInputActions'
        'Get-GDScriptAddonMetadata'
        'Get-GDExtensionManifest'
    )
}
