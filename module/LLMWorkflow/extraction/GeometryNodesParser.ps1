#requires -Version 5.1
<#
.SYNOPSIS
    Geometry Nodes parser for the LLM Workflow Phase 4 Structured Extraction Pipeline.

.DESCRIPTION
    Parses Blender Geometry Nodes node tree structures from:
    1. Python scripts that define node groups programmatically
    2. Exported JSON/metadata representations of node trees
    3. .blend file text blocks containing node group data

    This module implements the requirements from Section 26.6.2 of the
    canonical document for normalized Geometry Nodes extraction.

.NOTES
    File Name      : GeometryNodesParser.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Blender Support: Blender 3.x, Blender 4.x
#>

Set-StrictMode -Version Latest

# ============================================================================
# Script-level Constants and Node Type Definitions
# ============================================================================

# Input/Output Nodes
$script:InputOutputNodes = @(
    'NodeGroupInput', 'NodeGroupOutput'
)

# Mesh Primitive Nodes
$script:MeshPrimitiveNodes = @(
    'GeometryNodeMeshCircle', 'GeometryNodeMeshCone', 'GeometryNodeMeshCube',
    'GeometryNodeMeshCylinder', 'GeometryNodeMeshGrid', 'GeometryNodeMeshIcoSphere',
    'GeometryNodeMeshLine', 'GeometryNodeMeshPlane', 'GeometryNodeMeshUVSphere'
)

# Point Primitive Nodes
$script:PointPrimitiveNodes = @(
    'GeometryNodePoints', 'GeometryNodeDistributePointsOnFaces', 'GeometryNodeInstanceOnPoints'
)

# Utility Nodes
$script:UtilityNodes = @(
    'ShaderNodeMath', 'ShaderNodeVectorMath', 'ShaderNodeSeparateXYZ', 'ShaderNodeCombineXYZ',
    'ShaderNodeSeparateColor', 'ShaderNodeCombineColor', 'FunctionNodeBooleanMath',
    'FunctionNodeCompare', 'FunctionSwitch', 'ShaderNodeMix'
)

# Attribute Nodes
$script:AttributeNodes = @(
    'GeometryNodeAttributeStatistic', 'GeometryNodeDomainSize', 'FunctionNodeFieldAtIndex',
    'GeometryNodeSampleIndex'
)

# Geometry Operation Nodes
$script:GeometryOperationNodes = @(
    'GeometryNodeJoinGeometry', 'GeometryNodeMergeByDistance', 'GeometryNodeExtrudeMesh',
    'GeometryNodeSubdivisionSurface', 'GeometryNodeTriangulate'
)

# Material/Rendering Nodes
$script:MaterialNodes = @(
    'GeometryNodeSetMaterial', 'GeometryNodeMaterialSelection'
)

# All known node types combined
$script:KnownNodeTypes = $script:InputOutputNodes + $script:MeshPrimitiveNodes + 
                         $script:PointPrimitiveNodes + $script:UtilityNodes + 
                         $script:AttributeNodes + $script:GeometryOperationNodes + 
                         $script:MaterialNodes + @(
    'GeometryNodeSetPosition', 'GeometryNodeSetNormal', 'GeometryNodeTransform',
    'GeometryNodeSeparateGeometry', 'GeometryNodeDeleteGeometry',
    'GeometryNodeRealizeInstances', 'GeometryNodeSeparateComponents',
    'FunctionNodeInputVector', 'FunctionNodeInputInt', 'FunctionNodeInputFloat',
    'FunctionNodeInputBool', 'FunctionNodeInputColor', 'FunctionNodeInputString',
    'FunctionNodeInputRotation', 'GeometryNodeInputPosition', 'GeometryNodeInputNormal',
    'GeometryNodeInputIndex', 'GeometryNodeViewer', 'GeometryNodeSwitch',
    'ShaderNodeTexNoise', 'ShaderNodeTexVoronoi', 'ShaderNodeTexMusgrave',
    'NodeReroute', 'NodeFrame'
)

# ============================================================================
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
    Main parser for Geometry Nodes - entry point for the extraction pipeline.

.DESCRIPTION
    Parses Geometry Nodes from Python scripts, JSON exports, or .blend text blocks
    and returns a normalized structure according to the Phase 4 schema.
#>
function Invoke-GeometryNodesParse {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$InputObject,

        [Parameter()]
        [ValidateSet('Auto', 'Python', 'Json', 'BlendText')]
        [string]$InputType = 'Auto',

        [Parameter()]
        [string]$BlenderVersion = '4.x',

        [Parameter()]
        [string]$SourceFile = ''
    )

    begin {
        Write-Verbose "[GeometryNodesParser] Starting Geometry Nodes parse operation"
        $results = @()
    }

    process {
        try {
            $content = $InputObject
            $detectedType = $InputType
            $actualSourceFile = $SourceFile

            if ($detectedType -eq 'Auto') {
                $detectedType = Detect-GeometryNodesInputType -Content $content
                Write-Verbose "[GeometryNodesParser] Auto-detected input type: $detectedType"
            }

            if ($detectedType -eq 'File' -or ($content -match '\.(py|json|txt|blend)$' -and (Test-Path -LiteralPath $content -ErrorAction SilentlyContinue))) {
                if (Test-Path -LiteralPath $content -PathType Leaf) {
                    $actualSourceFile = Resolve-Path -LiteralPath $content | Select-Object -ExpandProperty Path
                    $content = Get-Content -LiteralPath $actualSourceFile -Raw -Encoding UTF8
                    $detectedType = Detect-GeometryNodesInputType -Content $content
                }
            }

            $parsedData = switch ($detectedType) {
                'Json' { Parse-GeometryNodesFromJson -JsonContent $content }
                'Python' { Parse-GeometryNodesFromPython -PythonContent $content }
                'BlendText' { Parse-GeometryNodesFromBlendText -TextContent $content }
                default { Parse-GeometryNodesFromPython -PythonContent $content }
            }

            $result = Get-NodeTreeStructure -ParsedData $parsedData -SourceFile $actualSourceFile
            $result['blenderVersion'] = $BlenderVersion
            $result['extractionTimestamp'] = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)

            $results += $result
        }
        catch {
            Write-Error "[GeometryNodesParser] Failed to parse Geometry Nodes: $_"
            throw
        }
    }

    end {
        if ($results.Count -eq 1) {
            return $results[0]
        }
        return $results
    }
}

<#
.SYNOPSIS
    Extracts the complete node tree structure with nodes, links, and interface.
#>
function Get-NodeTreeStructure {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$ParsedData,

        [Parameter()]
        [string]$SourceFile = ''
    )

    process {
        $nodeGroup = if ($ParsedData.ContainsKey('nodeGroups') -and $ParsedData.nodeGroups.Count -gt 0) {
            $ParsedData.nodeGroups[0]
        }
        else {
            @{
                name = "Unknown"
                type = "GeometryNodeTree"
                nodes = @()
                links = @()
                inputs = @()
                outputs = @()
            }
        }

        $normalizedNodes = @()
        $nodeIdMap = @{}
        $nodeCounter = 0

        foreach ($node in $nodeGroup.nodes) {
            $nodeCounter++
            $nodeId = "node_{0:D3}" -f $nodeCounter

            if ($node.ContainsKey('variableName')) {
                $nodeIdMap[$node.variableName] = $nodeId
            }
            if ($node.ContainsKey('id')) {
                $nodeIdMap[$node.id] = $nodeId
            }

            $nodeInputs = @()
            if ($node.ContainsKey('inputs')) {
                foreach ($key in $node.inputs.Keys) {
                    $input = $node.inputs[$key]
                    $nodeInputs += @{
                        identifier = $key
                        name = if ($input.ContainsKey('name')) { $input.name } else { $key }
                        type = if ($input.ContainsKey('type')) { $input.type } else { 'NodeSocketFloat' }
                        defaultValue = if ($input.ContainsKey('defaultValue')) { $input.defaultValue } else { $null }
                        isLinked = [bool]($input.ContainsKey('isLinked') -and $input.isLinked)
                    }
                }
            }

            $nodeOutputs = @()
            if ($node.ContainsKey('outputs')) {
                foreach ($key in $node.outputs.Keys) {
                    $output = $node.outputs[$key]
                    $nodeOutputs += @{
                        identifier = $key
                        name = if ($output.ContainsKey('name')) { $output.name } else { $key }
                        type = if ($output.ContainsKey('type')) { $output.type } else { 'NodeSocketFloat' }
                        defaultValue = if ($output.ContainsKey('defaultValue')) { $output.defaultValue } else { $null }
                        isLinked = [bool]($output.ContainsKey('isLinked') -and $output.isLinked)
                    }
                }
            }

            $parameters = @{}
            if ($node.ContainsKey('operation') -and $node.operation) {
                $parameters['operation'] = $node.operation
            }
            if ($node.ContainsKey('dataType') -and $node.dataType) {
                $parameters['dataType'] = $node.dataType
            }
            if ($node.ContainsKey('properties')) {
                foreach ($prop in $node.properties.Keys) {
                    $parameters[$prop] = $node.properties[$prop]
                }
            }

            $normalizedNode = @{
                id = $nodeId
                type = if ($node.ContainsKey('type')) { $node.type } else { 'Unknown' }
                name = if ($node.ContainsKey('name')) { $node.name } else { $nodeId }
                location = if ($node.ContainsKey('location')) { $node.location } else { @(0, 0) }
                inputs = $nodeInputs
                outputs = $nodeOutputs
                parameters = $parameters
                width = if ($node.ContainsKey('width')) { $node.width } else { 150 }
                height = if ($node.ContainsKey('height')) { $node.height } else { 100 }
                hide = if ($node.ContainsKey('hide')) { $node.hide } else { $false }
                parent = if ($node.ContainsKey('parent')) { $node.parent } else { $null }
            }

            $normalizedNodes += $normalizedNode
        }

        $normalizedLinks = @()
        foreach ($link in $nodeGroup.links) {
            $fromNodeId = if ($nodeIdMap.ContainsKey($link.fromNode)) { $nodeIdMap[$link.fromNode] } else { $link.fromNode }
            $toNodeId = if ($nodeIdMap.ContainsKey($link.toNode)) { $nodeIdMap[$link.toNode] } else { $link.toNode }

            $normalizedLinks += @{
                fromNode = $fromNodeId
                fromSocket = $link.fromSocket
                toNode = $toNodeId
                toSocket = $link.toSocket
            }
        }

        $nodeSocketLinks = @{}
        foreach ($link in $normalizedLinks) {
            $key = "$($link.fromNode).$($link.fromSocket)"
            $nodeSocketLinks[$key] = $true
            $key = "$($link.toNode).$($link.toSocket)"
            $nodeSocketLinks[$key] = $true
        }

        for ($i = 0; $i -lt $normalizedNodes.Count; $i++) {
            for ($j = 0; $j -lt $normalizedNodes[$i].inputs.Count; $j++) {
                $inputKey = "$($normalizedNodes[$i].id).$($normalizedNodes[$i].inputs[$j].identifier)"
                $normalizedNodes[$i].inputs[$j].isLinked = $nodeSocketLinks.ContainsKey($inputKey)
            }
            for ($j = 0; $j -lt $normalizedNodes[$i].outputs.Count; $j++) {
                $outputKey = "$($normalizedNodes[$i].id).$($normalizedNodes[$i].outputs[$j].identifier)"
                $normalizedNodes[$i].outputs[$j].isLinked = $nodeSocketLinks.ContainsKey($outputKey)
            }
        }

        $interface = @{
            inputItems = @()
            outputItems = @()
        }

        foreach ($input in $nodeGroup.inputs) {
            $interface.inputItems += @{
                name = if ($input.ContainsKey('name')) { $input.name } else { '' }
                type = if ($input.ContainsKey('type')) { $input.type } else { 'NodeSocketFloat' }
                defaultValue = if ($input.ContainsKey('defaultValue')) { $input.defaultValue } else { $null }
                minValue = if ($input.ContainsKey('minValue')) { $input.minValue } else { $null }
                maxValue = if ($input.ContainsKey('maxValue')) { $input.maxValue } else { $null }
            }
        }

        foreach ($output in $nodeGroup.outputs) {
            $interface.outputItems += @{
                name = if ($output.ContainsKey('name')) { $output.name } else { '' }
                type = if ($output.ContainsKey('type')) { $output.type } else { 'NodeSocketGeometry' }
            }
        }

        $result = @{
            nodeTreeType = if ($nodeGroup.ContainsKey('type')) { $nodeGroup.type } else { 'GeometryNodeTree' }
            name = if ($nodeGroup.ContainsKey('name')) { $nodeGroup.name } else { 'Unknown' }
            nodes = $normalizedNodes
            links = $normalizedLinks
            inputs = $nodeGroup.inputs | ForEach-Object {
                $inputItem = $_
                @{
                    name = if ($inputItem.ContainsKey('name')) { $inputItem.name } else { '' }
                    type = if ($inputItem.ContainsKey('type')) { $inputItem.type } else { 'NodeSocketFloat' }
                    defaultValue = if ($inputItem.ContainsKey('defaultValue')) { $inputItem.defaultValue } else { $null }
                }
            }
            outputs = $nodeGroup.outputs | ForEach-Object {
                $outputItem = $_
                @{
                    name = if ($outputItem.ContainsKey('name')) { $outputItem.name } else { '' }
                    type = if ($outputItem.ContainsKey('type')) { $outputItem.type } else { 'NodeSocketGeometry' }
                }
            }
            interface = $interface
            sourceFile = $SourceFile
        }

        return $result
    }
}

<#
.SYNOPSIS
    Extracts group input interface definitions.
#>
function Get-NodeGroupInputs {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$ParsedData
    )

    process {
        $inputs = @()
        
        if ($ParsedData.ContainsKey('inputs')) {
            $inputs = $ParsedData.inputs
        }
        elseif ($ParsedData.ContainsKey('interface') -and $ParsedData.interface -and $ParsedData.interface.ContainsKey('inputItems')) {
            $inputs = $ParsedData.interface.inputItems
        }

        return $inputs | ForEach-Object {
            $inputItem = $_
            @{
                name = if ($inputItem.ContainsKey('name')) { $inputItem.name } else { '' }
                type = if ($inputItem.ContainsKey('type')) { $inputItem.type } else { 'NodeSocketFloat' }
                defaultValue = if ($inputItem.ContainsKey('defaultValue')) { $inputItem.defaultValue } else { $null }
                minValue = if ($inputItem.ContainsKey('minValue')) { $inputItem.minValue } else { $null }
                maxValue = if ($inputItem.ContainsKey('maxValue')) { $inputItem.maxValue } else { $null }
                description = if ($inputItem.ContainsKey('description')) { $inputItem.description } else { '' }
            }
        }
    }
}

<#
.SYNOPSIS
    Extracts group output interface definitions.
#>
function Get-NodeGroupOutputs {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$ParsedData
    )

    process {
        $outputs = @()
        
        if ($ParsedData.ContainsKey('outputs')) {
            $outputs = $ParsedData.outputs
        }
        elseif ($ParsedData.ContainsKey('interface') -and $ParsedData.interface -and $ParsedData.interface.ContainsKey('outputItems')) {
            $outputs = $ParsedData.interface.outputItems
        }

        return $outputs | ForEach-Object {
            $outputItem = $_
            @{
                name = if ($outputItem.ContainsKey('name')) { $outputItem.name } else { '' }
                type = if ($outputItem.ContainsKey('type')) { $outputItem.type } else { 'NodeSocketGeometry' }
                description = if ($outputItem.ContainsKey('description')) { $outputItem.description } else { '' }
            }
        }
    }
}

<#
.SYNOPSIS
    Extracts node-specific parameters.
#>
function Get-NodeParameters {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$ParsedData,

        [Parameter()]
        [string]$NodeId = ''
    )

    process {
        $nodes = if ($ParsedData.ContainsKey('nodes')) { $ParsedData.nodes } else { @() }

        if (-not [string]::IsNullOrEmpty($NodeId)) {
            $node = $nodes | Where-Object { $_.id -eq $NodeId } | Select-Object -First 1
            if ($node) {
                return @{
                    nodeId = $node.id
                    nodeType = $node.type
                    nodeName = $node.name
                    parameters = $node.parameters
                }
            }
            return $null
        }

        return $nodes | ForEach-Object {
            @{
                nodeId = $_.id
                nodeType = $_.type
                nodeName = $_.name
                parameters = $_.parameters
            }
        }
    }
}

<#
.SYNOPSIS
    Converts the parsed node tree structure to JSON.
#>
function Convert-NodeTreeToJson {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$ParsedData,

        [Parameter()]
        [int]$Depth = 100,

        [Parameter()]
        [switch]$Compress
    )

    process {
        try {
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                $jsonParams = @{ Depth = $Depth }
                if ($Compress) { $jsonParams['Compress'] = $true }
                return $ParsedData | ConvertTo-Json @jsonParams
            }
            else {
                return ConvertTo-JsonCompatible -InputObject $ParsedData -Compress:$Compress
            }
        }
        catch {
            Write-Error "[Convert-NodeTreeToJson] Failed to convert to JSON: $_"
            throw
        }
    }
}

<#
.SYNOPSIS
    Validates node tree link integrity.
#>
function Test-NodeTreeConnectivity {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$ParsedData,

        [Parameter()]
        [switch]$CheckOrphanedNodes
    )

    process {
        $isValid = $true
        $errors = @()
        $warnings = @()

        $nodes = if ($ParsedData.ContainsKey('nodes')) { $ParsedData.nodes } else { @() }
        $links = if ($ParsedData.ContainsKey('links')) { $ParsedData.links } else { @() }

        $nodeMap = @{}
        $nodeSocketMap = @{}
        foreach ($node in $nodes) {
            $nodeMap[$node.id] = $node
            $nodeSocketMap[$node.id] = @{
                inputs = @()
                outputs = @()
            }
            foreach ($input in $node.inputs) {
                $nodeSocketMap[$node.id].inputs += $input.identifier
            }
            foreach ($output in $node.outputs) {
                $nodeSocketMap[$node.id].outputs += $output.identifier
            }
        }

        $connectedNodes = @{}
        foreach ($link in $links) {
            if (-not $nodeMap.ContainsKey($link.fromNode)) {
                $isValid = $false
                $errors += "Link references non-existent fromNode: $($link.fromNode)"
            }
            else {
                $connectedNodes[$link.fromNode] = $true
            }

            if (-not $nodeMap.ContainsKey($link.toNode)) {
                $isValid = $false
                $errors += "Link references non-existent toNode: $($link.toNode)"
            }
            else {
                $connectedNodes[$link.toNode] = $true
            }

            if ($nodeMap.ContainsKey($link.fromNode)) {
                if ($nodeSocketMap[$link.fromNode].outputs -notcontains $link.fromSocket) {
                    $warnings += "Link references unknown output socket '$($link.fromSocket)' on node '$($link.fromNode)'"
                }
            }
            if ($nodeMap.ContainsKey($link.toNode)) {
                if ($nodeSocketMap[$link.toNode].inputs -notcontains $link.toSocket) {
                    $warnings += "Link references unknown input socket '$($link.toSocket)' on node '$($link.toNode)'"
                }
            }
        }

        $orphanedNodes = @()
        if ($CheckOrphanedNodes) {
            foreach ($node in $nodes) {
                if (-not $connectedNodes.ContainsKey($node.id)) {
                    if ($node.type -notmatch 'NodeGroupInput|NodeGroupOutput|NodeReroute|NodeFrame') {
                        $orphanedNodes += $node.id
                    }
                }
            }
        }

        $hasGroupInput = $nodes | Where-Object { $_.type -eq 'NodeGroupInput' }
        $hasGroupOutput = $nodes | Where-Object { $_.type -eq 'NodeGroupOutput' }

        if (-not $hasGroupInput) {
            $warnings += "Node group has no Group Input node"
        }
        if (-not $hasGroupOutput) {
            $warnings += "Node group has no Group Output node"
        }

        return @{
            isValid = $isValid
            isValidStructure = ($errors.Count -eq 0)
            hasGroupInput = ($hasGroupInput -ne $null)
            hasGroupOutput = ($hasGroupOutput -ne $null)
            totalNodes = $nodes.Count
            totalLinks = $links.Count
            connectedNodes = $connectedNodes.Count
            orphanedNodes = $orphanedNodes
            orphanedNodeCount = $orphanedNodes.Count
            errorCount = $errors.Count
            warningCount = $warnings.Count
            errors = $errors
            warnings = $warnings
        }
    }
}

# ============================================================================
# Internal Helper Functions
# ============================================================================

function Detect-GeometryNodesInputType {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $trimmed = $Content.Trim()
    if (($trimmed.StartsWith('{') -and $trimmed.EndsWith('}')) -or
        ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']'))) {
        try {
            $null = $trimmed | ConvertFrom-Json -ErrorAction Stop
            return 'Json'
        }
        catch {
        }
    }

    if ($Content -match '(import bpy|from bpy|bpy\.data\.node_groups|def create.*node_group|GeometryNodeTree|\.nodes\.new)') {
        return 'Python'
    }

    if ($Content -match '^(# Blender|# Name:|# Type:)' -or 
        $Content -match '"nodes":\s*\[') {
        return 'BlendText'
    }

    return 'Python'
}

function Parse-GeometryNodesFromJson {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JsonContent
    )

    try {
        $data = $JsonContent | ConvertFrom-Json -Depth 100

        $nodeGroup = @{
            name = if ($data.PSObject.Properties.Name -contains 'name') { $data.name } else { "Imported" }
            type = if ($data.PSObject.Properties.Name -contains 'nodeTreeType') { $data.nodeTreeType } else { "GeometryNodeTree" }
            nodes = @()
            links = @()
            inputs = @()
            outputs = @()
        }

        if ($data.PSObject.Properties.Name -contains 'nodes') {
            foreach ($node in $data.nodes) {
                $parsedNode = @{
                    id = if ($node.PSObject.Properties.Name -contains 'id') { $node.id } else { [Guid]::NewGuid().ToString("N") }
                    type = $node.type
                    name = if ($node.PSObject.Properties.Name -contains 'name') { $node.name } else { $node.type }
                    location = if ($node.PSObject.Properties.Name -contains 'location') { $node.location } else { @(0, 0) }
                    width = if ($node.PSObject.Properties.Name -contains 'width') { $node.width } else { 150 }
                    height = if ($node.PSObject.Properties.Name -contains 'height') { $node.height } else { 100 }
                    hide = if ($node.PSObject.Properties.Name -contains 'hide') { $node.hide } else { $false }
                    parent = if ($node.PSObject.Properties.Name -contains 'parent') { $node.parent } else { $null }
                    inputs = @{}
                    outputs = @{}
                    properties = @{}
                }

                if ($node.PSObject.Properties.Name -contains 'inputs') {
                    foreach ($input in $node.inputs) {
                        $id = if ($input.PSObject.Properties.Name -contains 'identifier') { $input.identifier } else { $input.name }
                        $parsedNode.inputs[$id] = @{
                            name = $input.name
                            type = $input.type
                            defaultValue = if ($input.PSObject.Properties.Name -contains 'defaultValue') { $input.defaultValue } else { $null }
                            isLinked = if ($input.PSObject.Properties.Name -contains 'isLinked') { $input.isLinked } else { $false }
                        }
                    }
                }

                if ($node.PSObject.Properties.Name -contains 'outputs') {
                    foreach ($output in $node.outputs) {
                        $id = if ($output.PSObject.Properties.Name -contains 'identifier') { $output.identifier } else { $output.name }
                        $parsedNode.outputs[$id] = @{
                            name = $output.name
                            type = $output.type
                            defaultValue = if ($output.PSObject.Properties.Name -contains 'defaultValue') { $output.defaultValue } else { $null }
                            isLinked = if ($output.PSObject.Properties.Name -contains 'isLinked') { $output.isLinked } else { $false }
                        }
                    }
                }

                if ($node.PSObject.Properties.Name -contains 'parameters') {
                    foreach ($prop in $node.parameters.PSObject.Properties) {
                        $parsedNode.properties[$prop.Name] = $prop.Value
                    }
                }

                $nodeGroup.nodes += $parsedNode
            }
        }

        if ($data.PSObject.Properties.Name -contains 'links') {
            foreach ($link in $data.links) {
                $nodeGroup.links += @{
                    fromNode = $link.fromNode
                    fromSocket = $link.fromSocket
                    toNode = $link.toNode
                    toSocket = $link.toSocket
                }
            }
        }

        if ($data.PSObject.Properties.Name -contains 'interface') {
            if ($data.interface.PSObject.Properties.Name -contains 'inputItems') {
                $nodeGroup.inputs = $data.interface.inputItems
            }
            if ($data.interface.PSObject.Properties.Name -contains 'outputItems') {
                $nodeGroup.outputs = $data.interface.outputItems
            }
        }
        if ($data.PSObject.Properties.Name -contains 'inputs') {
            $nodeGroup.inputs = $data.inputs
        }
        if ($data.PSObject.Properties.Name -contains 'outputs') {
            $nodeGroup.outputs = $data.outputs
        }

        return @{
            nodeGroups = @($nodeGroup)
            format = 'json'
        }
    }
    catch {
        throw "Failed to parse JSON content: $_"
    }
}

function Parse-GeometryNodesFromPython {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonContent
    )

    $nodeGroups = @()

    try {
        $ngPattern = 'bpy\.data\.node_groups\.new\s*\(\s*name\s*=\s*["'']([^"'']+)["'']\s*,\s*type\s*=\s*["'']([^"'']+)["'']\s*\)'
        $ngMatches = [regex]::Matches($PythonContent, $ngPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

        if ($ngMatches.Count -eq 0) {
            $ngPattern = 'bpy\.data\.node_groups\.new\s*\(\s*["'']([^"'']+)["'']\s*,\s*["'']([^"'']+)["'']\s*\)'
            $ngMatches = [regex]::Matches($PythonContent, $ngPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
        }

        foreach ($match in $ngMatches) {
            $ngName = $match.Groups[1].Value
            $ngType = $match.Groups[2].Value

            $nodeGroup = @{
                name = $ngName
                type = $ngType
                nodes = @()
                links = @()
                inputs = @()
                outputs = @()
                variables = @{}
            }

            $varPattern = '(\w+)\s*=\s*' + [regex]::Escape($match.Value)
            $varMatch = [regex]::Match($PythonContent, $varPattern)
            if ($varMatch.Success) {
                $nodeGroup.variables['main'] = $varMatch.Groups[1].Value
            }

            $nodeGroups += $nodeGroup
        }

        if ($nodeGroups.Count -eq 0) {
            $funcPattern = 'def\s+(\w+)\s*\([^)]*\)[^:]*:\s*(?:["'']([^"'']*)["'']\s*)?(.*?)(?=\n(?:def\s|class\s|\Z))'
            $funcMatches = [regex]::Matches($PythonContent, $funcPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

            foreach ($funcMatch in $funcMatches) {
                $funcName = $funcMatch.Groups[1].Value
                $funcBody = $funcMatch.Groups[3].Value

                if ($funcBody -match 'node_groups|GeometryNodeTree|bpy\.data|\.nodes\.new') {
                    $nodeGroup = @{
                        name = $funcName
                        type = 'GeometryNodeTree'
                        nodes = @()
                        links = @()
                        inputs = @()
                        outputs = @()
                        variables = @{}
                        functionBody = $funcBody
                    }
                    $nodeGroups += $nodeGroup
                }
            }
        }

        for ($i = 0; $i -lt $nodeGroups.Count; $i++) {
            $ng = $nodeGroups[$i]
            $context = if ($ng.ContainsKey('functionBody')) { $ng.functionBody } else { $PythonContent }
            $ngVar = if ($ng.variables.ContainsKey('main')) { $ng.variables['main'] } else { '' }

            $ng.nodes = Extract-NodesFromPythonContent -Content $context -NodeGroupVariable $ngVar
            $ng.links = Extract-LinksFromPythonContent -Content $context -NodeGroupVariable $ngVar
            $ng.inputs = Extract-GroupInputsFromPythonContent -Content $context -NodeGroupVariable $ngVar
            $ng.outputs = Extract-GroupOutputsFromPythonContent -Content $context -NodeGroupVariable $ngVar

            $nodeGroups[$i] = $ng
        }

        return @{
            nodeGroups = $nodeGroups
            format = 'python'
        }
    }
    catch {
        throw "Failed to parse Python content: $_"
    }
}

function Parse-GeometryNodesFromBlendText {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TextContent
    )

    $trimmed = $TextContent.Trim()
    
    if (($trimmed.StartsWith('{') -and $trimmed.EndsWith('}')) -or
        ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']'))) {
        try {
            return Parse-GeometryNodesFromJson -JsonContent $TextContent
        }
        catch {
        }
    }

    return Parse-GeometryNodesFromPython -PythonContent $TextContent
}

function Extract-NodesFromPythonContent {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter()]
        [string]$NodeGroupVariable = ''
    )

    $nodes = @()
    $nodeCounter = 0

    $nodePattern = '(?m)^(\s*)(\w+)\s*=\s*(?:\w+\.)?nodes\.new\s*\(\s*["'']([^"'']+)["'']\s*\)'
    $matches = [regex]::Matches($Content, $nodePattern)

    foreach ($match in $matches) {
        $nodeCounter++
        $varName = $match.Groups[2].Value
        $nodeType = $match.Groups[3].Value

        $node = @{
            id = "node_{0:D3}" -f $nodeCounter
            variableName = $varName
            name = $varName
            type = $nodeType
            inputs = @{}
            outputs = @{}
            location = @(0, 0)
            width = 150
            height = 100
            hide = $false
            parent = $null
            properties = @{}
        }

        $locationPattern = [regex]::Escape($varName) + '\.location\s*=\s*\(\s*([^,]+)\s*,\s*([^)]+)\s*\)'
        $locMatch = [regex]::Match($Content, $locationPattern)
        if ($locMatch.Success) {
            $x = 0; $y = 0
            [void][double]::TryParse($locMatch.Groups[1].Value.Trim(), [ref]$x)
            [void][double]::TryParse($locMatch.Groups[2].Value.Trim(), [ref]$y)
            $node.location = @($x, $y)
        }

        $namePattern = [regex]::Escape($varName) + '\.name\s*=\s*["'']([^"'']+)["'']'
        $nameMatch = [regex]::Match($Content, $namePattern)
        if ($nameMatch.Success) {
            $node.name = $nameMatch.Groups[1].Value
        }

        $widthPattern = [regex]::Escape($varName) + '\.width\s*=\s*([\d.]+)'
        $widthMatch = [regex]::Match($Content, $widthPattern)
        if ($widthMatch.Success) {
            $node.width = [double]$widthMatch.Groups[1].Value
        }

        $heightPattern = [regex]::Escape($varName) + '\.height\s*=\s*([\d.]+)'
        $heightMatch = [regex]::Match($Content, $heightPattern)
        if ($heightMatch.Success) {
            $node.height = [double]$heightMatch.Groups[1].Value
        }

        $hidePattern = [regex]::Escape($varName) + '\.hide\s*=\s*(True|False)'
        $hideMatch = [regex]::Match($Content, $hidePattern)
        if ($hideMatch.Success) {
            $node.hide = $hideMatch.Groups[1].Value -eq 'True'
        }

        $parentPattern = [regex]::Escape($varName) + '\.parent\s*=\s*(\w+)'
        $parentMatch = [regex]::Match($Content, $parentPattern)
        if ($parentMatch.Success) {
            $node.parent = $parentMatch.Groups[1].Value
        }

        $opPattern = [regex]::Escape($varName) + '\.operation\s*=\s*["'']([^"'']+)["'']'
        $opMatch = [regex]::Match($Content, $opPattern)
        if ($opMatch.Success) {
            $node.operation = $opMatch.Groups[1].Value
        }

        $dtPattern = [regex]::Escape($varName) + '\.data_type\s*=\s*["'']([^"'']+)["'']'
        $dtMatch = [regex]::Match($Content, $dtPattern)
        if ($dtMatch.Success) {
            $node.dataType = $dtMatch.Groups[1].Value
        }

        $inputPattern = [regex]::Escape($varName) + '\.inputs\[(\d+|["'']([^"'']+)["''])\]\.default_value\s*=\s*([^\n]+)'
        $inputMatches = [regex]::Matches($Content, $inputPattern)
        foreach ($inMatch in $inputMatches) {
            $socketRef = if ($inMatch.Groups[2].Success) { $inMatch.Groups[2].Value } else { $inMatch.Groups[1].Value }
            $value = $inMatch.Groups[3].Value.Trim()

            $numValue = $null
            if ([double]::TryParse($value, [ref]$numValue)) {
                $node.inputs[$socketRef] = @{ defaultValue = $numValue; isLinked = $false }
            }
            else {
                $node.inputs[$socketRef] = @{ defaultValue = $value; isLinked = $false }
            }
        }

        $outputPattern = [regex]::Escape($varName) + '\.outputs\[(\d+|["'']([^"'']+)["''])\]\.default_value\s*=\s*([^\n]+)'
        $outputMatches = [regex]::Matches($Content, $outputPattern)
        foreach ($outMatch in $outputMatches) {
            $socketRef = if ($outMatch.Groups[2].Success) { $outMatch.Groups[2].Value } else { $outMatch.Groups[1].Value }
            $value = $outMatch.Groups[3].Value.Trim()

            $numValue = $null
            if ([double]::TryParse($value, [ref]$numValue)) {
                $node.outputs[$socketRef] = @{ defaultValue = $numValue; isLinked = $false }
            }
            else {
                $node.outputs[$socketRef] = @{ defaultValue = $value; isLinked = $false }
            }
        }

        switch -Regex ($nodeType) {
            'MeshGrid' {
                $sxPattern = [regex]::Escape($varName) + '\.inputs\[["'']Size X["'']\]\.default_value\s*=\s*([\d.]+)'
                $sxMatch = [regex]::Match($Content, $sxPattern)
                if ($sxMatch.Success) { $node.properties['sizeX'] = [double]$sxMatch.Groups[1].Value }

                $syPattern = [regex]::Escape($varName) + '\.inputs\[["'']Size Y["'']\]\.default_value\s*=\s*([\d.]+)'
                $syMatch = [regex]::Match($Content, $syPattern)
                if ($syMatch.Success) { $node.properties['sizeY'] = [double]$syMatch.Groups[1].Value }

                $vxPattern = [regex]::Escape($varName) + '\.inputs\[["'']Vertices X["'']\]\.default_value\s*=\s*(\d+)'
                $vxMatch = [regex]::Match($Content, $vxPattern)
                if ($vxMatch.Success) { $node.properties['verticesX'] = [int]$vxMatch.Groups[1].Value }

                $vyPattern = [regex]::Escape($varName) + '\.inputs\[["'']Vertices Y["'']\]\.default_value\s*=\s*(\d+)'
                $vyMatch = [regex]::Match($Content, $vyPattern)
                if ($vyMatch.Success) { $node.properties['verticesY'] = [int]$vyMatch.Groups[1].Value }
            }
            'Mesh(Circle|Cone|Cube|Cylinder|IcoSphere|UVSphere)' {
                $sizePattern = [regex]::Escape($varName) + '\.inputs\[["''](Size|Radius)["'']\]\.default_value\s*=\s*([\d.]+)'
                $sizeMatch = [regex]::Matches($Content, $sizePattern)
                foreach ($m in $sizeMatch) {
                    $node.properties['size'] = [double]$m.Groups[2].Value
                }
            }
            'SubdivisionSurface' {
                $lvlPattern = [regex]::Escape($varName) + '\.inputs\[["'']Level["'']\]\.default_value\s*=\s*(\d+)'
                $lvlMatch = [regex]::Match($Content, $lvlPattern)
                if ($lvlMatch.Success) { $node.properties['level'] = [int]$lvlMatch.Groups[1].Value }
            }
            '(Math|VectorMath)' {
                if (-not $node.ContainsKey('operation')) {
                    $node.operation = 'ADD'
                }
            }
        }

        $nodes += $node
    }

    return $nodes
}

function Extract-LinksFromPythonContent {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter()]
        [string]$NodeGroupVariable = ''
    )

    $links = @()
    $linkCounter = 0

    $linkPattern = '(?:\w+\.)?links\.new\s*\(\s*(\w+)\.outputs\[(\d+|["'']([^"'']*)["''])\]\s*,\s*(\w+)\.inputs\[(\d+|["'']([^"'']*)["''])\]\s*\)'
    $matches = [regex]::Matches($Content, $linkPattern)

    foreach ($match in $matches) {
        $linkCounter++
        $fromNode = $match.Groups[1].Value
        $fromSocket = if ($match.Groups[3].Success) { $match.Groups[3].Value } else { $match.Groups[2].Value }
        $toNode = $match.Groups[4].Value
        $toSocket = if ($match.Groups[6].Success) { $match.Groups[6].Value } else { $match.Groups[5].Value }

        $links += @{
            id = "link_{0:D3}" -f $linkCounter
            fromNode = $fromNode
            fromSocket = $fromSocket
            toNode = $toNode
            toSocket = $toSocket
        }
    }

    return $links
}

function Extract-GroupInputsFromPythonContent {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter()]
        [string]$NodeGroupVariable = ''
    )

    $inputs = @()

    $inputPattern = '\.inputs\.new\s*\(\s*["'']([^"'']+)["'']\s*,\s*["'']([^"'']+)["'']\s*\)'
    $matches = [regex]::Matches($Content, $inputPattern)

    foreach ($match in $matches) {
        $socketType = $match.Groups[1].Value
        $socketName = $match.Groups[2].Value

        $input = @{
            name = $socketName
            type = $socketType
            defaultValue = $null
            minValue = $null
            maxValue = $null
            description = ""
        }

        $subContent = $Content.Substring($match.Index)
        
        $defaultPattern = '^\s*\.inputs\[-1\]\.default_value\s*=\s*([^\n]+)'
        $defaultMatch = [regex]::Match($subContent, $defaultPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if ($defaultMatch.Success) {
            $val = $defaultMatch.Groups[1].Value.Trim()
            $numVal = $null
            if ([double]::TryParse($val, [ref]$numVal)) {
                $input.defaultValue = $numVal
            }
            else {
                $input.defaultValue = $val
            }
        }

        $minPattern = '^\s*\.inputs\[-1\]\.min_value\s*=\s*([\d.-]+)'
        $minMatch = [regex]::Match($subContent, $minPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if ($minMatch.Success) {
            $input.minValue = [double]$minMatch.Groups[1].Value
        }

        $maxPattern = '^\s*\.inputs\[-1\]\.max_value\s*=\s*([\d.-]+)'
        $maxMatch = [regex]::Match($subContent, $maxPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if ($maxMatch.Success) {
            $input.maxValue = [double]$maxMatch.Groups[1].Value
        }

        $inputs += $input
    }

    return $inputs
}

function Extract-GroupOutputsFromPythonContent {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter()]
        [string]$NodeGroupVariable = ''
    )

    $outputs = @()

    $outputPattern = '\.outputs\.new\s*\(\s*["'']([^"'']+)["'']\s*,\s*["'']([^"'']+)["'']\s*\)'
    $matches = [regex]::Matches($Content, $outputPattern)

    foreach ($match in $matches) {
        $socketType = $match.Groups[1].Value
        $socketName = $match.Groups[2].Value

        $outputs += @{
            name = $socketName
            type = $socketType
        }
    }

    return $outputs
}

function ConvertTo-JsonCompatible {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,

        [Parameter()]
        [switch]$Compress,

        [Parameter()]
        [int]$Depth = 10,

        [Parameter()]
        [int]$CurrentDepth = 0
    )

    if ($CurrentDepth -gt $Depth) {
        return '"..."'
    }

    if ($null -eq $InputObject) {
        return 'null'
    }

    $type = $InputObject.GetType()

    if ($type -eq [string]) {
        $escaped = $InputObject.Replace('\', '\\').Replace('"', '\"').Replace("`n", '\n').Replace("`r", '\r').Replace("`t", '\t')
        return '"' + $escaped + '"'
    }

    if ($type -eq [bool]) {
        return $InputObject.ToString().ToLower()
    }

    if ($type -is [ValueType] -and ($type -eq [int] -or $type -eq [double] -or $type -eq [float] -or $type -eq [decimal] -or $type -eq [long])) {
        return $InputObject.ToString()
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [hashtable] -or $InputObject -is [System.Collections.IDictionary])) {
        $items = @()
        foreach ($item in $InputObject) {
            $items += (ConvertTo-JsonCompatible -InputObject $item -Depth $Depth -CurrentDepth ($CurrentDepth + 1))
        }
        if ($items.Count -eq 0) {
            return '[]'
        }
        if ($Compress) {
            return '[' + ($items -join ',') + ']'
        }
        $indent = "  " * $CurrentDepth
        $innerIndent = "  " * ($CurrentDepth + 1)
        return "[" + [Environment]::NewLine + ($items -join ("," + [Environment]::NewLine + $innerIndent)) + [Environment]::NewLine + $indent + "]"
    }

    if ($InputObject -is [hashtable] -or $InputObject -is [System.Collections.IDictionary]) {
        $items = @()
        foreach ($key in $InputObject.Keys) {
            $keyStr = (ConvertTo-JsonCompatible -InputObject $key -Depth $Depth -CurrentDepth ($CurrentDepth + 1))
            $valueStr = (ConvertTo-JsonCompatible -InputObject $InputObject[$key] -Depth $Depth -CurrentDepth ($CurrentDepth + 1))
            $items += ($keyStr + ': ' + $valueStr)
        }
        if ($items.Count -eq 0) {
            return '{}'
        }
        if ($Compress) {
            return '{' + ($items -join ',') + '}'
        }
        $indent = "  " * $CurrentDepth
        $innerIndent = "  " * ($CurrentDepth + 1)
        return "{" + [Environment]::NewLine + ($items -join ("," + [Environment]::NewLine + $innerIndent)) + [Environment]::NewLine + $indent + "}"
    }

    if ($InputObject -is [System.Management.Automation.PSCustomObject] -or $InputObject.PSObject.Properties.Count -gt 0) {
        $items = @()
        foreach ($prop in $InputObject.PSObject.Properties) {
            $keyStr = (ConvertTo-JsonCompatible -InputObject $prop.Name -Depth $Depth -CurrentDepth ($CurrentDepth + 1))
            $valueStr = (ConvertTo-JsonCompatible -InputObject $prop.Value -Depth $Depth -CurrentDepth ($CurrentDepth + 1))
            $items += ($keyStr + ': ' + $valueStr)
        }
        if ($items.Count -eq 0) {
            return '{}'
        }
        if ($Compress) {
            return '{' + ($items -join ',') + '}'
        }
        $indent = "  " * $CurrentDepth
        $innerIndent = "  " * ($CurrentDepth + 1)
        return "{" + [Environment]::NewLine + ($items -join ("," + [Environment]::NewLine + $innerIndent)) + [Environment]::NewLine + $indent + "}"
    }

    return '"' + $InputObject.ToString() + '"'
}

Export-ModuleMember -Function @(
    'Invoke-GeometryNodesParse',
    'Get-NodeTreeStructure',
    'Get-NodeGroupInputs',
    'Get-NodeGroupOutputs',
    'Get-NodeParameters',
    'Convert-NodeTreeToJson',
    'Test-NodeTreeConnectivity'
)
