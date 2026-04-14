#requires -Version 5.1
<#
.SYNOPSIS
    RPG Maker MZ/MV Plugin Parser for LLM Workflow Phase 4 Structured Extraction Pipeline.

.DESCRIPTION
    Parses RPG Maker MZ/MV plugin .js files to extract structured metadata from JSDoc-style
    comment blocks. This parser implements the complete extraction pipeline for RPG Maker
    plugins including:
    
    - Plugin metadata (@plugindesc, @author, @version, @target, @url)
    - Plugin parameters (@param with @type, @default, @text, @desc, @min, @max, @option)
    - Plugin commands (@command with @arg definitions - MZ style)
    - Legacy plugin commands (@pluginCommand - MV style)
    - Plugin dependencies (@reqPlugin, @reqMV, @reqMZ, @reqVersion)
    - Plugin ordering (@before, @after directives)
    - Conflict detection (@conflict annotations)
    - Struct definitions (@struct declarations)
    - Help text extraction
    
    This parser follows the canonical architecture for Phase 4 Structured Extraction.

.NOTES
    File Name      : RPGMakerPluginParser.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Engine Support : RPG Maker MV, RPG Maker MZ

.EXAMPLE
    # Parse a single plugin file
    $manifest = Invoke-RPGMakerPluginParse -Path "MyPlugin.js"
    
    # Get just the metadata
    $metadata = Get-PluginMetadata -Path "MyPlugin.js"
    
    # Extract specific sections
    $params = Get-PluginParameters -Content $jsContent
    $commands = Get-PluginCommands -Content $jsContent
    $deps = Get-PluginDependencies -Content $jsContent
    
    # Test for conflicts
    $conflicts = Test-PluginConflict -Manifest $manifest -OtherManifests $otherPlugins
#>

Set-StrictMode -Version Latest

#===============================================================================
# Script-level Constants and Patterns
#===============================================================================

$script:Patterns = @{
    # Plugin header block: /*: ... */
    PluginBlock = '(?s)/\*:(.*?)(?:\*/|$)'
    
    # Single annotation line
    Annotation = '^\s*\*?\s*@(\w+)\s*(.*)$'
    
    # Plugin name from title block: // PluginName
    TitleBlock = '^\s*//\s*([\w\s]+)\s*$'
    
    # Alternative title pattern: //=== PluginName ===//
    TitleDecorated = '^\s*//\s*={3,}\s*(.+?)\s*={3,}'
    
    # RPG Maker version indicator in code
    VersionIndicatorMZ = 'Plugins\.\w+\.parameters'
    VersionIndicatorMV = 'PluginManager\.parameters\s*\(\s*["'']'
    
    # Struct definition pattern
    StructDefinition = '@struct\s+(\w+)'
    StructContent = '(?s)@struct\s+\w+\s*(?:\{([^}]+)\}|(.*?)(?=@struct|@param|@command|\*/))'
}

# Parameter type mappings (RPG Maker specific types)
$script:ParameterTypes = @{
    # Basic types
    'string' = 'string'
    'str' = 'string'
    'number' = 'number'
    'num' = 'number'
    'float' = 'number'
    'int' = 'number'
    'integer' = 'number'
    'boolean' = 'boolean'
    'bool' = 'boolean'
    'on/off' = 'boolean'
    'switch' = 'boolean'
    
    # Selection types
    'select' = 'select'
    'combo' = 'select'
    'file' = 'file'
    
    # Database object types (RPG Maker specific)
    'actor' = 'actor'
    'class' = 'class'
    'skill' = 'skill'
    'item' = 'item'
    'weapon' = 'weapon'
    'armor' = 'armor'
    'enemy' = 'enemy'
    'troop' = 'troop'
    'state' = 'state'
    'animation' = 'animation'
    'tileset' = 'tileset'
    'common_event' = 'common_event'
    'commonEvent' = 'common_event'
    'variable' = 'variable'
    'switch_id' = 'switch_id'
    
    # Special types
    'note' = 'note'
    'multiline_string' = 'note'
    'multiline_string[]' = 'note_list'
    'struct' = 'struct'
    'struct[]' = 'struct_list'
    'string[]' = 'string_list'
    'number[]' = 'number_list'
    
    # Audio types
    'audio' = 'audio'
    'audio_bgm' = 'audio_bgm'
    'audio_bgs' = 'audio_bgs'
    'audio_me' = 'audio_me'
    'audio_se' = 'audio_se'
    
    # Animation types
    'mv_animation' = 'mv_animation'
    'effekseer' = 'effekseer'
    
    # Color and icon
    'color' = 'color'
    'icon' = 'icon'
}

#===============================================================================
# Private Helper Functions
#===============================================================================

<#
.SYNOPSIS
    Extracts the JSDoc comment block from plugin file content.

.DESCRIPTION
    Locates and extracts the /*: ... */ comment block that contains
    RPG Maker plugin annotations. Also extracts the plugin name from
    the title block if present.

.PARAMETER Content
    The plugin file content as a string.

.OUTPUTS
    System.Collections.Hashtable with Block and Title properties.
#>
function Get-PluginCommentBlock {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        try {
            $result = @{
                Block = ''
                Title = ''
                RawContent = $Content
            }
            
            # Extract the /*: comment block
            if ($Content -match $script:Patterns.PluginBlock) {
                $result.Block = $matches[1].Trim()
                Write-Verbose "[RPGMakerPluginParser] Found plugin comment block"
            }
            else {
                Write-Verbose "[RPGMakerPluginParser] No RPG Maker-style comment block (/*:) found"
            }
            
            # Try to extract title from //=== PluginName ===// format
            $lines = $Content -split "`r?`n"
            foreach ($line in $lines[0..10]) {
                if ($line -match $script:Patterns.TitleDecorated) {
                    $result.Title = $matches[1].Trim()
                    Write-Verbose "[RPGMakerPluginParser] Found decorated title: $($result.Title)"
                    break
                }
                elseif ($line -match $script:Patterns.TitleBlock -and $line.Trim() -ne '//') {
                    $potentialTitle = $matches[1].Trim()
                    # Filter out separator lines
                    if ($potentialTitle -notmatch '^={3,}$' -and $potentialTitle -notmatch '^-{3,}$') {
                        $result.Title = $potentialTitle
                        Write-Verbose "[RPGMakerPluginParser] Found title: $($result.Title)"
                        break
                    }
                }
            }
            
            return $result
        }
        catch {
            Write-Warning "[RPGMakerPluginParser] Failed to extract comment block: $_"
            return @{ Block = ''; Title = ''; RawContent = $Content }
        }
    }
}

<#
.SYNOPSIS
    Parses annotation lines from comment block content.

.DESCRIPTION
    Extracts all @-prefixed annotations and their values from the
    comment block, returning them as a collection of parsed annotations.

.PARAMETER CommentBlock
    The extracted comment block content.

.OUTPUTS
    System.Array. Collection of annotation objects with Name, Value, and LineNumber properties.
#>
function Get-AnnotationLines {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommentBlock
    )
    
    try {
        $annotations = @()
        $lines = $CommentBlock -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            if ($line -match $script:Patterns.Annotation) {
                $annotations += [PSCustomObject]@{
                    Name = $matches[1].Trim()
                    Value = $matches[2].Trim()
                    RawLine = $line.Trim()
                    LineNumber = $lineNumber
                }
            }
        }
        
        Write-Verbose "[RPGMakerPluginParser] Found $($annotations.Count) annotations"
        return $annotations
    }
    catch {
        Write-Warning "[RPGMakerPluginParser] Failed to parse annotations: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Normalizes a parameter type value.

.DESCRIPTION
    Converts RPG Maker parameter types to standard type names using
    the type mapping dictionary.

.PARAMETER TypeValue
    The raw type string from the plugin.

.OUTPUTS
    System.String. Normalized type name.
#>
function ConvertTo-NormalizedType {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeValue
    )
    
    $normalized = $TypeValue.ToLower().Trim()
    
    # Handle struct<StructName> syntax
    if ($normalized -match '^struct<(.+)>$') {
        return "struct<$($matches[1])>"
    }
    
    # Handle array types
    if ($normalized -match '^(.+)\[\]$') {
        $baseType = $matches[1]
        if ($script:ParameterTypes.ContainsKey($baseType)) {
            return "$($script:ParameterTypes[$baseType])_list"
        }
        return "$baseType`_list"
    }
    
    if ($script:ParameterTypes.ContainsKey($normalized)) {
        return $script:ParameterTypes[$normalized]
    }
    
    return $normalized
}

<#
.SYNOPSIS
    Converts a default value string to appropriate type.

.DESCRIPTION
    Parses the default value based on the parameter type, handling
    type coercion for numbers, booleans, and arrays.

.PARAMETER DefaultValue
    The raw default value string.

.PARAMETER Type
    The normalized type name.

.OUTPUTS
    System.Object. The typed default value.
#>
function ConvertTo-TypedDefault {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [string]$DefaultValue,
        [string]$Type
    )
    
    try {
        if ([string]::IsNullOrWhiteSpace($DefaultValue)) {
            switch -Regex ($Type) {
                'boolean' { return $false }
                'number' { return 0 }
                'string_list|note_list|struct_list' { return @() }
                'number_list' { return @() }
                default { return '' }
            }
        }
        
        switch -Regex ($Type) {
            'boolean' {
                $lower = $DefaultValue.ToLower().Trim()
                return $lower -in @('true', 'on', 'yes', '1')
            }
            'number' {
                if ($DefaultValue -match '^-?\d+$') {
                    return [int]$DefaultValue
                }
                elseif ($DefaultValue -match '^-?\d+\.\d+$') {
                    return [double]$DefaultValue
                }
                return 0
            }
            'string_list|note_list' { 
                return @($DefaultValue -split '\s*,\s*' | Where-Object { $_ -ne '' })
            }
            'number_list' { 
                $parts = $DefaultValue -split '\s*,\s*' | Where-Object { $_ -ne '' }
                return @($parts | ForEach-Object { 
                    if ($_ -match '^-?\d+(\.\d+)?$') { [double]$_ } else { 0 }
                })
            }
            default { return $DefaultValue.Trim() }
        }
    }
    catch {
        Write-Verbose "[RPGMakerPluginParser] Failed to convert default value '$DefaultValue': $_"
        return $DefaultValue
    }
}

<#
.SYNOPSIS
    Extracts help text from the comment block.

.DESCRIPTION
    Parses @help annotations and multi-line help text following
    the @help annotation.

.PARAMETER CommentBlock
    The extracted comment block content.

.OUTPUTS
    System.String. The combined help text.
#>
function Get-HelpText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommentBlock
    )
    
    try {
        $annotations = Get-AnnotationLines -CommentBlock $CommentBlock
        $helpText = ''
        $inHelp = $false
        
        for ($i = 0; $i -lt $annotations.Count; $i++) {
            $ann = $annotations[$i]
            
            if ($ann.Name -eq 'help') {
                $inHelp = $true
                $helpText = $ann.Value
            }
            elseif ($inHelp) {
                # Continue collecting help text until we hit a structured annotation
                if ($ann.Name -in @('param', 'command', 'pluginCommand')) {
                    break
                }
                # Append non-annotation lines as help text
                $helpText += "`n" + $ann.RawLine
            }
        }
        
        # If no @help annotation, look for free text before @param
        if ([string]::IsNullOrWhiteSpace($helpText)) {
            $lines = $CommentBlock -split "`r?`n"
            $freeLines = @()
            foreach ($line in $lines) {
                $trimmed = $line.Trim() -replace '^\*\s?', ''
                if ($trimmed -match '^@(param|command|pluginCommand)') {
                    break
                }
                if ($trimmed -notmatch '^@' -and -not [string]::IsNullOrWhiteSpace($trimmed)) {
                    $freeLines += $trimmed
                }
            }
            $helpText = $freeLines -join "`n"
        }
        
        return $helpText.Trim()
    }
    catch {
        Write-Verbose "[RPGMakerPluginParser] Failed to extract help text: $_"
        return ''
    }
}

<#
.SYNOPSIS
    Detects the target engine version from plugin content.

.DESCRIPTION
    Analyzes the plugin content to determine if it's for MV, MZ, or both.
    Uses @target annotation and code patterns for detection.

.PARAMETER Content
    The plugin file content.

.PARAMETER TargetAnnotation
    The @target annotation value if present.

.OUTPUTS
    System.String. "MZ", "MV", or "Both".
#>
function Get-TargetEngine {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [string]$TargetAnnotation = ''
    )
    
    # Check explicit @target annotation first
    if (-not [string]::IsNullOrWhiteSpace($TargetAnnotation)) {
        $target = $TargetAnnotation.ToUpper().Trim()
        if ($target -in @('MZ', 'MV', 'BOTH')) {
            if ($target -eq 'BOTH') { return 'Both' }
            return $target
        }
    }
    
    # Detect based on code patterns
    $mzScore = 0
    $mvScore = 0
    
    # MZ patterns
    if ($Content -match $script:Patterns.VersionIndicatorMZ) {
        $mzScore += 5
    }
    if ($Content -match 'Graphics\.effekseer') {
        $mzScore += 3
    }
    if ($Content -match 'Window_Options') {
        $mzScore += 2
    }
    
    # MV patterns
    if ($Content -match $script:Patterns.VersionIndicatorMV) {
        $mvScore += 5
    }
    if ($Content -match 'Graphics\._renderer') {
        $mvScore += 2
    }
    
    # Check for explicit version comments
    if ($Content -match '(?i)for\s+MZ|RPG\s*Maker\s*MZ') {
        $mzScore += 3
    }
    if ($Content -match '(?i)for\s+MV|RPG\s*Maker\s*MV') {
        $mvScore += 3
    }
    
    if ($mzScore -gt $mvScore) {
        return 'MZ'
    }
    elseif ($mvScore -gt $mzScore) {
        return 'MV'
    }
    else {
        return 'MZ'  # Default to MZ for ambiguous cases
    }
}

<#
.SYNOPSIS
    Extracts struct definitions from the comment block.

.DESCRIPTION
    Parses @struct annotations and their content to extract
    struct type definitions.

.PARAMETER CommentBlock
    The extracted comment block content.

.OUTPUTS
    System.Array. Array of struct definition hashtables.
#>
function Get-StructDefinitions {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommentBlock
    )
    
    try {
        $structs = @()
        $annotations = Get-AnnotationLines -CommentBlock $CommentBlock
        
        for ($i = 0; $i -lt $annotations.Count; $i++) {
            $ann = $annotations[$i]
            
            if ($ann.Name -eq 'struct') {
                $structName = $ann.Value
                $structFields = @()
                
                # Look ahead for struct field definitions
                for ($j = $i + 1; $j -lt $annotations.Count; $j++) {
                    $fieldAnn = $annotations[$j]
                    
                    # Stop at next top-level annotation
                    if ($fieldAnn.Name -in @('struct', 'param', 'command')) {
                        break
                    }
                    
                    # Parse field definitions
                    switch ($fieldAnn.Name) {
                        'field' {
                            $fieldParts = $fieldAnn.Value -split '\s+'
                            $fieldName = $fieldParts[0]
                            $fieldType = if ($fieldParts.Count -gt 1) { $fieldParts[1] } else { 'string' }
                            
                            $structFields += @{
                                name = $fieldName
                                type = ConvertTo-NormalizedType -TypeValue $fieldType
                            }
                        }
                    }
                }
                
                $structs += @{
                    name = $structName
                    fields = $structFields
                }
            }
        }
        
        return $structs
    }
    catch {
        Write-Verbose "[RPGMakerPluginParser] Failed to extract struct definitions: $_"
        return @()
    }
}

#===============================================================================
# Public API Functions
#===============================================================================

<#
.SYNOPSIS
    Main parser for RPG Maker MZ/MV plugin files.

.DESCRIPTION
    Parses an RPG Maker plugin .js file and returns a complete normalized
    manifest containing all metadata, parameters, commands, dependencies,
    conflicts, and ordering information following the Phase 4 output schema.
    
    This is the primary entry point for plugin parsing in the Structured
    Extraction Pipeline.

.PARAMETER Path
    Path to the plugin .js file to parse.

.PARAMETER Content
    Plugin content as a string (alternative to Path).

.PARAMETER AsJson
    Output the manifest as a JSON string.

.OUTPUTS
    System.Collections.Hashtable or System.String (if -AsJson).

.EXAMPLE
    # Parse a plugin and get the manifest
    $manifest = Invoke-RPGMakerPluginParse -Path "MyPlugin.js"
    
    # Parse and output as JSON
    Invoke-RPGMakerPluginParse -Path "MyPlugin.js" -AsJson | Set-Content "manifest.json"
    
    # Parse multiple plugins
    Get-ChildItem "*.js" | Invoke-RPGMakerPluginParse
#>
function Invoke-RPGMakerPluginParse {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path', Position = 0, ValueFromPipeline = $true)]
        [Alias('FullName')]
        [ValidateScript({ 
            if (-not (Test-Path -LiteralPath $_)) { throw "File not found: $_" }
            return $true
        })]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [switch]$AsJson
    )
    
    begin {
        Write-Verbose "[RPGMakerPluginParser] Starting plugin parse operation"
    }
    
    process {
        try {
            # Load content if path provided
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                Write-Verbose "[RPGMakerPluginParser] Loading file: $Path"
                $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
                $sourceFile = $Path
            }
            else {
                $sourceFile = '<inline>'
            }
            
            if ([string]::IsNullOrWhiteSpace($Content)) {
                Write-Warning "[RPGMakerPluginParser] Empty content"
                return $null
            }
            
            Write-Verbose "[RPGMakerPluginParser] Parsing plugin content ($($Content.Length) chars)"
            
            # Extract comment block and metadata
            $blockResult = Get-PluginCommentBlock -Content $Content
            $commentBlock = $blockResult.Block
            
            if ([string]::IsNullOrWhiteSpace($commentBlock)) {
                Write-Warning "[RPGMakerPluginParser] No plugin comment block found"
                return $null
            }
            
            # Parse all annotations
            $annotations = Get-AnnotationLines -CommentBlock $commentBlock
            
            # Extract metadata
            $metadata = Get-PluginMetadata -Content $Content
            
            # Use title from block if plugin name not found
            if ([string]::IsNullOrEmpty($metadata.pluginName) -and -not [string]::IsNullOrEmpty($blockResult.Title)) {
                $metadata.pluginName = $blockResult.Title
            }
            
            # Extract components
            $parameters = Get-PluginParameters -Content $Content
            $commands = Get-PluginCommands -Content $Content
            $pluginCommands = Get-PluginLegacyCommands -Content $Content
            $dependencies = Get-PluginDependencies -Content $Content
            $conflicts = Get-PluginConflicts -Content $Content
            $order = Get-PluginOrder -Content $Content
            $structs = Get-StructDefinitions -CommentBlock $commentBlock
            $helpText = Get-HelpText -CommentBlock $commentBlock
            
            # Build manifest following the Phase 4 output schema
            $manifest = @{
                pluginName = if ($metadata.pluginName) { $metadata.pluginName } else { 'Unknown' }
                targetEngine = $metadata.targetEngine
                description = $metadata.description
                author = if ($metadata.author) { $metadata.author } else { 'Unknown' }
                url = $metadata.url
                helpText = if ($helpText) { $helpText } else { $metadata.help }
                version = if ($metadata.version) { $metadata.version } else { '1.0.0' }
                parameters = $parameters
                commands = $commands
                pluginCommands = $pluginCommands
                dependencies = $dependencies
                conflicts = $conflicts
                order = $order
                structs = $structs
                sourceFile = $sourceFile
                parsedAt = [DateTime]::UtcNow.ToString("o")
            }
            
            Write-Verbose "[RPGMakerPluginParser] Parse complete: $($manifest.pluginName) v$($manifest.version)"
            
            if ($AsJson) {
                return $manifest | ConvertTo-Json -Depth 10 -Compress:$false
            }
            
            return $manifest
        }
        catch {
            Write-Error "[RPGMakerPluginParser] Failed to parse plugin: $_"
            return $null
        }
    }
    
    end {
        Write-Verbose "[RPGMakerPluginParser] Parse operation complete"
    }
}

<#
.SYNOPSIS
    Extracts plugin metadata from RPG Maker plugin content.

.DESCRIPTION
    Parses the plugin header to extract basic metadata including
    name, author, version, target engine, URL, and description.

.PARAMETER Path
    Path to the plugin .js file.

.PARAMETER Content
    Plugin content as a string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Plugin metadata object with properties:
    - pluginName: The plugin name
    - description: Plugin description
    - author: Plugin author
    - version: Plugin version
    - targetEngine: Target engine (MZ, MV, or Both)
    - url: Plugin URL
    - help: Help text

.EXAMPLE
    Get-PluginMetadata -Path "MyPlugin.js"

.EXAMPLE
    $content = Get-Content "MyPlugin.js" -Raw
    Get-PluginMetadata -Content $content
#>
function Get-PluginMetadata {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([hashtable])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true, Position = 0)]
        [ValidateScript({ 
            if (-not (Test-Path -LiteralPath $_)) { throw "File not found: $_" }
            return $true
        })]
        [string]$Path,

        [Parameter(ParameterSetName = 'Content', Mandatory = $true)]
        [string]$Content
    )

    try {
        Write-Verbose "[RPGMakerPluginParser] Extracting plugin metadata..."

        # Get content from file if needed
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }

        # Extract comment block
        $blockResult = Get-PluginCommentBlock -Content $Content
        $commentBlock = $blockResult.Block
        
        if ([string]::IsNullOrWhiteSpace($commentBlock)) {
            Write-Warning "[RPGMakerPluginParser] No plugin comment block found"
            return @{
                pluginName = $blockResult.Title
                description = ''
                author = ''
                version = $null
                targetEngine = 'MZ'
                url = $null
                help = ''
            }
        }

        # Parse annotations
        $annotations = Get-AnnotationLines -CommentBlock $commentBlock

        # Build metadata
        $metadata = @{
            pluginName = ''
            description = ''
            author = ''
            version = $null
            targetEngine = 'MZ'
            url = $null
            help = ''
        }

        $targetAnnotation = ''
        
        # Extract known annotations
        foreach ($ann in $annotations) {
            switch ($ann.Name.ToLower()) {
                'plugindesc' { $metadata.pluginName = $ann.Value }
                'plugindescription' { $metadata.pluginName = $ann.Value }
                'author' { $metadata.author = $ann.Value }
                'version' { $metadata.version = $ann.Value }
                'target' { $targetAnnotation = $ann.Value }
                'url' { $metadata.url = $ann.Value }
                'website' { $metadata.url = $ann.Value }
                'help' { 
                    if ([string]::IsNullOrEmpty($metadata.help)) {
                        $metadata.help = $ann.Value
                    } else {
                        $metadata.help += "`n" + $ann.Value
                    }
                }
            }
        }
        
        # Detect target engine
        $metadata.targetEngine = Get-TargetEngine -Content $Content -TargetAnnotation $targetAnnotation

        # Use plugin name as description if no explicit description
        if ([string]::IsNullOrEmpty($metadata.description)) {
            $metadata.description = $metadata.pluginName
        }
        
        # Use title from block if plugin name not found
        if ([string]::IsNullOrEmpty($metadata.pluginName) -and -not [string]::IsNullOrEmpty($blockResult.Title)) {
            $metadata.pluginName = $blockResult.Title
        }

        Write-Verbose "[RPGMakerPluginParser] Metadata extracted: $($metadata.pluginName) by $($metadata.author)"
        return $metadata
    }
    catch {
        Write-Error "[RPGMakerPluginParser] Failed to extract plugin metadata: $_"
        return @{
            pluginName = 'Unknown'
            description = ''
            author = ''
            version = $null
            targetEngine = 'MZ'
            url = $null
            help = ''
        }
    }
}

<#
.SYNOPSIS
    Extracts plugin parameters from RPG Maker plugin content.

.DESCRIPTION
    Parses @param annotations and associated metadata (@type, @default,
    @text, @desc, @description, @min, @max, @parent, @option) to build 
    parameter definitions following the Phase 4 schema.

.PARAMETER Path
    Path to the plugin .js file.

.PARAMETER Content
    Plugin content as a string (alternative to Path).

.OUTPUTS
    System.Array. Array of parameter definition hashtables with properties:
    - name: Parameter internal name
    - displayName: Human-readable name (from @text)
    - description: Parameter description (from @desc)
    - type: Parameter type
    - default: Default value (typed)
    - min: Minimum value for numbers
    - max: Maximum value for numbers
    - options: Array of options for select types

.EXAMPLE
    Get-PluginParameters -Path "MyPlugin.js"

.EXAMPLE
    $content = Get-Content "MyPlugin.js" -Raw
    Get-PluginParameters -Content $content
#>
function Get-PluginParameters {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true, Position = 0)]
        [ValidateScript({ 
            if (-not (Test-Path -LiteralPath $_)) { throw "File not found: $_" }
            return $true
        })]
        [string]$Path,

        [Parameter(ParameterSetName = 'Content', Mandatory = $true)]
        [string]$Content
    )

    try {
        Write-Verbose "[RPGMakerPluginParser] Extracting plugin parameters..."

        # Get content from file if needed
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }

        # Extract comment block
        $blockResult = Get-PluginCommentBlock -Content $Content
        $commentBlock = $blockResult.Block
        
        if ([string]::IsNullOrWhiteSpace($commentBlock)) {
            return @()
        }

        # Parse annotations
        $annotations = Get-AnnotationLines -CommentBlock $commentBlock
        $parameters = @()
        $currentParam = $null

        for ($i = 0; $i -lt $annotations.Count; $i++) {
            $ann = $annotations[$i]
            $annName = $ann.Name.ToLower()

            # Stop when we hit command section
            if ($annName -eq 'command') {
                if ($null -ne $currentParam) {
                    $parameters += $currentParam
                    $currentParam = $null
                }
                break
            }

            switch ($annName) {
                'param' {
                    # Save previous parameter if exists
                    if ($null -ne $currentParam) {
                        $parameters += $currentParam
                    }
                    # Start new parameter - map to output schema
                    $currentParam = @{
                        name = $ann.Value
                        displayName = $ann.Value
                        description = ''
                        type = 'string'
                        default = ''
                        min = $null
                        max = $null
                        options = @()
                    }
                }
                'text' {
                    if ($null -ne $currentParam) {
                        $currentParam.displayName = $ann.Value
                    }
                }
                'desc' {
                    if ($null -ne $currentParam) {
                        $currentParam.description = $ann.Value
                    }
                }
                'description' {
                    if ($null -ne $currentParam) {
                        $currentParam.description = $ann.Value
                    }
                }
                'type' {
                    if ($null -ne $currentParam) {
                        $currentParam.type = ConvertTo-NormalizedType -TypeValue $ann.Value
                    }
                }
                'default' {
                    if ($null -ne $currentParam) {
                        $currentParam.default = $ann.Value
                    }
                }
                'min' {
                    if ($null -ne $currentParam -and $ann.Value -match '^-?\d+(\.\d+)?$') {
                        $currentParam.min = [double]$ann.Value
                    }
                }
                'max' {
                    if ($null -ne $currentParam -and $ann.Value -match '^-?\d+(\.\d+)?$') {
                        $currentParam.max = [double]$ann.Value
                    }
                }
                'option' {
                    if ($null -ne $currentParam) {
                        $currentParam.options += $ann.Value
                    }
                }
            }
        }

        # Save last parameter
        if ($null -ne $currentParam) {
            $parameters += $currentParam
        }

        # Post-process: convert default values to appropriate types
        foreach ($param in $parameters) {
            $param.default = ConvertTo-TypedDefault -DefaultValue $param.default -Type $param.type
        }

        Write-Verbose "[RPGMakerPluginParser] Found $($parameters.Count) parameters"
        return $parameters
    }
    catch {
        Write-Error "[RPGMakerPluginParser] Failed to extract plugin parameters: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts plugin commands from RPG Maker plugin content.

.DESCRIPTION
    Parses @command annotations (MZ style) and associated arguments 
    (@arg with @type, @default, @text, @desc) to build command definitions.

.PARAMETER Path
    Path to the plugin .js file.

.PARAMETER Content
    Plugin content as a string (alternative to Path).

.OUTPUTS
    System.Array. Array of command definition hashtables with properties:
    - name: Command internal name
    - displayName: Human-readable name (from @text)
    - description: Command description
    - args: Array of argument definitions

.EXAMPLE
    Get-PluginCommands -Path "MyPlugin.js"

.EXAMPLE
    $content = Get-Content "MyPlugin.js" -Raw
    Get-PluginCommands -Content $content
#>
function Get-PluginCommands {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true, Position = 0)]
        [ValidateScript({ 
            if (-not (Test-Path -LiteralPath $_)) { throw "File not found: $_" }
            return $true
        })]
        [string]$Path,

        [Parameter(ParameterSetName = 'Content', Mandatory = $true)]
        [string]$Content
    )

    try {
        Write-Verbose "[RPGMakerPluginParser] Extracting plugin commands (MZ style)..."

        # Get content from file if needed
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }

        # Extract comment block
        $blockResult = Get-PluginCommentBlock -Content $Content
        $commentBlock = $blockResult.Block
        
        if ([string]::IsNullOrWhiteSpace($commentBlock)) {
            return @()
        }

        # Parse annotations
        $annotations = Get-AnnotationLines -CommentBlock $commentBlock
        $commands = @()
        $currentCommand = $null
        $currentArg = $null

        for ($i = 0; $i -lt $annotations.Count; $i++) {
            $ann = $annotations[$i]
            $annName = $ann.Name.ToLower()

            switch ($annName) {
                'command' {
                    # Save previous command if exists
                    if ($null -ne $currentCommand) {
                        # Save last arg if exists
                        if ($null -ne $currentArg) {
                            $currentCommand.args += $currentArg
                        }
                        $commands += $currentCommand
                    }
                    # Start new command - map to output schema
                    $currentCommand = @{
                        name = $ann.Value
                        displayName = $ann.Value
                        description = ''
                        args = @()
                    }
                    $currentArg = $null
                }
                'text' {
                    if ($null -ne $currentCommand) {
                        $currentCommand.displayName = $ann.Value
                    }
                }
                'desc' {
                    if ($null -ne $currentArg) {
                        $currentArg.description = $ann.Value
                    }
                    elseif ($null -ne $currentCommand) {
                        $currentCommand.description = $ann.Value
                    }
                }
                'description' {
                    if ($null -ne $currentArg) {
                        $currentArg.description = $ann.Value
                    }
                    elseif ($null -ne $currentCommand) {
                        $currentCommand.description = $ann.Value
                    }
                }
                'arg' {
                    # Save previous arg if exists
                    if ($null -ne $currentArg) {
                        $currentCommand.args += $currentArg
                    }
                    # Start new argument - map to output schema
                    $currentArg = @{
                        name = $ann.Value
                        type = 'string'
                        default = ''
                    }
                }
                'type' {
                    if ($null -ne $currentArg) {
                        $currentArg.type = ConvertTo-NormalizedType -TypeValue $ann.Value
                    }
                }
                'default' {
                    if ($null -ne $currentArg) {
                        $currentArg.default = $ann.Value
                    }
                }
            }
        }

        # Save last command
        if ($null -ne $currentCommand) {
            if ($null -ne $currentArg) {
                $currentCommand.args += $currentArg
            }
            $commands += $currentCommand
        }

        # Post-process: convert default values to appropriate types
        foreach ($cmd in $commands) {
            foreach ($arg in $cmd.args) {
                $arg.default = ConvertTo-TypedDefault -DefaultValue $arg.default -Type $arg.type
            }
        }

        Write-Verbose "[RPGMakerPluginParser] Found $($commands.Count) commands"
        return $commands
    }
    catch {
        Write-Error "[RPGMakerPluginParser] Failed to extract plugin commands: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts legacy MV-style plugin commands.

.DESCRIPTION
    Parses @pluginCommand annotations for RPG Maker MV style commands.
    These are simpler commands with space-separated arguments.

.PARAMETER Path
    Path to the plugin .js file.

.PARAMETER Content
    Plugin content as a string (alternative to Path).

.OUTPUTS
    System.Array. Array of legacy command hashtables with properties:
    - command: The command string
    - args: Array of argument names

.EXAMPLE
    Get-PluginLegacyCommands -Path "MyPlugin.js"
#>
function Get-PluginLegacyCommands {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true, Position = 0)]
        [ValidateScript({ 
            if (-not (Test-Path -LiteralPath $_)) { throw "File not found: $_" }
            return $true
        })]
        [string]$Path,

        [Parameter(ParameterSetName = 'Content', Mandatory = $true)]
        [string]$Content
    )

    try {
        Write-Verbose "[RPGMakerPluginParser] Extracting legacy plugin commands (MV style)..."

        # Get content from file if needed
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }

        # Extract comment block
        $blockResult = Get-PluginCommentBlock -Content $Content
        $commentBlock = $blockResult.Block
        
        if ([string]::IsNullOrWhiteSpace($commentBlock)) {
            return @()
        }

        # Parse annotations
        $annotations = Get-AnnotationLines -CommentBlock $commentBlock
        $pluginCommands = @()

        foreach ($ann in $annotations) {
            if ($ann.Name -eq 'pluginCommand') {
                # Parse MV-style command: @pluginCommand CommandName arg1 arg2
                $parts = $ann.Value -split '\s+'
                if ($parts.Count -gt 0) {
                    $pluginCommands += @{
                        command = $parts[0]
                        args = $parts[1..($parts.Count - 1)]
                    }
                }
            }
        }

        Write-Verbose "[RPGMakerPluginParser] Found $($pluginCommands.Count) legacy plugin commands"
        # Ensure array return
        if ($pluginCommands -isnot [array]) { $pluginCommands = @($pluginCommands) }
        return ,$pluginCommands
    }
    catch {
        Write-Error "[RPGMakerPluginParser] Failed to extract legacy plugin commands: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts plugin dependencies from RPG Maker plugin content.

.DESCRIPTION
    Parses @reqPlugin, @reqMV, @reqMZ, @reqVersion, @require annotations
    to identify plugin dependencies and version requirements.

.PARAMETER Path
    Path to the plugin .js file.

.PARAMETER Content
    Plugin content as a string (alternative to Path).

.OUTPUTS
    System.Array. Array of dependency definition strings (plugin names).

.EXAMPLE
    Get-PluginDependencies -Path "MyPlugin.js"

.EXAMPLE
    $content = Get-Content "MyPlugin.js" -Raw
    Get-PluginDependencies -Content $content
#>
function Get-PluginDependencies {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true, Position = 0)]
        [ValidateScript({ 
            if (-not (Test-Path -LiteralPath $_)) { throw "File not found: $_" }
            return $true
        })]
        [string]$Path,

        [Parameter(ParameterSetName = 'Content', Mandatory = $true)]
        [string]$Content
    )

    try {
        Write-Verbose "[RPGMakerPluginParser] Extracting plugin dependencies..."

        # Get content from file if needed
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }

        # Extract comment block
        $blockResult = Get-PluginCommentBlock -Content $Content
        $commentBlock = $blockResult.Block
        
        if ([string]::IsNullOrWhiteSpace($commentBlock)) {
            return @()
        }

        # Parse annotations
        $annotations = Get-AnnotationLines -CommentBlock $commentBlock
        $dependencies = @()

        foreach ($ann in $annotations) {
            $annName = $ann.Name.ToLower()
            
            switch ($annName) {
                'reqplugin' { $dependencies += $ann.Value }
                'requires' { $dependencies += $ann.Value }
                'require' { $dependencies += $ann.Value }
                'base' { $dependencies += $ann.Value }
            }
        }

        # Remove duplicates while preserving order
        $dependencies = $dependencies | Select-Object -Unique
        
        # Ensure array return (handle single item case)
        if ($dependencies -isnot [array]) {
            $dependencies = @($dependencies)
        }

        Write-Verbose "[RPGMakerPluginParser] Found $($dependencies.Count) dependencies"
        return ,$dependencies
    }
    catch {
        Write-Error "[RPGMakerPluginParser] Failed to extract plugin dependencies: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts plugin conflicts from RPG Maker plugin content.

.DESCRIPTION
    Parses @conflict annotations to identify plugins that conflict
    with this plugin.

.PARAMETER Path
    Path to the plugin .js file.

.PARAMETER Content
    Plugin content as a string (alternative to Path).

.OUTPUTS
    System.Array. Array of conflicting plugin names.

.EXAMPLE
    Get-PluginConflicts -Path "MyPlugin.js"
#>
function Get-PluginConflicts {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true, Position = 0)]
        [ValidateScript({ 
            if (-not (Test-Path -LiteralPath $_)) { throw "File not found: $_" }
            return $true
        })]
        [string]$Path,

        [Parameter(ParameterSetName = 'Content', Mandatory = $true)]
        [string]$Content
    )

    try {
        Write-Verbose "[RPGMakerPluginParser] Extracting plugin conflicts..."

        # Get content from file if needed
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }

        # Extract comment block
        $blockResult = Get-PluginCommentBlock -Content $Content
        $commentBlock = $blockResult.Block
        
        if ([string]::IsNullOrWhiteSpace($commentBlock)) {
            return @()
        }

        # Parse annotations
        $annotations = Get-AnnotationLines -CommentBlock $commentBlock
        $conflicts = @()

        foreach ($ann in $annotations) {
            if ($ann.Name -eq 'conflict') {
                $conflicts += $ann.Value
            }
        }

        Write-Verbose "[RPGMakerPluginParser] Found $($conflicts.Count) conflicts"
        # Ensure array return
        if ($conflicts -isnot [array]) { $conflicts = @($conflicts) }
        return ,$conflicts
    }
    catch {
        Write-Error "[RPGMakerPluginParser] Failed to extract plugin conflicts: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts plugin load order information.

.DESCRIPTION
    Parses @before and @after annotations to determine plugin
    load ordering requirements.

.PARAMETER Path
    Path to the plugin .js file.

.PARAMETER Content
    Plugin content as a string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable with 'before' and 'after' arrays.

.EXAMPLE
    Get-PluginOrder -Path "MyPlugin.js"
#>
function Get-PluginOrder {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([hashtable])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true, Position = 0)]
        [ValidateScript({ 
            if (-not (Test-Path -LiteralPath $_)) { throw "File not found: $_" }
            return $true
        })]
        [string]$Path,

        [Parameter(ParameterSetName = 'Content', Mandatory = $true)]
        [string]$Content
    )

    try {
        Write-Verbose "[RPGMakerPluginParser] Extracting plugin load order..."

        # Get content from file if needed
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }

        # Extract comment block
        $blockResult = Get-PluginCommentBlock -Content $Content
        $commentBlock = $blockResult.Block
        
        $order = @{
            before = @()
            after = @()
        }
        
        if ([string]::IsNullOrWhiteSpace($commentBlock)) {
            return $order
        }

        # Parse annotations
        $annotations = Get-AnnotationLines -CommentBlock $commentBlock

        foreach ($ann in $annotations) {
            $annName = $ann.Name.ToLower()
            
            switch ($annName) {
                'before' { $order.before += $ann.Value }
                'after' { $order.after += $ann.Value }
                'order' {
                    # Parse @order After:PluginName or @order Before:PluginName format
                    if ($ann.Value -match '(?i)after:\s*(\w+)') {
                        $order.after += $matches[1]
                    }
                    if ($ann.Value -match '(?i)before:\s*(\w+)') {
                        $order.before += $matches[1]
                    }
                }
            }
        }
        
        # Remove duplicates and ensure arrays
        $order.before = $order.before | Select-Object -Unique
        $order.after = $order.after | Select-Object -Unique
        
        # Ensure array return for single item case
        if ($order.before -isnot [array]) { $order.before = @($order.before) }
        if ($order.after -isnot [array]) { $order.after = @($order.after) }

        Write-Verbose "[RPGMakerPluginParser] Found order: before=$($order.before.Count), after=$($order.after.Count)"
        return $order
    }
    catch {
        Write-Error "[RPGMakerPluginParser] Failed to extract plugin order: $_"
        return @{
            before = @()
            after = @()
        }
    }
}

<#
.SYNOPSIS
    Tests for potential plugin conflicts.

.DESCRIPTION
    Checks if a plugin manifest has conflicts with a list of other
    plugin manifests. Returns conflict information if found.

.PARAMETER Manifest
    The primary plugin manifest to check.

.PARAMETER OtherManifests
    Array of other plugin manifests to check against.

.OUTPUTS
    System.Array. Array of conflict information hashtables with properties:
    - plugin: The conflicting plugin name
    - conflictType: Type of conflict (explicit, dependency, order)
    - description: Description of the conflict

.EXAMPLE
    $conflicts = Test-PluginConflict -Manifest $plugin -OtherManifests $otherPlugins
#>
function Test-PluginConflict {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Manifest,
        
        [Parameter(Mandatory = $true)]
        [array]$OtherManifests
    )
    
    try {
        Write-Verbose "[RPGMakerPluginParser] Testing for conflicts with $($Manifest.pluginName)..."
        
        $conflictsFound = @()
        
        foreach ($other in $OtherManifests) {
            if ($other.pluginName -eq $Manifest.pluginName) {
                continue
            }
            
            # Check explicit conflicts
            if ($Manifest.conflicts -contains $other.pluginName) {
                $conflictsFound += @{
                    plugin = $other.pluginName
                    conflictType = 'explicit'
                    description = "$($Manifest.pluginName) explicitly conflicts with $($other.pluginName)"
                }
            }
            
            # Check reverse conflicts (other plugin conflicts with this one)
            if ($other.conflicts -contains $Manifest.pluginName) {
                $conflictsFound += @{
                    plugin = $other.pluginName
                    conflictType = 'explicit'
                    description = "$($other.pluginName) explicitly conflicts with $($Manifest.pluginName)"
                }
            }
            
            # Check for order conflicts (this plugin must be before another that must be before this)
            if ($Manifest.order.before -contains $other.pluginName -and 
                $other.order.before -contains $Manifest.pluginName) {
                $conflictsFound += @{
                    plugin = $other.pluginName
                    conflictType = 'order'
                    description = "Circular load order: $($Manifest.pluginName) must be before $($other.pluginName) and vice versa"
                }
            }
            
            if ($Manifest.order.after -contains $other.pluginName -and 
                $other.order.after -contains $Manifest.pluginName) {
                $conflictsFound += @{
                    plugin = $other.pluginName
                    conflictType = 'order'
                    description = "Circular load order: $($Manifest.pluginName) must be after $($other.pluginName) and vice versa"
                }
            }
        }
        
        Write-Verbose "[RPGMakerPluginParser] Found $($conflictsFound.Count) conflicts"
        return $conflictsFound
    }
    catch {
        Write-Error "[RPGMakerPluginParser] Failed to test for conflicts: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Tests if a file is a valid RPG Maker plugin.

.DESCRIPTION
    Validates that a .js file contains RPG Maker plugin annotations
    and can be parsed by this module.

.PARAMETER Path
    Path to the file to test.

.OUTPUTS
    System.Boolean. True if the file is a valid RPG Maker plugin.

.EXAMPLE
    Test-RPGMakerPlugin -Path "MyPlugin.js"

.EXAMPLE
    Get-ChildItem "*.js" | Where-Object { Test-RPGMakerPlugin -Path $_.FullName }
#>
function Test-RPGMakerPlugin {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [Alias('FullName')]
        [string]$Path
    )

    process {
        try {
            if (-not (Test-Path -LiteralPath $Path)) {
                return $false
            }

            $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop
            
            # Check for RPG Maker plugin markers
            $hasPluginBlock = $content -match '/\*:'
            $hasPluginDesc = $content -match '@plugindesc'
            $hasTarget = $content -match '@target\s+(MZ|MV)'
            $hasRPGMakerCode = $content -match 'PluginManager\.parameters|Plugins\.\w+\.parameters'
            
            return ($hasPluginBlock -and ($hasPluginDesc -or $hasTarget)) -or $hasRPGMakerCode
        }
        catch {
            Write-Verbose "[RPGMakerPluginParser] Error testing file '$Path': $_"
            return $false
        }
    }
}

<#
.SYNOPSIS
    Exports plugin manifest to JSON file.

.DESCRIPTION
    Parses a plugin and saves the normalized manifest to a JSON file.

.PARAMETER Path
    Path to the plugin .js file.

.PARAMETER OutputPath
    Path for the output JSON file (defaults to .json extension of input).

.PARAMETER Force
    Overwrite existing output file.

.EXAMPLE
    Export-RPGMakerPluginManifest -Path "MyPlugin.js"

.EXAMPLE
    Export-RPGMakerPluginManifest -Path "MyPlugin.js" -OutputPath "output/manifest.json" -Force
#>
function Export-RPGMakerPluginManifest {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ 
            if (-not (Test-Path -LiteralPath $_)) { throw "File not found: $_" }
            return $true
        })]
        [string]$Path,

        [Parameter(Position = 1)]
        [string]$OutputPath = '',

        [switch]$Force
    )

    try {
        # Generate default output path if not specified
        if ([string]::IsNullOrEmpty($OutputPath)) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
            $dir = [System.IO.Path]::GetDirectoryName($Path)
            $OutputPath = Join-Path $dir "$baseName.json"
        }

        # Check for existing file
        if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
            Write-Warning "[RPGMakerPluginParser] Output file exists. Use -Force to overwrite: $OutputPath"
            return
        }

        if ($PSCmdlet.ShouldProcess($OutputPath, 'Export plugin manifest')) {
            # Parse and export
            $manifest = Invoke-RPGMakerPluginParse -Path $Path
            if ($null -eq $manifest) {
                Write-Error "[RPGMakerPluginParser] Failed to parse plugin: $Path"
                return
            }

            $json = $manifest | ConvertTo-Json -Depth 10 -Compress:$false
            
            # Ensure output directory exists
            $outputDir = [System.IO.Path]::GetDirectoryName($OutputPath)
            if (-not [string]::IsNullOrEmpty($outputDir) -and -not (Test-Path $outputDir)) {
                New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
            }
            
            $json | Set-Content -LiteralPath $OutputPath -Encoding UTF8 -Force:$Force

            Write-Verbose "[RPGMakerPluginParser] Exported manifest to: $OutputPath"
            
            [PSCustomObject]@{
                Success = $true
                SourcePath = $Path
                OutputPath = $OutputPath
                PluginName = $manifest.pluginName
                Version = $manifest.version
            }
        }
    }
    catch {
        Write-Error "[RPGMakerPluginParser] Failed to export manifest: $_"
        [PSCustomObject]@{
            Success = $false
            Error = $_.ToString()
        }
    }
}

#===============================================================================
# Module Exports
#===============================================================================

if ($MyInvocation.InvocationName -ne ".") { Export-ModuleMember -Function @(
    'Invoke-RPGMakerPluginParse',
    'Get-PluginMetadata',
    'Get-PluginParameters',
    'Get-PluginCommands',
    'Get-PluginDependencies',
    'Get-PluginConflicts',
    'Get-PluginOrder',
    'Test-PluginConflict',
    'Test-RPGMakerPlugin',
    'Export-RPGMakerPluginManifest',
    'ConvertTo-NormalizedType',
    'ConvertTo-TypedDefault'
)

}

