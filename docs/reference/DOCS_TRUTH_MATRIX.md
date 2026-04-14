# Documentation Truth Matrix

This document maps what each top-level document claims about release state and metrics, and identifies any drift from the single source of truth.

## Related Docs
- [Release State](../releases/RELEASE_STATE.md)
- [Implementation Progress](../implementation/PROGRESS.md)
- [Remaining Work](../implementation/REMAINING_WORK.md)

## Single Sources of Truth

| Concern | Source of Truth | Location |
|---------|-----------------|----------|
| Version | `VERSION` file | [`VERSION`](../../VERSION) |
| Release state | `docs/releases/RELEASE_STATE.md` | [`RELEASE_STATE.md`](../../docs/releases/RELEASE_STATE.md) |
| Implementation progress | `docs/implementation/PROGRESS.md` | [`PROGRESS.md`](../../docs/implementation/PROGRESS.md) |
| Canonical architecture | `docs/workflow/LLMWorkflow_Canonical_Document_Set_*` | [`docs/workflow/`](../../docs/workflow/) canonical docs |

## Metric Counting Rules

To keep numbers consistent, use the following counting rules and scripts.

### PowerShell Modules
**Rule**: Count `.ps1` files under `module/LLMWorkflow/` that export functions, excluding test files and template/tool helpers.

```powershell
(Get-ChildItem -Path "module\LLMWorkflow" -Filter "*.ps1" -Recurse |
    Where-Object {
        $_.Name -notlike "*.Tests.ps1" -and
        $_.FullName -notlike "*\templates\*" -and
        $_.FullName -notlike "*\LLMWorkflow\scripts\*"
    }).Count
```

**Current Count**: `121`

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
**Rule**: Count parser and extractor modules under `module/LLMWorkflow/ingestion/parsers/` whose filenames end in `Parser.ps1` or `Extractor.ps1`.

```powershell
(Get-ChildItem -Path "module\LLMWorkflow\ingestion\parsers" -Filter "*.ps1" |
    Where-Object {
        $_.Name -notlike "*Test*" -and
        $_.Name -match "(Parser|Extractor)\.ps1$"
    }).Count
```

**Current Count**: `30`

### Golden Tasks
**Rule**: Count predefined task definitions declared in `module/LLMWorkflow/governance/GoldenTaskDefinitions.ps1`.

```powershell
(Select-String -Path "module\LLMWorkflow\governance\GoldenTaskDefinitions.ps1" -Pattern '-TaskId "gt-').Count
```

**Current Count**: `60`

### MCP Tools
**Rule**: Sum of tools declared across all MCP toolkit server manifests and gateway registries.

**Current Count**: `55`

---

## Document Claims Matrix

| Document | Version Claimed | Modules Claimed | Packs Claimed | Parsers Claimed | Golden Tasks Claimed | Status |
|----------|-----------------|-----------------|---------------|-----------------|----------------------|--------|
| [`README.md`](../../README.md) | 0.9.6 | 121 | 10 | 30 | 60 | ✅ truth |
| [`PROGRESS.md`](../../docs/implementation/PROGRESS.md) | 0.9.6 | 121 | 10 | 30 | 60 | ✅ truth |
| [`RELEASE_STATE.md`](../../docs/releases/RELEASE_STATE.md) | 0.9.6 | 121 | 10 | 30 | 60 | ✅ truth |

## Known Drift

### README.md
- No known drift.

### PROGRESS.md
- No known drift.

## Resolution Plan

1. ✅ Reconciled 2026-04-13: `VERSION`, `README.md`, `docs/implementation/PROGRESS.md`, `docs/releases/CHANGELOG.md`, `RELEASE_STATE.md`, and `LLMWorkflow.psd1` all aligned to `0.9.6`.
2. Metrics verified: 121 PowerShell modules, 10 domain packs, 30 extraction parsers, 60 golden tasks, 5 benchmark suites.
3. ✅ CI validation added (`tools/ci/validate-docs-truth.ps1`) to catch future drift automatically.
4. ✅ Remediation documentation sync completed on 2026-04-13 across `README.md`, `PROGRESS.md`, `TECHNICAL_DEBT_AUDIT.md`, `REMAINING_WORK.md`, and strategic execution plan docs.



