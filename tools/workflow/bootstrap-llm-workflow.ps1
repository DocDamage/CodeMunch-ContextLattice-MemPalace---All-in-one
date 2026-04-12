[CmdletBinding()]
param(
    [string]$ProjectRoot = ".",
    [string]$ToolkitSource = "",
    [ValidateSet("auto", "openai", "kimi", "gemini", "glm")]
    [string]$Provider = "auto",
    [switch]$SkipDependencyInstall,
    [switch]$SkipProviderNormalize,
    [switch]$SkipContextVerify,
    [switch]$SkipBridgeDryRun,
    [switch]$SmokeTestContext,
    [switch]$RequireSearchHit,
    [switch]$RunCodemunchIndex,
    [switch]$CodemunchEmbed,
    [switch]$DeepCheck,
    [switch]$FailIfNoProviderKey,
    [switch]$FailIfContextMissing,
    [switch]$Offline,
    [int]$ContextSearchAttempts = 20,
    [int]$ContextSearchDelaySec = 1,
    [int]$ContextTimeoutSec = 20,
    [switch]$ContinueOnError,
    [switch]$ShowTiming,
    [switch]$AsJson,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"
$script:WorkflowScriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { (Split-Path -Parent $PSCommandPath) }

# Phase results tracking for graceful degradation
$script:PhaseResults = @()

# Timing tracking
$script:PhaseTimings = @{}

# JSON output tracking
$script:JsonOutput = @{
    startTime = [DateTime]::UtcNow.ToString("o")
    phases = @()
    summary = @{}
    timing = @{}
}

function Write-Step {
    [CmdletBinding()]
    param([string]$Message, [switch]$NoJson)
    if ($AsJson -and -not $NoJson) {
        # In JSON mode, only capture to structured output, don't write to console
        return
    }
    Write-Output "[llm-workflow] $Message"
}

function Write-JsonOutput {
    [CmdletBinding()]
    param([int]$ExitCode = 0)
    $script:JsonOutput.endTime = [DateTime]::UtcNow.ToString("o")
    $script:JsonOutput.exitCode = $ExitCode
    $script:JsonOutput.success = ($ExitCode -eq 0)
    $script:JsonOutput | ConvertTo-Json -Depth 10 | Write-Output
}

function Measure-Phase {
    [CmdletBinding()]
    param(
        [string]$PhaseName,
        [scriptblock]$ScriptBlock,
        [switch]$SkipTiming
    )

    Write-Step "Starting phase: $PhaseName"
    
    $stopwatch = $null
    if (($ShowTiming -or $AsJson) -and -not $SkipTiming) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    }
    
    $phaseOutput = @{
        name = $PhaseName
        startTime = [DateTime]::UtcNow.ToString("o")
        status = "SUCCESS"
        message = ""
    }
    
    if ($ContinueOnError) {
        try {
            & $ScriptBlock
            $script:PhaseResults += @{
                Name = $PhaseName
                Status = "SUCCESS"
                Message = ""
            }
            if ($stopwatch) {
                $stopwatch.Stop()
                $script:PhaseTimings[$PhaseName] = $stopwatch.Elapsed
                $phaseOutput.durationMs = [int]$stopwatch.Elapsed.TotalMilliseconds
            }
            Write-Step "Completed phase: $PhaseName [OK]"
        }
        catch {
            $errorMsg = $_.Exception.Message
            $script:PhaseResults += @{
                Name = $PhaseName
                Status = "FAILED"
                Message = $errorMsg
            }
            $phaseOutput.status = "FAILED"
            $phaseOutput.message = $errorMsg
            if ($stopwatch) {
                $stopwatch.Stop()
                $script:PhaseTimings[$PhaseName] = $stopwatch.Elapsed
                $phaseOutput.durationMs = [int]$stopwatch.Elapsed.TotalMilliseconds
            }
            Write-Step "Failed phase: $PhaseName [FAIL] - $errorMsg"
        }
    }
    else {
        & $ScriptBlock
        $script:PhaseResults += @{
            Name = $PhaseName
            Status = "SUCCESS"
            Message = ""
        }
        if ($stopwatch) {
            $stopwatch.Stop()
            $script:PhaseTimings[$PhaseName] = $stopwatch.Elapsed
            $phaseOutput.durationMs = [int]$stopwatch.Elapsed.TotalMilliseconds
        }
    }
    
    $phaseOutput.endTime = [DateTime]::UtcNow.ToString("o")
    $script:JsonOutput.phases += $phaseOutput
}

function Write-Summary {
    [CmdletBinding()]
    param([switch]$AsJsonOutput)
    
    $failedPhases = @()
    $successCount = 0
    $skippedCount = 0
    
    foreach ($result in $script:PhaseResults) {
        $name = $result.Name
        $status = $result.Status
        $message = $result.Message
        
        switch ($status) {
            "SUCCESS" { $successCount++ }
            "FAILED" { $failedPhases += $result }
            "SKIPPED" { $skippedCount++ }
        }
    }
    
    $errorCount = $failedPhases.Count
    $totalCount = $script:PhaseResults.Count
    
    # Populate JSON summary
    $script:JsonOutput.summary = @{
        totalPhases = $totalCount
        successCount = $successCount
        failedCount = $errorCount
        skippedCount = $skippedCount
        failedPhases = @($failedPhases | ForEach-Object { 
            @{ name = $_.Name; message = $_.Message }
        })
    }
    
    # Populate timing info if available
    if ($script:PhaseTimings.Count -gt 0) {
        $timingInfo = @{}
        $totalMs = 0
        foreach ($key in $script:PhaseTimings.Keys) {
            $ms = [int]$script:PhaseTimings[$key].TotalMilliseconds
            $timingInfo[$key] = $ms
            $totalMs += $ms
        }
        $timingInfo["totalMs"] = $totalMs
        $script:JsonOutput.timing = $timingInfo
    }
    
    if ($AsJsonOutput) {
        return $errorCount
    }
    
    Write-Step "-- Summary -----------------------"
    
    foreach ($result in $script:PhaseResults) {
        $name = $result.Name
        $status = $result.Status
        $message = $result.Message
        
        switch ($status) {
            "SUCCESS" {
                $statusLabel = "[OK]"
                $displayMsg = "SUCCESS"
                Write-Step "$($statusLabel.PadRight(6)) $($name.PadRight(25)) $displayMsg"
            }
            "FAILED" {
                $statusLabel = "[FAIL]"
                $displayMsg = "FAILED: $message"
                Write-Step "$($statusLabel.PadRight(6)) $($name.PadRight(25)) $displayMsg"
            }
            "SKIPPED" {
                $statusLabel = "[SKIP]"
                $displayMsg = "SKIPPED (dependency failed)"
                Write-Step "$($statusLabel.PadRight(6)) $($name.PadRight(25)) $displayMsg"
            }
        }
    }
    
    Write-Step "----------------------------------------"
    
    if ($errorCount -eq 0) {
        Write-Step "All phases completed successfully (exit code 0)"
        return 0
    }
    else {
        Write-Step "Completed with $errorCount error$(if ($errorCount -ne 1) { 's' }) (exit code 1)"
        return 1
    }
}

function Resolve-ToolkitSourcePath {
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$RequestedSource)

    if (-not [string]::IsNullOrWhiteSpace($RequestedSource)) {
        return (Resolve-Path -LiteralPath $RequestedSource).Path
    }

    if (-not [string]::IsNullOrWhiteSpace($env:LLM_WORKFLOW_TOOLKIT_SOURCE) -and (Test-Path -LiteralPath $env:LLM_WORKFLOW_TOOLKIT_SOURCE)) {
        return (Resolve-Path -LiteralPath $env:LLM_WORKFLOW_TOOLKIT_SOURCE).Path
    }

    if ([string]::IsNullOrWhiteSpace($script:WorkflowScriptRoot)) {
        throw "Could not resolve script root for toolkit detection."
    }
    $localToolsRoot = (Resolve-Path -LiteralPath (Join-Path $script:WorkflowScriptRoot "..")).Path
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
    [CmdletBinding()]
    param(
        [string]$ToolsRoot,
        [string]$ProjectPath,
        [string]$ToolName
    )

    $target = Join-Path $ProjectPath "tools" $ToolName
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
    [CmdletBinding()]
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

function Ensure-PythonCommand {
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        throw "Python command not found. Install Python and ensure 'python' is on PATH."
    }
    Write-Step "Python command found: $($pythonCmd.Source)"
}

function Test-PythonImport {
    [CmdletBinding()]
    param([string]$ImportName)

    $probe = "import importlib.util; print(bool(importlib.util.find_spec(r'$ImportName')))"
    $resultRaw = & python -c $probe 2>$null
    $result = if ($null -eq $resultRaw) { "" } else { ($resultRaw | Out-String).Trim() }
    return ($LASTEXITCODE -eq 0 -and $result -eq "True")
}

function Ensure-PythonImport {
    [CmdletBinding()]
    param(
        [string]$ImportName,
        [string]$InstallName,
        [switch]$InstallIfMissing
    )

    if (Test-PythonImport -ImportName $ImportName) {
        Write-Step "Python module '$ImportName' is available."
        return $true
    }

    if (-not $InstallIfMissing) {
        return $false
    }

    Write-Step "Installing Python package '$InstallName' ..."
    & python -m pip install --upgrade $InstallName
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install Python package: $InstallName"
    }

    if (-not (Test-PythonImport -ImportName $ImportName)) {
        throw "Python package install completed but import '$ImportName' is still unavailable."
    }

    return $true
}

function Ensure-CodemunchRuntime {
    [CmdletBinding()]
    param([switch]$InstallIfMissing)

    $cmd = Get-Command codemunch-pro -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Step "codemunch-pro command found: $($cmd.Source)"
        return $true
    }

    if (Test-PythonImport -ImportName "codemunch_pro") {
        Write-Step "Python module 'codemunch_pro' is available (command wrapper not found)."
        return $true
    }

    if (-not $InstallIfMissing) {
        return $false
    }

    Write-Step "Installing codemunch-pro ..."
    & python -m pip install --upgrade codemunch-pro
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install codemunch-pro."
    }

    return $true
}

function Get-FirstEnvValue {
    [CmdletBinding()]
    param([string[]]$Names)

    foreach ($name in $Names) {
        $value = [System.Environment]::GetEnvironmentVariable($name, "Process")
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return @{
                Name = $name
                Value = $value
            }
        }
    }

    return @{
        Name = ""
        Value = ""
    }
}

function Get-ProviderProfile {
    [CmdletBinding()]
    param([string]$Name)

    switch ($Name.ToLowerInvariant()) {
        "openai" {
            return @{
                Name = "openai"
                ApiKeyVars = @("OPENAI_API_KEY")
                BaseUrlVars = @("OPENAI_BASE_URL")
                DefaultBaseUrl = "https://api.openai.com/v1"
            }
        }
        "kimi" {
            return @{
                Name = "kimi"
                ApiKeyVars = @("KIMI_API_KEY", "MOONSHOT_API_KEY")
                BaseUrlVars = @("KIMI_BASE_URL", "MOONSHOT_BASE_URL")
                DefaultBaseUrl = "https://api.moonshot.cn/v1"
            }
        }
        "gemini" {
            return @{
                Name = "gemini"
                ApiKeyVars = @("GEMINI_API_KEY", "GOOGLE_API_KEY")
                BaseUrlVars = @("GEMINI_BASE_URL")
                DefaultBaseUrl = "https://generativelanguage.googleapis.com/v1beta/openai"
            }
        }
        "glm" {
            return @{
                Name = "glm"
                ApiKeyVars = @("GLM_API_KEY", "ZHIPU_API_KEY")
                BaseUrlVars = @("GLM_BASE_URL")
                DefaultBaseUrl = "https://open.bigmodel.cn/api/paas/v4"
            }
        }
        default {
            throw "Unsupported provider: $Name"
        }
    }
}

function Get-ProviderPreferenceOrder {
    [CmdletBinding()]
    param()
    return @("openai", "kimi", "gemini", "glm")
}

function Resolve-ProviderProfile {
    [CmdletBinding()]
    param([string]$RequestedProvider)

    $requested = $RequestedProvider.ToLowerInvariant()

    if ($requested -ne "auto") {
        $profile = Get-ProviderProfile -Name $requested
        $api = Get-FirstEnvValue -Names $profile.ApiKeyVars
        $base = Get-FirstEnvValue -Names $profile.BaseUrlVars
        return @{
            Profile = $profile
            ApiKeyVar = $api.Name
            ApiKey = $api.Value
            BaseUrlVar = $base.Name
            BaseUrl = if ([string]::IsNullOrWhiteSpace($base.Value)) { $profile.DefaultBaseUrl } else { $base.Value }
        }
    }

    $envPreferred = [System.Environment]::GetEnvironmentVariable("LLM_PROVIDER", "Process")
    if (-not [string]::IsNullOrWhiteSpace($envPreferred)) {
        try {
            $preferredProfile = Get-ProviderProfile -Name $envPreferred
            $preferredApi = Get-FirstEnvValue -Names $preferredProfile.ApiKeyVars
            if (-not [string]::IsNullOrWhiteSpace($preferredApi.Value)) {
                $preferredBase = Get-FirstEnvValue -Names $preferredProfile.BaseUrlVars
                return @{
                    Profile = $preferredProfile
                    ApiKeyVar = $preferredApi.Name
                    ApiKey = $preferredApi.Value
                    BaseUrlVar = $preferredBase.Name
                    BaseUrl = if ([string]::IsNullOrWhiteSpace($preferredBase.Value)) { $preferredProfile.DefaultBaseUrl } else { $preferredBase.Value }
                }
            }
        }
        catch {
        }
    }

    foreach ($name in (Get-ProviderPreferenceOrder)) {
        $profile = Get-ProviderProfile -Name $name
        $api = Get-FirstEnvValue -Names $profile.ApiKeyVars
        if (-not [string]::IsNullOrWhiteSpace($api.Value)) {
            $base = Get-FirstEnvValue -Names $profile.BaseUrlVars
            return @{
                Profile = $profile
                ApiKeyVar = $api.Name
                ApiKey = $api.Value
                BaseUrlVar = $base.Name
                BaseUrl = if ([string]::IsNullOrWhiteSpace($base.Value)) { $profile.DefaultBaseUrl } else { $base.Value }
            }
        }
    }

    return $null
}

function Set-NormalizedProviderEnvironment {
    [CmdletBinding()]
    param(
        [string]$RequestedProvider,
        [switch]$FailIfMissing
    )

    $resolved = Resolve-ProviderProfile -RequestedProvider $RequestedProvider
    if ($null -eq $resolved -or [string]::IsNullOrWhiteSpace($resolved.ApiKey)) {
        $hint = "OPENAI_API_KEY, KIMI_API_KEY, GEMINI_API_KEY, or GLM_API_KEY"
        if ($FailIfMissing) {
            throw "No usable provider API key found in environment ($hint)."
        }
        Write-Warning "[llm-workflow] No provider API key found ($hint). Provider normalization skipped."
        return
    }

    [System.Environment]::SetEnvironmentVariable("LLM_PROVIDER", $resolved.Profile.Name, "Process")
    [System.Environment]::SetEnvironmentVariable("LLM_API_KEY", $resolved.ApiKey, "Process")
    [System.Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $resolved.ApiKey, "Process")

    if (-not [string]::IsNullOrWhiteSpace($resolved.BaseUrl)) {
        [System.Environment]::SetEnvironmentVariable("LLM_BASE_URL", $resolved.BaseUrl, "Process")
        [System.Environment]::SetEnvironmentVariable("OPENAI_BASE_URL", $resolved.BaseUrl, "Process")
    }

    $baseSource = if ([string]::IsNullOrWhiteSpace($resolved.BaseUrlVar)) { "default" } else { $resolved.BaseUrlVar }
    Write-Step "Provider resolved: $($resolved.Profile.Name) (api key: $($resolved.ApiKeyVar), base url: $baseSource)."
}

function Invoke-IfExists {
    [CmdletBinding()]
    param(
        [string]$ScriptPath,
        [hashtable]$NamedArgs = @{},
        [switch]$SkipOnError
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        if ($SkipOnError -and $ContinueOnError) {
            Write-Step "Skipping: script not found - $ScriptPath"
            return
        }
        throw "Missing script: $ScriptPath"
    }

    $global:LASTEXITCODE = 0
    & $ScriptPath @NamedArgs
    $exitCode = $global:LASTEXITCODE
    if (-not $?) {
        throw "Script failed: $ScriptPath"
    }
    if (($null -ne $exitCode) -and ($exitCode -ne 0)) {
        throw "Script failed: $ScriptPath (exit $exitCode)"
    }
}

# Handle offline mode
if ($Offline) {
    $SkipDependencyInstall = $true
    $SkipContextVerify = $true
    $SkipBridgeDryRun = $true
    Write-Step "Running in offline mode. Network operations disabled."
}

# Main execution
if ($DeepCheck) {
    $SmokeTestContext = $true
    $RunCodemunchIndex = $true
    $FailIfContextMissing = $true
    if (-not $PSBoundParameters.ContainsKey("ContextSearchAttempts")) {
        $ContextSearchAttempts = 90
    }
    if (-not $PSBoundParameters.ContainsKey("ContextSearchDelaySec")) {
        $ContextSearchDelaySec = 2
    }
    if (-not $PSBoundParameters.ContainsKey("ContextTimeoutSec")) {
        $ContextTimeoutSec = 30
    }
}

$ContextSearchAttempts = [Math]::Max(1, $ContextSearchAttempts)
$ContextSearchDelaySec = [Math]::Max(1, $ContextSearchDelaySec)
$ContextTimeoutSec = [Math]::Max(1, $ContextTimeoutSec)

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$toolsSource = Resolve-ToolkitSourcePath -RequestedSource $ToolkitSource

Write-Step "Project root: $projectPath"
Write-Step "Toolkit source: $toolsSource"

Measure-Phase -PhaseName "Tool scaffold" -ScriptBlock {
    Ensure-ToolFolder -ToolsRoot $toolsSource -ProjectPath $projectPath -ToolName "codemunch"
    Ensure-ToolFolder -ToolsRoot $toolsSource -ProjectPath $projectPath -ToolName "contextlattice"
    Ensure-ToolFolder -ToolsRoot $toolsSource -ProjectPath $projectPath -ToolName "memorybridge"
}

Measure-Phase -PhaseName "Environment load" -ScriptBlock {
    Import-EnvFile -Path (Join-Path $projectPath ".env")
    Import-EnvFile -Path (Join-Path $projectPath ".contextlattice" "orchestrator.env")
}

Measure-Phase -PhaseName "Provider normalize" -ScriptBlock {
    if (-not $SkipProviderNormalize) {
        Set-NormalizedProviderEnvironment -RequestedProvider $Provider -FailIfMissing:$FailIfNoProviderKey
    }
    else {
        Write-Step "Provider normalization skipped (flag set)"
    }
}

Measure-Phase -PhaseName "Python check" -ScriptBlock {
    $requiresPython = (-not $SkipDependencyInstall) -or (-not $SkipBridgeDryRun) -or $RunCodemunchIndex
    if ($Offline) {
        $requiresPython = $false
        Write-Step "Python check skipped (offline mode)"
    }
    if ($requiresPython) {
        Ensure-PythonCommand
    }
    else {
        Write-Step "Python check skipped (not required)"
    }
}

Measure-Phase -PhaseName "Dependency check" -ScriptBlock {
    if (-not $SkipDependencyInstall) {
        $null = Ensure-CodemunchRuntime -InstallIfMissing
        $null = Ensure-PythonImport -ImportName "chromadb" -InstallName "chromadb" -InstallIfMissing
    }
    else {
        if ($RunCodemunchIndex) {
            $codemunchReady = Ensure-CodemunchRuntime
            if (-not $codemunchReady) {
                throw "codemunch runtime is missing. Re-run without -SkipDependencyInstall to install codemunch-pro."
            }
        }

        if (-not $SkipBridgeDryRun) {
            $chromadbReady = Ensure-PythonImport -ImportName "chromadb" -InstallName "chromadb"
            if (-not $chromadbReady) {
                throw "chromadb module is missing. Re-run without -SkipDependencyInstall to install chromadb."
            }
        }
    }
}

$codemunchBootstrap = Join-Path $projectPath "tools" "codemunch" "bootstrap-project.ps1"
$codemunchIndex = Join-Path $projectPath "tools" "codemunch" "index-project.ps1"
$contextBootstrap = Join-Path $projectPath "tools" "contextlattice" "bootstrap-project.ps1"
$contextVerify = Join-Path $projectPath "tools" "contextlattice" "verify.ps1"
$memoryBootstrap = Join-Path $projectPath "tools" "memorybridge" "bootstrap-project.ps1"
$memorySync = Join-Path $projectPath "tools" "memorybridge" "sync-from-mempalace.ps1"

Measure-Phase -PhaseName "CodeMunch bootstrap" -ScriptBlock {
    Invoke-IfExists -ScriptPath $codemunchBootstrap -NamedArgs @{ ProjectRoot = $projectPath } -SkipOnError
}

Measure-Phase -PhaseName "ContextLattice bootstrap" -ScriptBlock {
    Invoke-IfExists -ScriptPath $contextBootstrap -NamedArgs @{ ProjectRoot = $projectPath } -SkipOnError
}

Measure-Phase -PhaseName "MemoryBridge bootstrap" -ScriptBlock {
    Invoke-IfExists -ScriptPath $memoryBootstrap -NamedArgs @{ ProjectRoot = $projectPath } -SkipOnError
}

Measure-Phase -PhaseName "CodeMunch index" -ScriptBlock {
    if ($RunCodemunchIndex) {
        $indexArgs = @{
            ProjectRoot = $projectPath
            OutFile = ".codemunch\last-index.json"
        }
        if ($CodemunchEmbed) {
            $indexArgs["Embed"] = $true
        }
        Invoke-IfExists -ScriptPath $codemunchIndex -NamedArgs $indexArgs -SkipOnError
    }
    else {
        $script:PhaseResults[-1].Status = "SKIPPED"
        $script:PhaseResults[-1].Message = "Skipped (flag not set)"
        Write-Step "CodeMunch index skipped (flag not set)"
    }
}

$hasContextApiKey = -not [string]::IsNullOrWhiteSpace($env:CONTEXTLATTICE_ORCHESTRATOR_API_KEY)

Measure-Phase -PhaseName "ContextLattice verify" -ScriptBlock {
    if (-not $SkipContextVerify) {
        if ($hasContextApiKey) {
            $verifyArgs = @{
                SearchAttempts = $ContextSearchAttempts
                SearchDelaySec = $ContextSearchDelaySec
                TimeoutSec = $ContextTimeoutSec
            }
            if ($SmokeTestContext) {
                $verifyArgs["SmokeTest"] = $true
            }
            if ($RequireSearchHit) {
                $verifyArgs["RequireSearchHit"] = $true
            }
            Invoke-IfExists -ScriptPath $contextVerify -NamedArgs $verifyArgs -SkipOnError
        }
        else {
            $msg = "CONTEXTLATTICE_ORCHESTRATOR_API_KEY is not set."
            if ($FailIfContextMissing) {
                throw $msg
            }
            Write-Warning "[llm-workflow] Skipping ContextLattice verify: $msg"
        }
    }
    else {
        Write-Step "ContextLattice verify skipped (flag set)"
    }
}

Measure-Phase -PhaseName "MemoryBridge dry-run" -ScriptBlock {
    if (-not $SkipBridgeDryRun) {
        if ($hasContextApiKey) {
            $bridgeArgs = @{ DryRun = $true }
            if ($DeepCheck) {
                $bridgeArgs["Strict"] = $true
            }
            Invoke-IfExists -ScriptPath $memorySync -NamedArgs $bridgeArgs -SkipOnError
        }
        else {
            $msg = "CONTEXTLATTICE_ORCHESTRATOR_API_KEY is not set."
            if ($FailIfContextMissing) {
                throw $msg
            }
            Write-Warning "[llm-workflow] Skipping MemPalace bridge dry-run: $msg"
        }
    }
    else {
        Write-Step "MemoryBridge dry-run skipped (flag set)"
    }
}

Measure-Phase -PhaseName "Plugin bootstrap" -ScriptBlock {
    $pluginManifestPath = Join-Path $projectPath ".llm-workflow" "plugins.json"
    if (Test-Path -LiteralPath $pluginManifestPath) {
        Write-Step "Loading plugin manifest..."
        try {
            $pluginContent = Get-Content -LiteralPath $pluginManifestPath -Raw -Encoding UTF8
            $pluginManifest = $pluginContent | ConvertFrom-Json -ErrorAction Stop
            if ($pluginManifest.plugins -and $pluginManifest.plugins.Count -gt 0) {
                Write-Step "Found $($pluginManifest.plugins.Count) registered plugin(s)"
                $bootstrapPlugins = @($pluginManifest.plugins | Where-Object { $_.runOn -contains "bootstrap" })
                Write-Step "Executing $($bootstrapPlugins.Count) bootstrap plugin(s)..."
                foreach ($plugin in $bootstrapPlugins) {
                    if (-not $plugin.bootstrapScript) {
                        Write-Warning "[llm-workflow] Plugin '$($plugin.name)' has no bootstrapScript defined"
                        continue
                    }
                    $scriptPath = Join-Path $projectPath $plugin.bootstrapScript
                    if (-not (Test-Path -LiteralPath $scriptPath)) {
                        $warnMsg = "Plugin '$($plugin.name)' bootstrap script not found: $($plugin.bootstrapScript)"
                        if ($Strict) {
                            throw $warnMsg
                        }
                        Write-Warning "[llm-workflow] $warnMsg"
                        continue
                    }
                    Write-Step "Running plugin: $($plugin.name)"
                    $global:LASTEXITCODE = 0
                    & $scriptPath -ProjectRoot $projectPath 2>&1 | ForEach-Object {
                        Write-Output "[plugin:$($plugin.name)] $_"
                    }
                    $exitCode = $global:LASTEXITCODE
                    if ($exitCode -ne 0) {
                        $errMsg = "Plugin '$($plugin.name)' failed with exit code $exitCode"
                        if ($Strict) {
                            throw $errMsg
                        }
                        Write-Warning "[llm-workflow] $errMsg"
                    }
                    else {
                        Write-Step "Plugin '$($plugin.name)' completed successfully"
                    }
                }
            }
            else {
                Write-Step "No plugins registered"
            }
        }
        catch {
            $errMsg = "Failed to process plugins: $($_.Exception.Message)"
            if ($Strict) {
                throw $errMsg
            }
            Write-Warning "[llm-workflow] $errMsg"
        }
    }
    else {
        Write-Step "No plugin manifest found (skipping plugin phase)"
    }
}

function Write-TimingSummary {
    [CmdletBinding()]
    param()
    if (-not $ShowTiming) {
        return
    }
    
    Write-Step "-- Timing -----------------------"
    
    # Define the phases we want to display in order
    $timingPhases = @(
        "Tool scaffold",
        "Environment load",
        "Dependency check",
        "CodeMunch index",
        "ContextLattice verify",
        "MemoryBridge dry-run"
    )
    
    # Map phase names to display names
    $displayNames = @{
        "Tool scaffold" = "Tool scaffold"
        "Environment load" = "Env loading"
        "Dependency check" = "Dependency check"
        "CodeMunch index" = "CodeMunch index"
        "ContextLattice verify" = "CL verify"
        "MemoryBridge dry-run" = "Bridge dry-run"
    }
    
    $totalTicks = 0
    
    foreach ($phase in $timingPhases) {
        if ($script:PhaseTimings.ContainsKey($phase)) {
            $elapsed = $script:PhaseTimings[$phase]
            $totalTicks += $elapsed.Ticks
            $seconds = $elapsed.TotalSeconds.ToString("F1")
            $displayName = $displayNames[$phase]
            Write-Step " $($displayName.PadRight(18)) $($seconds)s"
        }
    }
    
    $totalSeconds = [TimeSpan]::FromTicks($totalTicks).TotalSeconds.ToString("F1")
    Write-Step " $($"Total".PadRight(18)) $($totalSeconds)s"
}

$exitCode = Write-Summary -AsJsonOutput:$AsJson

if ($AsJson) {
    Write-JsonOutput -ExitCode $exitCode
}
else {
    Write-TimingSummary
    Write-Step "Workflow bootstrap complete."
}

exit $exitCode
