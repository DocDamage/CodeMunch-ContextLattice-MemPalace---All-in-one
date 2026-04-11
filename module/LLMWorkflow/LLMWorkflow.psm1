Set-StrictMode -Version Latest

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

Export-ModuleMember -Function Install-LLMWorkflow, Uninstall-LLMWorkflow, Invoke-LLMWorkflowUp -Alias llmup, llmdown
