#requires -Version 7.0
<#
.SYNOPSIS
    Extraction Performance Benchmarks
.DESCRIPTION
    Performance tests for parsing various file types:
    - GDScript parsing
    - Godot scene parsing
    - Blender Python parsing
    - Notebook parsing
.NOTES
    Version: 1.0.0
#>

param(
    [string]$TestDataPath = "$PSScriptRoot\testdata",
    [int]$WarmupRuns = 1,
    [int]$BenchmarkRuns = 10,
    [switch]$GenerateTestData
)

# Import benchmark suite
. "$PSScriptRoot\BenchmarkSuite.ps1"

# Results collection
$results = [System.Collections.Generic.List[object]]::new()

#region Test Data Generation

function Initialize-TestData {
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$Force
    )

    if ((Test-Path $Path) -and -not $Force) {
        return
    }

    New-Item -ItemType Directory -Path $Path -Force | Out-Null

    # Generate GDScript test files of varying sizes
    $gdscriptSmall = @'
extends Node
class_name Player

@export var speed: float = 200.0
@export var health: int = 100

var velocity: Vector2 = Vector2.ZERO

func _ready():
    pass

func _process(delta):
    var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    velocity = direction * speed
    move_and_slide()

func take_damage(amount: int):
    health -= amount
    if health <= 0:
        die()

func die():
    queue_free()
'@

    $gdscriptLarge = $gdscriptSmall + (@"

# Additional functions for large file test
func complex_calculation(iterations: int) -> float:
    var result: float = 0.0
    for i in range(iterations):
        result += sin(i * 0.1) * cos(i * 0.05)
    return result
"@ * 100)

    $gdscriptSmall | Set-Content "$Path\player_small.gd"
    $gdscriptLarge | Set-Content "$Path\player_large.gd"

    # Generate Godot scene files
    $sceneSmall = @'[gd_scene load_steps=2 format=3 uid="uid://c8yvxg3ulq3a"]

[ext_resource type="Script" path="res://player.gd" id="1_abc123"]

[node name="Player" type="CharacterBody2D"]
script = ExtResource("1_abc123")
speed = 300.0

[node name="Sprite2D" type="Sprite2D" parent="."]
texture = ExtResource("2_def456")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_abc")
'@

    $sceneLarge = $sceneSmall + (@"

[node name="ChildNode`$_`" type="Node2D" parent="."]
position = Vector2($_ * 10, $_ * 20)
"@ -replace '`$_`', '{0}' -f (0..200 | ForEach-Object { $_ }))

    $sceneSmall | Set-Content "$Path\level_small.tscn"
    $sceneLarge | Set-Content "$Path\level_large.tscn"

    # Generate Blender Python test files
    $blenderSmall = @'
import bpy

def create_cube():
    bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 0))
    return bpy.context.active_object

def apply_material(obj, color):
    mat = bpy.data.materials.new(name="CustomMaterial")
    mat.use_nodes = True
    principled = mat.node_tree.nodes["Principled BSDF"]
    principled.inputs["Base Color"].default_value = color
    obj.data.materials.append(mat)

if __name__ == "__main__":
    cube = create_cube()
    apply_material(cube, (1.0, 0.0, 0.0, 1.0))
'@

    $blenderLarge = $blenderSmall + (@"

def create_mesh_`$_`():
    vertices = [
        ($_ * 1.0, 0.0, 0.0),
        ($_ * 1.0 + 1, 0.0, 0.0),
        ($_ * 1.0 + 1, 1.0, 0.0),
        ($_ * 1.0, 1.0, 0.0)
    ]
    faces = [(0, 1, 2, 3)]
    mesh = bpy.data.meshes.new(name=f"Mesh`$_`")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    return mesh
"@ * 100)

    $blenderSmall | Set-Content "$Path\script_small.py"
    $blenderLarge | Set-Content "$Path\script_large.py"

    # Generate Jupyter notebook test files
    $notebookSmall = @'{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": 1,
   "metadata": {},
   "outputs": [],
   "source": [
    "import numpy as np\n",
    "import pandas as pd"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 2,
   "metadata": {},
   "outputs": [],
   "source": [
    "data = np.random.randn(100, 5)\n",
    "df = pd.DataFrame(data, columns=['A', 'B', 'C', 'D', 'E'])"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}'@

    $notebookLarge = @'{
 "cells": [
'@ + ((0..100 | ForEach-Object { @"
  {
   "cell_type": "code",
   "execution_count": $_,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Cell $_\n",
    "x = $_ * 10\n",
    "print(f'Result: {x}')"
   ]
  },
"@ }) -join "`n") + @'
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": ["# Final Section"]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}'@

    $notebookSmall | Set-Content "$Path\notebook_small.ipynb"
    $notebookLarge | Set-Content "$Path\notebook_large.ipynb"

    Write-Host "Generated test data in: $Path" -ForegroundColor Green
}

#endregion

#region Parsing Functions (Simulated)

function Invoke-GDScriptParse {
    param([string]$Content)
    # Simulate GDScript parsing
    $tokens = @()
    $lines = $Content -split "`n"
    foreach ($line in $lines) {
        if ($line -match '^\s*(func|class|var|const|@export)\s') {
            $tokens += @{ Type = $matches[1]; Line = $line }
        }
        if ($line -match '^\s*#') {
            $tokens += @{ Type = 'Comment'; Content = $line.Trim() }
        }
    }
    return $tokens
}

function Invoke-SceneParse {
    param([string]$Content)
    # Simulate Godot scene parsing
    $nodes = @()
    $sections = $Content -split '\[node name="([^"]+)"'
    for ($i = 1; $i -lt $sections.Count; $i += 2) {
        $nodeName = $sections[$i]
        $nodeContent = $sections[$i + 1]
        $nodes += @{
            Name = $nodeName
            Type = if ($nodeContent -match 'type="([^"]+)"') { $matches[1] } else { 'Node' }
        }
    }
    return $nodes
}

function Invoke-BlenderScriptParse {
    param([string]$Content)
    # Simulate Blender Python parsing
    $functions = @()
    $lines = $Content -split "`n"
    $inFunction = $false
    $currentFunction = $null
    
    foreach ($line in $lines) {
        if ($line -match '^def\s+(\w+)\s*\(') {
            if ($currentFunction) { $functions += $currentFunction }
            $currentFunction = @{ Name = $matches[1]; Calls = @() }
            $inFunction = $true
        }
        if ($inFunction -and $line -match 'bpy\.ops\.') {
            $currentFunction.Calls += $line.Trim()
        }
    }
    if ($currentFunction) { $functions += $currentFunction }
    return $functions
}

function Invoke-NotebookParse {
    param([string]$Content)
    # Simulate notebook parsing
    $notebook = $Content | ConvertFrom-Json
    $cells = @()
    foreach ($cell in $notebook.cells) {
        $cells += @{
            Type = $cell.cell_type
            Source = $cell.source -join ""
            ExecutionCount = $cell.execution_count
        }
    }
    return $cells
}

#endregion

#region Benchmark Definitions

function Invoke-GDScriptBenchmarks {
    param([string]$TestDataPath)
    
    $testFiles = @(
        @{ Name = "GDScript_Small"; Path = "$TestDataPath\player_small.gd"; Size = "~50 lines" }
        @{ Name = "GDScript_Large"; Path = "$TestDataPath\player_large.gd"; Size = "~2000 lines" }
    )

    foreach ($test in $testFiles) {
        $content = Get-Content $test.Path -Raw
        
        # Tokenization benchmark
        $result = Measure-Operation -Name "Extraction.GDScript.Tokenize.$($test.Name)" `
            -ScriptBlock { Invoke-GDScriptParse -Content $content } `
            -Parameters @{ Content = $content } `
            -WarmupRuns $WarmupRuns `
            -BenchmarkRuns $BenchmarkRuns
        $results.Add($result)

        # Full parse benchmark (includes symbol extraction)
        $result = Measure-Operation -Name "Extraction.GDScript.FullParse.$($test.Name)" `
            -ScriptBlock {
                $tokens = Invoke-GDScriptParse -Content $content
                $symbols = $tokens | Where-Object { $_.Type -in @('func', 'class', 'var') }
                @{ Tokens = $tokens; Symbols = $symbols }
            } `
            -Parameters @{ Content = $content } `
            -WarmupRuns $WarmupRuns `
            -BenchmarkRuns $BenchmarkRuns
        $results.Add($result)
    }

    # Batch processing benchmark
    $batchFiles = Get-ChildItem "$TestDataPath\*.gd"
    $result = Measure-Operation -Name "Extraction.GDScript.BatchProcessing" `
        -ScriptBlock {
            foreach ($file in $batchFiles) {
                $content = Get-Content $file -Raw
                $null = Invoke-GDScriptParse -Content $content
            }
        } `
        -Parameters @{ batchFiles = $batchFiles } `
        -WarmupRuns $WarmupRuns `
        -BenchmarkRuns $BenchmarkRuns
    $results.Add($result)
}

function Invoke-SceneBenchmarks {
    param([string]$TestDataPath)
    
    $testFiles = @(
        @{ Name = "Scene_Small"; Path = "$TestDataPath\level_small.tscn"; Nodes = 3 }
        @{ Name = "Scene_Large"; Path = "$TestDataPath\level_large.tscn"; Nodes = 200 }
    )

    foreach ($test in $testFiles) {
        $content = Get-Content $test.Path -Raw
        
        # Node extraction benchmark
        $result = Measure-Operation -Name "Extraction.Scene.NodeExtract.$($test.Name)" `
            -ScriptBlock { Invoke-SceneParse -Content $content } `
            -Parameters @{ Content = $content } `
            -WarmupRuns $WarmupRuns `
            -BenchmarkRuns $BenchmarkRuns
        $results.Add($result)

        # Dependency analysis benchmark
        $result = Measure-Operation -Name "Extraction.Scene.DependencyAnalysis.$($test.Name)" `
            -ScriptBlock {
                $nodes = Invoke-SceneParse -Content $content
                $deps = @()
                foreach ($node in $nodes) {
                    if ($content -match "\[ext_resource.*$($node.Name)") {
                        $deps += @{ Node = $node.Name; Dependencies = $matches[0] }
                    }
                }
                $deps
            } `
            -Parameters @{ Content = $content } `
            -WarmupRuns $WarmupRuns `
            -BenchmarkRuns $BenchmarkRuns
        $results.Add($result)
    }
}

function Invoke-BlenderBenchmarks {
    param([string]$TestDataPath)
    
    $testFiles = @(
        @{ Name = "Blender_Small"; Path = "$TestDataPath\script_small.py"; Functions = 3 }
        @{ Name = "Blender_Large"; Path = "$TestDataPath\script_large.py"; Functions = 100 }
    )

    foreach ($test in $testFiles) {
        $content = Get-Content $test.Path -Raw
        
        # Function extraction benchmark
        $result = Measure-Operation -Name "Extraction.Blender.FunctionExtract.$($test.Name)" `
            -ScriptBlock { Invoke-BlenderScriptParse -Content $content } `
            -Parameters @{ Content = $content } `
            -WarmupRuns $WarmupRuns `
            -BenchmarkRuns $BenchmarkRuns
        $results.Add($result)

        # API call analysis benchmark
        $result = Measure-Operation -Name "Extraction.Blender.APIAnalysis.$($test.Name)" `
            -ScriptBlock {
                $functions = Invoke-BlenderScriptParse -Content $content
                $apiCalls = $functions | ForEach-Object { $_.Calls } | Group-Object
                @{
                    TotalFunctions = $functions.Count
                    TotalAPICalls = ($functions | Measure-Object { $_.Calls.Count } -Sum).Sum
                    UniqueAPIs = $apiCalls.Count
                }
            } `
            -Parameters @{ Content = $content } `
            -WarmupRuns $WarmupRuns `
            -BenchmarkRuns $BenchmarkRuns
        $results.Add($result)
    }
}

function Invoke-NotebookBenchmarks {
    param([string]$TestDataPath)
    
    $testFiles = @(
        @{ Name = "Notebook_Small"; Path = "$TestDataPath\notebook_small.ipynb"; Cells = 2 }
        @{ Name = "Notebook_Large"; Path = "$TestDataPath\notebook_large.ipynb"; Cells = 100 }
    )

    foreach ($test in $testFiles) {
        $content = Get-Content $test.Path -Raw
        
        # Cell extraction benchmark
        $result = Measure-Operation -Name "Extraction.Notebook.CellExtract.$($test.Name)" `
            -ScriptBlock { Invoke-NotebookParse -Content $content } `
            -Parameters @{ Content = $content } `
            -WarmupRuns $WarmupRuns `
            -BenchmarkRuns $BenchmarkRuns
        $results.Add($result)

        # Code analysis benchmark
        $result = Measure-Operation -Name "Extraction.Notebook.CodeAnalysis.$($test.Name)" `
            -ScriptBlock {
                $cells = Invoke-NotebookParse -Content $content
                $codeCells = $cells | Where-Object { $_.Type -eq 'code' }
                $allCode = ($codeCells.Source -join "`n")
                $imports = [regex]::Matches($allCode, '^import\s+(\w+)|^from\s+(\w+)') | 
                    ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
                @{
                    TotalCells = $cells.Count
                    CodeCells = $codeCells.Count
                    Imports = $imports
                }
            } `
            -Parameters @{ Content = $content } `
            -WarmupRuns $WarmupRuns `
            -BenchmarkRuns $BenchmarkRuns
        $results.Add($result)
    }

    # Throughput benchmark (cells/second)
    $largeContent = Get-Content "$TestDataPath\notebook_large.ipynb" -Raw
    $result = Measure-Operation -Name "Extraction.Notebook.Throughput" `
        -ScriptBlock {
            $cells = Invoke-NotebookParse -Content $content
            # Return cells per millisecond for throughput calculation
            $cells.Count
        } `
        -Parameters @{ Content = $largeContent } `
        -WarmupRuns $WarmupRuns `
        -BenchmarkRuns $BenchmarkRuns
    # Adjust the metric to show cells/second
    $result | Add-Member -NotePropertyName "ThroughputMetric" -NotePropertyValue "cells/sec" -Force
    $result.Statistics | Add-Member -NotePropertyName "Throughput" -NotePropertyValue ([Math]::Round(1000 / $result.Statistics.Mean * 100, 2)) -Force
    $results.Add($result)
}

#endregion

#region Main Execution

# Initialize test data
Initialize-TestData -Path $TestDataPath -Force:$GenerateTestData

Write-Host "`n=== Running Extraction Benchmarks ===" -ForegroundColor Cyan

# Run all benchmark categories
Invoke-GDScriptBenchmarks -TestDataPath $TestDataPath
Invoke-SceneBenchmarks -TestDataPath $TestDataPath
Invoke-BlenderBenchmarks -TestDataPath $TestDataPath
Invoke-NotebookBenchmarks -TestDataPath $TestDataPath

# Summary
Write-Host "`n=== Extraction Benchmarks Complete ===" -ForegroundColor Cyan
Write-Host "Total benchmarks: $($results.Count)" -ForegroundColor Gray

# Return results
return $results

#endregion
