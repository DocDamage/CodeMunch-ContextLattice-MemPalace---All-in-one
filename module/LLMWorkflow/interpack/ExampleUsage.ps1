#Requires -Version 7.0
<#
.SYNOPSIS
    Inter-Pack Pipeline Example Usage
    
.DESCRIPTION
    Demonstrates usage of all Inter-Pack Pipeline modules:
    - VoiceAnimationPipeline
    - AIGenerationPipeline
    - MLModelDeploymentPipeline
    - ProvenanceTracker
    
.EXAMPLE
    . .\ExampleUsage.ps1
    Run-AllExamples
#>

# Import all pipeline modules
Import-Module "f:\stuff from desktop\CodeMunch-ContextLattice-MemPalace---All-in-one\module\LLMWorkflow\interpack\VoiceAnimationPipeline.ps1" -Force
Import-Module "f:\stuff from desktop\CodeMunch-ContextLattice-MemPalace---All-in-one\module\LLMWorkflow\interpack\AIGenerationPipeline.ps1" -Force
Import-Module "f:\stuff from desktop\CodeMunch-ContextLattice-MemPalace---All-in-one\module\LLMWorkflow\interpack\MLModelDeploymentPipeline.ps1" -Force
Import-Module "f:\stuff from desktop\CodeMunch-ContextLattice-MemPalace---All-in-one\module\LLMWorkflow\interpack\ProvenanceTracker.ps1" -Force

#region Voice Animation Pipeline Examples

function Example-VoiceAnimationPipeline {
    Write-Host "`n=== Voice Animation Pipeline Example ===" -ForegroundColor Cyan
    
    # 1. Initialize pipeline
    $voicePipeline = Start-VoiceAnimationPipeline `
        -VoicePack "VoiceGenPack" `
        -AnimationPack "BlenderPack" `
        -Config @{ FrameRate = 30; VisemeSet = "ARKit" }
    
    # 2. Create a mock audio file
    $mockAudio = Join-Path $PWD "mock_voice.wav"
    "RIFF`0`0`0`0WAVE" | Out-File -FilePath $mockAudio -Encoding utf8
    
    # 3. Sync voice to animation
    $track = Sync-VoiceToAnimation `
        -Pipeline $voicePipeline `
        -AudioFile $mockAudio `
        -Text "Hello, this is a test of voice animation synchronization."
    
    # 4. Convert visemes to blend shapes
    $blendShapes = Convert-VisemesToBlendShapes `
        -VisemeTrack $track `
        -BlendShapeSet "ARKit" `
        -SmoothTransitions
    
    # 5. Export lip sync animation
    $exportResult = Export-LipSyncAnimation `
        -BlendShapeData $blendShapes `
        -OutputPath "lipsync_animation.json" `
        -Format "JSON" `
        -IncludeAudioRef
    
    # 6. Validate synchronization
    $validation = Test-VoiceAnimationSync `
        -Track $track `
        -AudioFile $mockAudio `
        -QualityThreshold 0.8 `
        -DetailedReport
    
    if ($validation.ValidationReport) {
        $validation.ValidationReport | Out-File -FilePath "validation_report.txt" -Encoding UTF8
    }
    
    Write-Host "Voice Animation Pipeline Example Complete!" -ForegroundColor Green
    
    # Cleanup
    Remove-Item $mockAudio -ErrorAction SilentlyContinue
}

#endregion

#region AI Generation Pipeline Examples

function Example-AIGenerationPipeline {
    Write-Host "`n=== AI Generation Pipeline Example ===" -ForegroundColor Cyan
    
    # 1. Create pipeline configuration
    $config = New-AIGenerationPipeline `
        -Provider "Mock" `
        -TargetPack "GodotPack" `
        -Config @{ 
            DefaultWidth = 1024; 
            DefaultHeight = 1024; 
            ProvenanceTracking = $true;
            OptimizationSettings = @{
                MaxPolygonCount = 5000
                TargetTextureSize = 1024
                GenerateLODs = $true
            }
        }
    
    Write-Host "Pipeline configuration created" -ForegroundColor Gray
    
    # 2. Initialize AI pipeline
    $aiPipeline = Start-AIGenerationPipeline `
        -Provider "Mock" `
        -TargetPack "GodotPack" `
        -Config $config
    
    # 3. Use New-AIGeneratedAsset (unified interface) for different asset types
    
    # Generate Image
    $imageAsset = New-AIGeneratedAsset `
        -Pipeline $aiPipeline `
        -AssetType "Image" `
        -Prompt "A futuristic cyberpunk city at night with neon lights" `
        -Parameters @{
            NegativePrompt = "blurry, low quality, distorted"
            Steps = 30
            GuidanceScale = 7.5
            Seed = 12345
        }
    
    Write-Host "Image asset created: $($imageAsset.AssetId)" -ForegroundColor Gray
    
    # Generate Mesh (using image-to-3D workflow)
    $meshAsset = New-AIGeneratedAsset `
        -Pipeline $aiPipeline `
        -AssetType "Mesh" `
        -Prompt "sci-fi building structure" `
        -Parameters @{
            Method = "SingleImage"
            Quality = "High"
            Format = "GLB"
            GenerateTexture = $true
        }
    
    Write-Host "Mesh asset created: $($meshAsset.AssetId)" -ForegroundColor Gray
    
    # Generate Audio (TTS)
    $audioAsset = New-AIGeneratedAsset `
        -Pipeline $aiPipeline `
        -AssetType "Audio" `
        -Prompt "Welcome to the game! Victory achieved!" `
        -Parameters @{
            Duration = 3.0
            SampleRate = 44100
            Voice = "default"
        }
    
    Write-Host "Audio asset created: $($audioAsset.AssetId)" -ForegroundColor Gray
    
    # 4. Convert assets to game format
    $convertedMesh = Convert-ToGameFormat `
        -Pipeline $aiPipeline `
        -Asset $meshAsset `
        -TargetFormat "GLTF" `
        -OutputDir "./converted"
    
    $convertedImage = Convert-ToGameFormat `
        -Pipeline $aiPipeline `
        -Asset $imageAsset `
        -TargetFormat "PNG" `
        -OutputDir "./converted"
    
    Write-Host "Assets converted to game format" -ForegroundColor Gray
    
    # 5. Optimize assets for game
    $optimizedMesh = Optimize-AssetForGame `
        -Pipeline $aiPipeline `
        -Asset $convertedMesh `
        -OptimizationLevel "Medium" `
        -TargetPolygonCount 5000
    
    $optimizedImage = Optimize-AssetForGame `
        -Pipeline $aiPipeline `
        -Asset $convertedImage `
        -TargetTextureSize 1024
    
    Write-Host "Assets optimized for game" -ForegroundColor Gray
    
    # 6. Register with provenance tracking
    $registeredMesh = Register-GeneratedAsset `
        -Pipeline $aiPipeline `
        -Asset $optimizedMesh `
        -WorkflowId "example_workflow_001"
    
    $registeredImage = Register-GeneratedAsset `
        -Pipeline $aiPipeline `
        -Asset $optimizedImage `
        -WorkflowId "example_workflow_001"
    
    Write-Host "Assets registered with provenance" -ForegroundColor Gray
    
    # 7. Get generation status
    $status = Get-AIGenerationStatus -Pipeline $aiPipeline -IncludeDetails
    Write-Host "Generation status: $($status.CompletedCount) completed, $($status.FailedCount) failed" -ForegroundColor Gray
    
    # 8. Import to Godot (would import to actual project if available)
    $importResult = Import-ToGodot `
        -Pipeline $aiPipeline `
        -Asset $registeredMesh `
        -ImportPath "res://models/buildings"
    
    $importResult2 = Import-ToGodot `
        -Pipeline $aiPipeline `
        -Asset $registeredImage `
        -ImportPath "res://textures/environment"
    
    # 9. Also demonstrate Blender import
    $blenderResult = Import-ToBlender `
        -Pipeline $aiPipeline `
        -Asset $registeredMesh `
        -Collection "AI_Generated"
    
    # 10. Legacy functions still work
    $textureSet = Invoke-TextureGeneration `
        -Pipeline $aiPipeline `
        -Description "weathered sci-fi metal panels" `
        -MaterialType "Metal" `
        -Resolution 2048 `
        -Maps @("BaseColor", "Normal", "Roughness", "Metallic", "AO") `
        -Seamless
    
    $material = Invoke-MaterialGeneration `
        -Pipeline $aiPipeline `
        -Description "shiny blue metallic surface" `
        -ShaderType "PBR" `
        -TextureSet $textureSet `
        -EngineSpecific "Godot"
    
    # 11. Convert legacy assets to pack format
    $convertedModel = Convert-AIAssetToPack `
        -Pipeline $aiPipeline `
        -Asset $meshAsset `
        -OutputDir "models/characters"
    
    Write-Host "AI Generation Pipeline Example Complete!" -ForegroundColor Green
    Write-Host "Generated assets:" -ForegroundColor Gray
    Write-Host "  - Image: $($imageAsset.AssetId)" -ForegroundColor Gray
    Write-Host "  - Mesh: $($meshAsset.AssetId)" -ForegroundColor Gray
    Write-Host "  - Audio: $($audioAsset.AssetId)" -ForegroundColor Gray
    Write-Host "  - Texture Set: $($textureSet.SetId)" -ForegroundColor Gray
    Write-Host "  - Material: $($material.MaterialId)" -ForegroundColor Gray
}

function Example-AIGenerationWorkflowOrchestrator {
    Write-Host "`n=== AI Generation Workflow Orchestrator Example ===" -ForegroundColor Cyan
    
    # Create pipeline configuration
    $config = New-AIGenerationPipeline `
        -Provider "Mock" `
        -TargetPack "GodotPack" `
        -Config @{
            ProvenanceTracking = $true
            AutoImport = $false
            OptimizationSettings = @{
                MaxPolygonCount = 5000
                TargetTextureSize = 1024
                CompressionLevel = "Medium"
            }
        }
    
    # Define workflow with multiple assets to generate
    $workflow = @{
        Assets = @(
            @{
                Type = "Image"
                Prompt = "fantasy castle in mountains"
                OutputName = "castle_texture"
                TargetFormat = "PNG"
                Parameters = @{
                    Width = 1024
                    Height = 1024
                    Seed = 42
                }
            },
            @{
                Type = "Mesh"
                Prompt = "treasure chest with gold details"
                OutputName = "treasure_chest"
                TargetFormat = "GLB"
                Parameters = @{
                    Method = "SingleImage"
                    Quality = "High"
                    GenerateTexture = $true
                }
            },
            @{
                Type = "Audio"
                Prompt = "epic battle music intro"
                OutputName = "battle_music"
                TargetFormat = "WAV"
                Parameters = @{
                    Duration = 5.0
                    SampleRate = 44100
                }
            },
            @{
                Type = "Texture"
                Prompt = "weathered stone wall with moss"
                OutputName = "stone_wall"
                TargetFormat = "PNG"
                Parameters = @{
                    MaterialType = "Stone"
                    Resolution = 2048
                    Maps = @("BaseColor", "Normal", "Roughness")
                    Seamless = $true
                }
            }
        )
    }
    
    # Execute full workflow
    Write-Host "Starting workflow with $($workflow.Assets.Count) assets..." -ForegroundColor Yellow
    
    $result = Start-AIGenerationWorkflow `
        -Config $config `
        -Workflow $workflow `
        -AutoImport
    
    Write-Host "Workflow Complete! ID: $($result.WorkflowId)" -ForegroundColor Green
    Write-Host "Total assets generated: $($result.GeneratedAssets.Count)" -ForegroundColor Gray
    Write-Host "Status: $($result.Status)" -ForegroundColor Gray
    
    foreach ($asset in $result.GeneratedAssets) {
        Write-Host "  - $($asset.AssetType): $($asset.AssetId) -> $($asset.FilePath)" -ForegroundColor Gray
    }
}

#endregion

#region ML Model Deployment Pipeline Examples

function Example-MLModelDeploymentPipeline {
    Write-Host "`n=== ML Model Deployment Pipeline Example ===" -ForegroundColor Cyan
    
    # Create a mock ONNX model file
    $mockModel = Join-Path $PWD "mock_model.onnx"
    "ONNX MOCK MODEL DATA" | Out-File -FilePath $mockModel -Encoding utf8
    
    # 1. Initialize ML deployment pipeline for Godot
    $mlPipeline = Start-MLDeploymentPipeline `
        -ModelFormat "ONNX" `
        -TargetEngine "Godot" `
        -TargetVersion "4.2" `
        -Config @{ 
            RuntimeEngine = "ONNXRuntime"
            UseGPU = $false
            ThreadCount = 4
        }
    
    # 2. Package model for runtime
    $package = Package-MLModelForRuntime `
        -Pipeline $mlPipeline `
        -ModelPath $mockModel `
        -Optimize `
        -IncludeRuntime `
        -Metadata @{ 
            Description = "Character animation prediction model"
            Author = "ML Team"
            Version = "1.0.0"
        }
    
    # 3. Create a mock Godot project
    $godotProject = Join-Path $PWD "mock_godot_project"
    if (-not (Test-Path $godotProject)) {
        New-Item -ItemType Directory -Path $godotProject -Force | Out-Null
    }
    "; Godot Project`nconfig_version=5" | Out-File -FilePath (Join-Path $godotProject "project.godot") -Encoding UTF8
    
    # 4. Deploy to Godot
    $godotDeployment = Deploy-MLModelToGodot `
        -Pipeline $mlPipeline `
        -Package $package `
        -ProjectPath $godotProject `
        -ExtensionName "AIAnimationExtension" `
        -AutoConfigure
    
    # 5. Test inference
    $testResult = Test-MLModelInference `
        -Pipeline $mlPipeline `
        -Deployment $godotDeployment `
        -Iterations 50 `
        -OutputReport "inference_report.json"
    
    Write-Host "ML Deployment Pipeline (Godot) Example Complete!" -ForegroundColor Green
    
    # 6. Now deploy to Blender
    $mlPipelineBlender = Start-MLDeploymentPipeline `
        -ModelFormat "ONNX" `
        -TargetEngine "Blender" `
        -TargetVersion "4.0" `
        -Config @{ RuntimeEngine = "ONNXRuntime" }
    
    $packageBlender = Package-MLModelForRuntime `
        -Pipeline $mlPipelineBlender `
        -ModelPath $mockModel
    
    $blenderDeployment = Deploy-MLModelToBlender `
        -Pipeline $mlPipelineBlender `
        -Package $packageBlender `
        -AddonName "ml_animation_tools" `
        -Category "Animation"
    
    $testResultBlender = Test-MLModelInference `
        -Pipeline $mlPipelineBlender `
        -Deployment $blenderDeployment `
        -Iterations 30
    
    Write-Host "ML Deployment Pipeline (Blender) Example Complete!" -ForegroundColor Green
    
    # Cleanup
    Remove-Item $mockModel -ErrorAction SilentlyContinue
}

#endregion

#region Provenance Tracker Examples

function Example-ProvenanceTracker {
    Write-Host "`n=== Provenance Tracker Example ===" -ForegroundColor Cyan
    
    # 1. Create initial provenance record for AI-generated asset
    $record1 = New-ProvenanceRecord `
        -AssetId "ai_texture_001" `
        -Operation "TextToImageGeneration" `
        -PackId "AIGenPack" `
        -Parameters @{ 
            Prompt = "sci-fi metal texture"
            Steps = 30
            Seed = 12345
        } `
        -Outputs @{
            FilePath = "generated/texture_001.png"
            Resolution = "1024x1024"
        } `
        -Metadata @{
            Generator = "Stable Diffusion XL"
            GPU = "RTX 4090"
        }
    
    # 2. Add chain link for 3D conversion
    $record2 = Add-ProvenanceChain `
        -ParentProvenanceId $record1.ProvenanceId `
        -ChildAssetId "model_3d_001" `
        -ChildOperation "ImageTo3DConversion" `
        -ChildPackId "BlenderPack" `
        -Parameters @{
            Method = "NeRF"
            Quality = "High"
        }
    
    # 3. Add another link for animation
    $record3 = Add-ProvenanceChain `
        -ParentProvenanceId $record2.ProvenanceId `
        -ChildAssetId "animated_model_001" `
        -ChildOperation "Sync" `
        -ChildPackId "GodotPack" `
        -Parameters @{
            AnimationType = "Idle"
            FrameRate = 30
        }
    
    # 4. Get full provenance history
    $history = Get-ProvenanceHistory `
        -AssetId "animated_model_001" `
        -IncludeSiblings
    
    Write-Host "Provenance chain retrieved:" -ForegroundColor Green
    Write-Host "  Chain length: $($history.ChainLength)" -ForegroundColor Gray
    Write-Host "  Operations: $($history.Operations -join ' -> ')" -ForegroundColor Gray
    Write-Host "  Pack transitions: $($history.PackTransitions.Count)" -ForegroundColor Gray
    
    # 5. Export provenance manifest
    $exportResult = Export-ProvenanceManifest `
        -AssetId "animated_model_001" `
        -OutputPath "provenance_manifest.json" `
        -Format "JSON" `
        -IncludeFullChain
    
    # 6. Export as C2PA format
    $c2paResult = Export-ProvenanceManifest `
        -AssetId "animated_model_001" `
        -OutputPath "provenance_c2pa.json" `
        -Format "C2PA"
    
    # 7. Validate integrity
    $validation = Validate-ProvenanceIntegrity `
        -AssetId "animated_model_001" `
        -StrictMode
    
    Write-Host "Provenance Tracker Example Complete!" -ForegroundColor Green
    Write-Host "Validation result: $(if ($validation.IsValid) { 'PASSED' } else { 'FAILED' })" -ForegroundColor $(if ($validation.IsValid) { 'Green' } else { 'Red' })
}

#endregion

#region Combined Workflow Example

function Example-CombinedWorkflow {
    Write-Host "`n=== Combined Cross-Domain Workflow Example ===" -ForegroundColor Cyan
    Write-Host "Demonstrating: AI Generation → Provenance → Godot Deployment" -ForegroundColor Gray
    
    # Step 1: AI Generation with Provenance
    $aiPipeline = Start-AIGenerationPipeline -Provider "Mock" -TargetPack "GodotPack"
    
    # Generate texture with provenance
    $texture = Invoke-TextureGeneration `
        -Pipeline $aiPipeline `
        -Description "magical crystal surface" `
        -MaterialType "Stone" `
        -Resolution 2048
    
    # Create provenance record
    $provRecord = New-ProvenanceRecord `
        -AssetId $texture.SetId `
        -Operation "TextureGeneration" `
        -PackId "AIGenPack" `
        -Parameters $texture.Parameters
    
    # Step 2: Convert to material and track
    $material = Invoke-MaterialGeneration `
        -Pipeline $aiPipeline `
        -Description "crystal material with glow" `
        -TextureSet $texture `
        -EngineSpecific "Godot"
    
    $materialProv = Add-ProvenanceChain `
        -ParentProvenanceId $provRecord.ProvenanceId `
        -ChildAssetId $material.MaterialId `
        -ChildOperation "MaterialGeneration" `
        -ChildPackId "GodotPack"
    
    # Step 3: Package for Godot
    $converted = Convert-AIAssetToPack `
        -Pipeline $aiPipeline `
        -Asset $texture
    
    # Step 4: Export final provenance manifest
    $manifestExport = Export-ProvenanceManifest `
        -AssetId $material.MaterialId `
        -OutputPath "crystal_material_provenance.json" `
        -Format "JSON"
    
    Write-Host "`nCombined Workflow Complete!" -ForegroundColor Green
    Write-Host "Asset flow: AI Generation Pack → Godot Pack" -ForegroundColor Gray
    Write-Host "Provenance records: 2" -ForegroundColor Gray
    Write-Host "Manifest: $($manifestExport.OutputPath)" -ForegroundColor Gray
}

#endregion

#region Main Runner

function Run-AllExamples {
    Write-Host "`n========================================" -ForegroundColor White
    Write-Host "  LLM Workflow - Inter-Pack Pipeline Examples" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor White
    
    try {
        Example-VoiceAnimationPipeline
    } catch {
        Write-Warning "Voice Animation Pipeline example failed: $_"
    }
    
    try {
        Example-AIGenerationPipeline
    } catch {
        Write-Warning "AI Generation Pipeline example failed: $_"
    }
    
    try {
        Example-AIGenerationWorkflowOrchestrator
    } catch {
        Write-Warning "AI Generation Workflow Orchestrator example failed: $_"
    }
    
    try {
        Example-MLModelDeploymentPipeline
    } catch {
        Write-Warning "ML Model Deployment Pipeline example failed: $_"
    }
    
    try {
        Example-ProvenanceTracker
    } catch {
        Write-Warning "Provenance Tracker example failed: $_"
    }
    
    try {
        Example-CombinedWorkflow
    } catch {
        Write-Warning "Combined Workflow example failed: $_"
    }
    
    Write-Host "`n========================================" -ForegroundColor White
    Write-Host "  All Examples Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor White
}

#endregion

# Export example functions
Export-ModuleMember -Function @(
    'Example-VoiceAnimationPipeline',
    'Example-AIGenerationPipeline',
    'Example-AIGenerationWorkflowOrchestrator',
    'Example-MLModelDeploymentPipeline',
    'Example-ProvenanceTracker',
    'Example-CombinedWorkflow',
    'Run-AllExamples'
)
