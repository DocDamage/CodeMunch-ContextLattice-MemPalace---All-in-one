# Test BlenderPythonParser module
$ErrorActionPreference = 'Stop'

$testAddonContent = @'
bl_info = {
    "name": "My Blender Addon",
    "author": "Author Name",
    "version": (1, 2, 0),
    "blender": (4, 0, 0),
    "description": "A sample addon for demonstration",
    "category": "Object",
    "location": "View3D > Sidebar > My Tab"
}

import bpy
from bpy.props import FloatProperty, IntProperty, BoolProperty, EnumProperty

class MY_OT_simple_operator(bpy.types.Operator):
    """Tooltip"""
    bl_idname = "object.simple_operator"
    bl_label = "Simple Object Operator"
    bl_options = {'REGISTER', 'UNDO'}
    
    scale: FloatProperty(
        name="Scale",
        default=1.0,
        min=0.1,
        max=10.0
    )
    
    iterations: IntProperty(
        name="Iterations",
        default=1,
        min=1,
        max=100
    )
    
    def execute(self, context):
        for obj in context.selected_objects:
            obj.scale *= self.scale
        return {'FINISHED'}

class MY_PT_main_panel(bpy.types.Panel):
    bl_label = "My Panel"
    bl_idname = "MY_PT_main_panel"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = 'My Tab'
    
    def draw(self, context):
        layout = self.layout
        layout.operator("object.simple_operator")

classes = [MY_OT_simple_operator, MY_PT_main_panel]

def register():
    for cls in classes:
        bpy.utils.register_class(cls)

def unregister():
    for cls in classes:
        bpy.utils.unregister_class(cls)

if __name__ == "__main__":
    register()
'@

# Load the parser
$modulePath = Join-Path $PSScriptRoot "..\module\LLMWorkflow\extraction\BlenderPythonParser.ps1"
Write-Host "Loading from: $modulePath"

$ErrorActionPreference = 'SilentlyContinue'
. $modulePath
$ErrorActionPreference = 'Stop'

Write-Host "`n=== Testing BlenderPythonParser ===" -ForegroundColor Cyan

# Test bl_info extraction
$blInfo = Get-BlInfo -Content $testAddonContent
Write-Host "`nbl_info extraction:" -ForegroundColor Yellow
Write-Host "  name: $($blInfo.name)"
Write-Host "  author: $($blInfo.author)"
Write-Host "  version: $($blInfo.version -join '.')"
Write-Host "  blender: $($blInfo.blender -join '.')"
Write-Host "  category: $($blInfo.category)"

if ($blInfo.name -eq "My Blender Addon") {
    Write-Host "  [PASS] bl_info extracted correctly" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] bl_info extraction issue" -ForegroundColor Red
}

# Test operators
$operators = Get-BlenderOperators -Content $testAddonContent
Write-Host "`nOperators extraction (found $($operators.Count)):" -ForegroundColor Yellow
foreach ($op in $operators) {
    Write-Host "  - $($op.className) | idname: $($op.bl_idname) | label: $($op.bl_label)"
    Write-Host "    methods: execute=$($op.methods.execute), invoke=$($op.methods.invoke), modal=$($op.methods.modal)"
    Write-Host "    properties: $($op.properties.Count)"
}

if ($operators.Count -eq 1 -and $operators[0].className -eq "MY_OT_simple_operator") {
    Write-Host "  [PASS] Operators extracted correctly" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Operator extraction issue" -ForegroundColor Red
}

# Test panels
$panels = Get-BlenderPanels -Content $testAddonContent
Write-Host "`nPanels extraction (found $($panels.Count)):" -ForegroundColor Yellow
foreach ($panel in $panels) {
    Write-Host "  - $($panel.className) | idname: $($panel.bl_idname) | label: $($panel.bl_label)"
    Write-Host "    space_type: $($panel.bl_space_type) | region_type: $($panel.bl_region_type) | category: $($panel.bl_category)"
}

if ($panels.Count -eq 1 -and $panels[0].className -eq "MY_PT_main_panel") {
    Write-Host "  [PASS] Panels extracted correctly" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Panel extraction issue" -ForegroundColor Red
}

# Test full parser
$manifest = ConvertFrom-BlenderPython -Content $testAddonContent
Write-Host "`nFull manifest:" -ForegroundColor Yellow
Write-Host "  fileType: $($manifest.fileType)"
Write-Host "  totalClasses: $($manifest.summary.totalClasses)"
Write-Host "  totalOperators: $($manifest.summary.totalOperators)"
Write-Host "  totalPanels: $($manifest.summary.totalPanels)"
Write-Host "  hasPreferences: $($manifest.summary.hasPreferences)"

if ($manifest.fileType -eq "blender_addon" -and $manifest.summary.totalClasses -eq 2) {
    Write-Host "  [PASS] Full parser working correctly" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Full parser issue" -ForegroundColor Red
}

# Output full JSON
Write-Host "`nFull JSON Output:" -ForegroundColor Cyan
$manifest | ConvertTo-Json -Depth 10

Write-Host "`n=== All tests complete ===" -ForegroundColor Cyan
