# Recovery Playbooks

This document provides operator playbooks for the most common failure modes encountered during durable workflow execution in the LLM Workflow platform.

---

## 1. Interrupted Large Pack Build

### Symptoms
- Pack build process terminates unexpectedly (host reboot, process crash, Ctrl+C).
- Checkpoint file in `.llm-workflow/checkpoints/` shows `status: "running"` or `"failed"`.
- Partial pack artifacts exist in the output directory.

### Root Causes
- Long-running asset pipeline step exceeded available memory.
- External dependency download was interrupted.
- Operator cancelled the build.

### Recovery Steps
1. **Inspect checkpoint state**
   ```powershell
   Get-DurableWorkflowState -WorkflowId "pack-build-<pack-name>" -ProjectRoot .
   ```
2. **If `status` is `running` and `stepIndex` points to an incomplete step:**
   - Verify no stale locks are held:
     ```powershell
     Test-StaleLock -Name "pack" -ProjectRoot .
     ```
   - Resume the workflow:
     ```powershell
     $wf = New-DurableWorkflow -WorkflowId "pack-build-<pack-name>" -Steps $steps -RunId "<run-id-from-checkpoint>"
     Resume-DurableWorkflow -Workflow $wf -ProjectRoot .
     ```
3. **If `status` is `failed` at the asset-pipeline step:**
   - Check disk space and logs in `.llm-workflow/logs/`.
   - Fix the underlying issue (e.g., free disk space, restore network).
   - Resume as above.
4. **If partial artifacts are corrupt:**
   - Remove the incomplete output pack directory.
   - The resume logic will re-execute the step that produces the pack.

### Prevention
- Enable automatic stale-lock reclamation.
- Run large builds inside a Temporal workflow (Workstream 6) for host-level durability.

---

## 2. Failed Snapshot Export / Import

### Symptoms
- `Export-LLMWorkflowSnapshot` or import cmdlet throws with disk or network errors.
- Snapshot JSON is missing or truncated.
- Checksum mismatch on imported snapshot.

### Root Causes
- Insufficient disk space during export.
- Network timeout during upload/download of snapshot to remote storage.
- Snapshot schema version mismatch between source and target.

### Recovery Steps
1. **Check failure taxonomy**
   ```powershell
   Test-RecoverableFailure -Message "The remote server returned an error: (503)"  # -> true (transient)
   ```
2. **For transient failures (network / 503):**
   - Retry the operation with increased timeout.
   - If using durable orchestration, the checkpoint will automatically retry the step on resume.
3. **For resource failures (disk full):**
   - Free disk space or change the snapshot output path.
   - Re-run the export step.
4. **For schema mismatch (`data` category):**
   - Run `Migrate-StateFile` on the snapshot JSON to upgrade it to the target schema version.
   - Re-attempt import.

### Prevention
- Pre-validate disk space before export.
- Version snapshot schemas explicitly; include `_schema` header in every snapshot file.

---

## 3. Interrupted Federated Memory Sync

### Symptoms
- `Sync-MemPalaceBridge` stops mid-run.
- Checkpoint shows a pending `embed` or `index` step.
- Vector store contains only a subset of the expected embeddings.

### Root Causes
- ContextLattice orchestrator became unreachable.
- Rate limit from the embedding provider API.
- Large batch size causing memory pressure.

### Recovery Steps
1. **Read the last checkpoint**
   ```powershell
   Get-DurableWorkflowState -WorkflowId "federated-memory-sync" -ProjectRoot .
   ```
2. **Determine recoverability**
   ```powershell
   $state = Get-DurableWorkflowState ...
   Test-RecoverableFailure -Message $state.stepResults[-1].output
   Get-RecoveryAction -Message $state.stepResults[-1].output
   ```
3. **If provider rate limit (`resource` / `transient`):**
   - Reduce batch size in `bridge.config.json`.
   - Wait for rate-limit window to reset.
   - Resume the sync workflow.
4. **If orchestrator unreachable (`transient`):**
   - Verify `CONTEXTLATTICE_ORCHESTRATOR_URL` and API key.
   - Resume once connectivity is restored.
5. **If vector store is in an inconsistent state:**
   - Trigger a `heal` run to rebuild the affected index partition before resuming sync.

### Prevention
- Use smaller, checkpointed batches for embedding ingestion.
- Enable retry with exponential backoff in the bridge client configuration.

---

## 4. Failed Large External Ingestion

### Symptoms
- Ingestion of a large external repository or dataset fails partway through.
- Journal entries show `failed` status on the `ingest` step.
- Some files are partially downloaded or indexed.

### Root Causes
- Source repository throttled or blocked the connection.
- Local disk quota exceeded during intermediate file storage.
- Malformed document caused parser failure (`data` category).

### Recovery Steps
1. **Inspect journal and checkpoint**
   ```powershell
   Get-JournalState -RunId "<run-id>" -JournalDirectory .\.llm-workflow\journals -ManifestDirectory .\.llm-workflow\manifests
   Get-DurableWorkflowState -WorkflowId "large-external-ingest" -RunId "<run-id>" -ProjectRoot .
   ```
2. **If throttled (`transient`):**
   - Back off for the duration advised by the `Retry-After` header (if present).
   - Resume ingestion; already-ingested files will be skipped based on the checkpoint `stepResults`.
3. **If disk full (`resource`):**
   - Move or clear the intermediate cache folder.
   - Resume ingestion.
4. **If parser failure (`data`):**
   - Identify the offending file from the step output.
   - Quarantine or fix the file.
   - Update the ingestion filter to exclude the bad file.
   - Resume ingestion.

### Prevention
- Pre-scan external sources with a lightweight manifest pass before full ingestion.
- Set disk-space guardrails in `Policy.ps1` for ingestion workflows.

---

## 5. Failed Inter-Pack Transfer

### Symptoms
- Transfer of assets or metadata between two packs fails.
- Source pack lock is held but target pack was never updated.
- Checkpoint shows failure at the `transfer` or `validate-target` step.

### Root Causes
- Target pack manifest is locked by another process.
- Source and target pack schemas are incompatible (`data`).
- Network share hosting the target pack became unavailable.

### Recovery Steps
1. **Check lock status**
   ```powershell
   Get-LockInfo -Name "pack" -ProjectRoot .
   ```
2. **If target pack is locked:**
   - Wait for the other process to release the lock, or use `Remove-StaleLock` with `-Force` if the lock is stale.
   - Resume the transfer workflow.
3. **If schema mismatch (`data`):**
   - Run `Test-StateVersion` on both pack manifests.
   - Apply the necessary migration using `Migrate-StateFile`.
   - Re-run the validation step.
4. **If network share is down (`transient`):**
   - Restore network connectivity.
   - Resume the transfer; the source pack state is preserved in the checkpoint.

### Prevention
- Always acquire pack locks in a deterministic order (source then target) to avoid deadlocks.
- Validate schema compatibility before starting the transfer step.

---

*These playbooks are living documents. Update them when new failure modes are discovered or when recovery automation is improved.*
