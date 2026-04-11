Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try {
        return $listener.LocalEndpoint.Port
    } finally {
        $listener.Stop()
    }
}

function Start-MockContextLattice {
    param(
        [string]$StateFile,
        [string]$ApiKey
    )

    $port = Get-FreeTcpPort
    $serverScript = Join-Path $repoRoot "tests\helpers\mock_contextlattice_server.py"
    $args = @(
        $serverScript,
        "--port", "$port",
        "--api-key", $ApiKey,
        "--state-file", $StateFile
    )

    $proc = Start-Process -FilePath python -ArgumentList $args -PassThru -WindowStyle Hidden
    $baseUrl = "http://127.0.0.1:$port"

    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 150
        try {
            $health = Invoke-RestMethod -Method Get -Uri "$baseUrl/health" -TimeoutSec 2
            if ($health.ok) {
                $ready = $true
                break
            }
        } catch {
        }
    }
    if (-not $ready) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
        throw "Mock ContextLattice server did not become ready."
    }

    return [pscustomobject]@{
        Process = $proc
        BaseUrl = $baseUrl
    }
}

function Stop-MockContextLattice {
    param([System.Diagnostics.Process]$Process)
    if ($Process -and -not $Process.HasExited) {
        try {
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        } catch {
        }
    }
}

Describe "ContextLattice + MemPalace Integration" {
    It "runs contextlattice verify smoke test against mock server" {
        $python = Get-Command python -ErrorAction SilentlyContinue
        if (-not $python) {
            throw "python command is required for integration tests."
        }

        $apiKey = "integration-test-key"
        $stateFile = Join-Path $TestDrive "mock_state_verify.json"
        $mock = Start-MockContextLattice -StateFile $stateFile -ApiKey $apiKey
        try {
            $verifyScript = Join-Path $repoRoot "tools\contextlattice\verify.ps1"
            & $verifyScript `
                -OrchestratorUrl $mock.BaseUrl `
                -ApiKey $apiKey `
                -ProjectName "integration-project" `
                -SmokeTest `
                -RequireSearchHit `
                -SearchAttempts 4 `
                -SearchDelaySec 1 `
                -TimeoutSec 5

            $serverState = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
            @($serverState.writes).Count | Should Be 1
        } finally {
            Stop-MockContextLattice -Process $mock.Process
        }
    }

    It "runs mempalace bridge sync against mock server and writes memory" {
        $python = Get-Command python -ErrorAction SilentlyContinue
        if (-not $python) {
            throw "python command is required for integration tests."
        }

        $apiKey = "integration-test-key"
        $stateFile = Join-Path $TestDrive "mock_state_bridge.json"
        $mock = Start-MockContextLattice -StateFile $stateFile -ApiKey $apiKey
        try {
            $palacePath = Join-Path $TestDrive "palace"
            New-Item -ItemType Directory -Path $palacePath -Force | Out-Null

            $createCollectionScript = @'
import chromadb
import sys

path = sys.argv[1]
client = chromadb.PersistentClient(path=path)
name = "mempalace_drawers"
try:
    client.delete_collection(name)
except Exception:
    pass
col = client.create_collection(name)
col.add(
    ids=["drawer-1"],
    documents=["integration drawer content token_abc"],
    metadatas=[{"wing": "default_wing", "room": "room_a", "source_file": "sample.md"}],
)
print("ok")
'@
            $createCollectionScript | python - $palacePath | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to prepare mock MemPalace collection."
            }

            $syncScript = Join-Path $repoRoot "tools\memorybridge\sync-from-mempalace.ps1"
            & $syncScript `
                -ConfigPath (Join-Path $TestDrive "bridge.config.json") `
                -StatePath (Join-Path $TestDrive "sync-state.json") `
                -OrchestratorUrl $mock.BaseUrl `
                -ApiKey $apiKey `
                -PalacePath $palacePath `
                -CollectionName "mempalace_drawers" `
                -DefaultProjectName "integration-project" `
                -TopicPrefix "mempalace" `
                -ForceResync `
                -Strict

            $serverState = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
            @($serverState.writes).Count | Should Be 1
            $serverState.writes[0].topicPath | Should Match "^mempalace/"
            $serverState.writes[0].projectName | Should Be "integration-project"
        } finally {
            Stop-MockContextLattice -Process $mock.Process
        }
    }
}

