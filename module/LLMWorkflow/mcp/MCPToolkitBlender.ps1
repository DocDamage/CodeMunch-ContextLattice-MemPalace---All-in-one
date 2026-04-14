#requires -Version 5.1
Set-StrictMode -Version Latest

#===============================================================================
# Blender Integration Tools
#===============================================================================

<#
.SYNOPSIS
    Executes a Blender tool via MCP.
.DESCRIPTION
    Invokes a registered Blender-related MCP tool with the specified parameters.
.PARAMETER ToolName
    The name of the Blender tool to execute.
.PARAMETER Parameters
    Hashtable of parameters to pass to the tool.
.OUTPUTS
    System.Management.Automation.PSCustomObject with tool execution results.
.EXAMPLE
    PS C:\> Invoke-MCPBlenderTool -ToolName "blender_version" -Parameters @{}
    
    Gets the Blender version.
#>
function Invoke-MCPBlenderTool {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('blender_version', 'blender_operator', 'blender_export_mesh_library',
                     'blender_import_mesh', 'blender_render_scene', 'blender_list_materials',
                     'blender_apply_modifier', 'blender_export_godot')]
        [string]$ToolName,
        
        [Parameter()]
        [hashtable]$Parameters = @{}
    )
    
    return Invoke-MCPTool -ToolName $ToolName -Parameters $Parameters
}

<#
.SYNOPSIS
    Gets the installed Blender version.
.DESCRIPTION
    Queries the system for the installed Blender version.
.PARAMETER BlenderPath
    Optional path to the Blender executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with version information.
.EXAMPLE
    PS C:\> Get-MCPBlenderVersion
    
    Returns the Blender version information.
#>
function Get-MCPBlenderVersion {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$BlenderPath = ''
    )
    
    try {
        $blender = Find-BlenderExecutable -Path $BlenderPath
        
        if (-not $blender) {
            return [pscustomobject]@{
                installed = $false
                version = $null
                versionString = $null
                error = 'Blender executable not found'
            }
        }
        
        # Get version using --version flag
        $versionOutput = & $blender --version 2>&1 | Out-String
        $lines = $versionOutput -split "`r?`n"
        $versionString = $lines[0].Trim()
        
        # Parse version (format: Blender 3.6.0 or Blender 4.0.0)
        $versionMatch = $versionString -match 'Blender\s+(\d+)\.(\d+)\.(\d+)'
        $version = if ($versionMatch) {
            @{
                major = [int]$matches[1]
                minor = [int]$matches[2]
                patch = [int]$matches[3]
                full = $versionString
            }
        } else { $null }
        
        return [pscustomobject]@{
            installed = $true
            version = $version
            versionString = $versionString
            executable = $blender
            error = $null
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to get Blender version: $_"
        return [pscustomobject]@{
            installed = $false
            version = $null
            versionString = $null
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Executes a Blender operator via bpy.
.DESCRIPTION
    Runs a Blender Python operator using the bpy module.
.PARAMETER Operator
    The bpy operator to execute (e.g., 'mesh.primitive_cube_add').
.PARAMETER Parameters
    Hashtable of parameters for the operator.
.PARAMETER BlenderPath
    Optional path to the Blender executable.
.PARAMETER Background
    If specified, runs Blender in background mode (default: true for operators).
.OUTPUTS
    System.Management.Automation.PSCustomObject with execution result.
.EXAMPLE
    PS C:\> Invoke-MCPBlenderOperator -Operator "mesh.primitive_cube_add" -Parameters @{ size = 2 }
    
    Creates a cube in Blender.
#>
function Invoke-MCPBlenderOperator {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Operator,
        
        [Parameter()]
        [hashtable]$Parameters = @{},
        
        [Parameter()]
        [string]$BlenderPath = '',
        
        [Parameter()]
        [switch]$Background = $true
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'blender_operator' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $blender = Find-BlenderExecutable -Path $BlenderPath
        if (-not $blender) {
            throw 'Blender executable not found'
        }
        
        # Build Python script
        $paramList = @()
        foreach ($key in $Parameters.Keys) {
            $value = $Parameters[$key]
            if ($value -is [string]) {
                $paramList += "$key=`"$value`""
            }
            elseif ($value -is [bool]) {
                $paramList += "$key=$($value.ToString().ToLower())"
            }
            else {
                $paramList += "$key=$value"
            }
        }
        $paramString = if ($paramList.Count -gt 0) { ", $($paramList -join ', ')" } else { '' }
        
        $pythonScript = @"
import bpy
import sys
import json

try:
    bpy.ops.$Operator($($paramString.TrimStart(', ')))
    result = {"success": True, "message": "Operator executed successfully"}
except Exception as e:
    result = {"success": False, "error": str(e)}

print("MCP_RESULT:" + json.dumps(result))
"@
        
        $arguments = @()
        if ($Background) {
            $arguments += '--background'
        }
        $arguments += '--python-expr'
        $arguments += $pythonScript
        
        $output = & $blender @arguments 2>&1 | Out-String
        
        # Parse result from output
        $resultMatch = $output -match 'MCP_RESULT:(\{[^}]+\})'
        $result = if ($resultMatch) {
            $resultMatch[1] | ConvertFrom-Json
        } else {
            @{ success = $true; rawOutput = $output }
        }
        
        Write-MCPLog -Level INFO -Message "Executed Blender operator" -Metadata @{
            operator = $Operator
            success = $result.success
        }
        
        return [pscustomobject]$result
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to execute Blender operator: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Exports a mesh library from Blender.
.DESCRIPTION
    Exports selected or all meshes from a Blender file to a mesh library format.
.PARAMETER BlendFile
    The path to the .blend file to export from.
.PARAMETER OutputPath
    The output path for the exported mesh library.
.PARAMETER Format
    The export format: 'gltf', 'fbx', or 'obj'. Default: gltf.
.PARAMETER SelectedOnly
    If specified, exports only selected meshes.
.PARAMETER BlenderPath
    Optional path to the Blender executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with export result.
.EXAMPLE
    PS C:\> Invoke-MCPBlenderExportMeshLibrary -BlendFile "./models.blend" -OutputPath "./mesh_library.gltf"
    
    Exports meshes from the blend file to glTF format.
#>
function Invoke-MCPBlenderExportMeshLibrary {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$BlendFile,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,
        
        [Parameter()]
        [ValidateSet('gltf', 'fbx', 'obj')]
        [string]$Format = 'gltf',
        
        [Parameter()]
        [switch]$SelectedOnly,
        
        [Parameter()]
        [string]$BlenderPath = ''
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'blender_export_mesh_library' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $blender = Find-BlenderExecutable -Path $BlenderPath
        if (-not $blender) {
            throw 'Blender executable not found'
        }
        
        $resolvedBlendFile = Resolve-Path -LiteralPath $BlendFile | Select-Object -ExpandProperty Path
        $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
        
        # Build Python script for export
        $exportScript = @"
import bpy
import json
import os

try:
    # Clear default scene
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    
    # Load blend file
    bpy.ops.wm.open_mainfile(filepath=r'$resolvedBlendFile')
    
    # Select meshes
    bpy.ops.object.select_all(action='DESELECT')
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            obj.select_set(True)
    
    # Export based on format
    format_lower = '$Format'.lower()
    output_path = r'$resolvedOutputPath'
    
    if format_lower == 'gltf':
        bpy.ops.export_scene.gltf(filepath=output_path, use_selection=True)
    elif format_lower == 'fbx':
        bpy.ops.export_scene.fbx(filepath=output_path, use_selection=True)
    elif format_lower == 'obj':
        bpy.ops.export_scene.obj(filepath=output_path, use_selection=True)
    
    result = {"success": True, "message": f"Exported mesh library to {output_path}"}
except Exception as e:
    result = {"success": False, "error": str(e)}

print("MCP_RESULT:" + json.dumps(result))
"@
        
        $arguments = @(
            '--background'
            '--python-expr'
            $exportScript
        )
        
        $output = & $blender @arguments 2>&1 | Out-String
        
        # Parse result from output
        $resultMatch = $output -match 'MCP_RESULT:(\{[^}]+\})'
        $result = if ($resultMatch) {
            $resultMatch[1] | ConvertFrom-Json
        } else {
            @{ success = $true; rawOutput = $output }
        }
        
        Write-MCPLog -Level INFO -Message "Exported Blender mesh library" -Metadata @{
            blendFile = $resolvedBlendFile
            outputPath = $resolvedOutputPath
            format = $Format
            success = $result.success
        }
        
        return [pscustomobject]@{
            success = $result.success
            message = if ($result.message) { $result.message } else { "Export completed" }
            error = if ($result.error) { $result.error } else { $null }
            blendFile = $resolvedBlendFile
            outputPath = $resolvedOutputPath
            format = $Format
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to export Blender mesh library: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Imports mesh files into Blender.
.DESCRIPTION
    Imports OBJ, FBX, or glTF mesh files into a Blender scene.
.PARAMETER FilePath
    The path to the mesh file to import.
.PARAMETER BlendFile
    Optional path to an existing .blend file to append the import to.
.PARAMETER Format
    The import format: 'obj', 'fbx', 'gltf', 'glb', or 'auto' to detect from extension.
.PARAMETER BlenderPath
    Optional path to the Blender executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with import result.
.EXAMPLE
    PS C:\> Invoke-MCPBlenderImportMesh -FilePath "./model.obj" -Format "obj"
    
    Imports the OBJ file into Blender.
#>
function Invoke-MCPBlenderImportMesh {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$FilePath,
        
        [Parameter()]
        [string]$BlendFile = '',
        
        [Parameter()]
        [ValidateSet('auto', 'obj', 'fbx', 'gltf', 'glb')]
        [string]$Format = 'auto',
        
        [Parameter()]
        [string]$BlenderPath = ''
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'blender_import_mesh' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $blender = Find-BlenderExecutable -Path $BlenderPath
        if (-not $blender) {
            throw 'Blender executable not found'
        }
        
        $resolvedFilePath = Resolve-Path -LiteralPath $FilePath | Select-Object -ExpandProperty Path
        
        # Auto-detect format from extension if not specified
        $importFormat = $Format
        if ($importFormat -eq 'auto') {
            $extension = [System.IO.Path]::GetExtension($resolvedFilePath).ToLower()
            switch ($extension) {
                '.obj' { $importFormat = 'obj' }
                '.fbx' { $importFormat = 'fbx' }
                '.gltf' { $importFormat = 'gltf' }
                '.glb' { $importFormat = 'glb' }
                default { throw "Cannot auto-detect format from extension: $extension" }
            }
        }
        
        # Build Python script for import
        $importScript = @"
import bpy
import json
import os

try:
    # Clear default scene if not appending to existing
    clear_scene = $(if ($BlendFile) { 'False' } else { 'True' })
    if clear_scene:
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.object.delete(use_global=False)
    else:
        bpy.ops.wm.open_mainfile(filepath=r'$BlendFile')
    
    # Import based on format
    file_path = r'$resolvedFilePath'
    format_lower = '$importFormat'.lower()
    
    if format_lower == 'obj':
        bpy.ops.import_scene.obj(filepath=file_path)
    elif format_lower == 'fbx':
        bpy.ops.import_scene.fbx(filepath=file_path)
    elif format_lower in ['gltf', 'glb']:
        bpy.ops.import_scene.gltf(filepath=file_path)
    
    # Get imported object names
    imported_objects = [obj.name for obj in bpy.context.selected_objects]
    
    result = {
        "success": True,
        "message": f"Imported {len(imported_objects)} objects from {file_path}",
        "importedObjects": imported_objects,
        "format": format_lower
    }
except Exception as e:
    result = {"success": False, "error": str(e)}

print("MCP_RESULT:" + json.dumps(result))
"@
        
        $arguments = @(
            '--background'
            '--python-expr'
            $importScript
        )
        
        $output = & $blender @arguments 2>&1 | Out-String
        
        # Parse result from output
        $resultMatch = $output -match 'MCP_RESULT:(\{[^}]+\})'
        $result = if ($resultMatch) {
            $resultMatch[1] | ConvertFrom-Json
        } else {
            @{ success = $true; rawOutput = $output }
        }
        
        Write-MCPLog -Level INFO -Message "Imported mesh into Blender" -Metadata @{
            filePath = $resolvedFilePath
            format = $importFormat
            success = $result.success
        }
        
        return [pscustomobject]$result
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to import mesh into Blender: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Renders a Blender scene.
.DESCRIPTION
    Renders the current scene or an animation from a Blender file.
.PARAMETER BlendFile
    The path to the .blend file to render.
.PARAMETER OutputPath
    The output path for the rendered image or video.
.PARAMETER Animation
    If specified, renders the full animation instead of a single frame.
.PARAMETER FrameStart
    The start frame for animation rendering.
.PARAMETER FrameEnd
    The end frame for animation rendering.
.PARAMETER Engine
    The render engine to use (CYCLES, BLENDER_EEVEE, BLENDER_WORKBENCH).
.PARAMETER ResolutionX
    The horizontal resolution.
.PARAMETER ResolutionY
    The vertical resolution.
.PARAMETER BlenderPath
    Optional path to the Blender executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with render result.
.EXAMPLE
    PS C:\> Invoke-MCPBlenderRenderScene -BlendFile "./scene.blend" -OutputPath "./render.png"
    
    Renders the scene to an image file.
#>
function Invoke-MCPBlenderRenderScene {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$BlendFile,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,
        
        [Parameter()]
        [switch]$Animation,
        
        [Parameter()]
        [int]$FrameStart = 1,
        
        [Parameter()]
        [int]$FrameEnd = 250,
        
        [Parameter()]
        [ValidateSet('CYCLES', 'BLENDER_EEVEE', 'BLENDER_WORKBENCH')]
        [string]$Engine = 'BLENDER_EEVEE',
        
        [Parameter()]
        [int]$ResolutionX = 1920,
        
        [Parameter()]
        [int]$ResolutionY = 1080,
        
        [Parameter()]
        [string]$BlenderPath = ''
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'blender_render_scene' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $blender = Find-BlenderExecutable -Path $BlenderPath
        if (-not $blender) {
            throw 'Blender executable not found'
        }
        
        $resolvedBlendFile = Resolve-Path -LiteralPath $BlendFile | Select-Object -ExpandProperty Path
        $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
        
        # Build Python script for rendering
        $renderScript = @"
import bpy
import json
import os

try:
    # Load blend file
    bpy.ops.wm.open_mainfile(filepath=r'$resolvedBlendFile')
    
    # Set render settings
    scene = bpy.context.scene
    scene.render.engine = '$Engine'
    scene.render.resolution_x = $ResolutionX
    scene.render.resolution_y = $ResolutionY
    
    # Set output path
    output_path = r'$resolvedOutputPath'
    scene.render.filepath = output_path
    
    # Ensure output directory exists
    output_dir = os.path.dirname(output_path)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    # Render
    is_animation = $(if ($Animation) { 'True' } else { 'False' })
    if is_animation:
        scene.frame_start = $FrameStart
        scene.frame_end = $FrameEnd
        bpy.ops.render.render(animation=True)
        frame_count = $FrameEnd - $FrameStart + 1
        result = {
            "success": True,
            "message": f"Animation rendered: {frame_count} frames to {output_path}",
            "frameCount": frame_count,
            "outputPath": output_path
        }
    else:
        bpy.ops.render.render(write_file=True)
        result = {
            "success": True,
            "message": f"Frame rendered to {output_path}",
            "frame": scene.frame_current,
            "outputPath": output_path
        }
except Exception as e:
    result = {"success": False, "error": str(e)}

print("MCP_RESULT:" + json.dumps(result))
"@
        
        $arguments = @(
            '--background'
            '--python-expr'
            $renderScript
        )
        
        $output = & $blender @arguments 2>&1 | Out-String
        
        # Parse result from output
        $resultMatch = $output -match 'MCP_RESULT:(\{[^}]+\})'
        $result = if ($resultMatch) {
            $resultMatch[1] | ConvertFrom-Json
        } else {
            @{ success = $true; rawOutput = $output }
        }
        
        Write-MCPLog -Level INFO -Message "Rendered Blender scene" -Metadata @{
            blendFile = $resolvedBlendFile
            outputPath = $resolvedOutputPath
            animation = $Animation.IsPresent
            success = $result.success
        }
        
        return [pscustomobject]$result
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to render Blender scene: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Lists materials in a Blender file.
.DESCRIPTION
    Retrieves a list of materials from a .blend file, including usage information.
.PARAMETER BlendFile
    The path to the .blend file.
.PARAMETER IncludeOrphans
    If specified, includes materials not assigned to any object.
.PARAMETER BlenderPath
    Optional path to the Blender executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with material list.
.EXAMPLE
    PS C:\> Invoke-MCPBlenderListMaterials -BlendFile "./scene.blend"
    
    Lists all materials in the scene.
#>
function Invoke-MCPBlenderListMaterials {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$BlendFile,
        
        [Parameter()]
        [switch]$IncludeOrphans,
        
        [Parameter()]
        [string]$BlenderPath = ''
    )
    
    try {
        $blender = Find-BlenderExecutable -Path $BlenderPath
        if (-not $blender) {
            throw 'Blender executable not found'
        }
        
        $resolvedBlendFile = Resolve-Path -LiteralPath $BlendFile | Select-Object -ExpandProperty Path
        
        # Build Python script to list materials
        $materialScript = @"
import bpy
import json

try:
    # Load blend file
    bpy.ops.wm.open_mainfile(filepath=r'$resolvedBlendFile')
    
    # Collect materials
    materials = []
    include_orphans = $(if ($IncludeOrphans) { 'True' } else { 'False' })
    
    # Track which materials are used by objects
    used_materials = set()
    for obj in bpy.data.objects:
        if obj.type == 'MESH' and obj.data.materials:
            for mat_slot in obj.material_slots:
                if mat_slot.material:
                    used_materials.add(mat_slot.material.name)
    
    for mat in bpy.data.materials:
        is_used = mat.name in used_materials
        
        # Skip orphans if not requested
        if not is_used and not include_orphans:
            continue
        
        mat_info = {
            "name": mat.name,
            "isUsed": is_used,
            "useNodes": mat.use_nodes if hasattr(mat, 'use_nodes') else False,
            "blendMethod": mat.blend_method if hasattr(mat, 'blend_method') else None
        }
        
        # Get node tree info if using nodes
        if mat.use_nodes and mat.node_tree:
            nodes = []
            for node in mat.node_tree.nodes:
                node_info = {
                    "type": node.type,
                    "name": node.name,
                    "label": node.label if node.label else None
                }
                nodes.append(node_info)
            mat_info["nodes"] = nodes
            mat_info["nodeCount"] = len(nodes)
        
        materials.append(mat_info)
    
    result = {
        "success": True,
        "materials": materials,
        "totalCount": len(bpy.data.materials),
        "usedCount": len(used_materials),
        "orphanCount": len(bpy.data.materials) - len(used_materials)
    }
except Exception as e:
    result = {"success": False, "error": str(e)}

print("MCP_RESULT:" + json.dumps(result))
"@
        
        $arguments = @(
            '--background'
            '--python-expr'
            $materialScript
        )
        
        $output = & $blender @arguments 2>&1 | Out-String
        
        # Parse result from output
        $resultMatch = $output -match 'MCP_RESULT:(\{[^}]+\})'
        $result = if ($resultMatch) {
            $resultMatch[1] | ConvertFrom-Json
        } else {
            @{ success = $true; rawOutput = $output }
        }
        
        Write-MCPLog -Level INFO -Message "Listed Blender materials" -Metadata @{
            blendFile = $resolvedBlendFile
            success = $result.success
        }
        
        return [pscustomobject]$result
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to list Blender materials: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Applies modifiers to objects in Blender.
.DESCRIPTION
    Applies all or specific modifiers to a named object in a Blender file.
.PARAMETER BlendFile
    The path to the .blend file.
.PARAMETER ObjectName
    The name of the object to apply modifiers to.
.PARAMETER ModifierType
    Optional specific modifier type to apply (e.g., SUBSURF, MIRROR, ARRAY).
.PARAMETER AllModifiers
    If specified, applies all modifiers. Default is true.
.PARAMETER BlenderPath
    Optional path to the Blender executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with apply result.
.EXAMPLE
    PS C:\> Invoke-MCPBlenderApplyModifier -BlendFile "./scene.blend" -ObjectName "Cube" -AllModifiers
    
    Applies all modifiers to the Cube object.
#>
function Invoke-MCPBlenderApplyModifier {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$BlendFile,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ObjectName,
        
        [Parameter()]
        [string]$ModifierType = '',
        
        [Parameter()]
        [switch]$AllModifiers = $true,
        
        [Parameter()]
        [string]$BlenderPath = ''
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'blender_apply_modifier' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $blender = Find-BlenderExecutable -Path $BlenderPath
        if (-not $blender) {
            throw 'Blender executable not found'
        }
        
        $resolvedBlendFile = Resolve-Path -LiteralPath $BlendFile | Select-Object -ExpandProperty Path
        
        # Build Python script to apply modifiers
        $modifierScript = @"
import bpy
import json

try:
    # Load blend file
    bpy.ops.wm.open_mainfile(filepath=r'$resolvedBlendFile')
    
    # Find the object
    target_obj = None
    for obj in bpy.data.objects:
        if obj.name == r'$ObjectName':
            target_obj = obj
            break
    
    if not target_obj:
        raise ValueError(f"Object '$ObjectName' not found in blend file")
    
    # Select the object and make it active
    bpy.ops.object.select_all(action='DESELECT')
    target_obj.select_set(True)
    bpy.context.view_layer.objects.active = target_obj
    
    applied_modifiers = []
    modifier_type_filter = r'$ModifierType'
    apply_all = $(if ($AllModifiers) { 'True' } else { 'False' })
    
    # Apply modifiers
    for mod in list(target_obj.modifiers):
        should_apply = False
        
        if apply_all:
            should_apply = True
        elif modifier_type_filter and mod.type == modifier_type_filter:
            should_apply = True
        
        if should_apply:
            try:
                # Apply the modifier
                bpy.ops.object.modifier_apply(modifier=mod.name)
                applied_modifiers.append({
                    "name": mod.name,
                    "type": mod.type
                })
            except Exception as mod_error:
                applied_modifiers.append({
                    "name": mod.name,
                    "type": mod.type,
                    "error": str(mod_error)
                })
    
    result = {
        "success": True,
        "message": f"Applied {len(applied_modifiers)} modifiers to '{target_obj.name}'",
        "objectName": target_obj.name,
        "appliedModifiers": applied_modifiers,
        "remainingModifiers": len(target_obj.modifiers)
    }
except Exception as e:
    result = {"success": False, "error": str(e)}

print("MCP_RESULT:" + json.dumps(result))
"@
        
        $arguments = @(
            '--background'
            '--python-expr'
            $modifierScript
        )
        
        $output = & $blender @arguments 2>&1 | Out-String
        
        # Parse result from output
        $resultMatch = $output -match 'MCP_RESULT:(\{[^}]+\})'
        $result = if ($resultMatch) {
            $resultMatch[1] | ConvertFrom-Json
        } else {
            @{ success = $true; rawOutput = $output }
        }
        
        Write-MCPLog -Level INFO -Message "Applied modifiers in Blender" -Metadata @{
            blendFile = $resolvedBlendFile
            objectName = $ObjectName
            success = $result.success
        }
        
        return [pscustomobject]$result
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to apply modifiers in Blender: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Exports a Blender scene to Godot-compatible glTF format.
.DESCRIPTION
    Exports a .blend file to glTF format with settings optimized for Godot Engine.
.PARAMETER BlendFile
    The path to the .blend file.
.PARAMETER OutputPath
    The output path for the .glb/.gltf file.
.PARAMETER ExportMaterials
    If specified, exports materials. Default is true.
.PARAMETER ExportAnimations
    If specified, exports animations. Default is true.
.PARAMETER ExportCameras
    If specified, exports cameras. Default is false.
.PARAMETER ExportLights
    If specified, exports lights. Default is false.
.PARAMETER YUp
    If specified, uses Y-up coordinate system. Default is true (recommended for Godot).
.PARAMETER BlenderPath
    Optional path to the Blender executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with export result.
.EXAMPLE
    PS C:\> Invoke-MCPBlenderExportGodot -BlendFile "./scene.blend" -OutputPath "./export.glb"
    
    Exports the scene to Godot-compatible glTF format.
#>
function Invoke-MCPBlenderExportGodot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$BlendFile,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,
        
        [Parameter()]
        [switch]$ExportMaterials = $true,
        
        [Parameter()]
        [switch]$ExportAnimations = $true,
        
        [Parameter()]
        [switch]$ExportCameras = $false,
        
        [Parameter()]
        [switch]$ExportLights = $false,
        
        [Parameter()]
        [switch]$YUp = $true,
        
        [Parameter()]
        [string]$BlenderPath = ''
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'blender_export_godot' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $blender = Find-BlenderExecutable -Path $BlenderPath
        if (-not $blender) {
            throw 'Blender executable not found'
        }
        
        $resolvedBlendFile = Resolve-Path -LiteralPath $BlendFile | Select-Object -ExpandProperty Path
        $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
        
        # Build Python script for Godot export
        $exportScript = @"
import bpy
import json
import os

try:
    # Load blend file
    bpy.ops.wm.open_mainfile(filepath=r'$resolvedBlendFile')
    
    # Ensure output directory exists
    output_dir = os.path.dirname(r'$resolvedOutputPath')
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    # Set export options for Godot compatibility
    export_materials = $(if ($ExportMaterials) { 'True' } else { 'False' })
    export_animations = $(if ($ExportAnimations) { 'True' } else { 'False' })
    export_cameras = $(if ($ExportCameras) { 'True' } else { 'False' })
    export_lights = $(if ($ExportLights) { 'True' } else { 'False' })
    y_up = $(if ($YUp) { 'True' } else { 'False' })
    
    # Export to glTF with Godot-friendly settings
    bpy.ops.export_scene.gltf(
        filepath=r'$resolvedOutputPath',
        export_format='GLB' if r'$resolvedOutputPath'.endswith('.glb') else 'GLTF_SEPARATE',
        export_materials=export_materials,
        export_animations=export_animations,
        export_cameras=export_cameras,
        export_lights=export_lights,
        export_yup=y_up,
        export_apply=True,  # Apply modifiers
        export_texcoords=True,
        export_normals=True,
        export_draco_mesh_compression_enable=False,
        use_selection=False  # Export all objects
    )
    
    result = {
        "success": True,
        "message": f"Exported to Godot-compatible glTF: {r'$resolvedOutputPath'}",
        "outputPath": r'$resolvedOutputPath',
        "settings": {
            "exportMaterials": export_materials,
            "exportAnimations": export_animations,
            "exportCameras": export_cameras,
            "exportLights": export_lights,
            "yUp": y_up
        }
    }
except Exception as e:
    result = {"success": False, "error": str(e)}

print("MCP_RESULT:" + json.dumps(result))
"@
        
        $arguments = @(
            '--background'
            '--python-expr'
            $exportScript
        )
        
        $output = & $blender @arguments 2>&1 | Out-String
        
        # Parse result from output
        $resultMatch = $output -match 'MCP_RESULT:(\{[^}]+\})'
        $result = if ($resultMatch) {
            $resultMatch[1] | ConvertFrom-Json
        } else {
            @{ success = $true; rawOutput = $output }
        }
        
        Write-MCPLog -Level INFO -Message "Exported Blender to Godot format" -Metadata @{
            blendFile = $resolvedBlendFile
            outputPath = $resolvedOutputPath
            success = $result.success
        }
        
        return [pscustomobject]$result
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to export Blender to Godot format: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

function Find-BlenderExecutable {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Path = ''
    )
    
    # Check explicit path first
    if (-not [string]::IsNullOrEmpty($Path) -and (Test-Path -LiteralPath $Path)) {
        return $Path
    }
    
    # Check PATH
    $found = Get-Command 'blender' -ErrorAction SilentlyContinue
    if ($found) {
        return $found.Source
    }
    
    # Check common installation paths
    $commonPaths = @(
        'C:\Program Files\Blender Foundation\Blender\blender.exe',
        'C:\Program Files\Blender Foundation\Blender 4.0\blender.exe',
        'C:\Program Files\Blender Foundation\Blender 3.6\blender.exe',
        'C:\Program Files\Blender Foundation\Blender 4.1\blender.exe',
        'C:\Program Files\Blender Foundation\Blender 4.2\blender.exe',
        '/usr/bin/blender',
        '/usr/local/bin/blender',
        '/Applications/Blender.app/Contents/MacOS/Blender'
    )
    
    foreach ($testPath in $commonPaths) {
        if (Test-Path -LiteralPath $testPath) {
            return $testPath
        }
    }
    
    return $null
}

<#
.SYNOPSIS
    Searches local pack content.
.DESCRIPTION
    Performs a simple text search across pack files.
.PARAMETER Query
    The search query.
.PARAMETER PackIds
    Pack IDs to search.
.PARAMETER Limit
    Maximum results.
.OUTPUTS
    Array of search results.
#>
