# LLM Workflow Game Team Functions
# PowerShell 5.1+ compatible
# ASCII-only for Unicode safety

$GameTemplateRoot = Join-Path $PSScriptRoot "templates\game"
$GamePresetPath = Join-Path $GameTemplateRoot "game-preset.json"

function Get-GamePresetPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return $GamePresetPath
}

function Test-GamePresetAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return (Test-Path -LiteralPath $GamePresetPath)
}

function Get-GamePresetData {
    [CmdletBinding()]
    param()
    
    if (-not (Test-Path -LiteralPath $GamePresetPath)) {
        throw "Game preset not found: $GamePresetPath"
    }
    
    try {
        $content = Get-Content -LiteralPath $GamePresetPath -Raw -Encoding UTF8
        return ($content | ConvertFrom-Json)
    } catch {
        throw "Failed to parse game preset: $($_.Exception.Message)"
    }
}

function New-LLMWorkflowGamePreset {
    <#
    .SYNOPSIS
        Creates a game project structure with GDD, asset management, and task board.
    .DESCRIPTION
        Sets up a complete game development workflow with docs, assets, and templates.
        Optimized for rapid prototyping and game jam workflows.
    .PARAMETER ProjectRoot
        Path to the project root. Defaults to current directory.
    .PARAMETER ProjectName
        Name of the game project.
    .PARAMETER Template
        Game template to use (2d-platformer, topdown-rpg, puzzle, etc.).
    .PARAMETER Engine
        Game engine being used (Unity, Godot, Unreal, etc.).
    .PARAMETER JamMode
        Enable jam mode for fast iteration (sets ContinueOnError, lightweight artifacts).
    .PARAMETER SkipAssetFolders
        Skip creating asset subfolders (sfx, music, art).
    .EXAMPLE
        New-LLMWorkflowGamePreset -ProjectName "MyPlatformer" -Template "2d-platformer" -Engine "Godot"
        Creates a new 2D platformer project using Godot.
    .EXAMPLE
        New-LLMWorkflowGamePreset -JamMode
        Sets up a jam-optimized project in current directory.
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = ".",
        [string]$ProjectName = "",
        [ValidateSet("2d-platformer", "topdown-rpg", "puzzle", "fps-prototype", "visual-novel", "roguelike", "card-game", "endless-runner", "")]
        [string]$Template = "",
        [string]$Engine = "",
        [switch]$JamMode,
        [switch]$SkipAssetFolders
    )
    
    $ErrorActionPreference = "Stop"
    
    # Resolve or create project path
    if (Test-Path -LiteralPath $ProjectRoot) {
        $projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
    } else {
        New-Item -ItemType Directory -Path $ProjectRoot -Force | Out-Null
        $projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
    }
    
    # Determine project name
    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        $ProjectName = Split-Path -Leaf $projectPath
    }
    
    Write-Host "[gameteam] Creating game project: $ProjectName" -ForegroundColor Cyan
    
    # Load preset data
    $preset = Get-GamePresetData
    
    # Create folder structure
    $folders = @("docs", "assets", ".llm-workflow")
    if (-not $SkipAssetFolders) {
        $folders += @("assets\sfx", "assets\music", "assets\art")
    }
    
    foreach ($folder in $folders) {
        $folderPath = Join-Path $projectPath $folder
        if (-not (Test-Path -LiteralPath $folderPath)) {
            New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
            Write-Host "[gameteam] Created: $folder/" -ForegroundColor Gray
        } else {
            Write-Host "[gameteam] Exists: $folder/" -ForegroundColor DarkGray
        }
    }
    
    # Copy template files
    $templateFiles = @(
        @{ Source = "GDD.md"; Dest = "docs\GDD.md" },
        @{ Source = "TASKS.md"; Dest = "docs\TASKS.md" },
        @{ Source = "ASSET_MANIFEST.json"; Dest = "assets\ASSET_MANIFEST.json" }
    )
    
    $createdFiles = @()
    foreach ($tf in $templateFiles) {
        $sourcePath = Join-Path $GameTemplateRoot $tf.Source
        $destPath = Join-Path $projectPath $tf.Dest
        
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            Write-Warning "[gameteam] Template not found: $($tf.Source)"
            continue
        }
        
        if (Test-Path -LiteralPath $destPath) {
            Write-Host "[gameteam] Exists: $($tf.Dest)" -ForegroundColor DarkGray
        } else {
            Copy-Item -LiteralPath $sourcePath -Destination $destPath -Force
            Write-Host "[gameteam] Created: $($tf.Dest)" -ForegroundColor Gray
            $createdFiles += $tf.Dest
        }
    }
    
    # Create game-preset.json config
    $configPath = Join-Path $projectPath ".llm-workflow\game-preset.json"
    $config = @{
        projectName = $ProjectName
        created = (Get-Date -Format "yyyy-MM-dd")
        template = $Template
        engine = $Engine
        jamMode = $JamMode.IsPresent
        version = "1.0.0"
    }
    
    if (Test-Path -LiteralPath $configPath) {
        Write-Host "[gameteam] Exists: .llm-workflow/game-preset.json" -ForegroundColor DarkGray
    } else {
        $config | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $configPath -Encoding UTF8
        Write-Host "[gameteam] Created: .llm-workflow/game-preset.json" -ForegroundColor Gray
        $createdFiles += ".llm-workflow/game-preset.json"
    }
    
    # Apply template-specific defaults if specified
    if (-not [string]::IsNullOrWhiteSpace($Template)) {
        $templateData = $preset.gameTemplates | Where-Object { $_.id -eq $Template } | Select-Object -First 1
        if ($templateData) {
            Write-Host "[gameteam] Template: $($templateData.name)" -ForegroundColor Cyan
            if ([string]::IsNullOrWhiteSpace($Engine) -and $templateData.defaultEngine) {
                $Engine = ($templateData.defaultEngine -split "\|")[0]
                Write-Host "[gameteam] Suggested engine: $Engine" -ForegroundColor Gray
            }
        }
    }
    
    # Jam mode settings
    if ($JamMode) {
        Write-Host "[gameteam] Jam Mode enabled - fast iteration settings applied" -ForegroundColor Yellow
    }
    
    # Return summary
    return [pscustomobject]@{
        ProjectName = $ProjectName
        ProjectRoot = $projectPath
        Template = $Template
        Engine = $Engine
        JamMode = $JamMode.IsPresent
        CreatedFolders = $folders
        CreatedFiles = $createdFiles
        Success = $true
    }
}

function Get-LLMWorkflowGameTemplates {
    <#
    .SYNOPSIS
        Lists available game templates.
    .DESCRIPTION
        Returns a list of pre-defined game templates with descriptions and tags.
    .EXAMPLE
        Get-LLMWorkflowGameTemplates
        Lists all available templates.
    .EXAMPLE
        Get-LLMWorkflowGameTemplates | Where-Object { $_.tags -contains "2d" }
        Lists only 2D game templates.
    #>
    [CmdletBinding()]
    param()
    
    $preset = Get-GamePresetData
    $templates = @()
    
    foreach ($t in $preset.gameTemplates) {
        $templates += [pscustomobject]@{
            Id = $t.id
            Name = $t.name
            Description = $t.description
            Tags = $t.tags
            DefaultEngine = $t.defaultEngine
        }
    }
    
    return $templates
}

function Export-LLMWorkflowAssetManifest {
    <#
    .SYNOPSIS
        Generates or updates the asset tracking manifest.
    .DESCRIPTION
        Scans asset folders and generates a manifest with metadata and license tracking.
    .PARAMETER ProjectRoot
        Path to the project root. Defaults to current directory.
    .PARAMETER ScanFolders
        Scan asset folders for files and update the manifest.
    .PARAMETER OutputPath
        Custom output path for the manifest.
    .PARAMETER Format
        Output format (json or csv).
    .EXAMPLE
        Export-LLMWorkflowAssetManifest -ScanFolders
        Scans assets and updates the manifest.
    .EXAMPLE
        Export-LLMWorkflowAssetManifest -Format csv -OutputPath "assets/export.csv"
        Exports manifest to CSV format.
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = ".",
        [switch]$ScanFolders,
        [string]$OutputPath = "",
        [ValidateSet("json", "csv")]
        [string]$Format = "json"
    )
    
    $projectPath = Resolve-Path -LiteralPath $ProjectRoot
    $manifestPath = Join-Path $projectPath "assets\ASSET_MANIFEST.json"
    
    # Load or create manifest
    $manifest = $null
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $content = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
            $manifest = $content | ConvertFrom-Json
        } catch {
            Write-Warning "Failed to parse existing manifest, creating new one"
            $manifest = $null
        }
    }
    
    # Initialize default structure if needed
    if ($null -eq $manifest) {
        $preset = Get-GamePresetData
        $manifest = $preset | Select-Object -ExpandProperty templates
        $manifest = @{
            project = Split-Path -Leaf $projectPath
            version = "1.0.0"
            created = (Get-Date -Format "yyyy-MM-dd")
            lastUpdated = (Get-Date -Format "yyyy-MM-dd")
            assetCount = 0
            totalSize = "0 MB"
            categories = @{
                art = @{ description = "Visual assets"; folder = "assets/art"; assetCount = 0; assets = @() }
                sfx = @{ description = "Sound effects"; folder = "assets/sfx"; assetCount = 0; assets = @() }
                music = @{ description = "Background music"; folder = "assets/music"; assetCount = 0; assets = @() }
            }
            licenseSummary = @{ original = 0; cc0 = 0; ccBy = 0; ccBySa = 0; proprietary = 0; unknown = 0 }
        }
    }
    
    $manifest.lastUpdated = (Get-Date -Format "yyyy-MM-dd")
    
    # Scan folders if requested
    if ($ScanFolders) {
        Write-Host "[gameteam] Scanning asset folders..." -ForegroundColor Cyan
        
        $totalCount = 0
        $totalSize = 0
        $licenseCounts = @{ original = 0; cc0 = 0; ccBy = 0; ccBySa = 0; proprietary = 0; unknown = 0 }
        
        foreach ($category in @("art", "sfx", "music")) {
            $folderPath = Join-Path $projectPath "assets\$category"
            if (-not (Test-Path -LiteralPath $folderPath)) { continue }
            
            $files = Get-ChildItem -LiteralPath $folderPath -File -Recurse
            $categoryAssets = @()
            $categorySize = 0
            
            foreach ($file in $files) {
                $asset = @{
                    id = "$category-$($totalCount + 1)"
                    name = $file.BaseName
                    fileName = $file.Name
                    path = $file.FullName.Replace($projectPath, "").TrimStart("\", "/")
                    format = $file.Extension.TrimStart(".")
                    fileSize = "{0:N0} KB" -f ($file.Length / 1KB)
                    modifiedDate = $file.LastWriteTime.ToString("yyyy-MM-dd")
                    status = "done"
                    license = "unknown"
                }
                
                $categoryAssets += $asset
                $totalCount++
                $categorySize += $file.Length
                $licenseCounts.unknown++
            }
            
            $manifest.categories.$category.assets = $categoryAssets
            $manifest.categories.$category.assetCount = $categoryAssets.Count
            $totalSize += $categorySize
        }
        
        $manifest.assetCount = $totalCount
        $manifest.totalSize = "{0:N1} MB" -f ($totalSize / 1MB)
        $manifest.licenseSummary = $licenseCounts
        
        Write-Host "[gameteam] Found $totalCount assets" -ForegroundColor Green
    }
    
    # Determine output path
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = $manifestPath
    } else {
        $OutputPath = Join-Path $projectPath $OutputPath
    }
    
    # Save in requested format
    if ($Format -eq "json") {
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
        Write-Host "[gameteam] Manifest saved: $OutputPath" -ForegroundColor Green
    } elseif ($Format -eq "csv") {
        $csvData = @()
        foreach ($category in $manifest.categories.PSObject.Properties.Name) {
            foreach ($asset in $manifest.categories.$category.assets) {
                $csvData += [pscustomobject]@{
                    Category = $category
                    Name = $asset.name
                    FileName = $asset.fileName
                    Path = $asset.path
                    Format = $asset.format
                    Size = $asset.fileSize
                    License = $asset.license
                    Status = $asset.status
                    Tags = ($asset.tags -join ";")
                }
            }
        }
        $csvData | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Host "[gameteam] Manifest exported to CSV: $OutputPath" -ForegroundColor Green
    }
    
    return [pscustomobject]@{
        AssetCount = $manifest.assetCount
        TotalSize = $manifest.totalSize
        ManifestPath = $OutputPath
        Format = $Format
    }
}

function Invoke-LLMWorkflowGameUp {
    <#
    .SYNOPSIS
        Game team workflow bootstrap with preset support.
    .DESCRIPTION
        Extended version of Invoke-LLMWorkflowUp with game-specific features.
        Automatically detects game projects and applies appropriate settings.
    .PARAMETER ProjectRoot
        Path to the project root.
    .PARAMETER GameTeam
        Activate game team preset.
    .PARAMETER Template
        Game template to use.
    .PARAMETER Engine
        Game engine being used.
    .PARAMETER JamMode
        Enable jam mode (fast iteration, ContinueOnError).
    .PARAMETER All other parameters from Invoke-LLMWorkflowUp
    .EXAMPLE
        Invoke-LLMWorkflowGameUp -GameTeam -Template "2d-platformer"
        Sets up a game project with 2D platformer template.
    .EXAMPLE
        llmup -GameTeam -JamMode
        Quick jam setup with defaults.
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = ".",
        [switch]$GameTeam,
        [string]$Template = "",
        [string]$Engine = "",
        [switch]$JamMode,
        [switch]$SkipDependencyInstall,
        [switch]$SkipContextVerify,
        [switch]$SkipBridgeDryRun,
        [switch]$SmokeTestContext,
        [switch]$RequireSearchHit,
        [switch]$ContinueOnError,
        [switch]$ShowTiming,
        [switch]$Offline,
        [switch]$AsJson
    )
    
    $projectPath = Resolve-Path -LiteralPath $ProjectRoot
    
    # Check for existing game preset
    $gamePresetPath = Join-Path $projectPath ".llm-workflow\game-preset.json"
    $isGameProject = Test-Path -LiteralPath $gamePresetPath
    
    # Auto-detect game mode
    if ($isGameProject -and -not $GameTeam) {
        Write-Host "[gameteam] Detected game project, enabling game team mode" -ForegroundColor Cyan
        $GameTeam = $true
    }
    
    # Apply jam mode defaults
    if ($JamMode) {
        Write-Host "[gameteam] Jam Mode: enabling ContinueOnError and fast checks" -ForegroundColor Yellow
        $ContinueOnError = $true
    }
    
    # If GameTeam flag is set, ensure game structure exists
    if ($GameTeam) {
        if (-not $isGameProject) {
            Write-Host "[gameteam] Initializing game project structure..." -ForegroundColor Cyan
            New-LLMWorkflowGamePreset -ProjectRoot $projectPath -Template $Template -Engine $Engine -JamMode:$JamMode
        } else {
            Write-Host "[gameteam] Game project already initialized" -ForegroundColor Gray
        }
    }
    
    # Call base workflow up with appropriate parameters
    $invokeArgs = @{
        ProjectRoot = $ProjectRoot
    }
    
    if ($SkipDependencyInstall) { $invokeArgs["SkipDependencyInstall"] = $true }
    if ($SkipContextVerify -or $JamMode) { $invokeArgs["SkipContextVerify"] = $true }
    if ($SkipBridgeDryRun -or $JamMode) { $invokeArgs["SkipBridgeDryRun"] = $true }
    if ($SmokeTestContext) { $invokeArgs["SmokeTestContext"] = $true }
    if ($RequireSearchHit) { $invokeArgs["RequireSearchHit"] = $true }
    if ($ContinueOnError -or $JamMode) { $invokeArgs["ContinueOnError"] = $true }
    if ($ShowTiming) { $invokeArgs["ShowTiming"] = $true }
    if ($Offline) { $invokeArgs["Offline"] = $true }
    if ($AsJson) { $invokeArgs["AsJson"] = $true }
    
    # Call the base Invoke-LLMWorkflowUp
    Invoke-LLMWorkflowUp @invokeArgs
    
    # Game-specific post-setup
    if ($GameTeam) {
        Write-Host "[gameteam] Game setup complete" -ForegroundColor Green
        Write-Host "[gameteam] Templates available: GDD.md, TASKS.md, ASSET_MANIFEST.json" -ForegroundColor Gray
    }
}

# Export functions
Export-ModuleMember -Function New-LLMWorkflowGamePreset, Get-LLMWorkflowGameTemplates, Export-LLMWorkflowAssetManifest, Invoke-LLMWorkflowGameUp
