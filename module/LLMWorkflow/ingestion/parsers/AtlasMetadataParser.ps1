#requires -Version 5.1
<#
.SYNOPSIS
    Parses texture atlas metadata for game asset ingestion.

.DESCRIPTION
    Supports common texture atlas JSON formats such as those produced by
    TexturePacker and other atlas tools. Parses frames/regions, metadata,
    and image references into a normalized structure.

.PARAMETER FilePath
    Path to the atlas JSON metadata file.

.OUTPUTS
    System.Collections.Hashtable. Normalized atlas data.

.NOTES
    File Name      : AtlasMetadataParser.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
#>

Set-StrictMode -Version Latest

$script:ModuleVersion = '1.0.0'
$script:ModuleName = 'AtlasMetadataParser'

<#
.SYNOPSIS
    Creates a new atlas metadata parser configuration.

.OUTPUTS
    System.Collections.Hashtable. Parser configuration object.
#>
function New-AtlasMetadataParser {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return [ordered]@{
        parserName = 'AtlasMetadataParser'
        parserVersion = $script:ModuleVersion
        supportedFormats = @('texturepacker-json', 'generic-atlas-json')
        createdAt = [DateTime]::UtcNow.ToString('o')
    }
}

<#
.SYNOPSIS
    Reads a texture atlas JSON file.

.DESCRIPTION
    Parses JSON atlas metadata and returns normalized frames, metadata,
    and image references. Handles both TexturePacker hash and array formats.

.PARAMETER FilePath
    Path to the atlas JSON file.

.OUTPUTS
    System.Collections.Hashtable. Parsed atlas metadata.
#>
function Read-AtlasJson {
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
            $frames += ConvertTo-NormalizedAtlasFrame -Name $name -FrameObj $frameObj
        }
    }
    elseif ($json.frames -is [array]) {
        foreach ($frameObj in $json.frames) {
            $name = if ($frameObj.filename) { $frameObj.filename } else { '' }
            $frames += ConvertTo-NormalizedAtlasFrame -Name $name -FrameObj $frameObj
        }
    }

    if ($json.meta -ne $null) {
        $meta = ConvertTo-NormalizedAtlasMeta -MetaObj $json.meta
    }

    return [ordered]@{
        sourcePath = (Resolve-Path -LiteralPath $FilePath).Path
        format = 'generic-atlas-json'
        frames = $frames
        meta = $meta
        frameCount = $frames.Count
        parsedAt = [DateTime]::UtcNow.ToString('o')
        provenance = [ordered]@{ sourceFile = (Resolve-Path -LiteralPath $FilePath).Path; parsedBy = 'AtlasMetadataParser'; parsedAt = [DateTime]::UtcNow.ToString('o') }
        license = 'unknown'
        extractionDepth = 'deep'
    }
}

<#
.SYNOPSIS
    Gets atlas frames as a flat array of region descriptors.

.DESCRIPTION
    Converts parsed atlas frames into a flat array of region objects
    suitable for inventory and cataloging.

.PARAMETER AtlasData
    Output from Read-AtlasJson.

.OUTPUTS
    System.Array. Array of region hashtables.
#>
function Get-AtlasFrames {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [hashtable]$AtlasData
    )

    return @($AtlasData.frames)
}

<#
.SYNOPSIS
    Gets atlas regions grouped by filename.

.DESCRIPTION
    Returns a hashtable mapping frame names to their region data.

.PARAMETER AtlasData
    Output from Read-AtlasJson.

.OUTPUTS
    System.Collections.Hashtable. Regions grouped by name.
#>
function Get-AtlasRegions {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [hashtable]$AtlasData
    )

    $regions = [ordered]@{}
    foreach ($frame in $AtlasData.frames) {
        $filename = $null
        if ($frame -is [System.Collections.IDictionary] -and $frame.Contains('filename')) {
            $filename = $frame.filename
        }
        elseif ($frame -is [pscustomobject] -and $frame.filename) {
            $filename = $frame.filename
        }
        if (-not [string]::IsNullOrWhiteSpace($filename)) {
            $regions[$filename] = $frame
        }
    }
    return $regions
}

# Private helper: normalize atlas frame
function ConvertTo-NormalizedAtlasFrame {
    param(
        [string]$Name,
        [object]$FrameObj
    )

    $frame = [ordered]@{
        filename = $Name
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
        pivot = [ordered]@{
            x = 0.5
            y = 0.5
        }
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

    if ($null -ne $FrameObj -and $null -ne $FrameObj.PSObject.Properties['pivot'] -and $null -ne $FrameObj.pivot) {
        $p = $FrameObj.pivot
        $frame.pivot.x = if ($null -ne $p.PSObject.Properties['x'] -and $null -ne $p.x) { [double]$p.x } else { 0.5 }
        $frame.pivot.y = if ($null -ne $p.PSObject.Properties['y'] -and $null -ne $p.y) { [double]$p.y } else { 0.5 }
    }

    return $frame
}

# Private helper: normalize atlas meta
function ConvertTo-NormalizedAtlasMeta {
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
        smartupdate = ''
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
    if ($null -ne $MetaObj -and $null -ne $MetaObj.PSObject.Properties['smartupdate'] -and $null -ne $MetaObj.smartupdate) { $meta.smartupdate = [string]$MetaObj.smartupdate }

    return $meta
}

if ($null -ne $MyInvocation.MyCommand.Module) {
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'New-AtlasMetadataParser',
        'Read-AtlasJson',
        'Get-AtlasFrames',
        'Get-AtlasRegions'
    )
}

}

