#requires -Version 5.1

. (Join-Path (Join-Path $PSScriptRoot "..") "module\LLMWorkflow\LLMWorkflow.GameFunctions.ps1")

Describe "Game Asset Manifest" {
    It "creates engine-aware game folders" {
        $projectRoot = Join-Path $TestDrive "GamePreset"
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null

        $result = New-LLMWorkflowGamePreset -ProjectRoot $projectRoot -ProjectName "AssetScopeTest"

        $result.Success | Should Be $true
        (Test-Path -LiteralPath (Join-Path $projectRoot "assets\spritesheets")) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $projectRoot "assets\tilemaps")) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $projectRoot "assets\plugins")) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $projectRoot "assets\engines\rpgmaker\js\plugins")) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $projectRoot "assets\engines\unreal")) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $projectRoot "assets\engines\epic")) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $projectRoot "assets\shared")) | Should Be $true
    }

    It "classifies spritesheets, plugins, RPG Maker, Unreal, Epic, tilemaps, and music assets" {
        $projectRoot = Join-Path $TestDrive "AssetScan"
        $folders = @(
            "assets\spritesheets",
            "assets\tilemaps",
            "assets\plugins",
            "assets\engines\rpgmaker\js\plugins",
            "assets\engines\unreal\Maps",
            "assets\engines\epic",
            "assets\music"
        )

        foreach ($folder in $folders) {
            New-Item -ItemType Directory -Path (Join-Path $projectRoot $folder) -Force | Out-Null
        }

        "png" | Set-Content -LiteralPath (Join-Path $projectRoot "assets\spritesheets\player_walk.png")
        "tmx" | Set-Content -LiteralPath (Join-Path $projectRoot "assets\tilemaps\overworld.tmx")
        "plugin" | Set-Content -LiteralPath (Join-Path $projectRoot "assets\plugins\global_tools.gdextension")
        "rpgmaker" | Set-Content -LiteralPath (Join-Path $projectRoot "assets\engines\rpgmaker\js\plugins\BattleCore.js")
        "unreal" | Set-Content -LiteralPath (Join-Path $projectRoot "assets\engines\unreal\Maps\TestMap.umap")
        "epic" | Set-Content -LiteralPath (Join-Path $projectRoot "assets\engines\epic\FabDrop.zip")
        "music" | Set-Content -LiteralPath (Join-Path $projectRoot "assets\music\theme.ogg")

        Export-LLMWorkflowAssetManifest -ProjectRoot $projectRoot -ScanFolders | Out-Null
        $manifestPath = Join-Path $projectRoot "assets\ASSET_MANIFEST.json"
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

        $manifest.assetCount | Should Be 7
        $manifest.categories.spritesheets.assetCount | Should Be 1
        $manifest.categories.tilemaps.assetCount | Should Be 1
        $manifest.categories.plugins.assetCount | Should Be 1
        $manifest.categories.rpgmaker.assetCount | Should Be 1
        $manifest.categories.unreal.assetCount | Should Be 1
        $manifest.categories.epic.assetCount | Should Be 1
        $manifest.categories.music.assetCount | Should Be 1
        $manifest.categories.rpgmaker.assets[0].assetKind | Should Be "plugin"
        $manifest.categories.unreal.assets[0].engineFamily | Should Be "unreal"
        $manifest.categories.epic.assets[0].source | Should Be "fab"
        $manifest.licenseSummary.unknown | Should Be 7
    }

    It "preserves existing asset metadata on rescan" {
        $projectRoot = Join-Path $TestDrive "Rescan"
        $artFolder = Join-Path $projectRoot "assets\art"
        New-Item -ItemType Directory -Path $artFolder -Force | Out-Null
        "png" | Set-Content -LiteralPath (Join-Path $artFolder "portrait.png")

        $manifest = [ordered]@{
            project = "Rescan"
            version = "1.0.0"
            created = "2026-01-01"
            lastUpdated = "2026-01-01"
            assetCount = 1
            totalSize = "1 KB"
            categories = [ordered]@{
                art = [ordered]@{
                    description = "Visual assets"
                    folder = "assets/art"
                    assetCount = 1
                    assets = @(
                        [ordered]@{
                            id = "art-001"
                            name = "Hero Portrait"
                            fileName = "portrait.png"
                            path = "assets/art/portrait.png"
                            category = "art"
                            assetKind = "texture"
                            engineFamily = "cross-engine"
                            format = "png"
                            fileSize = "1 KB"
                            fileSizeBytes = 1024
                            tags = @("character", "portrait")
                            status = "review"
                            priority = "p1"
                            assignedTo = "artist1"
                            createdDate = "2026-01-01"
                            modifiedDate = "2026-01-01"
                            source = "original"
                            sourceUrl = ""
                            license = "CC0"
                            licenseUrl = ""
                            author = "Artist"
                            notes = "Keep metadata"
                        }
                    )
                }
            }
            licenseSummary = [ordered]@{
                original = 0
                cc0 = 1
                ccBy = 0
                ccBySa = 0
                proprietary = 0
                unknown = 0
            }
        }

        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $projectRoot "assets\ASSET_MANIFEST.json") -Encoding UTF8

        Export-LLMWorkflowAssetManifest -ProjectRoot $projectRoot -ScanFolders | Out-Null
        $rescanned = Get-Content -LiteralPath (Join-Path $projectRoot "assets\ASSET_MANIFEST.json") -Raw | ConvertFrom-Json
        $asset = $rescanned.categories.art.assets[0]

        $asset.name | Should Be "Hero Portrait"
        $asset.assignedTo | Should Be "artist1"
        $asset.license | Should Be "CC0"
        $asset.notes | Should Be "Keep metadata"
        $rescanned.licenseSummary.cc0 | Should Be 1
    }
}


