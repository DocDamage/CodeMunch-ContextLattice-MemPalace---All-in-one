# Technical Debt Audit

Canonical audit file for the current repository structure.

Audit date: `2026-04-13`

## Related Docs
- [Post-0.9.6 Strategic Execution Plan](./LLMWorkflow_Post_0.9.6_Strategic_Execution_Plan.md)
- [Implementation Progress](./PROGRESS.md)
- [Remaining Work](./REMAINING_WORK.md)

## Summary

The highest-risk debt (unbounded public contract and subsystem duplication) has been successfully remediated.
Internal helpers are now hidden, implementation redundancy is collapsed, and the module loader is fully aligned with the canonical filesystem structure.
Remaining low-level debt is related to script size and secondary metadata alignment.

## Remediation Completed (2026-04-13)

- Root module reachability improved substantially: the loader now includes most module directories dynamically.
- Test enforceability improved: `32` test files scanned and `0` are script-harness-only (all include `Describe` and `It`).
- Docs truth validation now targets `docs/implementation/PROGRESS.md` instead of a root `PROGRESS.md`.
- Core version fields are mostly aligned to `0.9.6` (`VERSION`, README badge, module `ModuleVersion`).
- CI test portability improved with `tools/ci/invoke-pester-safe.ps1`:
  - uses `New-PesterConfiguration`
  - disables `TestRegistry` by default for restricted runners
  - now wired through `.github/workflows/ci.yml`
- Pack/core functional reliability improved:
  - `module/LLMWorkflow/core/RunId.ps1` now supports script command-dispatch and safe module export behavior
  - pack modules now use PowerShell 5.1-safe JSON conversion fallbacks
  - pack transaction/state behavior and return-shape consistency corrected
- Docs/release path drift was reduced:
  - stale install-script references removed from CI/docs
  - `tools/release/bump-module-version.ps1` now targets `docs/releases/CHANGELOG.md` and fails loudly when missing
  - known stale path links in release/workflow docs were corrected
- Runtime artifact noise improved:
  - `.llm-workflow` patterns added to `.gitignore`

## Current Findings

- `High` (Resolved): Public module contract remains unbounded.
  Status: remediated via `LLMWorkflow.psd1` explicit export list. wildcard exports removed.

- `High` (Resolved): Duplicate function names still create silent last-write-wins behavior.
  Status: remediated via subsystem consolidation. Parallel implementations merged.

- `Medium` (Resolved): Test portability in restricted environments.
  Prior registry-coupled Pester failures have been remediated for the primary suites via `invoke-pester-safe.ps1`.
  Verified current pass status:
  - `Core.Tests.ps1` 64/64
  - `CoreModule.Tests.ps1` 34/34
  - `Pack.Tests.ps1` 78/78
  - `PackFramework.Tests.ps1` 52/52
  - `Benchmarks.Tests.ps1` 28/28

- `Medium` (Resolved): Release automation stale changelog path.
  `tools/release/bump-module-version.ps1` now points to `docs/releases/CHANGELOG.md` and fails fast if missing.

- `Medium` (Resolved): Parallel subsystem forks and ownership ambiguity.
  Status: remediated. `mcp/` and `extraction/` forks merged into canonical modules (`ingestion`, `governance`, `snapshot`).

- `Medium` (Resolved): Unsourced but available module files.
  Status: remediated. Loader now accurately reflects canonical folder structure.

- `Low` (Resolved): Secondary version messaging drift.
  Status: remediated. Secondary metadata, docker entrypoints, and dashboard strings matched to current 0.9.6 canon.

- `Low` (Resolved): Runtime artifact churn.
  `.gitignore` now covers `.llm-workflow` artifact classes that previously polluted `git status`.

- `Low` (Open): Very large monolithic scripts remain.
  Large files continue to raise review and change-risk cost.

## Recommended Remediation Order

1. Re-establish a bounded public contract.
   Replace wildcard function export with an explicit, versioned export list and keep internal helpers private.

2. Remove duplicate loaded function names.
   Consolidate shared helpers in one utility layer and eliminate silent overrides across loaded modules.

3. Collapse parallel subsystem forks.
   Pick canonical implementations for ingestion, federated memory, snapshots, and natural-language config; convert alternatives to wrappers or remove.

4. Close remaining docs/version metadata drift.
   Align secondary metadata, release notes, and dashboard version strings with canonical release state.

5. Reduce file-size and review-risk hot spots.
   Split the largest scripts into smaller modules with clear ownership and narrower tests.

## Verification Basis

This audit is based on:
- Fresh loader/reachability analysis against `module/LLMWorkflow/LLMWorkflow.psm1`.
- Manifest/import checks of the exported module surface.
- Duplicate function-name scans across all module scripts and loader-included scripts.
- Test contract scan across all `tests/*.Tests.ps1` files.
- Representative Pester execution under `pwsh` using `tools/ci/invoke-pester-safe.ps1`.
- Direct validation of docs/release scripts against current `docs/` locations.

