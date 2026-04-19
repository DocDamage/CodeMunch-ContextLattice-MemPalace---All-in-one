[CmdletBinding()]
param(
    [string]$ProjectRoot = ".",
    [ValidateSet("auto", "openai", "kimi", "gemini", "glm")]
    [string]$Provider = "auto",
    [switch]$CheckContext,
    [int]$TimeoutSec = 10,
    [switch]$AsJson,
    [switch]$Strict,
    [switch]$Dashboard
)

$ErrorActionPreference = "Stop"

# Launch dashboard mode if requested
if ($Dashboard) {
    $modulePath = Join-Path $PSScriptRoot "..\..\module\LLMWorkflow\LLMWorkflow.Dashboard.ps1"
    if (-not (Test-Path -LiteralPath $modulePath)) {
        # Try alternative path resolution
        $modulePath = Join-Path (Get-Location).Path "module\LLMWorkflow\LLMWorkflow.Dashboard.ps1"
    }
    if (Test-Path -LiteralPath $modulePath) {
        & $modulePath -ProjectRoot $ProjectRoot -Provider $Provider -CheckContext:$CheckContext -TimeoutSec $TimeoutSec
        exit $LASTEXITCODE
    } else {
        Write-Error "Dashboard script not found. Ensure the LLMWorkflow module is installed."
        exit 1
    }
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
    param(
        [string]$Version,
        [string]$Minimum
    )

    if ([string]::IsNullOrWhiteSpace($Version) -or $Version -eq "unknown") {
        return $false
    }
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
        [Parameter(Mandatory=$true)]
        [hashtable]$ProviderProfile,
        [Parameter(Mandatory=$true)]
        [string]$ApiKey,
        [Parameter(Mandatory=$true)]
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
            "openai" {
                $response = Invoke-RestMethod -Method Get -Uri "$BaseUrl/models" -Headers $headers -TimeoutSec $TimeoutSec
                $stopwatch.Stop()
                if ($LatencyMs) { $LatencyMs.Value = $stopwatch.ElapsedMilliseconds }
                return $true
            }
            "kimi" {
                $response = Invoke-RestMethod -Method Get -Uri "$BaseUrl/models" -Headers $headers -TimeoutSec $TimeoutSec
                $stopwatch.Stop()
                if ($LatencyMs) { $LatencyMs.Value = $stopwatch.ElapsedMilliseconds }
                return $true
            }
            "gemini" {
                $response = Invoke-RestMethod -Method Get -Uri "$BaseUrl/models" -Headers $headers -TimeoutSec $TimeoutSec
                $stopwatch.Stop()
                if ($LatencyMs) { $LatencyMs.Value = $stopwatch.ElapsedMilliseconds }
                return $true
            }
            "glm" {
                $body = @{
                    model = "glm-4-flash"
                    messages = @(@{ role = "user"; content = "Hi" })
                    max_tokens = 1
                } | ConvertTo-Json -Depth 4
                $response = Invoke-RestMethod -Method Post -Uri "$BaseUrl/chat/completions" -Headers $headers -Body $body -TimeoutSec $TimeoutSec
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

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
Import-EnvFile -Path (Join-Path $projectPath ".env")
Import-EnvFile -Path (Join-Path $projectPath ".contextlattice" "orchestrator.env")

$checks = New-Object System.Collections.Generic.List[object]

$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
$checks.Add([pscustomobject]@{
    Name = "python_command"
    Ok = ($null -ne $pythonCmd)
    Detail = if ($pythonCmd) { $pythonCmd.Source } else { "Install Python and add python to PATH." }
    LatencyMs = $null
})

# Python version check
$pythonVersion = $null
if ($pythonCmd) {
    $pythonVersion = Get-PythonVersion
}
$minPython = "3.10.0"
$pythonVersionOk = Test-VersionMeetsMinimum -Version $pythonVersion -Minimum $minPython
if ($pythonVersion) {
    $checks.Add([pscustomobject]@{
        Name = "python_version"
        Ok = $pythonVersionOk
        Detail = if ($pythonVersionOk) { $pythonVersion } else { "Found $pythonVersion, need >= $minPython" }
        LatencyMs = $null
    })
} else {
    $checks.Add([pscustomobject]@{
        Name = "python_version"
        Ok = $false
        Detail = "Not installed"
        LatencyMs = $null
    })
}

$codemunchCmd = Get-Command codemunch-pro -ErrorAction SilentlyContinue
$codemunchImport = $false
if ($pythonCmd) {
    $codemunchImport = Test-PythonImport -ImportName "codemunch_pro"
}
$checks.Add([pscustomobject]@{
    Name = "codemunch_runtime"
    Ok = ($null -ne $codemunchCmd) -or $codemunchImport
    Detail = if ($codemunchCmd) {
        "command: $($codemunchCmd.Source)"
    } elseif ($codemunchImport) {
        "python module codemunch_pro is importable"
    } else {
        "Install with: python -m pip install --upgrade codemunch-pro"
    }
    LatencyMs = $null
})

# codemunch-pro version check
$codemunchVersion = $null
if ($codemunchImport) {
    $codemunchVersion = Get-PythonPackageVersion -ImportName "codemunch_pro"
}
$minCodemunch = "1.0.0"
$codemunchVersionOk = Test-VersionMeetsMinimum -Version $codemunchVersion -Minimum $minCodemunch
if ($codemunchVersion) {
    $checks.Add([pscustomobject]@{
        Name = "codemunch_version"
        Ok = $codemunchVersionOk
        Detail = if ($codemunchVersionOk) { $codemunchVersion } else { "Found $codemunchVersion, need >= $minCodemunch" }
        LatencyMs = $null
    })
} else {
    $checks.Add([pscustomobject]@{
        Name = "codemunch_version"
        Ok = $false
        Detail = "Not installed"
        LatencyMs = $null
    })
}

$chromadbImport = $false
if ($pythonCmd) {
    $chromadbImport = Test-PythonImport -ImportName "chromadb"
}
$checks.Add([pscustomobject]@{
    Name = "chromadb_python_module"
    Ok = $chromadbImport
    Detail = if ($chromadbImport) { "chromadb import ok" } else { "Install with: python -m pip install --upgrade chromadb" }
    LatencyMs = $null
})

# chromadb version check
$chromadbVersion = $null
if ($chromadbImport) {
    $chromadbVersion = Get-PythonPackageVersion -ImportName "chromadb"
}
$minChromadb = "0.5.0"
$chromadbVersionOk = Test-VersionMeetsMinimum -Version $chromadbVersion -Minimum $minChromadb
if ($chromadbVersion) {
    $checks.Add([pscustomobject]@{
        Name = "chromadb_version"
        Ok = $chromadbVersionOk
        Detail = if ($chromadbVersionOk) { $chromadbVersion } else { "Found $chromadbVersion, need >= $minChromadb" }
        LatencyMs = $null
    })
} else {
    $checks.Add([pscustomobject]@{
        Name = "chromadb_version"
        Ok = $false
        Detail = "Not installed"
        LatencyMs = $null
    })
}

$providerResolved = Resolve-ProviderProfile -RequestedProvider $Provider
if ($null -eq $providerResolved) {
    $checks.Add([pscustomobject]@{
        Name = "provider_credentials"
        Ok = $false
        Detail = "No provider key found. Set OPENAI_API_KEY, KIMI_API_KEY, GEMINI_API_KEY, or GLM_API_KEY in .env"
        LatencyMs = $null
    })
} else {
    $baseSource = if ([string]::IsNullOrWhiteSpace($providerResolved.BaseUrlVar)) { "default" } else { $providerResolved.BaseUrlVar }
    $checks.Add([pscustomobject]@{
        Name = "provider_credentials"
        Ok = $providerResolved.ApiKeySet
        Detail = "provider=$($providerResolved.Profile.Name), apiKeyVar=$($providerResolved.ApiKeyVar), baseUrlSource=$baseSource"
        LatencyMs = $null
    })
}

$ctxUrl = $env:CONTEXTLATTICE_ORCHESTRATOR_URL
$ctxKeySet = -not [string]::IsNullOrWhiteSpace($env:CONTEXTLATTICE_ORCHESTRATOR_API_KEY)
$checks.Add([pscustomobject]@{
    Name = "contextlattice_env"
    Ok = (-not [string]::IsNullOrWhiteSpace($ctxUrl)) -and $ctxKeySet
    Detail = if ((-not [string]::IsNullOrWhiteSpace($ctxUrl)) -and $ctxKeySet) {
        "url=$ctxUrl, apiKey=present"
    } else {
        "Need CONTEXTLATTICE_ORCHESTRATOR_URL and CONTEXTLATTICE_ORCHESTRATOR_API_KEY"
    }
    LatencyMs = $null
})

if ($CheckContext) {
    if ((-not [string]::IsNullOrWhiteSpace($ctxUrl)) -and $ctxKeySet) {
        $base = $ctxUrl.TrimEnd('/')
        
        # Health check with latency
        $healthStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $healthOk = $false
        $healthDetail = ""
        try {
            $health = Invoke-RestMethod -Method Get -Uri "$base/health" -TimeoutSec $TimeoutSec
            $healthStopwatch.Stop()
            $healthOk = ($health.ok -eq $true)
            $healthDetail = "127.0.0.1:8075/health ok=$($health.ok)"
        } catch {
            $healthStopwatch.Stop()
            $healthOk = $false
            $healthDetail = $_.Exception.Message
        }
        $healthLatency = $healthStopwatch.ElapsedMilliseconds
        
        $checks.Add([pscustomobject]@{
            Name = "contextlattice_health"
            Ok = $healthOk
            Detail = $healthDetail
            LatencyMs = $healthLatency
        })
        
        # Status check with latency
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
        
        $checks.Add([pscustomobject]@{
            Name = "contextlattice_status"
            Ok = $statusOk
            Detail = $statusDetail
            LatencyMs = $statusLatency
        })
    } else {
        $checks.Add([pscustomobject]@{
            Name = "contextlattice_health"
            Ok = $false
            Detail = "Missing context env vars; cannot run connectivity test."
            LatencyMs = $null
        })
        $checks.Add([pscustomobject]@{
            Name = "contextlattice_status"
            Ok = $false
            Detail = "Missing context env vars; cannot run connectivity test."
            LatencyMs = $null
        })
    }
}

# Provider key validation with latency
if ($null -ne $providerResolved -and $providerResolved.ApiKeySet) {
    $apiKeyObj = Get-FirstEnvValue -Names $providerResolved.Profile.ApiKeyVars
    $apiKey = $apiKeyObj.Value
    $latencyRef = [ref]0
    
    $keyValid = Test-ProviderKey -ProviderProfile $providerResolved.Profile -ApiKey $apiKey -BaseUrl $providerResolved.BaseUrl -TimeoutSec $TimeoutSec -LatencyMs $latencyRef
    
    $checks.Add([pscustomobject]@{
        Name = "provider_key_valid"
        Ok = $keyValid
        Detail = if ($keyValid) { "Key validated for $($providerResolved.Profile.Name)" } else { "Key validation failed for $($providerResolved.Profile.Name)" }
        LatencyMs = $latencyRef.Value
    })
}

$failed = @($checks | Where-Object { -not $_.Ok })

# Build report with latency for JSON output
$checkObjects = foreach ($check in $checks) {
    $obj = [ordered]@{
        Name = $check.Name
        Ok = $check.Ok
        Detail = $check.Detail
    }
    if ($check.LatencyMs -ne $null) {
        $obj['latencyMs'] = $check.LatencyMs
    }
    [pscustomobject]$obj
}

$report = [pscustomobject]@{
    ProjectRoot = $projectPath
    ProviderRequested = $Provider
    ProviderResolved = if ($providerResolved) { $providerResolved.Profile.Name } else { "" }
    Checks = $checkObjects
    Success = ($failed.Count -eq 0)
}

if ($AsJson) {
    $report | ConvertTo-Json -Depth 8
} else {
    Write-Output "[llm-workflow-doctor] project=$projectPath"
    Write-Output "[llm-workflow-doctor] provider.requested=$Provider"
    if ($providerResolved) {
        Write-Output "[llm-workflow-doctor] provider.resolved=$($providerResolved.Profile.Name)"
    }

    foreach ($check in $checks) {
        $status = if ($check.Ok) { "OK" } else { "FAIL" }
        if ($check.LatencyMs -ne $null) {
            Write-Output ("[{0}] {1}: {2} ({3}ms)" -f $status, $check.Name, $check.Detail, $check.LatencyMs)
        } else {
            Write-Output ("[{0}] {1}: {2}" -f $status, $check.Name, $check.Detail)
        }
    }

    if ($failed.Count -eq 0) {
        Write-Output "[llm-workflow-doctor] all checks passed"
    } else {
        Write-Warning ("[llm-workflow-doctor] failed checks: {0}" -f ($failed.Name -join ", "))
    }
}

# Execute plugin checks
$pluginResults = @()
$pluginManifestPath = Join-Path $projectPath ".llm-workflow" "plugins.json"
if (Test-Path -LiteralPath $pluginManifestPath) {
    Write-Output "[llm-workflow-doctor] checking plugins..."
    try {
        $pluginContent = Get-Content -LiteralPath $pluginManifestPath -Raw -Encoding UTF8
        $pluginManifest = $pluginContent | ConvertFrom-Json -ErrorAction Stop
        if ($pluginManifest.plugins -and $pluginManifest.plugins.Count -gt 0) {
            $checkPlugins = @($pluginManifest.plugins | Where-Object { $_.runOn -contains "check" })
            foreach ($plugin in $checkPlugins) {
                if (-not $plugin.checkScript) {
                    $checks.Add([pscustomobject]@{
                        Name = "plugin_$($plugin.name)_check"
                        Ok = $false
                        Detail = "Plugin has no checkScript defined"
                        LatencyMs = $null
                    })
                    continue
                }
                $scriptPath = Join-Path $projectPath $plugin.checkScript
                if (-not (Test-Path -LiteralPath $scriptPath)) {
                    $checks.Add([pscustomobject]@{
                        Name = "plugin_$($plugin.name)_check"
                        Ok = $false
                        Detail = "Check script not found: $($plugin.checkScript)"
                        LatencyMs = $null
                    })
                    continue
                }
                $pluginStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $pluginOk = $false
                $pluginDetail = ""
                try {
                    $global:LASTEXITCODE = 0
                    $pluginOutput = & $scriptPath -ProjectRoot $projectPath 2>&1
                    $exitCode = $global:LASTEXITCODE
                    $pluginStopwatch.Stop()
                    if ($exitCode -eq 0) {
                        $pluginOk = $true
                        $pluginDetail = "Plugin check passed"
                    }
                    else {
                        $pluginDetail = "Plugin check failed (exit code $exitCode)"
                    }
                }
                catch {
                    $pluginStopwatch.Stop()
                    $pluginDetail = "Plugin check error: $($_.Exception.Message)"
                }
                $checks.Add([pscustomobject]@{
                    Name = "plugin_$($plugin.name)_check"
                    Ok = $pluginOk
                    Detail = $pluginDetail
                    LatencyMs = $pluginStopwatch.ElapsedMilliseconds
                })
            }
        }
    }
    catch {
        $checks.Add([pscustomobject]@{
            Name = "plugin_manifest"
            Ok = $false
            Detail = "Failed to parse plugin manifest: $($_.Exception.Message)"
            LatencyMs = $null
        })
    }
}

# Recalculate failed after plugin checks
$failed = @($checks | Where-Object { -not $_.Ok })

if ($Strict -and ($failed.Count -gt 0)) {
    exit 2
}

exit 0
