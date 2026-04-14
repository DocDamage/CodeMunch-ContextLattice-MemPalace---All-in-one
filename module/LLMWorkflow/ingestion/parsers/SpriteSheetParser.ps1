#requires -Version 5.1
<#
.SYNOPSIS
    Parses common spritesheet metadata formats for game asset ingestion.

.DESCRIPTION
    Supports JSON atlas sidecars used by common spritesheet tools,
    including Aseprite JSON export and generic frame-based atlas files.
    Produces normalized output with frame data, animation names, and
    geometry information.

.PARAMETER FilePath
    Path to the spritesheet JSON metadata file.

.PARAMETER BaseImagePath
    Optional path to the associated image file.

.OUTPUTS
    System.Collections.Hashtable. Normalized spritesheet manifest.

.NOTES
    File Name      : SpriteSheetParser.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
#>

Set-StrictMode -Version Latest

$script:ModuleVersion = '1.0.0'
$script:ModuleName = 'SpriteSheetParser'

<#
.SYNOPSIS
    Creates a new spritesheet parser configuration.

.DESCRIPTION
    Returns a parser configuration hashtable with version and defaults.

.OUTPUTS
    System.Collections.Hashtable. Parser configuration object.
#>
function New-SpriteSheetParser {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return [ordered]@{
        parserName = 'SpriteSheetParser'
        parserVersion = $script:ModuleVersion
        supportedFormats = @('aseprite-json', 'generic-json')
        createdAt = [DateTime]::UtcNow.ToString('o')
    }
}

<#
.SYNOPSIS
    Reads a generic spritesheet JSON file.

.DESCRIPTION
    Parses a JSON file that contains frames and optional metadata.
    Handles both array-style and dictionary-style frames properties.

.PARAMETER FilePath
    Path to the JSON file.

.OUTPUTS
    System.Collections.Hashtable. Parsed spritesheet data.
#>
function Read-SpriteSheetJson {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('Path')]
        [string]$FilePath
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "File not found: $FilePath"
    }

    $content = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8
    $json = $content | ConvertFrom-Json -ErrorAction Stop

    $frames = @()
    $meta = @{}

    if ($json.frames -is [System.Collections.IDictionary] -or $json.frames -is [PSCustomObject]) {
        $frameEntries = $json.frames | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
        foreach ($name in $frameEntries) {
            $frameObj = $json.frames.$name
            $frames += ConvertTo-NormalizedFrame -Name $name -FrameObj $frameObj
        }
    }
    elseif ($json.frames -is [array]) {
        foreach ($frameObj in $json.frames) {
            $name = if ($null -ne $frameObj.PSObject.Properties['filename'] -and $null -ne $frameObj.filename) { $frameObj.filename } else { '' }
            $frames += ConvertTo-NormalizedFrame -Name $name -FrameObj $frameObj
        }
    }

    if ($null -ne $json.meta) {
        $meta = ConvertTo-NormalizedMeta -MetaObj $json.meta
    }

    return [ordered]@{
        sourcePath = (Resolve-Path -LiteralPath $FilePath).Path
        format = 'generic-json'
        frames = $frames
        meta = $meta
        frameCount = $frames.Count
        parsedAt = [DateTime]::UtcNow.ToString('o')
        provenance = [ordered]@{ sourceFile = (Resolve-Path -LiteralPath $FilePath).Path; parsedBy = 'SpriteSheetParser'; parsedAt = [DateTime]::UtcNow.ToString('o') }
        license = 'unknown'
        extractionDepth = 'deep'
    }
}

<#
.SYNOPSIS
    Reads an Aseprite JSON export file.

.DESCRIPTION
    Parses Aseprite-specific JSON spritesheet exports, preserving
    frame tags, slices, and layer information when present.

.PARAMETER FilePath
    Path to the Aseprite JSON file.

.OUTPUTS
    System.Collections.Hashtable. Parsed Aseprite spritesheet data.
#>
function Read-AsepriteJson {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('Path')]
        [string]$FilePath
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "File not found: $FilePath"
    }

    $content = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8
    $json = $content | ConvertFrom-Json -ErrorAction Stop

    $frames = @()
    if ($json.frames -is [System.Collections.IDictionary] -or $json.frames -is [PSCustomObject]) {
        $frameEntries = $json.frames | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
        foreach ($name in $frameEntries) {
            $frameObj = $json.frames.$name
            $normalized = ConvertTo-NormalizedFrame -Name $name -FrameObj $frameObj
            $normalized.duration = if ($null -ne $frameObj.PSObject.Properties['duration'] -and $null -ne $frameObj.duration) { [int]$frameObj.duration } else { 100 }
            $frames += $normalized
        }
    }
    elseif ($json.frames -is [array]) {
        foreach ($frameObj in $json.frames) {
            $name = if ($frameObj.filename) { $frameObj.filename } else { '' }
            $normalized = ConvertTo-NormalizedFrame -Name $name -FrameObj $frameObj
            $normalized.duration = if ($frameObj.duration) { [int]$frameObj.duration } else { 100 }
            $frames += $normalized
        }
    }

    $meta = @{}
    if ($null -ne $json.meta) {
        $meta = ConvertTo-NormalizedMeta -MetaObj $json.meta
        if ($null -ne $json.meta.PSObject.Properties['frameTags'] -and $null -ne $json.meta.frameTags) {
            $meta.frameTags = @()
            foreach ($tag in $json.meta.frameTags) {
                $meta.frameTags += [ordered]@{
                    name = [string]$tag.name
                    from = [int]$tag.from
                    to = [int]$tag.to
                    direction = [string]$tag.direction
                }
            }
        }
        if ($null -ne $json.meta.PSObject.Properties['slices'] -and $null -ne $json.meta.slices) {
            $meta.slices = @()
            foreach ($slice in $json.meta.slices) {
                $meta.slices += [ordered]@{
                    name = [string]$slice.name
                    color = [string]$slice.color
                    keys = @($slice.keys | ForEach-Object {
                        [ordered]@{
                            frame = [int]$_.frame
                            bounds = [ordered]@{
                                x = [int]$_.bounds.x
                                y = [int]$_.bounds.y
                                w = [int]$_.bounds.w
                                h = [int]$_.bounds.h
                            }
                        }
                    })
                }
            }
        }
        if ($null -ne $json.meta.PSObject.Properties['layers'] -and $null -ne $json.meta.layers) {
            $meta.layers = @()
            foreach ($layer in $json.meta.layers) {
                $meta.layers += [ordered]@{
                    name = [string]$layer.name
                    opacity = [int]$layer.opacity
                    blendMode = [string]$layer.blendMode
                }
            }
        }
    }

    return [ordered]@{
        sourcePath = (Resolve-Path -LiteralPath $FilePath).Path
        format = 'aseprite-json'
        frames = $frames
        meta = $meta
        frameCount = $frames.Count
        parsedAt = [DateTime]::UtcNow.ToString('o')
        provenance = [ordered]@{ sourceFile = (Resolve-Path -LiteralPath $FilePath).Path; parsedBy = 'SpriteSheetParser'; parsedAt = [DateTime]::UtcNow.ToString('o') }
        license = 'unknown'
        extractionDepth = 'deep'
    }
}

<#
.SYNOPSIS
    Exports a normalized spritesheet manifest.

.DESCRIPTION
    Converts parsed spritesheet data into a normalized manifest suitable
    for downstream ingestion and cataloging.

.PARAMETER SpriteSheetData
    Output from Read-SpriteSheetJson or Read-AsepriteJson.

.PARAMETER BaseImagePath
    Optional path to the associated texture/image file.

.OUTPUTS
    System.Collections.Hashtable. Normalized manifest.
#>
function Export-SpriteSheetManifest {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [hashtable]$SpriteSheetData,

        [Parameter()]
        [string]$BaseImagePath = ''
    )

    $imagePath = if ([string]::IsNullOrWhiteSpace($BaseImagePath)) {
        if ($SpriteSheetData.meta -and $SpriteSheetData.meta.image) {
            Join-Path (Split-Path -Parent $SpriteSheetData.sourcePath) $SpriteSheetData.meta.image
        } else {
            ''
        }
    } else {
        $BaseImagePath
    }

    $animations = @()
    if ($SpriteSheetData.meta -and $SpriteSheetData.meta.frameTags) {
        foreach ($tag in $SpriteSheetData.meta.frameTags) {
            $animations += [ordered]@{
                name = $tag.name
                frameStart = $tag.from
                frameEnd = $tag.to
                direction = $tag.direction
                frameCount = ($tag.to - $tag.from + 1)
            }
        }
    }

    return [ordered]@{
        assetType = 'spritesheet'
        sourcePath = $SpriteSheetData.sourcePath
        baseImagePath = $imagePath
        format = $SpriteSheetData.format
        frameCount = $SpriteSheetData.frameCount
        frames = $SpriteSheetData.frames
        animations = $animations
        meta = $SpriteSheetData.meta
        parsedAt = $SpriteSheetData.parsedAt
        exportedAt = [DateTime]::UtcNow.ToString('o')
        parserVersion = $script:ModuleVersion
        provenance = [ordered]@{ sourceFile = $SpriteSheetData.sourcePath; parsedBy = 'SpriteSheetParser'; parsedAt = [DateTime]::UtcNow.ToString('o') }
        license = 'unknown'
        extractionDepth = 'deep'
    }
}

# Private helper: normalize a frame object
function ConvertTo-NormalizedFrame {
    param(
        [string]$Name,
        [object]$FrameObj
    )

    $frame = [ordered]@{
        name = $Name
        frame = [ordered]@{
            x = 0
            y = 0
            w = 0
            h = 0
        }
        rotated = $false
        trimmed = $false
        spriteSourceSize = [ordered]@{
            x = 0
            y = 0
            w = 0
            h = 0
        }
        sourceSize = [ordered]@{
            w = 0
            h = 0
        }
        duration = 100
    }

    if ($null -ne $FrameObj -and $null -ne $FrameObj.PSObject.Properties['frame'] -and $null -ne $FrameObj.frame) {
        $f = $FrameObj.frame
        $frame.frame.x = if ($null -ne $f.PSObject.Properties['x'] -and $null -ne $f.x) { [int]$f.x } else { 0 }
        $frame.frame.y = if ($null -ne $f.PSObject.Properties['y'] -and $null -ne $f.y) { [int]$f.y } else { 0 }
        $frame.frame.w = if ($null -ne $f.PSObject.Properties['w'] -and $null -ne $f.w) { [int]$f.w } else { 0 }
        $frame.frame.h = if ($null -ne $f.PSObject.Properties['h'] -and $null -ne $f.h) { [int]$f.h } else { 0 }
    }

    if ($null -ne $FrameObj -and $null -ne $FrameObj.PSObject.Properties['rotated'] -and $null -ne $FrameObj.rotated) { $frame.rotated = [bool]$FrameObj.rotated }
    if ($null -ne $FrameObj -and $null -ne $FrameObj.PSObject.Properties['trimmed'] -and $null -ne $FrameObj.trimmed) { $frame.trimmed = [bool]$FrameObj.trimmed }

    if ($null -ne $FrameObj -and $null -ne $FrameObj.PSObject.Properties['spriteSourceSize'] -and $null -ne $FrameObj.spriteSourceSize) {
        $ss = $FrameObj.spriteSourceSize
        $frame.spriteSourceSize.x = if ($null -ne $ss.PSObject.Properties['x'] -and $null -ne $ss.x) { [int]$ss.x } else { 0 }
        $frame.spriteSourceSize.y = if ($null -ne $ss.PSObject.Properties['y'] -and $null -ne $ss.y) { [int]$ss.y } else { 0 }
        $frame.spriteSourceSize.w = if ($null -ne $ss.PSObject.Properties['w'] -and $null -ne $ss.w) { [int]$ss.w } else { 0 }
        $frame.spriteSourceSize.h = if ($null -ne $ss.PSObject.Properties['h'] -and $null -ne $ss.h) { [int]$ss.h } else { 0 }
    }

    if ($null -ne $FrameObj -and $null -ne $FrameObj.PSObject.Properties['sourceSize'] -and $null -ne $FrameObj.sourceSize) {
        $ss = $FrameObj.sourceSize
        $frame.sourceSize.w = if ($null -ne $ss.PSObject.Properties['w'] -and $null -ne $ss.w) { [int]$ss.w } else { 0 }
        $frame.sourceSize.h = if ($null -ne $ss.PSObject.Properties['h'] -and $null -ne $ss.h) { [int]$ss.h } else { 0 }
    }

    if ($null -ne $FrameObj -and $null -ne $FrameObj.PSObject.Properties['duration'] -and $null -ne $FrameObj.duration) { $frame.duration = [int]$FrameObj.duration }

    return $frame
}

# Private helper: normalize meta object
function ConvertTo-NormalizedMeta {
    param(
        [object]$MetaObj
    )

    $meta = [ordered]@{
        app = ''
        version = ''
        image = ''
        format = ''
        size = [ordered]@{
            w = 0
            h = 0
        }
        scale = '1'
        frameTags = @()
        slices = @()
        layers = @()
    }

    if ($null -ne $MetaObj -and $null -ne $MetaObj.PSObject.Properties['app'] -and $null -ne $MetaObj.app) { $meta.app = [string]$MetaObj.app }
    if ($null -ne $MetaObj -and $null -ne $MetaObj.PSObject.Properties['version'] -and $null -ne $MetaObj.version) { $meta.version = [string]$MetaObj.version }
    if ($null -ne $MetaObj -and $null -ne $MetaObj.PSObject.Properties['image'] -and $null -ne $MetaObj.image) { $meta.image = [string]$MetaObj.image }
    if ($null -ne $MetaObj -and $null -ne $MetaObj.PSObject.Properties['format'] -and $null -ne $MetaObj.format) { $meta.format = [string]$MetaObj.format }
    if ($null -ne $MetaObj -and $null -ne $MetaObj.PSObject.Properties['size'] -and $null -ne $MetaObj.size) {
        $s = $MetaObj.size
        $meta.size.w = if ($null -ne $s.PSObject.Properties['w'] -and $null -ne $s.w) { [int]$s.w } else { 0 }
        $meta.size.h = if ($null -ne $s.PSObject.Properties['h'] -and $null -ne $s.h) { [int]$s.h } else { 0 }
    }
    if ($null -ne $MetaObj -and $null -ne $MetaObj.PSObject.Properties['scale'] -and $null -ne $MetaObj.scale) { $meta.scale = [string]$MetaObj.scale }

    return $meta
}

if ($null -ne $MyInvocation.MyCommand.Module) {
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'New-SpriteSheetParser',
        'Read-SpriteSheetJson',
        'Read-AsepriteJson',
        'Export-SpriteSheetManifest'
    )
}

}
