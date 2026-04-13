# v1.0 Release Criteria

> Workstream 8: v1.0 Certification and Release Discipline  
> Version: 1.0.0  
> Status: Active

This document defines the explicit exit criteria for declaring LLMWorkflow v1.0 certified and release-ready. Each criterion is derived from the strategic plan and must be satisfied with yes/no evidence before the release candidate can be promoted.

## Related Docs
- [Post-0.9.6 Strategic Execution Plan](../implementation/LLMWorkflow_Post_0.9.6_Strategic_Execution_Plan.md)
- [Remaining Work](../implementation/REMAINING_WORK.md)
- [Release Certification Checklist](./RELEASE_CERTIFICATION_CHECKLIST.md)

---

## Overview

A v1.0 release of LLMWorkflow is certified only when **all** of the following questions can be answered **Yes** with supporting evidence. Any **No** answer blocks release promotion.

---

## Criterion 1: Documentation Truth

### Question
**Do the docs agree on what the current state is?**

### Requirement
- The [`VERSION`](../VERSION) file is the single source of truth for the declared version.
- [`docs/releases/RELEASE_STATE.md`](../../docs/releases/RELEASE_STATE.md) accurately describes the state of every major component.
- [`docs/reference/DOCS_TRUTH_MATRIX.md`](../../docs/reference/DOCS_TRUTH_MATRIX.md) has been reconciled and shows no unacknowledged drift.
- All top-level documents (`README.md`, `PROGRESS.md`, canonical docs) agree on version and metric counts.

### Pass Criteria
| Check | Evidence |
|-------|----------|
| `VERSION` exists and is not empty | File present, one-line semantic version |
| `RELEASE_STATE.md` exists and is current | Last updated within the release window |
| `DOCS_TRUTH_MATRIX.md` exists and lists no unresolved drift | Drift table is empty or all items have resolution dates |
| CI validation catches future drift automatically | `tools/ci/validate-docs-truth.ps1` exists and exits 0 |

### Fail Criteria
- `VERSION` is missing, empty, or does not follow semver.
- `DOCS_TRUTH_MATRIX.md` shows unresolved drift in version, module count, pack count, or parser count.
- CI validation script is missing or fails in the release pipeline.

---

## Criterion 2: Critical Answer Path

### Question
**Can a critical answer path be traced end-to-end?**

### Requirement
- Every confidence-graded answer produced by the platform can trace back through retrieval, arbitration, evidence policy, and provenance.
- The path includes: query routing, cross-pack arbitration, confidence scoring, evidence attachment, and caveat registration.

### Pass Criteria
| Check | Evidence |
|-------|----------|
| Query routing module exists | `module/LLMWorkflow/retrieval/QueryRouter.ps1` |
| Cross-pack arbitration exists | `module/LLMWorkflow/retrieval/CrossPackArbitration.ps1` |
| Confidence policy exists | `module/LLMWorkflow/retrieval/ConfidencePolicy.ps1` |
| Evidence policy exists | `module/LLMWorkflow/retrieval/EvidencePolicy.ps1` |
| Caveat registry exists | `module/LLMWorkflow/retrieval/CaveatRegistry.ps1` |
| A documented walkthrough exists | `docs/EVALUATION_OPERATIONS.md` describes the path |
| Retrieval backend adapter exists | `module/LLMWorkflow/retrieval/RetrievalBackendAdapter.ps1` |

### Fail Criteria
- Any module in the critical path is missing.
- No documented walkthrough of an end-to-end answer exists.

---

## Criterion 3: Policy Enforceability

### Question
**Are major policy decisions externally enforceable and explainable?**

### Requirement
- The platform integrates an externalized policy engine (OPA-style) with an in-process fallback.
- Policy decisions must return an allow/deny result and a human-readable explanation.
- Rego bundles or equivalent external policy artifacts are present and versioned.

### Pass Criteria
| Check | Evidence |
|-------|----------|
| Policy adapter exists | `module/LLMWorkflow/policy/PolicyAdapter.ps1` |
| At least one OPA rego file exists | `policy/opa/*.rego` |
| Policy decisions return explainable results | `Invoke-PolicyDecision` returns `Decision` and `Explanation` properties |
| Policy runtime model is documented | `docs/POLICY_RUNTIME_MODEL.md` exists |

### Fail Criteria
- Policy adapter is missing.
- No external policy artifacts (rego files) are present.
- Policy decisions are opaque (no explanation field).

---

## Criterion 4: Mixed Document Ingestion

### Question
**Can the platform ingest mixed documents with provenance and confidence metadata?**

### Requirement
- The platform can ingest PDF, DOCX, PPTX, and common office formats.
- Ingestion adapters (Docling, Tika) normalize output to a common schema.
- Provenance (source path, extraction timestamp, engine) and confidence scores are attached to every document.

### Pass Criteria
| Check | Evidence |
|-------|----------|
| Docling adapter exists | `module/LLMWorkflow/ingestion/DoclingAdapter.ps1` |
| Tika adapter exists | `module/LLMWorkflow/ingestion/TikaAdapter.ps1` |
| Document normalizer exists | `module/LLMWorkflow/ingestion/DocumentNormalizer.ps1` |
| Ingestion model is documented | `docs/DOCUMENT_INGESTION_MODEL.md` exists |
| Every extraction result includes provenance and confidence | Adapter tests assert `sourcePath`, `extractedAt`, `engine`, and `confidence` fields |

### Fail Criteria
- Any required adapter or normalizer is missing.
- Extraction output omits provenance or confidence fields.

---

## Criterion 5: Game Asset Inventory

### Question
**Can the platform inventory and classify game assets without losing provenance semantics?**

### Requirement
- The platform can parse spritesheets, marketplace metadata, and engine-specific descriptors.
- Parsed assets retain source path, license, author, and extraction pipeline version.
- Normalized manifests are suitable for downstream cataloging.

### Pass Criteria
| Check | Evidence |
|-------|----------|
| Spritesheet parser exists | `module/LLMWorkflow/extraction/SpriteSheetParser.ps1` |
| Marketplace provenance normalizer exists | `module/LLMWorkflow/ingestion/MarkplaceProvenanceNormalizer.ps1` |
| Game asset ingestion model is documented | `docs/GAME_ASSET_INGESTION_MODEL.md` exists |
| Parsed manifests include provenance fields | Tests assert `sourcePath`, `parsedAt`, `parserVersion` |

### Fail Criteria
- Required parser or normalizer is missing.
- Asset manifests omit provenance or pipeline version.

---

## Criterion 6: Security Scans and SBOMs

### Question
**Are security scans and SBOMs part of normal operations?**

### Requirement
- Secret scanning, vulnerability scanning, and SBOM generation are automated.
- A consolidated security baseline script can be invoked in CI/CD.
- Promotion gates block release when critical or high findings exceed thresholds.

### Pass Criteria
| Check | Evidence |
|-------|----------|
| Security baseline orchestrator exists | `scripts/security/Invoke-SecurityBaseline.ps1` |
| SBOM build script exists | `scripts/security/Invoke-SBOMBuild.ps1` |
| Secret scan script exists | `scripts/security/Invoke-SecretScan.ps1` |
| Vulnerability scan script exists | `scripts/security/Invoke-VulnerabilityScan.ps1` |
| Security baseline is documented | `docs/SECURITY_BASELINE.md` exists |
| Supply chain policy is documented | `docs/SUPPLY_CHAIN_POLICY.md` exists |
| Promotion gate logic is implemented | `Test-PromotionGate` blocks on configurable thresholds |

### Fail Criteria
- Any required security script is missing.
- Promotion gates do not block on critical findings.
- SBOM output is missing or malformed.

---

## Criterion 7: Durable Execution

### Question
**Is at least one long-running workflow durably recoverable?**

### Requirement
- The platform includes a durable orchestrator module capable of checkpointing workflow state.
- The orchestrator can resume a workflow after interruption without data loss.
- Recovery behavior is documented and covered by automated tests.

### Pass Criteria
| Check | Evidence |
|-------|----------|
| Durable orchestrator module exists | `module/LLMWorkflow/workflow/DurableOrchestrator.ps1` |
| Checkpoint/recovery functions are implemented | `Save-WorkflowCheckpoint` and `Resume-WorkflowCheckpoint` exist |
| Recovery is tested | `tests/` include at least one durable-execution test |
| Durable execution is documented | `docs/SELF_HEALING.md` or equivalent covers durable recovery |

### Fail Criteria
- Durable orchestrator module is missing.
- No checkpoint/resume functions are implemented.
- No automated test validates recovery behavior.

---

## Criterion 8: MCP Lifecycle Governance

### Question
**Is MCP lifecycle governance active?**

### Requirement
- MCP tools are registered in a governed registry.
- Lifecycle rules (enable, disable, deprecate, version) are enforced by a module.
- Tool metadata includes capability taxonomy and exposure boundaries.

### Pass Criteria
| Check | Evidence |
|-------|----------|
| MCP registry module exists | `module/LLMWorkflow/mcp/MCPRegistry.ps1` |
| MCP lifecycle module exists | `module/LLMWorkflow/mcp/MCPLifecycle.ps1` |
| MCP governance tests pass | `tests/MCP.Tests.ps1` or equivalent validates registry and lifecycle |
| MCP exposure policy exists | `policy/opa/mcp_exposure.rego` |

### Fail Criteria
- MCP registry or lifecycle module is missing.
- No policy artifact governs MCP exposure.
- No automated test validates MCP governance behavior.

---

## Final Certification Gate

Before the release candidate is promoted to v1.0:

1. Run `scripts/Invoke-ReleaseCertification.ps1` with `-ProjectRoot` set to the repository root.
2. Verify that `Test-ReleaseCriteria` returns `$true` for **all** categories.
3. Review the JSON and Markdown reports produced by `Export-CertificationReport`.
4. Obtain sign-off from the release owner documented in `docs/RELEASE_CERTIFICATION_CHECKLIST.md`.

**If any criterion fails, the release is blocked until remediation and re-certification.**
