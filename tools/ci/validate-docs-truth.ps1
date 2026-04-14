#requires -Version 5.1
<#
.SYNOPSIS
    Validates that current-state docs agree on version and metrics.
.DESCRIPTION
    Computes the live repository counts for modules, packs, parser/extractor
    modules, and predefined golden tasks, then validates the current-state docs
    and docs-truth matrix against those values.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$drift = [System.Collections.Generic.List[string]]::new()
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path

function Add-Drift {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $script:drift.Add($Message)
}

function Get-FileText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Drift "Missing required doc: $RelativePath"
        return ""
    }

    return Get-Content -LiteralPath $path -Raw
}

function Assert-Match {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [Parameter(Mandatory = $true)]
        [string]$FailureMessage
    )

    if ($Content -notmatch $Pattern) {
        Add-Drift $FailureMessage
    }
}

function Assert-LiteralContains {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [string]$Literal,
        [Parameter(Mandatory = $true)]
        [string]$FailureMessage
    )

    if ($Content -notmatch [regex]::Escape($Literal)) {
        Add-Drift $FailureMessage
    }
}

# --- Truth sources ---
$version = (Get-Content -LiteralPath (Join-Path $repoRoot "VERSION") -Raw).Trim()

$moduleCount = (Get-ChildItem -Path (Join-Path $repoRoot "module\LLMWorkflow") -Filter "*.ps1" -Recurse |
    Where-Object {
        $_.Name -notlike "*.Tests.ps1" -and
        $_.FullName -notlike "*\templates\*" -and
        $_.FullName -notlike "*\LLMWorkflow\scripts\*"
    }).Count

$packCount = (Get-ChildItem -Path (Join-Path $repoRoot "packs\manifests") -Filter "*.json" |
    Where-Object {
        Test-Path (Join-Path (Join-Path $repoRoot "packs\registries") ($_.BaseName + ".sources.json"))
    }).Count

$parserCount = (Get-ChildItem -Path (Join-Path $repoRoot "module\LLMWorkflow\ingestion\parsers") -Filter "*.ps1" |
    Where-Object {
        $_.Name -notlike "*.Tests.ps1" -and
        ($_.Name.EndsWith("Parser.ps1") -or $_.Name.EndsWith("Extractor.ps1"))
    }).Count

$goldenTaskCount = (Select-String -Path (Join-Path $repoRoot "module\LLMWorkflow\governance\GoldenTaskDefinitions.ps1") -Pattern '-TaskId "gt-').Count

$mcpToolCount = 55

$manifest = Import-PowerShellDataFile -Path (Join-Path $repoRoot "module\LLMWorkflow\LLMWorkflow.psd1")
$readme = Get-FileText "README.md"
$progress = Get-FileText "docs\implementation\PROGRESS.md"
$releaseState = Get-FileText "docs\releases\RELEASE_STATE.md"
$docsTruth = Get-FileText "docs\reference\DOCS_TRUTH_MATRIX.md"
$platformOverview = Get-FileText "docs\architecture\PLATFORM_OVERVIEW.md"
$workflowIndex = Get-FileText "docs\workflow\LLMWorkflow_Canonical_Document_Set_INDEX.md"
$workflowRoadmap = Get-FileText "docs\workflow\LLMWorkflow_Canonical_Document_Set_Part_3_Godot_Blender_InterPack_and_Roadmap.md"

$docsTruthReadmeRow = ('| [`README.md`](../../README.md) | {0} | {1} | {2} | {3} | {4} | ✅ truth |' -f $version, $moduleCount, $packCount, $parserCount, $goldenTaskCount)
$docsTruthProgressRow = ('| [`PROGRESS.md`](../../docs/implementation/PROGRESS.md) | {0} | {1} | {2} | {3} | {4} | ✅ truth |' -f $version, $moduleCount, $packCount, $parserCount, $goldenTaskCount)
$docsTruthReleaseStateRow = ('| [`RELEASE_STATE.md`](../../docs/releases/RELEASE_STATE.md) | {0} | {1} | {2} | {3} | {4} | ✅ truth |' -f $version, $moduleCount, $packCount, $parserCount, $goldenTaskCount)

# --- Manifest checks ---
if ($manifest.ModuleVersion -ne $version) {
    Add-Drift "LLMWorkflow.psd1 ModuleVersion ($($manifest.ModuleVersion)) does not match VERSION ($version)"
}

# --- README checks ---
Assert-LiteralContains $readme "version-$version" "README.md version badge does not match VERSION ($version)"
Assert-LiteralContains $readme "PowerShell%20modules-$moduleCount" "README.md module badge does not match actual count ($moduleCount)"
Assert-LiteralContains $readme "domain%20packs-$packCount" "README.md pack badge does not match actual count ($packCount)"
Assert-LiteralContains $readme "**$moduleCount PowerShell Modules**" "README.md top-line module count does not match actual count ($moduleCount)"
Assert-Match $readme "\|\s+\*\*Extraction Parsers\*\*\s+\|\s+$parserCount\s+\|" "README.md parser stats row does not match actual count ($parserCount)"
Assert-LiteralContains $readme "Golden Task Evaluations ($goldenTaskCount Tasks)" "README.md golden task section total does not match actual count ($goldenTaskCount)"
Assert-LiteralContains $readme "Golden Task Coverage ($goldenTaskCount Total)" "README.md golden task coverage total does not match actual count ($goldenTaskCount)"
Assert-LiteralContains $readme "$goldenTaskCount predefined validation scenarios" "README.md golden task summary bullet does not match actual count ($goldenTaskCount)"

# --- PROGRESS checks ---
Assert-LiteralContains $progress "**Current Version:** $version" "docs/implementation/PROGRESS.md header version does not match VERSION ($version)"
Assert-Match $progress "\*\*PowerShell Modules:\*\*\s*$moduleCount" "docs/implementation/PROGRESS.md module count does not match actual count ($moduleCount)"
Assert-Match $progress "\*\*Domain Packs:\*\*\s*$packCount" "docs/implementation/PROGRESS.md pack count does not match actual count ($packCount)"
Assert-Match $progress "\*\*Extraction Parsers:\*\*\s*$parserCount" "docs/implementation/PROGRESS.md parser count does not match actual count ($parserCount)"
Assert-Match $progress "\*\*Golden Tasks:\*\*\s*$goldenTaskCount" "docs/implementation/PROGRESS.md golden task count does not match actual count ($goldenTaskCount)"

# --- RELEASE_STATE checks ---
Assert-LiteralContains $releaseState "**Declared Version:** ``$version``" "docs/releases/RELEASE_STATE.md version does not match VERSION ($version)"
Assert-Match $releaseState "(?s)- \*\*PowerShell Module\*\*:.*?Current count:\s*\*\*$moduleCount\*\*" "docs/releases/RELEASE_STATE.md module count does not match actual count ($moduleCount)"
Assert-Match $releaseState "(?s)- \*\*Domain Pack\*\*:.*?Current count:\s*\*\*$packCount\*\*" "docs/releases/RELEASE_STATE.md pack count does not match actual count ($packCount)"
Assert-Match $releaseState "(?s)- \*\*Extraction Parser\*\*:.*?Current count:\s*\*\*$parserCount\*\*" "docs/releases/RELEASE_STATE.md parser count does not match actual count ($parserCount)"
Assert-Match $releaseState "(?s)- \*\*Golden Task\*\*:.*?Current count:\s*\*\*$goldenTaskCount\*\*" "docs/releases/RELEASE_STATE.md golden task count does not match actual count ($goldenTaskCount)"
Assert-Match $releaseState "(?s)- \*\*MCP Tool\*\*:.*?Current count:\s*\*\*$mcpToolCount\*\*" "docs/releases/RELEASE_STATE.md MCP tool count does not match documented truth ($mcpToolCount)"

# --- DOCS_TRUTH_MATRIX checks ---
Assert-LiteralContains $docsTruth "**Current Count**: ``$moduleCount``" "docs/reference/DOCS_TRUTH_MATRIX.md module count does not match actual count ($moduleCount)"
Assert-LiteralContains $docsTruth "**Current Count**: ``$packCount``" "docs/reference/DOCS_TRUTH_MATRIX.md pack count does not match actual count ($packCount)"
Assert-LiteralContains $docsTruth "**Current Count**: ``$parserCount``" "docs/reference/DOCS_TRUTH_MATRIX.md parser count does not match actual count ($parserCount)"
Assert-LiteralContains $docsTruth "**Current Count**: ``$goldenTaskCount``" "docs/reference/DOCS_TRUTH_MATRIX.md golden task count does not match actual count ($goldenTaskCount)"
Assert-LiteralContains $docsTruth "**Current Count**: ``$mcpToolCount``" "docs/reference/DOCS_TRUTH_MATRIX.md MCP tool count does not match documented truth ($mcpToolCount)"
Assert-LiteralContains $docsTruth $docsTruthReadmeRow "docs/reference/DOCS_TRUTH_MATRIX.md README claims row is out of sync"
Assert-LiteralContains $docsTruth $docsTruthProgressRow "docs/reference/DOCS_TRUTH_MATRIX.md PROGRESS claims row is out of sync"
Assert-LiteralContains $docsTruth $docsTruthReleaseStateRow "docs/reference/DOCS_TRUTH_MATRIX.md RELEASE_STATE claims row is out of sync"
Assert-LiteralContains $docsTruth "Metrics verified: $moduleCount PowerShell modules, $packCount domain packs, $parserCount extraction parsers, $goldenTaskCount golden tasks" "docs/reference/DOCS_TRUTH_MATRIX.md metrics summary line is out of sync"

# --- PLATFORM_OVERVIEW checks ---
Assert-LiteralContains $platformOverview "**Version:** $version" "docs/architecture/PLATFORM_OVERVIEW.md version does not match VERSION ($version)"
Assert-Match $platformOverview "\*\*Total Functions:\*\* 800\+ \| \*\*Modules:\*\* $moduleCount \| \*\*Domain Packs:\*\* $packCount" "docs/architecture/PLATFORM_OVERVIEW.md headline counts are out of sync"
Assert-Match $platformOverview "\|\s+\*\*PowerShell Modules\*\*\s+\|\s+$moduleCount\s+\|" "docs/architecture/PLATFORM_OVERVIEW.md module metric row is out of sync"
Assert-Match $platformOverview "\|\s+\*\*Extraction Parsers\*\*\s+\|\s+$parserCount\s+\|" "docs/architecture/PLATFORM_OVERVIEW.md parser metric row is out of sync"
Assert-Match $platformOverview "\|\s+\*\*Golden Tasks\*\*\s+\|\s+$goldenTaskCount\s+\|" "docs/architecture/PLATFORM_OVERVIEW.md golden task metric row is out of sync"

# --- Canonical workflow summary checks ---
Assert-LiteralContains $workflowIndex "**Current Version:** $version" "docs/workflow/LLMWorkflow_Canonical_Document_Set_INDEX.md version does not match VERSION ($version)"
Assert-LiteralContains $workflowIndex "$moduleCount PowerShell modules" "docs/workflow/LLMWorkflow_Canonical_Document_Set_INDEX.md current-state module summary is out of sync"
Assert-LiteralContains $workflowRoadmap "**$moduleCount PowerShell modules** across all phases" "docs/workflow/LLMWorkflow_Canonical_Document_Set_Part_3_Godot_Blender_InterPack_and_Roadmap.md module summary is out of sync"
Assert-LiteralContains $workflowRoadmap "**Version $version**" "docs/workflow/LLMWorkflow_Canonical_Document_Set_Part_3_Godot_Blender_InterPack_and_Roadmap.md version summary is out of sync"

# --- Report ---
if ($drift.Count -gt 0) {
    Write-Output "::error title=Documentation Truth Drift::Documentation truth drift detected:"
    foreach ($item in $drift) {
        Write-Output "  - $item"
    }
    exit 1
}

Write-Output "Documentation truth validated successfully."
Write-Output "  Version:      $version"
Write-Output "  Modules:      $moduleCount"
Write-Output "  Packs:        $packCount"
Write-Output "  Parsers:      $parserCount"
Write-Output "  Golden Tasks: $goldenTaskCount"
Write-Output "  MCP Tools:    $mcpToolCount"
