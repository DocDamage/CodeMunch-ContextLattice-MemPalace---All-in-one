# Self-Healing Guide (llmheal)

The `llmheal` command provides automatic diagnosis and repair capabilities for common LLM Workflow issues.

## Related Docs
- [Troubleshooting Guide](./TROUBLESHOOTING.md)
- [Recovery Playbooks](./RECOVERY_PLAYBOOKS.md)
- [Implementation Progress](../implementation/PROGRESS.md)
- [Remaining Work](../implementation/REMAINING_WORK.md)

## Quick Start

```powershell
# Interactive diagnosis and repair
llmheal

# Preview what would be fixed (dry-run)
llmheal -WhatIf

# Auto-apply all fixes without prompting
llmheal -Force

# Fix only critical issues
llmheal -OnlyCritical -Force
```

## Features

### Auto-Fix Capabilities

| Issue | Detection | Repair Action |
|-------|-----------|---------------|
| **Missing .env file** | Checks for `.env` in project root | Creates from template with all standard variables |
| **Invalid Python path** | Verifies `python` command availability | Searches common locations and adds to PATH |
| **Missing ChromaDB** | Tests Python import of `chromadb` | Runs `pip install chromadb` |
| **Missing palace directory** | Checks `~/.mempalace/palace` | Creates directory with default collection |
| **Corrupted sync-state.json** | Validates JSON syntax | Backs up and recreates with defaults |
| **Template drift** | Compares tool folders to module templates | Re-syncs missing templates |
| **Missing ContextLattice API key** | Checks environment and `.env` file | Prompts with secure input masking |
| **Missing bridge config** | Checks `.memorybridge/bridge.config.json` | Creates default configuration |
| **Corrupted bridge config** | Validates JSON syntax | Backs up and recreates with defaults |

### Issue Categories

Issues are classified into three severity levels:

- **CRITICAL** (Red): Must be fixed for basic functionality
  - Missing Python
  - Missing ContextLattice API key
  - Corrupted configuration files

- **WARNING** (Yellow): Should be fixed for full functionality
  - Missing ChromaDB
  - Missing palace directory
  - Missing .env file

- **INFO** (Cyan): Optional improvements
  - Template drift
  - Missing non-essential configuration

## Usage Modes

### Interactive Mode (Default)

```powershell
llmheal
```

1. Shows diagnosis with color-coded status
2. Prompts Y/n for each fixable issue
3. Applies fixes one at a time
4. Shows detailed progress and results

### WhatIf Mode (Dry-Run)

```powershell
llmheal -WhatIf
```

- No actual changes made
- Shows what would be fixed
- Useful for auditing before repair

### Force Mode (Unattended)

```powershell
llmheal -Force
```

- Auto-applies all fixes without prompting
- Useful for CI/CD pipelines
- Creates default configurations where needed

### Combined Options

```powershell
# Only critical issues, auto-fix
llmheal -OnlyCritical -Force

# Include INFO-level issues
llmheal -IncludeInfo

# Check specific issue types only
llmheal -IssueTypes MissingEnvFile, MissingChromaDB
```

## Individual Repair Functions

For programmatic use or targeted repairs:

### Test-LLMWorkflowIssue

Detects a specific issue type:

```powershell
# Test for missing .env file
$result = Test-LLMWorkflowIssue -IssueType MissingEnvFile
$result.Detected    # $true if issue found
$result.Category    # CRITICAL, WARNING, or INFO
$result.Message     # Human-readable description
$result.CanFix      # Whether auto-fix is available
```

### Repair-LLMWorkflowIssue

Repairs a specific issue:

```powershell
# Repair missing ChromaDB
Repair-LLMWorkflowIssue -IssueType MissingChromaDB -Force

# Preview repair (WhatIf)
Repair-LLMWorkflowIssue -IssueType MissingEnvFile -WhatIf
```

### Get-LLMWorkflowRepairHistory

Shows past repair operations:

```powershell
# Show last 50 repairs
Get-LLMWorkflowRepairHistory

# Show last 10 repairs
Get-LLMWorkflowRepairHistory -Count 10

# Show repairs from past week
Get-LLMWorkflowRepairHistory -Since (Get-Date).AddDays(-7)

# Filter by issue type
Get-LLMWorkflowRepairHistory -IssueType MissingEnvFile, MissingChromaDB

# Export to file
Get-LLMWorkflowRepairHistory | Export-Csv repairs.csv
```

### Clear-LLMWorkflowRepairHistory

Clears the repair history:

```powershell
Clear-LLMWorkflowRepairHistory -Confirm
```

### Export-LLMWorkflowRepairHistory

Exports history to JSON or CSV:

```powershell
# Export to JSON
Export-LLMWorkflowRepairHistory -OutputPath repairs.json

# Export to CSV
Export-LLMWorkflowRepairHistory -OutputPath repairs.csv -Format csv
```

## Sample Output

### Interactive Mode

```
========================================
   LLM Workflow Self-Healing
========================================

Project: C:\Projects\MyApp
Mode: Interactive

Phase 1: Diagnosis
------------------
  Checking MissingEnvFile... OK
  Checking InvalidPythonPath... OK
  Checking MissingChromaDB... [WARNING] ChromaDB module not installed
  Checking MissingPalaceDirectory... [WARNING] Missing palace directory: ~/.mempalace/palace
  Checking CorruptedSyncState... OK
  Checking TemplateDrift... OK
  Checking MissingContextLatticeApiKey... [CRITICAL] ContextLattice API key not configured
  Checking MissingContextLatticeUrl... OK
  Checking MissingBridgeConfig... OK
  Checking CorruptedBridgeConfig... OK

Diagnosis Summary:
  Critical issues: 1
  Warnings: 2
  Info: 0
  Auto-fixable: 3

Phase 2: Repair
---------------

Issue: MissingContextLatticeApiKey
Description: ContextLattice API key not configured
Proposed fix: Prompt for API key with masking
Apply fix? [Y/n]: y
  Fixing MissingContextLatticeApiKey... FIXED

Issue: MissingChromaDB
Description: ChromaDB module not installed
Proposed fix: Install ChromaDB via pip
Apply fix? [Y/n]: y
  Fixing MissingChromaDB... FIXED

Issue: MissingPalaceDirectory
Description: Missing palace directory: ~/.mempalace/palace
Proposed fix: Create palace directory with default collection
Apply fix? [Y/n]: y
  Fixing MissingPalaceDirectory... FIXED

========================================
   Repair Summary
========================================

Total issues found: 3
  Fixed: 3
  Failed: 0
  Skipped: 0

Duration: 00:15
```

### WhatIf Mode

```
Phase 2: Repair
---------------

[WHATIF] Would fix: MissingChromaDB - Install ChromaDB via pip
[WHATIF] Would fix: MissingPalaceDirectory - Create palace directory with default collection

========================================
   Repair Summary
========================================

Total issues found: 2
  Fixed: 0 (WhatIf mode)
  Failed: 0
  Skipped: 0
```

## History and Logging

### History File

Repair operations are logged to:
- Windows: `%USERPROFILE%\.llm-workflow\heal-history.jsonl`
- Linux/Mac: `~/.llm-workflow/heal-history.jsonl`

Each entry includes:
- Timestamp (UTC)
- Operation type
- Issue type
- Status (Success/Failed)
- Details
- Project root
- Whether it was a WhatIf operation

### Log File

Detailed logs are written to:
- Windows: `%USERPROFILE%\.llm-workflow\heal-log.txt`
- Linux/Mac: `~/.llm-workflow/heal-log.txt`

## Safety Features

1. **Backups Created**: Before modifying any existing file, a timestamped backup is created
2. **WhatIf Support**: All destructive operations support `-WhatIf` for preview
3. **Confirmation Prompts**: Interactive mode prompts before each fix
4. **Graceful Degradation**: Continues checking even if one test fails
5. **Idempotent Operations**: Running heal multiple times is safe

## CI/CD Integration

```yaml
# .github/workflows/heal-check.yml
name: LLM Workflow Health Check

on: [push, pull_request]

jobs:
  heal:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install LLM Workflow Module
        run: |
          Install-Module LLMWorkflow -Scope CurrentUser -Force
          Import-Module LLMWorkflow
      
      - name: Run Self-Healing (WhatIf)
        run: |
          $result = Invoke-LLMWorkflowHeal -WhatIf
          if ($result.IssuesFound -gt 0) {
            Write-Host "Issues found that would be fixed: $($result.IssuesFound)"
          }
      
      - name: Apply Fixes
        run: |
          $result = Invoke-LLMWorkflowHeal -Force -OnlyCritical
          if (-not $result.Success) {
            throw "Critical issues could not be fixed"
          }
```

## Troubleshooting

### Heal Can't Find Python

If Python is installed but not found:

```powershell
# Add Python to PATH manually
$env:PATH = "C:\Python311;$env:PATH"

# Then run heal
llmheal
```

### API Key Prompt Hangs in Non-Interactive Mode

Use `-Force` to use placeholder values, or pre-configure the `.env` file:

```powershell
# Option 1: Use placeholder
llmheal -Force

# Option 2: Pre-configure
"CONTEXTLATTICE_ORCHESTRATOR_API_KEY=your-key" | Out-File .env
llmheal
```

### Repair History Too Large

The history is automatically trimmed to the last 1000 entries. To clear manually:

```powershell
Clear-LLMWorkflowRepairHistory -Confirm
```

---

*See also: [Troubleshooting Guide](../../docs/operations/TROUBLESHOOTING.md)*
