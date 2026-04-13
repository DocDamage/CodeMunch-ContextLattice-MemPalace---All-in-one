# LLM Workflow - Post-0.9.6 Strategic Execution Plan

## Document Purpose

This document defines the strategic execution plan for the LLM Workflow platform after the Phase 1-8 buildout and the 0.9.6-era documentation update.

This is not a bootstrap plan.
This is a stabilization, integration, ingestion-hardening, and v1.0-readiness plan.

The platform is already beyond the point where raw feature count is the main problem.
The next stage is about making the system:
- operationally trustworthy
- easier to observe and debug
- stricter about policy and governance
- better at mixed artifact and game asset ingestion
- safer to release and evolve

---

## Executive Summary

The correct move now is not another random expansion phase.
It is a discipline phase.

The platform already has a strong architecture across:
- operational core and state safety
- pack framework and source registries
- structured extraction
- retrieval and answer integrity
- human review and governance
- MCP and inter-pack capabilities
- promoted domain packs and broad engine-facing coverage

What it still needs is coherence at the program level.
The main risks are no longer lack of ideas. The main risks are drift, ambiguity, weak observability, and uneven ingestion quality across non-code artifacts.

The execution plan therefore focuses on eight tightly-scoped workstreams:
1. versioning and documentation truth
2. observability and evaluation backbone
3. policy externalization and enforcement
4. artifact and game asset ingestion hardening
5. security and supply-chain enforcement
6. durable orchestration for long-running work
7. retrieval substrate upgrades and MCP governance
8. v1.0 certification and release discipline

---

## Current Baseline

This plan assumes the following broad baseline:
- core phases are complete through Phase 8
- the platform has 10 domain packs
- the codebase is now large enough that operational leverage matters more than raw surface area
- metric counts in docs are not yet fully reconciled and must be treated as provisional until Workstream 1 lands

The baseline also includes several concrete additions that materially affect the roadmap.

### Recently Landed or In-Flight at Head

The platform now has early foundation work for broader game asset handling, including:
- engine-aware game preset folder scaffolding
- a multi-engine asset manifest model
- asset classification for spritesheets, tilemaps, plugins, RPG Maker assets, Unreal assets, Epic/Fab assets, and shared bundles
- Unreal descriptor extraction for `.uplugin` and `.uproject`
- regression coverage for asset manifests and Unreal descriptor extraction

This matters because the ingestion roadmap is no longer hypothetical. Some of it has already started and must now be reflected in the strategic plan.

### Baseline Reality

The project is now a multi-domain orchestration platform, not just a toolkit repo.
That changes the standard for progress.

Progress is no longer measured mainly by:
- module count
- function count
- pack count
- candidate repo count

Progress is now measured by:
- whether release truth is coherent
- whether failures are diagnosable
- whether policy is enforceable and explainable
- whether evidence quality holds up across mixed artifacts
- whether external integrations are governed
- whether the system can scale without answer-quality drift

---

## North Star

Turn the current platform into a v1.0-ready, evidence-governed, policy-enforced, operationally observable workflow system that can handle both code-centric and mixed artifact workloads safely.

### What v1.0 Should Mean

For this project, v1.0 should mean:
1. state integrity is trusted by default
2. documentation and release state have one operational truth
3. retrieval and answer behavior are measurable and debuggable
4. policy is a runtime concern, not only implementation discipline
5. mixed artifact ingestion is robust enough for real-world usage
6. game asset and engine descriptor intake is governed, traceable, and extensible
7. security and supply-chain posture are operational defaults
8. MCP growth is governed rather than organic sprawl
9. long-running work can recover cleanly from interruption

---

## Non-Goals

The following are explicitly not the priorities of this cycle:
- adding random new packs without governance pressure
- inflating module or function counts as a goal in itself
- replacing the architecture wholesale
- building distributed complexity before local observability is trustworthy
- treating marketplace or engine integrations as production-ready without provenance and policy controls
- pretending binary engine asset formats are solved before descriptor, manifest, and provenance layers are solid

---

## Strategic Frame

This cycle should be executed in two parallel tracks that stay coordinated.

### Track A - Platform Discipline

This track focuses on:
- version truth
- observability
- policy runtime
- security
- durable execution
- retrieval and MCP governance

### Track B - Evidence and Artifact Coverage

This track focuses on:
- document ingestion quality
- artifact normalization
- game asset inventory and classification
- engine descriptor parsing
- provenance and license normalization for external asset sources

Track B should not become a side quest. The platform is already moving toward game asset handling, so that work must be folded into the main program with the same standards as every other subsystem.

---

## Workstream Overview

| Workstream | Goal | Priority | Primary Release Window |
|---|---|---:|---|
| 1. Versioning and Documentation Truth | one operational truth for release state and metrics | Immediate | v0.9.7 |
| 2. Observability and Evaluation Backbone | traceable, diagnosable system behavior | Immediate | v0.9.7-v0.9.8 |
| 3. Policy Externalization and Enforcement | enforceable and explainable runtime controls | High | v0.9.8 |
| 4. Artifact and Game Asset Ingestion Hardening | mixed artifact and engine-aware intake that preserves provenance | High | v0.9.8-v0.9.9 |
| 5. Security and Supply-Chain Enforcement | safer promotion and release posture | High | v0.9.9 |
| 6. Durable Orchestration for Long-Running Work | resilient execution under interruption and retry | Medium-High | v1.0.0-rc1 |
| 7. Retrieval Substrate and MCP Governance | controlled backend growth and tool lifecycle governance | Medium-High | v1.0.0-rc1 |
| 8. v1.0 Certification and Release Discipline | explicit exit criteria and release gating | High | v1.0.0 |

---

# Workstream 1 - Versioning and Documentation Truth

## Objective

Eliminate ambiguity between README, changelog, progress tracking, canonical docs, manifests, and release labels so the project has one operational truth.

## Why This Matters

A platform built around provenance and auditability cannot tolerate documentation drift as a normal condition.
If the docs disagree about what exists, then operators and contributors lose trust before runtime behavior is even considered.

## Deliverables

- root-level `VERSION`
- `docs/RELEASE_STATE.md`
- `docs/DOCS_TRUTH_MATRIX.md`
- deterministic doc/version update helper
- CI validation for version and metric drift

## Required Outcomes

- each public-facing doc clearly distinguishes stable release state vs documented head state
- counters use documented counting rules
- CI catches contradictions automatically
- release prep becomes deterministic instead of manual archaeology

## Immediate Tasks

1. Create a single source of version truth.
2. Define release-state labels such as `released`, `documented-head`, `planned`, and `experimental`.
3. Normalize metric definitions for modules, functions, parsers, MCP tools, and packs.
4. Add CI validation across README, CHANGELOG, PROGRESS, canonical docs, and relevant manifests.
5. Add a release-state summary block to top-level docs.

## Acceptance Criteria

- no top-level doc contradicts the declared version source
- metric counts either reconcile automatically or are clearly scope-labeled
- CI fails when drift appears
- release-state ambiguity is eliminated

---

# Workstream 2 - Observability and Evaluation Backbone

## Objective

Move from "telemetry exists" to "telemetry is operationally useful."

## Strategic Direction

Adopt a structured observability backbone using:
- OpenTelemetry Collector for transport and normalization
- an LLM/eval observability layer such as Langfuse or Arize Phoenix

## Deliverables

- OTel instrumentation bridge
- answer lifecycle trace schema
- correlation ID propagation model
- trace-linked eval events
- operator dashboards for latency, abstain rates, parser failures, MCP failures, and regressions

## Required Outputs

- `module/LLMWorkflow/telemetry/OpenTelemetryBridge.ps1`
- `module/LLMWorkflow/telemetry/TraceEnvelope.ps1`
- `module/LLMWorkflow/telemetry/SpanFactory.ps1`
- `configs/observability/otel-collector.yaml`
- `docs/OBSERVABILITY_ARCHITECTURE.md`
- `docs/EVALUATION_OPERATIONS.md`

## Priority Instrumentation Targets

Start with:
- QueryRouter
- AnswerPlan
- CrossPackArbitration
- ConfidencePolicy
- EvidencePolicy
- RetrievalCache
- MCP gateway and toolkit server paths
- InterPackTransport
- SnapshotManager
- extraction pipeline failures by parser and file type

## Acceptance Criteria

- a single query can be traced end-to-end
- eval results link back to traces
- parser and tool failures are visible without log archaeology
- answer incidents can be pivoted by pack, profile, parser, source authority, and tool path

---

# Workstream 3 - Policy Externalization and Enforcement

## Objective

Turn policy from internal code logic into an explicit, testable, runtime-enforced system boundary.

## Strategic Direction

Adopt OPA or an equivalent policy engine for core policy domains.

## Deliverables

- externalized policy definitions
- policy adapter inside the toolkit
- policy decision explain mode
- independent policy regression suites
- policy bundle versioning and rollback model

## Required Outputs

- `policy/opa/*.rego`
- `module/LLMWorkflow/policy/PolicyAdapter.ps1`
- `module/LLMWorkflow/policy/PolicyDecisionCache.ps1`
- `docs/POLICY_RUNTIME_MODEL.md`
- `tests/PolicyEngine.Tests.ps1`

## Policy Domains

- execution mode policy
- command capability policy
- visibility and export policy
- workspace boundary policy
- human review policy
- MCP exposure policy
- inter-pack transfer policy
- source quarantine and promotion policy
- external asset and marketplace ingestion policy

## Acceptance Criteria

- critical permissions are externally enforceable
- denied or escalated actions are explainable
- policy regressions are testable independent of implementation modules
- governance decisions can be audited without reading the whole codebase

---

# Workstream 4 - Artifact and Game Asset Ingestion Hardening

## Objective

Upgrade ingestion so the platform handles real-world mixed artifacts and engine-specific game assets with consistent provenance, classification, and evidence quality.

## Why This Workstream Is Now Broader

Earlier planning treated ingestion mostly as a document problem.
That is no longer enough.

The platform now has active work toward handling:
- spritesheets
- tilemaps
- RPG Maker assets and plugins
- Unreal project and plugin descriptors
- Epic and Fab-sourced assets
- shared game content bundles

The strategy therefore needs to treat document ingestion and game asset ingestion as one coordinated evidence problem with different artifact classes.

## 4A - Document Ingestion Hardening

### Strategic Direction

Use:
- Docling as the preferred intelligent document ingestion layer
- Apache Tika as a broad fallback

### Deliverables

- external document ingestion adapter
- document normalization pipeline
- trust-aware document evidence classifier
- OCR vs non-OCR routing rules
- quarantine path for low-quality extraction

### Required Outputs

- `module/LLMWorkflow/ingestion/DoclingAdapter.ps1`
- `module/LLMWorkflow/ingestion/TikaAdapter.ps1`
- `module/LLMWorkflow/ingestion/DocumentNormalizer.ps1`
- `module/LLMWorkflow/ingestion/DocumentEvidenceClassifier.ps1`
- `docs/DOCUMENT_INGESTION_MODEL.md`
- `tests/DocumentIngestion.Tests.ps1`

## 4B - Game Asset and Engine Intake Hardening

### Strategic Direction

Treat game asset handling as a structured ingestion layer, not just file inventory.

The platform should support, at minimum:
- asset manifest and folder scaffolding for engine-aware projects
- classification of shared game asset families
- descriptor parsing for engine metadata files
- provenance and license normalization for marketplace content
- progressive extraction support for asset families that can be parsed safely

### Already Landed or In Motion

The current head state already includes:
- engine-aware asset manifest structure
- game preset folders for `art`, `spritesheets`, `tilemaps`, `plugins`, `rpgmaker`, `unreal`, `epic`, and `shared`
- asset scan classification across those families
- Unreal descriptor extraction for `.uplugin` and `.uproject`
- regression tests for the asset manifest and Unreal descriptor pipeline

### What Still Needs To Be Done

#### Game asset classification and normalization
- formalize the asset family taxonomy in documentation and tests
- add normalized provenance fields for marketplace and vendor-derived assets
- add license normalization for original, OSS, Creative Commons, proprietary, and restricted marketplace content

#### RPG Maker asset ingestion
- parse RPG Maker project asset directories such as character sheets, faces, tilesets, parallaxes, and audio folders
- distinguish project assets from plugin code and plugin metadata
- preserve engine-specific folder semantics in normalized output

#### Spritesheet and atlas ingestion
- add parser support for common spritesheet formats and atlas metadata
- support Aseprite sources and common JSON atlas sidecars
- preserve frame counts, frame geometry, animation names, and atlas relationships where available

#### Unreal and Epic intake
- keep `.uplugin` and `.uproject` as the first-class safe metadata layer
- add inventory-only handling and provenance classification for `.uasset`, `.umap`, `.ubulk`, `.uexp`, and packaged bundles until deeper parsing is justified
- add Fab and Epic provenance normalization so marketplace content is identifiable and reviewable

#### Cross-engine plugin and integration inventory
- normalize plugin metadata across RPG Maker, Unreal, Godot, and future engines where feasible
- mark mutating or build-affecting plugins with review-aware metadata

### Required Outputs

- `docs/GAME_ASSET_INGESTION_MODEL.md`
- `module/LLMWorkflow/extraction/RPGMakerAssetCatalogParser.ps1`
- `module/LLMWorkflow/extraction/SpriteSheetParser.ps1`
- `module/LLMWorkflow/extraction/AtlasMetadataParser.ps1`
- `module/LLMWorkflow/ingestion/MarketplaceProvenanceNormalizer.ps1`
- `module/LLMWorkflow/ingestion/AssetLicenseNormalizer.ps1`
- `tests/RPGMakerAssetCatalog.Tests.ps1`
- `tests/SpriteSheetExtraction.Tests.ps1`
- `tests/MarketplaceProvenance.Tests.ps1`

### Acceptance Criteria

- mixed artifacts are normalized into auditable evidence structures
- weakly extracted documents do not outrank cleaner sources silently
- game asset manifests preserve provenance, license, and engine family classification
- Unreal project and plugin descriptors route through structured extraction cleanly
- RPG Maker assets and common spritesheet formats have at least one safe normalized extraction path
- marketplace content is identifiable, classifiable, and reviewable

---

# Workstream 5 - Security and Supply-Chain Enforcement

## Objective

Make secret handling, dependency visibility, vulnerability scanning, and quarantine policy first-class operational controls.

## Strategic Direction

Adopt a baseline security toolchain using:
- TruffleHog for secret scanning
- Semgrep for static analysis rules
- Syft for SBOM generation
- Trivy for vulnerability and configuration scanning

## Deliverables

- security baseline pipeline
- SBOM generation for release artifacts
- vulnerability and misconfiguration scanning
- CI and promotion gates tied to findings
- governance and dashboard integration for security findings

## Required Outputs

- `scripts/security/Invoke-SecurityBaseline.ps1`
- `scripts/security/Invoke-SBOMBuild.ps1`
- `scripts/security/Invoke-SecretScan.ps1`
- `scripts/security/Invoke-VulnerabilityScan.ps1`
- `docs/SECURITY_BASELINE.md`
- `docs/SUPPLY_CHAIN_POLICY.md`

## Acceptance Criteria

- scanning is part of the default workflow
- major artifacts emit SBOMs
- critical findings can block promotion
- security findings show up in governance and incident flows

---

# Workstream 6 - Durable Orchestration for Long-Running Work

## Objective

Strengthen long-running, retry-heavy workflows so they survive interruption and recover deterministically.

## Strategic Direction

Evaluate:
- Temporal as the primary durable execution candidate
- Argo Workflows only if the target deployment model becomes explicitly Kubernetes-centric

## Deliverables

- decision memo on internal orchestration vs Temporal-backed durability
- durability boundary model
- pilot workflow migrated or prototyped
- failure taxonomy and recovery playbooks

## Recommended Pilot Workflows

- large pack build or refresh
- snapshot export or import
- federated memory synchronization
- large external ingestion workflow
- inter-pack transfer with promote and rollback semantics
- asset catalog refresh for large game content trees

## Acceptance Criteria

- at least one high-value workflow is proven recoverable
- recovery steps are deterministic and observable
- rollback remains intact
- durable execution does not bypass policy, review, or provenance rules

---

# Workstream 7 - Retrieval Substrate and MCP Governance

## Objective

Improve the retrieval substrate while preventing MCP growth from turning into ungoverned tool sprawl.

## Strategic Direction

### Retrieval candidates
Choose one primary direction:
- Qdrant for production-grade vector retrieval and filtering
- LanceDB for strong local or embedded ergonomics
- Graphiti if temporally aware graph memory becomes strategically important

### MCP governance candidates
Use:
- official MCP Registry for discoverability and metadata governance
- canonical server references for implementation baselines

## Deliverables

- retrieval substrate decision memo
- backend role model
- MCP tool registry and lifecycle rules
- capability taxonomy for MCP tools
- registry sync and discovery workflow

## Required Outputs

- `docs/RETRIEVAL_SUBSTRATE_DECISION.md`
- `docs/MCP_GOVERNANCE_MODEL.md`
- `module/LLMWorkflow/mcp/MCPToolRegistry.ps1`
- `module/LLMWorkflow/mcp/MCPToolLifecycle.ps1`
- `module/LLMWorkflow/retrieval/RetrievalBackendAdapter.ps1`

## Governance Rules

Each MCP tool should declare:
- tool ID
- owning pack
- safety level
- execution mode requirements
- mutating vs read-only status
- review requirements
- dependency footprint
- telemetry tags
- deprecation and replacement rules

The same governance model should eventually extend to engine-aware asset tooling and parsers that alter project state.

## Acceptance Criteria

- retrieval backend responsibilities are explicit
- MCP growth is governed through metadata and lifecycle states
- tool discovery does not depend on tribal knowledge
- mutating tool exposure is reviewable and auditable

---

# Workstream 8 - v1.0 Certification and Release Discipline

## Objective

Prevent v1.0 from becoming a vague aspiration by turning it into a measurable certification target.

## Deliverables

- explicit v1.0 exit criteria
- release readiness checklist
- cross-workstream gate review cadence
- release-candidate certification workflow

## Required Outputs

- `docs/V1_RELEASE_CRITERIA.md`
- `docs/RELEASE_CERTIFICATION_CHECKLIST.md`
- `tests/ReleaseCertification.Tests.ps1`

## Minimum Certification Questions

Before declaring v1.0, the project should be able to answer yes to all of the following:
- do the docs agree on what the current state is
- can a critical answer path be traced end-to-end
- are major policy decisions externally enforceable and explainable
- can the platform ingest mixed documents with provenance and confidence metadata
- can the platform inventory and classify game assets without losing provenance semantics
- are security scans and SBOMs part of normal operations
- is at least one long-running workflow durably recoverable
- is MCP lifecycle governance active

## Acceptance Criteria

- v1.0 exit criteria are documented before the final release push
- release-candidate gating is testable
- release declarations map to observable and enforceable system behavior

---

# Cross-Workstream Quality Gates

These apply to every workstream.

## Gate A - No silent authority drift
Any new integration must not weaken:
- source authority ordering
- private-project precedence
- confidence thresholds
- contradiction surfacing

## Gate B - No hidden policy bypass
Any new subsystem must respect:
- execution mode checks
- safety levels
- human review gates
- visibility boundaries

## Gate C - No observability blind spots
Any new critical path must emit:
- run ID
- correlation ID
- traceable events
- structured error classification

## Gate D - No release-state ambiguity
All additions must update:
- version truth
- release-state docs
- changelog and progress surfaces
- pack, parser, or tool counts if they change public-facing summaries

## Gate E - No expansion without tests
Every meaningful addition must include:
- happy path coverage
- failure path coverage
- recovery or interruption coverage where relevant
- policy or pathological-case coverage where relevant

## Gate F - No marketplace or engine asset ambiguity
Any new asset intake path must preserve:
- engine family
- source and marketplace provenance
- license semantics
- review requirements where ownership or redistribution is unclear

---

# Delivery Sequence

## Wave 0 - Reconcile truth
Focus:
- Workstream 1

Outcome:
- docs, metrics, and release status stop contradicting each other

## Wave 1 - Make the system observable
Focus:
- Workstream 2

Outcome:
- answer lifecycle, parser failures, and tool paths become traceable and debuggable

## Wave 2 - Make policy system-grade
Focus:
- Workstream 3

Outcome:
- permissions, review gates, and exposure boundaries gain explicit enforcement

## Wave 3 - Harden ingestion quality
Focus:
- Workstream 4A and the highest-value parts of 4B

Outcome:
- mixed documents and the current game-asset scope become first-class, governable evidence inputs

## Wave 4 - Lock down security posture
Focus:
- Workstream 5

Outcome:
- scanning, SBOMs, and promotion gates become operational defaults

## Wave 5 - Harden long-running execution
Focus:
- Workstream 6

Outcome:
- major workflows become resilient under interruption and retry

## Wave 6 - Normalize backend and MCP governance
Focus:
- Workstream 7

Outcome:
- retrieval substrate and tool lifecycle stop drifting into ad hoc growth

## Wave 7 - Certify release readiness
Focus:
- Workstream 8

Outcome:
- v1.0 becomes a checked condition, not a mood

---

# Suggested Release Mapping

## v0.9.7
Primary targets:
- version and docs truth reconciliation
- initial observability architecture baseline
- first OTel bridge and trace schema
- docs truth validation in CI

## v0.9.8
Primary targets:
- policy adapter
- first externalized policy bundles
- observability dashboards
- document and game-asset ingestion model docs
- formal recognition of the new asset taxonomy at head

## v0.9.9
Primary targets:
- document ingestion adapters
- marketplace and asset provenance normalization
- security baseline automation
- initial SBOM pipeline
- RPG Maker asset catalog extraction and first spritesheet parser path

## v1.0.0-rc1
Primary targets:
- durable workflow pilot
- retrieval substrate decision finalized
- MCP governance registry active
- cross-workstream gates passing
- Unreal descriptor extraction and asset-manifest coverage fully documented and release-aligned

## v1.0.0
Primary targets:
- stable release-state model
- traceable answer lifecycle
- enforceable policy runtime
- hardened artifact and game-asset ingestion posture
- governed MCP lifecycle
- documented recovery model for long-running operations

---

# Testing Expansion Plan

## Immediate Additions

### Documentation and release tests
- version consistency tests
- count reconciliation tests
- release-state validation tests

### Observability tests
- span presence on critical routes
- correlation ID propagation
- telemetry export failure behavior
- parser failure trace tagging

### Policy tests
- allow and deny matrix coverage
- review-gate trigger coverage
- workspace boundary policy tests
- MCP mutating access tests
- asset provenance review-policy tests

### Artifact ingestion tests
- PDF and document extraction comparisons
- OCR downgrade behavior
- translated-source authority downgrade behavior
- page and section traceability tests
- asset manifest classification tests
- Unreal descriptor extraction tests
- RPG Maker asset catalog tests
- spritesheet and atlas parsing tests
- marketplace provenance normalization tests

### Security tests
- secret scan fixtures
- SBOM generation tests
- misconfiguration detection tests
- promotion-block behavior tests

### Durable execution tests
- interrupted-run recovery tests
- duplicate retry dedupe tests
- rollback integrity tests
- partial-transfer recoverability tests

### MCP governance tests
- lifecycle state enforcement tests
- metadata completeness tests
- mutating tool registration policy tests
- deprecated tool visibility tests

---

# Major Risks

## Risk 1 - Integration bloat without leverage
If too many external systems are added at once, the platform becomes harder to reason about.

### Mitigation
- adopt integrations only when each has a named role
- require decision memos before adoption
- prefer one clear winner per problem class

## Risk 2 - Shadow architecture
If new integrations live beside the architecture instead of inside it, the project splits into parallel systems.

### Mitigation
- every integration must map into existing policy, provenance, journaling, and review structures

## Risk 3 - Observability theater
Telemetry can look impressive without helping diagnosis.

### Mitigation
- instrument a small number of critical flows deeply before widening coverage

## Risk 4 - Policy complexity explosion
Externalized policy can become unreadable if it is not structured well.

### Mitigation
- separate policy domains
- enforce naming conventions
- add explainability from day one

## Risk 5 - Retrieval substrate confusion
Multiple backend layers can create role confusion and stale assumptions.

### Mitigation
- publish backend responsibility boundaries before major adoption

## Risk 6 - MCP sprawl
More tools can quickly turn into governance debt.

### Mitigation
- require metadata, lifecycle state, telemetry tags, and review policy for every tool

## Risk 7 - Asset ingestion overclaim
It is easy to say "supports game assets" while only inventorying them shallowly.

### Mitigation
- distinguish inventory support, descriptor parsing support, and deep extraction support explicitly in docs and tests

## Risk 8 - Marketplace provenance ambiguity
Marketplace and Epic/Fab content can create ownership and redistribution confusion.

### Mitigation
- normalize provenance and license fields early
- require review-friendly metadata before expanding mutating workflows around such assets

---

# What Should Happen First

If execution continues immediately, the first concrete sequence should be:

1. reconcile version and metric truth across docs
2. add docs consistency validation to CI
3. define the observability trace schema
4. instrument routing, evidence, confidence, extraction, and MCP gateway paths
5. write the policy externalization plan and begin adapter-based migration
6. publish the artifact and game asset ingestion model
7. normalize marketplace provenance and asset license handling
8. add RPG Maker asset catalog extraction and a first spritesheet parser path
9. add security baseline automation
10. pilot durable execution on one workflow only
11. formalize MCP registry and lifecycle controls
12. freeze v1.0 release criteria and work backward from them

That is the right order because it improves operational control first, while still acknowledging that artifact and game-asset ingestion is already part of the real roadmap.

---

# Final Recommendation

The project does not need another undisciplined expansion wave.
It needs a disciplined integration phase that makes the current platform coherent, observable, governable, and ingestion-robust.

The right move now is:
- fewer shiny additions
- more release truth
- more observability
- more explicit policy
- stronger mixed artifact ingestion
- more honest game-asset support definitions
- stronger security baselines
- better governed tooling

That is how this becomes a serious v1.0 platform instead of a large but increasingly fragile toolkit.

---

# Exit Criteria for This Plan

This plan can be considered executed when:
- documentation no longer disagrees about release truth
- critical answer and extraction flows are traceable end-to-end
- major policy decisions are externally enforceable and explainable
- document ingestion is robust enough for mixed-source evidence
- game asset manifests preserve engine family, provenance, and license semantics
- Unreal project and plugin descriptors are documented, tested, and release-aligned
- security scanning and SBOM generation are part of normal operations
- at least one long-running workflow is durably recoverable
- MCP tool growth is governed with lifecycle rules and metadata
- the platform has a credible, testable v1.0 release path
