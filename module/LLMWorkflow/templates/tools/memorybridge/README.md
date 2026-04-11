# Memory Bridge Workflow

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

## Sync MemPalace -> ContextLattice

```powershell
.\tools\memorybridge\sync-from-mempalace.ps1
```

Useful options:

```powershell
.\tools\memorybridge\sync-from-mempalace.ps1 -DryRun
.\tools\memorybridge\sync-from-mempalace.ps1 -Limit 100
.\tools\memorybridge\sync-from-mempalace.ps1 -ForceResync
```

## How mapping works

- `wing` + `room` from MemPalace metadata become:
  - `topicPath`: `<topicPrefix>/<wing>/<room>`
  - `projectName`: mapped via `wingProjectMap[wing]` or `defaultProjectName`
- Content is forwarded verbatim.
- `fileName` includes deterministic drawer identifiers for traceability.

## Incremental behavior

The bridge stores synced drawer hashes in:

- `.memorybridge/sync-state.json`

If content hash for a drawer ID has not changed, it skips re-write.

## Reuse in other repos

Copy `tools/memorybridge/` and run:

```powershell
.\tools\memorybridge\bootstrap-project.ps1
.\tools\memorybridge\sync-from-mempalace.ps1 -DryRun
```

