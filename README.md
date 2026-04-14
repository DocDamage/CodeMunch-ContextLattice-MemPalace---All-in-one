# CodeMunch + ContextLattice + MemPalace (All-in-One)

[![Version](https://img.shields.io/badge/version-0.9.6-blue.svg)](https://github.com/yourusername/CodeMunch-ContextLattice-MemPalace)
[![Packs](https://img.shields.io/badge/domain%20packs-10-green.svg)](#domain-packs)
[![Modules](https://img.shields.io/badge/PowerShell%20modules-121-purple.svg)](#platform-scope)
[![MCP](https://img.shields.io/badge/MCP%20tools-55-orange.svg)](#advanced-features)

Canonical toolkit repo for the integrated workflow.

## Related Docs
- [Post-0.9.6 Strategic Execution Plan](docs/implementation/LLMWorkflow_Post_0.9.6_Strategic_Execution_Plan.md)
- [Implementation Progress](docs/implementation/PROGRESS.md)
- [Technical Debt Audit Summary](docs/implementation/TECHNICAL_DEBT_AUDIT.md)
- [Remaining Work](docs/implementation/REMAINING_WORK.md)
- [Current Test Baseline and Resolver Hardening Sync](docs/implementation/CURRENT_TEST_BASELINE_AND_RESOLVER_HARDENING.md)

## Remediation Status (2026-04-14)

### Completed Recently
- full `tests/` baseline is now treated as the real CI baseline through `tools/ci/invoke-pester-safe.ps1`
- install/bootstrap smoke is wired into CI alongside drift checking, compatibility-lock validation, and docs-truth validation
- provider resolver hardening is complete at the current branch baseline and covered in `tests/LLMWorkflow.Tests.ps1`
- curated-plugin compatibility coverage now includes active, deprecated, quarantined, retired, and mixed-state fixture scenarios, plus lock pinning coverage
- docs/release path drift was reduced across key workflow and release documents
- stale install-script references were removed in favor of direct module import usage where appropriate

### Still Left To Do
- continue Priority 0 failure-visibility cleanup and silent-failure reduction
- bound the public module contract and remove wildcard export exposure
- consolidate duplicate helpers and collapse parallel subsystem ownership forks
- keep observability, policy, and security enforcement moving toward v1.0 release gates
- keep mixed-artifact and game-asset ingestion governable, provenance-aware, and regression-tested

## Why Use This Toolkit?

### For AI-Assisted Development
- **Unified workflow**: one command (`llmup`) bootstraps the toolchain
- **Memory persistence**: MemPalace + ContextLattice bridge sync preserves useful context
- **Multi-provider support**: OpenAI, Claude, Kimi, Gemini, GLM, and Ollama
- **Context synchronization**: project memory and external memory can be coordinated through the workflow

### For Game Development
- **Game presets**: `llmup -GameTeam` scaffolds game-project structure quickly
- **Asset management**: asset manifests, license tracking, and game-team templates
- **Jam mode**: faster startup path for rapid prototyping and jam workflows
- **Structured extraction**: Godot, RPG Maker, Blender, Unreal descriptors, and project-asset catalogs

### For Operations and CI
- **Cross-platform CI**: Windows primary matrix, Linux/macOS experimental lanes
- **Safe Pester runner**: `tools/ci/invoke-pester-safe.ps1`
- **Docs-truth and drift guards**: compatibility lock validation, template drift detection, docs validation
- **Machine-readable output**: JSON-friendly and automation-friendly PowerShell workflows

## Platform Scope

The platform currently includes **121 PowerShell Modules**, 10 domain packs, 30 extraction parsers, and 60 golden tasks.

| Area | Current scope |
|---|---:|
| Domain packs | 10 |
| PowerShell modules | 121 |
| **Extraction Parsers** | 30 |
| Golden tasks | 60 |
| Benchmark suites | 5 |
| MCP tool surface | 55 |

## Architecture Snapshot

The platform is organized around a unified PowerShell workflow layer that coordinates:
- CodeMunch project indexing
- ContextLattice verification and synchronization
- MemPalace bridge synchronization
- domain-pack extraction, retrieval, governance, and MCP tooling

Core architectural lanes:
- **Core infrastructure**: run IDs, journaling, atomic writes, config, policy, execution modes, workspaces, visibility
- **Pack framework**: manifests, source registries, lockfiles, transactions, compatibility
- **Extraction**: domain-specific parsers and batch extraction support
- **Retrieval and integrity**: routing, confidence policy, answer planning, caveats, caching, incident bundles
- **Governance**: golden tasks, review gates, human annotations, replay, pack SLOs
- **Expansion**: MCP, inter-pack pipelines, snapshots, external ingestion, federated memory

For detailed architecture, see [docs/architecture/ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md).

## Domain Packs

| Pack | Status | Focus |
|---|---|---|
| `godot-engine` | ✅ Promoted | Godot engine development, GDScript, scenes, signals |
| `blender-engine` | ✅ Promoted | Blender automation, operators, geometry nodes, export workflows |
| `rpgmaker-mz` | ✅ Promoted | RPG Maker plugin development, conflict diagnosis, notetags |
| `voice-audio-generation` | ✅ Promoted | Voice, TTS/STS, audio generation pipelines |
| `agent-simulation` | ✅ Promoted | Agent workflows and simulation patterns |
| `notebook-data-workflow` | ✅ Promoted | Notebook and data workflow extraction |
| `ui-frontend-framework` | ✅ Promoted | UI/component and design-system workflows |
| `api-reverse-tooling` | ✅ Promoted | API discovery, reverse engineering, documentation |
| `ml-educational-reference` | ✅ Promoted | ML educational and reference content |
| `engine-reference` | ✅ Promoted | Cross-engine patterns and migration guidance |

## Core Infrastructure

Implemented phases:
- **Phase 1**: reliability and control foundation
- **Phase 2**: pack framework and source registry
- **Phase 3**: operator workflow and guarded execution
- **Phase 4**: structured extraction pipeline
- **Phase 5**: retrieval and answer integrity
- **Phase 6**: human trust, replay, and governance
- **Phase 7**: platform expansion (MCP, inter-pack, snapshots, federation)
- **Phase 8**: extended packs

The repo is now in post-0.9.6 hardening and release-state reconciliation, not raw feature infancy.

## Installation

### Recommended module install

```powershell
Import-Module .\module\LLMWorkflow\LLMWorkflow.psd1 -Force
Install-LLMWorkflow -NoProfileUpdate
```

Then in any project:

```powershell
Invoke-LLMWorkflowUp
# alias
llmup
```

### Script install

```powershell
.\tools\workflow\install-global-llm-workflow.ps1
```

### Uninstall

```powershell
Uninstall-LLMWorkflow
# alias
llmdown
```

## Common Commands

```powershell
llmup         # bootstrap project workflow
llmcheck      # validate setup
llmver        # show version
llmupdate     # update toolkit
llmdashboard  # interactive dashboard
llmheal       # self-healing diagnostics
```

## Game Team Workflow

Use the game-team preset for game repos:

```powershell
llmup -GameTeam -GameTemplate "topdown-rpg" -GameEngine "Godot"
llmup -GameTeam -JamMode
```

Game-oriented structure includes:
- `docs/GDD.md`
- `docs/TASKS.md`
- `assets/ASSET_MANIFEST.json`
- `assets/art`, `spritesheets`, `tilemaps`, `sfx`, `music`, `plugins`, engine-specific asset families
- `.llm-workflow/game-preset.json`

## Plugin Architecture

Third-party tools can register through `.llm-workflow/plugins.json`.

Example registration:

```powershell
Register-LLMWorkflowPlugin -ManifestPath "tools/my-plugin/manifest.json"
Get-LLMWorkflowPlugins
Unregister-LLMWorkflowPlugin -Name "my-plugin"
```

## Testing

Current branch baseline is broader than a few legacy suite counts.

### Baseline now treated as authoritative
- full `tests/` execution through `tools/ci/invoke-pester-safe.ps1`
- Windows CI matrix across `powershell` and `pwsh`
- Linux/macOS experimental Pester lanes
- install/bootstrap smoke
- docs-truth validation
- compatibility-lock validation
- template drift validation
- ContextLattice integration lane

### Local test invocation

```powershell
Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck
.\tools\ci\invoke-pester-safe.ps1 -Path .\tests -CI
```

### Notable hardening now covered
- provider resolver priority order
- `LLM_PROVIDER` override fallback behavior
- alias environment variable handling (`MOONSHOT_API_KEY`, `GOOGLE_API_KEY`, `ZHIPU_API_KEY`)
- base URL precedence and fallback behavior
- curated-plugin compatibility fixtures for active/deprecated/quarantined/retired/mixed scenarios
- Golden Task Evaluations (60 Tasks) and Golden Task Coverage (60 Total) with 60 predefined validation scenarios

CI workflows:
- `.github/workflows/ci.yml`
- `.github/workflows/gitleaks.yml`
- `.github/workflows/codeql.yml`
- `.github/workflows/release.yml`
- `.github/workflows/publish-gallery.yml`
- `.github/workflows/supply-chain.yml`

## Release

```powershell
.\tools\release\bump-module-version.ps1 -Version 0.2.1
git add .
git commit -m "Release 0.2.1"
.\tools\release\create-release-tag.ps1 -Push
```

PowerShell Gallery publishing is automated on GitHub Release publish when `PSGALLERY_API_KEY` is configured in repo secrets.

## Notes
- keep secrets in local `.env` files and never commit them
- use `CONTEXTLATTICE_ORCHESTRATOR_API_KEY` in `.env` or `.contextlattice/orchestrator.env` for ContextLattice auth
- for deeper implementation state, see `docs/implementation/PROGRESS.md`
