# LLM Workflow — Canonical Document Set (v3)

This is the active canonical document set for the LLM Workflow platform.

Use the files in this order:

1. **[Part 1 — Core Architecture and Operations](sandbox:/mnt/data/LLMWorkflow_Canonical_Document_Set_Part_1_Core_Architecture_and_Operations.md)**
2. **[Part 2 — RPG Maker MZ Pack and Acceptance](sandbox:/mnt/data/LLMWorkflow_Canonical_Document_Set_Part_2_RPGMaker_MZ_Pack_and_Acceptance.md)**
3. **[Part 3 — Godot, Blender, Inter-Pack, and Roadmap](sandbox:/mnt/data/LLMWorkflow_Canonical_Document_Set_Part_3_Godot_Blender_InterPack_and_Roadmap.md)**
4. **[Part 4 — Future Pack Intake and Source Candidates](sandbox:/mnt/data/LLMWorkflow_Canonical_Document_Set_Part_4_Future_Pack_Intake_and_Source_Candidates_v2.md)**
5. **[Appendage A — Godot Pack Additional Candidate Repositories](sandbox:/mnt/data/Godot_Pack_Appendage_Additional_Candidate_Repositories_v2.md)**

## Purpose of Part 4

Part 4 is the canonical place for **new repo intake decisions** that do **not** belong inside the currently active worked-example packs (`rpgmaker-mz`, `godot-engine`, `blender-engine`).

It exists so that:
- repo names are preserved
- future pack ideas stay concrete
- the core pack specs do not get polluted with unrelated sources
- candidate packs can be promoted later without losing evaluation history

## Purpose of Appendage A

Appendage A is the canonical add-on for **expanded Godot pack source intake** that is specific enough to matter operationally, but not yet merged into Part 3.

It exists so that:
- new Godot repos are preserved by name
- Godot-specific routing, extraction, and authority rules stay concrete
- the active Godot pack can grow without forcing a risky rewrite of Part 3 every pass
- approved appendage material can later be promoted into the main Godot section once stabilized

## Canonical editing rule

- Edit **Part 1–3** only when changing active architecture or active pack specs.
- Edit **Part 4** when evaluating new repos, future packs, or intake candidates outside the active worked-example packs.
- Edit **Appendage A** when expanding the Godot repo candidate set, routing rules, extraction targets, or evaluation tasks before those changes are promoted into Part 3.
- When candidate or appendage material becomes fully adopted, move it into the appropriate active part and mark the source entry as promoted/superseded.

## Candidate status meanings

- **Adopt now** — strong enough to add to the future-pack intake registry immediately
- **Conditional** — useful, but only if that domain becomes an actual toolkit target
- **Hold / Skip** — not worth adding now, duplicate, too educational, too stale, or wrong layer

## Implementation Status

| Phase | Description | Status | Module Location |
|-------|-------------|--------|-----------------|
| Phase 1 | Reliability & Control Foundation | ✅ Complete | `module/LLMWorkflow/core/` (16 files, 100+ functions) |
| Phase 2 | Pack Framework & Source Registry | ✅ Complete | `module/LLMWorkflow/pack/` (3 files, 27 functions) |
| Phase 3 | Operator Workflow & Guarded Execution | ✅ Complete | `module/LLMWorkflow/workflow/` (6 files, 52 functions) |
| Phase 4 | Structured Extraction Pipeline | ✅ Complete | `module/LLMWorkflow/extraction/` (7 files, 69 functions) |
| Phase 5 | Retrieval & Answer Integrity | ✅ Complete | `module/LLMWorkflow/retrieval/` (9 files, 140+ functions) |
| Phase 6 | Human Trust & Governance | ✅ Complete | `module/LLMWorkflow/governance/` (5 files, 85+ functions) |
| Phase 7 | Platform Expansion (MCP, Inter-Pack) | ✅ Complete | `module/LLMWorkflow/mcp/`, `module/LLMWorkflow/interpack/`, `module/LLMWorkflow/snapshot/` (11 files, 250+ functions) |

**Current Version:** 0.8.0  
**Total Functions:** 725+  
**Last Updated:** 2026-04-12

### Phase 4 Extraction Parsers

| Parser | File Types | Functions | Status |
|--------|------------|-----------|--------|
| GDScript Parser | `.gd` | 12 | ✅ Implemented |
| Godot Scene Parser | `.tscn`, `.tres` | 9 | ✅ Implemented |
| RPG Maker Plugin Parser | `.js` (plugins) | 12 | ✅ Implemented |
| Blender Python Parser | `.py` (addons) | 12 | ✅ Implemented |
| Geometry Nodes Parser | Node trees | 8 | ✅ Implemented |
| Shader Parser | `.gdshader`, `.shader` | 20 | ✅ Implemented |
| Pipeline Orchestrator | All types | 8 | ✅ Implemented |

### Phase 5 Retrieval & Answer Integrity

| Module | Purpose | Functions | Status |
|--------|---------|-----------|--------|
| QueryRouter.ps1 | Query routing and intent detection | 10 | ✅ Implemented |
| RetrievalProfiles.ps1 | Profile management (7 profiles) | 10 | ✅ Implemented |
| AnswerPlan.ps1 | Answer planning and tracing | 12 | ✅ Implemented |
| CrossPackArbitration.ps1 | Cross-pack arbitration | 15 | ✅ Implemented |
| ConfidencePolicy.ps1 | Confidence and abstain policy | 8 | ✅ Implemented |
| EvidencePolicy.ps1 | Evidence validation and policy | 10 | ✅ Implemented |
| CaveatRegistry.ps1 | Known caveats and falsehoods | 14 | ✅ Implemented |
| RetrievalCache.ps1 | Cache and invalidation | 20 | ✅ Implemented |
| IncidentBundle.ps1 | Answer incident tracking | 15 | ✅ Implemented |

### Phase 6 Human Trust & Governance

| Module | Purpose | Functions | Status |
|--------|---------|-----------|--------|
| HumanAnnotations.ps1 | Annotations and overrides | 12 | ✅ Implemented |
| GoldenTasks.ps1 | Golden task evals (10 tasks) | 10 | ✅ Implemented |
| ReplayHarness.ps1 | Replay and regression testing | 12 | ✅ Implemented |
| PackSLOs.ps1 | SLOs and telemetry | 12 | ✅ Implemented |
| HumanReviewGates.ps1 | Review gates and approvals | 22 | ✅ Implemented |

## Current note

Appendage A currently contains the extended Godot candidate set, including testing, AI behavior, dialogue, quest, inventory, rollback networking, editor VCS, signal visualization, save convenience, RPG data frameworks, chunk streaming, alternate voxel terrain, platform-service integration, and lightweight FSM sources.

**Phase 5 & 6 Complete:** Retrieval, answer integrity, human trust, and governance modules are now fully implemented. The platform now supports:
- Query routing with 7 retrieval profiles
- Cross-pack arbitration with dispute resolution
- Answer planning and traceability
- Confidence-based abstain/escalation policies
- Caveat registry with known falsehoods
- Human annotations and project overrides
- Golden task evaluation framework
- Replay harness for regression testing
- Pack SLOs and telemetry tracking
- Human review gates for sensitive operations
