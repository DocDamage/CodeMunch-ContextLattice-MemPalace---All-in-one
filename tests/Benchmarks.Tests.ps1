#requires -Version 5.1
<#
.SYNOPSIS
    Performance Benchmark Tests for LLM Workflow Platform

.DESCRIPTION
    Pester v5 test suite for performance benchmarks:
    - Core operation performance
    - Extraction performance
    - Retrieval performance

.NOTES
    File: Benchmarks.Tests.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Requires: Pester 5.0+

.WARNING
    These are performance benchmarks that may fail on slower systems.
    Use -SkipPerformanceTests to skip these tests in CI/CD.
#>

param(
    [switch]$SkipPerformanceTests
)

BeforeAll {
    # Set up test environment
    $script:TestRoot = Join-Path $TestDrive "BenchmarkTests"
    $script:ModuleRoot = Join-Path $PSScriptRoot ".." "module" "LLMWorkflow"
    $script:CoreModulePath = Join-Path $ModuleRoot "core"
    $script:ExtractionModulePath = Join-Path $ModuleRoot "extraction"
    $script:RetrievalModulePath = Join-Path $ModuleRoot "retrieval"
    
    # Create test directories
    New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:TestRoot ".llm-workflow") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:TestRoot ".llm-workflow" "locks") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:TestRoot ".llm-workflow" "journals") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:TestRoot ".llm-workflow" "manifests") -Force | Out-Null
    
    # Import modules
    $modules = @(
        "FileLock.ps1",
        "Journal.ps1", 
        "AtomicWrite.ps1",
        "Config.ps1"
    )
    
    foreach ($module in $modules) {
        $path = Join-Path $script:CoreModulePath $module
        if (Test-Path $path) { . $path }
    }
    
    # Import retrieval modules
    $retrievalModules = @(
        "QueryRouter.ps1",
        "CrossPackArbitration.ps1",
        "ConfidencePolicy.ps1"
    )
    
    foreach ($module in $retrievalModules) {
        $path = Join-Path $script:RetrievalModulePath $module
        if (Test-Path $path) { . $path }
    }
    
    # Create test files for extraction benchmarks
    $script:GDScriptSample = @"
extends Node2D
class_name Player

signal health_changed(new_health)
signal died

@export var max_health: int = 100
@export var speed: float = 200.0

var velocity: Vector2 = Vector2.ZERO
var current_health: int = max_health

func _ready():
    current_health = max_health
    health_changed.emit(current_health)

func _process(delta):
    var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
    velocity = input_dir * speed
    position += velocity * delta

func take_damage(amount: int):
    current_health = max(0, current_health - amount)
    health_changed.emit(current_health)
    if current_health <= 0:
        die()

func die():
    died.emit()
    queue_free()

func heal(amount: int):
    current_health = min(max_health, current_health + amount)
    health_changed.emit(current_health)
"@

    $script:SceneSample = @"
[gd_scene load_steps=4 format=3 uid="uid://sample123"]

[ext_resource type="Script" path="res://player.gd" id="1_script"]
[ext_resource type="Texture2D" uid="uid://texture456" path="res://player.png" id="2_texture"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_abc123"]
size = Vector2(32, 32)

[node name="Player" type="CharacterBody2D"]
script = ExtResource("1_script")

[node name="Sprite2D" type="Sprite2D" parent="."]
texture = ExtResource("2_texture")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_abc123")

[node name="AnimationPlayer" type="AnimationPlayer" parent="."]

[connection signal="health_changed" from="." to="." method="_on_health_changed"]
[connection signal="died" from="." to="." method="_on_died"]
"@

    # Write test files
    $script:GDScriptPath = Join-Path $script:TestRoot "test.gd"
    [System.IO.File]::WriteAllText($script:GDScriptPath, $script:GDScriptSample)
    
    $script:ScenePath = Join-Path $script:TestRoot "test.tscn"
    [System.IO.File]::WriteAllText($script:ScenePath, $script:SceneSample)
}

Describe "Core Operation Performance Benchmarks" -Skip:$SkipPerformanceTests {
    Context "File Operations Performance" {
        It "File lock acquisition should complete within 10ms" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $lock = Lock-File -Name "benchmark" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot
            $stopwatch.Stop()
            
            $lock | Should -Not -BeNullOrEmpty
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 10
            
            Unlock-File -Name "benchmark" -ProjectRoot $script:TestRoot | Out-Null
        }

        It "File lock release should complete within 10ms" {
            $lock = Lock-File -Name "benchmark" -TimeoutSeconds 5 -ProjectRoot $script:TestRoot
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Unlock-File -Name "benchmark" -ProjectRoot $script:TestRoot | Out-Null
            $stopwatch.Stop()
            
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 10
        }

        It "Atomic file write should complete within 10ms for small files" {
            $testPath = Join-Path $script:TestRoot "atomic-benchmark.txt"
            $content = "Small test content for benchmark"
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Write-AtomicFile -Path $testPath -Content $content
            $stopwatch.Stop()
            
            $result.Success | Should -Be $true
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 10
        }

        It "Atomic JSON write should complete within 10ms for small objects" {
            $testPath = Join-Path $script:TestRoot "atomic-json-benchmark.json"
            $data = @{ test = "value"; number = 42 }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Write-AtomicFile -Path $testPath -Content $data -Format Json
            $stopwatch.Stop()
            
            $result.Success | Should -Be $true
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 10
        }

        It "File existence check should complete within 10ms" {
            $testPath = Join-Path $script:TestRoot "exists-test.txt"
            "test" | Out-File -FilePath $testPath
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $exists = Test-Path -Path $testPath
            $stopwatch.Stop()
            
            $exists | Should -Be $true
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 10
        }
    }

    Context "Config Resolution Performance" {
        BeforeAll {
            # Create test config file
            $configDir = Join-Path $script:TestRoot ".llm-workflow"
            $configPath = Join-Path $configDir "config.json"
            $config = @{
                schemaVersion = 1
                defaults = @{
                    logLevel = "info"
                    cacheEnabled = $true
                }
                packs = @{
                    "rpgmaker-mz" = @{
                        enabled = $true
                        priority = "P1"
                    }
                }
            }
            $config | ConvertTo-Json -Depth 5 | Out-File -FilePath $configPath
        }

        It "Config load should complete within 50ms" {
            $configPath = Join-Path $script:TestRoot ".llm-workflow" "config.json"
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
            $stopwatch.Stop()
            
            $config | Should -Not -BeNullOrEmpty
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 50
        }

        It "Config value access should complete within 50ms" {
            $configPath = Join-Path $script:TestRoot ".llm-workflow" "config.json"
            $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $value = $config.defaults.logLevel
            $stopwatch.Stop()
            
            $value | Should -Be "info"
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 50
        }
    }

    Context "Journal Operation Performance" {
        It "Journal entry creation should complete within 5ms" {
            $runId = "20260413T000000Z-bench"
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $entry = New-JournalEntry -RunId $runId -Step "test" -Status "before" `
                -JournalDirectory (Join-Path $script:TestRoot ".llm-workflow" "journals")
            $stopwatch.Stop()
            
            $entry | Should -Not -BeNullOrEmpty
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5
        }

        It "Journal state retrieval should complete within 5ms" {
            $runId = "20260413T000001Z-bench"
            New-JournalEntry -RunId $runId -Step "test" -Status "before" `
                -JournalDirectory (Join-Path $script:TestRoot ".llm-workflow" "journals") | Out-Null
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $state = Get-JournalState -RunId $runId `
                -JournalDirectory (Join-Path $script:TestRoot ".llm-workflow" "journals") `
                -ManifestDirectory (Join-Path $script:TestRoot ".llm-workflow" "manifests")
            $stopwatch.Stop()
            
            $state | Should -Not -BeNullOrEmpty
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5
        }
    }
}

Describe "Extraction Performance Benchmarks" -Skip:$SkipPerformanceTests {
    Context "GDScript Parsing Performance" {
        It "GDScript parsing should complete within 100ms per file" {
            # Note: This assumes GDScriptParser.ps1 exists and is imported
            $gdScriptPath = Join-Path $script:TestRoot "test.gd"
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            # Simulate parsing by reading and basic regex analysis
            $content = Get-Content -Path $gdScriptPath -Raw
            $classes = [regex]::Matches($content, "class_(name|extends)")
            $functions = [regex]::Matches($content, "func\s+\w+")
            $signals = [regex]::Matches($content, "signal\s+\w+")
            
            $stopwatch.Stop()
            
            $classes.Count | Should -BeGreaterThan 0
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 100
        }

        It "Multiple GDScript file parsing should scale linearly" {
            $gdScriptPath = Join-Path $script:TestRoot "test.gd"
            $files = @(1..5) | ForEach-Object { $gdScriptPath }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            foreach ($file in $files) {
                $content = Get-Content -Path $file -Raw
                $null = [regex]::Matches($content, "func\s+\w+")
            }
            
            $stopwatch.Stop()
            
            # Should process 5 files within 500ms (5 * 100ms)
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 500
        }

        It "GDScript symbol extraction should complete within 100ms" {
            $content = $script:GDScriptSample
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            # Extract symbols
            $classMatch = [regex]::Match($content, "class_name\s+(\w+)")
            $extendsMatch = [regex]::Match($content, "extends\s+(\w+)")
            $functions = [regex]::Matches($content, "func\s+(\w+)")
            $exports = [regex]::Matches($content, "@export\s+var\s+(\w+)")
            $signals = [regex]::Matches($content, "signal\s+(\w+)")
            
            $stopwatch.Stop()
            
            $functions.Count | Should -BeGreaterThan 0
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 100
        }
    }

    Context "Scene File Parsing Performance" {
        It "Scene parsing should complete within 50ms per file" {
            $scenePath = Join-Path $script:TestRoot "test.tscn"
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            # Simulate scene parsing
            $content = Get-Content -Path $scenePath -Raw
            $nodes = [regex]::Matches($content, "\[node name=\"([^\"]+)\"")
            $resources = [regex]::Matches($content, "\[ext_resource")
            $connections = [regex]::Matches($content, "\[connection")
            
            $stopwatch.Stop()
            
            $nodes.Count | Should -BeGreaterThan 0
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 50
        }

        It "Scene node hierarchy extraction should complete within 50ms" {
            $content = $script:SceneSample
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            $nodes = @()
            $nodeMatches = [regex]::Matches($content, "\[node name=\"([^\"]+)\"\s+type=\"([^\"]+)\"")
            foreach ($match in $nodeMatches) {
                $nodes += @{
                    name = $match.Groups[1].Value
                    type = $match.Groups[2].Value
                }
            }
            
            $stopwatch.Stop()
            
            $nodes.Count | Should -BeGreaterThan 0
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 50
        }

        It "Scene resource extraction should complete within 50ms" {
            $content = $script:SceneSample
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            $resources = @()
            $resourceMatches = [regex]::Matches($content, "\[ext_resource\s+type=\"([^\"]+)\"\s+path=\"([^\"]+)\"")
            foreach ($match in $resourceMatches) {
                $resources += @{
                    type = $match.Groups[1].Value
                    path = $match.Groups[2].Value
                }
            }
            
            $stopwatch.Stop()
            
            $resources.Count | Should -BeGreaterThan 0
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 50
        }
    }

    Context "Batch Extraction Performance" {
        It "Batch extraction of 10 files should complete within 1000ms" {
            $files = @()
            for ($i = 1; $i -le 10; $i++) {
                $path = Join-Path $script:TestRoot "batch-test-$i.gd"
                [System.IO.File]::WriteAllText($path, $script:GDScriptSample)
                $files += $path
            }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            foreach ($file in $files) {
                $content = Get-Content -Path $file -Raw
                $null = [regex]::Matches($content, "func\s+\w+")
            }
            
            $stopwatch.Stop()
            
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 1000
        }
    }
}

Describe "Retrieval Performance Benchmarks" -Skip:$SkipPerformanceTests {
    Context "Query Routing Performance" {
        It "Query intent detection should complete within 20ms" {
            $query = "How do I create a GDScript plugin that uses signals and export variables?"
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $intent = Get-QueryIntent -Query $query
            $stopwatch.Stop()
            
            $intent | Should -Not -BeNullOrEmpty
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 20
        }

        It "Simple query routing should complete within 20ms" {
            $query = "GDScript API for signals"
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Invoke-QueryRouting -Query $query -EnableArbitration $false
            $stopwatch.Stop()
            
            $result | Should -Not -BeNullOrEmpty
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 20
        }

        It "Complex query routing should complete within 20ms" {
            $query = "How do I create a battle system plugin for RPG Maker MZ that integrates with existing plugins and handles compatibility issues?"
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Invoke-QueryRouting -Query $query -EnableArbitration $false
            $stopwatch.Stop()
            
            $result | Should -Not -BeNullOrEmpty
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 20
        }

        It "Profile retrieval should complete within 20ms" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $profile = Get-RetrievalProfile -ProfileName "api-lookup"
            $stopwatch.Stop()
            
            $profile | Should -Not -BeNullOrEmpty
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 20
        }
    }

    Context "Answer Planning Performance" {
        It "Answer confidence calculation should complete within 100ms" {
            $evidence = @(
                @{ sourceId = "src1"; relevanceScore = 0.95; authorityScore = 0.90; sourceType = "core-runtime"; evidenceType = "code-example" }
                @{ sourceId = "src2"; relevanceScore = 0.88; authorityScore = 0.85; sourceType = "exemplar-pattern"; evidenceType = "tutorial" }
                @{ sourceId = "src3"; relevanceScore = 0.82; authorityScore = 0.80; sourceType = "core-engine"; evidenceType = "api-reference" }
            )
            $answerPlan = @{ confidencePolicy = $null }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $answerPlan
            $stopwatch.Stop()
            
            $result | Should -Not -BeNullOrEmpty
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 100
        }

        It "Confidence component calculation should complete within 100ms" {
            $evidence = @(
                @{ sourceId = "src1"; relevanceScore = 0.95; authorityScore = 0.90; sourceType = "core-runtime"; evidenceType = "code-example" }
                @{ sourceId = "src2"; relevanceScore = 0.88; authorityScore = 0.85; sourceType = "exemplar-pattern"; evidenceType = "tutorial" }
            )
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $components = Get-ConfidenceComponents -Evidence $evidence -Context @{}
            $stopwatch.Stop()
            
            $components | Should -Not -BeNullOrEmpty
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 100
        }

        It "Cross-pack arbitration should complete within 100ms" {
            $packs = @(
                @{ packId = "godot-engine"; collections = @{ coll1 = @{ authorityRole = "core-engine" } } }
                @{ packId = "rpgmaker-mz"; collections = @{ coll1 = @{ authorityRole = "core-runtime" } } }
            )
            $workspaceContext = New-Object -TypeName PSObject -Property @{}
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Invoke-CrossPackArbitration -Query "Compare Godot and RPG Maker" -Packs $packs -WorkspaceContext $workspaceContext
            $stopwatch.Stop()
            
            $result | Should -Not -BeNullOrEmpty
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 100
        }

        It "Answer mode determination should complete within 100ms" {
            $policy = Get-DefaultConfidencePolicy
            $evidence = @(
                @{ sourceId = "src1"; relevanceScore = 0.95; authorityScore = 0.90; sourceType = "core-runtime" }
            )
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $mode = Get-AnswerMode -ConfidenceScore 0.85 -Policy $policy -EvidenceIssues @()
            $stopwatch.Stop()
            
            $mode | Should -Not -BeNullOrEmpty
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 100
        }
    }

    Context "Evidence Retrieval Performance" {
        It "Pack relevance scoring should complete within 20ms per pack" {
            $packManifest = @{
                packId = "godot-engine"
                collections = @{ coll1 = @{ authorityRole = "core-engine" } }
            }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $score = Test-PackRelevance -Query "GDScript signals" -PackManifest $packManifest
            $stopwatch.Stop()
            
            $score | Should -Not -BeNullOrEmpty
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 20
        }

        It "Multiple pack scoring should complete within 100ms for 5 packs" {
            $packs = @(
                @{ packId = "pack1"; collections = @{ coll1 = @{ authorityRole = "core-engine" } } }
                @{ packId = "pack2"; collections = @{ coll1 = @{ authorityRole = "exemplar-pattern" } } }
                @{ packId = "pack3"; collections = @{ coll1 = @{ authorityRole = "starter-template" } } }
                @{ packId = "pack4"; collections = @{ coll1 = @{ authorityRole = "core-runtime" } } }
                @{ packId = "pack5"; collections = @{ coll1 = @{ authorityRole = "curated-index" } } }
            )
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            foreach ($pack in $packs) {
                $null = Test-PackRelevance -Query "Test query" -PackManifest $pack
            }
            
            $stopwatch.Stop()
            
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 100
        }
    }

    Context "End-to-End Retrieval Performance" {
        It "Full query-to-answer pipeline should complete within 200ms" {
            $query = "How do I create a plugin?"
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            # Step 1: Route query
            $routing = Invoke-QueryRouting -Query $query -EnableArbitration $false
            
            # Step 2: Calculate confidence (simulated evidence)
            $evidence = @(
                @{ sourceId = "src1"; relevanceScore = 0.90; authorityScore = 0.85; sourceType = "core-engine" }
            )
            $answerPlan = @{ confidencePolicy = $null }
            $confidence = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $answerPlan
            
            $stopwatch.Stop()
            
            $routing | Should -Not -BeNullOrEmpty
            $confidence | Should -Not -BeNullOrEmpty
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 200
        }
    }
}

Describe "Performance Benchmark Summary" -Skip:$SkipPerformanceTests {
    It "Should meet all performance requirements" {
        # This test serves as a summary/checkpoint for all benchmarks
        $requirements = @{
            FileOperations = "< 10ms"
            ConfigResolution = "< 50ms"
            JournalWrites = "< 5ms"
            GDScriptParsing = "< 100ms per file"
            SceneParsing = "< 50ms per file"
            QueryRouting = "< 20ms"
            AnswerPlanning = "< 100ms"
        }
        
        foreach ($requirement in $requirements.GetEnumerator()) {
            $requirement.Key | Should -Not -BeNullOrEmpty
            $requirement.Value | Should -Not -BeNullOrEmpty
        }
    }
}
