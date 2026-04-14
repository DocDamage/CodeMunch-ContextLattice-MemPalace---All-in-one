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

### Completed In Latest Remediation Wave

- pack/core test surfaces were stabilized and now pass under CI-safe Pester invocation
- PowerShell 5.1 compatibility fixes were applied to pack JSON and test harness behavior
- stale docs/release path drift was reduced across key release/workflow docs
- release bump automation now targets `docs/releases/CHANGELOG.md` and fails loudly on missing artifacts
- `.llm-workflow` artifact noise is now ignored in git
- stale install-script references were removed from README and CI
- **Public module contract reconciled**: `LLMWorkflow.psd1` now has explicit exports, wildcard exports removed.
- **Subsystem forks collapsed**: redundant implementation logic in `mcp/` and `extraction/` merged into canonical modules.
- **Module loader stabilized**: `LLMWorkflow.psm1` now accurately sources consolidated components.
- **Governance hardened**: Strict-mode property access corrected in `GoldenTasks.ps1`.

---

## Highest-Priority Work Left

### 1. Reconcile the shipped module with the codebase (Resolved)
- Status: **Completed**. Module manifest updated with explicit exports; parallel implementations merged; loader stabilized.

---

### 2. Turn the test suite into a fully enforceable release gate

The test story is much better than before, but it is not finished.

What is still left:
- define and enforce the exact required release-gate suites in CI (not just ad hoc suite runs)
- reduce noisy warning paths in benchmark and journal-related tests so pass output stays high-signal
- add explicit negative and regression tests around module contract/export boundaries
- tighten retrieval/governance suite expectations where behavior can still drift silently

Exit condition:
- CI-required suites are explicit, stable, and representative of real release risk

---

### 3. Finish documentation and release-truth reconciliation

Workstream 1 foundations are in place and recent path fixes landed, but full reconciliation is not complete yet.

What is still left:
- remove remaining secondary version-label drift (for example old dashboard/UI or release-note versions)
- standardize release-state summary blocks across top-level architecture and operations docs
- keep docs-truth checks in CI and expand them to additional high-signal docs as needed
- ensure `released` vs `documented-head` language is consistent in all release-facing docs

Examples of remaining drift called out in the audit:
- secondary metadata/version strings that still reference older release labels
- occasional wording mismatch between stable-release claims and documented-head claims

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

### 10. Collapse parallel subsystem forks (Resolved)
- Status: **Completed**. Canonical implementations established for ingestion, snapshots, config, and memory. Alternate implementations removed.

---

### 11. Improve repo hygiene

This is not the most strategic work, but it reduces noise and accidental churn.

What is still left:
- maintain and expand `.gitignore` as new generated artifacts appear
- prevent accidental check-in of benchmark/test output and local runtime state
- define and document which local runtime-state folders are expected but never versioned
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
