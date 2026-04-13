# Memory Bridge Workflow

## Related Docs
- [Repository README](../../README.md)
- [Implementation Progress](../../docs/implementation/PROGRESS.md)
- [Technical Debt Audit](../../docs/implementation/TECHNICAL_DEBT_AUDIT.md)
- [Remaining Work](../../docs/implementation/REMAINING_WORK.md)

This folder provides a reusable one-way bridge from MemPalace local drawers
into ContextLattice (`MemPalace -> ContextLattice`).

Design goal:

- Keep ContextLattice as the canonical shared memory backend.
- Let MemPalace stay useful for local capture/mining/search workflows.
- Avoid brittle bidirectional sync.

## Prereqs

- Python with `chromadb` installed (used to read MemPalace drawer data)
- Running ContextLattice orchestrator (`/health` and `/status` reachable)
- `CONTEXTLATTICE_ORCHESTRATOR_API_KEY` set in your shell, or passed directly

## Bootstrap this repo

```powershell
.\tools\memorybridge\bootstrap-project.ps1
```

This creates:

- `.memorybridge/bridge.config.sample.json`
- `.memorybridge/bridge.config.json` (local, editable)

## Configuration

### Multi-Palace Support (v2.0+)

The bridge now supports multiple MemPalace instances in a single sync operation:

```json
{
  "version": "2.0",
  "palaces": [
    {
      "path": "~/.mempalace/palace",
      "collectionName": "mempalace_drawers",
      "topicPrefix": "mempalace",
      "wingProjectMap": {}
    },
    {
      "path": "./local-palace",
      "collectionName": "project_notes",
      "topicPrefix": "project",
      "wingProjectMap": {}
    }
  ],
  "orchestratorUrl": "http://127.0.0.1:8075",
  "apiKeyEnvVar": "CONTEXTLATTICE_ORCHESTRATOR_API_KEY"
}
```

Each palace configuration supports:

- `path`: Path to the MemPalace ChromaDB directory
- `collectionName`: ChromaDB collection name (default: `mempalace_drawers`)
- `topicPrefix`: Prefix for topic paths (default: `mempalace`)
- `wingProjectMap`: Map wing names to project names

### Legacy Format (Backward Compatible)

The bridge auto-migrates legacy single-palace configs on first run:

```json
{
  "palacePath": "~/.mempalace/palace",
  "collectionName": "mempalace_drawers",
  "topicPrefix": "mempalace",
  "wingProjectMap": {},
  "orchestratorUrl": "http://127.0.0.1:8075",
  "apiKeyEnvVar": "CONTEXTLATTICE_ORCHESTRATOR_API_KEY"
}
```

A backup is created at `bridge.config.json.legacy-backup` before migration.

## Sync MemPalace -> ContextLattice

### Sync all palaces

```powershell
.\tools\memorybridge\sync-from-mempalace.ps1
```

### Sync specific palace by index

```powershell
.\tools\memorybridge\sync-from-mempalace.ps1 -PalaceIndex 0
.\tools\memorybridge\sync-from-mempalace.ps1 -PalaceIndex 1
```

### Useful options

```powershell
.\tools\memorybridge\sync-from-mempalace.ps1 -DryRun
.\tools\memorybridge\sync-from-mempalace.ps1 -Limit 100
.\tools\memorybridge\sync-from-mempalace.ps1 -ForceResync
.\tools\memorybridge\sync-from-mempalace.ps1 -Workers 8
```

## PowerShell Module Commands

When using the LLMWorkflow PowerShell module:

```powershell
# List all configured palaces
Get-LLMWorkflowPalaces

# Test a specific palace
Test-LLMWorkflowPalace -Index 0

# Sync a specific palace
Sync-LLMWorkflowPalace -Index 0 -DryRun

# Sync all palaces
Sync-LLMWorkflowAllPalaces -ContinueOnError
```

Aliases: `llmpalaces`, `llmsync`

## How mapping works

- `wing` + `room` from MemPalace metadata become:
  - `topicPath`: `<topicPrefix>/<wing>/<room>`
  - `projectName`: mapped via `wingProjectMap[wing]` or `defaultProjectName`
- Content is forwarded verbatim.
- `fileName` includes deterministic drawer identifiers for traceability.

## Incremental behavior

The bridge stores synced drawer hashes in:

- `.memorybridge/sync-state.json`

State is tracked per-palace:

```json
{
  "version": 2,
  "palaces": {
    "palace_0": { "synced": {...}, "lastRunUtc": "..." },
    "palace_1": { "synced": {...}, "lastRunUtc": "..." }
  },
  "lastSummary": {...}
}
```

If content hash for a drawer ID has not changed, it skips re-write.

## Semantic Diff (Optional)

Enable semantic change detection using embeddings:

```powershell
.\tools\memorybridge\sync-from-mempalace.ps1 -SemanticDiff -SimilarityThreshold 0.95
```

This compares drawer content using cosine similarity of embeddings instead of
exact hash matching, useful for detecting minor edits that don't change meaning.

## Reuse in other repos

Copy `tools/memorybridge/` and run:

```powershell
.\tools\memorybridge\bootstrap-project.ps1
.\tools\memorybridge\sync-from-mempalace.ps1 -DryRun
```
