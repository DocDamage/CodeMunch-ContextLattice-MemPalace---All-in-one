# Extraction Pipeline Tests
# Tests for Phase 4 Structured Extraction Pipeline

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'module' 'LLMWorkflow' 'extraction'
    
    # Import all extraction modules
    @(
        'ExtractionPipeline.ps1',
        'GDScriptParser.ps1',
        'GodotSceneParser.ps1',
        'RPGMakerPluginParser.ps1',
        'BlenderPythonParser.ps1',
        'GeometryNodesParser.ps1',
        'ShaderParameterParser.ps1'
    ) | ForEach-Object {
        $path = Join-Path $ModulePath $_
        if (Test-Path $path) {
            . $path
        }
    }
    
    # Create test directory
    $TestDir = Join-Path $TestDrive "extraction_tests"
    New-Item -ItemType Directory -Path $TestDir -Force | Out-Null
}

Describe "Extraction Pipeline Core" {
    Context "Test-ExtractionSupported" {
        It "Returns true for supported Godot extensions" {
            Test-ExtractionSupported -FilePath "test.gd" | Should -Be $true
            Test-ExtractionSupported -FilePath "test.tscn" | Should -Be $true
            Test-ExtractionSupported -FilePath "test.tres" | Should -Be $true
            Test-ExtractionSupported -FilePath "test.gdshader" | Should -Be $true
        }
        
        It "Returns true for supported RPG Maker extensions" {
            Test-ExtractionSupported -FilePath "test.js" | Should -Be $true
        }
        
        It "Returns true for supported Blender extensions" {
            Test-ExtractionSupported -FilePath "test.py" | Should -Be $true
        }
        
        It "Returns false for unsupported extensions" {
            Test-ExtractionSupported -FilePath "test.xyz" | Should -Be $false
            Test-ExtractionSupported -FilePath "test.txt" | Should -Be $false
        }
    }
    
    Context "Get-SupportedExtractionTypes" {
        It "Returns list of supported types" {
            $types = Get-SupportedExtractionTypes
            $types | Should -Not -BeNullOrEmpty
            $types.Keys | Should -Contain ".gd"
            $types.Keys | Should -Contain ".tscn"
            $types.Keys | Should -Contain ".js"
            $types.Keys | Should -Contain ".py"
        }
    }
    
    Context "Get-ExtractionSchema" {
        It "Returns schema for gdscript type" {
            $schema = Get-ExtractionSchema -Type "gdscript"
            $schema | Should -Not -BeNullOrEmpty
            $schema.typeName | Should -Be "gdscript"
        }
        
        It "Returns schema for godot-scene type" {
            $schema = Get-ExtractionSchema -Type "godot-scene"
            $schema | Should -Not -BeNullOrEmpty
            $schema.typeName | Should -Be "godot-scene"
        }
        
        It "Throws for invalid type" {
            { Get-ExtractionSchema -Type "invalid" } | Should -Throw
        }
    }
}

Describe "GDScript Parser" {
    BeforeAll {
        $TestGDFile = Join-Path $TestDir "test_script.gd"
        @'
extends Node2D
class_name TestClass

signal health_changed(new_health: int)

@export var speed: float = 100.0
@onready var player = $Player

func _ready() -> void:
    pass

func take_damage(amount: int) -> void:
    health -= amount
    health_changed.emit(health)
'@ | Set-Content -Path $TestGDFile
    }
    
    Context "Invoke-GDScriptParse" {
        It "Parses GDScript file successfully" {
            $result = Invoke-GDScriptParse -FilePath $TestGDFile
            $result | Should -Not -BeNullOrEmpty
        }
        
        It "Extracts class information" {
            $result = Invoke-GDScriptParse -FilePath $TestGDFile
            $result.classInfo.extends | Should -Be "Node2D"
            $result.classInfo.className | Should -Be "TestClass"
        }
        
        It "Extracts signals" {
            $result = Invoke-GDScriptParse -FilePath $TestGDFile
            $result.signals | Should -HaveCount 1
            $result.signals[0].name | Should -Be "health_changed"
        }
        
        It "Extracts properties" {
            $result = Invoke-GDScriptParse -FilePath $TestGDFile
            $exports = $result.properties | Where-Object { $_.isExported }
            $exports | Should -HaveCount 1
            $exports[0].name | Should -Be "speed"
        }
        
        It "Extracts methods" {
            $result = Invoke-GDScriptParse -FilePath $TestGDFile
            $result.methods | Should -HaveCount 2
            $methodNames = $result.methods | ForEach-Object { $_.name }
            $methodNames | Should -Contain "_ready"
            $methodNames | Should -Contain "take_damage"
        }
    }
    
    Context "Get-GDScriptClassInfo" {
        It "Returns class metadata" {
            $info = Get-GDScriptClassInfo -FilePath $TestGDFile
            $info | Should -Not -BeNullOrEmpty
            $info.extends | Should -Be "Node2D"
        }
    }
}

Describe "Godot Scene Parser" {
    BeforeAll {
        $TestTSCNFile = Join-Path $TestDir "test_scene.tscn"
        @'
[gd_scene load_steps=3 format=3 uid="uid://c2e1yjsb3xjfq"]

[ext_resource type="Script" path="res://player.gd" id="1_x5k2a"]

[node name="Main" type="Node2D"]

[node name="Player" type="CharacterBody2D" parent="."]
position = Vector2(100, 200)
script = ExtResource("1_x5k2a")

[node name="Sprite2D" type="Sprite2D" parent="Player"]

[connection signal="health_changed" from="Player" to="." method="_on_player_health_changed"]
'@ | Set-Content -Path $TestTSCNFile
    }
    
    Context "Invoke-GodotSceneParse" {
        It "Parses TSCN file successfully" {
            $result = Invoke-GodotSceneParse -FilePath $TestTSCNFile
            $result | Should -Not -BeNullOrEmpty
        }
        
        It "Extracts scene header" {
            $result = Invoke-GodotSceneParse -FilePath $TestTSCNFile
            $result.formatVersion | Should -Be 3
            $result.loadSteps | Should -Be 3
        }
        
        It "Extracts external resources" {
            $result = Invoke-GodotSceneParse -FilePath $TestTSCNFile
            $result.extResources | Should -HaveCount 1
            $result.extResources[0].type | Should -Be "Script"
        }
        
        It "Extracts nodes" {
            $result = Invoke-GodotSceneParse -FilePath $TestTSCNFile
            $result.nodes | Should -HaveCount 3
            $nodeNames = $result.nodes | ForEach-Object { $_.name }
            $nodeNames | Should -Contain "Main"
            $nodeNames | Should -Contain "Player"
            $nodeNames | Should -Contain "Sprite2D"
        }
        
        It "Extracts signal connections" {
            $result = Invoke-GodotSceneParse -FilePath $TestTSCNFile
            $result.connections | Should -HaveCount 1
            $result.connections[0].signal | Should -Be "health_changed"
        }
    }
    
    Context "Get-SceneNodeHierarchy" {
        It "Builds hierarchical tree" {
            $tree = Get-SceneNodeHierarchy -FilePath $TestTSCNFile
            $tree | Should -Not -BeNullOrEmpty
            $tree.Name | Should -Be "Main"
        }
    }
}

Describe "RPG Maker Plugin Parser" {
    BeforeAll {
        $TestPluginFile = Join-Path $TestDir "TestPlugin.js"
        @'
//=============================================================================
// TestPlugin
//=============================================================================
/*:
 * @target MZ
 * @plugindesc Test plugin for extraction pipeline
 * @author TestAuthor
 * @url https://example.com
 *
 * @help
 * This is a test plugin.
 *
 * @param Speed
 * @text Movement Speed
 * @desc Player movement speed
 * @type number
 * @default 4
 * @min 1
 * @max 10
 *
 * @command SetSpeed
 * @text Set Speed
 * @desc Set the player speed
 * @arg speed
 * @type number
 * @default 4
 */

(function() {
    // Plugin code
})();
'@ | Set-Content -Path $TestPluginFile
    }
    
    Context "Invoke-RPGMakerPluginParse" {
        It "Parses plugin file successfully" {
            $result = Invoke-RPGMakerPluginParse -FilePath $TestPluginFile
            $result | Should -Not -BeNullOrEmpty
        }
        
        It "Extracts plugin metadata" {
            $result = Invoke-RPGMakerPluginParse -FilePath $TestPluginFile
            $result.pluginName | Should -Be "TestPlugin"
            $result.author | Should -Be "TestAuthor"
            $result.targetEngine | Should -Be "MZ"
        }
        
        It "Extracts parameters" {
            $result = Invoke-RPGMakerPluginParse -FilePath $TestPluginFile
            $result.parameters | Should -HaveCount 1
            $result.parameters[0].name | Should -Be "Speed"
            $result.parameters[0].type | Should -Be "number"
        }
        
        It "Extracts commands" {
            $result = Invoke-RPGMakerPluginParse -FilePath $TestPluginFile
            $result.commands | Should -HaveCount 1
            $result.commands[0].name | Should -Be "SetSpeed"
        }
    }
    
    Context "Test-RPGMakerPlugin" {
        It "Returns true for valid plugin" {
            Test-RPGMakerPlugin -FilePath $TestPluginFile | Should -Be $true
        }
    }
}

Describe "Blender Python Parser" {
    BeforeAll {
        $TestBlenderFile = Join-Path $TestDir "test_addon.py"
        @'
bl_info = {
    "name": "Test Addon",
    "author": "TestAuthor",
    "version": (1, 0, 0),
    "blender": (3, 6, 0),
    "location": "View3D > Sidebar",
    "description": "A test addon",
    "category": "Mesh"
}

import bpy

class TEST_OT_simple_operator(bpy.types.Operator):
    bl_idname = "test.simple_operator"
    bl_label = "Simple Operator"
    bl_options = {'REGISTER', 'UNDO'}
    
    scale: bpy.props.FloatProperty(name="Scale", default=1.0)
    
    def execute(self, context):
        bpy.ops.mesh.primitive_cube_add(size=self.scale)
        return {'FINISHED'}

class TEST_PT_simple_panel(bpy.types.Panel):
    bl_idname = "TEST_PT_simple_panel"
    bl_label = "Test Panel"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = 'Test'
    
    def draw(self, context):
        layout = self.layout
        layout.operator("test.simple_operator")

classes = [TEST_OT_simple_operator, TEST_PT_simple_panel]

def register():
    for cls in classes:
        bpy.utils.register_class(cls)

def unregister():
    for cls in classes:
        bpy.utils.unregister_class(cls)

if __name__ == "__main__":
    register()
'@ | Set-Content -Path $TestBlenderFile
    }
    
    Context "Invoke-BlenderPythonParse" {
        It "Parses Blender Python file successfully" {
            $result = Invoke-BlenderPythonParse -FilePath $TestBlenderFile
            $result | Should -Not -BeNullOrEmpty
        }
        
        It "Extracts addon info" {
            $result = Invoke-BlenderPythonParse -FilePath $TestBlenderFile
            $result.addonInfo.name | Should -Be "Test Addon"
            $result.addonInfo.author | Should -Be "TestAuthor"
            $result.addonInfo.category | Should -Be "Mesh"
        }
        
        It "Extracts operators" {
            $result = Invoke-BlenderPythonParse -FilePath $TestBlenderFile
            $result.operators | Should -HaveCount 1
            $result.operators[0].bl_idname | Should -Be "test.simple_operator"
        }
        
        It "Extracts panels" {
            $result = Invoke-BlenderPythonParse -FilePath $TestBlenderFile
            $result.panels | Should -HaveCount 1
            $result.panels[0].bl_idname | Should -Be "TEST_PT_simple_panel"
        }
    }
    
    Context "Get-BlenderAddonInfo" {
        It "Returns addon metadata" {
            $info = Get-BlenderAddonInfo -FilePath $TestBlenderFile
            $info.name | Should -Be "Test Addon"
            $info.version | Should -Be "1.0.0"
        }
    }
}

Describe "Batch Extraction" {
    BeforeAll {
        # Create multiple test files
        1..3 | ForEach-Object {
            @"
extends Node2D
class_name TestClass$_

signal signal$_

@export var var$_: int = $_
"@ | Set-Content -Path (Join-Path $TestDir "test_$_.gd")
        }
    }
    
    Context "Invoke-BatchExtraction" {
        It "Processes multiple files" {
            $files = Get-ChildItem -Path $TestDir -Filter "test_*.gd"
            $results = Invoke-BatchExtraction -FilePaths $files.FullName
            $results | Should -HaveCount 3
        }
        
        It "Generates extraction report" {
            $files = Get-ChildItem -Path $TestDir -Filter "test_*.gd"
            $null = Invoke-BatchExtraction -FilePaths $files.FullName
            $report = Export-ExtractionReport
            $report | Should -Not -BeNullOrEmpty
            $report.totalFiles | Should -Be 3
        }
    }
}

AfterAll {
    # Cleanup
    if (Test-Path $TestDir) {
        Remove-Item -Path $TestDir -Recurse -Force
    }
}
