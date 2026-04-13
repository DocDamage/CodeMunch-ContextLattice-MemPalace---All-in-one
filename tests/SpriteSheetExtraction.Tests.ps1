#requires -Version 5.1

<#
.SYNOPSIS
    Pester tests for SpriteSheetParser and AtlasMetadataParser.

.DESCRIPTION
    Validates spritesheet and atlas parsing, normalization,
    frame extraction, and manifest export.
#>

BeforeAll {
    $ExtractionPath = Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'module') 'LLMWorkflow') 'extraction'

    @(
        'SpriteSheetParser.ps1',
        'AtlasMetadataParser.ps1'
    ) | ForEach-Object {
        $path = Join-Path $ExtractionPath $_
        if (Test-Path $path) {
            . $path
        }
    }
}

Describe "SpriteSheetParser" {
    Context "New-SpriteSheetParser" {
        It "Returns parser configuration" {
            $parser = New-SpriteSheetParser
            $parser.parserName | Should -Be 'SpriteSheetParser'
            $parser.supportedFormats | Should -Contain 'aseprite-json'
            $parser.supportedFormats | Should -Contain 'generic-json'
        }
    }

    Context "Read-SpriteSheetJson" {
        It "Parses a generic spritesheet JSON" {
            $jsonPath = Join-Path $TestDrive 'spritesheet.json'
            @"
{
  "frames": {
    "frame1": {
      "frame": {"x":0,"y":0,"w":32,"h":32},
      "rotated": false,
      "trimmed": false,
      "spriteSourceSize": {"x":0,"y":0,"w":32,"h":32},
      "sourceSize": {"w":32,"h":32}
    },
    "frame2": {
      "frame": {"x":32,"y":0,"w":32,"h":32},
      "rotated": false,
      "trimmed": false,
      "spriteSourceSize": {"x":0,"y":0,"w":32,"h":32},
      "sourceSize": {"w":32,"h":32}
    }
  },
  "meta": {
    "app": "TestApp",
    "version": "1.0",
    "image": "sheet.png",
    "format": "RGBA8888",
    "size": {"w":64,"h":32},
    "scale": "1"
  }
}
"@ | Set-Content -LiteralPath $jsonPath -Encoding UTF8

            $result = Read-SpriteSheetJson -FilePath $jsonPath
            $result.format | Should -Be 'generic-json'
            $result.frameCount | Should -Be 2
            $result.frames[0].name | Should -Be 'frame1'
            $result.frames[0].frame.w | Should -Be 32
            $result.meta.image | Should -Be 'sheet.png'
        }

        It "Parses array-style frames" {
            $jsonPath = Join-Path $TestDrive 'spritesheet_array.json'
            @"
{
  "frames": [
    {"filename":"a","frame":{"x":0,"y":0,"w":16,"h":16}},
    {"filename":"b","frame":{"x":16,"y":0,"w":16,"h":16}}
  ],
  "meta": {"image":"sheet.png","size":{"w":32,"h":16}}
}
"@ | Set-Content -LiteralPath $jsonPath -Encoding UTF8

            $result = Read-SpriteSheetJson -FilePath $jsonPath
            $result.frameCount | Should -Be 2
            $result.frames[0].name | Should -Be 'a'
            $result.frames[1].name | Should -Be 'b'
        }

        It "Throws for missing file" {
            { Read-SpriteSheetJson -FilePath 'C:\NoSuchFile.json' } | Should -Throw
        }
    }

    Context "Read-AsepriteJson" {
        It "Parses Aseprite JSON with frame tags" {
            $jsonPath = Join-Path $TestDrive 'aseprite.json'
            @"
{
  "frames": {
    "Idle 0.aseprite": {
      "frame": {"x":0,"y":0,"w":32,"h":32},
      "duration": 100
    },
    "Idle 1.aseprite": {
      "frame": {"x":32,"y":0,"w":32,"h":32},
      "duration": 100
    }
  },
  "meta": {
    "app": "http://www.aseprite.org/",
    "version": "1.3.0",
    "image": "player.png",
    "format": "RGBA8888",
    "size": {"w":64,"h":32},
    "scale": "1",
    "frameTags": [
      {"name":"Idle","from":0,"to":1,"direction":"forward"}
    ],
    "layers": [
      {"name":"Layer 1","opacity":255,"blendMode":"normal"}
    ]
  }
}
"@ | Set-Content -LiteralPath $jsonPath -Encoding UTF8

            $result = Read-AsepriteJson -FilePath $jsonPath
            $result.format | Should -Be 'aseprite-json'
            $result.frameCount | Should -Be 2
            $result.frames[0].duration | Should -Be 100
            $result.meta.frameTags | Should -HaveCount 1
            $result.meta.frameTags[0].name | Should -Be 'Idle'
            $result.meta.frameTags[0].from | Should -Be 0
            $result.meta.frameTags[0].to | Should -Be 1
            $result.meta.layers | Should -HaveCount 1
            $result.meta.layers[0].name | Should -Be 'Layer 1'
        }
    }

    Context "Export-SpriteSheetManifest" {
        It "Exports a normalized manifest with animations" {
            $jsonPath = Join-Path $TestDrive 'aseprite_manifest.json'
            @"
{
  "frames": {"f1":{"frame":{"x":0,"y":0,"w":16,"h":16},"duration":100}},
  "meta": {
    "image": "sheet.png",
    "frameTags": [{"name":"Run","from":0,"to":0,"direction":"forward"}]
  }
}
"@ | Set-Content -LiteralPath $jsonPath -Encoding UTF8

            $data = Read-AsepriteJson -FilePath $jsonPath
            $manifest = Export-SpriteSheetManifest -SpriteSheetData $data
            $manifest.assetType | Should -Be 'spritesheet'
            $manifest.format | Should -Be 'aseprite-json'
            $manifest.animations | Should -HaveCount 1
            $manifest.animations[0].name | Should -Be 'Run'
        }
    }
}

Describe "AtlasMetadataParser" {
    Context "New-AtlasMetadataParser" {
        It "Returns parser configuration" {
            $parser = New-AtlasMetadataParser
            $parser.parserName | Should -Be 'AtlasMetadataParser'
            $parser.supportedFormats | Should -Contain 'texturepacker-json'
        }
    }

    Context "Read-AtlasJson" {
        It "Parses a TexturePacker-style atlas" {
            $jsonPath = Join-Path $TestDrive 'atlas.json'
            @'
{
  "frames": {
    "hero.png": {
      "frame": {"x":0,"y":0,"w":64,"h":64},
      "rotated": false,
      "trimmed": true,
      "spriteSourceSize": {"x":0,"y":0,"w":64,"h":64},
      "sourceSize": {"w":64,"h":64},
      "pivot": {"x":0.5,"y":0.5}
    }
  },
  "meta": {
    "app": "TexturePacker",
    "version": "1.0",
    "image": "atlas.png",
    "format": "RGBA8888",
    "size": {"w":128,"h":128},
    "scale": "1",
    "smartupdate": "$TexturePacker:SmartUpdate$"
  }
}
'@ | Set-Content -LiteralPath $jsonPath -Encoding UTF8

            $result = Read-AtlasJson -FilePath $jsonPath
            $result.format | Should -Be 'generic-atlas-json'
            $result.frameCount | Should -Be 1
            $result.frames[0].filename | Should -Be 'hero.png'
            $result.frames[0].pivot.x | Should -Be 0.5
            $result.meta.app | Should -Be 'TexturePacker'
            $result.meta.smartupdate | Should -Match 'SmartUpdate'
        }
    }

    Context "Get-AtlasFrames" {
        It "Returns flat array of frames" {
            $jsonPath = Join-Path $TestDrive 'atlas_frames.json'
            @"
{
  "frames": [
    {"filename":"a","frame":{"x":0,"y":0,"w":16,"h":16}},
    {"filename":"b","frame":{"x":16,"y":0,"w":16,"h":16}}
  ],
  "meta": {"image":"atlas.png"}
}
"@ | Set-Content -LiteralPath $jsonPath -Encoding UTF8

            $data = Read-AtlasJson -FilePath $jsonPath
            $frames = Get-AtlasFrames -AtlasData $data
            $frames | Should -HaveCount 2
        }
    }

    Context "Get-AtlasRegions" {
        It "Returns regions grouped by filename" {
            $jsonPath = Join-Path $TestDrive 'atlas_regions.json'
            @"
{
  "frames": {
    "r1": {"frame":{"x":0,"y":0,"w":8,"h":8}},
    "r2": {"frame":{"x":8,"y":0,"w":8,"h":8}}
  },
  "meta": {"image":"atlas.png"}
}
"@ | Set-Content -LiteralPath $jsonPath -Encoding UTF8

            $data = Read-AtlasJson -FilePath $jsonPath
            $regions = Get-AtlasRegions -AtlasData $data
            $regions['r1'] | Should -Not -BeNullOrEmpty
            $regions['r2'] | Should -Not -BeNullOrEmpty
            $regions['r1'].frame.w | Should -Be 8
        }
    }
}
