#requires -Version 5.1
<#
.SYNOPSIS
    RPG Maker project asset catalog parser for the LLM Workflow ingestion pipeline.

.DESCRIPTION
    Catalogs RPG Maker project asset directories and plugin folders into a normalized
    inventory structure that can be used for evidence, provenance, and migration work.

    The parser focuses on safe project inventory:
    - image asset families such as characters, faces, tilesets, and parallaxes
    - audio asset families such as bgm, bgs, me, and se
    - JavaScript plugin inventory under js/plugins
    - optional plugin metadata enrichment when RPGMakerPluginParser is available

.NOTES
    File Name      : RPGMakerAssetCatalogParser.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Engine Support : RPG Maker MV, RPG Maker MZ
#>

Set-StrictMode -Version Latest

$script:RPGMakerAssetFamilyDefinitions = [ordered]@{
    animations = @{ relativePath = 'img/animations'; assetKind = 'animation' }
    battlebacks1 = @{ relativePath = 'img/battlebacks1'; assetKind = 'battleback' }
    battlebacks2 = @{ relativePath = 'img/battlebacks2'; assetKind = 'battleback' }
    battlers = @{ relativePath = 'img/enemies'; assetKind = 'battler' }
    characters = @{ relativePath = 'img/characters'; assetKind = 'character-sheet' }
    enemies = @{ relativePath = 'img/enemies'; assetKind = 'enemy' }
    faces = @{ relativePath = 'img/faces'; assetKind = 'face-sheet' }
    parallaxes = @{ relativePath = 'img/parallaxes'; assetKind = 'parallax' }
    pictures = @{ relativePath = 'img/pictures'; assetKind = 'picture' }
    svActors = @{ relativePath = 'img/sv_actors'; assetKind = 'sideview-actor' }
    svEnemies = @{ relativePath = 'img/sv_enemies'; assetKind = 'sideview-enemy' }
    system = @{ relativePath = 'img/system'; assetKind = 'system-image' }
    tilesets = @{ relativePath = 'img/tilesets'; assetKind = 'tileset' }
    titles1 = @{ relativePath = 'img/titles1'; assetKind = 'title-screen' }
    titles2 = @{ relativePath = 'img/titles2'; assetKind = 'title-screen' }
    bgm = @{ relativePath = 'audio/bgm'; assetKind = 'bgm' }
    bgs = @{ relativePath = 'audio/bgs'; assetKind = 'bgs' }
    me = @{ relativePath = 'audio/me'; assetKind = 'me' }
    se = @{ relativePath = 'audio/se'; assetKind = 'se' }
    plugins = @{ relativePath = 'js/plugins'; assetKind = 'plugin' }
}

<#
.SYNOPSIS
    Parses an RPG Maker project and returns a normalized asset catalog.
#>
function Invoke-RPGMakerAssetCatalogParse {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('Path')]
        [string]$ProjectRoot,

        [Parameter()]
        [switch]$IncludePluginMetadata
    )

    if (-not (Test-Path -LiteralPath $ProjectRoot)) {
        throw "Project root not found: $ProjectRoot"
    }

    $resolvedRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
    if (-not (Test-RPGMakerAssetCatalog -ProjectRoot $resolvedRoot)) {
        throw "Project root does not look like an RPG Maker project: $resolvedRoot"
    }

    if ($IncludePluginMetadata) {
        Import-RPGMakerPluginParserDependency | Out-Null
    }

    $catalog = [ordered]@{
        engineFamily = 'rpgmaker'
        projectRoot = $resolvedRoot
        projectName = Split-Path -Leaf $resolvedRoot
        detectedVariant = Get-RPGMakerProjectVariant -ProjectRoot $resolvedRoot
        catalogVersion = '1.0.0'
        assetFamilies = [ordered]@{}
        statistics = [ordered]@{
            totalAssets = 0
            totalSizeBytes = 0
            familyCounts = [ordered]@{}
            familiesPresent = 0
            pluginCount = 0
            parsedPluginCount = 0
        }
        parsedAt = [DateTime]::UtcNow.ToString('o')
    }

    foreach ($familyName in $script:RPGMakerAssetFamilyDefinitions.Keys) {
        $definition = $script:RPGMakerAssetFamilyDefinitions[$familyName]
        $entries = Get-RPGMakerAssetEntries `
            -ProjectRoot $resolvedRoot `
            -FamilyName $familyName `
            -RelativePath $definition.relativePath `
            -AssetKind $definition.assetKind `
            -IncludePluginMetadata:$IncludePluginMetadata

        $familySize = 0
        foreach ($entry in @($entries)) {
            if ($null -ne $entry -and $null -ne $entry.PSObject.Properties['fileSizeBytes']) {
                $familySize += [int64]$entry.fileSizeBytes
            }
        }

        $catalog.assetFamilies[$familyName] = [ordered]@{
            relativePath = $definition.relativePath
            assetKind = $definition.assetKind
            assetCount = @($entries).Count
            totalSizeBytes = [int64]$familySize
            entries = @($entries)
        }

        $catalog.statistics.familyCounts[$familyName] = @($entries).Count
        $catalog.statistics.totalAssets += @($entries).Count
        $catalog.statistics.totalSizeBytes += [int64]$familySize

        if (@($entries).Count -gt 0) {
            $catalog.statistics.familiesPresent++
        }

        if ($familyName -eq 'plugins') {
            $catalog.statistics.pluginCount = @($entries).Count
            $catalog.statistics.parsedPluginCount = @(
                $entries | Where-Object {
                    $null -ne $_.pluginMetadata -and
                    $null -ne $_.pluginMetadata.PSObject.Properties['pluginName'] -and
                    -not [string]::IsNullOrWhiteSpace([string]$_.pluginMetadata.pluginName)
                }
            ).Count
        }
    }

    return $catalog
}

<#
.SYNOPSIS
    Retrieves the asset entries for a specific RPG Maker asset family.
#>
function Get-RPGMakerAssetEntries {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [string]$FamilyName,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$AssetKind,

        [Parameter()]
        [switch]$IncludePluginMetadata
    )

    $absolutePath = Join-Path $ProjectRoot ($RelativePath -replace '/', '\')
    if (-not (Test-Path -LiteralPath $absolutePath)) {
        return @()
    }

    $entries = @()
    $files = Get-ChildItem -LiteralPath $absolutePath -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName
    foreach ($file in $files) {
        $relativeFilePath = Get-RPGMakerRelativePath -ProjectRoot $ProjectRoot -Path $file.FullName
        $entry = [ordered]@{
            family = $FamilyName
            assetKind = $AssetKind
            fileName = $file.Name
            baseName = $file.BaseName
            relativePath = $relativeFilePath
            format = $file.Extension.TrimStart('.').ToLowerInvariant()
            fileSizeBytes = [int64]$file.Length
            modifiedDate = $file.LastWriteTime.ToString('yyyy-MM-dd')
        }

        if ($FamilyName -eq 'plugins') {
            $entry.pluginMetadata = Get-RPGMakerPluginMetadataSafe -Path $file.FullName -IncludePluginMetadata:$IncludePluginMetadata
        }

        $entries += [pscustomobject]$entry
    }

    return $entries
}

<#
.SYNOPSIS
    Tests whether the specified path is a valid RPG Maker project.
#>
function Test-RPGMakerAssetCatalog {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('Path')]
        [string]$ProjectRoot
    )

    if (-not (Test-Path -LiteralPath $ProjectRoot)) {
        return $false
    }

    $resolvedRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $markers = @(
        'Game.rmmzproject',
        'Game.rpgproject',
        'img',
        'audio',
        'js\plugins'
    )

    foreach ($marker in $markers) {
        if (Test-Path -LiteralPath (Join-Path $resolvedRoot $marker)) {
            return $true
        }
    }

    return $false
}

<#
.SYNOPSIS
    Parses an RPG Maker project and exports the asset catalog to a JSON file.
#>
function Export-RPGMakerAssetCatalog {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter()]
        [string]$OutputPath = '',

        [Parameter()]
        [switch]$IncludePluginMetadata,

        [Parameter()]
        [switch]$Force
    )

    $catalog = Invoke-RPGMakerAssetCatalogParse -ProjectRoot $ProjectRoot -IncludePluginMetadata:$IncludePluginMetadata

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Join-Path $catalog.projectRoot 'asset-catalog.json'
    }

    if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
        throw "Output file already exists: $OutputPath"
    }

    $catalog | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    return [pscustomobject]@{
        Success = $true
        OutputPath = $OutputPath
        TotalAssets = $catalog.statistics.totalAssets
        ParsedPluginCount = $catalog.statistics.parsedPluginCount
    }
}

function Get-RPGMakerProjectVariant {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    if (Test-Path -LiteralPath (Join-Path $ProjectRoot 'Game.rmmzproject')) {
        return 'MZ'
    }

    if (Test-Path -LiteralPath (Join-Path $ProjectRoot 'Game.rpgproject')) {
        return 'MV'
    }

    return 'Unknown'
}

function Get-RPGMakerRelativePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $root = [System.IO.Path]::GetFullPath($ProjectRoot)
    $fullPath = [System.IO.Path]::GetFullPath($Path)

    if ($fullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
    }

    return $fullPath.Replace('\', '/')
}

function Get-RPGMakerPluginMetadataSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [switch]$IncludePluginMetadata
    )

    $metadata = [ordered]@{
        fileName = [System.IO.Path]::GetFileName($Path)
        pluginName = ''
        targetEngine = ''
        version = ''
        author = ''
        isRecognizedPlugin = $false
    }

    if (-not $IncludePluginMetadata) {
        return [pscustomobject]$metadata
    }

    $fallback = Get-RPGMakerPluginHeaderFallback -Path $Path
    if ($null -ne $fallback) {
        $metadata.pluginName = $fallback.pluginName
        $metadata.targetEngine = $fallback.targetEngine
        $metadata.version = $fallback.version
        $metadata.author = $fallback.author
        $metadata.isRecognizedPlugin = $fallback.isRecognizedPlugin
    }

    try {
        if (Import-RPGMakerPluginParserDependency -and (Get-Command -Name Test-RPGMakerPlugin -ErrorAction SilentlyContinue)) {
            $metadata.isRecognizedPlugin = [bool](Test-RPGMakerPlugin -Path $Path)
        }

        if ($metadata.isRecognizedPlugin -and (Get-Command -Name Invoke-RPGMakerPluginParse -ErrorAction SilentlyContinue)) {
            $manifest = Invoke-RPGMakerPluginParse -Path $Path
            if ($null -ne $manifest) {
                $metadata.pluginName = [string]$manifest.pluginName
                $metadata.targetEngine = [string]$manifest.targetEngine
                $metadata.version = [string]$manifest.version
                $metadata.author = [string]$manifest.author
            }
        }

        if ([string]::IsNullOrWhiteSpace($metadata.pluginName) -and $null -ne $fallback) { $metadata.pluginName = $fallback.pluginName }
        if ([string]::IsNullOrWhiteSpace($metadata.targetEngine) -and $null -ne $fallback) { $metadata.targetEngine = $fallback.targetEngine }
        if ([string]::IsNullOrWhiteSpace($metadata.version) -and $null -ne $fallback) { $metadata.version = $fallback.version }
        if ([string]::IsNullOrWhiteSpace($metadata.author) -and $null -ne $fallback) { $metadata.author = $fallback.author }
    }
    catch {
        Write-Verbose "[RPGMakerAssetCatalogParser] Failed to enrich plugin metadata for '$Path': $_"
    }

    return [pscustomobject]$metadata
}

function Get-RPGMakerPluginHeaderFallback {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        return [pscustomobject]@{
            pluginName = Get-RPGMakerPluginAnnotationValue -Content $content -Annotation 'plugindesc'
            targetEngine = Get-RPGMakerPluginAnnotationValue -Content $content -Annotation 'target'
            version = Get-RPGMakerPluginAnnotationValue -Content $content -Annotation 'version'
            author = Get-RPGMakerPluginAnnotationValue -Content $content -Annotation 'author'
            isRecognizedPlugin = ($content -match '@plugindesc' -or $content -match '@target' -or $content -match 'PluginManager\.parameters')
        }
    }
    catch {
        return $null
    }
}

function Get-RPGMakerPluginAnnotationValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$Annotation
    )

    $pattern = "(?im)^\s*\*?\s*@{0}\s+(.+)$" -f [regex]::Escape($Annotation)
    $match = [regex]::Match($Content, $pattern)
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }

    return ''
}

function Import-RPGMakerPluginParserDependency {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ((Get-Command -Name Invoke-RPGMakerPluginParse -ErrorAction SilentlyContinue) -and
        (Get-Command -Name Test-RPGMakerPlugin -ErrorAction SilentlyContinue)) {
        return $true
    }

    $dependencyPath = Join-Path $PSScriptRoot 'RPGMakerPluginParser.ps1'
    if (-not (Test-Path -LiteralPath $dependencyPath)) {
        return $false
    }

    try {
        Import-Module $dependencyPath -Force -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-Verbose "[RPGMakerAssetCatalogParser] Failed to import RPGMakerPluginParser dependency: $_"
        return $false
    }
}

if ($null -ne $MyInvocation.MyCommand.Module) {
    Export-ModuleMember -Function @(
        'Invoke-RPGMakerAssetCatalogParse',
        'Get-RPGMakerAssetEntries',
        'Test-RPGMakerAssetCatalog',
        'Export-RPGMakerAssetCatalog'
    )
}
