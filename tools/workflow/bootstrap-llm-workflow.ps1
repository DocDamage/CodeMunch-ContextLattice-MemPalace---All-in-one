[CmdletBinding()]
param(
    [string]$ProjectRoot = ".",
    [string]$ToolkitSource = "",
    [switch]$SkipDependencyInstall,
    [switch]$SkipContextVerify,
    [switch]$SkipBridgeDryRun,
    [switch]$SmokeTestContext,
    [switch]$RequireSearchHit
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Output "[llm-workflow] $Message"
}

function Resolve-ToolkitSourcePath {
    param([string]$RequestedSource)

    if (-not [string]::IsNullOrWhiteSpace($RequestedSource)) {
        return (Resolve-Path -LiteralPath $RequestedSource).Path
    }

    if (-not [string]::IsNullOrWhiteSpace($env:LLM_WORKFLOW_TOOLKIT_SOURCE) -and (Test-Path -LiteralPath $env:LLM_WORKFLOW_TOOLKIT_SOURCE)) {
        return (Resolve-Path -LiteralPath $env:LLM_WORKFLOW_TOOLKIT_SOURCE).Path
    }

    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $localToolsRoot = (Resolve-Path -LiteralPath (Join-Path $scriptRoot "..")).Path
    $expectedDirs = @("codemunch", "contextlattice", "memorybridge")
    $allPresent = $true
    foreach ($name in $expectedDirs) {
        if (-not (Test-Path -LiteralPath (Join-Path $localToolsRoot $name))) {
            $allPresent = $false
            break
        }
    }
    if ($allPresent) {
        return $localToolsRoot
    }

    throw "Toolkit source not found. Set -ToolkitSource or LLM_WORKFLOW_TOOLKIT_SOURCE."
}

function Ensure-ToolFolder {
    param(
        [string]$ToolsRoot,
        [string]$ProjectPath,
        [string]$ToolName
    )

    $target = Join-Path (Join-Path $ProjectPath "tools") $ToolName
    if (Test-Path -LiteralPath $target) {
        Write-Step "tools/$ToolName already exists."
        return
    }

    $source = Join-Path $ToolsRoot $ToolName
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing toolkit template: $source"
    }

    New-Item -ItemType Directory -Path (Join-Path $ProjectPath "tools") -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
    Write-Step "Installed tools/$ToolName from template source."
}

function Import-EnvFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    foreach ($rawLine in (Get-Content -LiteralPath $Path)) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if ($line.StartsWith("#")) {
            continue
        }
        if ($line -match "^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$") {
            $name = $matches[1]
            $value = $matches[2]
            if ($value.Length -ge 2) {
                if (($value.StartsWith("'") -and $value.EndsWith("'")) -or ($value.StartsWith('"') -and $value.EndsWith('"'))) {
                    $value = $value.Substring(1, $value.Length - 2)
                }
            }
            [System.Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }

    Write-Step "Loaded env vars from $Path"
}

function Ensure-PythonImport {
    param(
        [string]$ImportName,
        [string]$InstallName
    )

    $probe = "import importlib.util; print(bool(importlib.util.find_spec(r'$ImportName')))"
    $resultRaw = & python -c $probe 2>$null
    $result = if ($null -eq $resultRaw) { "" } else { ($resultRaw | Out-String).Trim() }
    if ($LASTEXITCODE -eq 0 -and $result -eq "True") {
        Write-Step "Python module '$ImportName' is available."
        return
    }

    Write-Step "Installing Python package '$InstallName' ..."
    & python -m pip install --upgrade $InstallName
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install Python package: $InstallName"
    }
}

function Ensure-CodemunchCommand {
    $cmd = Get-Command codemunch-pro -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Step "codemunch-pro command found: $($cmd.Source)"
        return
    }

    Write-Step "Installing codemunch-pro ..."
    & python -m pip install --upgrade codemunch-pro
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install codemunch-pro."
    }
}

function Invoke-IfExists {
    param(
        [string]$ScriptPath,
        [hashtable]$NamedArgs = @{}
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "Missing script: $ScriptPath"
    }

    & $ScriptPath @NamedArgs
    $exitCodeVar = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    if ($exitCodeVar -and $exitCodeVar.Value -ne 0) {
        throw "Script failed: $ScriptPath (exit $($exitCodeVar.Value))"
    }
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$toolsSource = Resolve-ToolkitSourcePath -RequestedSource $ToolkitSource

Write-Step "Project root: $projectPath"
Write-Step "Toolkit source: $toolsSource"

Ensure-ToolFolder -ToolsRoot $toolsSource -ProjectPath $projectPath -ToolName "codemunch"
Ensure-ToolFolder -ToolsRoot $toolsSource -ProjectPath $projectPath -ToolName "contextlattice"
Ensure-ToolFolder -ToolsRoot $toolsSource -ProjectPath $projectPath -ToolName "memorybridge"

if (-not $SkipDependencyInstall) {
    Ensure-CodemunchCommand
    Ensure-PythonImport -ImportName "chromadb" -InstallName "chromadb"
}

$codemunchBootstrap = Join-Path $projectPath "tools\codemunch\bootstrap-project.ps1"
$contextBootstrap = Join-Path $projectPath "tools\contextlattice\bootstrap-project.ps1"
$contextVerify = Join-Path $projectPath "tools\contextlattice\verify.ps1"
$memoryBootstrap = Join-Path $projectPath "tools\memorybridge\bootstrap-project.ps1"
$memorySync = Join-Path $projectPath "tools\memorybridge\sync-from-mempalace.ps1"

Invoke-IfExists -ScriptPath $codemunchBootstrap -NamedArgs @{ ProjectRoot = $projectPath }
Invoke-IfExists -ScriptPath $contextBootstrap -NamedArgs @{ ProjectRoot = $projectPath }
Invoke-IfExists -ScriptPath $memoryBootstrap -NamedArgs @{ ProjectRoot = $projectPath }

Import-EnvFile -Path (Join-Path $projectPath ".env")
Import-EnvFile -Path (Join-Path $projectPath ".contextlattice\orchestrator.env")

if (-not $SkipContextVerify) {
    if (-not [string]::IsNullOrWhiteSpace($env:CONTEXTLATTICE_ORCHESTRATOR_API_KEY)) {
        $verifyArgs = @{}
        if ($SmokeTestContext) {
            $verifyArgs["SmokeTest"] = $true
        }
        if ($RequireSearchHit) {
            $verifyArgs["RequireSearchHit"] = $true
        }
        Invoke-IfExists -ScriptPath $contextVerify -NamedArgs $verifyArgs
    } else {
        Write-Warning "[llm-workflow] Skipping ContextLattice verify: CONTEXTLATTICE_ORCHESTRATOR_API_KEY is not set."
    }
}

if (-not $SkipBridgeDryRun) {
    if (-not [string]::IsNullOrWhiteSpace($env:CONTEXTLATTICE_ORCHESTRATOR_API_KEY)) {
        Invoke-IfExists -ScriptPath $memorySync -NamedArgs @{ DryRun = $true }
    } else {
        Write-Warning "[llm-workflow] Skipping MemPalace bridge dry-run: CONTEXTLATTICE_ORCHESTRATOR_API_KEY is not set."
    }
}

Write-Step "Workflow bootstrap complete."
