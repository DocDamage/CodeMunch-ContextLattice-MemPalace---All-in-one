# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning.

## Related Docs
- [Release State](./RELEASE_STATE.md)
- [v1.0 Release Criteria](./V1_RELEASE_CRITERIA.md)
- [Release Certification Checklist](./RELEASE_CERTIFICATION_CHECKLIST.md)
- [Remaining Work](../implementation/REMAINING_WORK.md)

## [Unreleased]

### Added - Game Asset Intake Foundation

- Engine-aware game asset manifest and preset scaffolding for:
  - `art`
  - `spritesheets`
  - `tilemaps`
  - `plugins`
  - `rpgmaker`
  - `unreal`
  - `epic`
  - `shared`
- Asset scan classification and metadata preservation across those families
- **UnrealDescriptorParser.ps1** for structured extraction of `.uplugin` and `.uproject`
- **RPGMakerAssetCatalogParser.ps1** for RPG Maker MV/MZ project asset cataloging across common `img/*`, `audio/*`, and `js/plugins` directories
- Regression tests for:
  - multi-engine asset manifest behavior
  - Unreal descriptor extraction
  - RPG Maker asset catalog parsing

### Changed - Documentation and Strategic Alignment

- Reframed the post-0.9.6 strategic execution plan around platform discipline plus artifact/game-asset ingestion hardening
- Updated top-level docs to distinguish broader game asset inventory support from deeper extraction support
- Added README examples and progress tracking for the new asset intake direction

## [0.9.6] - 2026-04-13

### Added - Appendage A Completion

- **15 Godot Pack Appendage A repositories added to source registry**
- New source families:
  - `ai_behavior` - AI behavior trees and decision-making patterns
  - `ai_fsm` - Finite state machine implementations
  - `dialogue` - Dialogue systems and conversation management
  - `rpg_data` - RPG data structures and persistence
  - `world_streaming` - World streaming and chunk management
  - `platform_services` - Platform integration services
  - `debugging` - Debugging tools and profilers
  - `voxel_systems` - Voxel-based world systems
- Total Godot pack sources: **43** (up from 29)

### Added - New Extraction Parsers

- **GodotInventoryExtractor.ps1** - Inventory, crafting, and equipment system extraction
- **GodotQuestExtractor.ps1** - Quest system parsing including objectives and rewards
- **GodotNetworkingExtractor.ps1** - Rollback netcode and RPC pattern extraction

### Added - MCP Toolkit Expansion

- **15 new MCP tools** across Godot, Blender, and RPG Maker MZ:
  - **Godot Engine (5 tools):**
    - `export_project` - Automated project export
    - `build_project` - Build pipeline execution
    - `run_tests` - Test suite execution
    - `check_syntax` - GDScript syntax validation
    - `get_scene_tree` - Scene hierarchy extraction
  - **Blender (5 tools):**
    - `import_mesh` - Mesh import automation
    - `render_scene` - Rendering pipeline
    - `list_materials` - Material inventory
    - `apply_modifier` - Modifier stack operations
    - `export_godot` - Godot-compatible export
  - **RPG Maker MZ (5 tools):**
    - `project_info` - Project metadata extraction
    - `list_plugins` - Plugin inventory
    - `analyze_plugin` - Plugin conflict analysis
    - `create_skeleton` - Plugin skeleton generation
    - `validate_notetags` - Notetag syntax validation

### Added - Test Suite

- **Core.Tests.ps1** (~75 tests) - Core module unit tests
- **MCP.Tests.ps1** (~50 tests) - MCP toolkit integration tests
- **Pack.Tests.ps1** (~85 tests) - Pack framework validation tests

### Added - Post-0.9.6 Strategic Platform Hardening

- **Observability backbone** - OTel bridge, trace schema, span factory (36 tests)
- **Policy externalization** - OPA adapter, externalized bundles, decision cache (29 tests)
- **Document/game-asset ingestion** - Docling/Tika adapters, normalizer, evidence classifier (21 tests)
- **Security baseline** - Secret scanning, SBOM, vulnerability scanning (20 tests)
- **Durable execution** - DurableOrchestrator, FailureTaxonomy, recovery playbooks (20 tests)
- **MCP governance registry** - MCPToolRegistry, MCPToolLifecycle, governance model (26 tests)
- **Retrieval substrate** - Query routing, cross-pack arbitration, confidence/evidence policies
- **v1.0 certification framework** - Release-state reconciliation, truth matrix, CI validation

### Updated

- Total modules: **106** PowerShell modules
- Total functions: **850+**
- Total lines of code: **100,000+**
- Domain packs: **10**
- Extraction parsers: **37+**
- Golden tasks: **30**

## [0.9.5] - 2026-04-12

### Added

#### Extended Domain Packs

- **4 New Domain Packs:**
  - `voice-audio-pack` - Voice synthesis, audio processing, speech recognition
  - `engine-reference-pack` - Game engine internals and reference documentation
  - `ui-frontend-pack` - UI frameworks, component libraries, frontend patterns
  - `ml-education-pack` - Machine learning tutorials, educational content, ML fundamentals

- **8 New Extraction Parsers:**
  - `VoiceMarkupParser.ps1` - Voice markup format parsing (SSML, etc.)
  - `AudioMetadataParser.ps1` - Audio file metadata extraction
  - `UIComponentParser.ps1` - UI component definition parsing
  - `FrontendConfigParser.ps1` - Frontend build config extraction (webpack, vite, etc.)
  - `MLNotebookParser.ps1` - ML training notebook parsing
  - `APIBlueprintParser.ps1` - API Blueprint specification parsing
  - `AgentBehaviorParser.ps1` - Agent simulation behavior tree parsing
  - `NotebookCellParser.ps1` - Jupyter notebook cell extraction

- **4 Advanced Inter-Pack Pipelines:**
  - Voice-to-Animation pipeline (Voice → Godot Animation)
  - UI-to-Scene pipeline (Frontend → Godot UI scenes)
  - ML-to-Shader pipeline (ML education → GDShader)
  - API-to-Plugin pipeline (API docs → RPG Maker plugins)

- **Godot Extended Sources:**
  - 9 additional Godot repository sources added
  - Enhanced GDExtension coverage
  - Additional demo project templates

## [0.9.0] - 2026-04-12

### Added

#### Future Pack Candidates

- **3 New Domain Packs:**
  - `api-reverse-pack` - API reverse engineering documentation and patterns
  - `notebook-pack` - Interactive notebook content and cell-based tutorials
  - `agent-simulation-pack` - Agent-based simulation frameworks and behavior models

- **MCP Deployment Scripts (5 tools):**
  - `Deploy-MCPServer.ps1` - Server deployment automation
  - `Register-MCPTool.ps1` - Tool registration with gateway
  - `Test-MCPDeployment.ps1` - Deployment validation and health checks
  - `Update-MCPManifest.ps1` - Manifest synchronization
  - `Invoke-MCPRollback.ps1` - Safe rollback procedures

- **Performance Benchmarking Suite (5 modules):**
  - `RetrievalBenchmark.ps1` - Retrieval latency and accuracy benchmarks
  - `ExtractionBenchmark.ps1` - Parser performance testing
  - `CacheBenchmark.ps1` - Cache hit rate and eviction testing
  - `QueryRouterBenchmark.ps1` - Routing decision performance
  - `EndToEndBenchmark.ps1` - Full workflow performance testing

- **25 New Golden Task Evaluations:**
  - 10 API reverse engineering tasks
  - 8 Notebook interaction tasks
  - 7 Agent simulation tasks
  - Property-based validation for all new tasks

## [0.8.0] - 2026-04-12

### Added

#### Phase 7 Platform Expansion

- **MCP Toolkit Servers (21 tools):**
  - `MCPServer-Retrieval.ps1` - MCP-compliant retrieval server
  - `MCPServer-Extraction.ps1` - Structured extraction MCP interface
  - `MCPServer-QueryRouter.ps1` - Query routing MCP service
  - `MCPServer-HealthMonitor.ps1` - Health monitoring MCP endpoint
  - `MCPServer-PackManager.ps1` - Pack management MCP interface
  - `MCPServer-Sync.ps1` - Synchronization MCP service
  - `MCPServer-Config.ps1` - Configuration MCP server
  - `MCPServer-Validation.ps1` - Validation MCP service
  - `MCPServer-Arbitration.ps1` - Cross-pack arbitration MCP
  - `MCPServer-Telemetry.ps1` - Telemetry collection MCP
  - `MCPServer-Incident.ps1` - Incident management MCP
  - `MCPServer-Replay.ps1` - Replay harness MCP interface
  - `MCPServer-Annotation.ps1` - Human annotation MCP
  - `MCPServer-GoldenTask.ps1` - Golden task evaluation MCP
  - `MCPServer-SLO.ps1` - SLO monitoring MCP
  - `MCPServer-ReviewGate.ps1` - Human review gate MCP
  - `MCPServer-Snapshot.ps1` - Memory snapshot MCP
  - `MCPServer-NaturalLang.ps1` - Natural language config MCP
  - `MCPServer-Dashboard.ps1` - Dashboard data MCP
  - `MCPServer-Ingestion.ps1` - External ingestion MCP
  - `MCPServer-Gateway.ps1` - Composite gateway MCP

- **MCP Composite Gateway:**
  - Unified entry point for all MCP toolkit servers
  - Request routing and load balancing
  - Authentication and rate limiting
  - Request/response transformation
  - Gateway health monitoring

- **Inter-Pack Transport:**
  - Cross-pack data transport layer
  - Schema translation between pack formats
  - Bidirectional sync capabilities
  - Transport integrity validation
  - `Invoke-InterPackTransport`, `Sync-PackData`

- **Snapshot Import/Export:**
  - Full workflow state snapshots
  - Incremental snapshot support
  - Cross-instance snapshot migration
  - Snapshot compression and encryption
  - `Export-WorkflowSnapshot`, `Import-WorkflowSnapshot`

- **Federated Memory:**
  - Multi-instance memory federation
  - Distributed memory synchronization
  - Conflict resolution for federated updates
  - Memory shard management
  - `Register-FederatedMemory`, `Sync-FederatedMemory`

- **Natural Language Config:**
  - Plain English configuration interface
  - Config validation via natural language
  - Intent-based config modification
  - Config explanation generation
  - `Set-ConfigByNaturalLanguage`, `Get-ConfigExplanation`

- **Dashboard Views:**
  - System health dashboard
  - Pack status dashboard
  - Retrieval performance dashboard
  - Golden task results dashboard
  - SLO compliance dashboard
  - `Show-SystemDashboard`, `Show-PackDashboard`

- **External Ingestion:**
  - Webhook-based external data ingestion
  - API endpoint ingestion
  - File upload ingestion
  - Ingestion pipeline orchestration
  - Validation and sanitization
  - `Register-IngestionEndpoint`, `Invoke-ExternalIngestion`

### Added

#### Phase 6 Human Trust & Governance (v0.7.0)

Complete implementation of Phase 6 using agent swarm approach:

**Human Annotations (HumanAnnotations.ps1)**
- Human annotation system for corrections and overrides
- `New-HumanAnnotation` with 7 annotation types: correction, deprecation, confidence, compatibility, relevance, caveat, override
- `New-ProjectOverride` for project-local customizations
- `Apply-Annotations` to answers and evidence
- `Get-EffectiveAnnotations` with override resolution
- Voting system: `Vote-Annotation` with score calculation
- Export/Import: `Export-Annotations`, `Import-Annotations`
- Storage: `.llm-workflow/state/annotations.json`

**Golden Tasks (GoldenTasks.ps1)**
- Golden task evaluation framework with property-based validation
- `New-GoldenTask` with flexible validation rules
- `Invoke-GoldenTaskEval` for running evaluations
- `Invoke-PackGoldenTasks` with parallel execution support
- `Test-PropertyBasedExpectation` for non-exact matching
- **10 Predefined Golden Tasks:**
  - RPG Maker MZ: Plugin skeleton, conflict diagnosis, notetag extraction, patch analysis
  - Godot Engine: GDScript class, signal connection, autoload setup
  - Blender Engine: Operator registration, geometry nodes, addon manifest
- Historical result tracking with pass/fail trending

**Replay Harness (ReplayHarness.ps1)**
- Before/after replay system for upgrade validation
- `Invoke-AnswerReplay` - Main replay orchestrator
- `Invoke-GoldenTaskReplay` - Replay golden tasks with config comparison
- `Invoke-IncidentReplay` - Replay bad-answer incidents
- `Compare-ReplayResults` - Detailed difference detection
- `Test-Regression` - Severity classification (minor/moderate/critical)
- `New-ReplayReport` - Summary, detailed, and comparison reports
- Batch replay: `Invoke-BatchReplay` with progress tracking
- Regression detection: evidence overlap, confidence delta, answer mode consistency

**Pack SLOs (PackSLOs.ps1)**
- Service level objectives and telemetry tracking
- `New-PackSLO` with configurable targets and thresholds
- `Record-Telemetry` with JSON Lines storage
- `Get-PackSLOStatus` with time range filtering
- `Test-SLOCompliance` with violation detection
- **SLO Targets:**
  - p95RetrievalLatencyMs: 1200ms
  - answerGroundingRate: 0.95
  - parserFailureRate: 0.02
  - provenanceCoverage: 0.99
  - goldenTaskPassRate: 0.90
- P95/P99 percentile calculations
- Trend analysis: improving/stable/degrading
- Automatic telemetry rotation (30-day retention)
- Predefined SLOs for RPG Maker MZ, Godot Engine, Blender Engine

**Human Review Gates (HumanReviewGates.ps1)**
- Approval workflows for sensitive operations
- `Test-HumanReviewRequired` - Check if review needed
- `New-ReviewGateRequest` - Create review requests
- `Submit-ReviewDecision` - Approve/reject with comments
- `Get-PendingReviews` - Review queue management
- **Review Triggers:**
  - `Test-LargeSourceDelta` - Large source changes (>30%)
  - `Test-MajorVersionJump` - Major version changes
  - `Test-TrustTierChange` - Trust tier modifications
  - `Test-VisibilityBoundaryChange` - Visibility changes
  - `Test-EvalRegression` - Evaluation regressions
- Review policies: `New-ReviewPolicy` with configurable rules
- Escalation: `Invoke-ReviewEscalation` after timeout

#### Phase 5 Retrieval & Answer Integrity (v0.7.0)

Complete implementation of Phase 5 using agent swarm approach:

**Query Router (QueryRouter.ps1)**
- Query intent detection and pack routing
- `Invoke-QueryRouting` - Main router with pack selection
- `Get-QueryIntent` - Intent detection via keyword matching
- `Route-QueryToPacks` - Pack ranking and ordering
- `Get-RoutingExplanation` - Human-readable routing decisions
- **7 Retrieval Profiles:** api-lookup, plugin-pattern, conflict-diagnosis, codegen, private-project-first, tooling-workflow, reverse-format
- Domain keyword matching for pack relevance
- Project-local query detection

**Retrieval Profiles (RetrievalProfiles.ps1)**
- Profile management and configuration
- `Get-RetrievalProfileConfig` - Get profile settings
- `Get-AllRetrievalProfiles` - List built-in and custom profiles
- `New-CustomRetrievalProfile` - Create user-defined profiles
- `Get-ProfilePackPreferences` - Pack ordering per profile
- `Get-ProfileEvidenceTypes` - Allowed evidence types
- Profile schema: pack preferences, evidence types, min trust tier, multi-source requirements

**Answer Plan & Trace (AnswerPlan.ps1)**
- Answer planning before synthesis, tracing after
- `New-AnswerPlan` - Create plan with retrieval profile
- `Add-PlanEvidence` - Add evidence requirements
- `Test-AnswerPlanCompleteness` - Validate plan
- `New-AnswerTrace` - Create trace after synthesis
- `Add-TraceEvidence` - Record evidence used
- `Add-TraceExclusion` - Record evidence excluded and why
- `Export-AnswerTrace` - Audit trail export
- **Answer Modes:** direct, caveat, dispute, abstain, escalate

**Cross-Pack Arbitration (CrossPackArbitration.ps1)**
- Multi-pack query handling and dispute resolution
- `Invoke-CrossPackArbitration` - Main arbitration logic
- `Test-PackRelevance` - Score pack relevance (0.0-1.0)
- `Get-ArbitratedPackOrder` - Priority-ordered pack list
- `Test-CrossPackAnswer` - Detect cross-pack queries
- `Add-CrossPackLabel` - Label multi-source answers
- `New-DisputeSet` - Create dispute sets (Section 13.2)
- `Add-DisputeClaim` - Add competing claims
- `Resolve-PackConflicts` - Cross-domain conflict detection

**Confidence Policy (ConfidencePolicy.ps1)**
- Confidence calculation and abstain decisions
- `Test-AnswerConfidence` - 4-factor confidence scoring
- `Get-AnswerMode` - Determine mode from confidence
- `Test-ShouldAbstain` - Low confidence detection
- `Get-ConfidenceComponents` - Factor breakdown
- `Get-AbstainDecision` - Structured abstain reasoning
- `Get-EscalationDecision` - Human review escalation
- **Confidence Factors:**
  - Evidence relevance: 0-40%
  - Source authority: 0-30%
  - Evidence consistency: 0-20%
  - Coverage: 0-10%
- **Thresholds:** direct (≥0.85), caveat (≥0.70), abstain (<0.50)

**Evidence Policy (EvidencePolicy.ps1)**
- Evidence validation and authority checking
- `Test-EvidencePolicy` - Full policy validation
- `Get-EvidenceQuality` - Quality scoring (0.0-1.0)
- `Test-EvidenceAuthority` - Authority requirement checking
- `Filter-EvidenceByPolicy` - Policy-based filtering
- `Test-TranslationOnlyEvidence` - Translation-only detection
- `Sort-BySourceAuthority` - Foundational-first sorting
- `Assert-PrivateProjectPrecedence` - Private project priority
- **Evidence Classification:** foundational > authoritative > exemplar > community > translation

**Caveat Registry (CaveatRegistry.ps1)**
- Known caveats and falsehoods registry
- `Get-CaveatRegistry` - Singleton registry access
- `Register-Caveat` - Add new caveat
- `Find-ApplicableCaveats` - Query-triggered caveats
- `Add-AnswerCaveats` - Attach caveats to answers
- `Test-KnownFalsehoods` - Falsehood detection
- **14 Predefined Caveats:**
  - Godot: 3 vs 4 syntax, typed arrays, signal syntax, node paths, C# limitations
  - RPG Maker: Plugin order, alias patterns, eval security
  - Blender: Python API changes, geometry nodes fields
- Categories: version-boundary, misconception, compatibility, experimental, deprecated

**Retrieval Cache (RetrievalCache.ps1)**
- Caching with LRU eviction and smart invalidation
- `Get-CachedRetrieval` - Cache retrieval with validation
- `Set-CachedRetrieval` - Store with TTL
- `Get-RetrievalCacheKey` - SHA256 key generation
- `Invoke-CacheInvalidation` - Targeted invalidation
- `Invoke-PackCacheInvalidation` - Pack update invalidation
- `Invoke-CacheMaintenance` - Cleanup and LRU eviction
- **Configuration:** 1h TTL (normal), 24h (API), max 1000 entries
- Cache key: query hash + profile + pack versions + taxonomy

**Incident Bundle (IncidentBundle.ps1)**
- Bad answer tracking and investigation
- `New-AnswerIncidentBundle` - Create incident
- `Add-IncidentEvidence` - Add selected/excluded evidence
- `Add-IncidentFeedback` - Link user feedback
- `Search-IncidentBundles` - Search by criteria
- `Get-IncidentRootCause` - Root cause analysis
- `Test-IncidentPattern` - Pattern matching
- **8 Root Cause Categories:**
  - bad-retrieval, wrong-authority-level, contradiction-not-surfaced
  - low-confidence-should-abstain, missing-source
  - extraction-bug, ranking-bug, privacy-boundary-issue
- **6 Known Patterns:** hallucination, outdated-info, contradiction-ignored, wrong-authority, incomplete-retrieval, privacy-leak

#### Phase 4 Structured Extraction Pipeline (v0.6.0)

Complete implementation of Phase 4 using agent swarm approach:

**GDScript Parser (GDScriptParser.ps1)**
- Godot GDScript file parsing (.gd) with class/method/signal extraction
- `Invoke-GDScriptParse`, `Get-GDScriptClassInfo`, `Get-GDScriptSignals`
- Extracts `@export`, `@onready`, `@tool`, `@icon` annotations
- Typed variable and function signature parsing
- Doc comment extraction (`##` style)
- Godot 3.x and 4.x syntax variant support
- Project-level extraction: `Get-GDScriptAutoloads`, `Get-GDScriptInputActions`
- Addon metadata: `Get-GDScriptAddonMetadata` (plugin.cfg)
- GDExtension manifest parsing: `Get-GDExtensionManifest`

**Godot Scene Parser (GodotSceneParser.ps1)**
- Scene file parsing (.tscn) with node hierarchy extraction
- Resource file parsing (.tres)
- `Invoke-GodotSceneParse`, `Get-SceneNodeHierarchy`
- Signal connection extraction: `Get-SceneSignalConnections`
- External/sub-resource reference tracking: `Get-SceneResourceRefs`
- Godot value type parsing: Vector2/3, Color, NodePath, ExtResource, SubResource
- Format 2 (Godot 3) and Format 3 (Godot 4) support

**RPG Maker Plugin Parser (RPGMakerPluginParser.ps1)**
- RPG Maker MZ/MV plugin file parsing (.js)
- `Invoke-RPGMakerPluginParse`, `Get-PluginMetadata`
- Plugin header extraction: `@target`, `@plugindesc`, `@author`, `@url`
- Parameter extraction with full type info: `Get-PluginParameters`
  - Types: number, string, boolean, select, actor, class, skill, item, struct, etc.
- Command extraction: `Get-PluginCommands` (MZ @command) and `Get-PluginLegacyCommands` (MV @pluginCommand)
- Dependency tracking: `Get-PluginDependencies` (@requires)
- Conflict detection: `Test-PluginConflict`, `Get-PluginConflicts`
- Load order extraction: `Get-PluginOrder` (@before, @after)

**Blender Python Parser (BlenderPythonParser.ps1)**
- Blender addon/script parsing (.py)
- `Invoke-BlenderPythonParse`, `Get-BlenderAddonInfo`
- bl_info dictionary extraction (name, author, version, blender version, category)
- Operator class registration extraction: `Get-BlenderOperators`
  - bl_idname, bl_label, bl_description, bl_options
  - Property declarations (bpy.props.*)
- Panel class extraction: `Get-BlenderPanels`
- Menu class extraction: `Get-BlenderMenus`
- Operator call pattern extraction: `Get-BlenderOperatorCalls` (bpy.ops.*)
- Dependency tracking: `Get-BlenderImports`, `Get-BlenderDependencies`

**Geometry Nodes Parser (GeometryNodesParser.ps1)**
- Blender Geometry Nodes tree structure extraction
- `Invoke-GeometryNodesParse`, `Get-NodeTreeStructure`
- Node group input/output interface extraction
- Support for: Mesh primitives, Point primitives, Utilities, Attributes
- Geometry operations: Join, Merge, Extrude, Subdivision
- Material nodes: Set Material, Material Selection
- Multiple input formats: Python scripts, JSON exports, .blend text blocks

**Shader Parser (ShaderParser.ps1)**
- Godot GDShader file parsing (.gdshader, .shader)
- Blender shader node tree parsing
- `ConvertFrom-GodotShader`, `ConvertFrom-BlenderShaderNodes`
- Shader type detection: spatial, canvas_item, particles, sky, fog
- Uniform parameter extraction with hints:
  - `hint_range(min, max, step)`, `source_color`
  - `hint_default_white/black`, `hint_normal`, `hint_anisotropy`
- Function signature extraction: `Get-ShaderFunctionDefinition`
- Varying and struct definition extraction
- Preprocessor directive parsing: `Get-ShaderPreprocessorDirectives`

**Extraction Pipeline Orchestrator (ExtractionPipeline.ps1)**
- Unified entry point: `Invoke-StructuredExtraction` with automatic file type detection
- Batch processing: `Invoke-BatchExtraction` with progress reporting
- Schema definitions: `Get-ExtractionSchema` for all extraction types
- File type validation: `Test-ExtractionSupported`
- Report generation: `Export-ExtractionReport`
- Normalized output envelope with metadata, errors, warnings

**Pack Manifest Updates**
- Added `extractionConfig` sections to all pack manifests
- File extension to parser mappings for each domain
- Extraction target configurations with parser function references
- Content validation patterns for ambiguous extensions

**Test Suite**
- Comprehensive Pester tests: `tests/ExtractionPipeline.Tests.ps1`
- Tests for all parsers and batch operations

#### Phase 3 Operator Workflow (v0.5.0)

Complete implementation of Phase 3 priorities using agent swarm approach:

**Priority 1: Health Score + Monitoring**
- Health score calculation (0-100) with component breakdown
- Source registry, lockfile, freshness, validation scoring
- Workspace health summaries with status indicators (Healthy/Degraded/Critical)
- Health report export with trending analysis (improving/stable/degrading)
- `Get-PackHealthScore`, `Test-PackHealth`, `Get-WorkspaceHealthSummary`

**Priority 2: Planner + Executor Previews**
- Execution plan creation with step-by-step operations
- Dry-run mode for preview without execution
- Resume support for interrupted plans
- Journal integration with before/after checkpoints
- Rollback on failure with automatic cleanup
- Plan manifest export/import for replay
- `New-ExecutionPlan`, `Invoke-ExecutionPlan`, `Show-ExecutionPlan`

**Priority 3: Git Hooks Integration**
- Pre-commit hooks with secret scanning and health checks (< 5s target)
- Post-commit hooks for auto-sync triggering
- Pre-push hooks with full validation and compatibility checks
- Cross-platform PowerShell hook scripts
- Backup/restore of existing hooks
- `Install-LLMWorkflowGitHooks`, `Invoke-GitHookPreCommit`

**Priority 4: Compatibility + Version Management**
- Semantic version comparison with range support (^, ~, >=, <)
- Pack/toolkit/source compatibility validation
- Version drift detection with severity levels
- Compatibility lockfile export (compatibility.lock.json)
- Cross-pack compatibility (Blender → Godot pipeline)
- `Test-CompatibilityMatrix`, `Get-VersionDrift`, `Assert-CompatibilityBeforeOperation`

**Priority 5: Include/Exclude Rules + Filters**
- Glob pattern support (**/*.js, src/**/*)
- Regex and literal path matching
- Priority-based pattern evaluation
- Per-pack default filters (RPG Maker, Godot, Blender)
- Filter config export/import
- `New-IncludeExcludeFilter`, `Get-IncludedSources`, `Test-PathAgainstFilter`

**Priority 6: Notification Hooks**
- Webhook notifications with retry logic (3 attempts, exponential backoff)
- Command execution notifications
- Log and event notifications
- Rate limiting per hook
- Async delivery (non-blocking)
- Standardized JSON payloads
- `Register-NotificationHook`, `Send-Notification`, `Invoke-NotificationWebhook`

#### Phase 2 Pack Framework (v0.4.0)

Complete implementation of Phase 2 priorities:

**Priority 1: Pack Manifest + Source Registry**
- Pack manifest schema with lifecycle states (draft → promoted → deprecated → retired)
- Source registry with trust tiers (High, Medium-High, Medium, Low, Quarantined)
- Install profiles: minimal, core-only, developer, full, private-first
- Authority roles per pack (core-runtime, exemplar-pattern, tooling-analyzer, etc.)
- Source priority ordering (P0-P5)
- Risk notes and retrieval routing rules
- `New-PackManifest`, `Set-PackLifecycleState`, `New-SourceRegistryEntry`

**Priority 2: Pack Transaction + Lockfile**
- Transaction model: prepare → build → validate → promote → rollback
- Deterministic pack.lock.json generation
- Build manifest creation with artifact counts
- Promotion/rollback support with state validation
- `New-PackTransaction`, `New-PackLockfile`, `Publish-PackBuild`, `Undo-PackBuild`

**Pack Definitions Created:**
- **RPG Maker MZ Pack** (`rpgmaker-mz`): 5 collections, 20+ sources, plugin conflict diagnosis
- **Godot Engine Pack** (`godot-engine`): 7 collections, 20+ sources, MCP integration
- **Blender Engine Pack** (`blender-engine`): 6 collections, 9 sources, synthetic data support

#### Phase 1 Core Infrastructure (v0.3.0)

Complete implementation of Phase 1 priorities from IMPROVEMENT_PROPOSALS.md using agent swarm approach:

**Priority 1: Journaling + Checkpoints**
- Run identification system with `New-RunId` (timestamp-based IDs like `20260411T210501Z-7f2c`)
- Structured JSON-lines logging with redaction support (`Write-StructuredLog`)
- Run manifests tracking command, args, execution mode, locks, artifacts
- Journal entries with before/after checkpoints for resume support
- Correlation IDs for distributed tracing

**Priority 2: File Locking + Atomic Writes**
- Cross-platform file locking (`Lock-File`, `Unlock-File`, `Test-StaleLock`)
- Atomic write operations using temp-file + fsync + rename pattern
- State file management with schema versioning
- Stale lock reclamation with PID verification
- Backup rotation for destructive mutations

**Priority 3: Effective Configuration System**
- 5-level configuration precedence (defaults → profile → project → env → args)
- `Get-LLMWorkflowEffectiveConfig` command with source tracking
- `llmconfig --explain` and `llmconfig --validate` CLI commands
- Secret masking in output (API keys, tokens, passwords)
- Environment variable support with `LLMWF_*` prefix
- Execution mode configuration (interactive, ci, watch, heal-watch, scheduled, mcp-readonly, mcp-mutating)

**Priority 4: Policy + Execution Mode Enforcement**
- Policy gates checked BEFORE locks and BEFORE apply operations
- 7 execution modes with different capability rules
- 4 safety levels: read-only, mutating, destructive, networked
- Command contract system with planner/executor separation
- Confirmation prompts for dangerous operations (restore, prune, delete)
- Exit codes: 9 (policy blocked), 11 (permission denied), 12 (user cancelled)

**Priority 5: Workspace + Visibility Boundaries**
- Workspace management (personal, project, team, readonly)
- 4 visibility levels: private, local-team, shared, public-reference
- Secret and PII scanning with 18 detection patterns
- Private project pack precedence in retrieval
- Export permission controls with data redaction

**New Module Files (16 core PowerShell modules, 100+ functions):**
```
module/LLMWorkflow/core/
├── RunId.ps1, Logging.ps1, Journal.ps1
├── FileLock.ps1, AtomicWrite.ps1, StateFile.ps1
├── ConfigSchema.ps1, ConfigPath.ps1, Config.ps1, ConfigCLI.ps1
├── Policy.ps1, ExecutionMode.ps1, CommandContract.ps1
├── Workspace.ps1, Visibility.ps1, PackVisibility.ps1
```

**System Invariants Implemented:**
- Command contract invariant (safety levels, exit codes, dry-run)
- State safety invariant (atomic writes, file locking, schema versioning)
- Journal invariant (before/after checkpoint entries)
- Policy invariant (gates before locks and apply)
- Secret/PII invariant (redaction, masking, scanning)
- Dry-run invariant (planner/executor separation)
- Cross-platform invariant (Windows/Linux/macOS)

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
