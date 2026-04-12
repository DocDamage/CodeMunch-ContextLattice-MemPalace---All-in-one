# LLM Workflow Dashboard

Interactive Terminal UI dashboard for monitoring LLM Workflow health.

## Overview

The dashboard provides a real-time, color-coded view of your workflow health checks with:

- **Color-coded status indicators** (Green=OK, Yellow=WARN, Red=FAIL)
- **Progress tracking** during check execution
- **Latency measurements** for network-dependent checks
- **Interactive controls** for re-running and auto-refresh
- **Fallback to plain text** for non-interactive environments

## Usage

### Launching the Dashboard

```powershell
# Using the module function
Show-LLMWorkflowDashboard

# Using the alias
llmdashboard

# Using the doctor script with dashboard mode
.\tools\workflow\doctor-llm-workflow.ps1 -Dashboard
```

### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ProjectRoot` | Path to project root | `.` |
| `Provider` | Provider to check (auto, openai, kimi, gemini, glm) | `auto` |
| `CheckContext` | Include ContextLattice connectivity checks | `$false` |
| `TimeoutSec` | Timeout for network checks | `10` |
| `NoInteractive` | Force plain-text output (for CI/CD) | `$false` |
| `RefreshInterval` | Auto-refresh interval in seconds (0=manual) | `0` |

### Examples

```powershell
# Basic interactive dashboard
Show-LLMWorkflowDashboard

# Check specific provider with ContextLattice connectivity
Show-LLMWorkflowDashboard -Provider kimi -CheckContext

# Auto-refresh every 30 seconds
Show-LLMWorkflowDashboard -RefreshInterval 30

# CI/CD friendly plain text output
Show-LLMWorkflowDashboard -NoInteractive

# Using with specific project root
Show-LLMWorkflowDashboard -ProjectRoot "C:\MyProject" -CheckContext
```

## Interactive Controls

When running in interactive mode:

| Key | Action |
|-----|--------|
| `R` | Re-run all checks immediately |
| `Q` | Quit the dashboard |
| `A` | Toggle auto-refresh mode |

## Display Format

```
========================================
   LLM WORKFLOW DASHBOARD v0.2.0
========================================

[OK]   python_command       Found: C:\Python311\python.exe
[OK]   python_version       3.11.4
[OK]   codemunch_runtime    command: C:\Python311\Scripts\codemunch-pro.exe
[OK]   codemunch_version    1.2.0
[OK]   chromadb_module      chromadb import ok
[WARN] chromadb_version     Found 0.4.24, need >= 0.5.0
[OK]   provider_credentials provider=openai, apiKeyVar=OPENAI_API_KEY, baseUrlSource=default
[WARN] contextlattice_env   Need CONTEXTLATTICE_ORCHESTRATOR_URL and CONTEXTLATTICE_ORCHESTRATOR_API_KEY
[OK]   provider_key_valid   Key validated for openai (245ms)

========================================
Summary: [OK: 7] [WARN: 2] [FAIL: 0]
Last updated: 14:32:15 | Auto-refresh: OFF | Provider: openai
========================================
Controls: [R]erun  [Q]uit  [A]uto-refresh
```

## Technical Details

### ANSI Escape Codes

The dashboard automatically detects ANSI support and uses:
- PowerShell 7.2+ built-in support
- Windows Terminal
- Consoles with `$env:TERM` set

For environments without ANSI support, it falls back to `Write-Host` with `-ForegroundColor`.

### Non-Interactive Mode

When running in CI/CD or non-interactive environments, the dashboard:
- Automatically detects non-interactive shells
- Outputs plain text via `Write-Output`
- Returns appropriate exit codes (0=all pass, 1=any fail)
- Respects the `-NoInteractive` switch to force this mode

### Performance

- Checks run sequentially to avoid overwhelming services
- Latency is measured for all network operations
- Progress updates happen in real-time as each check completes

## Troubleshooting

### Dashboard doesn't display colors

Ensure you're running in:
- Windows Terminal (recommended)
- PowerShell 7.2+ with `$env:TERM` set
- VS Code integrated terminal

### Auto-refresh not working

Auto-refresh requires the dashboard to be running in a proper interactive host:
```powershell
# Check your host
$Host.Name  # Should be "ConsoleHost"
```

### Keys not responding

The dashboard uses `$Host.UI.RawUI.ReadKey()` which requires:
- PowerShell ConsoleHost (not ISE)
- Interactive window (not piped/redirected input)

## Integration

### Azure DevOps / GitHub Actions

```yaml
- name: Run LLM Workflow Health Check
  shell: pwsh
  run: |
    Show-LLMWorkflowDashboard -NoInteractive
```

### Pre-commit Hook

```powershell
# In your pre-commit script
Import-Module LLMWorkflow
$result = Show-LLMWorkflowDashboard -NoInteractive
if ($LASTEXITCODE -ne 0) {
    Write-Error "Health checks failed"
    exit 1
}
```

### Scheduled Health Checks

```powershell
# Scheduled task script
$timestamp = Get-Date -Format "yyyy-MM-dd-HHmm"
$logFile = "logs\health-$timestamp.log"

Show-LLMWorkflowDashboard -NoInteractive | Tee-Object -FilePath $logFile

if ($LASTEXITCODE -ne 0) {
    Send-MailMessage -To "admin@example.com" -Subject "LLM Workflow Health Alert" -Body "Check logs at $logFile"
}
```
