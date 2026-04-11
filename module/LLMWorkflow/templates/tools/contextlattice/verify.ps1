param(
    [string]$OrchestratorUrl = "",
    [string]$ApiKey = "",
    [string]$ProjectName = "",
    [switch]$SmokeTest,
    [switch]$RequireSearchHit,
    [int]$SearchAttempts = 20,
    [int]$SearchDelaySec = 1,
    [int]$TimeoutSec = 20
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OrchestratorUrl)) {
    $OrchestratorUrl = $env:CONTEXTLATTICE_ORCHESTRATOR_URL
}
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $ApiKey = $env:CONTEXTLATTICE_ORCHESTRATOR_API_KEY
}
if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    if (-not [string]::IsNullOrWhiteSpace($env:CONTEXTLATTICE_PROJECT_NAME)) {
        $ProjectName = $env:CONTEXTLATTICE_PROJECT_NAME
    } else {
        $ProjectName = Split-Path -Leaf (Get-Location)
    }
}

if ([string]::IsNullOrWhiteSpace($OrchestratorUrl)) {
    throw "Missing OrchestratorUrl. Set -OrchestratorUrl or CONTEXTLATTICE_ORCHESTRATOR_URL."
}
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "Missing ApiKey. Set -ApiKey or CONTEXTLATTICE_ORCHESTRATOR_API_KEY."
}

$base = $OrchestratorUrl.TrimEnd('/')
$headers = @{ "x-api-key" = $ApiKey }

Write-Output "Checking ContextLattice health at $base ..."
$health = Invoke-RestMethod -Method Get -Uri "$base/health" -TimeoutSec $TimeoutSec
Write-Output ("health.ok={0}" -f $health.ok)

Write-Output "Checking authenticated status ..."
$status = Invoke-RestMethod -Method Get -Uri "$base/status" -Headers $headers -TimeoutSec $TimeoutSec
if ($status.service) {
    Write-Output ("status.service={0}" -f $status.service)
}
if ($status.sinks) {
    Write-Output ("status.sinks={0}" -f (($status.sinks | ConvertTo-Json -Compress)))
}

if ($SmokeTest) {
    $now = (Get-Date).ToUniversalTime().ToString("o")
    $token = [Guid]::NewGuid().ToString("N")

    Write-Output "Running memory smoke write ..."
    $writeBody = @{
        projectName = $ProjectName
        fileName = "notes/$token.md"
        content = "ContextLattice smoke write token=$token from $ProjectName at $now"
        topicPath = "runbooks/retrieval"
    } | ConvertTo-Json

    $writeResult = Invoke-RestMethod `
        -Method Post `
        -Uri "$base/memory/write" `
        -Headers ($headers + @{ "content-type" = "application/json" }) `
        -Body $writeBody `
        -TimeoutSec $TimeoutSec

    Write-Output ("memory.write.ok={0}" -f $writeResult.ok)
    if (-not $writeResult.ok) {
        throw "Smoke write returned ok=false."
    }

    Write-Output "Running memory smoke search ..."
    $searchBody = @{
        project = $ProjectName
        query = $token
        topic_path = "runbooks/retrieval"
        include_grounding = $true
    } | ConvertTo-Json

    $searchCount = 0
    $attempt = 0
    $maxAttempts = [Math]::Max(1, $SearchAttempts)
    while ($attempt -lt $maxAttempts) {
        $searchResult = Invoke-RestMethod `
            -Method Post `
            -Uri "$base/memory/search" `
            -Headers ($headers + @{ "content-type" = "application/json" }) `
            -Body $searchBody `
            -TimeoutSec $TimeoutSec

        $searchCount = if ($searchResult.results) { $searchResult.results.Count } else { 0 }
        if ($searchCount -gt 0) {
            break
        }

        Start-Sleep -Seconds ([Math]::Max(1, $SearchDelaySec))
        $attempt++
    }

    Write-Output ("memory.search.results={0}" -f $searchCount)
    if ($searchCount -eq 0) {
        $message = "Smoke write succeeded, but search did not return the just-written token within retry window. This can happen with async indexing lag."
        if ($RequireSearchHit) {
            throw $message
        }
        Write-Warning $message
        Write-Output "memory.search.eventual=false"
    } else {
        Write-Output "memory.search.eventual=true"
    }
}

Write-Output "ContextLattice verification complete."
