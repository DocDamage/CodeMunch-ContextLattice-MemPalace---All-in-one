[CmdletBinding()]
param(
    [string]$ProjectRoot = ".",
    [ValidateSet("auto", "openai", "kimi", "gemini", "glm")]
    [string]$Provider = "auto",
    [switch]$CheckContext,
    [int]$TimeoutSec = 10,
    [switch]$AsJson,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"

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
}

function Test-PythonImport {
    param([string]$ImportName)

    $probe = "import importlib.util; print(bool(importlib.util.find_spec(r'$ImportName')))"
    $resultRaw = & python -c $probe 2>$null
    $result = if ($null -eq $resultRaw) { "" } else { ($resultRaw | Out-String).Trim() }
    return ($LASTEXITCODE -eq 0 -and $result -eq "True")
}

function Get-FirstEnvValue {
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

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
Import-EnvFile -Path (Join-Path $projectPath ".env")
Import-EnvFile -Path (Join-Path $projectPath ".contextlattice\orchestrator.env")

$checks = New-Object System.Collections.Generic.List[object]

$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
$checks.Add([pscustomobject]@{
    Name = "python_command"
    Ok = ($null -ne $pythonCmd)
    Detail = if ($pythonCmd) { $pythonCmd.Source } else { "Install Python and add `python` to PATH." }
})

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
})

$chromadbImport = $false
if ($pythonCmd) {
    $chromadbImport = Test-PythonImport -ImportName "chromadb"
}
$checks.Add([pscustomobject]@{
    Name = "chromadb_python_module"
    Ok = $chromadbImport
    Detail = if ($chromadbImport) { "chromadb import ok" } else { "Install with: python -m pip install --upgrade chromadb" }
})

$providerResolved = Resolve-ProviderProfile -RequestedProvider $Provider
if ($null -eq $providerResolved) {
    $checks.Add([pscustomobject]@{
        Name = "provider_credentials"
        Ok = $false
        Detail = "No provider key found. Set OPENAI_API_KEY, KIMI_API_KEY, GEMINI_API_KEY, or GLM_API_KEY in .env"
    })
} else {
    $baseSource = if ([string]::IsNullOrWhiteSpace($providerResolved.BaseUrlVar)) { "default" } else { $providerResolved.BaseUrlVar }
    $checks.Add([pscustomobject]@{
        Name = "provider_credentials"
        Ok = $providerResolved.ApiKeySet
        Detail = "provider=$($providerResolved.Profile.Name), apiKeyVar=$($providerResolved.ApiKeyVar), baseUrlSource=$baseSource"
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
})

if ($CheckContext) {
    $ctxCheckOk = $false
    $ctxDetail = "Skipped"
    if ((-not [string]::IsNullOrWhiteSpace($ctxUrl)) -and $ctxKeySet) {
        try {
            $base = $ctxUrl.TrimEnd('/')
            $health = Invoke-RestMethod -Method Get -Uri "$base/health" -TimeoutSec $TimeoutSec
            $headers = @{ "x-api-key" = $env:CONTEXTLATTICE_ORCHESTRATOR_API_KEY }
            $status = Invoke-RestMethod -Method Get -Uri "$base/status" -Headers $headers -TimeoutSec $TimeoutSec
            $ctxCheckOk = ($health.ok -eq $true)
            $ctxDetail = "health.ok=$($health.ok); status_authenticated=True"
        } catch {
            $ctxCheckOk = $false
            $ctxDetail = $_.Exception.Message
        }
    } else {
        $ctxDetail = "Missing context env vars; cannot run connectivity test."
    }

    $checks.Add([pscustomobject]@{
        Name = "contextlattice_connectivity"
        Ok = $ctxCheckOk
        Detail = $ctxDetail
    })
}

$failed = @($checks | Where-Object { -not $_.Ok })
$report = [pscustomobject]@{
    ProjectRoot = $projectPath
    ProviderRequested = $Provider
    ProviderResolved = if ($providerResolved) { $providerResolved.Profile.Name } else { "" }
    Checks = $checks
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
        Write-Output ("[{0}] {1}: {2}" -f $status, $check.Name, $check.Detail)
    }

    if ($failed.Count -eq 0) {
        Write-Output "[llm-workflow-doctor] all checks passed"
    } else {
        Write-Warning ("[llm-workflow-doctor] failed checks: {0}" -f ($failed.Name -join ", "))
    }
}

if ($Strict -and ($failed.Count -gt 0)) {
    exit 2
}

exit 0
