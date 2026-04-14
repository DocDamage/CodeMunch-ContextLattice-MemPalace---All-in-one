# Priority 0 Execution Board

Branch: `codex/repo-reorg-and-audit`

Purpose:
- convert the Priority 0 remediation work into a branch-native execution board
- map each sidecar to its target file, failure class, and validation status
- make it obvious what is covered, what is partially covered, and what remains to be applied in-place

## Status legend

- `Source sidecar` = remediation patch exists for the tracked source file
- `Test sidecar` = regression or scaffold patch exists for validation
- `Direct in-place edit` = not yet landed through the connector overwrite path
- `Coverage level`
  - `Strong` = concrete regression test shape present for the core bug
  - `Scaffold` = test intent and assertion path defined, but stronger integration hooks still needed
  - `Mixed` = at least one strong regression plus additional scaffold coverage

---

## Governance / Core / Retrieval / Ingestion matrix

| Target source file | Failure class | Source sidecar | Test sidecar | Coverage level | Notes |
|---|---|---:|---:|---|---|
| `module/LLMWorkflow/governance/GoldenTasks.ps1` | Silent property-access fallback, incorrect confidence aggregation, host-only summary output | Yes | Yes | Mixed | Highest-value governance correctness bug: summary must use `Validation.Confidence` |
| `module/LLMWorkflow/governance/HumanReviewGates.ps1` | Silent export-context suppression, exception-driven dot-sourcing behavior | Yes | Yes | Scaffold | Explicit dot-sourcing path now defined in test sidecar |
| `module/LLMWorkflow/core/ConfigCLI.ps1` | Reusable-module `Write-Host` usage / pipeline-host split | Yes | Yes | Scaffold | Output-channel split documented; stronger stream assertions still needed |
| `module/LLMWorkflow/core/StateFile.ps1` | Temp-file cleanup failure hidden during atomic write failure | Yes | Yes | Scaffold | Primary error must remain state write failure |
| `module/LLMWorkflow/retrieval/AnswerPlan.ps1` | Unlock failure in `finally` can turn successful export into reported failure; helper fallback invisibility | Yes | Yes | Mixed | `Export-AnswerTrace` unlock isolation is a high-priority correctness fix |
| `module/LLMWorkflow/retrieval/RetrievalCache.ps1` | Temp-file cleanup failure hidden during atomic cache write failure | Yes | Yes | Scaffold | Primary cache write failure must stay dominant |
| `module/LLMWorkflow/retrieval/QueryRouter.ps1` | Optional arbitration failure collapses otherwise valid routing result | Yes | Yes | Strong | Highest-value routing fix in current bundle |
| `module/LLMWorkflow/retrieval/CaveatRegistry.ps1` | Temp cleanup failure hidden; missing `triggers.packs` edge case in extensible content | Yes | Yes | Strong | Extensibility hardening plus atomic-save cleanup visibility |
| `module/LLMWorkflow/retrieval/IncidentBundle.ps1` | Temp cleanup failure hidden during atomic export; fallback run-id invisibility | Yes | Yes | Mixed | Export contract stays honest under degraded cleanup conditions |
| `module/LLMWorkflow/ingestion/DoclingAdapter.ps1` | Timed-out process kill failure hidden; temp output cleanup failure hidden | Yes | Yes | Mixed | Failure should stay graceful while cleanup/kill issues become visible |
| `module/LLMWorkflow/ingestion/ExternalIngestion.ps1` | Malformed link parse invisibility; secret-scan file read invisibility; work-dir cleanup invisibility | Yes | Yes | Scaffold | Structured WARN logging path defined in sidecars |
| `module/LLMWorkflow/ingestion/parsers/GeometryNodesParser.ps1` | JSON probe/fallback failures silently discarded | Yes | Yes | Mixed | Parser fallback contract preserved; observability added |

---

## Existing test-sidecar files

### Already on branch

- `sidecars/priority0/Governance.Tests.priority0.patch`
- `sidecars/priority0/DocumentIngestion.Tests.priority0.patch`
- `sidecars/priority0/QueryRouter.Tests.priority0.patch`
- `sidecars/priority0/IncidentBundle.Tests.priority0.patch`
- `sidecars/priority0/CaveatRegistry.Tests.priority0.patch`
- `sidecars/priority0/AnswerPlan.Tests.priority0.patch`
- `sidecars/priority0/RetrievalCache.Tests.priority0.patch`
- `sidecars/priority0/StateFile.Tests.priority0.patch`
- `sidecars/priority0/HumanReviewGates.Tests.priority0.patch`
- `sidecars/priority0/ConfigCLI.Tests.priority0.patch`
- `sidecars/priority0/DoclingAdapter.Tests.priority0.patch`
- `sidecars/priority0/ExternalIngestion.Tests.priority0.patch`
- `sidecars/priority0/GoldenTasks.Tests.priority0.patch`
- `sidecars/priority0/GeometryNodesParser.Tests.priority0.patch`

### Legacy/bridge note

Two earlier test sidecars were created before the board standardized one-file-per-target naming:

- `sidecars/priority0/Governance.Tests.priority0.patch`
- `sidecars/priority0/DocumentIngestion.Tests.priority0.patch`

They still matter and should be treated as valid bridge artifacts:
- `Governance.Tests.priority0.patch` covers `GoldenTasks.ps1` confidence summary behavior
- `DocumentIngestion.Tests.priority0.patch` covers ingestion-path graceful failure expectations, especially around Docling and ingestion cleanup behavior

---

## Priority 0 failure classes covered so far

### 1. Silent cleanup failure after primary failure
Covered in:
- `StateFile.priority0.patch`
- `RetrievalCache.priority0.patch`
- `DoclingAdapter.priority0.patch`
- `ExternalIngestion.priority0.patch`
- `CaveatRegistry.priority0.patch`
- `IncidentBundle.priority0.patch`

### 2. Silent helper fallback or suppressed subsystem failure
Covered in:
- `AnswerPlan.priority0.patch`
- `IncidentBundle.priority0.patch`
- `HumanReviewGates.priority0.patch`
- `QueryRouter.priority0.patch`

### 3. Host-only output in reusable modules
Covered in:
- `GoldenTasks.priority0.patch`
- `ConfigCLI.priority0.patch`

### 4. Correctness bugs hidden behind “successful” execution
Covered in:
- `GoldenTasks.priority0.patch` (`Validation.Confidence` path)
- `AnswerPlan.priority0.patch` (`Export-AnswerTrace` should not fail after a successful write because unlock failed)
- `QueryRouter.priority0.patch` (routing should survive optional arbitration failure)

### 5. Fallback parser/crawler behavior that was previously invisible
Covered in:
- `ExternalIngestion.priority0.patch`
- `GeometryNodesParser.priority0.patch`
- `CaveatRegistry.priority0.patch`

---

## Current branch truth

What exists now:
- a branch-native remediation artifact
- a branch-native sidecar manifest
- source-sidecars for all identified Priority 0 targets above
- test-sidecars for every source-sidecar target above

What does **not** exist yet:
- direct in-place edits to the tracked source files through the connector overwrite path
- a single PR that applies all source-sidecars into their actual tracked files
- full-strength integration tests for every cleanup-warning path

---

## Recommended next execution order

1. Apply source sidecars in-place outside the connector overwrite limitation.
2. Turn scaffold tests into executable tests where stream capture or helper extraction is required.
3. Collapse bridge test sidecars into per-target test files for cleaner ownership.
4. Open a PR that groups:
   - source-sidecar application
   - strongest regression tests first
   - scaffold-to-strong follow-up tasks second

---

## Sidecar inventory

### Source sidecars
- `AnswerPlan.priority0.patch`
- `CaveatRegistry.priority0.patch`
- `ConfigCLI.priority0.patch`
- `DoclingAdapter.priority0.patch`
- `ExternalIngestion.priority0.patch`
- `GeometryNodesParser.priority0.patch`
- `GoldenTasks.priority0.patch`
- `HumanReviewGates.priority0.patch`
- `IncidentBundle.priority0.patch`
- `QueryRouter.priority0.patch`
- `RetrievalCache.priority0.patch`
- `StateFile.priority0.patch`

### Test sidecars
- `AnswerPlan.Tests.priority0.patch`
- `CaveatRegistry.Tests.priority0.patch`
- `ConfigCLI.Tests.priority0.patch`
- `DoclingAdapter.Tests.priority0.patch`
- `DocumentIngestion.Tests.priority0.patch`
- `ExternalIngestion.Tests.priority0.patch`
- `GeometryNodesParser.Tests.priority0.patch`
- `GoldenTasks.Tests.priority0.patch`
- `Governance.Tests.priority0.patch`
- `HumanReviewGates.Tests.priority0.patch`
- `IncidentBundle.Tests.priority0.patch`
- `QueryRouter.Tests.priority0.patch`
- `RetrievalCache.Tests.priority0.patch`
- `StateFile.Tests.priority0.patch`

This board is the current source of truth for the Priority 0 remediation bundle on this branch.
