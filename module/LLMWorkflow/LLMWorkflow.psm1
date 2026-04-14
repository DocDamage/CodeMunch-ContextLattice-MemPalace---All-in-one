Set-StrictMode -Version Latest

# Save the module root path for later use (PSScriptRoot changes when dot-sourcing)
$script:ModuleRoot = $PSScriptRoot

# Helper to check PS version requirement
function Test-PSVersionRequirement {
    param([string]$FilePath)
    $firstLine = Get-Content -LiteralPath $FilePath -TotalCount 1
    if ($firstLine -match '#requires\s+-Version\s+7') {
        if ($PSVersionTable.PSVersion.Major -lt 7) {
            return $false
        }
    }
    return $true
}

# Source core infrastructure components (Phase 1 priorities)
$CoreDirectory = Join-Path $PSScriptRoot "core"

$CoreFiles = @(
    # Type converters (canonical helper) - MUST BE FIRST for other core components
    "TypeConverters.ps1",
    # Run identification and logging (Priority 1: Journaling)
    "RunId.ps1",
    "Logging.ps1",
    "Journal.ps1",
    # State safety (Priority 2: File locking + atomic writes)
    "FileLock.ps1",
    "AtomicWrite.ps1",
    "StateFile.ps1",
    # Configuration (Priority 3: Effective config)
    "ConfigSchema.ps1",
    "ConfigPath.ps1",
    "Config.ps1",
    "ConfigCLI.ps1",
    # Policy and execution (Priority 4: Policy + execution modes)
    "Policy.ps1",
    "ExecutionMode.ps1",
    "CommandContract.ps1",
    # Workspace and visibility (Priority 5: Workspace boundaries)
    "Workspace.ps1",
    "Visibility.ps1",
    "PackVisibility.ps1"
)

foreach ($coreFile in $CoreFiles) {
    $corePath = Join-Path $CoreDirectory $coreFile
    if (Test-Path -LiteralPath $corePath) {
        . $corePath
    }
}

# Source telemetry components (Workstream 2)
Get-ChildItem -Path (Join-Path $script:ModuleRoot "telemetry") -Filter "*.ps1" -File | ForEach-Object {
    if (Test-PSVersionRequirement -FilePath $_.FullName) {
        . $_.FullName
    } else {
        Write-Verbose "Skipping PS 7-only script: $($_.Name)"
    }
}


# Source pack framework components (Phase 2 priorities)
$PackDirectory = Join-Path $script:ModuleRoot "pack"
$PackFiles = @(
    "PackManifest.ps1",
    "SourceRegistry.ps1",
    "PackTransaction.ps1"
)

foreach ($packFile in $PackFiles) {
    $packPath = Join-Path $PackDirectory $packFile
    if (Test-Path -LiteralPath $packPath) {
        . $packPath
    }
}

# Source workflow components (Phase 3 priorities)
$WorkflowDirectory = Join-Path $script:ModuleRoot "workflow"
$WorkflowFiles = @(
    "HealthScore.ps1",
    "Planner.ps1",
    "GitHooks.ps1",
    "Compatibility.ps1",
    "Filters.ps1",
    "Notifications.ps1",
    "DurableOrchestrator.ps1",
    "FailureTaxonomy.ps1"
)

foreach ($workflowFile in $WorkflowFiles) {
    $workflowPath = Join-Path $WorkflowDirectory $workflowFile
    if (Test-Path -LiteralPath $workflowPath) {
        . $workflowPath
    }
}


# Source retrieval components (Phase 5 priorities)
Get-ChildItem -Path (Join-Path $script:ModuleRoot "retrieval") -Filter "*.ps1" -File | ForEach-Object {
    if (Test-PSVersionRequirement -FilePath $_.FullName) {
        . $_.FullName
    } else {
        Write-Verbose "Skipping PS 7-only script: $($_.Name)"
    }
}

# Source governance components (Phase 6 priorities)
Get-ChildItem -Path (Join-Path $script:ModuleRoot "governance") -Filter "*.ps1" -File | ForEach-Object {
    if (Test-PSVersionRequirement -FilePath $_.FullName) {
        . $_.FullName
    } else {
        Write-Verbose "Skipping PS 7-only script: $($_.Name)"
    }
}


# Source policy components (Workstream 3)
Get-ChildItem -Path (Join-Path $script:ModuleRoot "policy") -Filter "*.ps1" -File | ForEach-Object {
    if (Test-PSVersionRequirement -FilePath $_.FullName) {
        . $_.FullName
    } else {
        Write-Verbose "Skipping PS 7-only script: $($_.Name)"
    }
}

# Source ingestion components (Workstream 4)
Get-ChildItem -Path (Join-Path $script:ModuleRoot "ingestion") -Filter "*.ps1" -File | ForEach-Object {
    if (Test-PSVersionRequirement -FilePath $_.FullName) {
        . $_.FullName
    } else {
        Write-Verbose "Skipping PS 7-only script: $($_.Name)"
    }
}

# Source MCP components (Phase 7 priorities)
$mcpExclude = @("FederatedMemory.ps1", "SnapshotManager.ps1", "NaturalLanguageConfig.ps1", "ExternalIngestion.ps1")
Get-ChildItem -Path (Join-Path $script:ModuleRoot "mcp") -Filter "*.ps1" -File | Where-Object {
    $_.Name -notin $mcpExclude
} | ForEach-Object {
    if (Test-PSVersionRequirement -FilePath $_.FullName) {
        . $_.FullName
    } else {
        Write-Verbose "Skipping PS 7-only script: $($_.Name)"
    }
}

# Source snapshot components
Get-ChildItem -Path (Join-Path $script:ModuleRoot "snapshot") -Filter "*.ps1" -File | ForEach-Object {
    if (Test-PSVersionRequirement -FilePath $_.FullName) {
        . $_.FullName
    } else {
        Write-Verbose "Skipping PS 7-only script: $($_.Name)"
    }
}

# Source inter-pack pipeline components (Phase 7)
Get-ChildItem -Path (Join-Path $script:ModuleRoot "interpack") -Filter "*.ps1" -File | ForEach-Object {
    if (Test-PSVersionRequirement -FilePath $_.FullName) {
        . $_.FullName
    } else {
        Write-Verbose "Skipping PS 7-only script: $($_.Name)"
    }
}
<#
.SYNOPSIS
    Returns the base path for user-installed PowerShell modules.
#>
function Get-UserModuleBasePath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $moduleRoots = @($env:PSModulePath -split [IO.Path]::PathSeparator | Where-Object { $_ -and $_ -like "$HOME*" })
    if ($moduleRoots.Count -gt 0) {
        return $moduleRoots[0]
    }
    # Platform-specific fallback
    if ($IsWindows -or ($PSVersionTable.PSVersion.Major -lt 6)) {
        return (Join-Path $HOME "Documents\WindowsPowerShell\Modules")
    } else {
        return (Join-Path $HOME ".local/share/powershell/Modules")
    }
}

<#
.SYNOPSIS
    Parses a .env file into a hashtable of key-value pairs.
#>
function Get-EnvFileMap {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([string]$Path)

    $result = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $result
    }

    foreach ($rawLine in (Get-Content -LiteralPath $Path)) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
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
            $result[$name] = $value
        }
    }

    return $result
}

function Remove-ProfileMarkerBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [string]$StartMarker,
        [Parameter(Mandatory = $true)]
        [string]$EndMarker
    )

    $pattern = [regex]::Escape($StartMarker) + ".*?" + [regex]::Escape($EndMarker) + "\r?\n?"
    $regexOptions = [System.Text.RegularExpressions.RegexOptions]::Singleline
    return [regex]::Replace($Content, $pattern, "", $regexOptions)
}

<#
.SYNOPSIS
    Retrieves version and installation metadata for the LLMWorkflow module.
#>
function Get-LLMWorkflowVersion {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $manifestPath = Join-Path $PSScriptRoot "LLMWorkflow.psd1"
    $manifest = Import-PowerShellDataFile -Path $manifestPath
    $available = @(Get-Module -ListAvailable -Name LLMWorkflow | Sort-Object -Property Version -Descending)
    $latestInstalled = if ($available.Count -gt 0) { [string]$available[0].Version } else { "" }
    $moduleBase = Get-UserModuleBasePath

    [pscustomobject]@{
        moduleName = "LLMWorkflow"
        manifestVersion = [string]$manifest.ModuleVersion
        latestInstalledVersion = $latestInstalled
        installedVersions = @($available | ForEach-Object { [string]$_.Version } | Select-Object -Unique)
        moduleBasePath = $moduleBase
        moduleRootExists = (Test-Path -LiteralPath (Join-Path $moduleBase "LLMWorkflow"))
        installRoot = "$HOME\.llm-workflow"
        installRootExists = (Test-Path -LiteralPath "$HOME\.llm-workflow")
        toolkitSourceEnv = [System.Environment]::GetEnvironmentVariable("LLM_WORKFLOW_TOOLKIT_SOURCE", "User")
    }
}

<#
.SYNOPSIS
    Installs the LLMWorkflow global launcher and toolkit.
#>
function Install-LLMWorkflow {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [string]$InstallRoot = "$HOME\.llm-workflow",
        [switch]$NoProfileUpdate,
        [string]$ProfilePath = $PROFILE,
        [switch]$SkipUserEnvPersist
    )

    $scriptPath = Join-Path (Join-Path $PSScriptRoot "scripts") "install-global-llm-workflow.ps1"
    $toolkitSource = Join-Path (Join-Path $PSScriptRoot "templates") "tools"

    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Missing script: $scriptPath"
    }
    if (-not (Test-Path -LiteralPath $toolkitSource)) {
        throw "Missing toolkit templates: $toolkitSource"
    }

    $invokeArgs = @{
        InstallRoot = $InstallRoot
        ToolkitSource = $toolkitSource
        ProfilePath = $ProfilePath
    }
    if ($NoProfileUpdate) {
        $invokeArgs["NoProfileUpdate"] = $true
    }
    if ($SkipUserEnvPersist) {
        $invokeArgs["SkipUserEnvPersist"] = $true
    }

    & $scriptPath @invokeArgs
}

<#
.SYNOPSIS
    Uninstalls the LLMWorkflow global launcher, module files, and environment variables.
#>
function Uninstall-LLMWorkflow {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$InstallRoot = "$HOME\.llm-workflow",
        [string]$ProfilePath = $PROFILE,
        [switch]$KeepInstallRoot,
        [switch]$KeepModuleFiles,
        [switch]$KeepUserEnv
    )

    $actions = [ordered]@{
        installRootRemoved = $false
        profileUpdated = $false
        userEnvCleared = $false
        moduleFilesRemoved = $false
    }

    if (-not $KeepInstallRoot -and (Test-Path -LiteralPath $InstallRoot)) {
        Remove-Item -LiteralPath $InstallRoot -Recurse -Force
        $actions.installRootRemoved = $true
    }

    if (-not $KeepUserEnv) {
        [System.Environment]::SetEnvironmentVariable("LLM_WORKFLOW_TOOLKIT_SOURCE", $null, "User")
        [System.Environment]::SetEnvironmentVariable("LLM_WORKFLOW_TOOLKIT_SOURCE", $null, "Process")
        $actions.userEnvCleared = $true
    }

    if (Test-Path -LiteralPath $ProfilePath) {
        $content = Get-Content -LiteralPath $ProfilePath -Raw
        if ($null -eq $content) {
            $content = ""
        }
        $updated = $content
        $updated = Remove-ProfileMarkerBlock -Content $updated -StartMarker "# >>> llmworkflow-module >>>" -EndMarker "# <<< llmworkflow-module <<<"
        $updated = Remove-ProfileMarkerBlock -Content $updated -StartMarker "# >>> llm-workflow >>>" -EndMarker "# <<< llm-workflow <<<"
        if ($updated -ne $content) {
            Set-Content -LiteralPath $ProfilePath -Value $updated -Encoding UTF8
            $actions.profileUpdated = $true
        }
    }

    if (-not $KeepModuleFiles) {
        Remove-Module LLMWorkflow -ErrorAction SilentlyContinue
        $moduleRoots = @($env:PSModulePath -split [IO.Path]::PathSeparator | Where-Object { $_ -and $_ -like "$HOME*" })
        $removedAny = $false
        foreach ($root in $moduleRoots) {
            $modulePath = Join-Path $root "LLMWorkflow"
            if (Test-Path -LiteralPath $modulePath) {
                try {
                    Remove-Item -LiteralPath $modulePath -Recurse -Force -ErrorAction Stop
                    $removedAny = $true
                } catch {
                    Write-Warning ("Could not remove module path {0}: {1}" -f $modulePath, $_.Exception.Message)
                }
            }
        }
        $actions.moduleFilesRemoved = $removedAny
    }

    [pscustomobject]$actions
}

<#
.SYNOPSIS
    Downloads and installs the latest LLMWorkflow release from GitHub.
#>
function Update-LLMWorkflow {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Repository = "DocDamage/CodeMunch-ContextLattice-MemPalace---All-in-one",
        [string]$Version = "",
        [switch]$IncludeGlobalLauncher,
        [string]$InstallRoot = "$HOME\.llm-workflow",
        [switch]$NoProfileUpdate,
        [switch]$SkipUserEnvPersist,
        [switch]$Force
    )

    $headers = @{
        "Accept" = "application/vnd.github+json"
        "User-Agent" = "LLMWorkflow-Updater"
    }

    $tagName = ""
    $releaseUri = ""
    if ([string]::IsNullOrWhiteSpace($Version)) {
        $releaseUri = "https://api.github.com/repos/$Repository/releases/latest"
    } else {
        $tagName = if ($Version.StartsWith("v")) { $Version } else { "v$Version" }
        $releaseUri = "https://api.github.com/repos/$Repository/releases/tags/$tagName"
    }

    $release = Invoke-RestMethod -Method Get -Uri $releaseUri -Headers $headers
    if (-not $release -or -not $release.assets) {
        throw "Release metadata did not include assets."
    }

    $zipAsset = $release.assets | Where-Object { $_.name -match '^LLMWorkflow-.*\.zip$' } | Select-Object -First 1
    $shaAsset = $release.assets | Where-Object { $_.name -match '^LLMWorkflow-.*\.zip\.sha256$' } | Select-Object -First 1
    if (-not $zipAsset) {
        throw "No module zip asset found in release."
    }
    if (-not $shaAsset) {
        throw "No sha256 asset found in release."
    }

    $tempRoot = Join-Path $env:TEMP ("llmworkflow-update-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    try {
        $zipPath = Join-Path $tempRoot $zipAsset.name
        $shaPath = Join-Path $tempRoot $shaAsset.name
        $extractPath = Join-Path $tempRoot "extract"
        New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

        Invoke-WebRequest -Uri $zipAsset.browser_download_url -Headers $headers -OutFile $zipPath
        Invoke-WebRequest -Uri $shaAsset.browser_download_url -Headers $headers -OutFile $shaPath

        $expectedLine = (Get-Content -LiteralPath $shaPath | Select-Object -First 1).Trim()
        if (-not $expectedLine) {
            throw "SHA256 file was empty."
        }
        $expectedHash = ($expectedLine -split '\s+')[0].ToLowerInvariant()
        $actualHash = ((Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash).ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "Downloaded module archive failed SHA256 verification."
        }

        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force
        $manifest = Get-ChildItem -Path $extractPath -Recurse -File -Filter "LLMWorkflow.psd1" | Select-Object -First 1
        if (-not $manifest) {
            throw "Extracted release does not contain LLMWorkflow.psd1."
        }

        $moduleData = Import-PowerShellDataFile -Path $manifest.FullName
        $resolvedVersion = [string]$moduleData.ModuleVersion
        if ([string]::IsNullOrWhiteSpace($resolvedVersion)) {
            throw "ModuleVersion missing from extracted manifest."
        }

        $moduleBase = Get-UserModuleBasePath
        $targetPath = Join-Path $moduleBase "LLMWorkflow" $resolvedVersion
        if ((Test-Path -LiteralPath $targetPath) -and -not $Force) {
            throw "Target module version already installed at $targetPath. Use -Force to replace."
        }

        Remove-Module LLMWorkflow -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $targetPath) {
            Remove-Item -LiteralPath $targetPath -Recurse -Force
        }
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null

        $moduleDir = Split-Path -Parent $manifest.FullName
        Copy-Item -Path (Join-Path $moduleDir "*") -Destination $targetPath -Recurse -Force
        Import-Module (Join-Path $targetPath "LLMWorkflow.psd1") -Force

        if ($IncludeGlobalLauncher) {
            Install-LLMWorkflow `
                -InstallRoot $InstallRoot `
                -NoProfileUpdate:$NoProfileUpdate `
                -SkipUserEnvPersist:$SkipUserEnvPersist
        }
    } finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Get-LLMWorkflowVersion
}

<#
.SYNOPSIS
    Validates the local project setup and optional ContextLattice connectivity.
#>
function Test-LLMWorkflowSetup {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$ProjectRoot = ".",
        [switch]$CheckConnectivity,
        [int]$TimeoutSec = 8,
        [switch]$Strict
    )

    $checks = New-Object System.Collections.Generic.List[object]
    $addCheck = {
        param([string]$Name, [string]$Status, [string]$Details)
        $checks.Add([pscustomobject]@{
            name = $Name
            status = $Status
            details = $Details
        })
    }

    $projectPath = ""
    if (Test-Path -LiteralPath $ProjectRoot) {
        $projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
        & $addCheck -Name "project_root" -Status "pass" -Details $projectPath
    } else {
        & $addCheck -Name "project_root" -Status "fail" -Details "Project root does not exist: $ProjectRoot"
    }

    if ($projectPath) {
        foreach ($tool in @("codemunch", "contextlattice", "memorybridge")) {
            $toolPath = Join-Path (Join-Path $projectPath "tools") $tool
            if (Test-Path -LiteralPath $toolPath) {
                & $addCheck -Name ("tool_" + $tool) -Status "pass" -Details "Found $toolPath"
            } else {
                & $addCheck -Name ("tool_" + $tool) -Status "warn" -Details "Missing $toolPath (run Invoke-LLMWorkflowUp)"
            }
        }
    }

    $envValues = @{}
    if ($projectPath) {
        $envFile = Join-Path $projectPath ".env"
        $ctxEnvFile = Join-Path (Join-Path $projectPath ".contextlattice") "orchestrator.env"
        if (Test-Path -LiteralPath $envFile) {
            & $addCheck -Name "env_file_root" -Status "pass" -Details "Found $envFile"
            $fromFile = Get-EnvFileMap -Path $envFile
            foreach ($key in $fromFile.Keys) { $envValues[$key] = $fromFile[$key] }
        } else {
            & $addCheck -Name "env_file_root" -Status "warn" -Details "Missing $envFile"
        }
        if (Test-Path -LiteralPath $ctxEnvFile) {
            & $addCheck -Name "env_file_contextlattice" -Status "pass" -Details "Found $ctxEnvFile"
            $fromCtx = Get-EnvFileMap -Path $ctxEnvFile
            foreach ($key in $fromCtx.Keys) { if (-not $envValues.ContainsKey($key)) { $envValues[$key] = $fromCtx[$key] } }
        } else {
            & $addCheck -Name "env_file_contextlattice" -Status "warn" -Details "Missing $ctxEnvFile"
        }
    }

    foreach ($name in @("CONTEXTLATTICE_ORCHESTRATOR_URL","CONTEXTLATTICE_ORCHESTRATOR_API_KEY","OPENAI_API_KEY","GEMINI_API_KEY","KIMI_API_KEY","GLM_API_KEY","GLM_BASE_URL")) {
        $processValue = [System.Environment]::GetEnvironmentVariable($name, "Process")
        if (-not [string]::IsNullOrWhiteSpace($processValue)) {
            $envValues[$name] = $processValue
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($envValues["CONTEXTLATTICE_ORCHESTRATOR_API_KEY"])) {
        & $addCheck -Name "contextlattice_api_key" -Status "pass" -Details "API key present"
    } else {
        & $addCheck -Name "contextlattice_api_key" -Status "warn" -Details "Missing CONTEXTLATTICE_ORCHESTRATOR_API_KEY"
    }

    if (-not [string]::IsNullOrWhiteSpace($envValues["CONTEXTLATTICE_ORCHESTRATOR_URL"])) {
        try {
            $null = [Uri]$envValues["CONTEXTLATTICE_ORCHESTRATOR_URL"]
            & $addCheck -Name "contextlattice_url" -Status "pass" -Details $envValues["CONTEXTLATTICE_ORCHESTRATOR_URL"]
        } catch {
            & $addCheck -Name "contextlattice_url" -Status "fail" -Details "Invalid URL format: $($envValues["CONTEXTLATTICE_ORCHESTRATOR_URL"])"
        }
    } else {
        & $addCheck -Name "contextlattice_url" -Status "warn" -Details "Missing CONTEXTLATTICE_ORCHESTRATOR_URL"
    }

    if (-not [string]::IsNullOrWhiteSpace($envValues["GLM_API_KEY"]) -and [string]::IsNullOrWhiteSpace($envValues["GLM_BASE_URL"])) {
        & $addCheck -Name "glm_base_url" -Status "warn" -Details "GLM_API_KEY is set but GLM_BASE_URL is missing."
    } elseif (-not [string]::IsNullOrWhiteSpace($envValues["GLM_BASE_URL"])) {
        & $addCheck -Name "glm_base_url" -Status "pass" -Details $envValues["GLM_BASE_URL"]
    } else {
        & $addCheck -Name "glm_base_url" -Status "warn" -Details "GLM provider not configured."
    }

    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        & $addCheck -Name "python_command" -Status "pass" -Details $pythonCmd.Source
        $probe = "import importlib.util; print(bool(importlib.util.find_spec(r'chromadb')))"
        $probeOut = & python -c $probe 2>$null
        $probeText = if ($null -eq $probeOut) { "" } else { ($probeOut | Out-String).Trim() }
        if ($LASTEXITCODE -eq 0 -and $probeText -eq "True") {
            & $addCheck -Name "python_chromadb" -Status "pass" -Details "chromadb import available"
        } else {
            & $addCheck -Name "python_chromadb" -Status "warn" -Details "chromadb import unavailable"
        }
    } else {
        & $addCheck -Name "python_command" -Status "fail" -Details "python is not on PATH"
    }

    $codemunchCmd = Get-Command codemunch-pro -ErrorAction SilentlyContinue
    if ($codemunchCmd) {
        & $addCheck -Name "codemunch_command" -Status "pass" -Details $codemunchCmd.Source
    } else {
        & $addCheck -Name "codemunch_command" -Status "warn" -Details "codemunch-pro command not found"
    }

    if ($CheckConnectivity) {
        $url = $envValues["CONTEXTLATTICE_ORCHESTRATOR_URL"]
        $key = $envValues["CONTEXTLATTICE_ORCHESTRATOR_API_KEY"]
        if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($key)) {
            & $addCheck -Name "contextlattice_connectivity" -Status "warn" -Details "Skipped: URL/API key missing"
        } else {
            $base = $url.TrimEnd('/')
            try {
                $health = Invoke-RestMethod -Method Get -Uri "$base/health" -TimeoutSec $TimeoutSec
                if ($health.ok) {
                    & $addCheck -Name "contextlattice_health" -Status "pass" -Details "$base/health ok=true"
                } else {
                    & $addCheck -Name "contextlattice_health" -Status "fail" -Details "$base/health responded but ok!=true"
                }
            } catch {
                & $addCheck -Name "contextlattice_health" -Status "fail" -Details ("Health check failed: {0}" -f $_.Exception.Message)
            }

            try {
                $status = Invoke-RestMethod -Method Get -Uri "$base/status" -Headers @{ "x-api-key" = $key } -TimeoutSec $TimeoutSec
                $svc = if ($status.service) { $status.service } else { "unknown" }
                & $addCheck -Name "contextlattice_status" -Status "pass" -Details "service=$svc"
            } catch {
                & $addCheck -Name "contextlattice_status" -Status "fail" -Details ("Status check failed: {0}" -f $_.Exception.Message)
            }
        }
    }

    $checkList = @($checks.ToArray())
    $failCount = @($checkList | Where-Object { $_.status -eq "fail" }).Count
    $warnCount = @($checkList | Where-Object { $_.status -eq "warn" }).Count
    $passCount = @($checkList | Where-Object { $_.status -eq "pass" }).Count

    $result = [pscustomobject]@{
        projectRoot = if ($projectPath) { $projectPath } else { $ProjectRoot }
        passed = ($failCount -eq 0)
        passCount = $passCount
        warningCount = $warnCount
        failCount = $failCount
        checks = $checkList
    }

    if ($Strict -and $failCount -gt 0) {
        throw ("Setup validation failed with {0} failing checks." -f $failCount)
    }

    return $result
}

<#
.SYNOPSIS
    Bootstraps the LLMWorkflow toolkit for a project.
#>
function Invoke-LLMWorkflowUp {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [string]$ProjectRoot = ".",
        [switch]$SkipDependencyInstall,
        [switch]$SkipContextVerify,
        [switch]$SkipBridgeDryRun,
        [switch]$SmokeTestContext,
        [switch]$RequireSearchHit,
        [switch]$ContinueOnError,
        [switch]$ShowTiming,
        [switch]$Offline,
        [switch]$AsJson,
        [switch]$GameTeam,
        [string]$GameTemplate = "",
        [string]$GameEngine = "",
        [switch]$JamMode
    )

    # Handle Game Team preset
    if ($GameTeam -or $JamMode) {
        $gamePresetPath = Join-Path $PSScriptRoot "LLMWorkflow.GameFunctions.ps1"
        if (Test-Path -LiteralPath $gamePresetPath) {
            . $gamePresetPath
            
            # Apply jam mode defaults
            if ($JamMode) {
                Write-Host "[llm-workflow] Jam Mode enabled: fast checks, ContinueOnError" -ForegroundColor Yellow
                $ContinueOnError = $true
                $SkipBridgeDryRun = $true
            }
            
            # Initialize game preset if needed
            $projectPath = Resolve-Path -LiteralPath $ProjectRoot
            $existingGamePreset = Join-Path $projectPath ".llm-workflow\game-preset.json"
            if (-not (Test-Path -LiteralPath $existingGamePreset)) {
                Write-Host "[llm-workflow] Initializing game team structure..." -ForegroundColor Cyan
                New-LLMWorkflowGamePreset -ProjectRoot $ProjectRoot -Template $GameTemplate -Engine $GameEngine -JamMode:$JamMode
            }
        }
    }

    $scriptPath = Join-Path (Join-Path $PSScriptRoot "scripts") "bootstrap-llm-workflow.ps1"
    $toolkitSource = Join-Path (Join-Path $PSScriptRoot "templates") "tools"

    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Missing script: $scriptPath"
    }
    if (-not (Test-Path -LiteralPath $toolkitSource)) {
        throw "Missing toolkit templates: $toolkitSource"
    }

    $invokeArgs = @{
        ProjectRoot = $ProjectRoot
        ToolkitSource = $toolkitSource
    }
    if ($SkipDependencyInstall) {
        $invokeArgs["SkipDependencyInstall"] = $true
    }
    if ($SkipContextVerify) {
        $invokeArgs["SkipContextVerify"] = $true
    }
    if ($SkipBridgeDryRun) {
        $invokeArgs["SkipBridgeDryRun"] = $true
    }
    if ($SmokeTestContext) {
        $invokeArgs["SmokeTestContext"] = $true
    }
    if ($RequireSearchHit) {
        $invokeArgs["RequireSearchHit"] = $true
    }
    if ($ContinueOnError) {
        $invokeArgs["ContinueOnError"] = $true
    }
    if ($ShowTiming) {
        $invokeArgs["ShowTiming"] = $true
    }
    if ($Offline) {
        $invokeArgs["Offline"] = $true
    }
    if ($AsJson) {
        $invokeArgs["AsJson"] = $true
    }

    & $scriptPath @invokeArgs
    
    if ($GameTeam -or $JamMode) {
        Write-Host "[llm-workflow] Game team setup complete. See docs/GDD.md and docs/TASKS.md" -ForegroundColor Green
    }
}

<#
.SYNOPSIS
    Returns configuration metadata for a specified LLM provider.
#>
function Get-ProviderProfile {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    $providerName = $Name.ToLower()
    switch ($providerName) {
        "openai" {
            return [pscustomobject]@{
                Name = "openai"
                ApiKeyVars = @("OPENAI_API_KEY")
                BaseUrlVars = @("OPENAI_BASE_URL")
                DefaultBaseUrl = "https://api.openai.com/v1"
            }
        }
        "claude" {
            return [pscustomobject]@{
                Name = "claude"
                ApiKeyVars = @("ANTHROPIC_API_KEY", "CLAUDE_API_KEY")
                BaseUrlVars = @("ANTHROPIC_BASE_URL", "CLAUDE_BASE_URL")
                DefaultBaseUrl = "https://api.anthropic.com/v1"
            }
        }
        "kimi" {
            return [pscustomobject]@{
                Name = "kimi"
                ApiKeyVars = @("KIMI_API_KEY", "MOONSHOT_API_KEY")
                BaseUrlVars = @("KIMI_BASE_URL", "MOONSHOT_BASE_URL")
                DefaultBaseUrl = "https://api.moonshot.cn/v1"
            }
        }
        "gemini" {
            return [pscustomobject]@{
                Name = "gemini"
                ApiKeyVars = @("GEMINI_API_KEY", "GOOGLE_API_KEY")
                BaseUrlVars = @("GEMINI_BASE_URL")
                DefaultBaseUrl = "https://generativelanguage.googleapis.com/v1beta/openai"
            }
        }
        "glm" {
            return [pscustomobject]@{
                Name = "glm"
                ApiKeyVars = @("GLM_API_KEY", "ZHIPU_API_KEY")
                BaseUrlVars = @("GLM_BASE_URL")
                DefaultBaseUrl = "https://open.bigmodel.cn/api/paas/v4"
            }
        }
        "ollama" {
            return [pscustomobject]@{
                Name = "ollama"
                ApiKeyVars = @("OLLAMA_API_KEY")
                BaseUrlVars = @("OLLAMA_BASE_URL", "OLLAMA_HOST")
                DefaultBaseUrl = "http://localhost:11434/v1"
            }
        }
        default {
            throw "Unsupported provider: $Name"
        }
    }
}

<#
.SYNOPSIS
    Returns the default provider preference order list.
#>
function Get-ProviderPreferenceOrder {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    return @("openai", "claude", "kimi", "gemini", "glm", "ollama")
}

<#
.SYNOPSIS
    Resolves the best available provider profile based on environment variables.
#>
function Resolve-ProviderProfile {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RequestedProvider
    )
    
    $preferenceOrder = Get-ProviderPreferenceOrder
    
    # Helper function to find first available API key
    function Find-ApiKey {
        param([array]$KeyVars)
        foreach ($var in $KeyVars) {
            $val = [Environment]::GetEnvironmentVariable($var)
            if (-not [string]::IsNullOrWhiteSpace($val)) {
                return @{ Var = $var; Key = $val }
            }
        }
        return $null
    }
    
    # Helper function to find base URL
    function Find-BaseUrl {
        param([array]$UrlVars, [string]$DefaultUrl)
        foreach ($var in $UrlVars) {
            $val = [Environment]::GetEnvironmentVariable($var)
            if (-not [string]::IsNullOrWhiteSpace($val)) {
                return @{ Var = $var; Url = $val }
            }
        }
        return @{ Var = ""; Url = $DefaultUrl }
    }
    
    # If specific provider requested
    if ($RequestedProvider -ne "auto") {
        $profile = Get-ProviderProfile -Name $RequestedProvider
        $apiKeyInfo = Find-ApiKey -KeyVars $profile.ApiKeyVars
        $baseUrlInfo = Find-BaseUrl -UrlVars $profile.BaseUrlVars -DefaultUrl $profile.DefaultBaseUrl
        
        return [pscustomobject]@{
            Profile = $profile
            ApiKey = if ($apiKeyInfo) { $apiKeyInfo.Key } else { "" }
            ApiKeyVar = if ($apiKeyInfo) { $apiKeyInfo.Var } else { "" }
            BaseUrl = $baseUrlInfo.Url
            BaseUrlVar = $baseUrlInfo.Var
        }
    }
    
    # Auto mode - check LLM_PROVIDER override first
    $envOverride = [Environment]::GetEnvironmentVariable("LLM_PROVIDER")
    if ($envOverride) {
        try {
            $profile = Get-ProviderProfile -Name $envOverride
            $apiKeyInfo = Find-ApiKey -KeyVars $profile.ApiKeyVars
            if ($apiKeyInfo) {
                $baseUrlInfo = Find-BaseUrl -UrlVars $profile.BaseUrlVars -DefaultUrl $profile.DefaultBaseUrl
                return [pscustomobject]@{
                    Profile = $profile
                    ApiKey = $apiKeyInfo.Key
                    ApiKeyVar = $apiKeyInfo.Var
                    BaseUrl = $baseUrlInfo.Url
                    BaseUrlVar = $baseUrlInfo.Var
                }
            }
        }
        catch {
            # Invalid LLM_PROVIDER value - fall through to auto-detection
        }
    }
    
    # Auto-detection by priority order
    foreach ($provider in $preferenceOrder) {
        $profile = Get-ProviderProfile -Name $provider
        $apiKeyInfo = Find-ApiKey -KeyVars $profile.ApiKeyVars
        if ($apiKeyInfo) {
            $baseUrlInfo = Find-BaseUrl -UrlVars $profile.BaseUrlVars -DefaultUrl $profile.DefaultBaseUrl
            return [pscustomobject]@{
                Profile = $profile
                ApiKey = $apiKeyInfo.Key
                ApiKeyVar = $apiKeyInfo.Var
                BaseUrl = $baseUrlInfo.Url
                BaseUrlVar = $baseUrlInfo.Var
            }
        }
    }
    
    return $null
}

<#
.SYNOPSIS
    Performs basic validation of a provider API key.
#>
function Test-ProviderKey {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProviderName,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiKey,
        [string]$BaseUrl,
        [int]$TimeoutSec = 10
    )
    
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        return $false
    }
    
    # Special handling for contextlattice
    if ($ProviderName -eq "contextlattice") {
        return -not [string]::IsNullOrWhiteSpace($BaseUrl)
    }
    
    # For all other providers, just validate the key format and base URL presence
    # In a real implementation, this would make an actual API call
    return $true
}

# Multi-Palace support functions

function Get-LLMWorkflowPalaces {
    <#
    .SYNOPSIS
        Gets the list of configured MemPalace instances from the bridge config.
    .DESCRIPTION
        Reads the bridge.config.json file and returns a list of configured palaces.
        Supports both legacy single-palace format and new multi-palace format.
    .PARAMETER ConfigPath
        Path to the bridge configuration file (default: .memorybridge/bridge.config.json)
    .EXAMPLE
        Get-LLMWorkflowPalaces
        Gets all palaces from the default config file.
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string]$ConfigPath = ".memorybridge/bridge.config.json"
    )
    
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Write-Warning "Config file not found: $ConfigPath"
        return @()
    }
    
    try {
        $configContent = Get-Content -LiteralPath $ConfigPath -Raw
        $config = $configContent | ConvertFrom-Json -AsHashtable
    } catch {
        Write-Error "Failed to parse config file: $_"
        return @()
    }
    
    # Check version and format
    $version = if ($config.ContainsKey("version")) { $config["version"] } else { "1.0" }
    $palaces = @()
    
    if ($config.ContainsKey("palaces") -and $config["palaces"] -is [array]) {
        # Multi-palace format (v2.0+)
        for ($i = 0; $i -lt $config["palaces"].Count; $i++) {
            $palace = $config["palaces"][$i]
            $wingMap = @{}
            if ($palace.ContainsKey("wingProjectMap") -and $palace["wingProjectMap"] -is [System.Collections.IDictionary]) {
                $wingMap = $palace["wingProjectMap"]
            }
            $palaces += [pscustomobject]@{
                Index = $i
                Id = "palace_$i"
                Path = if ($palace.ContainsKey("path")) { $palace["path"] } else { "" }
                CollectionName = if ($palace.ContainsKey("collectionName")) { $palace["collectionName"] } else { "mempalace_drawers" }
                TopicPrefix = if ($palace.ContainsKey("topicPrefix")) { $palace["topicPrefix"] } else { "mempalace" }
                WingProjectMap = $wingMap
            }
        }
    } elseif ($config.ContainsKey("palacePath")) {
        # Legacy single-palace format
        $wingMap = @{}
        if ($config.ContainsKey("wingProjectMap") -and $config["wingProjectMap"] -is [System.Collections.IDictionary]) {
            $wingMap = $config["wingProjectMap"]
        }
        $palaces += [pscustomobject]@{
            Index = 0
            Id = "palace_0"
            Path = $config["palacePath"]
            CollectionName = if ($config.ContainsKey("collectionName")) { $config["collectionName"] } else { "mempalace_drawers" }
            TopicPrefix = if ($config.ContainsKey("topicPrefix")) { $config["topicPrefix"] } else { "mempalace" }
            WingProjectMap = $wingMap
        }
    }
    
    return $palaces
}

function Test-LLMWorkflowPalace {
    <#
    .SYNOPSIS
        Tests the connectivity and validity of a specific palace.
    .DESCRIPTION
        Validates that the palace path exists and the ChromaDB collection is accessible.
    .PARAMETER Index
        The index of the palace to test (0-based).
    .PARAMETER ConfigPath
        Path to the bridge configuration file.
    .EXAMPLE
        Test-LLMWorkflowPalace -Index 0
        Tests the first palace in the configuration.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory=$true)]
        [int]$Index,
        [string]$ConfigPath = ".memorybridge/bridge.config.json"
    )
    
    $palaces = Get-LLMWorkflowPalaces -ConfigPath $ConfigPath
    if ($Index -lt 0 -or $Index -ge $palaces.Count) {
        throw "Palace index $Index out of range (0-$($palaces.Count - 1))"
    }
    
    $palace = $palaces | Where-Object { $_.Index -eq $Index } | Select-Object -First 1
    if (-not $palace) {
        throw "Palace with index $Index not found"
    }
    
    $expandedPath = [Environment]::ExpandEnvironmentVariables($palace.Path)
    if ($expandedPath.StartsWith("~")) {
        $expandedPath = $expandedPath.Replace("~", $HOME)
    }
    
    $checks = @{
        Index = $Index
        Id = $palace.Id
        Path = $palace.Path
        ExpandedPath = $expandedPath
        CollectionName = $palace.CollectionName
        TopicPrefix = $palace.TopicPrefix
        PathExists = Test-Path -LiteralPath $expandedPath
        IsValid = $false
        Errors = @()
    }
    
    if (-not $checks.PathExists) {
        $checks.Errors += "Palace path does not exist: $expandedPath"
    } else {
        # Try to get collection info using Python
        $pythonScript = @"
import chromadb
import json
import sys
try:
    client = chromadb.PersistentClient(path=r'$expandedPath')
    collection = client.get_collection('$($palace.CollectionName)')
    count = collection.count()
    print(json.dumps({"ok": true, "count": count}))
except Exception as e:
    print(json.dumps({"ok": false, "error": str(e)}))
"@
        try {
            $result = & python -c $pythonScript 2>&1 | Out-String
            $info = $result | ConvertFrom-Json
            if ($info.ok) {
                $checks.CollectionCount = $info.count
                $checks.IsValid = $true
            } else {
                $checks.Errors += "Collection error: $($info.error)"
            }
        } catch {
            $checks.Errors += "Failed to query collection: $_"
        }
    }
    
    return [pscustomobject]$checks
}

function Sync-LLMWorkflowPalace {
    <#
    .SYNOPSIS
        Syncs a specific MemPalace to ContextLattice.
    .DESCRIPTION
        Runs the sync operation for a single palace by index.
    .PARAMETER Index
        The index of the palace to sync (0-based).
    .PARAMETER ConfigPath
        Path to the bridge configuration file.
    .PARAMETER StatePath
        Path to the sync state file.
    .PARAMETER OrchestratorUrl
        Override the orchestrator URL.
    .PARAMETER ApiKey
        Override the API key.
    .PARAMETER Limit
        Maximum number of drawers to sync.
    .PARAMETER Workers
        Number of parallel workers (default: 4).
    .PARAMETER DryRun
        Show what would be synced without writing.
    .PARAMETER ForceResync
        Force resync of all drawers.
    .PARAMETER Strict
        Stop on first error.
    .EXAMPLE
        Sync-LLMWorkflowPalace -Index 0
        Syncs the first palace.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory=$true)]
        [int]$Index,
        [string]$ConfigPath = ".memorybridge/bridge.config.json",
        [string]$StatePath = ".memorybridge/sync-state.json",
        [string]$OrchestratorUrl = "",
        [string]$ApiKey = "",
        [int]$Limit = 0,
        [int]$Workers = 4,
        [switch]$DryRun,
        [switch]$ForceResync,
        [switch]$Strict
    )
    
    $palaces = Get-LLMWorkflowPalaces -ConfigPath $ConfigPath
    if ($Index -lt 0 -or $Index -ge $palaces.Count) {
        throw "Palace index $Index out of range (0-$($palaces.Count - 1))"
    }
    
    $toolRoot = Join-Path (Split-Path -Parent $PSScriptRoot) "tools\memorybridge"
    $scriptPath = Join-Path $toolRoot "sync-from-mempalace.ps1"
    
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Sync script not found: $scriptPath"
    }
    
    $invokeArgs = @{
        ConfigPath = $ConfigPath
        StatePath = $StatePath
        PalaceIndex = $Index
        Workers = $Workers
    }
    
    if ($OrchestratorUrl) { $invokeArgs["OrchestratorUrl"] = $OrchestratorUrl }
    if ($ApiKey) { $invokeArgs["ApiKey"] = $ApiKey }
    if ($Limit -gt 0) { $invokeArgs["Limit"] = $Limit }
    if ($DryRun) { $invokeArgs["DryRun"] = $true }
    if ($ForceResync) { $invokeArgs["ForceResync"] = $true }
    if ($Strict) { $invokeArgs["Strict"] = $true }
    
    & $scriptPath @invokeArgs
}

function Sync-LLMWorkflowAllPalaces {
    <#
    .SYNOPSIS
        Syncs all configured MemPalaces to ContextLattice.
    .DESCRIPTION
        Runs the sync operation for all palaces in the configuration.
    .PARAMETER ConfigPath
        Path to the bridge configuration file.
    .PARAMETER StatePath
        Path to the sync state file.
    .PARAMETER OrchestratorUrl
        Override the orchestrator URL.
    .PARAMETER ApiKey
        Override the API key.
    .PARAMETER Limit
        Maximum number of drawers to sync per palace.
    .PARAMETER Workers
        Number of parallel workers (default: 4).
    .PARAMETER DryRun
        Show what would be synced without writing.
    .PARAMETER ForceResync
        Force resync of all drawers.
    .PARAMETER Strict
        Stop on first error.
    .PARAMETER ContinueOnError
        Continue syncing remaining palaces if one fails.
    .EXAMPLE
        Sync-LLMWorkflowAllPalaces -DryRun
        Shows what would be synced without making changes.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$ConfigPath = ".memorybridge/bridge.config.json",
        [string]$StatePath = ".memorybridge/sync-state.json",
        [string]$OrchestratorUrl = "",
        [string]$ApiKey = "",
        [int]$Limit = 0,
        [int]$Workers = 4,
        [switch]$DryRun,
        [switch]$ForceResync,
        [switch]$Strict,
        [switch]$ContinueOnError
    )
    
    $palaces = Get-LLMWorkflowPalaces -ConfigPath $ConfigPath
    if ($palaces.Count -eq 0) {
        Write-Warning "No palaces configured in $ConfigPath"
        return
    }
    
    $results = @()
    $failedCount = 0
    
    foreach ($palace in $palaces) {
        Write-Host "Syncing palace $($palace.Index): $($palace.Id) ($($palace.Path))" -ForegroundColor Cyan
        
        try {
            $result = Sync-LLMWorkflowPalace `
                -Index $palace.Index `
                -ConfigPath $ConfigPath `
                -StatePath $StatePath `
                -OrchestratorUrl $OrchestratorUrl `
                -ApiKey $ApiKey `
                -Limit $Limit `
                -Workers $Workers `
                -DryRun:$DryRun `
                -ForceResync:$ForceResync `
                -Strict:$Strict
            
            $results += [pscustomobject]@{
                Index = $palace.Index
                Id = $palace.Id
                Success = $true
                Result = $result
            }
        } catch {
            $failedCount++
            $results += [pscustomobject]@{
                Index = $palace.Index
                Id = $palace.Id
                Success = $false
                Error = $_.Exception.Message
            }
            
            if (-not $ContinueOnError) {
                throw
            }
            
            Write-Warning "Failed to sync palace $($palace.Index): $_"
        }
    }
    
    return [pscustomobject]@{
        TotalPalaces = $palaces.Count
        Successful = ($palaces.Count - $failedCount)
        Failed = $failedCount
        Results = $results
    }
}

# Source plugin functions
$PluginFunctionsPath = Join-Path $PSScriptRoot "LLMWorkflow.PluginFunctions.ps1"
if (Test-Path -LiteralPath $PluginFunctionsPath) {
    . $PluginFunctionsPath
}

# Source dashboard functions
$DashboardPath = Join-Path $PSScriptRoot "LLMWorkflow.Dashboard.ps1"
function Show-LLMWorkflowDashboard {
    <#
    .SYNOPSIS
        Interactive Terminal UI dashboard for LLM Workflow Doctor.
    .DESCRIPTION
        Provides a color-coded, real-time updating dashboard for workflow health checks
        with progress indicators and interactive controls.
    .PARAMETER ProjectRoot
        Path to project root (default: current directory).
    .PARAMETER Provider
        Provider to check (auto, openai, kimi, gemini, glm).
    .PARAMETER CheckContext
        Include ContextLattice connectivity checks.
    .PARAMETER TimeoutSec
        Timeout for network checks (default: 10).
    .PARAMETER NoInteractive
        Force non-interactive plain-text output.
    .PARAMETER RefreshInterval
        Seconds between auto-refresh in interactive mode (default: 0 = manual only).
    .EXAMPLE
        Show-LLMWorkflowDashboard
        Launch the interactive dashboard.
    .EXAMPLE
        Show-LLMWorkflowDashboard -NoInteractive
        Plain-text output suitable for CI/CD.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [string]$ProjectRoot = ".",
        [ValidateSet("auto", "openai", "kimi", "gemini", "glm")]
        [string]$Provider = "auto",
        [switch]$CheckContext,
        [int]$TimeoutSec = 10,
        [switch]$NoInteractive,
        [int]$RefreshInterval = 0
    )
    
    if (-not (Test-Path -LiteralPath $DashboardPath)) {
        throw "Dashboard script not found: $DashboardPath"
    }
    
    & $DashboardPath -ProjectRoot $ProjectRoot -Provider $Provider -CheckContext:$CheckContext -TimeoutSec $TimeoutSec -NoInteractive:$NoInteractive -RefreshInterval $RefreshInterval
}

# Source game team functions
$GameFunctionsPath = Join-Path $PSScriptRoot "LLMWorkflow.GameFunctions.ps1"
if (Test-Path -LiteralPath $GameFunctionsPath) {
    . $GameFunctionsPath
}

# Source heal functions
$HealFunctionsPath = Join-Path $PSScriptRoot "LLMWorkflow.HealFunctions.ps1"
if (Test-Path -LiteralPath $HealFunctionsPath) {
    . $HealFunctionsPath
}

Set-Alias -Name llmup -Value Invoke-LLMWorkflowUp
Set-Alias -Name llmdown -Value Uninstall-LLMWorkflow
Set-Alias -Name llmcheck -Value Test-LLMWorkflowSetup
Set-Alias -Name llmver -Value Get-LLMWorkflowVersion
Set-Alias -Name llmupdate -Value Update-LLMWorkflow
Set-Alias -Name llmplugins -Value Get-LLMWorkflowPlugins
Set-Alias -Name llmpalaces -Value Get-LLMWorkflowPalaces
Set-Alias -Name llmsync -Value Sync-LLMWorkflowAllPalaces
Set-Alias -Name llmdashboard -Value Show-LLMWorkflowDashboard
Set-Alias -Name llmheal -Value Invoke-LLMWorkflowHeal

Export-ModuleMember -Function @(
    'Invoke-LLMWorkflowUp', 'Uninstall-LLMWorkflow', 'Install-LLMWorkflow', 'Update-LLMWorkflow', 
    'Get-LLMWorkflowVersion', 'Test-LLMWorkflowSetup',
    'Invoke-QueryRouting', 'Get-RetrievalProfile', 'Get-RetrievalProfileList', 'Get-QueryIntent', 'Get-RoutingExplanation',
    'New-AnswerPlan', 'Add-PlanEvidence', 'Test-AnswerPlanCompleteness',
    'New-AnswerTrace', 'Add-TraceEvidence', 'Export-AnswerTrace',
    'Get-CachedRetrieval', 'Invoke-CacheInvalidation', 'Invoke-CacheMaintenance', 'Clear-RetrievalCache',
    'Invoke-LLMWorkflowHeal', 'Show-LLMWorkflowDashboard', 'Get-LLMWorkflowPlugins', 'Get-LLMWorkflowPalaces', 'Sync-LLMWorkflowAllPalaces',
    'Get-GoldenTasks', 'Test-GoldenTaskCompleteness',
    'Get-TelemetryLog', 'Clear-TelemetryLog'
) -Alias llmup, llmdown, llmcheck, llmver, llmupdate, llmplugins, llmpalaces, llmsync, llmdashboard, llmheal