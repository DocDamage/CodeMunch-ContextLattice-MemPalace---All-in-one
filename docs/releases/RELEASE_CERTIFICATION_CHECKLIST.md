# Release Certification Checklist

> Workstream 8: v1.0 Certification and Release Discipline  
> Version: 1.0.0  
> Status: Use this checklist for every release candidate

This checklist must be completed and signed off before a release candidate can be promoted to a stable v1.0 tag. Each item has a **Check** (what to verify), **Owner** (who is accountable), **Evidence** (where to look), and **Status** (`Pending` / `Pass` / `Fail` / `N/A`).

## Related Docs
- [v1.0 Release Criteria](./V1_RELEASE_CRITERIA.md)
- [Post-0.9.6 Strategic Execution Plan](../implementation/LLMWorkflow_Post_0.9.6_Strategic_Execution_Plan.md)
- [Remaining Work](../implementation/REMAINING_WORK.md)

---

## How to Use

1. Copy this file and rename it to `RELEASE_CERTIFICATION_CHECKLIST_v<version>_<candidate>.md`.
2. Fill in the `Status` column for every row.
3. Attach the JSON report from `scripts/Invoke-ReleaseCertification.ps1` as supporting evidence.
4. Any `Fail` blocks promotion.

---

## 1. Documentation Truth

| # | Check | Owner | Evidence | Status |
|---|-------|-------|----------|--------|
| 1.1 | `VERSION` file exists and is not empty | Release Lead | `VERSION` | Pending |
| 1.2 | `docs/releases/RELEASE_STATE.md` exists and is current | Release Lead | `docs/releases/RELEASE_STATE.md` | Pending |
| 1.3 | `docs/reference/DOCS_TRUTH_MATRIX.md` exists and lists no unresolved drift | Release Lead | `docs/reference/DOCS_TRUTH_MATRIX.md` | Pending |
| 1.4 | README version badge matches `VERSION` | Docs Owner | `README.md` | Pending |
| 1.5 | PROGRESS version and metrics match truth sources | Docs Owner | `PROGRESS.md` | Pending |
| 1.6 | CI validation script catches future drift automatically | CI Owner | `tools/ci/validate-docs-truth.ps1` | Pending |

## 2. Observability

| # | Check | Owner | Evidence | Status |
|---|-------|-------|----------|--------|
| 2.1 | `SpanFactory.ps1` exists and exports span functions | Telemetry Owner | `module/LLMWorkflow/telemetry/SpanFactory.ps1` | Pending |
| 2.2 | `TraceEnvelope.ps1` exists and exports envelope functions | Telemetry Owner | `module/LLMWorkflow/telemetry/TraceEnvelope.ps1` | Pending |
| 2.3 | `OpenTelemetryBridge.ps1` exists and exports payload helpers | Telemetry Owner | `module/LLMWorkflow/telemetry/OpenTelemetryBridge.ps1` | Pending |
| 2.4 | Telemetry tests pass | Telemetry Owner | `tests/Telemetry.Tests.ps1` | Pending |
| 2.5 | Observability architecture is documented | Docs Owner | `docs/OBSERVABILITY_ARCHITECTURE.md` | Pending |

## 3. Policy

| # | Check | Owner | Evidence | Status |
|---|-------|-------|----------|--------|
| 3.1 | `PolicyAdapter.ps1` exists and returns explainable decisions | Policy Owner | `module/LLMWorkflow/policy/PolicyAdapter.ps1` | Pending |
| 3.2 | At least one OPA rego file is present | Policy Owner | `policy/opa/*.rego` | Pending |
| 3.3 | Policy decisions include `Decision` and `Explanation` fields | Policy Owner | `tests/PolicyEngine.Tests.ps1` | Pending |
| 3.4 | Policy runtime model is documented | Docs Owner | `docs/POLICY_RUNTIME_MODEL.md` | Pending |

## 4. Ingestion

### 4.1 Document Ingestion

| # | Check | Owner | Evidence | Status |
|---|-------|-------|----------|--------|
| 4.1.1 | `DoclingAdapter.ps1` exists | Ingestion Owner | `module/LLMWorkflow/ingestion/DoclingAdapter.ps1` | Pending |
| 4.1.2 | `TikaAdapter.ps1` exists | Ingestion Owner | `module/LLMWorkflow/ingestion/TikaAdapter.ps1` | Pending |
| 4.1.3 | `DocumentNormalizer.ps1` exists | Ingestion Owner | `module/LLMWorkflow/ingestion/DocumentNormalizer.ps1` | Pending |
| 4.1.4 | Document ingestion tests pass | Ingestion Owner | `tests/DocumentIngestion.Tests.ps1` | Pending |
| 4.1.5 | Document ingestion model is documented | Docs Owner | `docs/DOCUMENT_INGESTION_MODEL.md` | Pending |

### 4.2 Game Asset Ingestion

| # | Check | Owner | Evidence | Status |
|---|-------|-------|----------|--------|
| 4.2.1 | `SpriteSheetParser.ps1` exists | Asset Owner | `module/LLMWorkflow/extraction/SpriteSheetParser.ps1` | Pending |
| 4.2.2 | `MarketplaceProvenanceNormalizer.ps1` exists | Asset Owner | `module/LLMWorkflow/ingestion/MarketplaceProvenanceNormalizer.ps1` | Pending |
| 4.2.3 | Game asset ingestion tests pass | Asset Owner | `tests/SpriteSheetExtraction.Tests.ps1`, `tests/MarketplaceProvenance.Tests.ps1` | Pending |
| 4.2.4 | Game asset ingestion model is documented | Docs Owner | `docs/GAME_ASSET_INGESTION_MODEL.md` | Pending |

## 5. Security

| # | Check | Owner | Evidence | Status |
|---|-------|-------|----------|--------|
| 5.1 | `Invoke-SecurityBaseline.ps1` exists | Security Owner | `scripts/security/Invoke-SecurityBaseline.ps1` | Pending |
| 5.2 | `Invoke-SBOMBuild.ps1` exists | Security Owner | `scripts/security/Invoke-SBOMBuild.ps1` | Pending |
| 5.3 | `Invoke-SecretScan.ps1` exists | Security Owner | `scripts/security/Invoke-SecretScan.ps1` | Pending |
| 5.4 | `Invoke-VulnerabilityScan.ps1` exists | Security Owner | `scripts/security/Invoke-VulnerabilityScan.ps1` | Pending |
| 5.5 | Security baseline tests pass | Security Owner | `tests/SecurityBaseline.Tests.ps1` | Pending |
| 5.6 | Security baseline is documented | Docs Owner | `docs/SECURITY_BASELINE.md` | Pending |
| 5.7 | Supply chain policy is documented | Docs Owner | `docs/SUPPLY_CHAIN_POLICY.md` | Pending |

## 6. Durable Execution

| # | Check | Owner | Evidence | Status |
|---|-------|-------|----------|--------|
| 6.1 | `DurableOrchestrator.ps1` exists | Workflow Owner | `module/LLMWorkflow/workflow/DurableOrchestrator.ps1` | Pending |
| 6.2 | Checkpoint save function exists | Workflow Owner | `Save-WorkflowCheckpoint` in durable module | Pending |
| 6.3 | Checkpoint resume function exists | Workflow Owner | `Resume-WorkflowCheckpoint` in durable module | Pending |
| 6.4 | Durable execution is tested | Workflow Owner | Durable execution tests in `tests/` | Pending |
| 6.5 | Self-healing / durability is documented | Docs Owner | `docs/SELF_HEALING.md` | Pending |

## 7. MCP Governance

| # | Check | Owner | Evidence | Status |
|---|-------|-------|----------|--------|
| 7.1 | `MCPRegistry.ps1` exists | MCP Owner | `module/LLMWorkflow/mcp/MCPRegistry.ps1` | Pending |
| 7.2 | `MCPLifecycle.ps1` exists | MCP Owner | `module/LLMWorkflow/mcp/MCPLifecycle.ps1` | Pending |
| 7.3 | MCP governance tests pass | MCP Owner | `tests/MCP.Tests.ps1` | Pending |
| 7.4 | MCP exposure policy rego exists | Policy Owner | `policy/opa/mcp_exposure.rego` | Pending |

## 8. Testing

| # | Check | Owner | Evidence | Status |
|---|-------|-------|----------|--------|
| 8.1 | All existing Pester tests pass | QA Owner | `Invoke-Pester tests/` exits 0 | Pending |
| 8.2 | Release certification tests pass | QA Owner | `tests/ReleaseCertification.Tests.ps1` | Pending |
| 8.3 | Test coverage is documented or measured | QA Owner | Coverage report or test inventory | Pending |

## 9. Cross-Workstream Gates

| # | Check | Owner | Evidence | Status |
|---|-------|-------|----------|--------|
| 9.1 | No unresolved critical bugs in issue tracker | Release Lead | Issue tracker query / report | Pending |
| 9.2 | CHANGELOG.md is updated for this release | Release Lead | `CHANGELOG.md` | Pending |
| 9.3 | Compatibility lock is current | Release Lead | `compatibility.lock.json` | Pending |
| 9.4 | All required docs listed in V1_RELEASE_CRITERIA exist | Release Lead | `docs/V1_RELEASE_CRITERIA.md` | Pending |
| 9.5 | `Invoke-ReleaseCertification.ps1` runs without errors | Release Lead | Certification report JSON + Markdown | Pending |

---

## Sign-Off

| Role | Name | Date | Signature / Approval |
|------|------|------|----------------------|
| Release Lead | | | |
| Engineering Lead | | | |
| Security Owner | | | |
| QA Owner | | | |

---

## Automated Report Attachment

Attach the output of:

```powershell
scripts\Invoke-ReleaseCertification.ps1 -ProjectRoot . -OutputPath .\certification-reports
```

Expected artifacts:
- `certification-report-<timestamp>.json`
- `certification-report-<timestamp>.md`
