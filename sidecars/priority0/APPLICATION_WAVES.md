# Priority 0 Application Waves

Branch: `codex/repo-reorg-and-audit`

Purpose:
- define the recommended order for applying the Priority 0 source sidecars into tracked source files
- separate correctness-critical fixes from observability-only fixes and output-channel cleanup
- reduce risk by applying the most important truth-preserving fixes first

This document assumes the source sidecars already exist on-branch under `sidecars/priority0/`.

---

## Wave structure

### Wave 1 — correctness-critical fixes
Apply these first because they prevent the system from lying about success, confidence, or routing outcomes.

#### Files in Wave 1
- `GoldenTasks.priority0.patch`
- `AnswerPlan.priority0.patch`
- `QueryRouter.priority0.patch`
- `CaveatRegistry.priority0.patch`

#### Why these go first

##### 1. `GoldenTasks.priority0.patch`
This is a governance-signal integrity fix, not cosmetic cleanup.

Key issue:
- pack summary can read the wrong confidence path and under-report confidence by looking for top-level `Confidence` instead of `Validation.Confidence`

Risk if not fixed:
- release or governance summaries can look weaker or flatter than the actual per-task validation results
- confidence-based gating becomes untrustworthy

##### 2. `AnswerPlan.priority0.patch`
This prevents false export failures.

Key issue:
- `Export-AnswerTrace` can successfully write to disk and still surface as a failure if lock release throws in `finally`

Risk if not fixed:
- operators get a false-negative signal even though the trace export actually succeeded
- postmortem and audit workflows become unreliable

##### 3. `QueryRouter.priority0.patch`
This prevents optional enrichment from destroying core routing behavior.

Key issue:
- optional cross-pack arbitration can throw and collapse an otherwise valid routing result into a total routing failure

Risk if not fixed:
- queries that were successfully routed appear to have failed completely
- downstream retrieval behavior can degrade from optional subsystem instability

##### 4. `CaveatRegistry.priority0.patch`
This is partly observability, but it also hardens extensibility correctness.

Key issue:
- custom/imported caveats can omit `triggers.packs`, creating a missing-member edge case during applicability matching

Risk if not fixed:
- extensible registry content can break matching behavior unexpectedly
- custom caveats become less trustworthy than predefined caveats

#### Wave 1 exit criteria
- governance confidence summaries read `Validation.Confidence`
- answer trace export cannot be marked failed solely because unlock failed after a successful write
- routing survives arbitration failure and still returns valid selected packs
- custom caveats without `packs` do not break caveat matching

---

### Wave 2 — observability and cleanup fixes
Apply these next because they expose real failure surfaces without changing core success semantics.

#### Files in Wave 2
- `DoclingAdapter.priority0.patch`
- `ExternalIngestion.priority0.patch`
- `GeometryNodesParser.priority0.patch`
- `IncidentBundle.priority0.patch`
- `RetrievalCache.priority0.patch`
- `StateFile.priority0.patch`

#### Why these go second

##### 1. `DoclingAdapter.priority0.patch`
Makes timed-out process termination and temp cleanup visible.

Key issue:
- kill failures and temp directory cleanup failures were silently swallowed

Effect of fix:
- extraction remains graceful where intended
- hidden operational failure becomes visible to operators

##### 2. `ExternalIngestion.priority0.patch`
Makes crawl and secret-scan blind spots visible.

Key issue:
- malformed docs links, file-read failures, and work-dir cleanup failures disappear into silence

Effect of fix:
- structured warnings and WARN logs capture non-fatal ingestion degradation

##### 3. `GeometryNodesParser.priority0.patch`
Preserves parser fallback while surfacing why fallback happened.

Key issue:
- JSON probe and JSON fallback failures were silently discarded

Effect of fix:
- malformed JSON-like input still falls back correctly
- operators can finally tell why the parser changed path

##### 4. `IncidentBundle.priority0.patch`
Makes atomic export cleanup failures visible and fallback run-id behavior explicit.

Key issue:
- export cleanup residue and run-id fallback can become invisible

Effect of fix:
- bundle export failure remains honest
- helper-resolution fallback is diagnosable

##### 5. `RetrievalCache.priority0.patch`
Surfaces temp-file cleanup failure after cache write failure.

Key issue:
- temp cleanup after failed cache write was silently suppressed

Effect of fix:
- primary cache write failure stays primary
- secondary filesystem hygiene failure becomes visible

##### 6. `StateFile.priority0.patch`
Does the same for atomic state writes.

Key issue:
- temp cleanup after failed state write was silently suppressed

Effect of fix:
- state write failure remains the main error
- cleanup residue and permission issues stop disappearing

#### Wave 2 exit criteria
- no atomic-write temp cleanup failure of interest is silently discarded in the covered modules
- ingestion/crawl/parser fallback behavior remains graceful where intended
- hidden cleanup and helper-resolution issues are visible through warnings or structured logs

---

### Wave 3 — output-channel and module-behavior fixes
Apply these after correctness and observability because they improve module hygiene and testability without being as operationally dangerous as Waves 1 and 2.

#### Files in Wave 3
- `ConfigCLI.priority0.patch`
- `HumanReviewGates.priority0.patch`

#### Why these go third

##### 1. `ConfigCLI.priority0.patch`
Moves reusable-module status messages off `Write-Host`.

Key issue:
- status output is host-locked and harder to test or compose in pipelines

Effect of fix:
- actual command data remains on the output pipeline
- status moves to information/warning streams where it belongs

##### 2. `HumanReviewGates.priority0.patch`
Removes double-suppressed export behavior.

Key issue:
- dot-sourcing behavior depends on silent `Export-ModuleMember` failure with both `SilentlyContinue` and catch suppression

Effect of fix:
- non-module execution becomes explicit instead of exception-driven
- true export problems stop disappearing silently

#### Wave 3 exit criteria
- reusable module status output is pipeline-safe in the covered modules
- dot-sourcing and module export behavior are explicit branches instead of silent failure paths

---

## Recommended apply order inside each wave

### Wave 1 apply order
1. `GoldenTasks.priority0.patch`
2. `AnswerPlan.priority0.patch`
3. `QueryRouter.priority0.patch`
4. `CaveatRegistry.priority0.patch`

### Wave 2 apply order
1. `StateFile.priority0.patch`
2. `RetrievalCache.priority0.patch`
3. `DoclingAdapter.priority0.patch`
4. `IncidentBundle.priority0.patch`
5. `GeometryNodesParser.priority0.patch`
6. `ExternalIngestion.priority0.patch`

Rationale:
- start with atomic-write truthfulness in core state/cache flows
- then ingestion/export cleanup visibility
- finish with broader ingestion/parser observability changes

### Wave 3 apply order
1. `ConfigCLI.priority0.patch`
2. `HumanReviewGates.priority0.patch`

---

## Test-sidecar alignment

### Wave 1 validation
- `GoldenTasks.Tests.priority0.patch`
- `Governance.Tests.priority0.patch`
- `AnswerPlan.Tests.priority0.patch`
- `QueryRouter.Tests.priority0.patch`
- `CaveatRegistry.Tests.priority0.patch`

### Wave 2 validation
- `StateFile.Tests.priority0.patch`
- `RetrievalCache.Tests.priority0.patch`
- `DoclingAdapter.Tests.priority0.patch`
- `DocumentIngestion.Tests.priority0.patch`
- `IncidentBundle.Tests.priority0.patch`
- `GeometryNodesParser.Tests.priority0.patch`
- `ExternalIngestion.Tests.priority0.patch`

### Wave 3 validation
- `ConfigCLI.Tests.priority0.patch`
- `HumanReviewGates.Tests.priority0.patch`

---

## Current truth

This branch currently contains:
- source sidecars for all listed wave items
- test sidecars for all listed wave items
- `EXECUTION_BOARD.md` as the source-of-truth inventory

This branch does **not** yet contain:
- in-place tracked source edits applying these sidecars directly
- all executable tests fully materialized in tracked test files

---

## Practical recommendation

If you are applying these manually or through a local tool outside the connector overwrite limitation:

1. apply Wave 1 fully
2. run the strongest regression tests for Wave 1
3. apply Wave 2 fully
4. convert the highest-value Wave 2 scaffolds into executable tests where stream capture/helper extraction is needed
5. apply Wave 3 last

That order minimizes the chance of spending time polishing output behavior before the system stops lying about routing, confidence, or export success.
