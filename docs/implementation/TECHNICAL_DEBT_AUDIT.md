# Technical Debt Audit

Canonical audit file for the current repository structure.

## Summary

This repo's main debt is no longer just "large scripts." The deeper issue is contract drift between the filesystem, the shipped PowerShell module surface, the test suite, and the documentation and release automation. Large parts of the codebase exist but are not actually wired into the public module, several tests are either non-enforceable or broken under Windows PowerShell 5.1, and the recent docs reorganization outpaced the automation that validates and publishes docs.

## Findings

- `High`: The shipped module does not represent the codebase that now exists on disk. The root loader in `module/LLMWorkflow/LLMWorkflow.psm1` only sources a narrow set of files from `core`, `pack`, `workflow`, one retrieval file, one governance file, and one MCP file. A reachability scan found 73 module scripts not referenced by the root loader at all, including most of `extraction/`, all of `ingestion/`, `snapshot/`, `telemetry/`, `policy/`, and most of `mcp/`. This means the folder structure suggests capabilities that are not part of the shipped module surface.

- `High`: The manifest and actual exported surface still drift. `module/LLMWorkflow/LLMWorkflow.psd1` declares 266 exported functions, but importing the module exposes 243. Nineteen manifest-declared functions remain missing from the public surface, including `Invoke-CrossPackArbitration`, `Get-ArbitratedPackOrder`, `Get-PackAuthorityScore`, and `Get-ArbitrationStatistics`. This is a release-contract problem, not just an internal refactor artifact.

- `High`: Test enforceability is still weak enough that CI confidence is overstated. Four `*.Tests.ps1` files are script harnesses rather than real Pester specs: `tests/RetrievalProfiles.Tests.ps1`, `tests/HumanReviewGates.Tests.ps1`, `tests/ConfidencePolicy.Tests.ps1`, and `tests/IncidentBundle.Tests.ps1`. They print pass or fail output, but Pester discovers zero tests in them. This means important failures can exist outside the CI pass/fail contract.

- `High`: A separate slice of the real Pester suite is not PowerShell 5.1-safe even though the files declare `#requires -Version 5.1`. Several tests build paths with `Join-Path $PSScriptRoot ".." "module" "LLMWorkflow"`, which throws under Windows PowerShell 5.1. Examples include `tests/Governance.Tests.ps1`, `tests/RetrievalIntegrity.Tests.ps1`, `tests/MCP.Tests.ps1`, `tests/Core.Tests.ps1`, `tests/Pack.Tests.ps1`, and others. Since CI explicitly runs both `powershell` and `pwsh`, this is a real portability and pipeline debt item.

- `High`: The docs reorganization broke documentation and release automation. `tools/ci/validate-docs-truth.ps1` still reads `PROGRESS.md` from the repo root, but that file now lives under `docs/implementation/`. Running the script currently fails immediately on a missing file. `tools/release/bump-module-version.ps1` still targets a root `CHANGELOG.md`, but the changelog now lives under `docs/releases/CHANGELOG.md`. The structure changed faster than the tooling did.

- `Medium`: There are silent function-name collisions inside the files that are actually sourced by the root module, so behavior depends on source order rather than clear ownership. Examples include:
  `New-ExecutionPlan`, `Add-PlanStep`, `Show-ExecutionPlan`, and `Invoke-ExecutionPlan` in both `module/LLMWorkflow/core/CommandContract.ps1` and `module/LLMWorkflow/workflow/Planner.ps1`.
  `New-RunId` in `module/LLMWorkflow/core/RunId.ps1`, `FileLock.ps1`, `Policy.ps1`, and `CommandContract.ps1`.
  `Get-ExecutionMode` in both `module/LLMWorkflow/core/Config.ps1` and `FileLock.ps1`.
  `Get-ValidExecutionModes` in both `module/LLMWorkflow/core/ConfigSchema.ps1` and `ExecutionMode.ps1`.

- `Medium`: Parallel subsystem forks remain a major source of drift. The repo has distinct, non-identical implementations for the same conceptual areas:
  Snapshot management in `module/LLMWorkflow/snapshot/SnapshotManager.ps1` and `module/LLMWorkflow/mcp/SnapshotManager.ps1`.
  Natural-language config in `module/LLMWorkflow/core/NaturalLanguageConfig.ps1` and `module/LLMWorkflow/mcp/NaturalLanguageConfig.ps1`.
  External ingestion in `module/LLMWorkflow/extraction/ExternalIngestion.ps1` and `module/LLMWorkflow/mcp/ExternalIngestion.ps1`.
  Federated memory in `module/LLMWorkflow/governance/FederatedMemory.ps1` and `module/LLMWorkflow/mcp/FederatedMemory.ps1`.
  These are not thin wrappers over one canonical implementation; they are independent files with overlapping function names and different contents.

- `Medium`: At least one script-style test file is surfacing a real implementation bug that the current CI story does not reliably enforce. `tests/HumanReviewGates.Tests.ps1` reports failures around `Get-ReviewStatus`, approval submission, pending review listing, and escalation. In `module/LLMWorkflow/governance/HumanReviewGates.ps1`, several status calculations use `.Count` directly on pipeline results in one code path, while a later code path wraps the same pipelines with array coercion. That inconsistent collection handling strongly suggests a real data-shape defect rather than a flaky test.

- `Medium`: Documentation references are still stale after the move. Examples include:
  `docs/workflow/LLMWorkflow_Canonical_Document_Set_INDEX.md` still contains a `sandbox:/mnt/data/...` link.
  `docs/reference/DOCS_TRUTH_MATRIX.md` still describes canonical docs as root-level.
  `docs/releases/V1_RELEASE_CRITERIA.md` and `docs/releases/RELEASE_CERTIFICATION_CHECKLIST.md` still reference old paths such as `PROGRESS.md`, `CHANGELOG.md`, `docs/SELF_HEALING.md`, and `docs/OBSERVABILITY_ARCHITECTURE.md`.

- `Low`: Version and metrics truth is still fragmented. `VERSION` says `0.9.6`, README advertises `0.9.6`, the module manifest still says `0.7.0`, and the dashboard hardcodes `v0.2.0`. README also mixes a `106` module badge with prose that still says `87+ PowerShell Modules`. This is not only cosmetic; it weakens trust in release metadata.

- `Low`: Repo hygiene remains loose. There is no `.gitignore`, tracked Python bytecode still exists under `tools/memorybridge/__pycache__/`, and runtime state under `.llm-workflow/` is active in the repo root. With a repo this large, that increases accidental churn and noisy reviews.

## Recommended Remediation Order

1. Fix the public contract first.
   Decide what the shipped module is supposed to contain, wire only those files into `LLMWorkflow.psm1`, and make `FunctionsToExport` match the actual imported surface.

2. Eliminate function collisions in sourced files.
   Shared utilities should live in one place; high-level features should not redefine the same command names across multiple sourced modules.

3. Repair the test contract.
   Convert the four script-style `*.Tests.ps1` files into real Pester specs, then fix the PowerShell 5.1-incompatible `Join-Path` usage in the existing Pester suite.

4. Update docs and release automation to the new folder structure.
   `validate-docs-truth.ps1`, release scripts, and all certification or truth-matrix documents should point at `docs/implementation/`, `docs/releases/`, `docs/operations/`, `docs/architecture/`, and `docs/workflow/`.

5. Collapse parallel subsystem forks.
   Pick one canonical implementation each for snapshotting, natural-language config, ingestion, and federated memory. Everything else should become thin wrappers or be removed.

6. Clean up repo hygiene.
   Add `.gitignore`, stop tracking bytecode, and define which runtime-state folders are expected to be generated locally.

## Verification Basis

This audit is based on a fresh rescan of the reorganized project, targeted module import checks, duplicate-function analysis, source reachability analysis against `LLMWorkflow.psm1`, direct execution of representative Pester files, and validation of docs and release scripts against the new `docs/` layout.
