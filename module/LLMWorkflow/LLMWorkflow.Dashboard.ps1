#requires -Version 5.1
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
param(
    [string]$ProjectRoot = ".",
    [ValidateSet("auto", "openai", "kimi", "gemini", "glm")]
    [string]$Provider = "auto",
    [switch]$CheckContext,
    [int]$TimeoutSec = 10,
    [switch]$NoInteractive,
    [int]$RefreshInterval = 0
)

#region ANSI Escape Codes
$script:Ansi = @{
    Reset = "$([char]0x1B)[0m"
    Bold = "$([char]0x1B)[1m"
    Dim = "$([char]0x1B)[2m"
    Italic = "$([char]0x1B)[3m"
    Underline = "$([char]0x1B)[4m"
    Black = "$([char]0x1B)[30m"
    Red = "$([char]0x1B)[31m"
    Green = "$([char]0x1B)[32m"
    Yellow = "$([char]0x1B)[33m"
    Blue = "$([char]0x1B)[34m"
    Magenta = "$([char]0x1B)[35m"
    Cyan = "$([char]0x1B)[36m"
    White = "$([char]0x1B)[37m"
    BrightRed = "$([char]0x1B)[91m"
    BrightGreen = "$([char]0x1B)[92m"
    BrightYellow = "$([char]0x1B)[93m"
    BrightBlue = "$([char]0x1B)[94m"
    BgBlack = "$([char]0x1B)[40m"
    BgRed = "$([char]0x1B)[41m"
    BgGreen = "$([char]0x1B)[42m"
    BgYellow = "$([char]0x1B)[43m"
    BgBlue = "$([char]0x1B)[44m"
    BgCyan = "$([char]0x1B)[46m"
    Clear = "$([char]0x1B)[2J"
    ClearLine = "$([char]0x1B)[2K"
    CursorHome = "$([char]0x1B)[H"
    CursorUp = "$([char]0x1B)[A"
    CursorHide = "$([char]0x1B)[?25l"
    CursorShow = "$([char]0x1B)[?25h"
}
#endregion

#region Helper Functions

function Test-InteractiveShell {
    [CmdletBinding()]
    param()
    
    if ($NoInteractive) { return $false }
    if ($env:CI -or $env:TF_BUILD -or $env:GITHUB_ACTIONS -or $env:JENKINS_HOME) { return $false }
    
    try {
        if (-not $Host.UI.RawUI) { return $false }
        if ($Host.Name -match "ISE|Visual Studio Code") { return $true }
        if ($Host.Name -eq "ConsoleHost") { return $true }
    } catch {
        return $false
    }
    
    return $true
}

function Test-AnsiSupport {
    [CmdletBinding()]
    param()
    
    if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 2) {
        return $true
    }
    if ($env:TERM -and $env:TERM -ne "dumb") { return $true }
    if ($env:WT_SESSION) { return $true }
    if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
        return ($Host.Name -eq "ConsoleHost")
    }
    return $false
}

function Write-DashboardHeader {
    [CmdletBinding()]
    param([switch]$UseAnsi, [switch]$UseColors)
    
    if ($UseAnsi) {
        $a = $script:Ansi
        Write-Host "$($a.Bold)$($a.Cyan)========================================$($a.Reset)"
        Write-Host "$($a.Bold)$($a.Cyan)   LLM WORKFLOW DASHBOARD $($a.BrightYellow)v0.9.6$($a.Reset)"
        Write-Host "$($a.Bold)$($a.Cyan)========================================$($a.Reset)"
    } elseif ($UseColors) {
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "   LLM WORKFLOW DASHBOARD v0.9.6" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
    } else {
        Write-Output "========================================"
        Write-Output "   LLM WORKFLOW DASHBOARD v0.9.6"
        Write-Output "========================================"
    }
}

function Write-DashboardFooter {
    [CmdletBinding()]
    param(
        [switch]$UseAnsi,
        [switch]$UseColors,
        [string]$StatusMessage = "",
        [int]$PassCount = 0,
        [int]$WarnCount = 0,
        [int]$FailCount = 0
    )
    
    if ($UseAnsi) {
        $a = $script:Ansi
        Write-Host "$($a.Bold)========================================$($a.Reset)"
        Write-Host "$($a.Bold)Summary:$($a.Reset) " -NoNewline
        Write-Host "$($a.Green)[OK: $PassCount]$($a.Reset) " -NoNewline
        if ($WarnCount -gt 0) { Write-Host "$($a.Yellow)[WARN: $WarnCount]$($a.Reset) " -NoNewline }
        if ($FailCount -gt 0) { Write-Host "$($a.Red)[FAIL: $FailCount]$($a.Reset) " -NoNewline }
        Write-Host ""
        if ($StatusMessage) { Write-Host "$($a.Dim)$StatusMessage$($a.Reset)" }
        Write-Host "$($a.Bold)========================================$($a.Reset)"
        Write-Host "$($a.Dim)Controls: [R]erun  [Q]uit  [A]uto-refresh$($a.Reset)"
    } elseif ($UseColors) {
        Write-Host "========================================" -ForegroundColor White
        Write-Host "Summary: " -NoNewline
        Write-Host "[OK: $PassCount]" -ForegroundColor Green -NoNewline
        if ($WarnCount -gt 0) { Write-Host " [WARN: $WarnCount]" -ForegroundColor Yellow -NoNewline }
        if ($FailCount -gt 0) { Write-Host " [FAIL: $FailCount]" -ForegroundColor Red -NoNewline }
        Write-Host ""
        if ($StatusMessage) { Write-Host $StatusMessage -ForegroundColor Gray }
        Write-Host "========================================" -ForegroundColor White
        Write-Host "Controls: [R]erun  [Q]uit  [A]uto-refresh" -ForegroundColor Gray
    } else {
        Write-Output "========================================"
        Write-Output "Summary: [OK: $PassCount] [WARN: $WarnCount] [FAIL: $FailCount]"
        if ($StatusMessage) { Write-Output $StatusMessage }
        Write-Output "========================================"
        Write-Output "Controls: [R]erun  [Q]uit  [A]uto-refresh"
    }
}

function Write-CheckResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [ValidateSet("OK", "WARN", "FAIL", "PENDING")]
        [string]$Status,
        [string]$Detail = "",
        [int]$LatencyMs = 0,
        [switch]$UseAnsi,
        [switch]$UseColors,
        [int]$MaxNameWidth = 25
    )
    
    $paddedName = $Name.PadRight($MaxNameWidth)
    
    if ($UseAnsi) {
        $a = $script:Ansi
        switch ($Status) {
            "OK" {
                Write-Host "[$($a.Green)OK$($a.Reset)]   $paddedName " -NoNewline
            }
            "WARN" {
                Write-Host "[$($a.Yellow)WARN$($a.Reset)]  $paddedName " -NoNewline
            }
            "FAIL" {
                Write-Host "[$($a.Red)FAIL$($a.Reset)]  $paddedName " -NoNewline
            }
            "PENDING" {
                Write-Host "[$($a.Dim)....$($a.Reset)]  $paddedName " -NoNewline
            }
        }
        Write-Host "$($a.Dim)$Detail$($a.Reset)" -NoNewline
        if ($LatencyMs -gt 0) {
            Write-Host " $($a.Cyan)($($LatencyMs)ms)$($a.Reset)"
        } else {
            Write-Host ""
        }
    } elseif ($UseColors) {
        switch ($Status) {
            "OK" {
                Write-Host "[OK]   $paddedName " -NoNewline -ForegroundColor Green
            }
            "WARN" {
                Write-Host "[WARN] $paddedName " -NoNewline -ForegroundColor Yellow
            }
            "FAIL" {
                Write-Host "[FAIL] $paddedName " -NoNewline -ForegroundColor Red
            }
            "PENDING" {
                Write-Host "[....] $paddedName " -NoNewline -ForegroundColor Gray
            }
        }
        Write-Host $Detail -NoNewline -ForegroundColor Gray
        if ($LatencyMs -gt 0) {
            Write-Host " ($($LatencyMs)ms)" -ForegroundColor Cyan
        } else {
            Write-Host ""
        }
    } else {
        $statusStr = switch ($Status) {
            "OK" { "[OK]" }
            "WARN" { "[WARN]" }
            "FAIL" { "[FAIL]" }
            "PENDING" { "[....]" }
        }
        $latencyStr = if ($LatencyMs -gt 0) { " ($($LatencyMs)ms)" } else { "" }
        Write-Output "$statusStr $paddedName $Detail$latencyStr"
    }
}

function Write-ProgressBar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$Current,
        [Parameter(Mandatory=$true)]
        [int]$Total,
        [switch]$UseAnsi,
        [switch]$UseColors,
        [int]$Width = 40
    )
    
    $percent = if ($Total -gt 0) { [int](($Current / $Total) * 100) } else { 0 }
    $filled = [int](($Current / $Total) * $Width)
    $empty = $Width - $filled
    
    $bar = "[" + ("#" * $filled) + ("-" * $empty) + "]"
    
    if ($UseAnsi) {
        $a = $script:Ansi
        Write-Host "Progress: $bar " -NoNewline
        Write-Host "$($a.Bold)$($percent)%$($a.Reset)" -NoNewline
        Write-Host " ($Current/$Total)"
    } elseif ($UseColors) {
        Write-Host "Progress: $bar " -NoNewline
        Write-Host "$percent%" -NoNewline -ForegroundColor White
        Write-Host " ($Current/$Total)"
    } else {
        Write-Output "Progress: $bar $percent% ($Current/$Total)"
    }
}

function Write-PlainTextReport {
    [CmdletBinding()]
    param(
        [array]$Checks,
        [string]$ProjectPath,
        [string]$Provider,
        [hashtable]$ProviderResolved
    )
    
    Write-Output "[llm-workflow-doctor] project=$ProjectPath"
    Write-Output "[llm-workflow-doctor] provider.requested=$Provider"
    if ($ProviderResolved -and $ProviderResolved.Profile) {
        Write-Output "[llm-workflow-doctor] provider.resolved=$($ProviderResolved.Profile.Name)"
    }
    
    foreach ($check in $Checks) {
        $status = if ($check.Ok) { "OK" } else { "FAIL" }
        if ($check.LatencyMs -ne $null -and $check.LatencyMs -gt 0) {
            Write-Output ("[{0}] {1}: {2} ({3}ms)" -f $status, $check.Name, $check.Detail, $check.LatencyMs)
        } else {
            Write-Output ("[{0}] {1}: {2}" -f $status, $check.Name, $check.Detail)
        }
    }
    
    $failed = @($Checks | Where-Object { -not $_.Ok })
    if ($failed.Count -eq 0) {
        Write-Output "[llm-workflow-doctor] all checks passed"
    } else {
        Write-Warning ("[llm-workflow-doctor] failed checks: {0}" -f ($failed.Name -join ", "))
    }
}

#endregion

#region Core Check Functions

function Import-EnvFile {
    [CmdletBinding()]
    param([string]$Path)
    
    if (-not (Test-Path -LiteralPath $Path)) { return }
    
    foreach ($rawLine in (Get-Content -LiteralPath $Path)) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith("#")) { continue }
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
}

function Test-PythonImport {
    [CmdletBinding()]
    param([string]$ImportName)
    
    $probe = "import importlib.util; print(bool(importlib.util.find_spec(r'$ImportName')))"
    $resultRaw = & python -c $probe 2>$null
    $result = if ($null -eq $resultRaw) { "" } else { ($resultRaw | Out-String).Trim() }
    return ($LASTEXITCODE -eq 0 -and $result -eq "True")
}

function Get-PythonPackageVersion {
    [CmdletBinding()]
    param([string]$ImportName)
    
    try {
        $probe = "import $ImportName; print(getattr($ImportName, '__version__', 'unknown'))"
        $resultRaw = & python -c $probe 2>$null
        if ($LASTEXITCODE -eq 0 -and $null -ne $resultRaw) {
            return ($resultRaw | Out-String).Trim()
        }
    } catch {
        return $null
    }
    return $null
}

function Get-PythonVersion {
    try {
        $resultRaw = & python --version 2>&1
        if ($LASTEXITCODE -eq 0 -and $null -ne $resultRaw) {
            $versionLine = ($resultRaw | Out-String).Trim()
            if ($versionLine -match "Python\s+(\d+\.\d+\.\d+)") {
                return $matches[1]
            } elseif ($versionLine -match "Python\s+(\d+\.\d+)") {
                return $matches[1] + ".0"
            }
        }
    } catch {
        return $null
    }
    return $null
}

function Test-VersionMeetsMinimum {
    [CmdletBinding()]
    param([string]$Version, [string]$Minimum)
    
    if ([string]::IsNullOrWhiteSpace($Version) -or $Version -eq "unknown") { return $false }
    try {
        $v = [version]$Version
        $min = [version]$Minimum
        return ($v -ge $min)
    } catch {
        return $false
    }
}

function Get-FirstEnvValue {
    [CmdletBinding()]
    param([string[]]$Names)
    
    foreach ($name in $Names) {
        $value = [System.Environment]::GetEnvironmentVariable($name, "Process")
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return @{ Name = $name; Value = $value }
        }
    }
    return @{ Name = ""; Value = "" }
}

function Get-ProviderProfile {
    [CmdletBinding()]
    param([string]$Name)
    
    switch ($Name.ToLowerInvariant()) {
        "openai" {
            return @{ Name = "openai"; ApiKeyVars = @("OPENAI_API_KEY"); BaseUrlVars = @("OPENAI_BASE_URL"); DefaultBaseUrl = "https://api.openai.com/v1" }
        }
        "kimi" {
            return @{ Name = "kimi"; ApiKeyVars = @("KIMI_API_KEY", "MOONSHOT_API_KEY"); BaseUrlVars = @("KIMI_BASE_URL", "MOONSHOT_BASE_URL"); DefaultBaseUrl = "https://api.moonshot.cn/v1" }
        }
        "gemini" {
            return @{ Name = "gemini"; ApiKeyVars = @("GEMINI_API_KEY", "GOOGLE_API_KEY"); BaseUrlVars = @("GEMINI_BASE_URL"); DefaultBaseUrl = "https://generativelanguage.googleapis.com/v1beta/openai" }
        }
        "glm" {
            return @{ Name = "glm"; ApiKeyVars = @("GLM_API_KEY", "ZHIPU_API_KEY"); BaseUrlVars = @("GLM_BASE_URL"); DefaultBaseUrl = "https://open.bigmodel.cn/api/paas/v4" }
        }
        default {
            throw "Unsupported provider: $Name"
        }
    }
}

function Resolve-ProviderProfile {
    [CmdletBinding()]
    param([string]$RequestedProvider)
    
    $requested = $RequestedProvider.ToLowerInvariant()
    $order = @("openai", "kimi", "gemini", "glm")
    
    if ($requested -ne "auto") {
        $profile = Get-ProviderProfile -Name $requested
        $api = Get-FirstEnvValue -Names $profile.ApiKeyVars
        $base = Get-FirstEnvValue -Names $profile.BaseUrlVars
        return @{
            Profile = $profile
            ApiKeyVar = $api.Name
            ApiKeySet = -not [string]::IsNullOrWhiteSpace($api.Value)
            BaseUrlVar = $base.Name
            BaseUrl = if ([string]::IsNullOrWhiteSpace($base.Value)) { $profile.DefaultBaseUrl } else { $base.Value }
        }
    }
    
    foreach ($name in $order) {
        $profile = Get-ProviderProfile -Name $name
        $api = Get-FirstEnvValue -Names $profile.ApiKeyVars
        if (-not [string]::IsNullOrWhiteSpace($api.Value)) {
            $base = Get-FirstEnvValue -Names $profile.BaseUrlVars
            return @{
                Profile = $profile
                ApiKeyVar = $api.Name
                ApiKeySet = $true
                BaseUrlVar = $base.Name
                BaseUrl = if ([string]::IsNullOrWhiteSpace($base.Value)) { $profile.DefaultBaseUrl } else { $base.Value }
            }
        }
    }
    
    return $null
}

function Test-ProviderKey {
    [CmdletBinding()]
    param(
        [hashtable]$ProviderProfile,
        [string]$ApiKey,
        [string]$BaseUrl,
        [int]$TimeoutSec = 10,
        [ref]$LatencyMs
    )
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $providerName = $ProviderProfile.Name.ToLowerInvariant()
        $headers = @{
            "Authorization" = "Bearer $ApiKey"
            "Content-Type" = "application/json"
        }
        
        switch ($providerName) {
            { $_ -in @("openai", "kimi", "gemini") } {
                $null = Invoke-RestMethod -Method Get -Uri "$BaseUrl/models" -Headers $headers -TimeoutSec $TimeoutSec
                $stopwatch.Stop()
                if ($LatencyMs) { $LatencyMs.Value = $stopwatch.ElapsedMilliseconds }
                return $true
            }
            "glm" {
                $body = @{ model = "glm-4-flash"; messages = @(@{ role = "user"; content = "Hi" }); max_tokens = 1 } | ConvertTo-Json -Depth 4
                $null = Invoke-RestMethod -Method Post -Uri "$BaseUrl/chat/completions" -Headers $headers -Body $body -TimeoutSec $TimeoutSec
                $stopwatch.Stop()
                if ($LatencyMs) { $LatencyMs.Value = $stopwatch.ElapsedMilliseconds }
                return $true
            }
            default {
                $stopwatch.Stop()
                if ($LatencyMs) { $LatencyMs.Value = $stopwatch.ElapsedMilliseconds }
                return $false
            }
        }
    } catch {
        $stopwatch.Stop()
        if ($LatencyMs) { $LatencyMs.Value = $stopwatch.ElapsedMilliseconds }
        return $false
    }
}

#endregion

#region Main Dashboard Logic

function Invoke-DashboardCheck {
    [CmdletBinding()]
    param(
        [string]$ProjectRoot,
        [string]$Provider,
        [switch]$CheckContext,
        [int]$TimeoutSec,
        [scriptblock]$OnCheckComplete
    )
    
    $checks = New-Object System.Collections.Generic.List[object]
    $totalChecks = 9
    if ($CheckContext) { $totalChecks += 2 }
    $currentCheck = 0
    
    $projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
    Import-EnvFile -Path (Join-Path $projectPath ".env")
    Import-EnvFile -Path (Join-Path $projectPath ".contextlattice" "orchestrator.env")
    
    # Check 1: Python command
    $currentCheck++
    & $OnCheckComplete $currentCheck $totalChecks "python_command" "PENDING" "Checking..."
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    $checks.Add([pscustomobject]@{
        Name = "python_command"
        Ok = ($null -ne $pythonCmd)
        Detail = if ($pythonCmd) { "Found: $($pythonCmd.Source)" } else { "Install Python and add python to PATH." }
        LatencyMs = $null
    })
    & $OnCheckComplete $currentCheck $totalChecks "python_command" (if ($pythonCmd) { "OK" } else { "FAIL" }) $checks[-1].Detail
    
    # Check 2: Python version
    $currentCheck++
    & $OnCheckComplete $currentCheck $totalChecks "python_version" "PENDING" "Checking..."
    $pythonVersion = if ($pythonCmd) { Get-PythonVersion } else { $null }
    $minPython = "3.10.0"
    $pythonVersionOk = Test-VersionMeetsMinimum -Version $pythonVersion -Minimum $minPython
    if ($pythonVersion) {
        $checks.Add([pscustomobject]@{ Name = "python_version"; Ok = $pythonVersionOk; Detail = if ($pythonVersionOk) { $pythonVersion } else { "Found $pythonVersion, need >= $minPython" }; LatencyMs = $null })
    } else {
        $checks.Add([pscustomobject]@{ Name = "python_version"; Ok = $false; Detail = "Not installed"; LatencyMs = $null })
    }
    & $OnCheckComplete $currentCheck $totalChecks "python_version" (if ($pythonVersionOk) { "OK" } else { if ($pythonVersion) { "WARN" } else { "FAIL" } }) $checks[-1].Detail
    
    # Check 3: CodeMunch runtime
    $currentCheck++
    & $OnCheckComplete $currentCheck $totalChecks "codemunch_runtime" "PENDING" "Checking..."
    $codemunchCmd = Get-Command codemunch-pro -ErrorAction SilentlyContinue
    $codemunchImport = if ($pythonCmd) { Test-PythonImport -ImportName "codemunch_pro" } else { $false }
    $codemunchOk = ($null -ne $codemunchCmd) -or $codemunchImport
    $checks.Add([pscustomobject]@{
        Name = "codemunch_runtime"
        Ok = $codemunchOk
        Detail = if ($codemunchCmd) { "command: $($codemunchCmd.Source)" } elseif ($codemunchImport) { "python module codemunch_pro is importable" } else { "Install with: python -m pip install --upgrade codemunch-pro" }
        LatencyMs = $null
    })
    & $OnCheckComplete $currentCheck $totalChecks "codemunch_runtime" (if ($codemunchOk) { "OK" } else { "FAIL" }) $checks[-1].Detail
    
    # Check 4: CodeMunch version
    $currentCheck++
    & $OnCheckComplete $currentCheck $totalChecks "codemunch_version" "PENDING" "Checking..."
    $codemunchVersion = if ($codemunchImport) { Get-PythonPackageVersion -ImportName "codemunch_pro" } else { $null }
    $minCodemunch = "1.0.0"
    $codemunchVersionOk = Test-VersionMeetsMinimum -Version $codemunchVersion -Minimum $minCodemunch
    if ($codemunchVersion) {
        $checks.Add([pscustomobject]@{ Name = "codemunch_version"; Ok = $codemunchVersionOk; Detail = if ($codemunchVersionOk) { $codemunchVersion } else { "Found $codemunchVersion, need >= $minCodemunch" }; LatencyMs = $null })
    } else {
        $checks.Add([pscustomobject]@{ Name = "codemunch_version"; Ok = $false; Detail = "Not installed"; LatencyMs = $null })
    }
    & $OnCheckComplete $currentCheck $totalChecks "codemunch_version" (if ($codemunchVersionOk) { "OK" } else { if ($codemunchVersion) { "WARN" } else { "FAIL" } }) $checks[-1].Detail
    
    # Check 5: ChromaDB module
    $currentCheck++
    & $OnCheckComplete $currentCheck $totalChecks "chromadb_module" "PENDING" "Checking..."
    $chromadbImport = if ($pythonCmd) { Test-PythonImport -ImportName "chromadb" } else { $false }
    $checks.Add([pscustomobject]@{ Name = "chromadb_module"; Ok = $chromadbImport; Detail = if ($chromadbImport) { "chromadb import ok" } else { "Install with: python -m pip install --upgrade chromadb" }; LatencyMs = $null })
    & $OnCheckComplete $currentCheck $totalChecks "chromadb_module" (if ($chromadbImport) { "OK" } else { "FAIL" }) $checks[-1].Detail
    
    # Check 6: ChromaDB version
    $currentCheck++
    & $OnCheckComplete $currentCheck $totalChecks "chromadb_version" "PENDING" "Checking..."
    $chromadbVersion = if ($chromadbImport) { Get-PythonPackageVersion -ImportName "chromadb" } else { $null }
    $minChromadb = "0.5.0"
    $chromadbVersionOk = Test-VersionMeetsMinimum -Version $chromadbVersion -Minimum $minChromadb
    if ($chromadbVersion) {
        $checks.Add([pscustomobject]@{ Name = "chromadb_version"; Ok = $chromadbVersionOk; Detail = if ($chromadbVersionOk) { $chromadbVersion } else { "Found $chromadbVersion, need >= $minChromadb" }; LatencyMs = $null })
    } else {
        $checks.Add([pscustomobject]@{ Name = "chromadb_version"; Ok = $false; Detail = "Not installed"; LatencyMs = $null })
    }
    & $OnCheckComplete $currentCheck $totalChecks "chromadb_version" (if ($chromadbVersionOk) { "OK" } else { if ($chromadbVersion) { "WARN" } else { "FAIL" } }) $checks[-1].Detail
    
    # Check 7: Provider credentials
    $currentCheck++
    & $OnCheckComplete $currentCheck $totalChecks "provider_credentials" "PENDING" "Checking..."
    $providerResolved = Resolve-ProviderProfile -RequestedProvider $Provider
    if ($null -eq $providerResolved) {
        $checks.Add([pscustomobject]@{ Name = "provider_credentials"; Ok = $false; Detail = "No provider key found. Set OPENAI_API_KEY, KIMI_API_KEY, GEMINI_API_KEY, or GLM_API_KEY in .env"; LatencyMs = $null })
    } else {
        $baseSource = if ([string]::IsNullOrWhiteSpace($providerResolved.BaseUrlVar)) { "default" } else { $providerResolved.BaseUrlVar }
        $checks.Add([pscustomobject]@{ Name = "provider_credentials"; Ok = $providerResolved.ApiKeySet; Detail = "provider=$($providerResolved.Profile.Name), apiKeyVar=$($providerResolved.ApiKeyVar), baseUrlSource=$baseSource"; LatencyMs = $null })
    }
    & $OnCheckComplete $currentCheck $totalChecks "provider_credentials" (if ($providerResolved -and $providerResolved.ApiKeySet) { "OK" } else { "FAIL" }) $checks[-1].Detail
    
    # Check 8: ContextLattice env
    $currentCheck++
    & $OnCheckComplete $currentCheck $totalChecks "contextlattice_env" "PENDING" "Checking..."
    $ctxUrl = $env:CONTEXTLATTICE_ORCHESTRATOR_URL
    $ctxKeySet = -not [string]::IsNullOrWhiteSpace($env:CONTEXTLATTICE_ORCHESTRATOR_API_KEY)
    $ctxEnvOk = (-not [string]::IsNullOrWhiteSpace($ctxUrl)) -and $ctxKeySet
    $checks.Add([pscustomobject]@{ Name = "contextlattice_env"; Ok = $ctxEnvOk; Detail = if ($ctxEnvOk) { "url=$ctxUrl, apiKey=present" } else { "Need CONTEXTLATTICE_ORCHESTRATOR_URL and CONTEXTLATTICE_ORCHESTRATOR_API_KEY" }; LatencyMs = $null })
    & $OnCheckComplete $currentCheck $totalChecks "contextlattice_env" (if ($ctxEnvOk) { "OK" } else { "WARN" }) $checks[-1].Detail
    
    # Check 9: Provider key validation
    $currentCheck++
    & $OnCheckComplete $currentCheck $totalChecks "provider_key_valid" "PENDING" "Checking..."
    $keyValid = $false
    $keyLatency = 0
    if ($null -ne $providerResolved -and $providerResolved.ApiKeySet) {
        $apiKeyObj = Get-FirstEnvValue -Names $providerResolved.Profile.ApiKeyVars
        $apiKey = $apiKeyObj.Value
        $latencyRef = [ref]0
        $keyValid = Test-ProviderKey -ProviderProfile $providerResolved.Profile -ApiKey $apiKey -BaseUrl $providerResolved.BaseUrl -TimeoutSec $TimeoutSec -LatencyMs $latencyRef
        $keyLatency = $latencyRef.Value
    }
    $checks.Add([pscustomobject]@{ Name = "provider_key_valid"; Ok = $keyValid; Detail = if ($keyValid) { "Key validated for $($providerResolved.Profile.Name)" } else { "Key validation failed for $($providerResolved.Profile.Name)" }; LatencyMs = $keyLatency })
    & $OnCheckComplete $currentCheck $totalChecks "provider_key_valid" (if ($keyValid) { "OK" } else { "FAIL" }) $checks[-1].Detail $keyLatency
    
    # Context checks
    if ($CheckContext) {
        if ((-not [string]::IsNullOrWhiteSpace($ctxUrl)) -and $ctxKeySet) {
            $base = $ctxUrl.TrimEnd('/')
            
            # Check 10: ContextLattice health
            $currentCheck++
            & $OnCheckComplete $currentCheck $totalChecks "contextlattice_health" "PENDING" "Checking..."
            $healthStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $healthOk = $false
            $healthDetail = ""
            try {
                $health = Invoke-RestMethod -Method Get -Uri "$base/health" -TimeoutSec $TimeoutSec
                $healthStopwatch.Stop()
                $healthOk = ($health.ok -eq $true)
                $healthDetail = "$($ctxUrl)/health ok=$($health.ok)"
            } catch {
                $healthStopwatch.Stop()
                $healthOk = $false
                $healthDetail = $_.Exception.Message
            }
            $healthLatency = $healthStopwatch.ElapsedMilliseconds
            $checks.Add([pscustomobject]@{ Name = "contextlattice_health"; Ok = $healthOk; Detail = $healthDetail; LatencyMs = $healthLatency })
            & $OnCheckComplete $currentCheck $totalChecks "contextlattice_health" (if ($healthOk) { "OK" } else { "FAIL" }) $healthDetail $healthLatency
            
            # Check 11: ContextLattice status
            $currentCheck++
            & $OnCheckComplete $currentCheck $totalChecks "contextlattice_status" "PENDING" "Checking..."
            $statusStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $statusOk = $false
            $statusDetail = ""
            try {
                $headers = @{ "x-api-key" = $env:CONTEXTLATTICE_ORCHESTRATOR_API_KEY }
                $status = Invoke-RestMethod -Method Get -Uri "$base/status" -Headers $headers -TimeoutSec $TimeoutSec
                $statusStopwatch.Stop()
                $statusOk = $true
                $statusDetail = "service=contextlattice"
            } catch {
                $statusStopwatch.Stop()
                $statusOk = $false
                $statusDetail = $_.Exception.Message
            }
            $statusLatency = $statusStopwatch.ElapsedMilliseconds
            $checks.Add([pscustomobject]@{ Name = "contextlattice_status"; Ok = $statusOk; Detail = $statusDetail; LatencyMs = $statusLatency })
            & $OnCheckComplete $currentCheck $totalChecks "contextlattice_status" (if ($statusOk) { "OK" } else { "FAIL" }) $statusDetail $statusLatency
        } else {
            $currentCheck++
            & $OnCheckComplete $currentCheck $totalChecks "contextlattice_health" "WARN" "Missing context env vars; cannot run connectivity test."
            $checks.Add([pscustomobject]@{ Name = "contextlattice_health"; Ok = $false; Detail = "Missing context env vars; cannot run connectivity test."; LatencyMs = $null })
            
            $currentCheck++
            & $OnCheckComplete $currentCheck $totalChecks "contextlattice_status" "WARN" "Missing context env vars; cannot run connectivity test."
            $checks.Add([pscustomobject]@{ Name = "contextlattice_status"; Ok = $false; Detail = "Missing context env vars; cannot run connectivity test."; LatencyMs = $null })
        }
    }
    
    return @{
        Checks = $checks.ToArray()
        ProjectPath = $projectPath
        ProviderResolved = $providerResolved
    }
}

#endregion

#region Main Execution

$isInteractive = Test-InteractiveShell
$useAnsi = Test-AnsiSupport
$useColors = $isInteractive

# Non-interactive mode: just run checks and output plain text
if (-not $isInteractive) {
    $result = Invoke-DashboardCheck -ProjectRoot $ProjectRoot -Provider $Provider -CheckContext:$CheckContext -TimeoutSec $TimeoutSec -OnCheckComplete { param($c, $t, $n, $s, $d, $l) }
    Write-PlainTextReport -Checks $result.Checks -ProjectPath $result.ProjectPath -Provider $Provider -ProviderResolved $result.ProviderResolved
    $failed = @($result.Checks | Where-Object { -not $_.Ok })
    if ($failed.Count -gt 0) { exit 1 }
    exit 0
}

# Interactive dashboard mode
$checkResults = @{}
$autoRefresh = $false
$lastCheckTime = $null
$running = $true
$firstRun = $true

while ($running) {
    # Clear screen for refresh
    if (-not $firstRun) {
        Clear-Host
    }
    $firstRun = $false
    
    # Draw header
    Write-DashboardHeader -UseAnsi:$useAnsi -UseColors:$useColors
    Write-Host ""
    
    # Run checks if needed
    if ($lastCheckTime -eq $null -or $autoRefresh) {
        $checkResults = @{}
        $completedCount = 0
        
        $onComplete = {
            param($current, $total, $name, $status, $detail, $latency)
            $script:completedCount = $current
            $script:checkResults[$name] = @{
                Status = $status
                Detail = $detail
                LatencyMs = $latency
            }
        }
        
        # Show progress before detailed results
        if ($useAnsi -or $useColors) {
            Write-Host "Running checks..." -ForegroundColor Cyan
        }
    }
    
    # Execute checks
    $result = Invoke-DashboardCheck -ProjectRoot $ProjectRoot -Provider $Provider -CheckContext:$CheckContext -TimeoutSec $TimeoutSec -OnCheckComplete $onComplete
    $lastCheckTime = Get-Date
    
    # Display results
    Write-Host ""
    foreach ($check in $result.Checks) {
        $statusStr = if ($check.Ok) { "OK" } else { "FAIL" }
        # Determine if this is a warning case
        if (-not $check.Ok) {
            if ($check.Name -in @("python_version", "codemunch_version", "chromadb_version") -and $check.Detail -match "Found") {
                $statusStr = "WARN"
            }
            if ($check.Name -eq "contextlattice_env" -and $check.Detail -match "Need") {
                $statusStr = "WARN"
            }
        }
        Write-CheckResult -Name $check.Name -Status $statusStr -Detail $check.Detail -LatencyMs ($check.LatencyMs, 0 | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum) -UseAnsi:$useAnsi -UseColors:$useColors
    }
    
    # Calculate summary
    $passCount = @($result.Checks | Where-Object { $_.Ok }).Count
    $failCount = @($result.Checks | Where-Object { -not $_.Ok }).Count
    $warnCount = 0
    foreach ($check in $result.Checks | Where-Object { -not $_.Ok }) {
        if ($check.Name -in @("python_version", "codemunch_version", "chromadb_version") -and $check.Detail -match "Found") {
            $warnCount++
            $failCount--
        }
        if ($check.Name -eq "contextlattice_env" -and $check.Detail -match "Need") {
            $warnCount++
            $failCount--
        }
    }
    
    # Status message
    $statusMsg = "Last updated: $($lastCheckTime.ToString('HH:mm:ss'))"
    if ($autoRefresh) {
        $statusMsg += " | Auto-refresh: ON ($RefreshInterval sec)"
    } else {
        $statusMsg += " | Auto-refresh: OFF"
    }
    if ($result.ProviderResolved) {
        $statusMsg += " | Provider: $($result.ProviderResolved.Profile.Name)"
    }
    
    Write-Host ""
    Write-DashboardFooter -UseAnsi:$useAnsi -UseColors:$useColors -StatusMessage $statusMsg -PassCount $passCount -WarnCount $warnCount -FailCount $failCount
    
    # Wait for user input
    if ($autoRefresh -and $RefreshInterval -gt 0) {
        $timeout = $RefreshInterval * 1000
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $keyPressed = $false
        
        while ($stopwatch.ElapsedMilliseconds -lt $timeout -and -not $keyPressed) {
            if ($Host.UI.RawUI.KeyAvailable) {
                $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                $keyPressed = $true
                
                switch ($key.Character.ToString().ToUpper()) {
                    "Q" { $running = $false }
                    "R" { $lastCheckTime = $null; break }
                    "A" { $autoRefresh = -not $autoRefresh }
                }
            }
            Start-Sleep -Milliseconds 100
        }
        $stopwatch.Stop()
    } else {
        # Manual mode - wait for key press
        Write-Host ""
        Write-Host "Press a key..." -ForegroundColor Gray -NoNewline
        
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        switch ($key.Character.ToString().ToUpper()) {
            "Q" { $running = $false }
            "R" { $lastCheckTime = $null }
            "A" { $autoRefresh = -not $autoRefresh }
        }
    }
}

# Exit code
$failed = @($result.Checks | Where-Object { -not $_.Ok })
if ($failed.Count -gt 0) { exit 1 }
exit 0

#endregion

