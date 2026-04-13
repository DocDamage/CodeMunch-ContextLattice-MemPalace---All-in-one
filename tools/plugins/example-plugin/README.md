# Example Plugin

## Related Docs
- [Repository README](../../../README.md)
- [Implementation Progress](../../../docs/implementation/PROGRESS.md)
- [Technical Debt Audit](../../../docs/implementation/TECHNICAL_DEBT_AUDIT.md)
- [Remaining Work](../../../docs/implementation/REMAINING_WORK.md)

This is an example plugin demonstrating the LLM Workflow plugin architecture.

## Purpose

Shows how to create custom plugins that integrate with the LLM Workflow bootstrap and check processes.

## Installation

1. Copy this folder to your project's `tools/` directory:
   ```powershell
   Copy-Item -Recurse "templates/plugins/example-plugin" "tools/"
   ```

2. Register the plugin:
   ```powershell
   Register-LLMWorkflowPlugin -ManifestPath "tools/example-plugin/manifest.json"
   ```

## What It Does

- **bootstrap**: Creates a marker file in `.llm-workflow/example-plugin-ran.marker`
- **check**: Validates the marker file exists and contains valid JSON

## Plugin Structure

```
example-plugin/
├── manifest.json      # Plugin metadata and script paths
├── bootstrap.ps1      # Runs during Invoke-LLMWorkflowUp
├── check.ps1          # Runs during Test-LLMWorkflowSetup
└── README.md          # Documentation
```

## Manifest Format

```json
{
  "name": "example-plugin",
  "description": "Description of what this plugin does",
  "version": "1.0.0",
  "author": "Your Name",
  "bootstrapScript": "tools/example-plugin/bootstrap.ps1",
  "checkScript": "tools/example-plugin/check.ps1",
  "runOn": ["bootstrap", "check"]
}
```

### Manifest Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Unique plugin identifier |
| `description` | Yes | Human-readable description |
| `version` | No | Plugin version (semver) |
| `author` | No | Plugin author |
| `bootstrapScript` | No | Path to bootstrap script (relative to project root) |
| `checkScript` | No | Path to check/health script (relative to project root) |
| `runOn` | Yes | Array of triggers: `"bootstrap"`, `"check"` |

## Script Interface

Both scripts receive these parameters:

```powershell
param(
    [string]$ProjectRoot = ".",
    [hashtable]$Context = @{}  # Additional context from bootstrap
)
```

Scripts should:
- Use `Write-Output` for logging (prefixed with `[plugin-name]`)
- Return exit code 0 on success, non-zero on failure
- Handle errors gracefully
