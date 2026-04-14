# Release State

## Current Version

**Declared Version:** `0.9.6` (see root [`VERSION`](../../VERSION))

## Related Docs
- [Implementation Progress](../implementation/PROGRESS.md)
- [Remaining Work](../implementation/REMAINING_WORK.md)
- [Documentation Truth Matrix](../reference/DOCS_TRUTH_MATRIX.md)

## Release State Labels

| Label | Meaning |
|-------|---------|
| `released` | Shipped in a tagged release, stable |
| `documented-head` | Implemented at HEAD, documented, not yet in a stable tag |
| `planned` | Scheduled in the current strategic plan |
| `experimental` | Prototype or spike, may change significantly |

## Component States

| Component | State | Notes |
|-----------|-------|-------|
| Core infrastructure (Phase 1) | released | Journaling, locking, config, policy, execution modes |
| Pack framework (Phase 2) | released | Manifests, source registries, transactions |
| Operator workflow (Phase 3) | released | Health scores, planner, git hooks, compatibility |
| Structured extraction (Phase 4) | released | 30 parsers across code and asset formats |
| Retrieval and answer integrity (Phase 5) | released | Query routing, arbitration, confidence, evidence |
| Human trust and governance (Phase 6) | released | Annotations, SLOs, review gates, golden tasks |
| MCP and inter-pack (Phase 7) | released | Toolkit servers, composite gateway, transport |
| Extended packs (Phase 8) | released | 10 domain packs stable |
| Game asset manifest scaffolding | documented-head | Engine-aware folders, asset classification |
| Unreal descriptor extraction | documented-head | `.uplugin` and `.uproject` parsing |
| RPG Maker asset catalog | documented-head | `img/*`, `audio/*`, `js/plugins` inventory |
| Observability backbone | documented-head | OTel bridge, trace schema, span factory (36 tests) |
| Policy externalization | documented-head | OPA adapter, externalized bundles, decision cache (29 tests) |
| Document ingestion adapters | documented-head | Docling/Tika adapters, normalizer, evidence classifier (21 tests) |
| Security baseline | documented-head | Secret scanning, SBOM, vulnerability scanning (20 tests) |
| Durable execution | documented-head | DurableOrchestrator, FailureTaxonomy, recovery playbooks (20 tests) |
| MCP governance registry | documented-head | MCPToolRegistry, MCPToolLifecycle, governance model (26 tests) |

## Metric Definitions

These definitions are used to keep counts consistent across README, PROGRESS, and canonical docs.

- **PowerShell Module**: A `.ps1` file under `module/LLMWorkflow/` that exports functions and is not a test file or template helper.
  - Current count: **121**
- **Domain Pack**: A JSON manifest under `packs/manifests/` with a matching source registry.
  - Current count: **10**
- **Extraction Parser**: A parser or extractor module under `module/LLMWorkflow/ingestion/parsers/` whose filename ends in `Parser.ps1` or `Extractor.ps1`.
  - Current count: **30**
- **Golden Task**: A predefined evaluation scenario declared in `module/LLMWorkflow/governance/GoldenTaskDefinitions.ps1`.
  - Current count: **60**
- **MCP Tool**: A declared tool in an MCP toolkit server manifest.
  - Current count: **55**

## Change Log

| Date | Version | Change |
|------|---------|--------|
| 2026-04-13 | 0.9.6 | Added remediation status alignment across README, progress, audit, remaining work, and strategic plan |
| 2026-04-13 | 0.9.6 | Added release-state documentation and truth reconciliation |
| 2026-04-14 | 0.9.6 | Reconciled version drift and released vs documented-head wording across top-level docs; fixed parser count to 30 and added CHANGELOG to truth matrix |

