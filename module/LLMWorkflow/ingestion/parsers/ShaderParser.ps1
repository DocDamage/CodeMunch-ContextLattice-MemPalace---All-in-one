#requires -Version 5.1
<#
.SYNOPSIS
    Shader Parameter Parser for the LLM Workflow Platform's Phase 4 Structured Extraction Pipeline.

.DESCRIPTION
    This module provides PowerShell-based parsing capabilities for shader parameter extraction
    from Godot shader files (.gdshader), Blender shader node definitions, and generic GLSL shader files.
    
    It extracts:
    - Shader type declarations (for Godot)
    - Uniform/uniform parameter declarations with default values and hints
    - Varying declarations
    - Function definitions (vertex, fragment, light, etc.)
    - Struct definitions
    - Preprocessor directives (#define, #include, etc.)

.NOTES
    File Name      : ShaderParser.ps1
    Module Version : 1.0.0
    Author         : LLM Workflow Platform
    Copyright      : (c) DocDamage. All rights reserved.
    Requires       : PowerShell 5.1 or later

.EXAMPLE
    Import-Module ShaderParser.ps1
    $shaderData = ConvertFrom-GodotShader -Path "./materials/player.gdshader"
    $shaderData | ConvertTo-Json -Depth 10

.LINK
    https://github.com/DocDamage/CodeMunch-ContextLattice-MemPalace---All-in-one
#>

Set-StrictMode -Version Latest

#region Helper Functions

<#
.SYNOPSIS
    Removes C-style comments from shader source code.

.DESCRIPTION
    Strips both single-line (//) and multi-line (/* */) comments from shader source.
    Preserves comment content for documentation extraction if needed.

.PARAMETER Content
    The shader source code content.

.PARAMETER PreserveDocComments
    If specified, preserves documentation comments (/** */) for later extraction.

.OUTPUTS
    System.String - The source code with comments removed.
#>
function Remove-ShaderComments {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content,

        [switch]$PreserveDocComments
    )

    process {
        try {
            Write-Verbose "Removing comments from shader source"
            
            $result = $Content
            
            if ($PreserveDocComments) {
                # Remove single-line comments
                $result = [regex]::Replace($result, '//.*$', '', [System.Text.RegularExpressions.RegexOptions]::Multiline)
                # Remove multi-line non-doc comments /* */ but preserve /** */
                $result = [regex]::Replace($result, '(?<!/)/\*(?!\*).*?\*/', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            }
            else {
                # Remove all single-line comments
                $result = [regex]::Replace($result, '//.*$', '', [System.Text.RegularExpressions.RegexOptions]::Multiline)
                # Remove all multi-line comments
                $result = [regex]::Replace($result, '/\*.*?\*/', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            }
            
            return $result
        }
        catch {
            Write-Error "Failed to remove comments: $_"
            return $Content
        }
    }
}

<#
.SYNOPSIS
    Normalizes whitespace in shader source code.

.DESCRIPTION
    Collapses multiple whitespace characters and normalizes line endings.

.PARAMETER Content
    The shader source code content.

.OUTPUTS
    System.String - The normalized source code.
#>
function Optimize-ShaderWhitespace {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )

    process {
        try {
            $result = $Content
            # Normalize line endings to Unix-style
            $result = $result -replace "`r`n", "`n"
            $result = $result -replace "`r", "`n"
            # Trim trailing whitespace from each line
            $result = ($result -split "`n" | ForEach-Object { $_.TrimEnd() }) -join "`n"
            return $result
        }
        catch {
            Write-Error "Failed to normalize whitespace: $_"
            return $Content
        }
    }
}

<#
.SYNOPSIS
    Extracts the shader type from a Godot shader file.

.DESCRIPTION
    Parses the shader_type declaration from Godot shader source.

.PARAMETER Content
    The Godot shader source code.

.OUTPUTS
    System.String - The shader type (spatial, canvas_item, particles, sky, fog) or empty string.
#>
function Get-GodotShaderType {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    try {
        $match = [regex]::Match($Content, 'shader_type\s+(\w+)\s*;')
        if ($match.Success) {
            $shaderType = $match.Groups[1].Value.ToLower()
            Write-Verbose "Found shader type: $shaderType"
            return $shaderType
        }
        return ""
    }
    catch {
        Write-Error "Failed to extract shader type: $_"
        return ""
    }
}

<#
.SYNOPSIS
    Extracts render mode declarations from a Godot shader.

.DESCRIPTION
    Parses render_mode declarations and returns an array of mode strings.

.PARAMETER Content
    The Godot shader source code.

.OUTPUTS
    System.String[] - Array of render mode strings.
#>
function Get-GodotRenderMode {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    try {
        $modes = @()
        $pattern = 'render_mode\s+([^;]+);'
        $matches = [regex]::Matches($Content, $pattern)
        
        foreach ($match in $matches) {
            $modeList = $match.Groups[1].Value
            $individualModes = $modeList -split ',' | ForEach-Object { $_.Trim() }
            $modes += $individualModes
        }
        
        Write-Verbose "Found render modes: $($modes -join ', ')"
        return $modes
    }
    catch {
        Write-Error "Failed to extract render modes: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Parses a Godot uniform declaration line.

.DESCRIPTION
    Extracts uniform name, type, hint, and default value from a uniform declaration.

.PARAMETER Line
    The uniform declaration line.

.OUTPUTS
    System.Collections.Hashtable - Uniform definition or $null if parsing fails.
#>
function ConvertFrom-GodotUniform {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Line
    )

    try {
        # Pattern for: uniform type name : hint = default;
        # or: uniform type name = default;
        # or: uniform type name;
        $pattern = 'uniform\s+(\w+)\s+(\w+)(?:\s*:\s*([^=;]+))?(?:\s*=\s*([^;]+))?\s*;'
        $match = [regex]::Match($Line, $pattern)
        
        if (-not $match.Success) {
            return $null
        }
        
        $uniformType = $match.Groups[1].Value
        $uniformName = $match.Groups[2].Value
        $hintText = if ($match.Groups[3].Success) { $match.Groups[3].Value.Trim() } else { "" }
        $defaultValue = if ($match.Groups[4].Success) { $match.Groups[4].Value.Trim() } else { $null }
        
        # Parse hint into structured format
        $hint = @{}
        $hintString = ""
        
        if (-not [string]::IsNullOrWhiteSpace($hintText)) {
            $hintParts = $hintText -split ',' | ForEach-Object { $_.Trim() }
            
            foreach ($part in $hintParts) {
                if ($part -match 'hint_range\s*\(\s*([^,]+)\s*,\s*([^,]+)(?:\s*,\s*([^)]+))?\s*\)') {
                    $hint['type'] = 'range'
                    $hint['min'] = $matches[1].Trim()
                    $hint['max'] = $matches[2].Trim()
                    if ($matches[3]) {
                        $hint['step'] = $matches[3].Trim()
                    }
                    $hintString = "range($($hint['min']), $($hint['max'])$(if($hint['step']){', '+$hint['step']}))"
                }
                elseif ($part -eq 'source_color') {
                    $hint['type'] = 'source_color'
                    $hintString = 'source_color'
                }
                elseif ($part -eq 'instance_index') {
                    $hint['type'] = 'instance_index'
                    $hintString = 'instance_index'
                }
                elseif ($part -match 'hint_(\w+)') {
                    $hintType = $matches[1]
                    $hint['type'] = $hintType
                    $hintString = $part
                }
                elseif ($part -match 'filter_(\w+)') {
                    $hint['filter'] = $matches[1]
                    if ($hintString) { $hintString += ", " }
                    $hintString += $part
                }
                elseif ($part -match 'repeat_(\w+)') {
                    $hint['repeat'] = $matches[1]
                    if ($hintString) { $hintString += ", " }
                    $hintString += $part
                }
                elseif ($part -match 'hint_default_(\w+)') {
                    $hint['default'] = $matches[1]
                    if ($hintString) { $hintString += ", " }
                    $hintString += $part
                }
                else {
                    if ($hintString) { $hintString += ", " }
                    $hintString += $part
                }
            }
        }
        
        return @{
            name = $uniformName
            type = $uniformType
            defaultValue = $defaultValue
            hint = $hintString
            hintDetail = $hint
        }
    }
    catch {
        Write-Error "Failed to parse uniform declaration: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Parses a GLSL uniform declaration line.

.DESCRIPTION
    Extracts uniform name, type, and array size from GLSL uniform declarations.

.PARAMETER Line
    The uniform declaration line.

.OUTPUTS
    System.Collections.Hashtable - Uniform definition or $null if parsing fails.
#>
function ConvertFrom-GLSLUniform {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Line
    )

    try {
        # Pattern for: uniform type name;
        # or: uniform type name[size];
        # or: uniform layout(...) type name;
        $pattern = 'uniform\s+(?:(?:highp|mediump|lowp)\s+)?(?:layout\s*\([^)]+\)\s+)?(\w+)\s+(\w+)(?:\[(\w+)\])?\s*;'
        $match = [regex]::Match($Line, $pattern)
        
        if (-not $match.Success) {
            return $null
        }
        
        $uniformType = $match.Groups[1].Value
        $uniformName = $match.Groups[2].Value
        $arraySize = if ($match.Groups[3].Success) { $match.Groups[3].Value } else { $null }
        
        return @{
            name = $uniformName
            type = $uniformType
            isArray = ($null -ne $arraySize)
            arraySize = $arraySize
            defaultValue = $null  # GLSL uniforms don't have defaults in shader
            hint = ""
        }
    }
    catch {
        Write-Error "Failed to parse GLSL uniform: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Parses a varying declaration line (Godot or GLSL).

.DESCRIPTION
    Extracts varying/in/out variable name and type.

.PARAMETER Line
    The varying declaration line.

.PARAMETER ShaderLanguage
    The shader language type: 'godot' or 'glsl'.

.OUTPUTS
    System.Collections.Hashtable - Varying definition or $null if parsing fails.
#>
function ConvertFrom-Varying {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Line,

        [Parameter(Mandatory = $true)]
        [ValidateSet('godot', 'glsl')]
        [string]$ShaderLanguage
    )

    try {
        $pattern = if ($ShaderLanguage -eq 'godot') {
            'varying\s+(\w+)\s+(\w+)\s*;'
        }
        else {
            '(?:in|out)\s+(?:(?:smooth|flat|noperspective)\s+)?(?:highp|mediump|lowp\s+)?(\w+)\s+(\w+)(?:\[(\w+)\])?\s*;'
        }
        
        $match = [regex]::Match($Line, $pattern)
        
        if (-not $match.Success) {
            return $null
        }
        
        $varyingType = $match.Groups[1].Value
        $varyingName = $match.Groups[2].Value
        $arraySize = if ($match.Groups[3].Success) { $match.Groups[3].Value } else { $null }
        
        $result = @{
            name = $varyingName
            type = $varyingType
        }
        
        if ($ShaderLanguage -eq 'glsl' -and $arraySize) {
            $result['isArray'] = $true
            $result['arraySize'] = $arraySize
        }
        
        # Determine if this is input or output for GLSL
        if ($ShaderLanguage -eq 'glsl') {
            $trimmedLine = $Line.Trim()
            if ($trimmedLine.StartsWith('in ')) {
                $result['direction'] = 'in'
            }
            elseif ($trimmedLine.StartsWith('out ')) {
                $result['direction'] = 'out'
            }
        }
        
        return $result
    }
    catch {
        Write-Error "Failed to parse varying: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Parses a function definition from shader source.

.DESCRIPTION
    Extracts function name, return type, and parameters from a function declaration.

.PARAMETER Content
    The shader source code.

.PARAMETER FunctionName
    Optional specific function name to extract.

.OUTPUTS
    System.Collections.Hashtable[] - Array of function definitions.
#>
function Get-ShaderFunctionDefinition {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [string]$FunctionName = ""
    )

    try {
        $functions = @()
        
        # Pattern to match function definitions
        # Matches: return_type function_name(params) {
        $pattern = '(\w+)\s+(\w+)\s*\(([^)]*)\)\s*\{'
        $matches = [regex]::Matches($Content, $pattern)
        
        foreach ($match in $matches) {
            $returnType = $match.Groups[1].Value
            $funcName = $match.Groups[2].Value
            $paramsText = $match.Groups[3].Value
            
            # Skip struct definitions that look like functions
            if ($returnType -in @('struct', 'if', 'while', 'for', 'switch')) {
                continue
            }
            
            if (-not [string]::IsNullOrWhiteSpace($FunctionName) -and $funcName -ne $FunctionName) {
                continue
            }
            
            # Parse parameters
            $parameters = @()
            if (-not [string]::IsNullOrWhiteSpace($paramsText)) {
                $paramList = $paramsText -split ',' | ForEach-Object { $_.Trim() }
                foreach ($param in $paramList) {
                    if ([string]::IsNullOrWhiteSpace($param)) { continue }
                    
                    # Pattern: (in|out|inout)? type name
                    $paramPattern = '(?:(in|out|inout)\s+)?(\w+)\s+(\w+)(?:\[(\w+)\])?'
                    $paramMatch = [regex]::Match($param, $paramPattern)
                    
                    if ($paramMatch.Success) {
                        $paramObj = @{
                            name = $paramMatch.Groups[3].Value
                            type = $paramMatch.Groups[2].Value
                            qualifier = if ($paramMatch.Groups[1].Success) { $paramMatch.Groups[1].Value } else { '' }
                        }
                        if ($paramMatch.Groups[4].Success) {
                            $paramObj['isArray'] = $true
                            $paramObj['arraySize'] = $paramMatch.Groups[4].Value
                        }
                        $parameters += $paramObj
                    }
                }
            }
            
            $functions += @{
                name = $funcName
                returnType = $returnType
                parameters = $parameters
            }
        }
        
        return $functions
    }
    catch {
        Write-Error "Failed to extract function definitions: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Parses struct definitions from shader source.

.DESCRIPTION
    Extracts struct name and member fields.

.PARAMETER Content
    The shader source code.

.OUTPUTS
    System.Collections.Hashtable[] - Array of struct definitions.
#>
function Get-ShaderStructDefinition {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    try {
        $structs = @()
        
        # Pattern to match struct definitions: struct Name { ... };
        $pattern = 'struct\s+(\w+)\s*\{([^}]+)\}\s*;'
        $matches = [regex]::Matches($Content, $pattern)
        
        foreach ($match in $matches) {
            $structName = $match.Groups[1].Value
            $membersText = $match.Groups[2].Value
            
            $members = @()
            $memberLines = $membersText -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            
            foreach ($memberLine in $memberLines) {
                # Pattern: type name or type name[size]
                $memberPattern = '(\w+)\s+(\w+)(?:\[(\w+)\])?'
                $memberMatch = [regex]::Match($memberLine, $memberPattern)
                
                if ($memberMatch.Success) {
                    $member = @{
                        name = $memberMatch.Groups[2].Value
                        type = $memberMatch.Groups[1].Value
                    }
                    if ($memberMatch.Groups[3].Success) {
                        $member['isArray'] = $true
                        $member['arraySize'] = $memberMatch.Groups[3].Value
                    }
                    $members += $member
                }
            }
            
            $structs += @{
                name = $structName
                members = $members
            }
        }
        
        return $structs
    }
    catch {
        Write-Error "Failed to extract struct definitions: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts preprocessor directives from shader source.

.DESCRIPTION
    Parses #define, #include, #ifdef, #ifndef, #endif, #else, #elif, #undef, #pragma, #version directives.

.PARAMETER Content
    The shader source code.

.OUTPUTS
    System.Collections.Hashtable[] - Array of preprocessor directive definitions.
#>
function Get-ShaderPreprocessorDirectives {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    try {
        $directives = @()
        $lines = $Content -split "`n"
        
        foreach ($line in $lines) {
            $trimmedLine = $line.Trim()
            
            # Match preprocessor directives
            if ($trimmedLine -match '^#\s*(\w+)\s*(.*)$') {
                $directive = $matches[1]
                $value = $matches[2].Trim()
                
                $directiveObj = @{
                    directive = $directive
                    rawValue = $value
                }
                
                # Parse specific directive types
                switch ($directive) {
                    'define' {
                        # #define NAME value or #define NAME(args) value
                        if ($value -match '^(\w+)\s*(?:\(([^)]*)\))?\s*(.*)$') {
                            $directiveObj['name'] = $matches[1]
                            $directiveObj['parameters'] = if ($matches[2]) { $matches[2] } else { $null }
                            $directiveObj['definition'] = if ($matches[3]) { $matches[3].Trim() } else { $null }
                            $directiveObj['isFunctionLike'] = [bool]$matches[2]
                        }
                    }
                    'include' {
                        # #include "file" or #include <file>
                        if ($value -match '^["<]([^">]+)[">]$') {
                            $directiveObj['path'] = $matches[1]
                            $directiveObj['isSystemInclude'] = $value.StartsWith('<')
                        }
                    }
                    'ifdef' {
                        $directiveObj['condition'] = $value
                        $directiveObj['type'] = 'conditional_start'
                    }
                    'ifndef' {
                        $directiveObj['condition'] = $value
                        $directiveObj['type'] = 'conditional_start_negated'
                    }
                    'if' {
                        $directiveObj['condition'] = $value
                        $directiveObj['type'] = 'conditional_if'
                    }
                    'elif' {
                        $directiveObj['condition'] = $value
                        $directiveObj['type'] = 'conditional_elif'
                    }
                    'else' {
                        $directiveObj['type'] = 'conditional_else'
                    }
                    'endif' {
                        $directiveObj['type'] = 'conditional_end'
                    }
                    'undef' {
                        $directiveObj['name'] = $value
                    }
                    'pragma' {
                        $directiveObj['pragma'] = $value
                    }
                    'version' {
                        if ($value -match '^(\d+)\s*(\w+)?$') {
                            $directiveObj['version'] = $matches[1]
                            $directiveObj['profile'] = if ($matches[2]) { $matches[2] } else { $null }
                        }
                    }
                    'extension' {
                        # #extension extension_name : behavior
                        if ($value -match '^(\w+)\s*:\s*(\w+)$') {
                            $directiveObj['extension'] = $matches[1]
                            $directiveObj['behavior'] = $matches[2]
                        }
                    }
                }
                
                $directives += $directiveObj
            }
        }
        
        return $directives
    }
    catch {
        Write-Error "Failed to extract preprocessor directives: $_"
        return @()
    }
}

#endregion

#region Main Parser Functions

<#
.SYNOPSIS
    Converts Godot shader file content to a structured manifest.

.DESCRIPTION
    Parses a Godot shader file (.gdshader) and extracts all relevant information
    including shader type, render modes, uniforms, varyings, functions, structs,
    and preprocessor directives.

.PARAMETER Path
    Path to the .gdshader file.

.PARAMETER Content
    Direct shader content string (alternative to Path).

.PARAMETER IncludeRawSource
    If specified, includes the raw source code in the output.

.OUTPUTS
    System.Collections.Hashtable - Structured shader manifest.

.EXAMPLE
    $manifest = ConvertFrom-GodotShader -Path "./shaders/water.gdshader"
    $manifest | ConvertTo-Json -Depth 10

.EXAMPLE
    $shaderContent = Get-Content -Raw "./shaders/fire.gdshader"
    $manifest = ConvertFrom-GodotShader -Content $shaderContent
#>
function ConvertFrom-GodotShader {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(ParameterSetName = 'Content')]
        [string]$Content,

        [switch]$IncludeRawSource
    )

    try {
        # Get content from path if provided
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                throw "Shader file not found: $Path"
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            Write-Verbose "Parsing Godot shader: $Path"
        }
        else {
            Write-Verbose "Parsing Godot shader from content"
        }

        if ([string]::IsNullOrWhiteSpace($Content)) {
            throw "Shader content is empty"
        }

        # Process content
        $processedContent = Remove-ShaderComments -Content $Content -PreserveDocComments
        $processedContent = Optimize-ShaderWhitespace -Content $processedContent
        
        # Extract shader type
        $shaderType = Get-GodotShaderType -Content $Content
        
        # Extract render modes
        $renderModes = Get-GodotRenderMode -Content $Content
        
        # Extract uniforms
        $uniforms = @()
        $uniformMatches = [regex]::Matches($processedContent, 'uniform\s+\w+\s+\w+[^;]*;')
        foreach ($match in $uniformMatches) {
            $uniform = ConvertFrom-GodotUniform -Line $match.Value
            if ($uniform) {
                $uniforms += $uniform
            }
        }
        
        # Extract varyings
        $varyings = @()
        $varyingMatches = [regex]::Matches($processedContent, 'varying\s+\w+\s+\w+\s*;')
        foreach ($match in $varyingMatches) {
            $varying = ConvertFrom-Varying -Line $match.Value -ShaderLanguage 'godot'
            if ($varying) {
                $varyings += $varying
            }
        }
        
        # Extract functions
        $functions = Get-ShaderFunctionDefinition -Content $processedContent
        
        # Extract structs
        $structs = Get-ShaderStructDefinition -Content $processedContent
        
        # Extract preprocessor directives
        $defines = Get-ShaderPreprocessorDirectives -Content $Content
        
        # Build manifest
        $manifest = @{
            fileType = "godot_shader"
            shaderType = $shaderType
            renderMode = $renderModes
            uniforms = $uniforms
            varyings = $varyings
            functions = $functions
            structs = $structs
            defines = $defines
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        # Add source file path if provided
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $manifest['sourcePath'] = (Resolve-Path -LiteralPath $Path).Path
        }
        
        # Include raw source if requested
        if ($IncludeRawSource) {
            $manifest['source'] = $Content
        }
        
        Write-Verbose "Successfully parsed Godot shader with $($uniforms.Count) uniforms, $($varyings.Count) varyings, $($functions.Count) functions"
        
        return $manifest
    }
    catch {
        Write-Error "Failed to parse Godot shader: $_"
        throw
    }
}

<#
.SYNOPSIS
    Converts GLSL shader file content to a structured manifest.

.DESCRIPTION
    Parses a GLSL shader file (.glsl, .vert, .frag, .comp) and extracts all relevant information
    including uniforms, varyings (in/out), functions, structs, and preprocessor directives.

.PARAMETER Path
    Path to the GLSL file.

.PARAMETER Content
    Direct shader content string (alternative to Path).

.PARAMETER ShaderStage
    Optional shader stage hint (vertex, fragment, geometry, compute, etc.).

.PARAMETER IncludeRawSource
    If specified, includes the raw source code in the output.

.OUTPUTS
    System.Collections.Hashtable - Structured shader manifest.

.EXAMPLE
    $manifest = ConvertFrom-GLSLShader -Path "./shaders/lighting.vert"
    $manifest | ConvertTo-Json -Depth 10

.EXAMPLE
    $shaderContent = Get-Content -Raw "./shaders/effects.frag"
    $manifest = ConvertFrom-GLSLShader -Content $shaderContent -ShaderStage fragment
#>
function ConvertFrom-GLSLShader {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(ParameterSetName = 'Content')]
        [string]$Content,

        [string]$ShaderStage = "",

        [switch]$IncludeRawSource
    )

    try {
        # Get content from path if provided
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                throw "Shader file not found: $Path"
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            Write-Verbose "Parsing GLSL shader: $Path"
            
            # Try to infer shader stage from extension
            if ([string]::IsNullOrWhiteSpace($ShaderStage)) {
                $extension = [System.IO.Path]::GetExtension($Path).ToLower()
                $ShaderStage = switch ($extension) {
                    '.vert' { 'vertex' }
                    '.frag' { 'fragment' }
                    '.geom' { 'geometry' }
                    '.comp' { 'compute' }
                    '.tesc' { 'tessellation_control' }
                    '.tese' { 'tessellation_evaluation' }
                    default { 'unknown' }
                }
            }
        }
        else {
            Write-Verbose "Parsing GLSL shader from content"
            if ([string]::IsNullOrWhiteSpace($ShaderStage)) {
                $ShaderStage = 'unknown'
            }
        }

        if ([string]::IsNullOrWhiteSpace($Content)) {
            throw "Shader content is empty"
        }

        # Process content
        $processedContent = Remove-ShaderComments -Content $Content
        $processedContent = Optimize-ShaderWhitespace -Content $processedContent
        
        # Extract version from #version directive
        $version = $null
        $versionMatch = [regex]::Match($Content, '#\s*version\s+(\d+)')
        if ($versionMatch.Success) {
            $version = $versionMatch.Groups[1].Value
        }
        
        # Extract uniforms
        $uniforms = @()
        $uniformMatches = [regex]::Matches($processedContent, 'uniform\s+(?:highp|mediump|lowp\s+)?(?:layout\s*\([^)]+\)\s+)?\w+\s+\w+(?:\[\w+\])?\s*;')
        foreach ($match in $uniformMatches) {
            $uniform = ConvertFrom-GLSLUniform -Line $match.Value
            if ($uniform) {
                $uniforms += $uniform
            }
        }
        
        # Extract varyings (in/out for modern GLSL)
        $varyings = @()
        
        # Match 'in' declarations (excluding layout and uniform)
        $inMatches = [regex]::Matches($processedContent, '(?<!\w)in\s+(?:smooth|flat|noperspective\s+)?(?:highp|mediump|lowp\s+)?(?:\w+)\s+\w+(?:\[\w+\])?\s*;')
        foreach ($match in $inMatches) {
            $varying = ConvertFrom-Varying -Line $match.Value -ShaderLanguage 'glsl'
            if ($varying) {
                $varyings += $varying
            }
        }
        
        # Match 'out' declarations
        $outMatches = [regex]::Matches($processedContent, '(?<!\w)out\s+(?:smooth|flat|noperspective\s+)?(?:highp|mediump|lowp\s+)?(?:\w+)\s+\w+(?:\[\w+\])?\s*;')
        foreach ($match in $outMatches) {
            $varying = ConvertFrom-Varying -Line $match.Value -ShaderLanguage 'glsl'
            if ($varying) {
                $varyings += $varying
            }
        }
        
        # Also look for legacy 'varying' keyword (older GLSL)
        $legacyVaryingMatches = [regex]::Matches($processedContent, 'varying\s+\w+\s+\w+\s*;')
        foreach ($match in $legacyVaryingMatches) {
            $varying = ConvertFrom-Varying -Line $match.Value -ShaderLanguage 'godot'  # Reuse godot parser for varyings
            if ($varying) {
                $varying['direction'] = 'varying'
                $varyings += $varying
            }
        }
        
        # Extract functions
        $functions = Get-ShaderFunctionDefinition -Content $processedContent
        
        # Extract structs
        $structs = Get-ShaderStructDefinition -Content $processedContent
        
        # Extract preprocessor directives
        $defines = Get-ShaderPreprocessorDirectives -Content $Content
        
        # Extract layout qualifiers for inputs/outputs
        $layouts = @()
        $layoutMatches = [regex]::Matches($Content, 'layout\s*\(([^)]+)\)\s+(in|out)\s+\w+\s+\w+')
        foreach ($match in $layoutMatches) {
            $layouts += @{
                qualifier = $match.Groups[1].Value
                direction = $match.Groups[2].Value
                fullMatch = $match.Value
            }
        }
        
        # Build manifest
        $manifest = @{
            fileType = "glsl_shader"
            shaderStage = $ShaderStage
            glslVersion = $version
            uniforms = $uniforms
            varyings = $varyings
            functions = $functions
            structs = $structs
            defines = $defines
            layouts = $layouts
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        # Add source file path if provided
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $manifest['sourcePath'] = (Resolve-Path -LiteralPath $Path).Path
        }
        
        # Include raw source if requested
        if ($IncludeRawSource) {
            $manifest['source'] = $Content
        }
        
        Write-Verbose "Successfully parsed GLSL shader with $($uniforms.Count) uniforms, $($varyings.Count) varyings, $($functions.Count) functions"
        
        return $manifest
    }
    catch {
        Write-Error "Failed to parse GLSL shader: $_"
        throw
    }
}

<#
.SYNOPSIS
    Extracts uniform declarations from shader content.

.DESCRIPTION
    Parses shader source and returns an array of uniform variable definitions.
    Supports both Godot and GLSL shader syntax.

.PARAMETER Path
    Path to the shader file.

.PARAMETER Content
    Direct shader content string (alternative to Path).

.PARAMETER ShaderType
    The type of shader: 'godot' or 'glsl'. If not specified, will attempt auto-detection.

.OUTPUTS
    System.Collections.Hashtable[] - Array of uniform definitions.

.EXAMPLE
    $uniforms = Get-ShaderParameters -Path "./shaders/material.gdshader" -ShaderType godot
    $uniforms | Format-Table name, type, defaultValue

.EXAMPLE
    $uniforms = Get-ShaderParameters -Content $glslCode -ShaderType glsl
#>
function Get-ShaderParameters {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(ParameterSetName = 'Content')]
        [string]$Content,

        [ValidateSet('godot', 'glsl', 'auto')]
        [string]$ShaderType = 'auto'
    )

    try {
        # Get content from path if provided
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                throw "Shader file not found: $Path"
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            
            # Auto-detect shader type from extension if needed
            if ($ShaderType -eq 'auto') {
                $extension = [System.IO.Path]::GetExtension($Path).ToLower()
                $ShaderType = switch ($extension) {
                    '.gdshader' { 'godot' }
                    '.glsl' { 'glsl' }
                    { $_ -in @('.vert', '.frag', '.geom', '.comp', '.tesc', '.tese') } { 'glsl' }
                    default { 'glsl' }
                }
                Write-Verbose "Auto-detected shader type: $ShaderType"
            }
        }
        else {
            # Auto-detect from content if needed
            if ($ShaderType -eq 'auto') {
                if ($Content -match 'shader_type\s+\w+\s*;') {
                    $ShaderType = 'godot'
                }
                else {
                    $ShaderType = 'glsl'
                }
                Write-Verbose "Auto-detected shader type from content: $ShaderType"
            }
        }

        if ([string]::IsNullOrWhiteSpace($Content)) {
            throw "Shader content is empty"
        }

        # Process content
        $processedContent = Remove-ShaderComments -Content $Content
        
        $uniforms = @()
        
        if ($ShaderType -eq 'godot') {
            $uniformMatches = [regex]::Matches($processedContent, 'uniform\s+\w+\s+\w+[^;]*;')
            foreach ($match in $uniformMatches) {
                $uniform = ConvertFrom-GodotUniform -Line $match.Value
                if ($uniform) {
                    $uniforms += $uniform
                }
            }
        }
        else {
            $uniformMatches = [regex]::Matches($processedContent, 'uniform\s+(?:highp|mediump|lowp\s+)?(?:layout\s*\([^)]+\)\s+)?\w+\s+\w+(?:\[\w+\])?\s*;')
            foreach ($match in $uniformMatches) {
                $uniform = ConvertFrom-GLSLUniform -Line $match.Value
                if ($uniform) {
                    $uniforms += $uniform
                }
            }
        }
        
        Write-Verbose "Extracted $($uniforms.Count) uniform parameters"
        return $uniforms
    }
    catch {
        Write-Error "Failed to extract shader parameters: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts function definitions from shader content.

.DESCRIPTION
    Parses shader source and returns an array of function definitions including
    function name, return type, and parameters.

.PARAMETER Path
    Path to the shader file.

.PARAMETER Content
    Direct shader content string (alternative to Path).

.PARAMETER FunctionName
    Optional specific function name to extract.

.OUTPUTS
    System.Collections.Hashtable[] - Array of function definitions.

.EXAMPLE
    $functions = Get-ShaderFunctions -Path "./shaders/effect.frag"
    $functions | Where-Object { $_.name -eq 'main' }

.EXAMPLE
    $vertexFunc = Get-ShaderFunctions -Content $shaderCode -FunctionName "vertex"
#>
function Get-ShaderFunctions {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(ParameterSetName = 'Content')]
        [string]$Content,

        [string]$FunctionName = ""
    )

    try {
        # Get content from path if provided
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                throw "Shader file not found: $Path"
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }

        if ([string]::IsNullOrWhiteSpace($Content)) {
            throw "Shader content is empty"
        }

        # Process content
        $processedContent = Remove-ShaderComments -Content $Content
        
        $functions = Get-ShaderFunctionDefinition -Content $processedContent -FunctionName $FunctionName
        
        Write-Verbose "Extracted $($functions.Count) function definitions"
        return $functions
    }
    catch {
        Write-Error "Failed to extract shader functions: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts varying declarations from shader content.

.DESCRIPTION
    Parses shader source and returns an array of varying/in/out variable definitions.
    For Godot shaders, extracts 'varying' declarations.
    For GLSL shaders, extracts 'in' and 'out' declarations.

.PARAMETER Path
    Path to the shader file.

.PARAMETER Content
    Direct shader content string (alternative to Path).

.PARAMETER ShaderType
    The type of shader: 'godot' or 'glsl'. If not specified, will attempt auto-detection.

.PARAMETER Direction
    Filter by direction: 'in', 'out', or 'all' (default: 'all').

.OUTPUTS
    System.Collections.Hashtable[] - Array of varying definitions.

.EXAMPLE
    $varyings = Get-ShaderVaryings -Path "./shaders/vertex.vert" -ShaderType glsl
    $varyings | Where-Object { $_.direction -eq 'out' }

.EXAMPLE
    $varyings = Get-ShaderVaryings -Content $godotCode -ShaderType godot
#>
function Get-ShaderVaryings {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(ParameterSetName = 'Content')]
        [string]$Content,

        [ValidateSet('godot', 'glsl', 'auto')]
        [string]$ShaderType = 'auto',

        [ValidateSet('in', 'out', 'all')]
        [string]$Direction = 'all'
    )

    try {
        # Get content from path if provided
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                throw "Shader file not found: $Path"
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            
            # Auto-detect shader type from extension if needed
            if ($ShaderType -eq 'auto') {
                $extension = [System.IO.Path]::GetExtension($Path).ToLower()
                $ShaderType = switch ($extension) {
                    '.gdshader' { 'godot' }
                    default { 'glsl' }
                }
            }
        }
        else {
            # Auto-detect from content if needed
            if ($ShaderType -eq 'auto') {
                if ($Content -match 'shader_type\s+\w+\s*;') {
                    $ShaderType = 'godot'
                }
                else {
                    $ShaderType = 'glsl'
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($Content)) {
            throw "Shader content is empty"
        }

        # Process content
        $processedContent = Remove-ShaderComments -Content $Content
        
        $varyings = @()
        
        if ($ShaderType -eq 'godot') {
            $varyingMatches = [regex]::Matches($processedContent, 'varying\s+\w+\s+\w+\s*;')
            foreach ($match in $varyingMatches) {
                $varying = ConvertFrom-Varying -Line $match.Value -ShaderLanguage 'godot'
                if ($varying) {
                    $varyings += $varying
                }
            }
        }
        else {
            if ($Direction -in @('in', 'all')) {
                $inMatches = [regex]::Matches($processedContent, '(?<!\w)in\s+(?:smooth|flat|noperspective\s+)?(?:highp|mediump|lowp\s+)?(?:\w+)\s+\w+(?:\[\w+\])?\s*;')
                foreach ($match in $inMatches) {
                    $varying = ConvertFrom-Varying -Line $match.Value -ShaderLanguage 'glsl'
                    if ($varying) {
                        $varyings += $varying
                    }
                }
            }
            
            if ($Direction -in @('out', 'all')) {
                $outMatches = [regex]::Matches($processedContent, '(?<!\w)out\s+(?:smooth|flat|noperspective\s+)?(?:highp|mediump|lowp\s+)?(?:\w+)\s+\w+(?:\[\w+\])?\s*;')
                foreach ($match in $outMatches) {
                    $varying = ConvertFrom-Varying -Line $match.Value -ShaderLanguage 'glsl'
                    if ($varying) {
                        $varyings += $varying
                    }
                }
            }
            
            # Check for legacy 'varying' keyword
            $legacyMatches = [regex]::Matches($processedContent, 'varying\s+\w+\s+\w+\s*;')
            foreach ($match in $legacyMatches) {
                $varying = ConvertFrom-Varying -Line $match.Value -ShaderLanguage 'godot'
                if ($varying) {
                    $varying['direction'] = 'varying'
                    $varyings += $varying
                }
            }
        }
        
        Write-Verbose "Extracted $($varyings.Count) varying declarations"
        return $varyings
    }
    catch {
        Write-Error "Failed to extract shader varyings: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts struct definitions from shader content.

.DESCRIPTION
    Parses shader source and returns an array of struct definitions including
    struct name and member fields.

.PARAMETER Path
    Path to the shader file.

.PARAMETER Content
    Direct shader content string (alternative to Path).

.PARAMETER StructName
    Optional specific struct name to extract.

.OUTPUTS
    System.Collections.Hashtable[] - Array of struct definitions.

.EXAMPLE
    $structs = Get-ShaderStructs -Path "./shaders/types.glsl"
    $structs | Format-Table name, @{L='Members'; E={$_.members.Count}}

.EXAMPLE
    $lightStruct = Get-ShaderStructs -Content $shaderCode -StructName "LightData"
#>
function Get-ShaderStructs {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(ParameterSetName = 'Content')]
        [string]$Content,

        [string]$StructName = ""
    )

    try {
        # Get content from path if provided
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                throw "Shader file not found: $Path"
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }

        if ([string]::IsNullOrWhiteSpace($Content)) {
            throw "Shader content is empty"
        }

        # Process content
        $processedContent = Remove-ShaderComments -Content $Content
        
        $structs = Get-ShaderStructDefinition -Content $processedContent
        
        if (-not [string]::IsNullOrWhiteSpace($StructName)) {
            $structs = $structs | Where-Object { $_.name -eq $StructName }
        }
        
        Write-Verbose "Extracted $($structs.Count) struct definitions"
        return $structs
    }
    catch {
        Write-Error "Failed to extract shader structs: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Converts Blender shader node Python definitions to a structured manifest.

.DESCRIPTION
    Parses Python code that defines Blender shader node trees and extracts
    node types, connections, and parameters.

.PARAMETER Path
    Path to the Python file containing shader node definitions.

.PARAMETER Content
    Direct Python content string (alternative to Path).

.PARAMETER IncludeRawSource
    If specified, includes the raw source code in the output.

.OUTPUTS
    System.Collections.Hashtable - Structured shader node manifest.

.EXAMPLE
    $manifest = ConvertFrom-BlenderShaderNodes -Path "./materials/procedural_wood.py"
    $manifest | ConvertTo-Json -Depth 10

.EXAMPLE
    $pythonCode = @'
import bpy
def create_material(material):
    material.use_nodes = True
    nodes = material.node_tree.nodes
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.inputs["Base Color"].default_value = (0.8, 0.3, 0.1, 1.0)
'@
    $manifest = ConvertFrom-BlenderShaderNodes -Content $pythonCode
#>
function ConvertFrom-BlenderShaderNodes {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(ParameterSetName = 'Content')]
        [string]$Content,

        [switch]$IncludeRawSource
    )

    try {
        # Get content from path if provided
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                throw "Python file not found: $Path"
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            Write-Verbose "Parsing Blender shader node definitions: $Path"
        }
        else {
            Write-Verbose "Parsing Blender shader node definitions from content"
        }

        if ([string]::IsNullOrWhiteSpace($Content)) {
            throw "Content is empty"
        }

        # Extract nodes.new() calls
        $nodes = @()
        $nodePattern = 'nodes\.new\s*\(\s*["'']?([^"'')]+)["'']?\s*\)'
        $nodeMatches = [regex]::Matches($Content, $nodePattern)
        
        $nodeVariables = @{}  # Track variable assignments
        
        foreach ($match in $nodeMatches) {
            $nodeType = $match.Groups[1].Value
            
            # Try to find the variable name this node is assigned to
            $beforeMatch = $Content.Substring(0, $match.Index)
            $lineStart = $beforeMatch.LastIndexOf("`n") + 1
            $line = $Content.Substring($lineStart, $match.Index - $lineStart)
            
            $varName = $null
            if ($line -match '(\w+)\s*=\s*nodes\.new') {
                $varName = $matches[1]
                $nodeVariables[$varName] = $nodeType
            }
            
            $nodeInfo = @{
                type = $nodeType
                variableName = $varName
                parameters = @()
                inputs = @()
                outputs = @()
                location = $null
            }
            
            # Extract location if available
            if ($varName) {
                $locationPattern = [regex]::Escape($varName) + '\.location\s*=\s*\(\s*([^,]+)\s*,\s*([^)]+)\s*\)'
                $locationMatch = [regex]::Match($Content, $locationPattern)
                if ($locationMatch.Success) {
                    $nodeInfo['location'] = @{
                        x = $locationMatch.Groups[1].Value.Trim()
                        y = $locationMatch.Groups[2].Value.Trim()
                    }
                }
            }
            
            $nodes += $nodeInfo
        }
        
        # Extract input value assignments using a simpler pattern
        $inputMatches = [regex]::Matches($Content, '(\w+)\.inputs\[["'']?([^"'']+)["'']?\]\s*\.\s*(\w+)\s*=\s*([^\n]+)')
        
        foreach ($match in $inputMatches) {
            $varName = $match.Groups[1].Value
            $inputName = $match.Groups[2].Value
            $property = $match.Groups[3].Value
            $value = $match.Groups[4].Value.Trim()
            
            if ($nodeVariables.ContainsKey($varName)) {
                $node = $nodes | Where-Object { $_.variableName -eq $varName } | Select-Object -First 1
                if ($node) {
                    $node['inputs'] += @{
                        name = $inputName
                        property = $property
                        value = $value
                    }
                }
            }
        }
        
        # Extract links/connections
        $links = @()
        $linkPattern1 = 'links\.new\s*\(\s*(\w+)\.outputs\[["'']?([^"'']+)["'']?\]\s*,\s*(\w+)\.inputs\[["'']?([^"'']+)["'']?\]\s*\)'
        $linkPattern2 = 'links\.new\s*\(\s*(\w+)\.inputs\[["'']?([^"'']+)["'']?\]\s*,\s*(\w+)\.outputs\[["'']?([^"'']+)["'']?\]\s*\)'
        
        $linkMatches1 = [regex]::Matches($Content, $linkPattern1)
        foreach ($match in $linkMatches1) {
            $links += @{
                from = @{ node = $match.Groups[1].Value; socket = $match.Groups[2].Value }
                to = @{ node = $match.Groups[3].Value; socket = $match.Groups[4].Value }
            }
        }
        
        $linkMatches2 = [regex]::Matches($Content, $linkPattern2)
        foreach ($match in $linkMatches2) {
            $links += @{
                from = @{ node = $match.Groups[3].Value; socket = $match.Groups[4].Value }
                to = @{ node = $match.Groups[1].Value; socket = $match.Groups[2].Value }
            }
        }
        
        # Extract function definitions
        $functions = @()
        $funcPattern = 'def\s+(\w+)\s*\(\s*([^)]*)\s*\)'
        $funcMatches = [regex]::Matches($Content, $funcPattern)
        foreach ($match in $funcMatches) {
            $functions += @{
                name = $match.Groups[1].Value
                parameters = $match.Groups[2].Value.Trim()
            }
        }
        
        # Build manifest
        $manifest = @{
            fileType = "blender_shader_nodes"
            nodes = $nodes
            links = $links
            functions = $functions
            nodeCount = $nodes.Count
            linkCount = $links.Count
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        # Add source file path if provided
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $manifest['sourcePath'] = (Resolve-Path -LiteralPath $Path).Path
        }
        
        # Include raw source if requested
        if ($IncludeRawSource) {
            $manifest['source'] = $Content
        }
        
        Write-Verbose "Successfully parsed Blender shader nodes: $($nodes.Count) nodes, $($links.Count) links"
        
        return $manifest
    }
    catch {
        Write-Error "Failed to parse Blender shader nodes: $_"
        throw
    }
}

<#
.SYNOPSIS
    Creates a normalized shader manifest from parsed shader data.

.DESCRIPTION
    Takes parsed shader data from any supported format and creates a normalized
    manifest with a consistent schema suitable for cross-platform use.

.PARAMETER InputObject
    The parsed shader data (output from ConvertFrom-GodotShader, ConvertFrom-GLSLShader, or ConvertFrom-BlenderShaderNodes).

.PARAMETER ShaderFormat
    The source format of the shader data.

.PARAMETER OutputPath
    Optional path to save the manifest JSON file.

.PARAMETER IncludeMetadata
    If specified, includes additional metadata in the manifest.

.OUTPUTS
    System.Collections.Hashtable - Normalized shader manifest.

.EXAMPLE
    $godotData = ConvertFrom-GodotShader -Path "./shaders/water.gdshader"
    $manifest = New-ShaderManifest -InputObject $godotData -ShaderFormat godot

.EXAMPLE
    $glslData = ConvertFrom-GLSLShader -Path "./shaders/light.vert"
    $manifest = New-ShaderManifest -InputObject $glslData -ShaderFormat glsl -OutputPath "./manifests/light.json"
#>
function New-ShaderManifest {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$InputObject,

        [Parameter(Mandatory = $true)]
        [ValidateSet('godot', 'glsl', 'blender')]
        [string]$ShaderFormat,

        [string]$OutputPath = "",

        [switch]$IncludeMetadata
    )

    process {
        try {
            Write-Verbose "Creating normalized shader manifest from $ShaderFormat format"
            
            # Base manifest structure
            $manifest = @{
                schemaVersion = "1.0.0"
                manifestType = "shader_definition"
                sourceFormat = $ShaderFormat
                generatedAt = [DateTime]::UtcNow.ToString("o")
                generator = "LLMWorkflow.ShaderParser"
            }
            
            # Add source path if available
            if ($InputObject.ContainsKey('sourcePath')) {
                $manifest['sourcePath'] = $InputObject['sourcePath']
                $manifest['sourceFileName'] = [System.IO.Path]::GetFileName($InputObject['sourcePath'])
            }
            
            # Normalize parameters/uniforms
            $parameters = @()
            if ($InputObject.ContainsKey('uniforms')) {
                foreach ($uniform in $InputObject['uniforms']) {
                    $param = @{
                        name = $uniform['name']
                        type = $uniform['type']
                        semantic = "uniform"
                        defaultValue = if ($uniform.ContainsKey('defaultValue')) { $uniform['defaultValue'] } else { $null }
                        hint = if ($uniform.ContainsKey('hint')) { $uniform['hint'] } else { "" }
                        isArray = if ($uniform.ContainsKey('isArray')) { $uniform['isArray'] } else { $false }
                    }
                    if ($uniform.ContainsKey('arraySize')) {
                        $param['arraySize'] = $uniform['arraySize']
                    }
                    $parameters += $param
                }
            }
            $manifest['parameters'] = $parameters
            
            # Normalize varyings/inputs/outputs
            $varyings = @()
            if ($InputObject.ContainsKey('varyings')) {
                foreach ($varying in $InputObject['varyings']) {
                    $var = @{
                        name = $varying['name']
                        type = $varying['type']
                        direction = if ($varying.ContainsKey('direction')) { $varying['direction'] } else { "varying" }
                    }
                    if ($varying.ContainsKey('isArray')) {
                        $var['isArray'] = $varying['isArray']
                        $var['arraySize'] = $varying['arraySize']
                    }
                    $varyings += $var
                }
            }
            $manifest['varyings'] = $varyings
            
            # Normalize functions
            $functions = @()
            if ($InputObject.ContainsKey('functions')) {
                foreach ($func in $InputObject['functions']) {
                    $function = @{
                        name = $func['name']
                        returnType = $func['returnType']
                        parameters = $func['parameters']
                    }
                    $functions += $function
                }
            }
            $manifest['functions'] = $functions
            
            # Normalize structs
            $structs = @()
            if ($InputObject.ContainsKey('structs')) {
                $structs = $InputObject['structs']
            }
            $manifest['structs'] = $structs
            
            # Normalize preprocessor directives
            $defines = @()
            if ($InputObject.ContainsKey('defines')) {
                $defines = $InputObject['defines']
            }
            $manifest['preprocessor'] = @{
                defines = $defines
            }
            
            # Format-specific properties
            switch ($ShaderFormat) {
                'godot' {
                    $manifest['shaderProfile'] = @{
                        type = $InputObject['shaderType']
                        renderModes = $InputObject['renderMode']
                    }
                }
                'glsl' {
                    $manifest['shaderProfile'] = @{
                        stage = $InputObject['shaderStage']
                        glslVersion = $InputObject['glslVersion']
                        layouts = if ($InputObject.ContainsKey('layouts')) { $InputObject['layouts'] } else { @() }
                    }
                }
                'blender' {
                    $manifest['shaderProfile'] = @{
                        nodeCount = $InputObject['nodeCount']
                        linkCount = $InputObject['linkCount']
                    }
                    $manifest['nodes'] = $InputObject['nodes']
                    $manifest['links'] = $InputObject['links']
                }
            }
            
            # Add metadata if requested
            if ($IncludeMetadata) {
                $vertexFuncs = @($functions | Where-Object { $_.name -eq 'vertex' })
                $fragmentFuncs = @($functions | Where-Object { $_.name -in @('fragment', 'main') })
                
                $manifest['metadata'] = @{
                    parameterCount = if ($parameters) { @($parameters).Count } else { 0 }
                    varyingCount = if ($varyings) { @($varyings).Count } else { 0 }
                    functionCount = if ($functions) { @($functions).Count } else { 0 }
                    structCount = if ($structs) { @($structs).Count } else { 0 }
                    defineCount = if ($defines) { @($defines).Count } else { 0 }
                    hasVertexFunction = $vertexFuncs.Count -gt 0
                    hasFragmentFunction = $fragmentFuncs.Count -gt 0
                }
            }
            
            # Save to file if path provided
            if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
                $outputDir = Split-Path -Parent $OutputPath
                if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
                    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
                }
                $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
                Write-Verbose "Saved manifest to: $OutputPath"
            }
            
            return $manifest
        }
        catch {
            Write-Error "Failed to create shader manifest: $_"
            throw
        }
    }
}

#endregion

#region Batch Processing Functions

<#
.SYNOPSIS
    Parses multiple shader files in a directory.

.DESCRIPTION
    Recursively finds shader files matching specified patterns and parses them
    into structured manifests.

.PARAMETER Path
    Directory path to search for shader files.

.PARAMETER Filter
    File filter pattern(s). Default: @("*.gdshader", "*.glsl", "*.vert", "*.frag", "*.comp")

.PARAMETER Recursive
    If specified, searches subdirectories recursively.

.PARAMETER OutputDirectory
    Optional directory to save individual manifest JSON files.

.OUTPUTS
    System.Collections.Hashtable[] - Array of parsed shader manifests.

.EXAMPLE
    $shaders = Get-ChildShader -Path "./assets/shaders" -Recursive
    $shaders | Export-Csv -Path "./shaders_inventory.csv"

.EXAMPLE
    $shaders = Get-ChildShader -Path "./materials" -Filter "*.gdshader" -OutputDirectory "./manifests"
#>
function Get-ChildShader {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string[]]$Filter = @("*.gdshader", "*.glsl", "*.vert", "*.frag", "*.geom", "*.comp", "*.tesc", "*.tese"),

        [switch]$Recursive,

        [string]$OutputDirectory = ""
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            throw "Directory not found: $Path"
        }

        $results = @()
        
        foreach ($pattern in $Filter) {
            $getChildItemArgs = @{
                LiteralPath = $Path
                Filter = $pattern
            }
            if ($Recursive) {
                $getChildItemArgs['Recurse'] = $true
            }
            $files = Get-ChildItem @getChildItemArgs
            
            foreach ($file in $files) {
                Write-Verbose "Processing: $($file.FullName)"
                
                try {
                    $extension = $file.Extension.ToLower()
                    $parsed = $null
                    
                    switch ($extension) {
                        '.gdshader' {
                            $parsed = ConvertFrom-GodotShader -Path $file.FullName
                        }
                        { $_ -in @('.glsl', '.vert', '.frag', '.geom', '.comp', '.tesc', '.tese') } {
                            $parsed = ConvertFrom-GLSLShader -Path $file.FullName
                        }
                    }
                    
                    if ($parsed) {
                        $result = @{
                            filePath = $file.FullName
                            fileName = $file.Name
                            extension = $extension
                            parsedData = $parsed
                        }
                        
                        # Save individual manifest if output directory specified
                        if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
                            if (-not (Test-Path -LiteralPath $OutputDirectory)) {
                                New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
                            }
                            
                            $manifestName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name) + ".json"
                            $manifestPath = Join-Path $OutputDirectory $manifestName
                            
                            $parsed | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
                            $result['manifestPath'] = $manifestPath
                        }
                        
                        $results += $result
                    }
                }
                catch {
                    Write-Warning "Failed to parse $($file.FullName): $_"
                    $results += @{
                        filePath = $file.FullName
                        fileName = $file.Name
                        extension = $extension
                        error = $_.ToString()
                        parsedData = $null
                    }
                }
            }
        }
        
        Write-Verbose "Processed $($results.Count) shader files"
        return $results
    }
    catch {
        Write-Error "Failed to process shader directory: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Compares two shader manifests and reports differences.

.DESCRIPTION
    Performs a semantic comparison between two shader manifests and identifies
    differences in parameters, functions, and other properties.

.PARAMETER ReferenceManifest
    The reference (baseline) shader manifest.

.PARAMETER DifferenceManifest
    The shader manifest to compare against the reference.

.OUTPUTS
    System.Collections.Hashtable - Comparison results.

.EXAMPLE
    $ref = ConvertFrom-GodotShader -Path "./shaders/v1.gdshader" | New-ShaderManifest -ShaderFormat godot
    $diff = ConvertFrom-GodotShader -Path "./shaders/v2.gdshader" | New-ShaderManifest -ShaderFormat godot
    $comparison = Compare-ShaderManifest -ReferenceManifest $ref -DifferenceManifest $diff
#>
function Compare-ShaderManifest {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ReferenceManifest,

        [Parameter(Mandatory = $true)]
        [hashtable]$DifferenceManifest
    )

    try {
        $comparison = @{
            identical = $true
            differences = @()
            addedParameters = @()
            removedParameters = @()
            modifiedParameters = @()
            addedFunctions = @()
            removedFunctions = @()
        }
        
        # Compare parameters
        $refParams = $ReferenceManifest['parameters'] | ForEach-Object { $_.name }
        $diffParams = $DifferenceManifest['parameters'] | ForEach-Object { $_.name }
        
        $addedParams = $diffParams | Where-Object { $_ -notin $refParams }
        $removedParams = $refParams | Where-Object { $_ -notin $diffParams }
        $commonParams = $refParams | Where-Object { $_ -in $diffParams }
        
        $comparison['addedParameters'] = $addedParams
        $comparison['removedParameters'] = $removedParams
        
        foreach ($paramName in $commonParams) {
            $refParam = $ReferenceManifest['parameters'] | Where-Object { $_.name -eq $paramName } | Select-Object -First 1
            $diffParam = $DifferenceManifest['parameters'] | Where-Object { $_.name -eq $paramName } | Select-Object -First 1
            
            if ($refParam['type'] -ne $diffParam['type'] -or 
                $refParam['defaultValue'] -ne $diffParam['defaultValue']) {
                $comparison['modifiedParameters'] += @{
                    name = $paramName
                    reference = $refParam
                    difference = $diffParam
                }
            }
        }
        
        # Compare functions
        $refFuncs = $ReferenceManifest['functions'] | ForEach-Object { $_.name }
        $diffFuncs = $DifferenceManifest['functions'] | ForEach-Object { $_.name }
        
        $comparison['addedFunctions'] = $diffFuncs | Where-Object { $_ -notin $refFuncs }
        $comparison['removedFunctions'] = $refFuncs | Where-Object { $_ -notin $diffFuncs }
        
        # Determine if manifests are identical
        $comparison['identical'] = (
            $comparison['addedParameters'].Count -eq 0 -and
            $comparison['removedParameters'].Count -eq 0 -and
            $comparison['modifiedParameters'].Count -eq 0 -and
            $comparison['addedFunctions'].Count -eq 0 -and
            $comparison['removedFunctions'].Count -eq 0
        )
        
        return $comparison
    }
    catch {
        Write-Error "Failed to compare shader manifests: $_"
        return $null
    }
}

#endregion

# Export module members (only if loaded as a module)
if ($MyInvocation.InvocationName -ne '.') {
    Export-ModuleMember -Function @(
        # Main parser functions
        'ConvertFrom-GodotShader',
        'ConvertFrom-GLSLShader',
        'ConvertFrom-BlenderShaderNodes',
        
        # Extraction functions
        'Get-ShaderParameters',
        'Get-ShaderFunctions',
        'Get-ShaderVaryings',
        'Get-ShaderStructs',
        
        # Manifest functions
        'New-ShaderManifest',
        
        # Batch processing
        'Get-ChildShader',
        'Compare-ShaderManifest',
        
        # Helper functions (exported for advanced users)
        'Remove-ShaderComments',
        'Optimize-ShaderWhitespace',
        'Get-ShaderPreprocessorDirectives'
    )
}
