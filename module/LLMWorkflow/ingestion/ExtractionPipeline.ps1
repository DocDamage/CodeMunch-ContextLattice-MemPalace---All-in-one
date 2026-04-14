#requires -Version 5.1
<#
.SYNOPSIS
    Main Extraction Pipeline orchestrator for LLM Workflow Phase 4 Structured Extraction.

.DESCRIPTION
    This module provides a unified interface to extract structured data from all supported
    file types across the RPG Maker MZ, Godot Engine, and Blender Engine packs.
    
    It coordinates domain-specific parsers and produces normalized output envelopes
    following the Phase 4 extraction schema.

    Supported File Types:
    - Godot Engine: .gd (GDScript), .tscn (Scene), .tres (Resource), .gdshader/.shader (Shader)
    - RPG Maker MZ: .js (Plugins)
    - Blender Engine: .py (Python scripts/addons), .blend (indirect via scripts)
    - Unreal Engine: .uplugin (Plugin descriptors), .uproject (Project descriptors)

    The pipeline implements:
    - Automatic file type detection based on extension and content
    - Routing to appropriate domain-specific parsers
    - Normalized envelope wrapping of parser output
    - Progress tracking for batch operations
    - Comprehensive error handling and reporting

.NOTES
    File Name      : ExtractionPipeline.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    
    Canonical Doc  : LLMWorkflow_Canonical_Document_Set_Part_3_Godot_Blender_InterPack_and_Roadmap.md
                     Section 25.15 (Structured Extraction Pipeline)

.EXAMPLE
    # Single file extraction
    $result = Invoke-StructuredExtraction -FilePath "player.gd" -PackType "godot-engine"
    
    # Batch extraction with progress
    Invoke-BatchExtraction -FilePaths (Get-ChildItem *.gd -Recurse) -OutputDirectory "./extracted"
    
    # Check if file type is supported
    if (Test-ExtractionSupported -FilePath "unknown.xyz") {
        # Process file
    }
    
    # Get extraction schema for a type
    $schema = Get-ExtractionSchema -Type "gdscript"
    
    # Generate extraction report
    Export-ExtractionReport -Results $batchResults -OutputPath "./report.json"
#>

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Generates a new correlation ID for request tracing.
#>
function New-CorrelationId {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return [Guid]::NewGuid().ToString()
}

# ============================================================================
# Module Constants and Configuration
# ============================================================================

$script:ModuleVersion = '1.0.0'
$script:ModuleName = 'ExtractionPipeline'

# File extension to parser mapping
$script:ExtensionMapping = @{
    # Godot Engine
    '.gd'       = @{ Parser = 'GDScript'; Function = 'Invoke-GDScriptParse'; PackType = 'godot-engine'; FileType = 'gdscript' }
    '.tscn'     = @{ Parser = 'GodotScene'; Function = 'Invoke-GodotSceneParse'; PackType = 'godot-engine'; FileType = 'godot-scene' }
    '.tres'     = @{ Parser = 'GodotResource'; Function = 'Invoke-GodotResourceParse'; PackType = 'godot-engine'; FileType = 'godot-resource' }
    '.gdshader' = @{ Parser = 'Shader'; Function = 'ConvertFrom-GodotShader'; PackType = 'godot-engine'; FileType = 'gdshader' }
    '.shader'   = @{ Parser = 'Shader'; Function = 'ConvertFrom-GodotShader'; PackType = 'godot-engine'; FileType = 'gdshader' }
    
    # RPG Maker MZ
    '.js'       = @{ Parser = 'RPGMakerPlugin'; Function = 'Invoke-RPGMakerPluginParse'; PackType = 'rpgmaker-mz'; FileType = 'rpgmaker-plugin' }
    
    # Blender Engine
    '.py'       = @{ Parser = 'BlenderPython'; Function = 'Invoke-BlenderPythonParse'; PackType = 'blender-engine'; FileType = 'blender-python' }
    '.blend'    = @{ Parser = 'GeometryNodes'; Function = 'Invoke-GeometryNodesParse'; PackType = 'blender-engine'; FileType = 'geometry-nodes' }

    # Unreal Engine
    '.uplugin'  = @{ Parser = 'UnrealDescriptor'; Function = 'Invoke-UnrealDescriptorParse'; PackType = 'unreal-engine'; FileType = 'unreal-plugin' }
    '.uproject' = @{ Parser = 'UnrealDescriptor'; Function = 'Invoke-UnrealDescriptorParse'; PackType = 'unreal-engine'; FileType = 'unreal-project' }
}

# Schema definitions for each extraction type
$script:SchemaDefinitions = @{
    'gdscript' = @{
        type = 'object'
        description = 'GDScript file extraction containing class metadata, signals, properties, methods, and annotations'
        requiredProperties = @('fileType', 'filePath', 'engineTarget', 'className', 'extends', 'elements', 'elementCounts')
        properties = @{
            fileType = @{ type = 'string'; enum = @('gdscript') }
            filePath = @{ type = 'string' }
            engineTarget = @{ type = 'string'; enum = @('4.x', '3.x', 'Unknown') }
            className = @{ type = 'string' }
            extends = @{ type = 'string' }
            isTool = @{ type = 'boolean' }
            icon = @{ type = 'string' }
            elements = @{ 
                type = 'array'
                items = @{
                    type = 'object'
                    properties = @{
                        elementType = @{ type = 'string'; enum = @('class', 'signal', 'property', 'method', 'annotation', 'enum') }
                        name = @{ type = 'string' }
                        lineNumber = @{ type = 'integer' }
                        extends = @{ type = 'string' }
                        className = @{ type = 'string' }
                        parameters = @{ type = 'array' }
                        returnType = @{ type = 'string' }
                        annotations = @{ type = 'array' }
                        docComment = @{ type = 'string' }
                        sourceFile = @{ type = 'string' }
                    }
                }
            }
            elementCounts = @{ type = 'object' }
            provenance = @{ type = 'object' }
            license = @{ type = 'string' }
            parsedAt = @{ type = 'string'; format = 'date-time' }
        }
    }
    
    'godot-scene' = @{
        type = 'object'
        description = 'Godot scene (.tscn) or resource (.tres) file extraction'
        requiredProperties = @('sceneType', 'filePath', 'loadSteps', 'formatVersion', 'nodes', 'connections')
        properties = @{
            sceneType = @{ type = 'string'; enum = @('scene', 'resource', 'unknown') }
            filePath = @{ type = 'string' }
            loadSteps = @{ type = 'integer' }
            formatVersion = @{ type = 'integer' }
            uid = @{ type = 'string' }
            extResource = @{ type = 'array' }
            subResource = @{ type = 'array' }
            nodes = @{ type = 'array' }
            connections = @{ type = 'array' }
            editableInstances = @{ type = 'array' }
            provenance = @{ type = 'object' }
            license = @{ type = 'string' }
            parsedAt = @{ type = 'string'; format = 'date-time' }
        }
    }
    
    'godot-resource' = @{
        type = 'object'
        description = 'Godot resource file extraction (same schema as godot-scene)'
        ref = 'godot-scene'
    }
    
    'rpgmaker-plugin' = @{
        type = 'object'
        description = 'RPG Maker MZ/MV plugin extraction containing metadata, parameters, commands, and dependencies'
        requiredProperties = @('pluginName', 'targetEngine', 'version', 'parameters', 'commands')
        properties = @{
            pluginName = @{ type = 'string' }
            targetEngine = @{ type = 'string'; enum = @('MZ', 'MV', 'Both') }
            description = @{ type = 'string' }
            author = @{ type = 'string' }
            url = @{ type = 'string' }
            helpText = @{ type = 'string' }
            version = @{ type = 'string' }
            parameters = @{ type = 'array' }
            commands = @{ type = 'array' }
            pluginCommands = @{ type = 'array' }
            dependencies = @{ type = 'array' }
            conflicts = @{ type = 'array' }
            order = @{ type = 'object' }
            structs = @{ type = 'array' }
            sourceFile = @{ type = 'string' }
            provenance = @{ type = 'object' }
            license = @{ type = 'string' }
            parsedAt = @{ type = 'string'; format = 'date-time' }
        }
    }
    
    'blender-python' = @{
        type = 'object'
        description = 'Blender Python addon/script extraction containing operators, panels, menus, and properties'
        requiredProperties = @('addonInfo', 'operators', 'panels', 'menus')
        properties = @{
            addonInfo = @{ 
                type = 'object'
                properties = @{
                    name = @{ type = 'string' }
                    author = @{ type = 'string' }
                    version = @{ type = 'array' }
                    blender = @{ type = 'array' }
                    location = @{ type = 'string' }
                    description = @{ type = 'string' }
                    category = @{ type = 'string' }
                    support = @{ type = 'string' }
                }
            }
            operators = @{ type = 'array' }
            panels = @{ type = 'array' }
            menus = @{ type = 'array' }
            operatorCalls = @{ type = 'array' }
            imports = @{ type = 'array' }
            dependencies = @{ type = 'array' }
            geometryNodes = @{ type = 'object' }
            provenance = @{ type = 'object' }
            license = @{ type = 'string' }
            sourceFile = @{ type = 'string' }
            parsedAt = @{ type = 'string'; format = 'date-time' }
            compatibility = @{ type = 'object' }
        }
    }
    
    'gdshader' = @{
        type = 'object'
        description = 'Godot shader file extraction containing uniforms, varyings, functions, and render modes'
        requiredProperties = @('shaderType', 'uniforms', 'functions')
        properties = @{
            shaderType = @{ type = 'string' }
            shaderName = @{ type = 'string' }
            uniforms = @{ type = 'array' }
            varyings = @{ type = 'array' }
            consts = @{ type = 'array' }
            functions = @{ type = 'array' }
            renderMode = @{ type = 'array' }
            sourceFile = @{ type = 'string' }
            provenance = @{ type = 'object' }
            license = @{ type = 'string' }
        }
    }
    
    'geometry-nodes' = @{
        type = 'object'
        description = 'Blender Geometry Nodes extraction containing node groups, nodes, and links'
        requiredProperties = @('nodeGroups', 'nodes', 'links')
        properties = @{
            nodeGroups = @{ type = 'array' }
            nodes = @{ type = 'array' }
            links = @{ type = 'array' }
            inputs = @{ type = 'array' }
            outputs = @{ type = 'array' }
            provenance = @{ type = 'object' }
            license = @{ type = 'string' }
            parsedAt = @{ type = 'string'; format = 'date-time' }
        }
    }
    
    'shader' = @{
        type = 'object'
        description = 'Generic shader extraction (delegates to gdshader schema)'
        ref = 'gdshader'
    }

    'unreal-plugin' = @{
        type = 'object'
        description = 'Unreal Engine plugin descriptor extraction containing plugin metadata, modules, references, and compatibility hints'
        requiredProperties = @('descriptorType', 'fileVersion', 'friendlyName', 'modules', 'plugins')
        properties = @{
            descriptorType = @{ type = 'string'; enum = @('plugin') }
            fileVersion = @{ type = 'integer' }
            version = @{ type = 'integer' }
            versionName = @{ type = 'string' }
            friendlyName = @{ type = 'string' }
            name = @{ type = 'string' }
            description = @{ type = 'string' }
            category = @{ type = 'string' }
            engineAssociation = @{ type = 'string' }
            createdBy = @{ type = 'string' }
            createdByUrl = @{ type = 'string' }
            docsUrl = @{ type = 'string' }
            marketplaceUrl = @{ type = 'string' }
            supportUrl = @{ type = 'string' }
            canContainContent = @{ type = 'boolean' }
            isBetaVersion = @{ type = 'boolean' }
            isExperimentalVersion = @{ type = 'boolean' }
            enabledByDefault = @{ type = 'boolean' }
            installed = @{ type = 'boolean' }
            targetPlatforms = @{ type = 'array' }
            modules = @{ type = 'array' }
            plugins = @{ type = 'array' }
            sourceFile = @{ type = 'string' }
            provenance = @{ type = 'object' }
            license = @{ type = 'string' }
            parsedAt = @{ type = 'string'; format = 'date-time' }
            compatibility = @{ type = 'object' }
        }
    }

    'unreal-project' = @{
        type = 'object'
        description = 'Unreal Engine project descriptor extraction containing engine association, plugin references, modules, and target platforms'
        requiredProperties = @('descriptorType', 'fileVersion', 'name', 'plugins')
        properties = @{
            descriptorType = @{ type = 'string'; enum = @('project') }
            fileVersion = @{ type = 'integer' }
            version = @{ type = 'integer' }
            versionName = @{ type = 'string' }
            friendlyName = @{ type = 'string' }
            name = @{ type = 'string' }
            description = @{ type = 'string' }
            category = @{ type = 'string' }
            engineAssociation = @{ type = 'string' }
            targetPlatforms = @{ type = 'array' }
            modules = @{ type = 'array' }
            plugins = @{ type = 'array' }
            sourceFile = @{ type = 'string' }
            provenance = @{ type = 'object' }
            license = @{ type = 'string' }
            parsedAt = @{ type = 'string'; format = 'date-time' }
            compatibility = @{ type = 'object' }
        }
    }
}

# ============================================================================
# Module-level Variables
# ============================================================================

$script:ParserModulesLoaded = $false
$script:LoadedParserModules = @()

# ============================================================================
# Private Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Loads all required parser modules.
.DESCRIPTION
    Dot-sources all domain-specific parser modules. This is called automatically
    when needed but can be called explicitly to pre-load modules.
.OUTPUTS
    System.Boolean. $true if all modules loaded successfully.
#>
function Import-ParserModules {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    if ($script:ParserModulesLoaded) {
        return $true
    }
    
    $extractionPath = Join-Path $PSScriptRoot 'parsers'
    
    $requiredModules = @(
        'GDScriptParser.ps1'
        'GodotSceneParser.ps1'
        'RPGMakerPluginParser.ps1'
        'BlenderPythonParser.ps1'
        'UnrealDescriptorParser.ps1'
        'ShaderParser.ps1'
        'GeometryNodesParser.ps1'
    )
    
    $success = $true
    $loadedModules = @()
    
    foreach ($module in $requiredModules) {
        $modulePath = Join-Path $extractionPath $module
        if (Test-Path -LiteralPath $modulePath) {
            try {
                . $modulePath
                $loadedModules += $module
                Write-Verbose "[$script:ModuleName] Loaded parser module: $module"
            }
            catch {
                Write-Warning "[$script:ModuleName] Failed to load module $module`: $_"
                $success = $false
            }
        }
        else {
            Write-Warning "[$script:ModuleName] Module not found: $modulePath"
            $success = $false
        }
    }
    
    $script:ParserModulesLoaded = $success
    $script:LoadedParserModules = $loadedModules
    
    return $success
}

<#
.SYNOPSIS
    Calculates SHA256 checksum for a file.
.DESCRIPTION
    Computes the SHA256 hash of file content for integrity tracking.
.PARAMETER Path
    Path to the file.
.OUTPUTS
    System.String. SHA256 hash string prefixed with "sha256:".
#>
function Get-FileChecksum {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        $hash = Get-FileHash -Path $Path -Algorithm SHA256 -ErrorAction Stop
        return "sha256:$($hash.Hash.ToLower())"
    }
    catch {
        Write-Verbose "[$script:ModuleName] Failed to compute checksum: $_"
        return 'sha256:unknown'
    }
}

<#
.SYNOPSIS
    Gets file metadata for extraction envelope.
.DESCRIPTION
    Collects file size, line count, and checksum information.
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
            checksum = Get-FileChecksum -Path $Path
            lastModified = $fileInfo.LastWriteTimeUtc.ToString("o")
        }
    }
    catch {
        return @{
            fileSize = 0
            lineCount = 0
            checksum = 'sha256:error'
            lastModified = $null
        }
    }
}

<#
.SYNOPSIS
    Creates the normalized extraction envelope.
.DESCRIPTION
    Wraps parser output in the standard Phase 4 extraction envelope format.
.PARAMETER ExtractionId
    Unique extraction identifier (UUID).
.PARAMETER SourceFile
    Path to the source file.
.PARAMETER FileType
    Detected file type.
.PARAMETER PackType
    Pack/engine type.
.PARAMETER Success
    Whether extraction was successful.
.PARAMETER Data
    Parser-specific output data.
.PARAMETER Errors
    Array of error messages.
.PARAMETER Warnings
    Array of warning messages.
.PARAMETER Metadata
    File metadata hashtable.
.OUTPUTS
    System.Collections.Hashtable. Normalized extraction envelope.
#>
function New-ExtractionEnvelope {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExtractionId,
        
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,
        
        [Parameter(Mandatory = $true)]
        [string]$FileType,
        
        [Parameter(Mandatory = $true)]
        [string]$PackType,
        
        [Parameter(Mandatory = $true)]
        [bool]$Success,
        
        [Parameter()]
        [object]$Data = $null,
        
        [Parameter()]
        [array]$Errors = @(),
        
        [Parameter()]
        [array]$Warnings = @(),
        
        [Parameter()]
        [hashtable]$Metadata = @{},
        
        [Parameter()]
        [string]$ExtractionDepth = 'deep',

        [Parameter()]
        [string]$CorrelationId = ''
    )
    
    $provenance = [ordered]@{ 
        sourceFile = $SourceFile
        extractedBy = 'ExtractionPipeline'
        extractedAt = [DateTime]::UtcNow.ToString('o')
        correlationId = $CorrelationId
    }

    return @{
        extractionId = $ExtractionId
        extractedAt = [DateTime]::UtcNow.ToString("o")
        sourceFile = $SourceFile
        provenance = $provenance
        correlationId = $CorrelationId
        license = 'unknown'
        fileType = $FileType
        packType = $PackType
        extractionDepth = $ExtractionDepth
        success = $Success
        errors = $Errors
        warnings = $Warnings
        data = $Data
        metadata = $Metadata
    }
}

<#
.SYNOPSIS
    Detects file type from content when extension is ambiguous.
.DESCRIPTION
    Analyzes file content to determine the actual file type, particularly
    useful for .js files which could be RPG Maker plugins or regular JS.
.PARAMETER Path
    Path to the file.
.PARAMETER Extension
    File extension (including dot).
.PARAMETER Content
    Optional file content (will be read if not provided).
.OUTPUTS
    System.Collections.Hashtable. Detection result with FileType and Confidence.
#>
function Test-FileContentType {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [string]$Extension,
        
        [Parameter()]
        [string]$Content = ''
    )
    
    if ([string]::IsNullOrEmpty($Content) -and (Test-Path -LiteralPath $Path)) {
        try {
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        catch {
            # Continue with empty content
        }
    }
    
    switch ($Extension.ToLower()) {
        '.js' {
            # Check for RPG Maker plugin patterns
            $isRMMZ = $Content -match '/\*:|@plugindesc|PluginManager\.parameters'
            if ($isRMMZ) {
                return @{ FileType = 'rpgmaker-plugin'; Confidence = 'high' }
            }
            return @{ FileType = 'unknown'; Confidence = 'low' }
        }
        
        '.py' {
            # Check for Blender addon patterns
            $isBlender = $Content -match 'import bpy|from bpy|bl_info\s*=|bpy\.types'
            if ($isBlender) {
                return @{ FileType = 'blender-python'; Confidence = 'high' }
            }
            return @{ FileType = 'unknown'; Confidence = 'low' }
        }
        
        '.shader' {
            # Check for Godot vs other shader types
            $isGodot = $Content -match 'shader_type\s+\w+\s*;'
            if ($isGodot) {
                return @{ FileType = 'gdshader'; Confidence = 'high' }
            }
            return @{ FileType = 'shader'; Confidence = 'medium' }
        }
        
        default {
            if ($script:ExtensionMapping.ContainsKey($Extension)) {
                return @{ 
                    FileType = $script:ExtensionMapping[$Extension].FileType
                    Confidence = 'high'
                }
            }
            return @{ FileType = 'unknown'; Confidence = 'none' }
        }
    }
}

<#
.SYNOPSIS
    Executes the appropriate parser for a file.
.DESCRIPTION
    Routes the file to the correct parser based on file type mapping.
.PARAMETER Path
    Path to the file.
.PARAMETER FileType
    Detected file type.
.PARAMETER Mapping
    Extension mapping entry.
.OUTPUTS
    System.Collections.Hashtable. Parser output or $null on failure.
#>
function Invoke-ParserByType {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [string]$FileType,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Mapping,

        [Parameter()]
        [string]$CorrelationId = ''
    )
    
    $parserFunction = $Mapping.Function
    
    # Verify function exists
    if (-not (Get-Command -Name $parserFunction -ErrorAction SilentlyContinue)) {
        throw "Parser function '$parserFunction' not found. Ensure parser modules are loaded."
    }
    
    Write-Verbose "[$CorrelationId] [$script:ModuleName] Invoking parser: $parserFunction for $Path"
    
    # Invoke the parser, passing CorrelationId if supported
    $cmd = Get-Command -Name $parserFunction -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Parameters.ContainsKey('CorrelationId')) {
        $result = & $parserFunction -Path $Path -CorrelationId $CorrelationId
    }
    else {
        $result = & $parserFunction -Path $Path
    }
    
    return $result
}

<#
.SYNOPSIS
    Converts extraction envelope to requested output format.
.DESCRIPTION
    Converts the hashtable envelope to JSON string, PSCustomObject, or returns as-is.
.PARAMETER Envelope
    The extraction envelope.
.PARAMETER Format
    Desired output format: json, object, or hashtable.
.OUTPUTS
    System.Object. Formatted output based on Format parameter.
#>
function ConvertTo-OutputFormat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$Envelope,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('json', 'object', 'hashtable')]
        [string]$Format
    )
    
    process {
        switch ($Format) {
            'json' {
                return $Envelope | ConvertTo-Json -Depth 20 -Compress:$false
            }
            'object' {
                return [PSCustomObject]$Envelope
            }
            'hashtable' {
                return $Envelope
            }
        }
    }
}

# ============================================================================
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
    Main orchestrator that routes files to appropriate parsers based on extension and content type.

.DESCRIPTION
    The primary entry point for the extraction pipeline. Automatically detects file type,
    routes to the appropriate domain-specific parser, and returns a normalized extraction envelope.

.PARAMETER FilePath
    Path to the file to extract. Mandatory.

.PARAMETER PackType
    Optional pack type hint (rpgmaker-mz, godot-engine, blender-engine). If not specified,
    will be detected from file extension.

.PARAMETER OutputFormat
    Output format for the extraction result. Options:
    - json: JSON string
    - object: PSCustomObject
    - hashtable: Hashtable (default)

.OUTPUTS
    System.Object. Extraction result in the requested format (hashtable by default).

.EXAMPLE
    # Extract a GDScript file
    $result = Invoke-StructuredExtraction -FilePath "player.gd"

.EXAMPLE
    # Extract with JSON output
    $json = Invoke-StructuredExtraction -FilePath "plugin.js" -OutputFormat json

.EXAMPLE
    # Extract with explicit pack type
    $result = Invoke-StructuredExtraction -FilePath "script.py" -PackType "blender-engine"

.EXAMPLE
    # Extract and convert to object
    $obj = Invoke-StructuredExtraction -FilePath "scene.tscn" -OutputFormat object
#>
function Invoke-StructuredExtraction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('Path')]
        [string]$FilePath,
        
        [Parameter()]
        [ValidateSet('rpgmaker-mz', 'godot-engine', 'blender-engine', 'unreal-engine')]
        [string]$PackType = '',
        
        [Parameter()]
        [ValidateSet('json', 'object', 'hashtable')]
        [string]$OutputFormat = 'hashtable',
        
        [Parameter()]
        [ValidateSet('inventory', 'deep')]
        [string]$ExtractionDepth = 'deep',

        [Parameter()]
        [string]$CorrelationId = ''
    )
    
    begin {
        $extractionId = [System.Guid]::NewGuid().ToString()
        if ([string]::IsNullOrEmpty($CorrelationId)) {
            $CorrelationId = New-CorrelationId
        }
        Write-Verbose "[$CorrelationId] Starting extraction for $FilePath"
        
        # Ensure parser modules are loaded
        if (-not (Import-ParserModules)) {
            Write-Warning "[$CorrelationId] [$script:ModuleName] Some parser modules failed to load"
        }
    }
    
    process {
        # Validate file exists
        if (-not (Test-Path -LiteralPath $FilePath)) {
            $envelope = New-ExtractionEnvelope `
                -ExtractionId $extractionId `
                -SourceFile $FilePath `
                -FileType 'unknown' `
                -PackType ($PackType -or 'unknown') `
                -Success $false `
                -Errors @("File not found: $FilePath") `
                -ExtractionDepth $ExtractionDepth `
                -CorrelationId $CorrelationId
            
            return ConvertTo-OutputFormat -Envelope $envelope -Format $OutputFormat
        }
        
        $resolvedPath = Resolve-Path -Path $FilePath | Select-Object -ExpandProperty Path
        $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
        $errors = @()
        $warnings = @()
        
        # Determine file type from extension
        $mapping = $null
        $detectedFileType = 'unknown'
        $detectedPackType = $PackType
        
        if ($script:ExtensionMapping.ContainsKey($extension)) {
            $mapping = $script:ExtensionMapping[$extension]
            $detectedFileType = $mapping.FileType
            if ([string]::IsNullOrEmpty($detectedPackType)) {
                $detectedPackType = $mapping.PackType
            }
        }
        else {
            # Try content-based detection for ambiguous extensions
            $contentType = Test-FileContentType -Path $FilePath -Extension $extension
            if ($contentType.Confidence -ne 'none') {
                $detectedFileType = $contentType.FileType
                # Find mapping by file type
                foreach ($entry in $script:ExtensionMapping.GetEnumerator()) {
                    if ($entry.Value.FileType -eq $detectedFileType) {
                        $mapping = $entry.Value
                        if ([string]::IsNullOrEmpty($detectedPackType)) {
                            $detectedPackType = $entry.Value.PackType
                        }
                        break
                    }
                }
            }
        }
        
        # If still no mapping, return unsupported error
        if ($null -eq $mapping) {
            $envelope = New-ExtractionEnvelope `
                -ExtractionId $extractionId `
                -SourceFile $resolvedPath `
                -FileType $detectedFileType `
                -PackType ($detectedPackType -or 'unknown') `
                -Success $false `
                -Errors @("Unsupported file type: $extension") `
                -ExtractionDepth $ExtractionDepth `
                -CorrelationId $CorrelationId
            
            return ConvertTo-OutputFormat -Envelope $envelope -Format $OutputFormat
        }
        
        Write-Verbose "[$CorrelationId] [$script:ModuleName] Detected type: $detectedFileType, pack: $detectedPackType"
        
        # Get file metadata
        $metadata = Get-FileMetadata -Path $resolvedPath
        
        # Execute extraction
        $data = $null
        $success = $false
        
        try {
            $data = Invoke-ParserByType -Path $resolvedPath -FileType $detectedFileType -Mapping $mapping -CorrelationId $CorrelationId
            
            if ($null -ne $data) {
                $success = $true
                Write-Verbose "[$CorrelationId] [$script:ModuleName] Extraction successful"
            }
            else {
                $errors += "Parser returned null - file may be empty or invalid"
            }
        }
        catch {
            $errorMsg = "Extraction failed: $_"
            $errors += $errorMsg
            Write-Warning "[$CorrelationId] [$script:ModuleName] $errorMsg"
        }
        
        # Build envelope
        $envelope = New-ExtractionEnvelope `
            -ExtractionId $extractionId `
            -SourceFile $resolvedPath `
            -FileType $detectedFileType `
            -PackType $detectedPackType `
            -Success $success `
            -Data $data `
            -Errors $errors `
            -Warnings $warnings `
            -Metadata $metadata `
            -ExtractionDepth $ExtractionDepth `
            -CorrelationId $CorrelationId
        
        return ConvertTo-OutputFormat -Envelope $envelope -Format $OutputFormat
    }
    
    end {
        Write-Verbose "[$CorrelationId] [$script:ModuleName] Extraction [$extractionId] complete"
    }
}

<#
.SYNOPSIS
    Returns the schema definition for a given extraction type.

.DESCRIPTION
    Retrieves the JSON Schema-like definition for the specified extraction type.
    This describes the structure of data returned by the parsers.

.PARAMETER Type
    The extraction type to get the schema for. Valid values:
    - gdscript
    - godot-scene
    - godot-resource
    - rpgmaker-plugin
    - blender-python
    - unreal-plugin
    - unreal-project
    - geometry-nodes
    - shader

.OUTPUTS
    System.Collections.Hashtable. Schema definition.

.EXAMPLE
    # Get schema for GDScript
    $schema = Get-ExtractionSchema -Type "gdscript"

.EXAMPLE
    # Get all schemas
    $types = @("gdscript", "godot-scene", "rpgmaker-plugin")
    $schemas = $types | ForEach-Object { Get-ExtractionSchema -Type $_ }
#>
function Get-ExtractionSchema {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet('gdscript', 'godot-scene', 'godot-resource', 
                     'rpgmaker-plugin', 'blender-python', 'unreal-plugin',
                     'unreal-project', 'geometry-nodes', 'shader')]
        [string]$Type
    )
    
    if ($script:SchemaDefinitions.ContainsKey($Type)) {
        $schema = $script:SchemaDefinitions[$Type]
        
        # Handle schema references
        if ($schema.ContainsKey('ref')) {
            $refSchema = $script:SchemaDefinitions[$schema.ref]
            if ($null -ne $refSchema) {
                return $refSchema
            }
        }
        
        return $schema
    }
    
    return $null
}

<#
.SYNOPSIS
    Tests if a file type is supported for extraction.

.DESCRIPTION
    Checks whether the specified file path has a supported extension
    and optionally validates content for ambiguous types.

.PARAMETER FilePath
    Path to the file to check.

.PARAMETER ValidateContent
    If specified, also validates file content for ambiguous extensions like .js and .py.

.OUTPUTS
    System.Boolean. $true if the file type is supported.

.EXAMPLE
    # Simple extension check
    if (Test-ExtractionSupported -FilePath "script.gd") { ... }

.EXAMPLE
    # Check with content validation
    Test-ExtractionSupported -FilePath "plugin.js" -ValidateContent
#>
function Test-ExtractionSupported {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('Path')]
        [string]$FilePath,
        
        [Parameter()]
        [switch]$ValidateContent
    )
    
    # Check if file exists
    if (-not (Test-Path -LiteralPath $FilePath)) {
        return $false
    }
    
    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    
    # Direct extension match
    if ($script:ExtensionMapping.ContainsKey($extension)) {
        # For .js and .py, optionally validate content
        if ($ValidateContent -and ($extension -in @('.js', '.py', '.shader'))) {
            $contentType = Test-FileContentType -Path $FilePath -Extension $extension
            return $contentType.Confidence -in @('high', 'medium')
        }
        return $true
    }
    
    # Try content-based detection
    if ($ValidateContent) {
        $contentType = Test-FileContentType -Path $FilePath -Extension $extension
        return $contentType.Confidence -in @('high', 'medium')
    }
    
    return $false
}

<#
.SYNOPSIS
    Returns list of supported file extensions and their handlers.

.DESCRIPTION
    Returns a collection of all supported file types with their associated
    parser modules, functions, and pack types.

.PARAMETER AsHashtable
    If specified, returns a hashtable instead of objects.

.OUTPUTS
    System.Array or System.Collections.Hashtable. List of supported types.

.EXAMPLE
    # Get supported types as objects
    Get-SupportedExtractionTypes | Format-Table

.EXAMPLE
    # Get as hashtable
    $types = Get-SupportedExtractionTypes -AsHashtable
    $types['.gd']
#>
function Get-SupportedExtractionTypes {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [switch]$AsHashtable
    )
    
    if ($AsHashtable) {
        return $script:ExtensionMapping
    }
    
    $types = foreach ($entry in $script:ExtensionMapping.GetEnumerator()) {
        [PSCustomObject]@{
            Extension = $entry.Key
            Parser = $entry.Value.Parser
            Function = $entry.Value.Function
            PackType = $entry.Value.PackType
            FileType = $entry.Value.FileType
        }
    }
    
    return $types
}

<#
.SYNOPSIS
    Processes multiple files with progress reporting.

.DESCRIPTION
    Extracts structured data from multiple files in a batch operation.
    Provides progress reporting and can preserve directory hierarchy in output.

.PARAMETER FilePaths
    Array of file paths to process.

.PARAMETER OutputDirectory
    Directory to save extracted results. If not specified, results are returned.

.PARAMETER PreserveHierarchy
    If specified and OutputDirectory is provided, preserves the directory structure
    relative to the common root path.

.PARAMETER Parallel
    If specified, processes files in parallel (requires PowerShell 7+).

.PARAMETER ThrottleLimit
    Maximum number of parallel operations when using -Parallel.

.OUTPUTS
    System.Array. Array of extraction results.

.EXAMPLE
    # Batch extract all GD files
    $results = Invoke-BatchExtraction -FilePaths (Get-ChildItem *.gd -Recurse)

.EXAMPLE
    # Extract and save to directory
    Invoke-BatchExtraction -FilePaths $files -OutputDirectory "./extracted" -PreserveHierarchy

.EXAMPLE
    # Extract with progress
    $results = Invoke-BatchExtraction -FilePaths $files -Verbose
#>
function Invoke-BatchExtraction {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string[]]$FilePaths,
        
        [Parameter()]
        [string]$OutputDirectory = '',
        
        [Parameter()]
        [switch]$PreserveHierarchy,
        
        [Parameter()]
        [switch]$Parallel,
        
        [Parameter()]
        [int]$ThrottleLimit = 4
    )
    
    begin {
        $batchId = [System.Guid]::NewGuid().ToString().Substring(0, 8)
        Write-Verbose "[$script:ModuleName] Starting batch extraction [$batchId]"
        
        # Ensure parser modules are loaded
        if (-not (Import-ParserModules)) {
            Write-Warning "[$script:ModuleName] Some parser modules failed to load"
        }
        
        # Filter to existing files
        $validFiles = $FilePaths | Where-Object { Test-Path -LiteralPath $_ }
        $totalFiles = $validFiles.Count
        
        if ($totalFiles -eq 0) {
            Write-Warning "[$script:ModuleName] No valid files to process"
            return @()
        }
        
        Write-Verbose "[$script:ModuleName] Processing $totalFiles files"
        
        # Create output directory if specified
        if (-not [string]::IsNullOrEmpty($OutputDirectory)) {
            if (-not (Test-Path -LiteralPath $OutputDirectory)) {
                New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
            }
        }
        
        # Calculate common root for hierarchy preservation
        $commonRoot = ''
        if ($PreserveHierarchy -and $validFiles.Count -gt 0) {
            $commonRoot = [System.IO.Path]::GetDirectoryName($validFiles[0])
            foreach ($file in $validFiles) {
                $dir = [System.IO.Path]::GetDirectoryName($file)
                while (-not $dir.StartsWith($commonRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $commonRoot = [System.IO.Path]::GetDirectoryName($commonRoot)
                    if ([string]::IsNullOrEmpty($commonRoot)) { break }
                }
            }
        }
        
        $results = [System.Collections.ArrayList]::new()
        $processed = 0
        $successCount = 0
        $failCount = 0
    }
    
    process {
        foreach ($filePath in $validFiles) {
            $processed++
            
            # Progress
            $percentComplete = ($processed / $totalFiles) * 100
            $status = "Processing $processed of $totalFiles`: $([System.IO.Path]::GetFileName($filePath))"
            Write-Progress -Activity "Batch Extraction [$batchId]" -Status $status -PercentComplete $percentComplete
            
            Write-Verbose "[$script:ModuleName] [$processed/$totalFiles] Extracting: $filePath"
            
            # Extract
            try {
                $result = Invoke-StructuredExtraction -FilePath $filePath -OutputFormat hashtable
                [void]$results.Add($result)
                
                if ($result.success) {
                    $successCount++
                }
                else {
                    $failCount++
                    Write-Warning "[$script:ModuleName] Failed to extract: $filePath - $($result.errors -join ', ')"
                }
                
                # Save to file if output directory specified
                if (-not [string]::IsNullOrEmpty($OutputDirectory)) {
                    $outputPath = ''
                    
                    if ($PreserveHierarchy -and -not [string]::IsNullOrEmpty($commonRoot)) {
                        # Calculate relative path
                        $relativePath = $filePath.Substring($commonRoot.Length).TrimStart('\', '/')
                        $relativeDir = [System.IO.Path]::GetDirectoryName($relativePath)
                        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
                        $outputPath = Join-Path $OutputDirectory $relativeDir "$fileName.json"
                    }
                    else {
                        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
                        $outputPath = Join-Path $OutputDirectory "$fileName.json"
                    }
                    
                    # Ensure output subdirectory exists
                    $outputDir = [System.IO.Path]::GetDirectoryName($outputPath)
                    if (-not (Test-Path -LiteralPath $outputDir)) {
                        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
                    }
                    
                    # Save JSON
                    $result | ConvertTo-Json -Depth 20 | Set-Content -Path $outputPath -Encoding UTF8
                    Write-Verbose "[$script:ModuleName] Saved: $outputPath"
                }
            }
            catch {
                $failCount++
                Write-Warning "[$script:ModuleName] Exception extracting $filePath`: $_"
                
                # Add error result
                $batchCorrelationId = New-CorrelationId
                [void]$results.Add(@{
                    extractionId = [System.Guid]::NewGuid().ToString()
                    extractedAt = [DateTime]::UtcNow.ToString("o")
                    sourceFile = $filePath
                    correlationId = $batchCorrelationId
                    provenance = [ordered]@{
                        sourceFile = $filePath
                        extractedBy = 'ExtractionPipeline'
                        extractedAt = [DateTime]::UtcNow.ToString('o')
                        correlationId = $batchCorrelationId
                    }
                    fileType = 'unknown'
                    packType = 'unknown'
                    success = $false
                    errors = @($_.ToString())
                    warnings = @()
                    data = $null
                    metadata = @{}
                })
            }
        }
    }
    
    end {
        Write-Progress -Activity "Batch Extraction [$batchId]" -Completed
        
        Write-Verbose "[$script:ModuleName] Batch [$batchId] complete: $successCount succeeded, $failCount failed"
        
        return $results.ToArray()
    }
}

<#
.SYNOPSIS
    Generates a summary report of extraction results.

.DESCRIPTION
    Analyzes a collection of extraction results and generates a summary report
    with statistics, errors, and aggregated information.

.PARAMETER Results
    Array of extraction result envelopes (from Invoke-StructuredExtraction or Invoke-BatchExtraction).

.PARAMETER OutputPath
    Optional path to save the report as JSON.

.PARAMETER IncludeDetails
    If specified, includes detailed per-file results in the report.

.OUTPUTS
    System.Collections.Hashtable. Summary report object.

.EXAMPLE
    # Generate report from batch results
    $results = Invoke-BatchExtraction -FilePaths $files
    $report = Export-ExtractionReport -Results $results

.EXAMPLE
    # Save report to file
    Export-ExtractionReport -Results $results -OutputPath "./extraction-report.json"

.EXAMPLE
    # Get detailed report
    $report = Export-ExtractionReport -Results $results -IncludeDetails
#>
function Export-ExtractionReport {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [array]$Results,
        
        [Parameter()]
        [string]$OutputPath = '',
        
        [Parameter()]
        [switch]$IncludeDetails
    )
    
    begin {
        $allResults = [System.Collections.ArrayList]::new()
    }
    
    process {
        foreach ($result in $Results) {
            [void]$allResults.Add($result)
        }
    }
    
    end {
        $resultsArray = $allResults.ToArray()
        $total = $resultsArray.Count
        
        if ($total -eq 0) {
            Write-Warning "[$script:ModuleName] No results to report"
            return $null
        }
        
        # Calculate statistics
        $successful = ($resultsArray | Where-Object { $_.success }).Count
        $failed = $total - $successful
        $successRate = if ($total -gt 0) { ($successful / $total) * 100 } else { 0 }
        
        # Group by file type
        $byFileType = $resultsArray | Group-Object -Property fileType | ForEach-Object {
            @{
                fileType = $_.Name
                count = $_.Count
                successful = ($_.Group | Where-Object { $_.success }).Count
                failed = ($_.Group | Where-Object { -not $_.success }).Count
            }
        }
        
        # Group by pack type
        $byPackType = $resultsArray | Group-Object -Property packType | ForEach-Object {
            @{
                packType = $_.Name
                count = $_.Count
                successful = ($_.Group | Where-Object { $_.success }).Count
                failed = ($_.Group | Where-Object { -not $_.success }).Count
            }
        }
        
        # Collect errors
        $errors = $resultsArray | Where-Object { $_.errors.Count -gt 0 } | ForEach-Object {
            @{
                file = $_.sourceFile
                errors = $_.errors
            }
        }
        
        # Collect warnings
        $warnings = $resultsArray | Where-Object { $_.warnings.Count -gt 0 } | ForEach-Object {
            @{
                file = $_.sourceFile
                warnings = $_.warnings
            }
        }
        
        # File size statistics
        $totalSize = ($resultsArray | ForEach-Object { $_.metadata.fileSize } | Measure-Object -Sum).Sum
        $avgSize = if ($total -gt 0) { $totalSize / $total } else { 0 }
        
        # Build report
        $report = @{
            reportId = [System.Guid]::NewGuid().ToString()
            generatedAt = [DateTime]::UtcNow.ToString("o")
            summary = @{
                totalFiles = $total
                successful = $successful
                failed = $failed
                successRate = [Math]::Round($successRate, 2)
                totalSizeBytes = $totalSize
                averageSizeBytes = [Math]::Round($avgSize, 0)
            }
            byFileType = $byFileType
            byPackType = $byPackType
            errors = @{
                count = $errors.Count
                items = $errors
            }
            warnings = @{
                count = $warnings.Count
                items = $warnings
            }
        }
        
        if ($IncludeDetails) {
            $report.details = $resultsArray | ForEach-Object {
                @{
                    extractionId = $_.extractionId
                    sourceFile = $_.sourceFile
                    fileType = $_.fileType
                    packType = $_.packType
                    success = $_.success
                    extractedAt = $_.extractedAt
                }
            }
        }
        
        # Save to file if path specified
        if (-not [string]::IsNullOrEmpty($OutputPath)) {
            $reportDir = [System.IO.Path]::GetDirectoryName($OutputPath)
            if (-not [string]::IsNullOrEmpty($reportDir) -and -not (Test-Path -LiteralPath $reportDir)) {
                New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
            }
            
            $report | ConvertTo-Json -Depth 15 | Set-Content -Path $OutputPath -Encoding UTF8
            Write-Verbose "[$script:ModuleName] Report saved to: $OutputPath"
        }
        
        return $report
    }
}

<#
.SYNOPSIS
    Gets the version of the ExtractionPipeline module.
.DESCRIPTION
    Returns the version string of this module.
.OUTPUTS
    System.String. Version string in semantic versioning format.
#>
function Get-ExtractionPipelineVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    return $script:ModuleVersion
}

<#
.SYNOPSIS
    Resets the parser module loading state.
.DESCRIPTION
    Forces parser modules to be reloaded on next use. Useful for development
    or when parser modules have been updated.
#>
function Reset-ExtractionPipeline {
    [CmdletBinding()]
    param()
    
    $script:ParserModulesLoaded = $false
    $script:LoadedParserModules = @()
    Write-Verbose "[$script:ModuleName] Pipeline state reset"
}

Set-Alias -Name 'Invoke-ExtractionPipeline' -Value 'Invoke-StructuredExtraction'

# Export module members (only if loaded as a module)
if ($MyInvocation.InvocationName -ne '.') {
    Export-ModuleMember -Function @(
        'Invoke-StructuredExtraction'
        'Get-ExtractionSchema'
        'Test-ExtractionSupported'
        'Get-SupportedExtractionTypes'
        'Invoke-BatchExtraction'
        'Export-ExtractionReport'
        'Get-ExtractionPipelineVersion'
        'Reset-ExtractionPipeline'
    ) -Alias @(
        'Invoke-ExtractionPipeline'
    )
}
