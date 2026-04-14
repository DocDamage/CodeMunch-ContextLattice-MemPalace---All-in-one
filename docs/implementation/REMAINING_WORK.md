# Remaining Work

This document tracks the practical work still left between the current documented head state and an honest `v1.0` release.

It is intentionally narrower than the strategic plan and more execution-oriented than the audit.
Use it to answer one question:

**What still has to happen before this repo can be called release-ready with a straight face?**

**Last Updated:** 2026-04-13

## Related Docs
- [Post-0.9.6 Strategic Execution Plan](./LLMWorkflow_Post_0.9.6_Strategic_Execution_Plan.md)
- [Implementation Progress](./PROGRESS.md)
- [Detailed Working Audit](../../deep_audit_results.txt)

---

## Current Read

The platform is no longer blocked on missing core capability.
It is blocked on consistency, diagnosability, and release discipline.

The repo already has broad surface area across:
- orchestration and workflow runtime
- extraction and mixed-artifact handling
- governance and review flows
- MCP and retrieval infrastructure
- game-engine and asset-facing tooling

That breadth is now a strength and a maintenance risk at the same time.
The remaining work is mostly about turning prototype-era success into operational trust.

### What Recently Improved

Several important cleanup and foundation tasks are already done or materially underway:
- explicit module exports replaced wildcard export behavior in `LLMWorkflow.psd1`
- subsystem fork consolidation reduced parallel implementations and loader ambiguity
- CI-safe Pester invocation and core suite stabilization landed
- release/docs truth improved and path drift was reduced
- PowerShell 5.1 compatibility improved in key pack and test paths
- game-asset intake foundations landed for engine-aware manifests and preset scaffolding
- Unreal descriptor extraction landed for `.uplugin` and `.uproject`
- RPG Maker asset catalog parsing landed for common asset families and plugin metadata
- recent asset-ingestion additions shipped with regression tests instead of relying on later cleanup

That is real progress.
It also means the remaining work is now less about expansion and more about hardening the surfaces that already exist.

---

## Remaining Work by Release Priority

### Priority 0: Failure Visibility and Unsafe Execution

This is the most important work left.
If the system can fail silently, suppress important diagnostics, or execute unpredictably, `v1.0` is not ready no matter how many features exist.

#### What Still Needs To Happen
- reduce and justify `-ErrorAction SilentlyContinue` usage in production modules
- eliminate empty `catch` blocks and replace them with explicit handling or rethrow behavior
- remove or tightly isolate `Invoke-Expression` usage from release-relevant paths
- replace `Write-Host` in reusable modules with structured diagnostics or pipeline-safe output
- make degraded-mode behavior visible and testable instead of quiet

#### First Targets
- `GoldenTasks.ps1`
- `GeometryNodesParser.ps1`
- `DoclingAdapter.ps1`
- `ExternalIngestion.ps1`
- `DashboardViews.ps1`
- `LLMWorkflow.HealFunctions.ps1`
- `MLModelDeploymentPipeline.ps1`
- `LLMWorkflow.Dashboard.ps1`

#### Exit Condition
- critical modules no longer swallow failures or hide important state transitions from operators and tests

### Priority 1: Structural Refactoring and Canonical Ownership

The repo still contains too many large modules and duplicated helpers.
That slows review, increases regression radius, and makes it too easy for new work to repeat old patterns.

#### What Still Needs To Happen
- decompose the largest modules into coherent private helper files or submodules
- replace duplicated utility functions with canonical shared implementations
- make ownership boundaries clearer in file layout and loader wiring
- pin new seams with tests so refactors reduce risk instead of redistributing it

#### First Targets
- `MLModelDeploymentPipeline.ps1`
- `ExternalIngestion.ps1`
- `AIGenerationPipeline.ps1`
- `GoldenTasks.ps1`
- `ExtractionPipeline.ps1`
- `LLMWorkflow.GameFunctions.ps1`
- `IncidentBundle.ps1`
- `Journal.ps1`

#### Exit Condition
- the highest-risk modules are no longer giant, ambiguous maintenance zones

### Priority 2: Module Contracts and PowerShell Hygiene

A large amount of remaining work is basic contract quality.
This is less dramatic than a silent failure bug, but it is everywhere and it affects operator trust, discoverability, and maintenance speed.

#### What Still Needs To Happen
- add `Set-StrictMode` to reusable modules that still lack it
- add `[CmdletBinding()]` where functions are still script-style without proper contracts
- add `.SYNOPSIS` help to public and important semi-public functions
- add `[OutputType()]` where it clarifies downstream behavior
- remediate unapproved PowerShell verbs or document intentional exceptions
- tighten parameter contracts where `$args` is still standing in for explicit parameters

#### First Targets
- `AIGenerationPipeline.ps1`
- `LLMWorkflow.psm1`
- `LLMWorkflow.GameFunctions.ps1`
- `NaturalLanguageConfig.ps1`
- `DashboardViews.ps1`
- `bootstrap-llm-workflow.ps1`
- `UnrealDescriptorParser.ps1`
- `RPGMakerAssetCatalogParser.ps1`
- `SpriteSheetParser.ps1`
- `AtlasMetadataParser.ps1`

#### Exit Condition
- core public surfaces look and behave like deliberate modules, not leftover prototype scripts

### Priority 3: Test and Evidence Coverage

The test story improved, but it is still uneven.
`v1.0` requires stronger coverage around foundational behavior, not only around newly touched areas.

#### What Still Needs To Happen
- convert release-critical suites into explicit CI gates
- add direct tests or strong evidence of coverage for state, locking, contract, and workspace primitives
- add more negative and regression tests around exports, loader behavior, and policy fallback paths
- keep newer game-asset and extraction surfaces under regression coverage as they grow
- reduce noisy warnings in suites where signal is still diluted

#### First Targets
- `AtomicWrite.ps1`
- `CommandContract.ps1`
- `FileLock.ps1`
- `Journal.ps1`
- `StateFile.ps1`
- `TypeConverters.ps1`
- `Workspace.ps1`
- `LLMWorkflow.GameFunctions.ps1`
- module export and loader boundary tests

#### Exit Condition
- CI reflects real release risk rather than partial confidence from ad hoc suite runs

### Priority 4: Documentation and Release Truth

Recent reconciliation work helped a lot, but this still needs to be treated as release infrastructure, not optional polish.

#### What Still Needs To Happen
- remove remaining version-label and release-state drift in top-level docs and dashboards
- keep docs-truth checks active and expand them where they add real signal
- standardize `released` versus `documented-head` wording across release-facing docs
- keep plan, progress, changelog, and audit language aligned as head changes

#### Exit Condition
- release docs, automation, and summary dashboards all describe the same reality

### Priority 5: Observability and Policy on the Critical Path

The architecture exists.
The remaining work is to make it operationally useful and visibly active where it matters.

#### What Still Needs To Happen
- propagate trace and correlation IDs across routing, retrieval, arbitration, confidence, evidence, extraction, and MCP flows
- make parser and tool failures diagnosable without log archaeology
- ensure policy is invoked at real mutation and exposure boundaries, not just represented on disk
- standardize human-readable allow or deny explanations
- make fallback and degraded policy behavior explicit and testable

#### First Targets
- `QueryRouter.ps1`
- `AnswerPlan.ps1`
- `CrossPackArbitration.ps1`
- `ConfidencePolicy.ps1`
- `EvidencePolicy.ps1`
- `RetrievalCache.ps1`
- MCP gateway and toolkit paths
- extraction failure paths

#### Exit Condition
- a real answer or ingestion incident can be traced and explained end-to-end

### Priority 6: Mixed Artifact and Game Asset Ingestion Hardening

This area is now a real platform capability, not a speculative future add-on.
That means it has remaining work of its own.

#### What Still Needs To Happen
- keep provenance and license fields consistent across asset and document outputs
- clearly distinguish inventory-only support from deep extraction support for engine-native formats
- normalize marketplace and source-attribution metadata for external assets, including Epic or Fab-style sources
- continue broadening engine-aware coverage without overclaiming binary parsing support
- add stronger help, contracts, and pipeline integration around newer parser surfaces
- validate outputs across more real sample corpora, not only synthetic tests

#### First Targets
- `LLMWorkflow.GameFunctions.ps1`
- `ExtractionPipeline.ps1`
- `UnrealDescriptorParser.ps1`
- `RPGMakerAssetCatalogParser.ps1`
- `SpriteSheetParser.ps1`
- `AtlasMetadataParser.ps1`
- provenance and manifest normalization paths

#### Exit Condition
- mixed-artifact outputs are consistent enough for governance, retrieval, and cataloging without parser-specific special casing

### Priority 7: Security, Portability, and Promotion Discipline

The repo has security and supply-chain pieces in place.
The remaining work is making them unavoidable, reviewable, and portable.

#### What Still Needs To Happen
- triage heuristic secret findings to closure
- remove or normalize hardcoded absolute paths where they affect portability or release tooling
- make security scans and SBOM evidence part of normal promotion flow
- define evidence retention and override rules for release and hotfix scenarios
- keep scratch and audit tooling from leaking local-machine assumptions into production paths

#### First Targets
- `LLMWorkflow.HealFunctions.ps1`
- `NaturalLanguageConfig.ps1`
- `entrypoint.ps1`
- deployment scripts for MCP surfaces
- security promotion scripts and evidence paths
- scratch and audit helpers with absolute path assumptions

#### Exit Condition
- a release candidate cannot move forward without current security evidence and portable-enough execution paths

### Priority 8: Durable Execution and MCP Lifecycle Governance

These are important, but they should land after the failure-handling and structural work above because they depend on a more trustworthy base.

#### What Still Needs To Happen
- define which long-running workflows must use durability by default
- document and test resume semantics in production-shaped scenarios
- enforce MCP lifecycle transitions rather than just documenting them
- wire tool exposure policy into onboarding, promotion, and retirement flows
- govern retrieval backend selection across environments and profiles

#### Exit Condition
- long-running workflows recover predictably and MCP growth is governed by rules instead of convention

---

## Resolved or Mostly Resolved Items

These are no longer the main remaining-work drivers and should not keep reappearing as if they were still open program blockers.

### Reconcile the Shipped Module with the Codebase
- Status: `Completed`
- explicit exports replaced wildcard export behavior
- loader sourcing was corrected to match canonical components

### Collapse Parallel Subsystem Forks
- Status: `Completed` or materially resolved for current head
- redundant implementations across major subsystem areas were merged into canonical modules
- remaining work is now about structural quality and governance, not basic fork cleanup

---

## Suggested Execution Order

If we follow one practical sequence, it should be this:

1. clear Priority 0 failure-visibility issues
2. decompose the highest-risk large modules and remove duplicate helpers
3. harden module contracts and PowerShell hygiene on core public surfaces
4. convert critical coverage into explicit release-gate tests
5. finish doc and release-truth reconciliation
6. deepen observability and runtime policy on the critical path
7. harden mixed-artifact and game-asset ingestion consistency
8. tighten security, portability, durable execution, and MCP lifecycle governance

This order matches the new audit on purpose.
It is meant to reduce disagreement between planning docs.

---

## What Would Count as Done

This repo should be treated as honestly `v1.0` ready only when all of the following are true:
- critical modules do not fail silently or swallow exceptions without visibility
- the largest high-risk modules have been decomposed enough to reduce regression radius
- core public surfaces have strict mode, function contracts, help, and reasonable output declarations
- CI gates reflect real release risk and cover foundational runtime primitives
- release docs and automation no longer contradict each other
- critical answer and ingestion paths are traceable and explainable
- mixed-artifact and game-asset ingestion outputs are governable, tested, and clearly scoped
- security evidence is part of promotion, not an optional extra
- durable execution and MCP lifecycle rules are enforceable where they matter

Until then, the repo is strong and increasingly disciplined, but still in hardening mode rather than true release-final mode.

---

## Basis for This Document

This summary is derived from:
- `docs/implementation/LLMWorkflow_Post_0.9.6_Strategic_Execution_Plan.md`
- `PROGRESS.md`
- `deep_audit_results.txt`
- current release and architecture documents under `docs/`

