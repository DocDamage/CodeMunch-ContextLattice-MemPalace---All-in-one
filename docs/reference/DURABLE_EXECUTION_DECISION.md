# Decision Memo: Durable Execution Engine for LLMWorkflow

**Workstream:** 6 – Durable Orchestration for Long-Running Work  
**Date:** 2026-04-13  
**Status:** Approved  
**Author:** LLM Workflow Team

## 1. Context

LLMWorkflow executes multi-step, long-running operations such as large pack builds, federated memory synchronisation, snapshot exports, and inter-pack transfers. These workflows can run for minutes to hours and must survive:

- Process crashes or host restarts
- Transient network or API failures
- Operator-initiated cancellation
- Resource-pressure pauses

Without a durable execution layer, an interrupted workflow must restart from the beginning, wasting compute and risking data inconsistency.

## 2. Options Evaluated

| Criterion | Temporal | Internal Orchestration (PowerShell) | Argo Workflows |
|---|---|---|---|
| **Durability guarantees** | Strong (event-sourced, replay, exactly-once) | Moderate (file-based checkpoints) | Strong (Kubernetes-native, DAG replay) |
| **Operational complexity** | Medium (requires Temporal Server / Cloud) | Low (runs in existing PowerShell host) | High (requires Kubernetes cluster) |
| **PowerShell integration** | SDK available (.NET / PowerShell wrappers possible) | Native | Indirect (container-based) |
| **Scalability** | High (horizontal workers) | Limited to single node | High (K8s pods) |
| **Learning curve** | Moderate | Low | High |
| **Cost (self-hosted)** | Moderate (DB + server) | Minimal (disk only) | High (K8s infrastructure) |
| **Observability** | Built-in UI, search, tracing | Custom (checkpoints + journals) | Web UI, Prometheus |

### 2.1 Temporal
Temporal provides a durable execution boundary via event sourcing and deterministic workflow replay. Workflows are authored in .NET (C# or PowerShell via the .NET SDK) and executed by Temporal workers. Every activity is checkpointed automatically; retries, timeouts, and cancellation are first-class concepts.

**Pros:** battle-tested durability, clear separation between workflow (orchestration) and activity (execution) code, built-in visibility.  
**Cons:** adds external dependency (PostgreSQL / MySQL + Temporal Server or SaaS cost), requires refactoring existing PowerShell scripts into activities.

### 2.2 Internal Orchestration (PowerShell)
The existing `DurableOrchestrator.ps1` module implements a lightweight checkpoint-and-resume mechanism using JSON files in `.llm-workflow/checkpoints/`. Each step writes its state to disk before proceeding.

**Pros:** zero new infrastructure, immediate PS 5.1 compatibility, minimal code change.  
**Cons:** no automatic replay, no distributed execution, checkpoint consistency is manual, harder to observe across hosts.

### 2.3 Argo Workflows
Argo runs containerised workflows on Kubernetes, expressing DAGs in YAML. It provides artifact passing, retry policies, and a rich UI.

**Pros:** cloud-native, massive scale, declarative DAGs.  
**Cons:** requires a Kubernetes cluster (far beyond current operational footprint), forces containerisation of all PowerShell logic, steep YAML complexity.

## 3. Durability Boundary Model

We define three boundaries:

| Boundary | Definition | Implementation |
|---|---|---|
| **Process boundary** | Survives process crash / restart | Checkpoint files + resume logic |
| **Host boundary** | Survives machine failure | External durable store (Temporal history) |
| **Operator boundary** | Survives human cancellation and later approval | Graceful stop + explicit resume commands |

- **Internal Orchestration** covers the *Process boundary* today.
- **Temporal** covers both *Process* and *Host boundaries*.
- **Argo** covers all three but at unacceptable operational cost for the current team size.

## 4. Recommendation

**Adopt Temporal as the primary durable execution engine** for all workflows that exceed 15 minutes, touch remote systems, or are scheduled to run unattended.

**Retain the internal PowerShell orchestrator** as a lightweight fallback for:
- Short-lived interactive scripts (< 5 minutes)
- Environments where Temporal is unavailable (offline CI agents, local developer machines)
- Quick prototype workflows before they are promoted to Temporal

**Do not pursue Argo Workflows** unless the organisation standardises on Kubernetes and provides cluster management support.

## 5. When to Use Each Option

| Scenario | Recommended Engine | Rationale |
|---|---|---|
| Large pack build (> 1 000 assets) | **Temporal** | Long duration, many external API calls, must survive interruption |
| Snapshot export / import | **Temporal** | Network-bound, retryable activities, needs exactly-once semantics |
| Federated memory sync | **Temporal** | Multi-stage, cross-service, requires timeout and backoff policies |
| Small local ingestion (< 100 files) | **Internal** | Fast, interactive, checkpoint overhead not justified |
| Prototype / spike workflows | **Internal** | Rapid iteration without infrastructure churn |
| Scheduled unattended nightly jobs | **Temporal** | Requires host-level durability and observability |

## 6. Migration Path – Pilot Workflow: Large Pack Build

The **large pack build** is the highest-value pilot because it is the longest-running, most failure-prone workflow today.

### 6.1 Current State
The pack build is driven by a PowerShell script that:
1. Validates the pack manifest
2. Downloads / resolves external dependencies
3. Runs the asset pipeline (extraction, transformation)
4. Produces the output pack and updates the index

If interrupted at step 3, the entire build restarts.

### 6.2 Target State (Temporal)
A Temporal workflow orchestrates the same four steps as **activities**. Each activity is a thin wrapper around the existing PowerShell functions.

### 6.3 Step-by-Step Migration

| Phase | Task | Duration | Success Criteria |
|---|---|---|---|
| **1. Wrapper** | Create `Invoke-PackBuildActivity` C# / PS wrapper for each existing step | 1 week | Activities execute standalone |
| **2. Workflow definition** | Implement `PackBuildWorkflow` in Temporal .NET SDK | 1 week | Workflow runs end-to-end in Temporal dev server |
| **3. Checkpoint parity** | Map existing JSON checkpoint schema to Temporal query handlers | 3 days | Operator can query progress via Temporal Web UI |
| **4. Cut-over** | Add feature flag `UseTemporalForPackBuild`; default off, then on | 1 week | Production builds use Temporal without rollback |
| **5. Cleanup** | Remove file-based checkpoint code for pack build (retain generic `DurableOrchestrator.ps1` for other workflows) | 1 week | No dead code, tests green |

### 6.4 Rollback Plan
If Temporal proves unstable:
1. Flip feature flag to `UseTemporalForPackBuild = $false`
2. The existing PowerShell script resumes via `.llm-workflow/checkpoints/`
3. No data loss because Temporal activities are idempotent and write to the same pack output directory

## 7. Decision

| Decision | Value |
|---|---|
| **Primary durable engine** | Temporal |
| **Fallback engine** | Internal PowerShell orchestration (`DurableOrchestrator.ps1`) |
| **Not selected** | Argo Workflows |
| **Pilot workflow** | Large pack build |
| **Target cut-over** | 4 weeks from approval |

---

*This memo was produced as part of Workstream 6 (Durable Orchestration for Long-Running Work).*
