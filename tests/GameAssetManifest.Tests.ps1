#requires -Version 5.1

Describe "Game Asset Manifest" {
    BeforeAll {
        $script:GameFunctionsPath = Join-Path (Join-Path $PSScriptRoot "..") "module\LLMWorkflow\LLMWorkflow.GameFunctions.ps1"
        . $script:GameFunctionsPath
    }

    It "creates engine-aware game folders" {
        $projectRoot = Join-Path $TestDrive "GamePreset"
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null

        $result = New-LLMWorkflowGamePreset -ProjectRoot $projectRoot -ProjectName "AssetScopeTest"

        $result.Success | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $projectRoot "assets\spritesheets")) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $projectRoot "assets\tilemaps")) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $projectRoot "assets\plugins")) | Should -Be $true
    }

    It "classifies spritesheets, plugins, RPG Maker, Unreal, Epic, tilemaps, and music assets" {
        $projectRoot = Join-Path $TestDrive "AssetClassify"
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null

        # Create sample assets
        $assets = @(
            "assets\spritesheets\hero.png",
            "assets\tilemaps\dungeon.tmx",
            "assets\plugins\MyPlugin.js",
            "assets\music\battle.ogg"
        )
        foreach ($asset in $assets) {
            $path = Join-Path $projectRoot $asset
            $dir = Split-Path -Parent $path
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            "test" | Set-Content -Path $path -NoNewline
        }

        $result = Export-LLMWorkflowAssetManifest -ProjectRoot $projectRoot -ScanFolders

        $result.AssetCount | Should -BeGreaterThan 0
        $manifest = Get-Content -LiteralPath $result.ManifestPath -Raw | ConvertFrom-Json
        $manifest.categories.spritesheets.assetCount | Should -BeGreaterThan 0
        $manifest.categories.plugins.assetCount | Should -BeGreaterThan 0
        $manifest.categories.music.assetCount | Should -BeGreaterThan 0
        $manifest.categories.tilemaps.assetCount | Should -BeGreaterThan 0
    }

    It "preserves existing asset metadata on rescan" {
        $projectRoot = Join-Path $TestDrive "AssetRescan"
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        $presetPath = Join-Path $projectRoot "assets\ASSET_MANIFEST.json"
        $dir = Split-Path -Parent $presetPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        $legacyAsset = [ordered]@{
            id = "spritesheets-legacy"
            name = "legacy"
            fileName = "legacy.png"
            path = "assets/spritesheets/legacy.png"
            category = "spritesheets"
            assetKind = "spritesheet"
            engineFamily = "cross-engine"
            format = "png"
            dimensions = ""
            duration = ""
            fileSize = "3 B"
            fileSizeBytes = 3
            tags = @("legacy")
            status = "done"
            priority = "p2"
            assignedTo = ""
            createdDate = "2026-04-14"
            modifiedDate = "2026-04-14"
            source = "custom"
            sourceUrl = ""
            license = "CC0"
            licenseUrl = ""
            author = ""
            notes = ""
        }
        $manifest = New-LLMWorkflowDefaultAssetManifest -ProjectName "AssetRescan"
        $manifest.categories.spritesheets.assets = @($legacyAsset)
        $manifest.categories.spritesheets.assetCount = 1
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $presetPath -Encoding UTF8

        $legacyPath = Join-Path $projectRoot "assets\spritesheets\legacy.png"
        $assetPath = Join-Path $projectRoot "assets\spritesheets\new_asset.png"
        New-Item -ItemType Directory -Path (Split-Path -Parent $assetPath) -Force | Out-Null
        "old" | Set-Content -Path $legacyPath -NoNewline
        "new" | Set-Content -Path $assetPath -NoNewline

        $result = Export-LLMWorkflowAssetManifest -ProjectRoot $projectRoot -ScanFolders

        $result.AssetCount | Should -BeGreaterThan 0
        $updatedManifest = Get-Content -LiteralPath $result.ManifestPath -Raw | ConvertFrom-Json
        $allAssets = $updatedManifest.categories.spritesheets.assets
        $legacy = $allAssets | Where-Object { $_.fileName -eq "legacy.png" }
        $legacy | Should -Not -BeNullOrEmpty
        $legacy.license | Should -Be "CC0"
    }
}
