#requires -Version 5.1

Describe "RPG Maker Asset Catalog Parser" {
    BeforeAll {
        $parserPath = Join-Path (Join-Path $PSScriptRoot "..") "module\LLMWorkflow\extraction\RPGMakerAssetCatalogParser.ps1"
        if (Test-Path $parserPath) {
            try { . $parserPath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } }
        }
    }

    It "detects RPG Maker project roots" {
        $projectRoot = Join-Path $TestDrive "RmmzProject"
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $projectRoot "img") -Force | Out-Null
        "" | Set-Content -LiteralPath (Join-Path $projectRoot "Game.rmmzproject") -Encoding UTF8

        (Test-RPGMakerAssetCatalog -ProjectRoot $projectRoot) | Should -Be $true
        (Test-RPGMakerAssetCatalog -ProjectRoot (Join-Path $TestDrive "MissingProject")) | Should -Be $false
    }

    It "catalogs common RPG Maker asset families" {
        $projectRoot = Join-Path $TestDrive "CatalogProject"
        @(
            "img\\characters",
            "img\\faces",
            "img\\tilesets",
            "img\\parallaxes",
            "audio\\bgm",
            "audio\\se",
            "js\\plugins"
        ) | ForEach-Object {
            New-Item -ItemType Directory -Path (Join-Path $projectRoot $_) -Force | Out-Null
        }

        "" | Set-Content -LiteralPath (Join-Path $projectRoot "Game.rmmzproject") -Encoding UTF8
        "png" | Set-Content -LiteralPath (Join-Path $projectRoot "img\\characters\\Actor1.png")
        "png" | Set-Content -LiteralPath (Join-Path $projectRoot "img\\faces\\Actor1.png")
        "png" | Set-Content -LiteralPath (Join-Path $projectRoot "img\\tilesets\\Dungeon.png")
        "png" | Set-Content -LiteralPath (Join-Path $projectRoot "img\\parallaxes\\Sky.png")
        "ogg" | Set-Content -LiteralPath (Join-Path $projectRoot "audio\\bgm\\Theme.ogg")
        "ogg" | Set-Content -LiteralPath (Join-Path $projectRoot "audio\\se\\Cursor.ogg")
        "console.log('plugin');" | Set-Content -LiteralPath (Join-Path $projectRoot "js\\plugins\\Utility.js")

        $catalog = Invoke-RPGMakerAssetCatalogParse -ProjectRoot $projectRoot

        $catalog.engineFamily | Should -Be "rpgmaker"
        $catalog.detectedVariant | Should -Be "MZ"
        $catalog.statistics.totalAssets | Should -Be 7
        $catalog.assetFamilies.characters.assetCount | Should -Be 1
        $catalog.assetFamilies.faces.assetCount | Should -Be 1
        $catalog.assetFamilies.tilesets.assetCount | Should -Be 1
        $catalog.assetFamilies.parallaxes.assetCount | Should -Be 1
        $catalog.assetFamilies.bgm.assetCount | Should -Be 1
        $catalog.assetFamilies.se.assetCount | Should -Be 1
        $catalog.assetFamilies.plugins.assetCount | Should -Be 1
        $catalog.assetFamilies.characters.entries[0].relativePath | Should -Be "img/characters/Actor1.png"
    }

    It "enriches plugin inventory with RPG Maker plugin metadata when requested" {
        $projectRoot = Join-Path $TestDrive "PluginProject"
        New-Item -ItemType Directory -Path (Join-Path $projectRoot "js\\plugins") -Force | Out-Null
        "" | Set-Content -LiteralPath (Join-Path $projectRoot "Game.rmmzproject") -Encoding UTF8

        @'
/*:
 * @target MZ
 * @plugindesc Inventory Test Plugin
 * @author TestAuthor
 * @version 1.2.0
 */
(function() {})();
'@ | Set-Content -LiteralPath (Join-Path $projectRoot "js\\plugins\\InventoryTest.js") -Encoding UTF8

        $catalog = Invoke-RPGMakerAssetCatalogParse -ProjectRoot $projectRoot -IncludePluginMetadata
        $pluginEntry = $catalog.assetFamilies.plugins.entries[0]

        $catalog.statistics.pluginCount | Should -Be 1
        $catalog.statistics.parsedPluginCount | Should -Be 1
        $pluginEntry.pluginMetadata.isRecognizedPlugin | Should -Be $true
        $pluginEntry.pluginMetadata.pluginName | Should -Be "Inventory Test Plugin"
        $pluginEntry.pluginMetadata.targetEngine | Should -Be "MZ"
        $pluginEntry.pluginMetadata.version | Should -Be "1.2.0"
    }
}
