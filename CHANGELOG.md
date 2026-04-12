# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning.

## [Unreleased]

### Added

#### Core Infrastructure
- **Provider Resolution System**: Auto-detection with priority ordering (OpenAI > Claude > Kimi > Gemini > GLM > Ollama)
  - `Get-ProviderProfile`, `Resolve-ProviderProfile`, `Get-ProviderPreferenceOrder`
  - Environment variable override support (`LLM_PROVIDER`)
  - Alternative env var names (e.g., `MOONSHOT_API_KEY` for Kimi)
  - 35 Pester tests for provider resolution logic

#### Memory & Sync Features
- **Multi-Palace Support (v2.0)**: Sync from multiple MemPalace instances
  - Config migration from v1.0 to v2.0 with automatic backup
  - Per-palace state tracking and consolidated summaries
  - New commands: `Get-LLMWorkflowPalaces`, `Sync-LLMWorkflowPalace`, `Sync-LLMWorkflowAllPalaces`
  - Aliases: `llmpalaces`, `llmsync`

- **Parallel Bridge Writes**: ThreadPoolExecutor for concurrent sync operations
  - Configurable `--workers` parameter (default 4, max 10)
  - Exponential backoff retry logic (3 retries, 1s/2s/4s delays)
  - Thread-safe state management with locks

- **Memory Snapshots**: Export/import full workflow state
  - `Export-LLMWorkflowMemory` / `Import-LLMWorkflowMemory`
  - Archive project state with metadata and history

#### Plugin Architecture
- **Plugin System**: Third-party tool integration via `.llm-workflow/plugins.json`
  - Register plugins with `Register-LLMWorkflowPlugin`
  - Trigger support: `bootstrap`, `check`
  - Plugin validation and execution
  - Example plugin template included
  - Alias: `llmplugins`

#### Game Development Features
- **Game Team Workflow Preset**: `llmup -GameTeam`
  - 8 game templates (2d-platformer, roguelike, visual-novel, etc.)
  - Game Design Document (GDD) template generation
  - Asset manifest with license tracking
  - Task board templates (HacknPlan, Trello, GitHub Projects compatible)
  - Jam mode for rapid prototyping

#### Observability & Diagnostics
- **Interactive TUI Dashboard**: `Show-LLMWorkflowDashboard` (alias: `llmdashboard`)
  - Real-time health monitoring with color-coded status
  - Progress tracking and latency measurements
  - Interactive controls (R=re-run, Q=quit, A=auto-refresh)
  - Plain-text fallback for CI/CD

- **Self-Healing**: `Invoke-LLMWorkflowHeal` (alias: `llmheal`)
  - Auto-fix common issues (missing .env, Python paths, ChromaDB, etc.)
  - `-WhatIf` dry-run mode
  - `-Force` auto-apply mode
  - Repair history tracking with export

- **Latency Reporting**: Response time tracking for all network operations
  - Doctor checks show timing (e.g., "127.0.0.1:8075/health ok=true (23ms)")
  - Performance bottleneck identification

- **Sync History**: JSONL-based sync operation logging
  - `Get-LLMWorkflowSyncHistory` (alias: `llmhistory`)
  - Configurable max entries (default 500)
  - Trend analysis support

- **Timing Metrics**: Bootstrap phase duration tracking
  - `-ShowTiming` flag outputs phase durations
  - Identify slow operations in workflow

#### Operational Features
- **Graceful Degradation**: `-ContinueOnError` continues on failures
  - Summary table of all phase results
  - Non-zero exit code but completes all possible steps

- **Offline Mode**: `-Offline` skips all network operations
  - Local-only operations for air-gapped environments
  - Useful for development on planes/trains

- **Structured JSON Logging**: `-AsJson` flag for machine-readable output
  - CI/CD pipeline integration
  - Consistent schema across all commands

#### Developer Experience
- **JSON Schema Validation**: IDE autocomplete and validation
  - Schemas for bridge.config.json, index.defaults.json, orchestrator.env
  - VS Code integration with hover tooltips
  - Pattern validation for URLs and enums

- **Docker Support**: Full containerization
  - `Dockerfile` and `Dockerfile.windows`
  - `docker-compose.yml` with ChromaDB and Ollama services
  - CI/CD pipeline examples

- **Cross-Platform CI Matrix**: GitHub Actions for Windows, Linux, macOS
  - Path separator fixes (`Join-Path` usage)
  - Platform-specific module paths
  - Experimental Linux/macOS support

- **PSScriptAnalyzer Compliance**: Full linting integration
  - All functions have `[CmdletBinding()]`
  - Cross-platform path handling
  - CI lint job with warning/error separation

- **Tab Completion**: Argument completers for providers, templates, tools

#### Security & Quality
- **API Key Validation**: `Test-ProviderKey` validates credentials
  - Latency tracking per provider
  - Provider-specific endpoint testing

- **Secret Masking**: `Protect-Secret` masks API keys in output
  - Format: `sk-...XXXX`
  - `-ShowSecrets` flag for debugging

- **Template Drift Detection**: Validates tool scripts match templates
  - CI gate to prevent drift
  - Automatic re-sync capability

### Changed
- Enhanced bootstrap script with phase tracking and timing
- Improved error handling with categorized messages (CRITICAL/WARNING/INFO)
- Cross-platform path separator fixes throughout
- Updated CI workflow with E2E integration tests

### Fixed
- Path separator consistency (all paths use `Join-Path`)
- PowerShell 5.1 compatibility issues
- Unicode character handling (ASCII-only output)
- `$args` variable shadowing in scripts

## [0.2.0] - 2026-04-11

### Added
- New module commands:
  - `Get-LLMWorkflowVersion`
  - `Update-LLMWorkflow` (GitHub release download + SHA256 verification)
  - `Test-LLMWorkflowSetup`
  - aliases: `llmver`, `llmupdate`, `llmcheck`
- `compatibility.lock.json` with pinned tested refs for CodeMunch/ContextLattice/MemPalace.
- Compatibility lock validation CI gate (`tools/ci/validate-compatibility-lock.ps1`).
- Mock ContextLattice integration harness with Pester integration tests.
- Release hardening:
  - optional Authenticode signing in release workflow
  - signing report artifact
- New automation workflows:
  - PowerShell Gallery publish
  - supply-chain workflow (dependency review, SBOM, pip-audit)

## [0.1.0] - 2026-04-11

### Added
- Canonical all-in-one toolkit for CodeMunch Pro, ContextLattice, and MemPalace.
- Global one-shot bootstrap command (`llm-workflow-up`, `llmup`).
- Versioned PowerShell module (`LLMWorkflow`) with:
  - `Install-LLMWorkflow`
  - `Invoke-LLMWorkflowUp`
  - `llmup` alias
