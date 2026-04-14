# LLM Workflow Game Team Functions
# PowerShell 5.1+ compatible
# ASCII-only for Unicode safety

Set-StrictMode -Version Latest

$GameTemplateRoot = Join-Path (Join-Path $PSScriptRoot 'templates') 'game'
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

function New-LLMWorkflowDefaultAssetCategories {
    [CmdletBinding()]
    param()

    return [ordered]@{
        art = [ordered]@{
            description = "Shared visual assets such as textures, models, UI, concept art, and reference images"
            folder = "assets/art"
            assetCount = 0
            assets = @()
        }
        spritesheets = [ordered]@{
            description = "Sprite sheets, atlases, Aseprite files, and frame-based 2D animation sources"
            folder = "assets/spritesheets"
            assetCount = 0
            assets = @()
        }
        tilemaps = [ordered]@{
            description = "Tilemaps, tilesets, autotile definitions, and level-layout source files"
            folder = "assets/tilemaps"
            assetCount = 0
            assets = @()
        }
        sfx = [ordered]@{
            description = "Sound effects and short-form gameplay audio"
            folder = "assets/sfx"
            assetCount = 0
            assets = @()
        }
        music = [ordered]@{
            description = "Music, ambiences, stems, and long-form audio tracks"
            folder = "assets/music"
            assetCount = 0
            assets = @()
        }
        plugins = [ordered]@{
            description = "Engine plugins, editor extensions, runtime modules, and integration scripts"
            folder = "assets/plugins"
            assetCount = 0
            assets = @()
        }
        rpgmaker = [ordered]@{
            description = "RPG Maker project assets such as plugins, character sheets, tilesets, and database-adjacent resources"
            folder = "assets/engines/rpgmaker"
            assetCount = 0
            assets = @()
        }
        unreal = [ordered]@{
            description = "Unreal Engine content including uasset, umap, uproject, imported meshes, and project-side content"
            folder = "assets/engines/unreal"
            assetCount = 0
            assets = @()
        }
        epic = [ordered]@{
            description = "Epic ecosystem assets such as Fab marketplace drops, Megascans, and Epic-distributed samples"
            folder = "assets/engines/epic"
            assetCount = 0
            assets = @()
        }
        shared = [ordered]@{
            description = "Cross-engine packs, archives, manifests, and assets shared across toolchains"
            folder = "assets/shared"
            assetCount = 0
            assets = @()
        }
    }
}

function New-LLMWorkflowDefaultAssetTemplates {
    [CmdletBinding()]
    param()

    return [ordered]@{
        art = [ordered]@{
            id = ""
            name = ""
            fileName = ""
            path = ""
            category = "art"
            assetKind = "sprite|texture|material|model|ui|concept"
            engineFamily = "cross-engine"
            format = "png|jpg|webp|psd|fbx|obj|blend"
            dimensions = ""
            fileSize = ""
            fileSizeBytes = 0
            tags = @()
            status = "todo|wip|review|done"
            priority = "p0|p1|p2"
            assignedTo = ""
            createdDate = ""
            modifiedDate = ""
            source = "original|fab|itchio|kenney|custom|unknown"
            sourceUrl = ""
            license = "original|CC0|CC-BY|CC-BY-SA|CC-BY-NC|proprietary|unknown"
            licenseUrl = ""
            author = ""
            notes = ""
        }
        spritesheets = [ordered]@{
            id = ""
            name = ""
            fileName = ""
            path = ""
            category = "spritesheets"
            assetKind = "spritesheet|atlas|aseprite"
            engineFamily = "cross-engine"
            format = "png|webp|ase|aseprite|json"
            frameSize = ""
            dimensions = ""
            fileSize = ""
            fileSizeBytes = 0
            tags = @()
            status = "todo|wip|review|done"
            source = "original|fab|itchio|custom|unknown"
            license = "original|CC0|CC-BY|CC-BY-SA|proprietary|unknown"
            notes = ""
        }
        tilemaps = [ordered]@{
            id = ""
            name = ""
            fileName = ""
            path = ""
            category = "tilemaps"
            assetKind = "tilemap|tileset|autotile"
            engineFamily = "cross-engine"
            format = "tmx|tsx|json|png"
            tileSize = ""
            fileSize = ""
            fileSizeBytes = 0
            tags = @()
            status = "todo|wip|review|done"
            source = "original|fab|itchio|custom|unknown"
            license = "original|CC0|CC-BY|CC-BY-SA|proprietary|unknown"
            notes = ""
        }
        sfx = [ordered]@{
            id = ""
            name = ""
            fileName = ""
            path = ""
            category = "sfx"
            assetKind = "sfx|voice|foley|ui"
            engineFamily = "cross-engine"
            format = "wav|mp3|ogg|flac"
            duration = ""
            fileSize = ""
            fileSizeBytes = 0
            tags = @()
            status = "todo|wip|review|done"
            source = "original|freesound|custom|unknown"
            license = "original|CC0|CC-BY|proprietary|unknown"
            notes = ""
        }
        music = [ordered]@{
            id = ""
            name = ""
            fileName = ""
            path = ""
            category = "music"
            assetKind = "music|stem|ambient"
            engineFamily = "cross-engine"
            format = "wav|mp3|ogg|flac"
            duration = ""
            loopable = $false
            fileSize = ""
            fileSizeBytes = 0
            tags = @()
            status = "todo|wip|review|done"
            source = "original|composer|custom|unknown"
            license = "original|CC0|CC-BY|proprietary|unknown"
            notes = ""
        }
        plugins = [ordered]@{
            id = ""
            name = ""
            fileName = ""
            path = ""
            category = "plugins"
            assetKind = "plugin|editor-plugin|runtime-plugin"
            engineFamily = "plugin"
            targetEngine = "RPGMaker|Godot|Unreal|Unity|Generic"
            format = "js|uplugin|gdextension|dll|py|cs"
            fileSize = ""
            fileSizeBytes = 0
            tags = @()
            status = "todo|wip|review|done"
            source = "original|marketplace|custom|unknown"
            license = "original|MIT|Apache-2.0|GPL|proprietary|unknown"
            notes = ""
        }
        engineAsset = [ordered]@{
            id = ""
            name = ""
            fileName = ""
            path = ""
            category = "rpgmaker|unreal|epic|shared"
            assetKind = "plugin|project|map|texture|mesh|bundle|sample"
            engineFamily = "rpgmaker|unreal|epic|cross-engine"
            format = "uasset|umap|uproject|js|png|fbx|zip"
            fileSize = ""
            fileSizeBytes = 0
            tags = @()
            status = "todo|wip|review|done"
            source = "original|fab|epic|marketplace|custom|unknown"
            license = "original|CC0|CC-BY|CC-BY-SA|proprietary|unknown"
            notes = ""
        }
        shared = [ordered]@{
            id = ""
            name = ""
            fileName = ""
            path = ""
            category = "shared"
            assetKind = "archive|manifest|reference|bundle"
            engineFamily = "cross-engine"
            format = "zip|7z|rar|json|csv|txt"
            fileSize = ""
            fileSizeBytes = 0
            tags = @()
            status = "todo|wip|review|done"
            source = "original|fab|marketplace|custom|unknown"
            license = "original|CC0|CC-BY|CC-BY-SA|proprietary|unknown"
            notes = ""
        }
    }
}

function New-LLMWorkflowDefaultLicenseSummary {
    [CmdletBinding()]
    param()

    return [ordered]@{
        original = 0
        cc0 = 0
        ccBy = 0
        ccBySa = 0
        proprietary = 0
        unknown = 0
    }
}

function New-LLMWorkflowDefaultAssetManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectName
    )

    $today = Get-Date -Format "yyyy-MM-dd"
    return [ordered]@{
        project = $ProjectName
        version = "1.1.0"
        created = $today
        lastUpdated = $today
        assetCount = 0
        totalSize = "0 B"
        categories = New-LLMWorkflowDefaultAssetCategories
        licenseSummary = New-LLMWorkflowDefaultLicenseSummary
        templates = New-LLMWorkflowDefaultAssetTemplates
        exampleAssets = @(
            [ordered]@{
                id = "spritesheets-001"
                name = "Player Walk Atlas"
                fileName = "player_walk.png"
                path = "assets/spritesheets/player_walk.png"
                category = "spritesheets"
                assetKind = "spritesheet"
                engineFamily = "cross-engine"
                format = "png"
                dimensions = "512x256"
                fileSize = "48 KB"
                fileSizeBytes = 49152
                tags = @("character", "player", "walk-cycle")
                status = "wip"
                priority = "p0"
                assignedTo = "artist1"
                createdDate = $today
                modifiedDate = $today
                source = "original"
                sourceUrl = ""
                license = "original"
                licenseUrl = ""
                author = "Team"
                notes = "8-direction sprite sheet for shared engine import."
            },
            [ordered]@{
                id = "rpgmaker-001"
                name = "Battle Core Plugin"
                fileName = "BattleCore.js"
                path = "assets/engines/rpgmaker/js/plugins/BattleCore.js"
                category = "rpgmaker"
                assetKind = "plugin"
                engineFamily = "rpgmaker"
                format = "js"
                fileSize = "18 KB"
                fileSizeBytes = 18432
                tags = @("rpgmaker", "plugin", "battle")
                status = "review"
                priority = "p1"
                assignedTo = ""
                createdDate = $today
                modifiedDate = $today
                source = "custom"
                sourceUrl = ""
                license = "proprietary"
                licenseUrl = ""
                author = ""
                notes = "Tracks imported RPG Maker plugins separately from shared code assets."
            },
            [ordered]@{
                id = "unreal-001"
                name = "Hero Material Instance"
                fileName = "MI_Hero.uasset"
                path = "assets/engines/unreal/Characters/Hero/MI_Hero.uasset"
                category = "unreal"
                assetKind = "uasset"
                engineFamily = "unreal"
                format = "uasset"
                fileSize = "256 KB"
                fileSizeBytes = 262144
                tags = @("unreal", "material", "character")
                status = "done"
                priority = "p1"
                assignedTo = ""
                createdDate = $today
                modifiedDate = $today
                source = "fab"
                sourceUrl = ""
                license = "proprietary"
                licenseUrl = ""
                author = ""
                notes = "Example Unreal content inventory entry."
            }
        )
    }
}

function Get-LLMWorkflowRelativeAssetPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullPath,

        [Parameter(Mandatory = $true)]
        [string]$ProjectPath
    )

    $root = [System.IO.Path]::GetFullPath($ProjectPath)
    $path = [System.IO.Path]::GetFullPath($FullPath)
    if ($path.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $path.Substring($root.Length).TrimStart("\", "/")
        return $relative.Replace("\", "/")
    }

    return $path.Replace("\", "/")
}

function Format-LLMWorkflowAssetFileSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [long]$Bytes
    )

    if ($Bytes -lt 1KB) { return "$Bytes B" }
    if ($Bytes -lt 1MB) { return ("{0:N0} KB" -f ($Bytes / 1KB)) }
    if ($Bytes -lt 1GB) { return ("{0:N1} MB" -f ($Bytes / 1MB)) }
    return ("{0:N2} GB" -f ($Bytes / 1GB))
}

function Get-LLMWorkflowExistingAssetLookup {
    [CmdletBinding()]
    param(
        $Manifest
    )

    $lookup = @{}
    if ($null -eq $Manifest -or $null -eq $Manifest.categories) {
        return $lookup
    }

    $categoryNames = if ($Manifest.categories -is [System.Collections.IDictionary]) {
        @($Manifest.categories.Keys)
    } else {
        @($Manifest.categories.PSObject.Properties.Name)
    }

    foreach ($categoryName in $categoryNames) {
        $categoryValue = if ($Manifest.categories -is [System.Collections.IDictionary]) {
            $Manifest.categories[$categoryName]
        } else {
            $Manifest.categories.PSObject.Properties[$categoryName].Value
        }

        foreach ($asset in @($categoryValue.assets)) {
            if ($null -eq $asset -or [string]::IsNullOrWhiteSpace($asset.path)) {
                continue
            }

            $lookup[$asset.path.ToLowerInvariant()] = $asset
        }
    }

    return $lookup
}

function Merge-LLMWorkflowAssetManifest {
    [CmdletBinding()]
    param(
        $ExistingManifest,

        [Parameter(Mandatory = $true)]
        [string]$ProjectName
    )

    $manifest = New-LLMWorkflowDefaultAssetManifest -ProjectName $ProjectName
    if ($null -eq $ExistingManifest) {
        return $manifest
    }

    foreach ($propertyName in @("project", "version", "created", "lastUpdated")) {
        $property = $ExistingManifest.PSObject.Properties[$propertyName]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            $manifest[$propertyName] = $property.Value
        }
    }

    if ($null -ne $ExistingManifest.PSObject.Properties["templates"] -and $null -ne $ExistingManifest.templates) {
        foreach ($templateProperty in $ExistingManifest.templates.PSObject.Properties) {
            $manifest.templates[$templateProperty.Name] = $templateProperty.Value
        }
    }

    if ($null -ne $ExistingManifest.PSObject.Properties["exampleAssets"] -and $null -ne $ExistingManifest.exampleAssets) {
        $manifest.exampleAssets = @($ExistingManifest.exampleAssets)
    }

    if ($null -ne $ExistingManifest.PSObject.Properties["categories"] -and $null -ne $ExistingManifest.categories) {
        foreach ($categoryProperty in $ExistingManifest.categories.PSObject.Properties) {
            if (-not $manifest.categories.Contains($categoryProperty.Name)) {
                $manifest.categories[$categoryProperty.Name] = [ordered]@{
                    description = "Imported legacy category"
                    folder = "assets/$($categoryProperty.Name)"
                    assetCount = 0
                    assets = @()
                }
            }

            if ($null -ne $categoryProperty.Value.PSObject.Properties["description"] -and
                -not [string]::IsNullOrWhiteSpace([string]$categoryProperty.Value.description)) {
                $manifest.categories[$categoryProperty.Name].description = $categoryProperty.Value.description
            }

            if ($null -ne $categoryProperty.Value.PSObject.Properties["folder"] -and
                -not [string]::IsNullOrWhiteSpace([string]$categoryProperty.Value.folder)) {
                $manifest.categories[$categoryProperty.Name].folder = $categoryProperty.Value.folder
            }

            if ($null -ne $categoryProperty.Value.PSObject.Properties["assets"] -and $null -ne $categoryProperty.Value.assets) {
                $manifest.categories[$categoryProperty.Name].assets = @($categoryProperty.Value.assets)
                $manifest.categories[$categoryProperty.Name].assetCount = @($categoryProperty.Value.assets).Count
            }
        }
    }

    if ($null -ne $ExistingManifest.PSObject.Properties["licenseSummary"] -and $null -ne $ExistingManifest.licenseSummary) {
        foreach ($licenseProperty in $ExistingManifest.licenseSummary.PSObject.Properties) {
            $manifest.licenseSummary[$licenseProperty.Name] = $licenseProperty.Value
        }
    }

    return $manifest
}

function Get-LLMWorkflowDefaultAssetSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category
    )

    switch ($Category) {
        "epic" { return "fab" }
        "unreal" { return "unreal" }
        "rpgmaker" { return "rpgmaker" }
        "plugins" { return "custom" }
        default { return "unknown" }
    }
}

function Get-LLMWorkflowAssetCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$Extension
    )

    $path = $RelativePath.ToLowerInvariant().Replace('\', '/')
    $isImage = $Extension -in @(".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".tga", ".psd")
    $isAudio = $Extension -in @(".wav", ".mp3", ".ogg", ".flac", ".aac", ".m4a")
    $isModel = $Extension -in @(".fbx", ".obj", ".gltf", ".glb", ".blend", ".dae")
    $isPlugin = $Extension -in @(".uplugin", ".gdextension", ".gde", ".dll", ".js", ".py", ".cs")

    if ($path -match "^assets/music/" -or $path -match "/(bgm|music|songs?)/") { return "music" }
    if ($path -match "^assets/sfx/" -or $path -match "/(sfx|se|sounds?)/") { return "sfx" }
    if ($path -match "/(engines/)?epic/" -or $path -match "/fab/" -or $path -match "/megascans/") { return "epic" }
    if ($path -match "/(engines/)?unreal/" -or $Extension -in @(".uasset", ".umap", ".uproject", ".ubulk", ".uexp")) { return "unreal" }
    if ($path -match "/(engines/)?rpgmaker/" -or $path -match "/rmmz/" -or $Extension -in @(".rmmzproject", ".rvdata", ".rvdata2", ".rxdata")) { return "rpgmaker" }
    if ($path -match "/plugins?/" -or $Extension -in @(".uplugin", ".gdextension", ".gde")) { return "plugins" }
    if ($path -match "/shared/") { return "shared" }
    if ($path -match "/spritesheets?/" -or $path -match "(spritesheet|sprite_sheet|sprite-atlas|spriteatlas|atlas)" -or $Extension -in @(".ase", ".aseprite")) { return "spritesheets" }
    if ($path -match "/tilemaps?/" -or $path -match "(tilemap|tileset|autotile)" -or $Extension -in @(".tmx", ".tsx")) { return "tilemaps" }
    if ($path -match "^assets/art/") { return "art" }

    if ($isImage -or $isModel) { return "art" }
    if ($isAudio) { return "sfx" }
    if ($isPlugin) { return "plugins" }
    if ($Extension -in @(".zip", ".7z", ".rar", ".pak", ".csv", ".json")) { return "shared" }

    return "shared"
}

function Get-LLMWorkflowAssetKind {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$Extension
    )

    $path = $RelativePath.ToLowerInvariant().Replace('\', '/')

    switch ($Category) {
        "spritesheets" {
            if ($Extension -in @(".ase", ".aseprite")) { return "aseprite" }
            if ($path -match "(atlas|spriteatlas)") { return "atlas" }
            return "spritesheet"
        }
        "tilemaps" {
            if ($Extension -eq ".tsx" -or $path -match "tileset") { return "tileset" }
            if ($path -match "autotile") { return "autotile" }
            return "tilemap"
        }
        "sfx" { return "sfx" }
        "music" { return "music" }
        "plugins" {
            if ($Extension -eq ".uplugin") { return "unreal-plugin" }
            if ($Extension -eq ".js") { return "runtime-plugin" }
            if ($path -match "/editor/") { return "editor-plugin" }
            return "plugin"
        }
        "rpgmaker" {
            if ($Extension -eq ".js" -or $path -match "/js/plugins/") { return "plugin" }
            if ($path -match "(tileset|tilemap)") { return "tileset" }
            if ($path -match "(characters|battlers|faces|parallaxes)") { return "sprite" }
            if ($Extension -in @(".ogg", ".m4a", ".wav")) { return "audio" }
            return "rpgmaker-asset"
        }
        "unreal" {
            if ($Extension -eq ".uproject") { return "project" }
            if ($Extension -eq ".uplugin") { return "plugin" }
            if ($Extension -eq ".umap") { return "map" }
            if ($Extension -eq ".uasset") { return "uasset" }
            if ($Extension -in @(".fbx", ".obj")) { return "mesh" }
            return "unreal-asset"
        }
        "epic" {
            if ($path -match "megascans") { return "megascans" }
            if ($Extension -eq ".uplugin") { return "plugin" }
            if ($Extension -in @(".zip", ".7z", ".rar")) { return "marketplace-pack" }
            return "marketplace-asset"
        }
        "art" {
            if ($Extension -in @(".fbx", ".obj", ".gltf", ".glb", ".blend")) { return "model" }
            if ($path -match "(ui|hud)") { return "ui" }
            if ($path -match "sprite") { return "sprite" }
            return "texture"
        }
        "shared" {
            if ($Extension -in @(".zip", ".7z", ".rar", ".pak")) { return "archive" }
            if ($Extension -in @(".json", ".csv")) { return "manifest" }
            return "bundle"
        }
        default { return "asset" }
    }
}

function Get-LLMWorkflowAssetEngineFamily {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category
    )

    switch ($Category) {
        "rpgmaker" { return "rpgmaker" }
        "unreal" { return "unreal" }
        "epic" { return "epic" }
        "plugins" { return "plugin" }
        default { return "cross-engine" }
    }
}

function Get-LLMWorkflowAssetTags {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$AssetKind,

        $ExistingTags
    )

    $tags = New-Object System.Collections.Generic.List[string]
    foreach ($tag in @($ExistingTags)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$tag) -and -not $tags.Contains([string]$tag)) {
            $tags.Add([string]$tag)
        }
    }

    foreach ($tag in @($Category, $AssetKind)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$tag) -and -not $tags.Contains([string]$tag)) {
            $tags.Add([string]$tag)
        }
    }

    return @($tags)
}

function Get-LLMWorkflowLicenseSummaryKey {
    [CmdletBinding()]
    param(
        [string]$License
    )

    $normalized = ([string]$License).Trim().ToLowerInvariant()
    switch -Regex ($normalized) {
        "^original$" { return "original" }
        "^cc0$" { return "cc0" }
        "^cc[- ]?by([- ]?4\.0)?$" { return "ccBy" }
        "^cc[- ]?by[- ]?sa([- ]?4\.0)?$" { return "ccBySa" }
        "^proprietary$" { return "proprietary" }
        default { return "unknown" }
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
    [OutputType([pscustomobject])]
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
    
    # Create folder structure from preset data so templates and implementation stay aligned
    $folders = @()
    if ($preset.folderStructure) {
        foreach ($folder in $preset.folderStructure) {
            $normalizedFolder = ([string]$folder).TrimEnd("/", "\")
            if ([string]::IsNullOrWhiteSpace($normalizedFolder)) {
                continue
            }

            if ($SkipAssetFolders -and $normalizedFolder -like "assets/*" -and $normalizedFolder -ne "assets") {
                continue
            }

            if ($folders -notcontains $normalizedFolder) {
                $folders += $normalizedFolder
            }
        }
    }

    if ($folders.Count -eq 0) {
        $folders = @("docs", "assets", ".llm-workflow")
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
        @{ Source = "GDD.md"; Dest = (Join-Path 'docs' 'GDD.md') },
        @{ Source = "TASKS.md"; Dest = (Join-Path 'docs' 'TASKS.md') },
        @{ Source = "ASSET_MANIFEST.json"; Dest = (Join-Path 'assets' 'ASSET_MANIFEST.json') }
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
    $configPath = Join-Path (Join-Path $projectPath '.llm-workflow') 'game-preset.json'
    $config = @{
        projectName = $ProjectName
        created = (Get-Date -Format "yyyy-MM-dd")
        template = $Template
        engine = $Engine
        jamMode = $JamMode.IsPresent
        version = "1.0.0"
    }
    $config.provenance = [ordered]@{
        createdBy = 'LLMWorkflow.GameFunctions'
        createdAt = [DateTime]::UtcNow.ToString('o')
    }
    
    if (Test-Path -LiteralPath $configPath) {
        Write-Host "[gameteam] Exists: .llm-workflow/game-preset.json" -ForegroundColor DarkGray
    } else {
        $config | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $configPath -Encoding UTF8
        Write-Host "[gameteam] Created: .llm-workflow/game-preset.json" -ForegroundColor Gray
        $createdFiles += Join-Path '.llm-workflow' 'game-preset.json'
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
        Provenance = $config.provenance
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
    [OutputType([pscustomobject[]])]
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
            Provenance = [ordered]@{
                generatedBy = 'LLMWorkflow.GameFunctions'
                generatedAt = [DateTime]::UtcNow.ToString('o')
            }
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
    [OutputType([pscustomobject])]
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = ".",
        [switch]$ScanFolders,
        [string]$OutputPath = "",
        [ValidateSet("json", "csv")]
        [string]$Format = "json",
        [ValidateSet("inventory", "deep")]
        [string]$ExtractionDepth = "inventory"
    )
    
    $projectPath = Resolve-Path -LiteralPath $ProjectRoot
    $manifestPath = Join-Path (Join-Path $projectPath 'assets') 'ASSET_MANIFEST.json'
    
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
        $manifest = New-LLMWorkflowDefaultAssetManifest -ProjectName (Split-Path -Leaf $projectPath)
    } else {
        $manifest = Merge-LLMWorkflowAssetManifest -ExistingManifest $manifest -ProjectName (Split-Path -Leaf $projectPath)
    }
    $manifest.lastUpdated = (Get-Date -Format "yyyy-MM-dd")
    $manifest.extractionDepth = $ExtractionDepth
    $manifest.provenance = [ordered]@{
        generatedBy = 'LLMWorkflow.GameFunctions'
        generatedAt = [DateTime]::UtcNow.ToString('o')
        projectRoot = $ProjectRoot
    }

    # Scan folders if requested
    if ($ScanFolders) {
        Write-Host "[gameteam] Scanning asset folders..." -ForegroundColor Cyan

        $totalCount = 0
        $totalSize = 0
        $licenseCounts = New-LLMWorkflowDefaultLicenseSummary
        $existingAssets = Get-LLMWorkflowExistingAssetLookup -Manifest $manifest
        $categorySequence = @($manifest.categories.Keys)
        $categoryCounters = @{}

        foreach ($categoryName in $categorySequence) {
            $manifest.categories[$categoryName].assets = @()
            $manifest.categories[$categoryName].assetCount = 0
            $categoryCounters[$categoryName] = 0
        }

        $assetsRoot = Join-Path $projectPath "assets"
        if (Test-Path -LiteralPath $assetsRoot) {
            $files = Get-ChildItem -LiteralPath $assetsRoot -File -Recurse |
                Where-Object { $_.Name -ne "ASSET_MANIFEST.json" }

            foreach ($file in $files) {
                $relativePath = Get-LLMWorkflowRelativeAssetPath -FullPath $file.FullName -ProjectPath $projectPath
                $extension = $file.Extension.ToLowerInvariant()
                $category = Get-LLMWorkflowAssetCategory -RelativePath $relativePath -Extension $extension
                $assetKind = Get-LLMWorkflowAssetKind -Category $category -RelativePath $relativePath -Extension $extension
                $engineFamily = Get-LLMWorkflowAssetEngineFamily -Category $category
                $existingAsset = $existingAssets[$relativePath.ToLowerInvariant()]

                if (-not $manifest.categories.Contains($category)) {
                    $manifest.categories[$category] = [ordered]@{
                        description = "Discovered during asset scan"
                        folder = "assets/$category"
                        assetCount = 0
                        assets = @()
                    }
                    $categoryCounters[$category] = 0
                    $categorySequence += $category
                }

                $categoryCounters[$category]++
                $assetId = if ($null -ne $existingAsset -and -not [string]::IsNullOrWhiteSpace([string]$existingAsset.id)) {
                    [string]$existingAsset.id
                } else {
                    "{0}-{1:D3}" -f $category, $categoryCounters[$category]
                }

                $license = if ($null -ne $existingAsset -and -not [string]::IsNullOrWhiteSpace([string]$existingAsset.license)) {
                    [string]$existingAsset.license
                } else {
                    "unknown"
                }

                $asset = [ordered]@{
                    id = $assetId
                    name = if ($null -ne $existingAsset -and -not [string]::IsNullOrWhiteSpace([string]$existingAsset.name)) { [string]$existingAsset.name } else { $file.BaseName }
                    fileName = $file.Name
                    path = $relativePath
                    category = $category
                    assetKind = $assetKind
                    engineFamily = $engineFamily
                    format = $file.Extension.TrimStart(".").ToLowerInvariant()
                    dimensions = if ($null -ne $existingAsset -and $null -ne $existingAsset.PSObject.Properties["dimensions"]) { [string]$existingAsset.dimensions } else { "" }
                    duration = if ($null -ne $existingAsset -and $null -ne $existingAsset.PSObject.Properties["duration"]) { [string]$existingAsset.duration } else { "" }
                    fileSize = Format-LLMWorkflowAssetFileSize -Bytes $file.Length
                    fileSizeBytes = [long]$file.Length
                    tags = Get-LLMWorkflowAssetTags -Category $category -AssetKind $assetKind -ExistingTags $(if ($null -ne $existingAsset) { $existingAsset.tags } else { @() })
                    status = if ($null -ne $existingAsset -and -not [string]::IsNullOrWhiteSpace([string]$existingAsset.status)) { [string]$existingAsset.status } else { "done" }
                    priority = if ($null -ne $existingAsset -and -not [string]::IsNullOrWhiteSpace([string]$existingAsset.priority)) { [string]$existingAsset.priority } else { "p2" }
                    assignedTo = if ($null -ne $existingAsset -and $null -ne $existingAsset.PSObject.Properties["assignedTo"]) { [string]$existingAsset.assignedTo } else { "" }
                    createdDate = if ($null -ne $existingAsset -and -not [string]::IsNullOrWhiteSpace([string]$existingAsset.createdDate)) { [string]$existingAsset.createdDate } else { $file.CreationTime.ToString("yyyy-MM-dd") }
                    modifiedDate = $file.LastWriteTime.ToString("yyyy-MM-dd")
                    source = if ($null -ne $existingAsset -and -not [string]::IsNullOrWhiteSpace([string]$existingAsset.source)) { [string]$existingAsset.source } else { Get-LLMWorkflowDefaultAssetSource -Category $category }
                    sourceUrl = if ($null -ne $existingAsset -and $null -ne $existingAsset.PSObject.Properties["sourceUrl"]) { [string]$existingAsset.sourceUrl } else { "" }
                    license = $license
                    licenseUrl = if ($null -ne $existingAsset -and $null -ne $existingAsset.PSObject.Properties["licenseUrl"]) { [string]$existingAsset.licenseUrl } else { "" }
                    author = if ($null -ne $existingAsset -and $null -ne $existingAsset.PSObject.Properties["author"]) { [string]$existingAsset.author } else { "" }
                    notes = if ($null -ne $existingAsset -and $null -ne $existingAsset.PSObject.Properties["notes"]) { [string]$existingAsset.notes } else { "" }
                }

                $manifest.categories[$category].assets += $asset
                $manifest.categories[$category].assetCount = @($manifest.categories[$category].assets).Count
                $totalCount++
                $totalSize += $file.Length

                $licenseKey = Get-LLMWorkflowLicenseSummaryKey -License $license
                $licenseCounts[$licenseKey]++
            }
        }

        foreach ($categoryName in $categorySequence) {
            $manifest.categories[$categoryName].assetCount = @($manifest.categories[$categoryName].assets).Count
        }

        $manifest.assetCount = $totalCount
        $manifest.totalSize = Format-LLMWorkflowAssetFileSize -Bytes $totalSize
        $manifest.licenseSummary = $licenseCounts

        Write-Host "[gameteam] Found $totalCount assets" -ForegroundColor Green
    }

    # Normalize license field across all assets
    foreach ($cat in @($manifest.categories.Keys)) {
        foreach ($asset in $manifest.categories[$cat].assets) {
            if ($null -eq $asset -or [string]::IsNullOrWhiteSpace([string]$asset.license)) {
                if ($asset -is [System.Collections.IDictionary]) { $asset['license'] = 'unknown' }
                else { $asset | Add-Member -NotePropertyName 'license' -NotePropertyValue 'unknown' -Force }
            }
        }
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
        $categoryNames = if ($manifest.categories -is [System.Collections.IDictionary]) {
            @($manifest.categories.Keys)
        } else {
            @($manifest.categories.PSObject.Properties.Name)
        }

        foreach ($category in $categoryNames) {
            $categoryData = if ($manifest.categories -is [System.Collections.IDictionary]) {
                $manifest.categories[$category]
            } else {
                $manifest.categories.PSObject.Properties[$category].Value
            }

            foreach ($asset in $categoryData.assets) {
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
        ExtractionDepth = $manifest.extractionDepth
        Provenance = $manifest.provenance
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
    [OutputType([void])]
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
    $gamePresetPath = Join-Path (Join-Path $projectPath '.llm-workflow') 'game-preset.json'
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
if ($null -ne $MyInvocation.MyCommand.Module) {
    Export-ModuleMember -Function New-LLMWorkflowGamePreset, Get-LLMWorkflowGameTemplates, Export-LLMWorkflowAssetManifest, Invoke-LLMWorkflowGameUp
}
