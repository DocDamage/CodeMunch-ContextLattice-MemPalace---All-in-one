Set-StrictMode -Version Latest

function Get-UserModuleBasePath {
    $moduleRoots = @($env:PSModulePath -split ';' | Where-Object { $_ -and $_ -like "$HOME*" })
    if ($moduleRoots.Count -gt 0) {
        return $moduleRoots[0]
    }
    return (Join-Path $HOME "Documents\WindowsPowerShell\Modules")
}

function Get-EnvFileMap {
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
    return [regex]::Replace($Content, $pattern, "", [System.Text.RegularExpressions.RegexOptions]::Singleline)
}

function Get-LLMWorkflowVersion {
    [CmdletBinding()]
    param()

    $manifestPath = Join-Path $PSScriptRoot "LLMWorkflow.psd1"
    $manifest = Import-PowerShellDataFile -Path $manifestPath
    $available = @(Get-Module -ListAvailable -Name LLMWorkflow | Sort-Object Version -Descending)
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

function Install-LLMWorkflow {
    [CmdletBinding()]
    param(
        [string]$InstallRoot = "$HOME\.llm-workflow",
        [switch]$NoProfileUpdate,
        [string]$ProfilePath = $PROFILE,
        [switch]$SkipUserEnvPersist
    )

    $scriptPath = Join-Path $PSScriptRoot "scripts\install-global-llm-workflow.ps1"
    $toolkitSource = Join-Path $PSScriptRoot "templates\tools"

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

function Uninstall-LLMWorkflow {
    [CmdletBinding()]
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
        $moduleRoots = @($env:PSModulePath -split ';' | Where-Object { $_ -and $_ -like "$HOME*" })
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

function Update-LLMWorkflow {
    [CmdletBinding()]
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
        $targetPath = Join-Path $moduleBase ("LLMWorkflow\" + $resolvedVersion)
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

function Test-LLMWorkflowSetup {
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = ".",
        [switch]$CheckConnectivity,
        [int]$TimeoutSec = 8,
        [switch]$Strict
    )

    $checks = New-Object System.Collections.Generic.List[object]
    function Add-Check {
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
        Add-Check -Name "project_root" -Status "pass" -Details $projectPath
    } else {
        Add-Check -Name "project_root" -Status "fail" -Details "Project root does not exist: $ProjectRoot"
    }

    if ($projectPath) {
        foreach ($tool in @("codemunch", "contextlattice", "memorybridge")) {
            $toolPath = Join-Path $projectPath ("tools\" + $tool)
            if (Test-Path -LiteralPath $toolPath) {
                Add-Check -Name ("tool_" + $tool) -Status "pass" -Details "Found $toolPath"
            } else {
                Add-Check -Name ("tool_" + $tool) -Status "warn" -Details "Missing $toolPath (run Invoke-LLMWorkflowUp)"
            }
        }
    }

    $envValues = @{}
    if ($projectPath) {
        $envFile = Join-Path $projectPath ".env"
        $ctxEnvFile = Join-Path $projectPath ".contextlattice\orchestrator.env"
        if (Test-Path -LiteralPath $envFile) {
            Add-Check -Name "env_file_root" -Status "pass" -Details "Found $envFile"
            $fromFile = Get-EnvFileMap -Path $envFile
            foreach ($key in $fromFile.Keys) { $envValues[$key] = $fromFile[$key] }
        } else {
            Add-Check -Name "env_file_root" -Status "warn" -Details "Missing $envFile"
        }
        if (Test-Path -LiteralPath $ctxEnvFile) {
            Add-Check -Name "env_file_contextlattice" -Status "pass" -Details "Found $ctxEnvFile"
            $fromCtx = Get-EnvFileMap -Path $ctxEnvFile
            foreach ($key in $fromCtx.Keys) { if (-not $envValues.ContainsKey($key)) { $envValues[$key] = $fromCtx[$key] } }
        } else {
            Add-Check -Name "env_file_contextlattice" -Status "warn" -Details "Missing $ctxEnvFile"
        }
    }

    foreach ($name in @("CONTEXTLATTICE_ORCHESTRATOR_URL","CONTEXTLATTICE_ORCHESTRATOR_API_KEY","OPENAI_API_KEY","GEMINI_API_KEY","KIMI_API_KEY","GLM_API_KEY","GLM_BASE_URL")) {
        $processValue = [System.Environment]::GetEnvironmentVariable($name, "Process")
        if (-not [string]::IsNullOrWhiteSpace($processValue)) {
            $envValues[$name] = $processValue
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($envValues["CONTEXTLATTICE_ORCHESTRATOR_API_KEY"])) {
        Add-Check -Name "contextlattice_api_key" -Status "pass" -Details "API key present"
    } else {
        Add-Check -Name "contextlattice_api_key" -Status "warn" -Details "Missing CONTEXTLATTICE_ORCHESTRATOR_API_KEY"
    }

    if (-not [string]::IsNullOrWhiteSpace($envValues["CONTEXTLATTICE_ORCHESTRATOR_URL"])) {
        try {
            $null = [Uri]$envValues["CONTEXTLATTICE_ORCHESTRATOR_URL"]
            Add-Check -Name "contextlattice_url" -Status "pass" -Details $envValues["CONTEXTLATTICE_ORCHESTRATOR_URL"]
        } catch {
            Add-Check -Name "contextlattice_url" -Status "fail" -Details "Invalid URL format: $($envValues["CONTEXTLATTICE_ORCHESTRATOR_URL"])"
        }
    } else {
        Add-Check -Name "contextlattice_url" -Status "warn" -Details "Missing CONTEXTLATTICE_ORCHESTRATOR_URL"
    }

    if (-not [string]::IsNullOrWhiteSpace($envValues["GLM_API_KEY"]) -and [string]::IsNullOrWhiteSpace($envValues["GLM_BASE_URL"])) {
        Add-Check -Name "glm_base_url" -Status "warn" -Details "GLM_API_KEY is set but GLM_BASE_URL is missing."
    } elseif (-not [string]::IsNullOrWhiteSpace($envValues["GLM_BASE_URL"])) {
        Add-Check -Name "glm_base_url" -Status "pass" -Details $envValues["GLM_BASE_URL"]
    } else {
        Add-Check -Name "glm_base_url" -Status "warn" -Details "GLM provider not configured."
    }

    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        Add-Check -Name "python_command" -Status "pass" -Details $pythonCmd.Source
        $probe = "import importlib.util; print(bool(importlib.util.find_spec(r'chromadb')))"
        $probeOut = & python -c $probe 2>$null
        $probeText = if ($null -eq $probeOut) { "" } else { ($probeOut | Out-String).Trim() }
        if ($LASTEXITCODE -eq 0 -and $probeText -eq "True") {
            Add-Check -Name "python_chromadb" -Status "pass" -Details "chromadb import available"
        } else {
            Add-Check -Name "python_chromadb" -Status "warn" -Details "chromadb import unavailable"
        }
    } else {
        Add-Check -Name "python_command" -Status "fail" -Details "python is not on PATH"
    }

    $codemunchCmd = Get-Command codemunch-pro -ErrorAction SilentlyContinue
    if ($codemunchCmd) {
        Add-Check -Name "codemunch_command" -Status "pass" -Details $codemunchCmd.Source
    } else {
        Add-Check -Name "codemunch_command" -Status "warn" -Details "codemunch-pro command not found"
    }

    if ($CheckConnectivity) {
        $url = $envValues["CONTEXTLATTICE_ORCHESTRATOR_URL"]
        $key = $envValues["CONTEXTLATTICE_ORCHESTRATOR_API_KEY"]
        if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($key)) {
            Add-Check -Name "contextlattice_connectivity" -Status "warn" -Details "Skipped: URL/API key missing"
        } else {
            $base = $url.TrimEnd('/')
            try {
                $health = Invoke-RestMethod -Method Get -Uri "$base/health" -TimeoutSec $TimeoutSec
                if ($health.ok) {
                    Add-Check -Name "contextlattice_health" -Status "pass" -Details "$base/health ok=true"
                } else {
                    Add-Check -Name "contextlattice_health" -Status "fail" -Details "$base/health responded but ok!=true"
                }
            } catch {
                Add-Check -Name "contextlattice_health" -Status "fail" -Details ("Health check failed: {0}" -f $_.Exception.Message)
            }

            try {
                $status = Invoke-RestMethod -Method Get -Uri "$base/status" -Headers @{ "x-api-key" = $key } -TimeoutSec $TimeoutSec
                $svc = if ($status.service) { $status.service } else { "unknown" }
                Add-Check -Name "contextlattice_status" -Status "pass" -Details "service=$svc"
            } catch {
                Add-Check -Name "contextlattice_status" -Status "fail" -Details ("Status check failed: {0}" -f $_.Exception.Message)
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

function Invoke-LLMWorkflowUp {
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = ".",
        [switch]$SkipDependencyInstall,
        [switch]$SkipContextVerify,
        [switch]$SkipBridgeDryRun,
        [switch]$SmokeTestContext,
        [switch]$RequireSearchHit
    )

    $scriptPath = Join-Path $PSScriptRoot "scripts\bootstrap-llm-workflow.ps1"
    $toolkitSource = Join-Path $PSScriptRoot "templates\tools"

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

    & $scriptPath @invokeArgs
}

Set-Alias -Name llmup -Value Invoke-LLMWorkflowUp
Set-Alias -Name llmdown -Value Uninstall-LLMWorkflow
Set-Alias -Name llmcheck -Value Test-LLMWorkflowSetup
Set-Alias -Name llmver -Value Get-LLMWorkflowVersion
Set-Alias -Name llmupdate -Value Update-LLMWorkflow

Export-ModuleMember `
    -Function Install-LLMWorkflow, Uninstall-LLMWorkflow, Update-LLMWorkflow, Get-LLMWorkflowVersion, Test-LLMWorkflowSetup, Invoke-LLMWorkflowUp `
    -Alias llmup, llmdown, llmcheck, llmver, llmupdate
