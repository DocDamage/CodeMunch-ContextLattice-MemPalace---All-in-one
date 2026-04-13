# Evaluation Operations

This document describes how evaluation events link to distributed traces, the dashboards operators require, and the priority instrumentation targets for the LLMWorkflow observability backbone.

## Related Docs
- [Observability Architecture](../architecture/OBSERVABILITY_ARCHITECTURE.md)
- [Post-0.9.6 Strategic Execution Plan](../implementation/LLMWorkflow_Post_0.9.6_Strategic_Execution_Plan.md)
- [Implementation Progress](../implementation/PROGRESS.md)
- [Remaining Work](../implementation/REMAINING_WORK.md)

---

## Table of Contents

- [Overview](#overview)
- [Linking Evaluation Events to Traces](#linking-evaluation-events-to-traces)
- [Priority Instrumentation Targets](#priority-instrumentation-targets)
- [Operator Dashboards](#operator-dashboards)
- [Alerting Rules](#alerting-rules)
- [Implementation Checklist](#implementation-checklist)

---

## Overview

Evaluation operations measure the quality, correctness, and performance of LLMWorkflow components. By linking every evaluation event to a trace span, operators can move from aggregate scores to per-request root-cause analysis. The observability backbone ensures that evaluation data is emitted alongside execution traces with shared correlation IDs.

---

## Linking Evaluation Events to Traces

### Correlation Model

Each evaluation event is attached to a trace via the `correlationId` field. The correlation ID is typically the current run ID (from `RunId.ps1`), but it can also be a workflow-specific session identifier.

```mermaid
sequenceDiagram
    participant WF as Workflow
    participant S as Span
    participant E as Evaluator
    participant D as Dashboard

    WF->>S: Start Span: QueryRouter.Resolve
    WF->>E: Evaluate result
    E->>S: Add-SpanEvent -Name "evaluation.scored"<br/>-Attributes @{ score=0.92; threshold=0.80 }
    S->>D: Export with correlationId
    D->>D: Join trace + evaluation by correlationId
```

### Evaluation Event Schema

When an evaluation is recorded, it is added as a span event with the following attributes:

| Attribute | Type | Description |
|-----------|------|-------------|
| `evaluation.score` | double | Normalized score between 0.0 and 1.0. |
| `evaluation.threshold` | double | The passing threshold for the evaluation. |
| `evaluation.result` | string | `pass`, `fail`, or `warning`. |
| `evaluation.metric` | string | Metric name (e.g., `relevance`, `authority_agreement`). |
| `evaluation.granularity` | string | `span`, `batch`, or `session`. |

If an evaluation fails, the span status should be set to `ERROR` and the following attributes are recommended:

| Attribute | Type | Description |
|-----------|------|-------------|
| `error.message` | string | Human-readable reason for failure. |
| `evaluation.expected` | string | Expected output or behavior. |
| `evaluation.actual` | string | Actual output or behavior. |

### Example

```powershell
$span = New-Span -Name "AnswerPlan.Build" | Start-Span

# ... build answer plan ...

$span = $span | Add-SpanEvent -Name "evaluation.scored" -Attributes @{
    "evaluation.score"      = 0.94
    "evaluation.threshold"  = 0.85
    "evaluation.result"     = "pass"
    "evaluation.metric"     = "plan_completeness"
    "evaluation.granularity" = "span"
}

$span = $span | Stop-Span -Status OK
Send-OTelSpan -Span (New-TraceEnvelope -Span $span | Close-TraceEnvelope)
```

---

## Priority Instrumentation Targets

The following components are the highest priority for trace instrumentation because they directly impact answer quality, latency, and system reliability.

### 1. QueryRouter

| Property | Value |
|----------|-------|
| **Span Name** | `QueryRouter.Resolve` |
| **Key Attributes** | `query.text`, `router.strategy`, `pack.count`, `selected.packs` |
| **Evaluation Metric** | Route accuracy, latency P95 |
| **Failure Mode** | No pack selected, timeout, ambiguous query |

QueryRouter is the entry point for most retrieval operations. Instrumentation here captures how user queries are mapped to packs and what strategies are applied.

### 2. AnswerPlan

| Property | Value |
|----------|-------|
| **Span Name** | `AnswerPlan.Build` |
| **Key Attributes** | `plan.steps`, `plan.sources`, `plan.confidence` |
| **Evaluation Metric** | Plan completeness, source coverage |
| **Failure Mode** | Missing steps, low confidence, circular dependencies |

AnswerPlan spans should capture the structure of the generated plan and the confidence score before execution.

### 3. CrossPackArbitration

| Property | Value |
|----------|-------|
| **Span Name** | `CrossPackArbitration.Resolve` |
| **Key Attributes** | `dispute.count`, `arbitration.strategy`, `winner.pack` |
| **Evaluation Metric** | Agreement rate, resolution latency |
| **Failure Mode** | Unresolved dispute, tie, authority mismatch |

Cross-pack arbitration is complex and benefits heavily from child spans per disputed claim.

### 4. ConfidencePolicy

| Property | Value |
|----------|-------|
| **Span Name** | `ConfidencePolicy.Evaluate` |
| **Key Attributes** | `confidence.score`, `policy.threshold`, `policy.action` |
| **Evaluation Metric** | Precision/recall of confidence gating |
| **Failure Mode** | False positive gating, threshold drift |

ConfidencePolicy determines whether an answer is allowed to proceed. Evaluation events here should include the raw score and the threshold that was applied.

### 5. EvidencePolicy

| Property | Value |
|----------|-------|
| **Span Name** | `EvidencePolicy.Validate` |
| **Key Attributes** | `evidence.count`, `evidence.quality`, `policy.result` |
| **Evaluation Metric** | Evidence recall, validation latency |
| **Failure Mode** | Missing citations, low-quality evidence |

EvidencePolicy spans link back to retrieval spans to show which sources were used to justify an answer.

### 6. RetrievalCache

| Property | Value |
|----------|-------|
| **Span Name** | `RetrievalCache.Lookup` |
| **Key Attributes** | `cache.key`, `cache.hit`, `cache.ttl_seconds` |
| **Evaluation Metric** | Hit ratio, stale rate |
| **Failure Mode** | Cache stampede, TTL expiration |

RetrievalCache spans should emit events for `cache.hit` and `cache.miss` to help operators tune TTLs.

### 7. MCP Gateway

| Property | Value |
|----------|-------|
| **Span Name** | `MCPGateway.Ingest` |
| **Key Attributes** | `mcp.source`, `mcp.operation`, `mcp.status_code` |
| **Evaluation Metric** | Ingestion throughput, error rate |
| **Failure Mode** | Rate limiting, auth failure, schema rejection |

MCP gateway spans bridge external ingestion sources into the workflow. Network-level failures are common and must be captured.

### 8. InterPackTransport

| Property | Value |
|----------|-------|
| **Span Name** | `InterPackTransport.Transfer` |
| **Key Attributes** | `source.pack`, `target.pack`, `payload.size_bytes` |
| **Evaluation Metric** | Transfer latency, checksum validation |
| **Failure Mode** | Pack mismatch, serialization error, timeout |

InterPackTransport moves data between packs. Large payloads should have size attributes to correlate latency with throughput.

### 9. SnapshotManager

| Property | Value |
|----------|-------|
| **Span Name** | `SnapshotManager.Create` / `SnapshotManager.Restore` |
| **Key Attributes** | `snapshot.id`, `snapshot.size_bytes`, `snapshot.pack_count` |
| **Evaluation Metric** | Snapshot duration, restore integrity |
| **Failure Mode** | Disk full, corrupt snapshot, version mismatch |

SnapshotManager spans are critical for disaster-recovery runbooks and should always include the snapshot identifier.

### 10. Extraction Pipeline Failures

| Property | Value |
|----------|-------|
| **Span Name** | `ExtractionPipeline.Run` |
| **Key Attributes** | `extractor.type`, `input.files`, `output.records` |
| **Evaluation Metric** | Success rate, records per second |
| **Failure Mode** | Parser error, schema drift, encoding issue |

Extraction pipeline spans should have one child span per extractor so operators can pinpoint which parser failed.

---

## Operator Dashboards

### Dashboard 1: Trace Overview

**Purpose**: High-level health of the workflow platform.

| Panel | Data Source | Query / Filter |
|-------|-------------|----------------|
| Requests/min | Traces | `span_name` exists |
| Error Rate | Traces | `status = ERROR` |
| P95 Latency | Traces | percentile(duration, 95) |
| Top 5 Slowest Spans | Traces | group by `span_name` |
| Evaluation Pass Rate | Span Events | `event.name = "evaluation.scored"` and `evaluation.result = pass` |

### Dashboard 2: Component Drill-Down

**Purpose**: Deep-dive into a single priority component (e.g., QueryRouter).

| Panel | Data Source | Query / Filter |
|-------|-------------|----------------|
| Latency Distribution | Traces | `span_name = QueryRouter.Resolve` |
| Attribute Heatmap | Traces | group by `router.strategy` |
| Evaluation Trend | Span Events | `evaluation.metric = route_accuracy` over time |
| Error Log | Traces + Logs | `status = ERROR` joined by `correlation.id` |

### Dashboard 3: Evaluation Operations

**Purpose**: Track evaluation scores and thresholds across releases.

| Panel | Data Source | Query / Filter |
|-------|-------------|----------------|
| Score Trend | Span Events | `evaluation.score` by `evaluation.metric` |
| Threshold Breaches | Span Events | `evaluation.result = fail` count |
| Component Scorecard | Span Events | average score by `span_name` |
| Correlation Search | Traces + Events | lookup by `correlation.id` |

---

## Alerting Rules

The following alerts are recommended for production operation:

| Alert | Condition | Severity |
|-------|-----------|----------|
| High Error Rate | `ERROR` spans > 5% over 5 minutes | Critical |
| Latency Spike | P95 latency > 2x baseline over 10 minutes | Warning |
| Evaluation Failure | `evaluation.result = fail` > 10% over 15 minutes | Warning |
| Extraction Pipeline Down | Zero successful `ExtractionPipeline.Run` spans for 30 minutes | Critical |
| MCP Gateway Errors | `MCPGateway.Ingest` error rate > 1% over 5 minutes | Warning |
| Cache Hit Rate Drop | `RetrievalCache.Lookup` hit rate < 50% over 10 minutes | Info |

---

## Implementation Checklist

- [ ] `SpanFactory.ps1` imported in all priority target modules.
- [ ] Root spans emit `llmworkflow.runId` and `correlation.id` attributes.
- [ ] Evaluation events use the `evaluation.scored` event name with standard attributes.
- [ ] `OpenTelemetryBridge.ps1` is configured with the correct collector endpoint.
- [ ] Collector is deployed with `configs/observability/otel-collector.yaml`.
- [ ] Dashboards are created in Grafana (or equivalent) using the panel definitions above.
- [ ] Alerts are configured and routed to the on-call channel.

---

## See Also

- `docs/OBSERVABILITY_ARCHITECTURE.md` — Detailed architecture of the telemetry modules.
- `tests/Telemetry.Tests.ps1` — Pester tests for span and envelope correctness.
