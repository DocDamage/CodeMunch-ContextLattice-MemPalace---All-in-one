# Retrieval Substrate Decision Memo

## Workstream 7 — Retrieval Substrate and MCP Governance

**Status:** Approved  
**Date:** 2026-04-13  
**Author:** LLMWorkflow Architecture Team  
**Scope:** Primary vector retrieval backend and embedded/local fallback for the LLMWorkflow platform.

## Related Docs
- [MCP Governance Model](../architecture/MCP_GOVERNANCE_MODEL.md)
- [Implementation Progress](../implementation/PROGRESS.md)
- [Remaining Work](../implementation/REMAINING_WORK.md)
- [v1.0 Release Criteria](../releases/V1_RELEASE_CRITERIA.md)

---

## 1. Decision Summary

LLMWorkflow will adopt a **dual-backend retrieval substrate**:

| Role | Backend | Use Case |
|------|---------|----------|
| **Primary (Production)** | Qdrant | Production-grade vector search, hybrid filtering, multi-tenant collections, and horizontal scaling. |
| **Fallback (Embedded/Local)** | LanceDB | Offline workstations, CI runners without containerized services, air-gapped environments, and quick-start onboarding. |

This decision balances operational maturity, embedding performance, filtering expressiveness, and operational simplicity for PowerShell-centric deployments.

---

## 2. Evaluation Criteria

The following criteria were weighted during evaluation:

1. **Hybrid Query Support** — vector + payload filtering for pack-aware retrieval.
2. **Operational Footprint** — ease of deployment in Windows/PowerShell environments.
3. **PowerShell Accessibility** — REST-first or file-first APIs that do not require native Python dependencies in the host process.
4. **Embedding Efficiency** — HNSW performance at 10K–1M document scale per workspace.
5. **License and Distribution** — permissive licensing compatible with the project’s MIT license.

---

## 3. Candidate Analysis

### 3.1 Qdrant (Selected as Primary)

- **Deployment model:** Docker / Kubernetes / managed cloud / Windows binary.
- **Interface:** HTTP REST API with JSON payloads; no client-side native runtime required.
- **Filtering:** Rich payload filtering (match, range, geo, full-text) that aligns with pack metadata schemas.
- **Scalability:** Collections can shard across peers; suitable for multi-workspace or multi-pack deployments.
- **PowerShell fit:** `Invoke-RestMethod` can target Qdrant endpoints directly with standard PS 5.1 syntax.

**Risks and mitigations:**
- Requires a running service. Mitigated by LanceDB fallback and a lightweight local Qdrant mode via Docker Compose.

### 3.2 LanceDB (Selected as Fallback)

- **Deployment model:** File-based (Arrow tables) with optional embedded server.
- **Interface:** File I/O + optional HTTP when the small Rust-based server is launched locally.
- **Filtering:** SQL-like filters over Arrow columns; sufficient for local pack queries.
- **Scalability:** Best up to mid-size datasets (millions of rows); perfectly adequate for single-workstation use.
- **PowerShell fit:** File paths are native to PowerShell; optional HTTP mode uses the same adapter pattern as Qdrant.

**Risks and mitigations:**
- Less mature distributed story. Mitigated by restricting LanceDB to single-node fallback scenarios.

### 3.3 Rejected Candidates

- **Chroma** — Evaluated favorably for local use, but its distributed operational model is less mature than Qdrant and its REST contract evolved rapidly during evaluation.
- **Weaviate** — Strong feature set, but heavier operational footprint and GraphQL-first interface add friction in pure PowerShell clients.
- **Milvus/Zilliz** — Excellent at very large scale, but introduces unnecessary complexity for the current target scale.
- **pgvector** — Good for SQL-aligned teams, but couples the retrieval substrate to a Postgres operational lifecycle that many Windows-first users do not already maintain.

---

## 4. Backend Role Model

```
┌─────────────────────────────────────────────────────────────┐
│                    RetrievalBackendAdapter                  │
│  ─────────────────────────────────────────────────────────  │
│  Unified PowerShell surface:                                │
│   New-RetrievalBackendAdapter                               │
│   Search-RetrievalBackend                                   │
│   Add-RetrievalDocument                                     │
│   Remove-RetrievalDocument                                  │
│   Test-RetrievalBackendConnection                           │
└─────────────────────────────────────────────────────────────┘
                            │
            ┌───────────────┴───────────────┐
            │                               │
    ┌───────▼───────┐               ┌───────▼───────┐
    │    Qdrant     │               │   LanceDB     │
    │   (Primary)   │               │  (Fallback)   │
    │  HTTP REST    │               │  File + HTTP  │
    │  Collections  │               │  Local Tables │
    │  Cloud ready  │               │  Zero install │
    └───────────────┘               └───────────────┘
```

---

## 5. Responsibility Boundaries

| Concern | Qdrant Primary | LanceDB Fallback |
|---------|----------------|------------------|
| **Embedding storage** | Collection-per-pack or single collection with `packId` payload filter. | Table-per-pack or single table with `packId` partition. |
| **Filtering** | Payload filters + vector search in one request. | SQL filter string passed alongside vector query. |
| **Connection config** | `QDRANT_URL`, `QDRANT_API_KEY`, `QDRANT_COLLECTION_PREFIX`. | `LANCEDB_PATH` (directory on disk), optional `LANCEDB_HOST` for embedded server. |
| **Adapter impl** | `Invoke-RestMethod` against Qdrant REST endpoints. | File-based mock + optional HTTP when server is available. |
| **Failure behavior** | On connection failure, emit a typed error; caller may elect LanceDB fallback if configured. | Always local; failures are filesystem or schema errors. |
| **Operational upgrades** | Schema migrations managed via Qdrant collection aliases and versioning scripts. | Table versions managed by directory naming and backup rotation. |

---

## 6. Configuration Precedents

Environment variables drive backend selection in `Get-EffectiveConfig`:

```powershell
$retrievalConfig = @{
    backend = $env:LLM_RETRIEVAL_BACKEND  # "qdrant" | "lancedb"
    qdrant = @{
        url = $env:QDRANT_URL
        apiKey = $env:QDRANT_API_KEY
        collectionPrefix = $env:QDRANT_COLLECTION_PREFIX
    }
    lancedb = @{
        path = $env:LANCEDB_PATH
        host = $env:LANCEDB_HOST
    }
}
```

If `backend` is not explicitly set, the adapter attempts Qdrant first and degrades to LanceDB when `Test-RetrievalBackendConnection` fails.

---

## 7. Migration and Rollout

1. **Phase 7a** — Implement `RetrievalBackendAdapter` with Qdrant HTTP mocks and LanceDB file mocks.
2. **Phase 7b** — Integrate adapter into `QueryRouter` for cross-pack retrieval.
3. **Phase 7c** — Add Docker Compose service for local Qdrant; update `LLMWorkflow.Post_0.9.6_Strategic_Execution_Plan.md`.
4. **Phase 7d** — Document production deployment patterns (managed Qdrant, backup, monitoring).

---

## 8. Decision Record

| Date | Action | Owner |
|------|--------|-------|
| 2026-04-13 | Approved dual-backend substrate: Qdrant primary, LanceDB fallback. | Architecture Team |

---

*This memo is part of the LLMWorkflow canonical document set. Changes require a PR and human review gate.*
