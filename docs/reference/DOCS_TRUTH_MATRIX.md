# Documentation Truth Matrix

This document maps what each top-level document claims about release state and metrics, and identifies any drift from the single source of truth.

## Related Docs
- [Release State](../releases/RELEASE_STATE.md)
- [Implementation Progress](../implementation/PROGRESS.md)
- [Remaining Work](../implementation/REMAINING_WORK.md)

## Single Sources of Truth

| Concern | Source of Truth | Location |
|---------|-----------------|----------|
| Version | `VERSION` file | [`VERSION`](../VERSION) |
| Release state | `docs/releases/RELEASE_STATE.md` | [`RELEASE_STATE.md`](../../docs/releases/RELEASE_STATE.md) |
| Implementation progress | `PROGRESS.md` | [`PROGRESS.md`](../../docs/implementation/PROGRESS.md) |
| Canonical architecture | `LLMWorkflow_Canonical_Document_Set_*` | Root-level canonical docs |

## Metric Counting Rules

To keep numbers consistent, use the following counting rules and scripts.

### PowerShell Modules
**Rule**: Count `.ps1` files under `module/LLMWorkflow/` that export functions, excluding test files and template/tool helpers.

```powershell
(Get-ChildItem -Path "module\LLMWorkflow" -Filter "*.ps1" -Recurse |
    Where-Object {
        $_.Name -notlike "*.Tests.ps1" -and
        $_.Name -notlike "*Test*.ps1" -and
        $_.FullName -notlike "*\templates\*" -and
        $_.FullName -notlike "*\LLMWorkflow\scripts\*"
    }).Count
```

**Current Count**: `106`

### Domain Packs
**Rule**: Count JSON files under `packs/manifests/` that have a matching `.sources.json` registry under `packs/registries/`.

```powershell
(Get-ChildItem -Path "packs\manifests" -Filter "*.json" |
    Where-Object {
        Test-Path (Join-Path "packs\registries" ($_.BaseName + ".sources.json"))
    }).Count
```

**Current Count**: `10`

### Extraction Parsers
**Rule**: Count modules under `module/LLMWorkflow/extraction/` whose primary role is parsing or extracting structure.

```powershell
(Get-ChildItem -Path "module\LLMWorkflow\extraction" -Filter "*.ps1" |
    Where-Object { $_.Name -notlike "*Test*" }).Count
```

**Current Count**: `31`

### Golden Tasks
**Rule**: Count tasks defined in `module/LLMWorkflow/governance/GoldenTasks.ps1`.

```powershell
((Get-Content "module\LLMWorkflow\governance\GoldenTasks.ps1" -Raw |
    Select-String -Pattern '(?m)^\s*\[.+?\].+?' -AllMatches).Matches).Count
```

**Current Count**: `30`

### MCP Tools
**Rule**: Sum of tools declared across all MCP toolkit server manifests and gateway registries.

**Current Count**: `55`

---

## Document Claims Matrix

| Document | Version Claimed | Modules Claimed | Packs Claimed | Parsers Claimed | Golden Tasks Claimed | Status |
|----------|-----------------|-----------------|---------------|-----------------|----------------------|--------|
| [`README.md`](../README.md) | 0.9.6 | 106 | 10 | — | 30+ | ✅ truth |
| [`PROGRESS.md`](../../docs/implementation/PROGRESS.md) | 0.9.6 | 106 | 10 | 31 | 30 | ✅ truth |
| [`RELEASE_STATE.md`](../../docs/releases/RELEASE_STATE.md) | 0.9.6 | 106 | 10 | 31 | 30 | ✅ truth |

## Known Drift

### README.md
- No known drift.

### PROGRESS.md
- No known drift.

## Resolution Plan

1. ✅ Reconciled 2026-04-13: `VERSION`, `README.md`, `PROGRESS.md`, `CHANGELOG.md`, `RELEASE_STATE.md`, and `LLMWorkflow.psd1` all aligned to `0.9.6`.
2. Metrics verified: 106 PowerShell modules, 10 domain packs, 31 extraction parsers, 30 golden tasks, 5 benchmark suites.
3. Add CI validation (`tools/ci/validate-docs-truth.ps1`) to catch future drift automatically.
