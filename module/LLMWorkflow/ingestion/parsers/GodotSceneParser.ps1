#Requires -Version 5.1
<#
.SYNOPSIS
    PowerShell module for parsing Godot scene files (.tscn) and resource files (.tres).

.DESCRIPTION
    This module provides functions to parse Godot 3 and Godot 4 scene and resource files,
    extracting node hierarchies, signal connections, resource references, and properties.
    Supports both format=2 (Godot 3) and format=3 (Godot 4) file formats.

.NOTES
    File Name      : GodotSceneParser.ps1
    Author         : LLMWorkflow
    Version        : 1.0.0
    Godot Versions : 3.x (format=2), 4.x (format=3)
#>

#region Helper Functions

<#
.SYNOPSIS
    Parses a Godot value string into an appropriate PowerShell object.

.DESCRIPTION
    Converts Godot value types (Vector2, Color, NodePath, etc.) to PowerShell objects.
    Handles strings, numbers, booleans, arrays, and Godot-specific types.

.PARAMETER Value
    The Godot value string to parse.

.OUTPUTS
    The parsed value as a PowerShell object.
#>
function ConvertFrom-GodotValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $trimmed = $Value.Trim()

    # Handle empty or null
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return ""
    }

    # Handle null literal
    if ($trimmed -eq 'null') {
        return $null
    }

    # Handle true/false booleans
    if ($trimmed -eq 'true') { return $true }
    if ($trimmed -eq 'false') { return $false }

    # Handle integers
    if ($trimmed -match '^-?\d+$') {
        return [int]$trimmed
    }

    # Handle floats
    if ($trimmed -match '^-?\d+\.\d+$') {
        return [double]$trimmed
    }

    # Handle double-quoted strings
    if ($trimmed -match '^"(.*)"$') {
        return $matches[1]
    }

    # Handle ExtResource reference
    if ($trimmed -match '^ExtResource\s*\(\s*"([^"]+)"\s*\)$') {
        return @{ 
            '__type' = 'ExtResource'
            'id' = $matches[1]
        }
    }

    # Handle SubResource reference
    if ($trimmed -match '^SubResource\s*\(\s*"([^"]+)"\s*\)$') {
        return @{ 
            '__type' = 'SubResource'
            'id' = $matches[1]
        }
    }

    # Handle NodePath
    if ($trimmed -match '^NodePath\s*\(\s*"([^"]+)"\s*\)$') {
        return @{
            '__type' = 'NodePath'
            'path' = $matches[1]
        }
    }

    # Handle Vector2
    if ($trimmed -match '^Vector2\s*\(\s*([^,]+),\s*([^)]+)\s*\)$') {
        return @{
            '__type' = 'Vector2'
            'x' = [double]$matches[1].Trim()
            'y' = [double]$matches[2].Trim()
        }
    }

    # Handle Vector3
    if ($trimmed -match '^Vector3\s*\(\s*([^,]+),\s*([^,]+),\s*([^)]+)\s*\)$') {
        return @{
            '__type' = 'Vector3'
            'x' = [double]$matches[1].Trim()
            'y' = [double]$matches[2].Trim()
            'z' = [double]$matches[3].Trim()
        }
    }

    # Handle Vector2i (Godot 4)
    if ($trimmed -match '^Vector2i\s*\(\s*([^,]+),\s*([^)]+)\s*\)$') {
        return @{
            '__type' = 'Vector2i'
            'x' = [int]$matches[1].Trim()
            'y' = [int]$matches[2].Trim()
        }
    }

    # Handle Vector3i (Godot 4)
    if ($trimmed -match '^Vector3i\s*\(\s*([^,]+),\s*([^,]+),\s*([^)]+)\s*\)$') {
        return @{
            '__type' = 'Vector3i'
            'x' = [int]$matches[1].Trim()
            'y' = [int]$matches[2].Trim()
            'z' = [int]$matches[3].Trim()
        }
    }

    # Handle Color
    if ($trimmed -match '^Color\s*\(\s*([^,]+),\s*([^,]+),\s*([^,]+)(?:,\s*([^)]+))?\s*\)$') {
        $color = @{
            '__type' = 'Color'
            'r' = [double]$matches[1].Trim()
            'g' = [double]$matches[2].Trim()
            'b' = [double]$matches[3].Trim()
        }
        if ($matches[4]) {
            $color['a'] = [double]$matches[4].Trim()
        }
        return $color
    }

    # Handle Rect2
    if ($trimmed -match '^Rect2\s*\(\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^)]+)\s*\)$') {
        return @{
            '__type' = 'Rect2'
            'x' = [double]$matches[1].Trim()
            'y' = [double]$matches[2].Trim()
            'width' = [double]$matches[3].Trim()
            'height' = [double]$matches[4].Trim()
        }
    }

    # Handle Transform2D
    if ($trimmed -match '^Transform2D\s*\(\s*([^)]+)\s*\)$') {
        $values = $matches[1] -split ',' | ForEach-Object { [double]$_.Trim() }
        return @{
            '__type' = 'Transform2D'
            'values' = $values
        }
    }

    # Handle arrays [...]
    if ($trimmed -match '^\[(.*)\]$' -and -not $trimmed.StartsWith('[' + [char]0x0A)) {
        $content = $matches[1]
        if ([string]::IsNullOrWhiteSpace($content)) {
            return @()
        }
        # Split by comma but handle nested structures
        $items = @()
        $current = ''
        $depth = 0
        for ($i = 0; $i -lt $content.Length; $i++) {
            $char = $content[$i]
            if ($char -eq '(' -or $char -eq '[' -or $char -eq '{') {
                $depth++
            }
            elseif ($char -eq ')' -or $char -eq ']' -or $char -eq '}') {
                $depth--
            }
            
            if ($char -eq ',' -and $depth -eq 0) {
                $items += (ConvertFrom-GodotValue -Value $current.Trim())
                $current = ''
            }
            else {
                $current += $char
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($current)) {
            $items += (ConvertFrom-GodotValue -Value $current.Trim())
        }
        return $items
    }

    # Handle dictionaries {}
    if ($trimmed -match '^\{(.*)\}$' -and -not $trimmed.StartsWith('{' + [char]0x0A)) {
        return @{}
    }

    # Return as string if no special handling
    return $trimmed
}

<#
.SYNOPSIS
    Parses key-value pairs from a section body.

.DESCRIPTION
    Extracts property key-value pairs from a section's content lines,
    handling multi-line values and Godot-specific types.

.PARAMETER Lines
    The lines belonging to the section.

.OUTPUTS
    Hashtable containing the parsed properties.
#>
function Read-GodotSectionProperties {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$Lines
    )

    $properties = @{}
    $currentKey = $null
    $currentValue = [System.Text.StringBuilder]::new()
    $inMultiline = $false

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        $trimmed = $line.Trim()

        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith(';') -or $trimmed.StartsWith('#')) {
            continue
        }

        # Check if this is a new property (key = value format)
        if ($trimmed -match '^([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.*)$' -and -not $inMultiline) {
            # Save previous property if exists
            if ($null -ne $currentKey) {
                $properties[$currentKey] = ConvertFrom-GodotValue -Value $currentValue.ToString()
            }

            $currentKey = $matches[1]
            $value = $matches[2]
            [void]$currentValue.Clear()
            [void]$currentValue.Append($value)
        }
        elseif ($null -ne $currentKey) {
            # Continuation of previous value (multi-line)
            [void]$currentValue.AppendLine()
            [void]$currentValue.Append($line)
        }
    }

    # Save last property
    if ($null -ne $currentKey) {
        $properties[$currentKey] = ConvertFrom-GodotValue -Value $currentValue.ToString()
    }

    return $properties
}

<#
.SYNOPSIS
    Parses a section header into its type and attributes.

.DESCRIPTION
    Extracts the section type and key-value attributes from a Godot section header.

.PARAMETER Header
    The section header line (e.g., "[node name="Main" type="Node2D"]").

.OUTPUTS
    Hashtable with 'type' and 'attributes' keys.
#>
function Read-GodotSectionHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Header
    )

    $result = @{
        type = ''
        attributes = @{}
    }

    # Match section header: [type attr1="value1" attr2="value2"]
    if ($Header -match '^\[([a-zA-Z_][a-zA-Z0-9_]*)(?:\s+(.*))?\]$') {
        $result.type = $matches[1]
        $attrString = if ($matches.Count -gt 2) { $matches[2] } else { '' }

        if (-not [string]::IsNullOrWhiteSpace($attrString)) {
            # Parse attributes using regex
            $pattern = '([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(?:("(?:[^"\\]|\\.)*")|([^\s"]+))'
            $matches = [regex]::Matches($attrString, $pattern)
            
            foreach ($match in $matches) {
                $key = $match.Groups[1].Value
                $value = if ($match.Groups[2].Success) {
                    # Quoted string - remove quotes and unescape
                    $match.Groups[2].Value.Trim('"').Replace('\"', '"').Replace('\\', '\')
                }
                else {
                    # Unquoted value
                    $match.Groups[3].Value
                }
                $result.attributes[$key] = $value
            }
        }
    }

    return $result
}

<#
.SYNOPSIS
    Reads and sections a Godot file into individual sections.

.DESCRIPTION
    Parses the file content and splits it into sections based on section headers.

.PARAMETER Content
    The file content to parse.

.OUTPUTS
    Array of hashtables, each representing a section with header and body lines.
#>
function Read-GodotFileSections {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $sections = @()
    $currentSection = $null
    $bodyLines = [System.Collections.Generic.List[string]]::new()

    $lines = $Content -split "`r?`n"

    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        # Check if this is a section header
        if ($trimmed -match '^\[[a-zA-Z_][a-zA-Z0-9_]*') {
            # Save previous section if exists
            if ($null -ne $currentSection) {
                $currentSection.body = $bodyLines.ToArray()
                $sections += $currentSection
            }

            # Start new section
            $headerInfo = Read-GodotSectionHeader -Header $trimmed
            $currentSection = @{
                header = $headerInfo
                body = @()
            }
            [void]$bodyLines.Clear()
        }
        elseif ($null -ne $currentSection) {
            [void]$bodyLines.Add($line)
        }
    }

    # Save last section
    if ($null -ne $currentSection) {
        $currentSection.body = $bodyLines.ToArray()
        $sections += $currentSection
    }

    return $sections
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Parses a Godot scene file (.tscn) and returns structured data.

.DESCRIPTION
    Main parser for Godot scene files. Extracts all sections including gd_scene header,
    ext_resource, sub_resource, node, and connection sections.
    Supports both Godot 3 (format=2) and Godot 4 (format=3) file formats.

.PARAMETER FilePath
    Path to the .tscn file to parse.

.PARAMETER Content
    The file content to parse. Alternative to FilePath.

.OUTPUTS
    Hashtable containing the parsed scene data:
    - sceneType: "scene"
    - filePath: The input file path
    - loadSteps: Number of load steps from header
    - formatVersion: Format version (2 or 3)
    - uid: Unique identifier (Godot 4)
    - extResources: Array of external resource references
    - subResources: Array of sub-resource definitions
    - nodes: Array of node definitions
    - connections: Array of signal connections

.EXAMPLE
    $scene = Invoke-GodotSceneParse -FilePath "res://main.tscn"
    $scene.nodes | Where-Object { $_.type -eq "CharacterBody2D" }

.EXAMPLE
    $content = Get-Content "player.tscn" -Raw
    $scene = Invoke-GodotSceneParse -Content $content
#>
function Invoke-GodotSceneParse {
    [CmdletBinding(DefaultParameterSetName = 'File')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'File', Position = 0)]
        [string]$FilePath,

        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )

    # Get content from file or parameter
    if ($PSCmdlet.ParameterSetName -eq 'File') {
        if (-not (Test-Path -Path $FilePath)) {
            throw "File not found: $FilePath"
        }
        $Content = Get-Content -Path $FilePath -Raw -Encoding UTF8
        $actualFilePath = (Resolve-Path -Path $FilePath).Path
    }
    else {
        $actualFilePath = 'inline'
    }

    # Initialize result
    $result = @{
        sceneType = 'scene'
        filePath = $actualFilePath
        loadSteps = 0
        formatVersion = 3
        uid = $null
        extResources = @()
        subResources = @()
        nodes = @()
        connections = @()
    }

    # Parse sections
    $sections = Read-GodotFileSections -Content $Content

    foreach ($section in $sections) {
        $sectionType = $section.header.type
        $attrs = $section.header.attributes

        switch ($sectionType) {
            'gd_scene' {
                if ($attrs.ContainsKey('load_steps')) {
                    $result.loadSteps = [int]$attrs['load_steps']
                }
                if ($attrs.ContainsKey('format')) {
                    $result.formatVersion = [int]$attrs['format']
                }
                if ($attrs.ContainsKey('uid')) {
                    $result.uid = $attrs['uid']
                }
            }

            'ext_resource' {
                $resource = @{
                    id = $attrs['id']
                    type = $attrs['type']
                    path = $attrs['path']
                }
                if ($attrs.ContainsKey('uid')) {
                    $resource.uid = $attrs['uid']
                }
                $result.extResources += $resource
            }

            'sub_resource' {
                $resource = @{
                    id = $attrs['id']
                    type = $attrs['type']
                    properties = Read-GodotSectionProperties -Lines $section.body
                }
                $result.subResources += $resource
            }

            'node' {
                $node = @{
                    name = $attrs['name']
                    type = $attrs['type']
                    parent = if ($attrs.ContainsKey('parent')) { $attrs['parent'] } else { $null }
                    properties = Read-GodotSectionProperties -Lines $section.body
                }
                if ($attrs.ContainsKey('instance')) {
                    $node.instance = $attrs['instance']
                }
                if ($attrs.ContainsKey('index')) {
                    $node.index = [int]$attrs['index']
                }
                if ($attrs.ContainsKey('groups')) {
                    $node.groups = $attrs['groups'] -split ',' | ForEach-Object { $_.Trim() }
                }
                $result.nodes += $node
            }

            'connection' {
                $connection = @{
                    signal = $attrs['signal']
                    from = $attrs['from']
                    to = $attrs['to']
                    method = $attrs['method']
                }
                if ($attrs.ContainsKey('flags')) {
                    $connection.flags = [int]$attrs['flags']
                }
                if ($attrs.ContainsKey('binds')) {
                    # Parse binds array
                    $bindsStr = $attrs['binds']
                    if ($bindsStr -match '^\[(.*)\]$') {
                        $bindsContent = $matches[1]
                        if ([string]::IsNullOrWhiteSpace($bindsContent)) {
                            $connection.binds = @()
                        }
                        else {
                            $connection.binds = $bindsContent -split ',' | ForEach-Object { 
                                ConvertFrom-GodotValue -Value $_.Trim() 
                            }
                        }
                    }
                }
                $result.connections += $connection
            }
        }
    }

    return $result
}

<#
.SYNOPSIS
    Extracts the complete node hierarchy from a parsed Godot scene.

.DESCRIPTION
    Takes the output of Invoke-GodotSceneParse and returns the node tree structure.
    Optionally builds a parent-child hierarchy representation.

.PARAMETER SceneData
    The parsed scene data from Invoke-GodotSceneParse.

.PARAMETER BuildHierarchy
    If specified, builds a tree structure with children nested under parents.

.OUTPUTS
    Array of node objects, or hierarchical tree if BuildHierarchy is specified.

.EXAMPLE
    $scene = Invoke-GodotSceneParse -FilePath "main.tscn"
    Get-SceneNodeHierarchy -SceneData $scene

.EXAMPLE
    $scene = Invoke-GodotSceneParse -FilePath "main.tscn"
    Get-SceneNodeHierarchy -SceneData $scene -BuildHierarchy
#>
function Get-SceneNodeHierarchy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$SceneData,

        [switch]$BuildHierarchy
    )

    process {
        $nodes = $SceneData.nodes

        if (-not $BuildHierarchy) {
            return $nodes
        }

        # Build hierarchical structure
        $nodeDict = @{}
        $rootNode = $null
        
        # First pass: identify root node and build dictionary
        foreach ($node in $nodes) {
            $node.children = @()
            $nodeDict[$node.name] = $node
            # Node with no parent is the root
            if ($null -eq $node.parent -or $node.parent -eq '') {
                $rootNode = $node
            }
        }

        # Second pass: build hierarchy
        foreach ($node in $nodes) {
            if ($null -eq $node.parent -or $node.parent -eq '') {
                continue  # Skip root node
            }

            # Resolve parent path
            $parentPath = $node.parent
            $parentName = if ($parentPath -eq '.') {
                # "." means direct child of the root node
                $rootNode.name
            }
            else {
                # Get the last component of the path (e.g., "Player/Sprite" -> "Sprite")
                ($parentPath -split '/')[-1]
            }

            if ($parentName -and $nodeDict.ContainsKey($parentName)) {
                $parent = $nodeDict[$parentName]
                $parent.children += $node
            }
        }

        return @(, @($rootNode))
    }
}

<#
.SYNOPSIS
    Extracts all signal connections from a parsed Godot scene.

.DESCRIPTION
    Takes the output of Invoke-GodotSceneParse and returns signal connection data.
    Can filter by source node, target node, or signal name.

.PARAMETER SceneData
    The parsed scene data from Invoke-GodotSceneParse.

.PARAMETER FromNode
    Filter by source node path.

.PARAMETER ToNode
    Filter by target node path.

.PARAMETER SignalName
    Filter by signal name.

.OUTPUTS
    Array of connection objects matching the filters.

.EXAMPLE
    $scene = Invoke-GodotSceneParse -FilePath "main.tscn"
    Get-SceneSignalConnections -SceneData $scene

.EXAMPLE
    $scene = Invoke-GodotSceneParse -FilePath "main.tscn"
    Get-SceneSignalConnections -SceneData $scene -FromNode "Player" -SignalName "health_changed"
#>
function Get-SceneSignalConnections {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$SceneData,

        [string]$FromNode,

        [string]$ToNode,

        [string]$SignalName
    )

    process {
        $result = [System.Collections.Generic.List[hashtable]]::new()
        
        foreach ($conn in $SceneData.connections) {
            if ($FromNode -and $conn.from -ne $FromNode) { continue }
            if ($ToNode -and $conn.to -ne $ToNode) { continue }
            if ($SignalName -and $conn.signal -ne $SignalName) { continue }
            $result.Add($conn)
        }

        return ,$result.ToArray()
    }
}

<#
.SYNOPSIS
    Extracts external and sub-resource references from a parsed Godot scene.

.DESCRIPTION
    Takes the output of Invoke-GodotSceneParse and returns resource reference data.
    Can filter by resource type or ID.

.PARAMETER SceneData
    The parsed scene data from Invoke-GodotSceneParse.

.PARAMETER ResourceType
    Filter by resource type (e.g., "Script", "Texture2D", "PackedScene").

.PARAMETER ResourceId
    Filter by resource ID.

.PARAMETER IncludeExternal
    Include external resources in results. Default is true.

.PARAMETER IncludeSubResources
    Include sub-resources in results. Default is true.

.OUTPUTS
    Array of resource reference objects.

.EXAMPLE
    $scene = Invoke-GodotSceneParse -FilePath "main.tscn"
    Get-SceneResourceRefs -SceneData $scene

.EXAMPLE
    $scene = Invoke-GodotSceneParse -FilePath "main.tscn"
    Get-SceneResourceRefs -SceneData $scene -ResourceType "Script"

.EXAMPLE
    $scene = Invoke-GodotSceneParse -FilePath "main.tscn"
    Get-SceneResourceRefs -SceneData $scene -ResourceId "1_x5k2a"
#>
function Get-SceneResourceRefs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$SceneData,

        [string]$ResourceType,

        [string]$ResourceId,

        [bool]$IncludeExternal = $true,

        [bool]$IncludeSubResources = $true
    )

    process {
        $result = [System.Collections.Generic.List[hashtable]]::new()

        if ($IncludeExternal) {
            foreach ($res in $SceneData.extResources) {
                if ($ResourceType -and $res.type -ne $ResourceType) { continue }
                if ($ResourceId -and $res.id -ne $ResourceId) { continue }

                $resource = [hashtable]::new($res)
                $resource['__resourceKind'] = 'external'
                $result.Add($resource)
            }
        }

        if ($IncludeSubResources) {
            foreach ($res in $SceneData.subResources) {
                if ($ResourceType -and $res.type -ne $ResourceType) { continue }
                if ($ResourceId -and $res.id -ne $ResourceId) { continue }

                $resource = [hashtable]::new($res)
                $resource['__resourceKind'] = 'sub'
                $result.Add($resource)
            }
        }

        return ,$result.ToArray()
    }
}

<#
.SYNOPSIS
    Parses a Godot resource file (.tres) and returns structured data.

.DESCRIPTION
    Parser for Godot resource files. Extracts the gd_resource header and all
    resource sections including ext_resource, sub_resource, and resource properties.
    Supports both Godot 3 (format=2) and Godot 4 (format=3) file formats.

.PARAMETER FilePath
    Path to the .tres file to parse.

.PARAMETER Content
    The file content to parse. Alternative to FilePath.

.OUTPUTS
    Hashtable containing the parsed resource data:
    - sceneType: "resource"
    - filePath: The input file path
    - loadSteps: Number of load steps from header
    - formatVersion: Format version (2 or 3)
    - uid: Unique identifier (Godot 4)
    - resourceType: The main resource type
    - resourceClass: The resource class name
    - extResources: Array of external resource references
    - subResources: Array of sub-resource definitions
    - properties: Hashtable of resource properties

.EXAMPLE
    $resource = Invoke-GodotResourceParse -FilePath "res://materials/player.tres"
    $resource.properties.albedo_color

.EXAMPLE
    $content = Get-Content "shader_material.tres" -Raw
    $resource = Invoke-GodotResourceParse -Content $content
#>
function Invoke-GodotResourceParse {
    [CmdletBinding(DefaultParameterSetName = 'File')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'File', Position = 0)]
        [string]$FilePath,

        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )

    # Get content from file or parameter
    if ($PSCmdlet.ParameterSetName -eq 'File') {
        if (-not (Test-Path -Path $FilePath)) {
            throw "File not found: $FilePath"
        }
        $Content = Get-Content -Path $FilePath -Raw -Encoding UTF8
        $actualFilePath = (Resolve-Path -Path $FilePath).Path
    }
    else {
        $actualFilePath = 'inline'
    }

    # Initialize result
    $result = @{
        sceneType = 'resource'
        filePath = $actualFilePath
        loadSteps = 0
        formatVersion = 3
        uid = $null
        resourceType = $null
        resourceClass = $null
        extResources = @()
        subResources = @()
        properties = @{}
    }

    # Parse sections
    $sections = Read-GodotFileSections -Content $Content

    foreach ($section in $sections) {
        $sectionType = $section.header.type
        $attrs = $section.header.attributes

        switch ($sectionType) {
            'gd_resource' {
                if ($attrs.ContainsKey('load_steps')) {
                    $result.loadSteps = [int]$attrs['load_steps']
                }
                if ($attrs.ContainsKey('format')) {
                    $result.formatVersion = [int]$attrs['format']
                }
                if ($attrs.ContainsKey('uid')) {
                    $result.uid = $attrs['uid']
                }
                if ($attrs.ContainsKey('type')) {
                    $result.resourceType = $attrs['type']
                }
            }

            'ext_resource' {
                $resource = @{
                    id = $attrs['id']
                    type = $attrs['type']
                    path = $attrs['path']
                }
                if ($attrs.ContainsKey('uid')) {
                    $resource.uid = $attrs['uid']
                }
                $result.extResources += $resource
            }

            'sub_resource' {
                $resource = @{
                    id = $attrs['id']
                    type = $attrs['type']
                    properties = Read-GodotSectionProperties -Lines $section.body
                }
                $result.subResources += $resource
            }

            'resource' {
                if ($attrs.ContainsKey('type')) {
                    $result.resourceType = $attrs['type']
                }
                if ($attrs.ContainsKey('script_class')) {
                    $result.resourceClass = $attrs['script_class']
                }
                $result.properties = Read-GodotSectionProperties -Lines $section.body
            }
        }
    }

    return $result
}

#endregion

#region Export Module Members

# Only export when loaded as a module (not when dot-sourced)
if ($null -ne $MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Invoke-GodotSceneParse',
        'Get-SceneNodeHierarchy',
        'Get-SceneSignalConnections',
        'Get-SceneResourceRefs',
        'Invoke-GodotResourceParse',
        'ConvertFrom-GodotValue',
        'Read-GodotSectionProperties',
        'Read-GodotSectionHeader',
        'Read-GodotFileSections'
    )
}

#endregion
