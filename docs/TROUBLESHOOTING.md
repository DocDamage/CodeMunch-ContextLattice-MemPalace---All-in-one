# Troubleshooting Guide

This guide helps you diagnose and resolve common issues with the CodeMunch + ContextLattice + MemPalace workflow toolkit.

---

## Table of Contents

1. [Quick Diagnostics](#quick-diagnostics)
2. [Common Issues](#common-issues)
3. [Error Messages Reference](#error-messages-reference)
4. [Diagnostic Commands](#diagnostic-commands)
5. [Getting Help](#getting-help)

---

## Quick Diagnostics

### Running llmcheck

The `llmcheck` command (alias for `Test-LLMWorkflowSetup`) performs a quick health check of your environment:

```powershell
# Basic check
llmcheck

# Include connectivity tests
llmcheck -CheckConnectivity

# Strict mode - throws on failure
llmcheck -Strict

# Machine-readable JSON output
llmcheck -AsJson | ConvertFrom-Json
```

**Interpreting Results:**

| Status | Meaning | Action |
|--------|---------|--------|
| `pass` | Check succeeded | None needed |
| `warn` | Non-critical issue | Review and fix when convenient |
| `fail` | Critical issue | Must fix before proceeding |

Example output:
```
project_root         : pass  C:\Projects\MyProject
tool_codemunch       : pass  Found C:\Projects\MyProject\tools\codemunch
env_file_root        : warn  Missing .env
contextlattice_url   : pass  http://127.0.0.1:8075
python_chromadb      : warn  chromadb import unavailable
```

### Using llmheal (Self-Healing)

The `llmheal` command automatically diagnoses and fixes common issues:

```powershell
# Interactive diagnosis with prompts
llmheal

# Preview what would be fixed (dry-run)
llmheal -WhatIf

# Auto-apply all fixes without prompting
llmheal -Force

# Fix only critical issues
llmheal -OnlyCritical -Force

# Include info-level issues
llmheal -IncludeInfo
```

**Auto-Fix Capabilities:**

| Issue | Fix Applied |
|-------|-------------|
| Missing .env file | Creates from template with prompts |
| Invalid Python path | Finds and configures correct Python |
| Missing ChromaDB | Runs `pip install chromadb` |
| Missing palace directory | Creates with default collection |
| Corrupted sync-state.json | Backs up and recreates |
| Template drift | Re-syncs from module templates |
| Missing ContextLattice API key | Prompts with secure masking |
| Missing bridge config | Creates default configuration |

See [Self-Healing Guide](SELF_HEALING.md) for complete documentation.

**Legacy bootstrap repair:**

```powershell
# Install missing dependencies
llmup -SkipContextVerify
```

### Verbose and Debug Output

Enable detailed logging for troubleshooting:

```powershell
# Module functions support -Verbose
Test-LLMWorkflowSetup -Verbose
Invoke-LLMWorkflowUp -Verbose

# For scripts, use -Debug
& tools/workflow/doctor-llm-workflow.ps1 -Debug
```

---

## Common Issues

### a. Python/Environment Issues

#### `chromadb` Import Fails

**Symptoms:**
- `python_chromadb` check shows `warn` or `fail`
- Error: `chromadb import unavailable`
- ImportError when running Python scripts

**Solutions:**

```powershell
# Install chromadb manually
python -m pip install --upgrade chromadb

# Verify installation
python -c "import chromadb; print(chromadb.__version__)"

# If using venv, activate it first
.\venv\Scripts\Activate.ps1
python -m pip install chromadb
```

#### Virtual Environment Activation

**Symptoms:**
- Python packages installed but not found
- ModuleNotFoundError for installed packages

**Solutions:**

```powershell
# Create venv (if not exists)
python -m venv venv

# Activate on Windows PowerShell
.\venv\Scripts\Activate.ps1

# Activate on Windows CMD
venv\Scripts\activate.bat

# Install requirements in venv
python -m pip install chromadb codemunch-pro
```

#### Multiple Python Versions

**Symptoms:**
- `python` command not found
- Wrong Python version being used
- Packages installed for wrong Python

**Solutions:**

```powershell
# Check which Python is being used
Get-Command python
python --version

# Use specific Python version
py -3.11 -m pip install chromadb
py -3.11 tools/memorybridge/sync-from-mempalace.ps1

# Add Python to PATH temporarily
$env:PATH = "C:\Python311;$env:PATH"

# Or permanently (requires new shell)
[Environment]::SetEnvironmentVariable("PATH", "C:\Python311;$env:PATH", "User")
```

**Required Python Version:** 3.10 or higher

#### Pip Package Not Found

**Symptoms:**
- `pip` command not recognized
- Package installation fails

**Solutions:**

```powershell
# Use python -m pip instead of pip directly
python -m pip install chromadb

# Upgrade pip first
python -m pip install --upgrade pip

# If behind proxy
python -m pip install --proxy http://proxy.company.com:8080 chromadb
```

---

### b. ContextLattice Connection Issues

#### Server Unreachable

**Symptoms:**
- `contextlattice_health` check fails
- Error: `Unable to connect to the remote server`
- Timeout errors

**Solutions:**

```powershell
# Check if ContextLattice is running
Invoke-RestMethod -Uri "http://127.0.0.1:8075/health" -TimeoutSec 5

# Check if port is listening
netstat -an | findstr 8075

# Test with curl (if available)
curl http://127.0.0.1:8075/health
```

**Common causes:**
1. **ContextLattice not running:** Start the orchestrator service
2. **Wrong port:** Default is 8075, check your configuration
3. **Firewall blocking:** Add exception for port 8075
4. **Different host:** If running remotely, update URL

#### Invalid API Key

**Symptoms:**
- `contextlattice_status` check fails
- HTTP 401 or 403 errors
- Authentication failures

**Solutions:**

```powershell
# Verify API key is set
$env:CONTEXTLATTICE_ORCHESTRATOR_API_KEY

# Check which env var is being used
doctor-llm-workflow.ps1 -CheckContext

# Set API key for current session
$env:CONTEXTLATTICE_ORCHESTRATOR_API_KEY = "your-api-key-here"

# Or set in .env file
"CONTEXTLATTICE_ORCHESTRATOR_API_KEY=your-key" | Out-File -Append .env
```

#### Wrong Base URL Configuration

**Symptoms:**
- Health check works but status check fails
- Connection to wrong server
- Invalid URL format errors

**Solutions:**

```powershell
# Verify URL format (should include protocol)
$env:CONTEXTLATTICE_ORCHESTRATOR_URL = "http://127.0.0.1:8075"

# Check current configuration
llmcheck | Select-String contextlattice_url

# Common mistakes to avoid:
# - Missing http:// or https://
# - Trailing slash (handled automatically, but check anyway)
# - Wrong port number
```

---

### c. MemPalace/ChromaDB Issues

#### Collection Not Found

**Symptoms:**
- Bridge sync shows `Collection does not exist`
- Empty results from ChromaDB queries
- First-time setup issues

**Solutions:**

```powershell
# Collection is created automatically on first use
# If missing, initialize MemPalace first

# Check palace path exists
Test-Path ~/.mempalace/palace

# List available collections (Python)
python -c "
import chromadb
client = chromadb.PersistentClient(path='~/.mempalace/palace')
print(client.list_collections())
"

# Create collection manually if needed
python -c "
import chromadb
client = chromadb.PersistentClient(path='~/.mempalace/palace')
collection = client.create_collection('mempalace_drawers')
print('Collection created')
"
```

#### Database Locked

**Symptoms:**
- Error: `database is locked`
- ChromaDB operations hang or fail
- Concurrent access errors

**Solutions:**

1. **Close other applications using the palace:**
   - Other PowerShell sessions
   - Python scripts
   - IDE extensions

2. **Check for zombie processes:**
   ```powershell
   Get-Process | Where-Object { $_.ProcessName -match "python" }
   ```

3. **Wait and retry:**
   ```powershell
   Start-Sleep -Seconds 5
   # Retry your operation
   ```

4. **If persistently locked:**
   ```powershell
   # Find and kill processes (use with caution)
   Get-Process python | Stop-Process -Force
   ```

#### Corrupted Palace Data

**Symptoms:**
- Unexpected errors from ChromaDB
- Missing or corrupted records
- Strange behavior from queries

**Solutions:**

```powershell
# Backup current palace
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
Copy-Item ~/.mempalace/palace "~/.mempalace/palace_backup_$timestamp" -Recurse

# Check ChromaDB integrity (Python)
python -c "
import chromadb
client = chromadb.PersistentClient(path='~/.mempalace/palace')
collections = client.list_collections()
for c in collections:
    col = client.get_collection(c.name)
    count = col.count()
    print(f'{c.name}: {count} items')
"

# If corrupted, restore from backup or recreate
# WARNING: This deletes all data
# Remove-Item ~/.mempalace/palace -Recurse -Force
```

---

### d. Provider/API Key Issues

#### Key Not Found

**Environment Variable Precedence:**

1. Process-level environment variables (highest priority)
2. `.env` file in project root
3. `.contextlattice/orchestrator.env`
4. User-level environment variables

**Symptoms:**
- `provider_credentials` check fails
- No provider detected
- API calls fail with authentication errors

**Solutions:**

```powershell
# Check current environment
Get-ChildItem Env: | Where-Object { $_.Name -like "*API_KEY*" }

# Set key for current session
$env:OPENAI_API_KEY = "sk-..."
$env:KIMI_API_KEY = "..."
$env:GEMINI_API_KEY = "..."
$env:GLM_API_KEY = "..."

# Create .env file
@"
OPENAI_API_KEY=sk-your-key-here
KIMI_API_KEY=your-kimi-key
"@ | Out-File -FilePath .env -Encoding UTF8
```

**Supported Providers and Key Variables:**

| Provider | API Key Variables | Base URL Variables |
|----------|-------------------|-------------------|
| OpenAI | `OPENAI_API_KEY` | `OPENAI_BASE_URL` |
| Kimi | `KIMI_API_KEY`, `MOONSHOT_API_KEY` | `KIMI_BASE_URL`, `MOONSHOT_BASE_URL` |
| Gemini | `GEMINI_API_KEY`, `GOOGLE_API_KEY` | `GEMINI_BASE_URL` |
| GLM | `GLM_API_KEY`, `ZHIPU_API_KEY` | `GLM_BASE_URL` |
| Claude | `ANTHROPIC_API_KEY`, `CLAUDE_API_KEY` | `ANTHROPIC_BASE_URL`, `CLAUDE_BASE_URL` |
| Ollama | `OLLAMA_API_KEY` | `OLLAMA_BASE_URL`, `OLLAMA_HOST` |

#### Invalid Key Format

**Symptoms:**
- Key validation fails
- HTTP 401 errors from provider
- Authentication rejected

**Solutions:**

```powershell
# Validate key format (OpenAI example)
$key = $env:OPENAI_API_KEY
if ($key -match "^sk-[a-zA-Z0-9]{20,}$") { "Valid format" } else { "Invalid format" }

# Test key with doctor script
doctor-llm-workflow.ps1 -Provider openai -Strict
```

#### Provider-Specific Errors

**OpenAI:**
```powershell
# Rate limiting - add delays between requests
Start-Sleep -Milliseconds 500

# Check quota
# Visit: https://platform.openai.com/account/usage
```

**Kimi:**
```powershell
# Default base URL
$env:KIMI_BASE_URL = "https://api.moonshot.cn/v1"
```

**GLM:**
```powershell
# GLM requires both API key AND base URL
$env:GLM_API_KEY = "your-key"
$env:GLM_BASE_URL = "https://open.bigmodel.cn/api/paas/v4"

# Check configuration
llmcheck | Select-String glm
```

---

### e. Sync Issues

#### Bridge Sync Failures

**Symptoms:**
- `MemPalace -> ContextLattice sync failed`
- Partial sync results
- Write failures

**Solutions:**

```powershell
# Run dry-run first to check connectivity
tools/memorybridge/sync-from-mempalace.ps1 -DryRun

# Check with verbose output
& tools/memorybridge/sync-from-mempalace.ps1 -DryRun -Verbose

# Verify ContextLattice connectivity first
Invoke-RestMethod -Uri "$env:CONTEXTLATTICE_ORCHESTRATOR_URL/health"
```

#### Partial Sync Recovery

**Symptoms:**
- Some records synced, others failed
- Intermittent failures
- Network timeout during sync

**Solutions:**

```powershell
# Retry with increased batch size
& tools/memorybridge/sync-from-mempalace.ps1 -BatchSize 100

# Force resync of all records
& tools/memorybridge/sync-from-mempalace.ps1 -ForceResync

# Check sync state
cat .memorybridge/sync-state.json | ConvertFrom-Json

# View sync history
cat .memorybridge/sync-history.jsonl
```

#### Duplicate Entries

**Symptoms:**
- Same content appears multiple times in ContextLattice
- Sync state not tracking correctly

**Solutions:**

```powershell
# Clear sync state to force full resync
Remove-Item .memorybridge/sync-state.json
& tools/memorybridge/sync-from-mempalace.ps1 -ForceResync

# Check for duplicate drawer IDs in palace
python -c "
import chromadb
client = chromadb.PersistentClient(path='~/.mempalace/palace')
collection = client.get_collection('mempalace_drawers')
results = collection.get()
ids = results['ids']
duplicates = [id for id in set(ids) if ids.count(id) > 1]
print(f'Duplicates: {duplicates}')
"
```

---

## Error Messages Reference

### PowerShell Module Errors

| Error | Meaning | Solution |
|-------|---------|----------|
| `Missing toolkit template` | Tool folder not found | Run `llmup` to scaffold tools |
| `Python command not found` | Python not in PATH | Install Python or add to PATH |
| `chromadb import unavailable` | ChromaDB not installed | `python -m pip install chromadb` |
| `No usable provider API key found` | Missing LLM provider credentials | Set API key in .env file |
| `Target module version already installed` | Version conflict | Use `-Force` to replace |

### ContextLattice Errors

| Error | Meaning | Solution |
|-------|---------|----------|
| `Unable to connect` | Server not running | Start ContextLattice orchestrator |
| `The remote server returned an error: (401)` | Invalid API key | Check `CONTEXTLATTICE_ORCHESTRATOR_API_KEY` |
| `The remote server returned an error: (404)` | Wrong endpoint URL | Verify `CONTEXTLATTICE_ORCHESTRATOR_URL` |
| `Smoke write returned ok=false` | Write operation failed | Check ContextLattice logs |
| `Search did not return results` | Indexing lag | Increase `ContextSearchAttempts` |

### ChromaDB Errors

| Error | Meaning | Solution |
|-------|---------|----------|
| `Collection does not exist` | First time setup | Create collection or run initialization |
| `database is locked` | Concurrent access | Close other applications |
| `No such file or directory` | Wrong palace path | Check `MEMPALACE_PALACE_PATH` |
| `Permission denied` | Access rights | Check folder permissions |

### Bridge Sync Errors

| Error | Meaning | Solution |
|-------|---------|----------|
| `Palace path does not exist` | Wrong path configuration | Set correct `--palace-path` |
| `Missing API key` | Auth not configured | Set `CONTEXTLATTICE_ORCHESTRATOR_API_KEY` |
| `ContextLattice status check failed` | Cannot connect to server | Verify server is running |
| `Writes failed: N` | Partial sync failure | Check logs and retry |

---

## Diagnostic Commands

### llmcheck -AsJson (Machine-Readable Status)

```powershell
# Get structured output for automation
$status = llmcheck -AsJson | ConvertFrom-Json

# Check specific components
if ($status.passed) { "All good" } else { "Issues found" }

# Count failures
$status.checks | Where-Object { $_.status -eq "fail" }

# Check specific component
$status.checks | Where-Object { $_.name -eq "python_chromadb" }
```

### llmcheck -Strict (Detailed Validation)

```powershell
# Exit with error code on any failure
llmcheck -Strict
$LASTEXITCODE  # Will be non-zero if any check failed

# Use in CI/CD pipelines
if (-not (llmcheck -Strict)) { throw "Setup validation failed" }
```

### Doctor Script with Specific Checks

```powershell
# Run full diagnostic with ContextLattice check
& tools/workflow/doctor-llm-workflow.ps1 -CheckContext -Strict

# Check specific provider
& tools/workflow/doctor-llm-workflow.ps1 -Provider kimi -CheckContext

# JSON output for parsing
$diag = & tools/workflow/doctor-llm-workflow.ps1 -CheckContext -AsJson | ConvertFrom-Json
$diag.Checks | Where-Object { -not $_.Ok }

# Custom timeout for slow connections
& tools/workflow/doctor-llm-workflow.ps1 -CheckContext -TimeoutSec 30
```

### Deep Check (End-to-End Validation)

```powershell
# Comprehensive validation
llm-workflow-check

# Or with the module
Invoke-LLMWorkflowUp -DeepCheck -FailIfContextMissing

# Skip dependency install if already done
llm-workflow-check -SkipDependencyInstall
```

---

## Getting Help

### Information to Include in Bug Reports

When reporting issues, please include:

1. **Environment Information:**
   ```powershell
   # Run and include output
   llmver
   python --version
   $PSVersionTable.PSVersion
   ```

2. **Diagnostic Results:**
   ```powershell
   # Save to file and attach
   & tools/workflow/doctor-llm-workflow.ps1 -CheckContext -AsJson > diagnostics.json
   ```

3. **Error Messages:**
   - Full error message (copy-paste)
   - Stack trace if available
   - Exit codes: `$LASTEXITCODE`

4. **Configuration (sanitized):**
   ```powershell
   # Show env vars without values
   Get-ChildItem Env: | Where-Object { 
       $_.Name -match "API_KEY|URL|PROVIDER" 
   } | Select-Object Name, @{N="Set";E={$_.Value -ne ""}}
   ```

### How to Collect Logs

```powershell
# Capture all output to file
llmup -Verbose *>&1 | Tee-Object -FilePath llmup.log

# Capture debug output
$DebugPreference = "Continue"
Invoke-LLMWorkflowUp -Verbose *>&1 | Out-File debug.log
$DebugPreference = "SilentlyContinue"

# View PowerShell error log
Get-Error | Select-Object -First 5

# Clear error log
$Error.Clear()
```

### Debug Mode Usage

```powershell
# Enable debug preference
$DebugPreference = "Continue"
$VerbosePreference = "Continue"

# Run commands
doctor-llm-workflow.ps1 -CheckContext

# Reset preferences
$DebugPreference = "SilentlyContinue"
$VerbosePreference = "SilentlyContinue"

# Or use inline
$DebugPreference = "Continue"; llmcheck; $DebugPreference = "SilentlyContinue"
```

### Common Diagnostic Patterns

```powershell
# Quick health check
function Test-MySetup {
    $checks = @()
    
    # Check Python
    $python = Get-Command python -ErrorAction SilentlyContinue
    $checks += [PSCustomObject]@{ Test = "Python"; Pass = ($null -ne $python); Info = $python.Source }
    
    # Check ChromaDB
    $chroma = python -c "import chromadb; print('ok')" 2>$null
    $checks += [PSCustomObject]@{ Test = "ChromaDB"; Pass = ($chroma -eq "ok"); Info = $chroma }
    
    # Check ContextLattice
    try {
        $health = Invoke-RestMethod "$env:CONTEXTLATTICE_ORCHESTRATOR_URL/health" -TimeoutSec 2
        $checks += [PSCustomObject]@{ Test = "ContextLattice"; Pass = $health.ok; Info = "Healthy" }
    } catch {
        $checks += [PSCustomObject]@{ Test = "ContextLattice"; Pass = $false; Info = $_.Exception.Message }
    }
    
    $checks | Format-Table
}

Test-MySetup
```

---

## Quick Reference Card

```powershell
# Emergency fixes
python -m pip install --upgrade chromadb codemunch-pro    # Reinstall dependencies
Remove-Item .memorybridge/sync-state.json -Force           # Reset sync state
$Error.Clear()                                             # Clear errors

# Useful one-liners
python -c "import chromadb; print(chromadb.__version__)"  # Check ChromaDB version
irm "$env:CONTEXTLATTICE_ORCHESTRATOR_URL/health"         # Quick health check
Get-Content .env                                          # View env file
```

---

*Last updated: 2026-04-11*
