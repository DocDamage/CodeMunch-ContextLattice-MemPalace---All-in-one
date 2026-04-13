# MCP Governance Model

## Workstream 7 — Retrieval Substrate and MCP Governance

**Version:** 1.0.0  
**Date:** 2026-04-13  
**Status:** Draft  
**Scope:** Model Context Protocol (MCP) tool registry, capability taxonomy, metadata requirements, lifecycle rules, and governance policies for the LLMWorkflow platform.

---

## 1. Overview

The LLMWorkflow platform exposes functionality to external callers (including LLM agents) through an MCP-compatible tool surface. To ensure safety, observability, and controlled evolution, every MCP tool must be registered in a **canonical tool registry** and governed by the rules in this document.

---

## 2. Tool Registry

The canonical registry is an in-memory hashtable backed by JSON. It is managed by `MCPToolRegistry.ps1`.

### 2.1 Registry Operations

| Operation | Function | Purpose |
|-----------|----------|---------|
| Create | `New-MCPToolRegistry` | Initializes a new in-memory registry. |
| Register | `Register-MCPTool` | Adds a tool with complete metadata. |
| Retrieve | `Get-MCPTool` | Returns one tool’s metadata. |
| Discover | `Find-MCPTools` | Lists tools filtered by pack, capability, or safety level. |
| Export | `Export-MCPToolRegistry` | Serializes the registry to JSON. |
| Import | `Import-MCPToolRegistry` | Hydrates the registry from JSON. |

### 2.2 Registry Schema

Each entry in the registry is a hashtable/JSON object with the following top-level keys:

```json
{
  "toolId": "string",
  "owningPack": "string",
  "safetyLevel": "read-only | mutating | destructive | networked",
  "executionModeRequirements": ["interactive", "ci", "watch", "mcp-readonly", "mcp-mutating"],
  "isMutating": false,
  "isReadOnly": true,
  "reviewRequired": false,
  "dependencyFootprint": ["module1", "module2"],
  "telemetryTags": ["search", "retrieval", "pack-aware"],
  "capability": "search | ingest | transform | explain | diagnose | heal | governance",
  "deprecated": false,
  "deprecationNotice": null,
  "replacedBy": null,
  "lifecycleState": "draft | experimental | stable | deprecated | retired",
  "registeredAt": "2026-04-13T10:00:00Z",
  "updatedAt": "2026-04-13T10:00:00Z",
  "version": "1.0.0"
}
```

---

## 3. Required Metadata Fields

Every MCP tool MUST declare the following metadata at registration time.

### 3.1 Core Identity

| Field | Type | Description |
|-------|------|-------------|
| `toolId` | String | Globally unique tool identifier. Format: lowercase alphanumerics, hyphens, underscores. Max length 64. |
| `owningPack` | String | The pack that owns this tool (e.g., `core`, `rpgmaker-mz`, `godot`, `retrieval`). |
| `version` | String | Semantic version of the tool contract. |

### 3.2 Safety and Execution

| Field | Type | Description |
|-------|------|-------------|
| `safetyLevel` | String | One of: `read-only`, `mutating`, `destructive`, `networked`. |
| `executionModeRequirements` | String[] | Modes under which the tool may run. Empty array means no restrictions. |
| `isMutating` | Boolean | `true` if the tool changes state outside the registry. |
| `isReadOnly` | Boolean | `true` if the tool only reads state. Mutually exclusive with `isMutating` at the logical level, though a tool may declare both if it has mixed paths. |

### 3.3 Governance

| Field | Type | Description |
|-------|------|-------------|
| `reviewRequired` | Boolean | If `true`, promotions to `stable` or changes to `safetyLevel` require human review gate approval. |
| `dependencyFootprint` | String[] | List of module or package dependencies required for execution. |
| `telemetryTags` | String[] | Tags used for telemetry routing and cost attribution. |
| `capability` | String | Taxonomy bucket. See §4. |

### 3.4 Deprecation and Replacement

| Field | Type | Description |
|-------|------|-------------|
| `deprecated` | Boolean | `true` if the tool is no longer recommended. |
| `deprecationNotice` | String | Human-readable explanation of why the tool was deprecated and what replaces it. |
| `replacedBy` | String | `toolId` of the preferred replacement, if any. |
| `lifecycleState` | String | Current state. See §5. |

---

## 4. Capability Taxonomy

All MCP tools MUST declare exactly one primary capability from the following taxonomy:

| Capability | Description | Example Tools |
|------------|-------------|---------------|
| `search` | Vector or keyword search over indexed documents. | `Search-RetrievalBackend` |
| `ingest` | Ingestion of external content into the platform. | `Invoke-GitHubRepoIngestion` |
| `transform` | Data transformation, normalization, or extraction. | `Parse-BlenderPythonScript` |
| `explain` | Explainability, summarization, or documentation retrieval. | `Get-PackManifest`, `Get-ExecutionModeContext` |
| `diagnose` | Health checks, issue detection, or drift analysis. | `Test-PackHealth`, `Test-LLMWorkflowIssue` |
| `heal` | Automated repair, remediation, or state correction. | `Repair-LLMWorkflowIssue` |
| `governance` | Policy enforcement, review gates, or audit functions. | `Test-PolicyPermission`, `Submit-ReviewDecision` |

---

## 5. Lifecycle Rules

Tools move through a finite state machine managed by `MCPToolLifecycle.ps1`.

### 5.1 States

| State | Meaning |
|-------|---------|
| `draft` | Under active development; not visible to external callers. |
| `experimental` | Available for testing; may change without deprecation notice. |
| `stable` | Fully supported; contract changes require semver bump and review. |
| `deprecated` | Still callable, but emits warnings; replacement should be used. |
| `retired` | No longer callable; registry entry kept for audit only. |

### 5.2 Allowed Transitions

```
draft ──► experimental ──► stable ──► deprecated ──► retired
    │          │            │            ▲
    │          ▼            ▼            │
    └────► retired ◄─────────────────────┘
```

Explicit allowed transitions:

- `draft` → `experimental`
- `draft` → `retired`
- `experimental` → `stable`
- `experimental` → `retired`
- `stable` → `deprecated`
- `stable` → `retired` (emergency only; requires review gate)
- `deprecated` → `retired`
- `deprecated` → `stable` (reversal; requires review gate)

All other transitions are **denied** by `Test-MCPToolLifecycleTransition`.

### 5.3 Deprecation Rules

1. A tool MUST be in `deprecated` state for at least **one minor release cycle** before transition to `retired`.
2. Deprecation MUST populate `deprecationNotice` and `replacedBy` (if applicable).
3. Deprecated tools MUST remain visible in `Find-MCPTools` so that integrators can discover the replacement.
4. Calling a deprecated tool MAY emit a structured warning but MUST NOT fail unless the tool is `retired`.

### 5.4 Review Requirements

- `reviewRequired` tools cannot move to `stable` without a completed review gate.
- Changes to `safetyLevel`, `isMutating`, or `capability` on a `stable` tool require re-review.

---

## 6. Governance Rules

### 6.1 Registration Rules

1. `toolId` must be unique within the registry. Re-registration with the same `toolId` is treated as an update and bumps `updatedAt`.
2. `owningPack` must be a known pack identifier.
3. `safetyLevel` must be one of the allowed values.
4. If `isMutating` is `true`, `safetyLevel` cannot be `read-only`.
5. `lifecycleState` defaults to `draft` if not specified.

### 6.2 Execution Rules

1. The MCP gateway (`MCPCompositeGateway.ps1`) MUST check `lifecycleState` before dispatching a tool call.
2. `retired` tools MUST be rejected with exit code `9` (`PolicyBlocked`).
3. Tools with `executionModeRequirements` MUST be rejected if the current mode is not in the allowed list.
4. `destructive` tools MUST pass `Request-Confirmation` when invoked in `interactive` mode unless `-Confirm:$false` is explicitly supplied.

### 6.3 Telemetry Rules

1. Every tool invocation MUST emit a telemetry event tagged with `telemetryTags`.
2. Tool failures MUST include `toolId`, `owningPack`, `lifecycleState`, and `safetyLevel` in the failure payload.

### 6.4 Sync Rules

`Invoke-MCPToolRegistrySync` reconciles the in-memory registry with canonical sources:

1. Loads the persisted JSON registry from disk.
2. Merges any pack-manifest-declared tools that are missing.
3. Removes `retired` tools older than the audit retention window (configurable; default 180 days).
4. Writes the merged registry back to disk.

---

## 7. Integration with Policy System

The MCP governance model is a specialization of the general policy system (`Policy.ps1`):

- `mcp-readonly` mode allows only tools where `safetyLevel` is `read-only`.
- `mcp-mutating` mode allows tools where `safetyLevel` is `read-only` or `mutating`.
- `destructive` tools are blocked in all MCP modes and in `ci`, `watch`, and `scheduled` modes.
- The `Assert-PolicyPermission` gate is invoked by the MCP gateway before tool dispatch.

---

## 8. Version History

| Version | Date | Change |
|---------|------|--------|
| 1.0.0 | 2026-04-13 | Initial governance model for Workstream 7. |

---

*This document is part of the LLMWorkflow canonical document set. Changes require a PR and human review gate.*
