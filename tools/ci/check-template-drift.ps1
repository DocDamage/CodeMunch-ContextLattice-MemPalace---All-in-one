[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Get-RelativeFileHashes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $rootPath = (Resolve-Path -LiteralPath $Root).Path
    $files = Get-ChildItem -LiteralPath $rootPath -Recurse -File | Sort-Object FullName
    $map = @{}
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($rootPath.Length).TrimStart('\', '/').Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        $map[$relative] = $hash
    }
    return $map
}

function Compare-DirectoryContent {
    param(
        [string]$SourcePath,
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Missing source path: $SourcePath"
    }
    if (-not (Test-Path -LiteralPath $TargetPath)) {
        throw "Missing target path: $TargetPath"
    }

    $sourceMap = Get-RelativeFileHashes -Root $SourcePath
    $targetMap = Get-RelativeFileHashes -Root $TargetPath

    $sourceKeys = @($sourceMap.Keys | Sort-Object)
    $targetKeys = @($targetMap.Keys | Sort-Object)

    $missingInTarget = @($sourceKeys | Where-Object { -not $targetMap.ContainsKey($_) })
    $extraInTarget = @($targetKeys | Where-Object { -not $sourceMap.ContainsKey($_) })
    $hashMismatches = @()

    foreach ($key in $sourceKeys) {
        if ($targetMap.ContainsKey($key) -and $sourceMap[$key] -ne $targetMap[$key]) {
            $hashMismatches += $key
        }
    }

    return [pscustomobject]@{
        Source = $SourcePath
        Target = $TargetPath
        MissingInTarget = $missingInTarget
        ExtraInTarget = $extraInTarget
        HashMismatches = $hashMismatches
        IsMatch = (($missingInTarget.Count -eq 0) -and ($extraInTarget.Count -eq 0) -and ($hashMismatches.Count -eq 0))
    }
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path

$pairs = @(
    @{
        Source = Join-Path $repoRoot "tools\codemunch"
        Target = Join-Path $repoRoot "module\LLMWorkflow\templates\tools\codemunch"
    },
    @{
        Source = Join-Path $repoRoot "tools\contextlattice"
        Target = Join-Path $repoRoot "module\LLMWorkflow\templates\tools\contextlattice"
    },
    @{
        Source = Join-Path $repoRoot "tools\memorybridge"
        Target = Join-Path $repoRoot "module\LLMWorkflow\templates\tools\memorybridge"
    }
)

$results = @()
foreach ($pair in $pairs) {
    $results += Compare-DirectoryContent -SourcePath $pair.Source -TargetPath $pair.Target
}

# workflow installer scripts are mirrored outside template trees.
$scriptPairs = @(
    @{
        Source = Join-Path $repoRoot "tools\workflow\bootstrap-llm-workflow.ps1"
        Target = Join-Path $repoRoot "module\LLMWorkflow\scripts\bootstrap-llm-workflow.ps1"
    },
    @{
        Source = Join-Path $repoRoot "tools\workflow\install-global-llm-workflow.ps1"
        Target = Join-Path $repoRoot "module\LLMWorkflow\scripts\install-global-llm-workflow.ps1"
    }
)

foreach ($pair in $scriptPairs) {
    if (-not (Test-Path -LiteralPath $pair.Source)) {
        throw "Missing source file: $($pair.Source)"
    }
    if (-not (Test-Path -LiteralPath $pair.Target)) {
        throw "Missing target file: $($pair.Target)"
    }
    $sourceHash = (Get-FileHash -LiteralPath $pair.Source -Algorithm SHA256).Hash
    $targetHash = (Get-FileHash -LiteralPath $pair.Target -Algorithm SHA256).Hash
    $isMatch = ($sourceHash -eq $targetHash)
    $results += [pscustomobject]@{
        Source = $pair.Source
        Target = $pair.Target
        MissingInTarget = @()
        ExtraInTarget = @()
        HashMismatches = if ($isMatch) { @() } else { @("<file hash mismatch>") }
        IsMatch = $isMatch
    }
}

$failed = @($results | Where-Object { -not $_.IsMatch })
if ($failed.Count -eq 0) {
    Write-Output "[drift-check] OK: templates and mirrored scripts are in sync."
    exit 0
}

Write-Error "[drift-check] Drift detected between tools and module copies."
foreach ($item in $failed) {
    Write-Output "Source: $($item.Source)"
    Write-Output "Target: $($item.Target)"
    if ($item.MissingInTarget.Count -gt 0) {
        Write-Output "  Missing in target:"
        foreach ($entry in $item.MissingInTarget) {
            Write-Output "   - $entry"
        }
    }
    if ($item.ExtraInTarget.Count -gt 0) {
        Write-Output "  Extra in target:"
        foreach ($entry in $item.ExtraInTarget) {
            Write-Output "   - $entry"
        }
    }
    if ($item.HashMismatches.Count -gt 0) {
        Write-Output "  Hash/content mismatches:"
        foreach ($entry in $item.HashMismatches) {
            Write-Output "   - $entry"
        }
    }
}

exit 1

