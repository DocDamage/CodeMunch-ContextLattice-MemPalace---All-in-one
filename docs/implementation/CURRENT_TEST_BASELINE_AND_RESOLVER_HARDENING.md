# Current Test Baseline and Resolver Hardening Sync

Date: 2026-04-14
Branch: `codex/repo-reorg-and-audit`

Purpose:
- record the actual current test baseline reflected by the branch
- capture the resolver hardening that is already implemented and tested
- provide a truth source for syncing README / progress-tracker language

This document is intentionally grounded in the current repo state rather than older release-summary wording.

---

## Actual current test baseline

The branch baseline is broader than the older partial-suite summary that only called out a few file-level Pester counts.

### CI baseline currently exercised

1. **Drift/documentation guard stage**
   - `tools/ci/check-template-drift.ps1`
   - `tools/ci/validate-compatibility-lock.ps1`
   - `tools/ci/validate-docs-truth.ps1`

2. **Lint stage**
   - repo-wide `PSScriptAnalyzer` run
   - build fails on analyzer errors

3. **Windows CI matrix**
   - `powershell`
   - `pwsh`
   - module import smoke
   - project bootstrap smoke
   - full Pester execution through:
     - `tools/ci/invoke-pester-safe.ps1 -Path .\tests -CI`

4. **Linux CI (experimental)**
   - module import smoke
   - full Pester execution through safe runner

5. **macOS CI (experimental)**
   - module import smoke
   - full Pester execution through safe runner

6. **E2E integration lane**
   - ContextLattice integration test invocation through:
     - `tests/Integration.ContextLattice.Tests.ps1`

### Why the old baseline wording is stale

The older progress summary only listed a narrow subset of suites such as:
- `Core.Tests.ps1`
- `CoreModule.Tests.ps1`
- `Pack.Tests.ps1`
- `PackFramework.Tests.ps1`
- `Benchmarks.Tests.ps1`

That wording is incomplete relative to the actual branch baseline because the branch now treats:
- full `tests/` execution via the safe Pester runner,
- install/bootstrap smoke,
- docs truth validation,
- compatibility lock validation,
- and ContextLattice integration
as part of the real baseline.

### Recommended tracker wording

Use wording closer to this:

> Current baseline is the full `tests/` Pester run through `tools/ci/invoke-pester-safe.ps1`, plus install/bootstrap smoke, drift/doc truth validation, compatibility-lock validation, and the ContextLattice integration lane.

---

## Completed resolver hardening

The provider resolver is no longer just a simple happy-path selector. The branch already has meaningful hardening and regression coverage around provider profile selection and credential resolution.

### Resolver behavior already covered in `tests/LLMWorkflow.Tests.ps1`

#### Provider profile shape coverage
- `Get-ProviderProfile` for:
  - `openai`
  - `claude`
  - `kimi`
  - `gemini`
  - `glm`
  - `ollama`
- case-insensitive provider names
- unsupported provider rejection

#### Auto-detection order hardening
- verifies priority order:
  - `openai > claude > kimi > gemini > glm > ollama`
- verifies the resolver chooses the highest-priority available provider when multiple credentials exist

#### Environment override hardening
- respects `LLM_PROVIDER` override when matching credentials exist
- falls back cleanly when `LLM_PROVIDER` points to a provider without credentials
- ignores invalid `LLM_PROVIDER` values and returns to auto-detection behavior

#### Alias environment variable hardening
- `MOONSHOT_API_KEY` for `kimi`
- `GOOGLE_API_KEY` for `gemini`
- `ZHIPU_API_KEY` for `glm`

#### Base URL resolution hardening
- default base URL fallback when no explicit base URL is set
- custom base URL usage when explicitly set
- `OLLAMA_HOST` as fallback base URL source
- `OLLAMA_BASE_URL` taking precedence over `OLLAMA_HOST`

#### Explicit-request behavior hardening
- explicit provider request returns the requested provider shape even with no key
- no-provider scenario returns `$null` under `auto`

#### Input validation hardening
- whitespace API keys rejected by `Test-ProviderKey`
- contextlattice provider path documented as requiring non-empty base URL
- timeout parameter acceptance covered

### What “completed resolver hardening” should mean in tracker language

Reasonable synced wording:

> Resolver hardening is complete for the current branch baseline: provider profile mapping, priority-order auto-detection, invalid override fallback, alias env var handling, base-URL precedence, and key-validation edge cases are covered in `tests/LLMWorkflow.Tests.ps1`.

---

## New compatibility-fixture coverage added in this branch update

This branch update also adds richer curated-plugin compatibility scenarios instead of relying on a thin compatibility surface.

### Added fixture files
- `tests/fixtures/compat/curated-plugin/active.sources.json`
- `tests/fixtures/compat/curated-plugin/deprecated.sources.json`
- `tests/fixtures/compat/curated-plugin/quarantined.sources.json`
- `tests/fixtures/compat/curated-plugin/retired.sources.json`
- `tests/fixtures/compat/curated-plugin/mixed.sources.json`

### Added suite
- `tests/Compatibility.CuratedPlugin.Tests.ps1`

### Added behavior coverage
- active curated-plugin fixture remains compatible
- deprecated curated-plugin fixture surfaces a warning state
- quarantined curated-plugin fixture is incompatible
- retired curated-plugin fixture is incompatible
- mixed curated-plugin fixture carries both warning and incompatible signals
- compatibility lock export pins curated-plugin refs from the fixture state

---

## Suggested README / progress sync edits

### README remediation/status area
Replace vague “core/pack/framework/benchmark suites remediated and passing” wording with:

- full `tests/` baseline now runs through `tools/ci/invoke-pester-safe.ps1`
- install/bootstrap smoke is part of CI baseline
- docs truth + compatibility-lock validation are part of the baseline
- provider resolver hardening is complete and covered by `tests/LLMWorkflow.Tests.ps1`
- curated-plugin compatibility fixture coverage has been expanded

### `docs/implementation/PROGRESS.md`
Update the “Verified Test Outcomes” section so it no longer implies the baseline is only a handful of named suites with old pass counts.

Preferred replacement:

- describe the baseline as full `tests/` execution through the safe runner
- mention Windows PowerShell + `pwsh` as the primary matrix
- mention experimental Linux/macOS lanes
- mention drift/doc truth + compatibility-lock validation
- mention ContextLattice integration lane
- explicitly call out resolver hardening as complete and already covered

---

## Current limitation note

The branch now contains the truth-source document needed to sync README/progress wording, but direct in-place overwrite of large tracked docs is still constrained by the connector path available in this session.

So the actual truth is now captured on-branch here first, and should be treated as the source for the next direct README / progress-file content reconciliation step.
