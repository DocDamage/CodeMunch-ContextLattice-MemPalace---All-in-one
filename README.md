# CodeMunch + ContextLattice + MemPalace (All-in-One)

Canonical toolkit repo for the integrated workflow:

- `CodeMunch Pro` project indexing and MCP wrapper setup
- `ContextLattice` project bootstrap + connectivity verification
- `MemPalace -> ContextLattice` incremental bridge
- one global command to bootstrap any repo in one shot

## Repository layout

- `tools/codemunch`
- `tools/contextlattice`
- `tools/memorybridge`
- `tools/workflow`

`tools/workflow` contains the global installer and unified bootstrap command.

## Option A: Script install (global command)

From this repo:

```powershell
.\tools\workflow\install-global-llm-workflow.ps1
```

Open a new PowerShell session.

## Option B: Versioned module install (recommended)

From this repo:

```powershell
.\install-module.ps1
```

Then in any project folder:

```powershell
Invoke-LLMWorkflowUp
```

Alias:

```powershell
llmup
```

Optional (from module):

```powershell
Install-LLMWorkflow
```

This installs the same global launcher under `~/.llm-workflow`.

## Use in any project

From any repo folder (script or module path):

```powershell
llm-workflow-up
```

Alias:

```powershell
llmup
```

What it does:

1. Loads `.env` and `.contextlattice/orchestrator.env` when present.
2. Auto-creates missing tool folders in the current project:
   - `tools/codemunch`
   - `tools/contextlattice`
   - `tools/memorybridge`
3. Installs/validates dependencies (`codemunch-pro`, `chromadb`).
4. Runs project bootstrap scripts for all three toolchains.
5. Runs ContextLattice verify and MemPalace bridge dry-run (if API key exists).

## Optional flags

```powershell
llm-workflow-up -SkipDependencyInstall
llm-workflow-up -SkipContextVerify
llm-workflow-up -SkipBridgeDryRun
llm-workflow-up -SmokeTestContext
llm-workflow-up -SmokeTestContext -RequireSearchHit
```

## Notes

- Keep secrets in local `.env` files and never commit them.
- For ContextLattice auth, set `CONTEXTLATTICE_ORCHESTRATOR_API_KEY` in `.env`
  or `.contextlattice/orchestrator.env`.
