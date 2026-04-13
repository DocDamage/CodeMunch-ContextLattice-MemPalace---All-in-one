# Policy Runtime Model

This document describes the policy externalization and enforcement architecture for the LLM Workflow platform. It covers the policy adapter, decision cache, explainability model, and guidance for adding new policy domains.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Policy Adapter](#policy-adapter)
- [Decision Cache](#decision-cache)
- [Explainability](#explainability)
- [OPA Policy Domains](#opa-policy-domains)
- [Adding a New Policy Domain](#adding-a-new-policy-domain)
- [Integration with Execution Mode System](#integration-with-execution-mode-system)

---

## Overview

The LLM Workflow platform implements a policy gate before any destructive or agent-invokable operation (Invariant 3.6). To support scalable governance, the policy system is externalized through an OPA-style adapter layer. When an external engine is unavailable, the adapter transparently falls back to an in-process evaluator so that safety checks are never skipped.

Key design goals:

- **Externalization**: Decouple policy logic from application code.
- **Resilience**: Never fail open; always fall back to a safe in-process evaluator.
- **Performance**: Cache repeated decisions with TTL.
- **Explainability**: Every decision includes a human-readable explanation.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     LLM Workflow Runtime                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Policy Gate  │─▶│ PolicyAdapter│─▶│ External OPA Engine  │  │
│  │ (Invoker)    │  │ (Client)     │  │ (HTTP endpoint)      │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│         │                 │                                     │
│         ▼                 ▼                                     │
│  ┌──────────────┐  ┌──────────────┐                            │
│  │ DecisionCache│  │ In-Process   │                            │
│  │ (TTL cache)  │  │ Fallback     │                            │
│  └──────────────┘  └──────────────┘                            │
└─────────────────────────────────────────────────────────────────┘
```

1. **Invoker** calls the adapter with a domain and input.
2. **Adapter** checks the cache, then tries the external engine.
3. If the engine is unreachable, the adapter evaluates the request in-process.
4. The result is cached (if configured) and returned with an explanation.

---

## Policy Adapter

The adapter is implemented in `module/LLMWorkflow/policy/PolicyAdapter.ps1`.

### Functions

| Function | Purpose |
|----------|---------|
| `New-PolicyAdapter` | Creates an adapter configuration (engine URI, timeout, fallback mode). |
| `Invoke-PolicyDecision` | Evaluates a decision against the configured engine and returns `allow`/`deny` plus explanation. |
| `Test-PolicyDecision` | Boolean wrapper over `Invoke-PolicyDecision`. |
| `Get-PolicyExplanation` | Returns a human-readable explanation string from a decision result. |

### Fallback Modes

- **`in-process`** (default): Evaluates the request using built-in PowerShell rules that mirror the OPA policies.
- **`default-decision`**: Returns a fixed default decision (`allow` or `deny`) without evaluation.

### Example

```powershell
$adapter = New-PolicyAdapter `
    -EngineUri "http://localhost:8181/v1/data/llmworkflow" `
    -EngineType "opa" `
    -FallbackMode "in-process"

$result = Invoke-PolicyDecision -Adapter $adapter `
    -Domain "execution_mode" `
    -InputObject @{ mode = "ci"; command = "build"; safetyLevel = "Mutating" }

if ($result.Decision -eq "allow") {
    # proceed
}
```

---

## Decision Cache

The cache is implemented in `module/LLMWorkflow/policy/PolicyDecisionCache.ps1`. It stores policy decisions in memory with a configurable TTL to avoid repeated engine round-trips.

### Functions

| Function | Purpose |
|----------|---------|
| `Get-PolicyDecisionCache` | Retrieves a cached entry by key if it has not expired. |
| `Set-PolicyDecisionCache` | Stores a decision result with a TTL. |
| `Test-PolicyDecisionCache` | Returns `$true` if a valid cached entry exists. |
| `Clear-PolicyDecisionCache` | Removes entries (all, expired only, or by key). |
| `New-PolicyCacheKey` | Generates a deterministic cache key from adapter ID, domain, and input. |

### TTL Behavior

- Default TTL is **300 seconds** (5 minutes).
- Expired entries are treated as cache misses and are removed on the next access.
- Explicit `Clear-PolicyDecisionCache -ExpiredOnly` can be used for periodic housekeeping.

### Cache Key Design

Cache keys are stable hashes produced from the adapter ID, domain, and a sorted serialization of the input object:

```powershell
$key = New-PolicyCacheKey -AdapterId $adapter.AdapterId -Domain "execution_mode" -InputObject $input
```

---

## Explainability

Every policy decision returned by `Invoke-PolicyDecision` includes an `Explanation` field. The explanation is generated by:

1. **External engine**: OPA policies return a structured `explanation` string.
2. **Fallback evaluator**: In-process rules produce domain-specific messages (e.g., "Destructive operations are not allowed in 'ci' mode").

`Get-PolicyExplanation` can augment the explanation with additional context, such as noting that the decision was produced via a fallback path.

---

## OPA Policy Domains

OPA policies are stored under `policy/opa/` and are organized by domain:

| Policy File | Domain | Concern |
|-------------|--------|---------|
| `execution_mode.rego` | `execution_mode` | Maps commands and safety levels to allowed execution modes. |
| `mcp_exposure.rego` | `mcp_exposure` | Governs which MCP tools may be exposed and under what review/scope constraints. |
| `interpack_transfer.rego` | `interpack_transfer` | Validates source quarantine, promotion tiers, and provenance for asset transfers. |
| `workspace_boundary.rego` | `workspace_boundary` | Enforces visibility boundaries (`private`, `local-team`, `shared`, `public-reference`). |

Each policy follows these conventions:

- `package llmworkflow.<domain>`
- `default allow := false`
- `allow` rule composed of constraint checks
- `explanation` rule for human-readable decision rationale

---

## Adding a New Policy Domain

To add a new policy domain (e.g., `budget_enforcement`):

### 1. Create the Rego Policy

Create `policy/opa/budget_enforcement.rego`:

```rego
package llmworkflow.budget_enforcement

import future.keywords.if
import future.keywords.in

default allow := false

allow if {
    input.estimatedCost <= input.budgetLimit
    input.currency == "USD"
}

explanation := "Budget check passed." if { allow }
explanation := "Estimated cost exceeds budget limit." if { not allow }
```

### 2. Add In-Process Fallback

In `module/LLMWorkflow/policy/PolicyAdapter.ps1`, extend `Invoke-InProcessPolicyEngine`:

```powershell
"budget_enforcement" {
    return Evaluate-BudgetEnforcementPolicy -InputObject $InputObject
}
```

Add the evaluator function:

```powershell
function Evaluate-BudgetEnforcementPolicy {
    param([hashtable]$InputObject)
    # ... evaluation logic ...
}
```

### 3. Add Tests

Add Pester tests in `tests/PolicyEngine.Tests.ps1` covering the new domain.

### 4. Document

Update this document to list the new domain in the OPA Policy Domains table.

---

## Integration with Execution Mode System

The policy adapter works alongside the existing execution mode system (`module/LLMWorkflow/core/ExecutionMode.ps1` and `Policy.ps1`). The typical flow is:

1. The runtime determines the current execution mode via `Get-CurrentExecutionMode`.
2. Before a command is executed, the runtime calls `Test-PolicyDecision` with the `execution_mode` domain.
3. If the policy adapter denies the operation, the runtime raises `PermissionDeniedByMode` (exit code 11) and blocks execution.
4. If the adapter allows the operation, the runtime proceeds to any confirmation or lock gates.

This layering ensures that policy externalization does not bypass existing safety invariants.
