# Unified LLM Workflow Launcher

This folder provides a one-shot setup command for any project:

- Load local env files (`.env`, `.contextlattice/orchestrator.env`)
- Ensure project tool folders exist:
  - `tools/codemunch`
  - `tools/contextlattice`
  - `tools/memorybridge`
- Install required runtime dependencies when missing:
  - `codemunch-pro`
  - `chromadb`
- Bootstrap and verify:
  - CodeMunch project files
  - ContextLattice project files + connectivity check
  - MemPalace bridge files + dry-run sync

## Install global command

From this repository:

```powershell
.\tools\workflow\install-global-llm-workflow.ps1
```

Then open a new PowerShell session and run in any project root:

```powershell
llm-workflow-up
```

Alias:

```powershell
llmup
```

## Useful flags

```powershell
llm-workflow-up -SkipDependencyInstall
llm-workflow-up -SkipContextVerify
llm-workflow-up -SkipBridgeDryRun
llm-workflow-up -SmokeTestContext
llm-workflow-up -SmokeTestContext -RequireSearchHit
```

