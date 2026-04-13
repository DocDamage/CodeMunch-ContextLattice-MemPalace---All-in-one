# Technical Debt Audit

Canonical audit file for the current repository structure.

Audit date: `2026-04-13`

## Related Docs
- [Post-0.9.6 Strategic Execution Plan](./LLMWorkflow_Post_0.9.6_Strategic_Execution_Plan.md)
- [Implementation Progress](./PROGRESS.md)
- [Remaining Work](./REMAINING_WORK.md)

## Summary

The highest-risk debt has shifted from "missing wiring" to "contract control." The module now loads most feature areas, but it exports an extremely broad internal surface (`*`) and contains many duplicate function names across loaded files. Release/docs automation still has path drift after docs reorganization, and test execution currently assumes capabilities (registry access) that are not portable to restricted runners.

## Resolved Since Prior Audit

- Root module reachability improved substantially: the loader now includes most module directories dynamically.
- Test enforceability improved: `32` test files scanned and `0` are script-harness-only (all include `Describe` and `It`).
- Docs truth validation now targets `docs/implementation/PROGRESS.md` instead of a root `PROGRESS.md`.
- Core version fields are mostly aligned to `0.9.6` (`VERSION`, README badge, module `ModuleVersion`).

## Findings

- `High`: Public module contract is effectively unbounded.
  `module/LLMWorkflow/LLMWorkflow.psd1:11` sets `FunctionsToExport = @('*')`, and `module/LLMWorkflow/LLMWorkflow.psm1:1299` uses `Export-ModuleMember -Function *`.
  A fresh import exposes `1383` functions, which means helper/internal commands become part of the public API contract by default.

- `High`: Duplicate function names in loaded scope cause silent last-write-wins behavior.
  Loader-scope scan found `18` duplicated function names across sourced files (and `39` across all module `.ps1` files).
  Examples:
  `ConvertTo-Hashtable` appears in many loaded files (`module/LLMWorkflow/core/TypeConverters.ps1:3`, `module/LLMWorkflow/core/Journal.ps1:51`, `module/LLMWorkflow/core/FileLock.ps1:41`, `module/LLMWorkflow/governance/HumanReviewGates.ps1:527`, etc.).
  `Register-MCPTool` and `Get-MCPTool` are both defined in `module/LLMWorkflow/mcp/MCPToolRegistry.ps1` and `module/LLMWorkflow/mcp/MCPToolkitServer.ps1`.
  `Set-NestedValue` is defined in both `module/LLMWorkflow/core/Config.ps1:881` and `module/LLMWorkflow/core/ConfigCLI.ps1:474`.

- `High`: Test execution portability is weak in restricted environments.
  Running approved Pester suites under `pwsh` discovered `427` tests but failed all due to registry access assumptions in Pester setup (`Requested registry access is not allowed`, `New-TestRegistry` / `New-RandomTempRegistry` failures).
  This is a real CI portability risk for sandboxed/self-hosted runners with constrained registry permissions.

- `Medium`: Release automation still points at stale changelog path.
  `tools/release/bump-module-version.ps1:21` targets root `CHANGELOG.md`, but only `docs/releases/CHANGELOG.md` exists.
  Because the script wraps this in `if (Test-Path ...)`, changelog updates can be silently skipped during version bumps.

- `Medium`: Parallel subsystem forks and selective excludes remain a drift vector.
  Duplicate subsystem files still exist:
  `module/LLMWorkflow/extraction/ExternalIngestion.ps1` and `module/LLMWorkflow/mcp/ExternalIngestion.ps1`,
  `module/LLMWorkflow/governance/FederatedMemory.ps1` and `module/LLMWorkflow/mcp/FederatedMemory.ps1`,
  `module/LLMWorkflow/snapshot/SnapshotManager.ps1` and `module/LLMWorkflow/mcp/SnapshotManager.ps1`,
  `module/LLMWorkflow/core/NaturalLanguageConfig.ps1` and `module/LLMWorkflow/mcp/NaturalLanguageConfig.ps1`.
  The root loader explicitly excludes some MCP variants (`module/LLMWorkflow/LLMWorkflow.psm1:90`, `module/LLMWorkflow/LLMWorkflow.psm1:147`), but canonical ownership is still unclear.

- `Medium`: Some valid module code remains unsourced, reinforcing dead-code ambiguity.
  A reachability scan found non-template module files present but not sourced by `LLMWorkflow.psm1`, including:
  `module/LLMWorkflow/core/NaturalLanguageConfig.ps1` and `module/LLMWorkflow/DashboardViews.ps1`.

- `Medium`: Documentation and certification docs still contain stale paths/links.
  `docs/releases/V1_RELEASE_CRITERIA.md:31` still references top-level `PROGRESS.md`.
  `docs/releases/RELEASE_CERTIFICATION_CHECKLIST.md:33` and `:120` still reference `PROGRESS.md` and `CHANGELOG.md` at repo root.
  `docs/releases/RELEASE_CERTIFICATION_CHECKLIST.md:44` and `:96` still reference old `docs/OBSERVABILITY_ARCHITECTURE.md` and `docs/SELF_HEALING.md` paths.
  `docs/workflow/LLMWorkflow_Canonical_Document_Set_INDEX.md:16` still includes a `sandbox:/mnt/data/...` link.

- `Low`: Version messaging is still inconsistent in secondary metadata.
  `module/LLMWorkflow/LLMWorkflow.psd1:20` release notes still describe `v0.7.0`.
  Dashboard docs/UI still hardcode `v0.2.0` (`module/LLMWorkflow/LLMWorkflow.Dashboard.ps1:114`, `docs/reference/dashboard.md:80`).

- `Low`: Runtime artifact churn remains noisy.
  `.gitignore` now exists, but `.llm-workflow/` runtime/report/backup artifacts are still showing up in `git status` because that path is not ignored.

- `Low`: Several critical scripts remain very large monoliths.
  Examples include:
  `module/LLMWorkflow/mcp/MCPToolkitServer.ps1` (~`5888` lines),
  `module/LLMWorkflow/governance/GoldenTasks.ps1` (~`4784` lines),
  `module/LLMWorkflow/mcp/MCPCompositeGateway.ps1` (~`4184` lines).
  These increase change risk, review time, and collision probability.

## Recommended Remediation Order

1. Re-establish a bounded public contract.
   Replace wildcard function export with an explicit, versioned export list and keep internal helpers private.

2. Remove duplicate loaded function names.
   Consolidate shared helpers in one utility layer and eliminate silent overrides across loaded modules.

3. Harden test portability.
   Make tests resilient to restricted environments by removing registry assumptions or gating registry-dependent setup.

4. Fix release-path automation.
   Update `bump-module-version.ps1` to `docs/releases/CHANGELOG.md` and fail loudly when expected release artifacts are missing.

5. Collapse parallel subsystem forks.
   Pick canonical implementations for ingestion, federated memory, snapshots, and natural-language config; convert alternatives to wrappers or remove.

6. Complete docs path reconciliation.
   Update release criteria/checklists and canonical index links to current `docs/` structure only.

7. Reduce repo noise and file size risk.
   Ignore `.llm-workflow` runtime artifacts and split the largest module scripts into smaller, testable units.

## Verification Basis

This audit is based on:
- Fresh loader/reachability analysis against `module/LLMWorkflow/LLMWorkflow.psm1`.
- Manifest/import checks of the exported module surface.
- Duplicate function-name scans across all module scripts and loader-included scripts.
- Test contract scan across all `tests/*.Tests.ps1` files.
- Representative Pester execution under `pwsh`.
- Direct validation of docs/release scripts against current `docs/` locations.
