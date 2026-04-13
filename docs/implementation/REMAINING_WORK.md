# Remaining Work

This document captures the work still left to complete after the Phase 1-8 buildout and the post-0.9.6 hardening wave.

It is intentionally narrower than the full strategic plan.
The goal here is to answer one practical question:

**What still has to happen before this repo can honestly be called v1.0-ready?**

**Last Updated:** 2026-04-13

## Related Docs
- [Post-0.9.6 Strategic Execution Plan](./LLMWorkflow_Post_0.9.6_Strategic_Execution_Plan.md)
- [Implementation Progress](./PROGRESS.md)
- [Technical Debt Audit](./TECHNICAL_DEBT_AUDIT.md)

---

## Current Read

The platform is no longer in a "missing core features" state.
Most of the planned subsystem files, docs, and tests now exist.

The remaining work is mainly in five categories:
- public contract reconciliation
- operational hardening
- enforcement depth
- documentation/release correctness
- cleanup of drift created by rapid expansion

In other words: the repo looks broad enough already.
What is left is making it trustworthy, coherent, and releasable.

---

## Highest-Priority Work Left

### 1. Reconcile the shipped module with the codebase

This is the biggest remaining contract problem.

What is still left:
- decide which subsystem files are part of the supported public module surface
- update `module/LLMWorkflow/LLMWorkflow.psm1` so the intended files are actually sourced
- make `module/LLMWorkflow/LLMWorkflow.psd1` exports match the real imported surface
- remove or wrap duplicate implementations instead of letting source order decide behavior

Why this is still open:
- the technical debt audit found a large set of scripts on disk that are not reachable from the root loader
- the manifest and actual exported function surface still drift
- multiple sourced files redefine commands such as `New-RunId`, `Get-ExecutionMode`, and plan-related helpers

Exit condition:
- importing `LLMWorkflow` exposes exactly the supported command set, with no silent shadowing and no manifest/export drift

---

### 2. Turn the test suite into a fully enforceable release gate

The test story is much better than before, but it is not finished.

What is still left:
- convert the remaining script-style `*.Tests.ps1` harnesses into real Pester tests
- ensure all declared PowerShell 5.1-compatible tests are actually 5.1-safe
- reduce or document warning-heavy tests that currently pass but still emit confusing operational noise
- define the minimum required suite for release certification and CI blocking

Known remaining debt:
- `tests/RetrievalProfiles.Tests.ps1`
- `tests/HumanReviewGates.Tests.ps1`
- `tests/ConfidencePolicy.Tests.ps1`
- `tests/IncidentBundle.Tests.ps1`

Exit condition:
- every important behavior is covered by Pester-discoverable tests and CI pass/fail reflects real risk

---

### 3. Finish documentation and release-truth reconciliation

Workstream 1 has landed meaningful foundations, but not every doc contract is clean yet.

What is still left:
- reconcile stale path references introduced by the docs reorganization
- remove contradictions between "stable release" language and "documented-head" language
- add or standardize release-state summary blocks where they are still missing
- ensure release automation points at the current `docs/` layout everywhere
- reconcile any remaining version and metric drift across README, release docs, dashboards, and module metadata

Examples of remaining drift called out in the audit:
- stale references to old root-level doc paths
- stale references inside release criteria and certification docs
- version strings that still disagree across different surfaces

Exit condition:
- docs, release scripts, and dashboards all agree on version, paths, metrics, and component state

---

### 4. Make observability operational, not just present

The telemetry files and architecture docs exist.
What remains is deeper adoption on the critical path.

What is still left:
- instrument the full answer path end-to-end
- propagate trace and correlation IDs consistently across retrieval, arbitration, confidence, evidence, MCP, and extraction
- attach eval events to traces in a way operators can use
- define operator dashboards and incident drill-down flows
- verify that parser/tool failures can be diagnosed without log archaeology

Priority targets still called out by the strategic plan:
- `QueryRouter`
- `AnswerPlan`
- `CrossPackArbitration`
- `ConfidencePolicy`
- `EvidencePolicy`
- `RetrievalCache`
- MCP gateway/toolkit paths
- extraction failure paths

Exit condition:
- a real answer incident can be traced by query, pack, parser, authority source, and tool path from one workflow

---

### 5. Deepen policy enforcement in runtime paths

Policy artifacts and adapters exist, but v1.0 needs stronger proof that policy is actually in the loop where it matters.

What is still left:
- confirm policy evaluation is invoked at all major high-risk mutation points
- standardize human-readable policy explanations across all allow/deny paths
- expand policy coverage for MCP exposure, inter-pack transfer, workspace boundaries, and release gates
- make fallback behavior explicit and testable so degraded policy mode is visible, not silent

Exit condition:
- high-risk operations are visibly governed by externalized policy with explainable results and audited fallback rules

---

## Medium-Priority Work Left

### 6. Harden mixed artifact and game-asset ingestion further

The repo now has good early coverage for manifests, Unreal descriptors, and RPG Maker asset catalogs.
That is a foundation, not the finish line.

What is still left:
- broaden mixed-document ingestion validation across real sample corpora
- make provenance and license fields uniformly present across all asset/document outputs
- clarify which binary or engine-native formats are inventory-only versus deeply parsed
- add stronger normalization around marketplace metadata, licensing, and source attribution
- continue engine-aware asset coverage without pretending binary extraction is solved

Exit condition:
- ingestion outputs are consistent enough for downstream governance, retrieval, and cataloging without per-parser special cases

---

### 7. Finish durable execution as an operational workflow, not just a module

The durable orchestrator exists and tests pass, but the release bar is higher than local functionality.

What is still left:
- define which real long-running workflows must use durability by default
- document recovery semantics more explicitly for operators
- add at least one production-shaped resume scenario with durable checkpoints across interruption
- decide how far Workstream 6 goes locally versus through an external workflow engine

Exit condition:
- at least one real long-running path is durably resumable, documented, and exercised by tests and operations docs

---

### 8. Finish MCP lifecycle governance and retrieval substrate governance

Files and docs exist, but governance maturity still needs tightening.

What is still left:
- ensure registry and lifecycle modules match the release criteria and actual file names
- verify that MCP lifecycle state transitions are enforced, not only documented
- wire tool exposure policy into onboarding, promotion, and retirement flows
- clarify how retrieval backend selection is governed across environments and profiles

Exit condition:
- MCP/tool growth is controlled by lifecycle rules, exposure policy, and tests instead of expanding by convention

---

### 9. Operationalize the security baseline in the release path

The scripts exist and tests are present.
The remaining work is more about enforcement and evidence than raw implementation.

What is still left:
- make security scans and SBOM generation unavoidable in release and promotion flows
- define evidence retention for security reports
- verify thresholds and overrides for emergency branches or hotfixes
- connect supply-chain policy, scan output, and release sign-off in one operator flow

Exit condition:
- a release candidate cannot be promoted without current security evidence and a passing promotion gate

---

## Cleanup Work Left

### 10. Collapse parallel subsystem forks

The repo still contains parallel implementations of the same conceptual subsystem.

Areas called out by the audit:
- snapshot management
- natural-language config
- external ingestion
- federated memory

What is still left:
- choose one canonical implementation per subsystem
- convert alternates into thin wrappers or delete them
- remove duplicate function names where they create ambiguous ownership

Exit condition:
- each subsystem has one obvious source of truth

---

### 11. Improve repo hygiene

This is not the most strategic work, but it reduces noise and accidental churn.

What is still left:
- add and maintain a real `.gitignore`
- stop tracking generated bytecode and similar runtime artifacts
- define which local runtime-state folders are expected to exist but should not be versioned
- keep the root worktree cleaner so reviews stay high-signal

Exit condition:
- generated state and cache artifacts no longer pollute normal development flow

---

## Suggested Execution Order

If only one sequence is followed, this should be it:

1. Reconcile the public module contract.
2. Convert all remaining non-enforceable tests into real CI gates.
3. Finish docs/release truth cleanup and path reconciliation.
4. Deepen observability and policy enforcement on the critical answer path.
5. Harden ingestion consistency and real recovery workflows.
6. Tighten MCP governance and release security gates.
7. Collapse duplicate subsystem implementations.
8. Clean up repo hygiene.

---

## What Would Count As "Done"

This repo can be treated as genuinely v1.0-ready only when the following are all true:
- the shipped module surface matches the code that is actually supported
- release docs and automation no longer contradict each other
- CI reflects real risk because important tests are enforceable
- critical answer paths are traceable and diagnosable
- policy is active in runtime decisions, not only present on disk
- ingestion outputs preserve provenance and licensing consistently
- at least one real long-running workflow is durably recoverable
- MCP and retrieval growth are governed by enforceable lifecycle rules
- security evidence is part of normal promotion, not an optional extra

Until then, the project is strong and increasingly mature, but still in hardening mode rather than final v1.0 release mode.

---

## Basis For This Document

This summary is derived from:
- `docs/implementation/LLMWorkflow_Post_0.9.6_Strategic_Execution_Plan.md`
- `docs/implementation/PROGRESS.md`
- `docs/implementation/TECHNICAL_DEBT_AUDIT.md`
- current release and architecture documents under `docs/`
