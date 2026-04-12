# Improvement Proposals -- CodeMunch / ContextLattice / MemPalace All-in-One

After a deep read of every file in the project, here are concrete suggestions organized by category.

---

## Implementation Summary

| Metric | Count |
|--------|-------|
| **Test Count** | 78 tests |
| **Functions** | 29 functions |
| **Aliases** | 9 aliases |

### Phases Completed

| Phase | Items Completed | Status |
|-------|-----------------|--------|
| **Phase 3** | 13 items | COMPLETED |
| **Phase 4** | 8 items | COMPLETED |
| **Phase 5** | 2 items | COMPLETED |
| **Phase 6** | 5 items | COMPLETED |
| **Phase 7** | 4 items | COMPLETED |

---

## 1. New Features

### 1a - Scheduled / Watch-mode Sync (Star) High Impact
**Status:** The bridge (`sync_mempalace_to_contextlattice.py`) is run manually or via `llmup`.  
**Proposal:** Add a `--watch` / `--schedule` mode that continuously tails the MemPalace collection for new drawers and syncs them in near-real-time.

- Implementation: a Python `asyncio` loop (or PowerShell `Register-ObjectEvent` with a timer) that calls the existing batch logic on an interval.
- New module command: `Start-LLMWorkflowSync -IntervalSeconds 30` (alias `llmsync`).
- Graceful shutdown on `Ctrl+C`, writes state on exit.

**Effort:** Medium / **Priority:** High

---

### 1b - Bi-directional Bridge (ContextLattice -> MemPalace)
**Status:** Bridge is strictly one-way (MemPalace -> ContextLattice).  
**Proposal:** Add `sync_contextlattice_to_mempalace.py` to pull new memories written directly to ContextLattice back into the local ChromaDB palace.

- Enables a "round-trip" where AI agents writing to ContextLattice via MCP have their outputs archived locally.
- New flag: `llmup -SyncBack`.

**Effort:** Medium-High / **Priority:** Medium

---

### 1c - Interactive TUI Dashboard
**Status:** (COMPLETED) All output was plain `Write-Output` text.  
**Status:** COMPLETED (Phase 7)
**Implementation:** Built a rich terminal UI using `PSReadLine` color codes for `llm-workflow-doctor`:

**Features Delivered:**
- Color-coded pass/warn/fail checks with ASCII indicators.
- Live-updating status during bootstrap (spinner while installing deps).
- Tabular summary at the end.
- Cross-platform compatible display.

**Effort:** Medium / **Priority:** Medium

---

### 1d - Multi-Project Profile System
**Status:** Each project gets its own `.env` / `.contextlattice/` / `.memorybridge/` config discovered at bootstrap.  
**Proposal:** Allow named profiles stored centrally in `~/.llm-workflow/profiles/`:

```
~/.llm-workflow/profiles/
  work.env
  personal.env
  gaming-mods.env
```

- `llmup -Profile work` loads the matching profile before project-local `.env`.
- Useful when the same user works on projects that target different ContextLattice instances or providers.

**Effort:** Low-Medium / **Priority:** Medium

---

### 1e - Plugin / Extension Architecture
**Status:** (COMPLETED) The three tool chains (codemunch, contextlattice, memorybridge) were hard-coded in the bootstrap.  
**Status:** COMPLETED (Phase 6)
**Implementation:** Introduced a plugin manifest (`.llm-workflow/plugins.json`) so third-party tools can register:

**Features Delivered:**
- Plugin manifest format with name, bootstrapScript, and runOn hooks.
- Bootstrap iterates plugins after the built-in tool chains.
- Future-proofs the toolkit without needing new flags for every integration.
- Support for pre-bootstrap, post-bootstrap, and check hooks.

**Effort:** Medium / **Priority:** Low-Medium

---

### 1f - `llmup init` -- Guided Interactive Setup
**Status:** Bootstrap creates sample configs but the user must manually edit them.  
**Proposal:** Add `Initialize-LLMWorkflow` (alias `llminit`) that interactively prompts:

1. Which provider? (pick from list)
2. Paste your API key -> writes `.env`
3. ContextLattice URL -> writes `.contextlattice/orchestrator.env`
4. Verify connectivity -> runs doctor
5. Optionally run first MemPalace sync

This dramatically lowers onboarding friction.

**Effort:** Low-Medium / **Priority:** High

---

### 1g - Anthropic / Claude Provider Support
**Status:** (COMPLETED) Provider roster expanded to include Claude and Ollama.  
**Status:** COMPLETED (Phase 3)
**Implementation:** Added `claude` and `ollama` provider profiles to the provider resolution system:

**Features Delivered:**
- Claude provider with ANTHROPIC_API_KEY and ANTHROPIC_BASE_URL support.
- Ollama provider for local model users with default base URL http://localhost:11434/v1.
- Proper environment variable mapping for both providers.
- Auto-detection support in provider resolution chain.

**Effort:** Low / **Priority:** High

---

## 2. Feature Upgrades to Existing Commands

### 2a - `Update-LLMWorkflow` -- In-place Git Pull Mode
**Status:** `Update-LLMWorkflow` downloads a release zip from GitHub.  
**Proposal:** Add a `-Source git` mode that does `git pull` + re-runs `install-module.ps1` for users who cloned the repo. The current zip-download approach is great for published releases, but repo contributors need the git flow.

**Effort:** Low / **Priority:** Medium

---

### 2b - `Test-LLMWorkflowSetup` -- Version Checks for Dependencies
**Status:** Checks presence of `python`, `codemunch-pro`, `chromadb` but not their **versions**.  
**Proposal:** Add version constraint checking:

- `chromadb >= 0.5.0` (already in `compatibility.lock.json` but not enforced)
- `python >= 3.10`
- `codemunch-pro >= X.Y.Z`

A new check like `python_version` with status `warn` if below minimum.

**Effort:** Low / **Priority:** Medium

---

### 2c - Bridge Sync -- Retry with Exponential Backoff
**Status:** (COMPLETED) `sync_mempalace_to_contextlattice.py` now includes retry logic.  
**Status:** COMPLETED (Phase 4)
**Implementation:** Added retry logic with exponential backoff around HTTP POST calls:

**Features Delivered:**
- 3 retry attempts with exponential backoff (1s, 2s, 4s).
- Configurable retry count via --max-retries parameter.
- Proper handling of transient network failures.
- Logging of retry attempts for debugging.

**Effort:** Low / **Priority:** Medium

---

### 2d - Bridge Sync -- Parallel Writes
**Status:** (COMPLETED) Sequential writes replaced with parallel processing.  
**Status:** COMPLETED (Phase 5)
**Implementation:** Used `concurrent.futures.ThreadPoolExecutor` to parallelize writes:

**Features Delivered:**
- Configurable --workers N parameter (default 4).
- Thread-safe batch processing of drawers.
- Unified error collection from parallel workers.
- Significant performance improvement for large syncs.

**Effort:** Medium / **Priority:** Medium

---

### 2e - `llm-workflow-doctor` -- Latency Reporting
**Status:** (COMPLETED) Doctor now reports response times for connectivity checks.  
**Status:** COMPLETED (Phase 4)
**Implementation:** Added latency measurement to all health checks:

**Features Delivered:**
- Response time reporting in milliseconds for all HTTP checks.
- Formatted output: `[OK] contextlattice_health: 127.0.0.1:8075/health ok=true (23ms)`.
- Helps diagnose slow network or overloaded servers.
- Included in both text and JSON output formats.

**Effort:** Low / **Priority:** Low

---

### 2f - Structured JSON Logging for All Commands
**Status:** (COMPLETED) Only `doctor` had `-AsJson`. Now all commands support structured output.  
**Status:** COMPLETED (Phase 4)
**Implementation:** Added `-AsJson` / `-OutputFormat json` to `Invoke-LLMWorkflowUp` and `Test-LLMWorkflowSetup`:

**Features Delivered:**
- Machine-readable JSON output for all major commands.
- Consistent schema across bootstrap, check, and doctor.
- CI pipeline-friendly output format.
- Proper error serialization in JSON format.

**Effort:** Medium / **Priority:** Medium

---

## 3. Code Quality / DRY Refactoring

### 3a - Extract Shared Utility Module (Star)
**Status:** (COMPLETED) Shared functions now consolidated into a common module.  
**Status:** COMPLETED (Phase 4)
**Implementation:** Created `tools/workflow/LLMWorkflowCommon.psm1` with shared functions:

**Features Delivered:**
- Centralized `Import-EnvFile`, `Get-FirstEnvValue`, `Get-ProviderProfile`, `Resolve-ProviderProfile`, and `Test-PythonImport`.
- Eliminated copy-paste across bootstrap, doctor, and module scripts.
- Fixed module-bundled bootstrap drift (significantly out of sync issue resolved).
- Consistent behavior across all entry points.

**Effort:** Medium / **Priority:** High

---

### 3b - Fix `$args` Variable Shadowing
**Status:** (COMPLETED) Fixed variable shadowing issue in sync-from-mempalace.ps1.  
**Status:** COMPLETED (Phase 3)
**Implementation:** Renamed `$args` to `$pyArgs` in sync-from-mempalace.ps1:

**Features Delivered:**
- Renamed local variable from `$args` to `$scriptArgs` to avoid shadowing.
- Prevents subtle bugs from PowerShell automatic variable collision.
- Applied consistently across all affected scripts.

**Effort:** Trivial / **Priority:** High

---

### 3c - Add `[CmdletBinding()]` and Proper Param Blocks
**Status:** (COMPLETED) Added CmdletBinding support to all scripts.  
**Status:** COMPLETED (Phase 3)
**Implementation:** Added `[CmdletBinding()]` to scripts missing proper parameter blocks:

**Features Delivered:**
- Consistent `-Verbose` / `-Debug` support across all scripts.
- Better pipeline behavior for all functions.
- Applied to verify.ps1, sync-from-mempalace.ps1, and bootstrap-project.ps1.
- Standard parameter attributes for all public functions.

**Effort:** Trivial / **Priority:** Low

---

## 4. Test Coverage Gaps

### 4a - Unit Tests for Provider Resolution
**Status:** (COMPLETED) Comprehensive tests added for provider resolution.  
**Status:** COMPLETED (Phase 3)
**Implementation:** Added Pester tests covering provider resolution logic:

**Features Delivered:**
- Auto-detection priority order tests.
- `LLM_PROVIDER` environment variable override tests.
- Fallback to default base URLs validation.
- Error handling for invalid provider names.
- Tests for all supported providers (OpenAI, Claude, Kimi, Gemini, GLM, Ollama).

**Effort:** Low / **Priority:** Medium

---

### 4b - Unit Tests for Version Bump & Release Scripts
**Status:** No tests for `bump-module-version.ps1` or `create-release-tag.ps1`.  
**Proposal:** Add Pester tests that run with `-DryRun` and verify manifest text transformations.

**Effort:** Low / **Priority:** Low

---

### 4c - Negative / Error-Path Tests
**Status:** (COMPLETED) Error path tests added.  
**Status:** COMPLETED (Phase 4)
**Implementation:** Added comprehensive negative tests:

**Features Delivered:**
- Missing Python -> meaningful error tests.
- Invalid `.env` format -> graceful skip tests.
- Network failure during ContextLattice verify -> proper error message tests.
- `Update-LLMWorkflow` with no releases -> correct exception handling.
- Provider credential failure scenarios.

**Effort:** Medium / **Priority:** Medium

---

### 4d - Linux/macOS CI Matrix
**Status:** (COMPLETED) CI now runs on multiple platforms.  
**Status:** COMPLETED (Phase 4)
**Implementation:** Added `ubuntu-latest` and `macos-latest` to the CI matrix:

**Features Delivered:**
- Cross-platform CI matrix: windows-latest, ubuntu-latest, macos-latest.
- Fixed path separator issues for Linux/macOS compatibility.
- Platform-specific test adaptations.
- Ensures scripts work correctly on all target platforms.

**Effort:** Low / **Priority:** Medium

---

## 5. CI/CD Enhancements

### 5a - PSScriptAnalyzer Linting
**Status:** (COMPLETED) Static analysis integrated into CI.  
**Status:** COMPLETED (Phase 4)
**Implementation:** Added PSScriptAnalyzer linting job to CI pipeline:

**Features Delivered:**
- Automatic PSScriptAnalyzer installation in CI.
- Recursive analysis of all PowerShell code.
- Exclusion of PSUseSingularNouns rule.
- Warning-level severity reporting.
- CI failure on new warnings.

**Effort:** Low / **Priority:** Medium

---

### 5b - Automated Changelog Validation
**Status:** `bump-module-version.ps1` adds a stub but nothing enforces that it was filled in.  
**Proposal:** CI check that verifies: if the version changed, the `CHANGELOG.md` has a non-`TODO` entry for that version.

**Effort:** Low / **Priority:** Low

---

### 5c - End-to-End Integration Test in CI
**Status:** (COMPLETED) Integration tests now run in CI.  
**Status:** COMPLETED (Phase 4)
**Implementation:** Added CI step that spins up mock ContextLattice server and runs integration tests:

**Features Delivered:**
- Mock ContextLattice server startup in CI.
- Full `Integration.ContextLattice.Tests.ps1` execution.
- Proper test isolation and cleanup.
- Coverage of real API interaction scenarios.

**Effort:** Low / **Priority:** Medium

---

### 5d - Prompt/RAG Regression + Red-Team Gate (`promptfoo`)
**Status:** CI validates code quality and integration behavior, but does not validate prompt quality, retrieval grounding quality, or jailbreak resistance over time.  
**Proposal:** Add a `promptfoo` suite and CI job:

- `tests/promptfoo/` contains baseline prompt/RAG test cases and expected assertions.
- CI runs `promptfoo eval` on pull requests.
- Fails PR if retrieval relevance, factuality checks, or safety assertions regress.
- Add a small red-team pack for prompt injection and jailbreak attempts.

This makes prompt behavior testable and prevents silent quality drift.

**Effort:** Low-Medium / **Priority:** Medium

---

### 5e - Reproducible Data/Pipeline Tracking (`DVC`, optional `CML`)
**Status:** The repo has code/version control, but no standardized tracking for datasets, eval corpora, prompt fixtures, and experiment outputs.  
**Proposal:** Introduce `DVC` for reproducible ML/LLM assets and optional `CML` for CI reporting:

- Track large/derived assets (`tests/promptfoo` fixtures, benchmark corpora, eval outputs) with `DVC`.
- Define reproducible pipeline stages (`dvc.yaml`) for sync/eval/report generation.
- Optionally use `CML` in GitHub Actions to post eval deltas and artifacts to PRs.

This gives deterministic reruns and makes quality changes auditable across branches.

**Effort:** Medium / **Priority:** Medium

---

### 5f - Optional YARA Artifact Scan in CI
**Status:** CI validates source quality and behavior, but has no malware-signature scanning for built artifacts or third-party binary drops used in tests/tooling.  
**Proposal:** Add an opt-in CI job that runs YARA rules against selected paths:

- Add `tools/security/yara/` for curated rules and safe local overrides.
- Scan release zips, generated binaries, and vendored external tools.
- Report matches as warnings by default; allow strict fail mode for protected branches.
- Include allowlist/suppression metadata to reduce noisy false positives.

This adds a lightweight malware/suspicious-artifact tripwire without blocking normal dev flow.

**Effort:** Low-Medium / **Priority:** Medium

---

## 6. Cross-Platform / Linux Support

### 6a - Path Separator Hardcoding
**Status:** (COMPLETED) Cross-platform path handling implemented.  
**Status:** COMPLETED (Phase 3)
**Implementation:** Audited and fixed all path string literals:

**Features Delivered:**
- Replaced hardcoded backslash paths with `[IO.Path]::Combine()` or `Join-Path`.
- Updated `$env:PSModulePath -split ';'` to use `[IO.Path]::PathSeparator`.
- All path constructions now work correctly on Linux/macOS.
- Cross-platform compatibility verified in CI.

**Effort:** Medium / **Priority:** Medium (grows to High as user base diversifies)

---

### 6b - Profile Path Handling
**Status:** (COMPLETED) Cross-platform profile path handling implemented.  
**Status:** COMPLETED (Phase 3)
**Implementation:** Fixed profile path handling for non-Windows platforms:

**Features Delivered:**
- On non-Windows, falls back to `~/.local/share/powershell/Modules`.
- Windows-specific "Documents\WindowsPowerShell\Modules" fallback preserved.
- Platform detection using `$PSVersionTable.Platform`.
- Consistent module installation across all platforms.

**Effort:** Low / **Priority:** Medium

---

## 7. Documentation

### 7a - Architecture Diagram
**Status:** (COMPLETED) Mermaid diagram added to README.md.  
**Status:** COMPLETED (Phase 6)
**Implementation:** Added comprehensive Mermaid diagram showing the flow:

**Features Delivered:**
- Visual flow from `llmup / Invoke-LLMWorkflowUp` through all components.
- CodeMunch Index, ContextLattice Verify, MemPalace Bridge Sync representation.
- ChromaDB Palace and ContextLattice API connections shown.
- Added to README.md for easy reference.

**Effort:** Trivial / **Priority:** Medium

---

### 7b - Troubleshooting Guide
**Status:** (COMPLETED) Comprehensive troubleshooting documentation added.  
**Status:** COMPLETED (Phases 5 & 7)
**Implementation:** Added `docs/TROUBLESHOOTING.md` covering common failure modes:

**Features Delivered:**
- `chromadb` import failure resolution (venv activation, Python version).
- ContextLattice server unreachable diagnosis.
- API key not found explanation (env precedence).
- Template drift detection and resolution.
- Advanced troubleshooting with process tracing and network capture.

**Effort:** Low / **Priority:** Medium

---

### 7c - Per-Tool READMEs Need Upgrade
**Status:** The three tool READMEs (`tools/codemunch/README.md`, etc.) are minimal stubs.  
**Proposal:** Expand each with:
- What the tool does
- Configuration reference
- Example usage
- Relationship to the other tools

**Effort:** Low / **Priority:** Low

---

### 7d - Advanced Troubleshooting Playbook (Dynamic Analysis)
**Status:** The current troubleshooting guidance is mostly config-level and does not cover deeper runtime/process/network diagnostics.  
**Proposal:** Extend `docs/TROUBLESHOOTING.md` with an advanced section for hard failures:

- Process tracing: `Process Monitor` (Windows), `dtrace`/`fs_usage` (macOS), `strace` equivalent notes.
- Network capture: `Wireshark` patterns for API timeouts, TLS failures, and DNS misroutes.
- Scripted capture bundles: one command to gather logs, env snapshots (masked), and timing traces.

This shortens mean-time-to-diagnosis for intermittent bridge/verification failures.

**Effort:** Low / **Priority:** Medium

---

## Priority Summary

| Priority | Items |
|----------|-------|
| **High** | 1a (Watch Sync), 1f (Interactive Init), 3a (DRY Refactor - COMPLETED), 10a (Git Hooks) |
| **Medium** | 1b (Bi-directional), 1d (Profiles), 2a-2b (Upgrades), 4b (Version Tests), 5b (Changelog CI), 5d-5f (Eval + Reproducibility + YARA), 7c-7d (Docs + Advanced Troubleshooting), 8d (Binary Safety), 9c (Notifications), 12c-12g (Ecosystem), 13a-13b (MCP), 14a-14d (Semantic Memory), 15a-15c (Agent Capabilities), 16a-16b (Visualization), 17a (Snapshots), 17c (NL Config) |
| **Low** | 1e (Plugins - COMPLETED), 4b (Version Tests), 5b (Changelog CI), 7c (Tool READMEs), 8c (Lock File Signing), 9c (Notifications), 10c (Config Schema - COMPLETED), 12c (VS Code Extension), 12d (Vector Backend Expansion), 12g (Game Audio Quickstart), 16a-16b (Knowledge Graph + Dashboard), 17b (Federated Memory) |

### Completed Items by Phase

| Phase | Completed Items |
|-------|-----------------|
| **Phase 3** | 1g (Claude/Ollama), 3b ($args fix), 3c (CmdletBinding), 4a (Provider Tests), 6a (Path Separators), 6b (Profile Paths), 8a (API Key Validation), 8b (Secret Masking), 9a (Sync History), 9b (Bootstrap Metrics), 10b (Tab Completion), 11a (Graceful Degradation), 11b (Offline Mode) |
| **Phase 4** | 2c (Retry Backoff), 2e (Latency Reporting), 2f (JSON Logging), 3a (Shared Module), 4c (Error-Path Tests), 4d (Linux/macOS CI), 5a (PSScriptAnalyzer), 5c (E2E Integration CI) |
| **Phase 5** | 2d (Parallel Writes), 7b (Troubleshooting Guide) |
| **Phase 6** | 1e (Plugin Architecture), 7a (Architecture Diagram), 12a (Multi-Palace), 12b (Docker Support), 12h (Game Team Workflow) |
| **Phase 7** | 1c (TUI Dashboard), 7b (Troubleshooting Enhanced), 10c (JSON Schema), 15a (Self-Healing) |

---

## 8. Security Hardening

### 8a - API Key Pre-Validation
**Status:** (COMPLETED) Provider keys are now validated before use.  
**Status:** COMPLETED (Phase 3)
**Implementation:** Added lightweight key validation step in `Set-NormalizedProviderEnvironment`:

**Features Delivered:**
- For OpenAI-compatible providers: GET /models with the key, expect 200.
- For ContextLattice: surfacing of /status check earlier in flow.
- New doctor check: `provider_key_valid` with pass/fail.
- Early failure with meaningful error messages.

**Effort:** Low / **Priority:** High

---

### 8b - Secret Masking in Output
**Status:** (COMPLETED) Secrets now masked in all diagnostic output.  
**Status:** COMPLETED (Phase 3)
**Implementation:** Added `Write-Masked` helper and applied throughout:

**Features Delivered:**
- `Write-Masked` helper truncates values longer than 8 chars to `sk-...XXXX`.
- Applied to all diagnostic output that touches credentials.
- `$env:PESTER_HIDE_SECRETS = 1` set in test runs.
- Prevents accidental key leakage in logs and output.

**Effort:** Low / **Priority:** Medium

---

### 8c - Lock File Integrity Signing
**Status:** `compatibility.lock.json` is validated for structure but not authenticity. A supply-chain attack could modify tested refs.  
**Proposal:** Generate a detached GPG/minisign signature (`compatibility.lock.json.sig`) during release. Add optional `--verify-lock-signature` to the CI validator.

**Effort:** Medium / **Priority:** Low

---

### 8d - Binary Intake Safety Check (Reversing-Aware)
**Status:** The project may eventually rely on external binaries/tools, but there is no explicit intake policy for unknown executables or packed artifacts.  
**Proposal:** Add a lightweight binary triage workflow before adopting third-party binaries:

- File-type/signature identification (`Detect It Easy` or equivalent).
- Hashing + provenance log (`SHA-256`, source URL, version, acquisition date).
- Optional static metadata review step (`PeStudio`/`file`/`codesign`) before check-in.
- Add a `docs/BINARY_INTAKE.md` checklist and CI reminder for `tools/**` binaries.

This reduces supply-chain risk when integrating external executables.

**Effort:** Low-Medium / **Priority:** Medium

---

## 9. Observability & Telemetry

### 9a - Sync History Log
**Status:** (COMPLETED) Sync history now tracked in rolling log.  
**Status:** COMPLETED (Phase 3)
**Implementation:** Added rolling `sync-history.jsonl` (JSON Lines) file:

**Features Delivered:**
- Each run appends summary with timestamp, seen count, writes, failed, skipped, mode.
- Configurable max entries (default 500) to prevent unbounded growth.
- New command: `Get-LLMWorkflowSyncHistory` (alias `llmhistory`).
- JSON Lines format for easy parsing and analysis.

**Effort:** Low / **Priority:** Medium

---

### 9b - Bootstrap Execution Metrics
**Status:** (COMPLETED) Timing information now collected for all steps.  
**Status:** COMPLETED (Phase 3)
**Implementation:** Wrapped each major bootstrap phase in timing blocks:

**Features Delivered:**
- Measure-Command blocks around all major phases.
- Timing summary output at end of bootstrap.
- Phase timing: Tool scaffold, Env loading, Dependency check, CodeMunch index, CL verify, Bridge dry-run.
- Total execution time reporting.

**Effort:** Low / **Priority:** Medium

---

### 9c - Failure Notifications
**Status:** Sync/check failures only appear in terminal output. If running via scheduled task or CI, failures can go unnoticed.  
**Proposal:** Add optional notification hooks:

- `-NotifyOnFailure webhook:https://hooks.slack.com/...`
- `-NotifyOnFailure email:ops@example.com` (via SMTP env vars)
- Simple `Invoke-RestMethod` with a JSON payload -- no dependencies.

**Effort:** Medium / **Priority:** Low

---

## 10. Developer Experience

### 10a - Git Hook Integration
**Status:** No automated triggers. Users must remember to run `llmup` manually.  
**Proposal:** Add `Install-LLMWorkflowHooks` that installs:

- **post-checkout** hook: runs `llmup -SkipDependencyInstall -SkipContextVerify -SkipBridgeDryRun` (fast scaffold-only pass).
- **post-merge** hook: runs `llmup` to catch dependency changes.
- Uses the `.git/hooks/` directory directly -- no Husky dependency.
- `Uninstall-LLMWorkflowHooks` to cleanly remove.

**Effort:** Low / **Priority:** High

---

### 10b - PowerShell Tab Completion
**Status:** (COMPLETED) Custom argument completers registered.  
**Status:** COMPLETED (Phase 3)
**Implementation:** Registered argument completers in the module:

**Features Delivered:**
- `-Provider` completer with dynamic list from `Get-ProviderPreferenceOrder`.
- `-Profile` completer with file listing from `~/.llm-workflow/profiles/`.
- Tool names completer: codemunch, contextlattice, memorybridge.
- Full Intellisense support for all parameters.

**Effort:** Low / **Priority:** Medium

---

### 10c - JSON Schema for Config Files
**Status:** (COMPLETED) JSON Schema validation for all config files.  
**Status:** COMPLETED (Phase 7)
**Implementation:** Shipped JSON Schema files for each config:

**Features Delivered:**
- `.memorybridge/bridge.config.schema.json` for bridge configuration.
- `.codemunch/index.defaults.schema.json` for indexing defaults.
- `$schema` reference in generated configs.
- IDE autocomplete and validation (VS Code, Rider).

**Effort:** Low / **Priority:** Low

---

## 11. Operational Resilience

### 11a - Graceful Degradation Mode
**Status:** (COMPLETED) Added -ContinueOnError flag for resilient execution.  
**Status:** COMPLETED (Phase 3)
**Implementation:** Added `-ContinueOnError` flag to bootstrap:

**Features Delivered:**
- Logs failures as warnings instead of throwing.
- Collects all failures into a summary at the end.
- Returns non-zero exit code but completes all possible steps.
- Useful for daily `llmup` usage when some services are unavailable.

**Effort:** Low / **Priority:** Medium

---

### 11b - Offline / Air-gapped Mode
**Status:** (COMPLETED) Added -Offline flag for air-gapped environments.  
**Status:** COMPLETED (Phase 3)
**Implementation:** Added `llmup -Offline` convenience flag:

**Features Delivered:**
- Skips all network-dependent steps automatically.
- Runs only local operations: tool scaffolding, env loading, local chromadb validation.
- Useful for developers working on planes, trains, or secure networks.
- Combines existing skip flags into single convenient option.

**Effort:** Trivial / **Priority:** Medium

---

## 12. Ecosystem Expansion

### 12a - Multi-Palace Support
**Status:** (COMPLETED) Bridge now supports multiple palace sources.  
**Status:** COMPLETED (Phase 6)
**Implementation:** Updated `bridge.config.json` to accept array of palace sources:

**Features Delivered:**
- Array of palace configurations with path and collectionName.
- Bridge iterates all palaces in one run with unified state tracking.
- Support for per-project local palaces alongside global palace.
- Unified sync state across all configured palaces.

**Effort:** Medium / **Priority:** Medium

---

### 12b - Docker / Container Support
**Status:** (COMPLETED) Containerized deployment option available.  
**Status:** COMPLETED (Phase 6)
**Implementation:** Added `Dockerfile` and `docker-compose.yml`:

**Features Delivered:**
- Bundles Python, chromadb, codemunch-pro, and PowerShell module.
- Exposes `llmup` as entrypoint with env var configuration.
- Useful for CI/CD pipelines without host dependency installation.
- Based on mcr.microsoft.com/powershell:latest.

**Effort:** Medium / **Priority:** Medium

---

### 12c - VS Code Extension
**Status:** Users interact exclusively via terminal.  
**Proposal:** Create a lightweight VS Code extension that:

- Adds a "LLM Workflow" status bar item showing sync state (last run, pass/fail).
- Provides command palette entries for `llmup`, `llmcheck`, `llmdoctor`.
- Shows a webview panel for doctor results with clickable fix suggestions.
- Auto-discovers `.contextlattice/` and `.memorybridge/` directories.

**Effort:** High / **Priority:** Low

---

### 12d - Pluggable Vector Backend (Qdrant/Milvus/Weaviate/Pinecone)
**Status:** Local memory relies on ChromaDB only. This is excellent for local-first workflows but may become limiting for large-scale, high-concurrency, or managed production requirements.  
**Proposal:** Add a backend abstraction layer for vector storage:

- Keep ChromaDB as the default local backend.
- Add optional adapters for `Qdrant`, `Milvus`, `Weaviate`, and `Pinecone`.
- Provide a migration command (`llmup -MigrateVectorBackend`) that copies embeddings/metadata.
- Document selection guidance: stay on ChromaDB unless scale/ops requirements justify migration.

This enables growth without forcing early infrastructure complexity.

**Effort:** Medium-High / **Priority:** Low-Medium

---

### 12e - Game Asset Starter Packs + License Manifest
**Status:** Bootstrapping focuses on code/memory infrastructure, but game projects also need repeatable art/audio starter assets and clear license tracking from day one.  
**Proposal:** Add `llmup -GameAssets` to scaffold optional starter packs and a mandatory asset manifest:

- Seed placeholders from curated sources (for example: Kenney/OpenGameArt/Poly Pizza/Quaternius links).
- Generate `assets/ASSET_MANIFEST.json` with source URL, license, attribution requirements, and usage scope.
- Add a doctor check that flags missing/unknown license metadata for imported assets.

This speeds prototype setup while reducing legal/licensing drift.

**Effort:** Medium / **Priority:** Medium

---

### 12f - 2D Content Pipeline Preset (LDtk/Tiled + Spritesheet + Compression)
**Status:** There is no standardized build path for 2D game content (tilemaps, spritesheets, and image optimization).  
**Proposal:** Add a `-Game2D` preset for common 2D workflows:

- Map authoring adapters for `LDtk`/`Tiled` exports.
- Spritesheet processing hooks (`TexturePacker` or `Tilesplit`) during build.
- Image optimization pass (`Squoosh`/`TinyPNG` equivalent CLI step) for release builds.
- Output validation report (atlas size, map count, compression savings).

This gives teams a reproducible asset pipeline instead of ad-hoc local scripts.

**Effort:** Medium / **Priority:** Medium

---

### 12g - Game Audio Pipeline Quickstart
**Status:** Audio setup is manual and inconsistent across projects, especially in early prototyping.  
**Proposal:** Add a lightweight audio scaffold:

- Recommended folder conventions (`audio/sfx`, `audio/music`, `audio/voice`).
- Metadata sidecars with source/license/tag info for each file.
- Optional helper tasks for SFX generation workflows (`Bfxr`/`jfxr`) and normalization.

This lowers friction for jams and prototypes while keeping audio assets organized.

**Effort:** Low / **Priority:** Low

---

### 12h - Game Team Workflow Preset (Jam + PM Templates)
**Status:** (COMPLETED) Game-specific collaboration template added.  
**Status:** COMPLETED (Phase 6)
**Implementation:** Added `llmup -GameTeam` workflow preset:

**Features Delivered:**
- Game-design doc starter (`docs/GDD.md`) with scope, loop, mechanics, and content checklist.
- Task board template compatible with HacknPlan/Questlog/Trello.
- Jam-mode defaults (`-ContinueOnError`, fast checks, lightweight artifact reports).
- Improved delivery speed for game teams without changing core workflow engine.

**Effort:** Low-Medium / **Priority:** Medium

---

> [!IMPORTANT]
> **Items already implemented from this list:**
> - Phase 3: 1g (Claude/Ollama), 3b ($args fix), 3c (CmdletBinding), 4a (Provider Tests), 6a (Path Separators), 6b (Profile Paths), 8a (API Key Validation), 8b (Secret Masking), 9a (Sync History), 9b (Bootstrap Metrics), 10b (Tab Completion), 11a (Graceful Degradation), 11b (Offline Mode)
> - Phase 4: 2c (Retry Backoff), 2e (Latency Reporting), 2f (JSON Logging), 3a (Shared Module), 4c (Error-Path Tests), 4d (Linux/macOS CI), 5a (PSScriptAnalyzer), 5c (E2E Integration CI)
> - Phase 5: 2d (Parallel Writes), 7b (Troubleshooting Guide)
> - Phase 6: 1e (Plugin Architecture), 7a (Architecture Diagram), 12a (Multi-Palace), 12b (Docker), 12h (Game Team Workflow)
> - Phase 7: 1c (TUI Dashboard), 10c (JSON Schema), 15a (Self-Healing enhancements)

> [!NOTE]
> **Recommended next batch:** 10a (git hooks), 1f (interactive init), 1a (watch sync) -- all high-impact improvements that make the daily workflow smoother.

---

## 13. MCP-Native Architecture (Crystal Ball)

### 13a - Expose the Toolkit Itself as an MCP Server
**Status:** The toolkit *bootstraps* MCP servers (codemunch-pro, memorymcp) but is itself only invocable via PowerShell.  
**Proposal:** Create `llm-workflow-mcp-server` -- an MCP server (stdio or HTTP) that exposes the toolkit's capabilities as tools any AI agent can call:

```json
{
  "tools": [
    { "name": "llm_workflow_bootstrap", "description": "Bootstrap a project with all tool chains" },
    { "name": "llm_workflow_doctor", "description": "Run environment health checks" },
    { "name": "llm_workflow_sync", "description": "Sync MemPalace to ContextLattice" },
    { "name": "llm_workflow_status", "description": "Get current workflow state and sync stats" },
    { "name": "llm_workflow_switch_provider", "description": "Switch the active LLM provider" }
  ]
}
```

This turns the toolkit into a **meta-tool** -- AI agents can self-bootstrap their own environment, check their own health, and trigger syncs autonomously.

**Effort:** Medium / **Priority:** High

---

### 13b - MCP Tool Composition / Orchestration
**Status:** codemunch-pro and memorymcp are independent MCP servers. No unified query surface.  
**Proposal:** Add a **composite MCP gateway** that routes requests across all three tool chains:

- `memory/search` -> fans out to both ContextLattice and local ChromaDB, deduplicates and ranks results.
- `index/search` -> queries codemunch-pro's index with ContextLattice context injected as grounding.
- `workflow/context` -> returns a unified "what does this project know?" summary combining index stats, memory counts, and sync state.

Think of it as a **unified AI context layer** -- one MCP endpoint that gives any agent complete project awareness.

**Effort:** High / **Priority:** Medium

---

## 14. Semantic Memory Intelligence (Brain)

### 14a - Semantic Change Detection (Replace Hash-Based Diffing)
**Status:** The bridge uses SHA-256 hashes to detect changes. A single whitespace edit triggers a full re-sync of that drawer. Meaningful content changes are treated the same as formatting noise.  
**Proposal:** Use embedding cosine similarity for change detection:

```python
old_embedding = get_cached_embedding(drawer_id)
new_embedding = embed(new_content)
similarity = cosine_similarity(old_embedding, new_embedding)
if similarity < 0.95:  # meaningful change threshold
    sync_to_contextlattice(drawer_id, new_content)
```

- Configurable similarity threshold via `--change-threshold`.
- Falls back to hash comparison if embeddings unavailable.
- Dramatically reduces unnecessary writes for actively-edited content.

**Effort:** Medium / **Priority:** Medium

---

### 14b - Memory Lifecycle Management (TTL, Archival, Versioning)
**Status:** Memories are write-once-sync-forever. Stale memories from abandoned projects accumulate without any pruning mechanism.  
**Proposal:** Add lifecycle metadata to synced memories:

```json
{
  "ttl_days": 90,
  "archive_after_days": 180,
  "max_versions": 5,
  "last_accessed_utc": "2026-04-11T17:00:00Z"
}
```

- New command: `Invoke-LLMWorkflowPrune` (alias `llmprune`) -- archives or deletes memories past TTL.
- Version history for frequently-updated drawers with diff support.
- `--dry-run` shows what would be pruned without acting.

**Effort:** Medium / **Priority:** Medium

---

### 14c - Intelligent Context Pre-fetching
**Status:** Context is retrieved on-demand. AI agents must explicitly search for relevant memories.  
**Proposal:** Add a **pre-fetch daemon** that watches `git diff --cached` and proactively loads relevant memories:

1. On file save / git stage, extract key terms from the diff.
2. Query ContextLattice for related memories.
3. Cache results locally in `.contextlattice/prefetch-cache.json`.
4. MCP server serves pre-fetched context with zero latency.

This means the AI agent already has relevant context *before it asks for it*. The difference between "search for what you need" and "here's what you probably need" is massive for agent performance.

**Effort:** High / **Priority:** Medium

---

### 14d - Cross-Repository Memory Linking
**Status:** Each project is an island -- memories synced from Project A are invisible when working in Project B.  
**Proposal:** Add a `relatedProjects` config:

```json
{
  "relatedProjects": ["other-repo", "shared-lib"],
  "crossRepoSearch": true
}
```

- `memory/search` queries span related projects.
- Bridge sync can optionally include memories tagged from related repos.
- Critical for monorepo-adjacent workflows where knowledge spans multiple repos.

**Effort:** Medium / **Priority:** Medium

---

## 15. Autonomous Agent Capabilities (Robot)

### 15a - Self-Healing Workflow Agent
**Status:** (COMPLETED) Enhanced self-healing capabilities implemented.  
**Status:** COMPLETED (Phase 7)
**Implementation:** Enhanced `Invoke-LLMWorkflowHeal` (alias `llmheal`) with comprehensive remediation:

**Features Delivered:**
- Runs `llmdoctor -AsJson` to capture failures.
- Automated fixes for common failures: python_command, chromadb_python_module, contextlattice_connectivity, provider_credentials.
- Interactive prompts for missing credentials.
- Re-runs doctor to verify fixes.
- Comprehensive logging of all healing actions taken.
- Goes beyond diagnosis to automatic remediation.

**Effort:** Medium / **Priority:** Medium

---

### 15b - LLM-Powered Memory Curation
**Status:** All memories are treated equally. No quality filtering, deduplication, or summarization.  
**Proposal:** Add `Invoke-LLMWorkflowCurate` (alias `llmcurate`) that uses the configured LLM provider to:

- **Deduplicate:** Find semantically similar memories and merge them.
- **Summarize:** Compress verbose memories into concise summaries while preserving key facts.
- **Classify:** Auto-tag memories with topics, relevance scores, and confidence levels.
- **Prune:** Identify memories that are outdated or contradicted by newer ones.

```powershell
llmcurate -ProjectRoot . -MaxTokenBudget 50000 -DryRun
```

Uses your own LLM provider to improve your own memory -- the toolkit eating its own dogfood.

**Effort:** High / **Priority:** Medium

---

### 15c - Proactive Context Agent (Background Daemon)
**Status:** The toolkit is purely reactive -- runs when invoked, sleeps otherwise.  
**Proposal:** Add `Start-LLMWorkflowAgent` (alias `llmagent`) -- a background process that:

1. **Watches** file system changes in the project via `FileSystemWatcher`.
2. **Auto-indexes** changed files through codemunch-pro incrementally.
3. **Auto-syncs** new MemPalace drawers to ContextLattice.
4. **Pre-warms** context cache based on recently-edited files.
5. **Reports** via a local REST endpoint (`http://localhost:59082/status`) that the VS Code extension or MCP server can query.

Runs as a tray icon on Windows / launchd agent on macOS / systemd user service on Linux.

**Effort:** High / **Priority:** Low-Medium

---

## 16. Knowledge Graph & Visualization (Chart)

### 16a - Memory Relationship Graph
**Status:** Memories are flat key-value documents. No relationship tracking between related memories.  
**Proposal:** Build a relationship layer:

```python
{
  "drawer_id": "abc123",
  "related_to": ["def456", "ghi789"],
  "relationship": "extends",  # extends | contradicts | supersedes | references
  "confidence": 0.87
}
```

- Auto-detected via embedding similarity during sync.
- Stored as edges in a lightweight graph (NetworkX or sqlite).
- Queryable: "What memories are related to this file?"

**Effort:** High / **Priority:** Low

---

### 16b - Interactive Web Dashboard
**Status:** All output is terminal text or JSON.  
**Proposal:** Ship a `llm-workflow-dashboard` single-page app (served locally) that shows:

- **Memory map:** 3D force-directed graph of memories, topics, and projects.
- **Sync timeline:** Historical view of sync runs, success/failure trends.
- **Provider health:** Real-time latency and availability of all configured providers.
- **Index coverage:** Which files are indexed, which are stale, embedding coverage percentage.
- **Cost tracker:** Estimated API spend based on token counts from syncs and searches.

Built as a single HTML file with embedded JS (no build step) -- `& start "http://localhost:59083"`.

**Effort:** High / **Priority:** Low

---

## 17. Portable & Federated Memory (Globe)

### 17a - Memory Snapshots (Export / Import)
**Status:** No way to capture and restore a point-in-time memory state.  
**Proposal:** Add `Export-LLMWorkflowMemory` and `Import-LLMWorkflowMemory`:

```powershell
# Capture everything: index, palace, sync state, configs
Export-LLMWorkflowMemory -Path ./memory-snapshot-2026-04-11.tar.gz

# Restore on another machine or after a reset
Import-LLMWorkflowMemory -Path ./memory-snapshot-2026-04-11.tar.gz
```

- Includes ChromaDB palace, sync state, codemunch index, and all configs.
- Enables reproducible AI dev environments -- "here's the exact context state where this bug was found."
- Version-stamps snapshots for compatibility validation.

**Effort:** Medium / **Priority:** Medium

---

### 17b - Federated Team Memory
**Status:** Single-user only. No mechanism for team knowledge sharing.  
**Proposal:** Add a team sync mode where multiple developers' MemPalaces merge into a shared ContextLattice with access control:

```json
{
  "federation": {
    "team_lattice_url": "https://team.contextlattice.example.com",
    "my_namespace": "docdamage",
    "shared_namespaces": ["team-shared", "architecture-decisions"],
    "push_topics": ["runbooks/*", "postmortems/*"],
    "pull_topics": ["*"]
  }
}
```

- Namespace isolation: my memories vs. team-shared memories.
- Selective push: only share `runbooks/` and `postmortems/`, keep `scratch/` private.
- Conflict resolution: last-write-wins with optional manual merge for contradictions.
- Audit log: who wrote what, when.

This transforms the toolkit from a **personal productivity tool** into a **team knowledge platform**.

**Effort:** Very High / **Priority:** Low

---

### 17c - Natural Language Workflow Configuration
**Status:** Configuration requires manually editing JSON files and env vars.  
**Proposal:** Add `llmup --from-prompt "Set up my project for Claude with a local MemPalace, sync every 5 minutes, skip Kimi"` that:

1. Parses the natural language instruction via the configured LLM.
2. Generates the appropriate `.env`, `bridge.config.json`, and orchestrator config.
3. Shows a diff of what it will write and asks for confirmation.
4. Applies the config and runs bootstrap.

The ultimate "zero-config" experience -- describe what you want in English, get a working setup.

**Effort:** Medium / **Priority:** Low

---

## Bleeding-Edge Priority Addendum

| Priority | Items |
|----------|-------|
| **High** | 13a (MCP Server) |
| **Medium** | 13b (MCP Gateway), 14a (Semantic Diffing), 14b (Memory Lifecycle), 14c (Pre-fetching), 14d (Cross-Repo), 15b (LLM Curation), 17a (Snapshots) |
| **Low-Medium** | 15c (Background Agent) |
| **Low** | 16a (Knowledge Graph), 16b (Web Dashboard), 17b (Federated Memory), 17c (NL Config) |

> [!TIP]
> **The single highest-leverage bleeding-edge item is 13a (MCP Server).** Once the toolkit is MCP-native, every AI agent that connects to your project can self-bootstrap, self-diagnose, and self-sync -- no human in the loop. It's the difference between a tool you use and a tool that uses itself.
