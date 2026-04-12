# LLM Workflow — Canonical Architecture, Pack Framework, and Delivery Plan

## Status

**This is the canonical source-of-truth document.**  
It supersedes the earlier implementation plans, review passes, and RPG Maker pack review notes. Earlier documents should be treated as archived design history after this one is adopted.

---

## 1. Purpose

This document defines the complete architecture, governance model, delivery order, and first domain-pack specification for the LLM Workflow platform.

The platform is no longer just a bootstrap script or a convenience wrapper. It is a **stateful operational layer** for:

- local and project-scoped memory
- multi-source ingestion
- structured extraction
- retrieval and answer assembly
- policy-controlled automation
- domain packs
- human review and correction
- long-term pack maintenance

This document is written to prevent three common failures:

1. a feature-rich system with weak state integrity
2. a large corpus with weak retrieval and answer discipline
3. a smart automation layer that humans cannot inspect, correct, or trust

The governing principle is:

> **Do not ship autonomy before safety. Do not ship breadth before answer quality. Do not ship scale before control.**

---

## 2. What this system is optimizing for

The platform must optimize for all of the following at the same time:

- **State integrity** under concurrency, interruption, migration, and recovery
- **Operator trust** through previews, manifests, journals, answer traces, and explainability
- **Safe continuous operation** under watch loops, scheduled runs, and partial outages
- **High-quality retrieval** through pack-aware routing, structured artifacts, evidence rules, and confidence policy
- **Controlled automation** through policy gates, execution modes, budgets, and human review
- **Human-correctable knowledge** through annotations, dispute handling, ownership, and replay
- **Domain scalability** through pack manifests, source registries, pack builds, and lifecycle rules
- **Private/public separation** through workspaces, visibility boundaries, and export controls

---

## 3. System invariants

These are non-negotiable. Every command, pack, and answer path inherits them.

### 3.1 Command contract invariant

Every public command must define:

- purpose
- parameters
- exit codes
- dry-run behavior
- locks acquired
- state touched
- remote systems touched
- output contract
- safety level: `read-only`, `mutating`, `destructive`, `networked`

### 3.2 State safety invariant

Any mutable state/config/log/report file must use:

- file locking
- temp-file write
- flush + fsync
- atomic rename
- schema version tagging
- backup before destructive mutation where applicable

### 3.3 Journal invariant

Any command performing more than one mutating step must write a journal/checkpoint entry before and after each step.

### 3.4 Idempotency invariant

Any command that may retry a remote write must use deterministic idempotency keys or a local dedupe ledger.

### 3.5 Secret and PII invariant

Secrets and sensitive content may never be:

- written to logs unredacted
- stored in manifests unmasked
- shown in previews
- silently embedded into memory stores
- exported in plaintext snapshots unless explicitly requested

### 3.6 Policy invariant

Destructive or agent-invokable operations must pass a policy gate before execution.

### 3.7 Provenance invariant

Every ingested or generated knowledge artifact must answer:

- where did this come from?
- when was it created or imported?
- what source/repo/file produced it?
- what transform generated it?
- what run wrote it?
- what workspace and pack owns it?

### 3.8 Dry-run invariant

Every mutating command must use planner/executor separation. Preview and apply must share the same planner.

### 3.9 Test invariant

Every stateful feature must ship with:

- happy-path test
- negative-path test
- interrupted-execution test or equivalent
- idempotency test
- dry-run equivalence test
- migration/compatibility test if versioned state is involved

### 3.10 Cross-platform invariant

Paths, locks, watchers, temp files, process handling, and child process calls must work on Windows, Linux, and macOS.

### 3.11 Answer integrity invariant

No answer may present low-trust, contradictory, translation-only, or public-example evidence as authoritative without an explicit caveat.

---

## 4. Canonical architecture

### 4.1 Control plane vs data plane

#### Control plane
Implemented primarily in PowerShell/module orchestration. Responsible for:

- init/bootstrap
- effective config resolution
- policy and execution-mode checks
- locks
- planner/executor control
- doctor/heal
- manifests and journals
- human interaction
- pack lifecycle control
- answer planning
- status/health reporting

#### Data plane
Implemented primarily in Python workers. Responsible for:

- sync processing
- vector store I/O
- embedding jobs
- structured extraction
- artifact normalization
- pack builds
- backup/export/import
- retrieval helpers
- re-embedding and migration jobs

Long-running data tasks must not live directly inside top-level PowerShell bodies.

### 4.2 Canonical project layout

```text
.llm-workflow/
  config/
    effective-config.json
    policy.json
    workspace.json
  logs/
    2026-04-11.jsonl
  manifests/
    20260411T210501Z-7f2c.run.json
  journals/
    20260411T210501Z-7f2c.journal.json
  state/
    sync-state.json
    heal-state.json
    compatibility-state.json
    migrations-state.json
    pack-state.json
    entity-registry.json
    schema-registry.json
  telemetry/
    sync-history.jsonl
    key-check-history.jsonl
    index-history.jsonl
    eval-history.jsonl
    answer-history.jsonl
  reports/
    latest-health.json
    latest-sync-plan.json
    latest-pack-build.json
    latest-answer-trace.json
  cache/
    file-hashes.json
    retrieval-cache/
    embed-cache.json
    prefetch-cache.json
  locks/
    sync.lock
    heal.lock
    index.lock
    ingest.lock
    pack.lock
  queue/
    watch-events.jsonl
  backups/
    palace/
    config/
    state/
    manifests/
    packs/
  quarantine/
    parser-failures/
    unsafe-sources/
  packs/
    manifests/
    registries/
    builds/
    staging/
    promoted/
  schemas/
```

### 4.3 Standard persistent file header

Every persistent JSON file should include:

```json
{
  "schemaVersion": 1,
  "updatedUtc": "2026-04-11T21:00:00Z",
  "createdByRunId": "20260411T210501Z-7f2c"
}
```

### 4.4 Standard exit codes

| Code | Meaning |
|---|---|
| 0 | success |
| 1 | general failure |
| 2 | invalid arguments or config |
| 3 | dependency missing |
| 4 | remote service unavailable |
| 5 | auth failure |
| 6 | partial success |
| 7 | state lock unavailable |
| 8 | migration required / incompatible state |
| 9 | safety policy blocked run |
| 10 | budget/circuit breaker blocked run |
| 11 | permission denied by execution mode |
| 12 | user-cancelled / aborted |

---

## 5. Effective configuration, policy, and execution modes

### 5.1 Precedence model

Lowest to highest priority:

1. built-in defaults
2. central named profile
3. project config
4. environment variables in current shell
5. explicit command arguments

### 5.2 Required config commands

- `Get-LLMWorkflowEffectiveConfig`
- `llmconfig --explain`
- `llmconfig --validate`

These must show the final resolved value, the source of the value, masked secrets, and conflicts/shadowing.

### 5.3 Execution modes

- `interactive`
- `ci`
- `watch`
- `heal-watch`
- `scheduled`
- `mcp-readonly`
- `mcp-mutating`

### 5.4 Policy model

Every top-level command must declare capability tags. Policy is checked before locks and before apply.

Example policy file:

```json
{
  "schemaVersion": 1,
  "defaultMode": "interactive",
  "rules": {
    "mcp-readonly": {
      "allow": ["doctor", "status", "preview", "search"],
      "deny": ["restore", "prune", "delete", "switch-provider"]
    },
    "watch": {
      "allow": ["sync", "index", "telemetry"],
      "deny": ["migrate", "restore", "prune"]
    }
  },
  "requireConfirmationFor": ["restore", "prune", "delete", "provider-rotate"]
}
```

---

## 6. State model, manifests, journals, and run integrity

### 6.1 Structured logging

All top-level commands must route through one shared structured logging layer. Logs must support:

- JSON-lines file output
- console rendering
- correlation IDs
- redaction
- retention and rotation
- safe degradation on log write failure

### 6.2 Run manifests

One deterministic manifest per top-level run. It must include:

- run ID
- command and args
- execution mode
- policy decision
- git commit
- config/profile sources
- locks acquired
- artifacts written
- warnings/errors
- exit code
- resume/restart status

### 6.3 Journals and checkpoints

Any multi-step operation must write per-step before/after entries and support `--resume` and `--restart`.

This applies to:

- large sync jobs
- pack builds
- export/import
- restore
- re-embedding
- ingestion
- pack refreshes

### 6.4 File locking and atomic writes

Rules:

- one subsystem = one lock
- lock file includes pid, host, execution mode, run ID, timestamp
- writes use temp-file + fsync + atomic rename
- stale locks must be reclaimable safely

### 6.5 Schema versioning and migrations

Every persistent config/state/artifact file is versioned and migratable. Migration must support:

- sequential upgrades
- dry-run migration plan
- backup before mutation
- compatibility report
- invalid/unknown version handling

---

## 7. Workspaces, visibility boundaries, and private/public control

### 7.1 Workspace model

All queries, annotations, pack selections, and exports must execute inside an explicit workspace context.

Workspace types:

- personal default workspace
- project-specific workspace
- team workspace
- read-only reference workspace

Example:

```json
{
  "workspaceId": "project-my-rpg",
  "packsEnabled": [
    "rpgmaker_core_api",
    "rpgmaker_plugin_patterns",
    "rpgmaker_private_project"
  ],
  "visibilityRules": {
    "privateProjectPack": "workspace-local"
  }
}
```

### 7.2 Visibility controls

Each pack or collection must declare:

- `visibility`: private | local-team | shared | public-reference
- `exportable`: true/false
- `federatable`: true/false
- `allowedAnswerContexts`: local-only | same-project | same-pack | any

Private project content must never leak into public pack summaries, shared exports, federated memory, or answers for unrelated workspaces unless policy explicitly permits it.

### 7.3 Private-project precedence

If a query is clearly about the user’s project:

1. search private project pack first
2. fall back to public/domain packs only if needed
3. label fallback explicitly

---

## 8. Domain Pack Framework

### 8.1 Definition

A Domain Pack is a versioned, governed knowledge product with:

- explicit scope
- source set
- parse and extraction rules
- trust defaults
- eval suites
- refresh policy
- lifecycle state
- ownership and review policy
- install profiles
- workspace compatibility rules

### 8.2 Pack manifest

```json
{
  "packId": "rpgmaker-mz",
  "domain": "game-dev",
  "version": "1.0.0-draft",
  "taxonomyVersion": "1",
  "status": "draft",
  "defaultCollections": [
    "rpgmaker_core_api",
    "rpgmaker_plugin_patterns",
    "rpgmaker_tooling",
    "rpgmaker_llm_workflows",
    "rpgmaker_private_project"
  ]
}
```

### 8.3 Pack lifecycle states

- `draft`
- `building`
- `staged`
- `validated`
- `promoted`
- `deprecated`
- `retired`
- `removed`

Rules:

- only validated builds can be promoted
- deprecated packs are excluded from default retrieval
- retired packs remain inspectable but frozen
- removed packs leave tombstoned audit metadata

### 8.4 Pack channels

Supported channels:

- `draft`
- `candidate`
- `stable`
- `frozen`

Use channels to control risk and install defaults.

### 8.5 Pack install profiles

Supported profiles:

- `minimal`
- `core-only`
- `developer`
- `full`
- `private-first`

Install profile selection must control footprint, source breadth, and retrieval defaults.

### 8.6 Pack ownership and stewardship

Each pack needs accountable owners/reviewers.

Example:

```json
{
  "packId": "rpgmaker-mz",
  "owners": ["Doc"],
  "reviewers": ["pack-maintainer-1"],
  "defaultPromotionPolicy": "owner-or-reviewer-approval",
  "escalationContact": "Doc"
}
```

---

## 9. Source Registry and source governance

### 9.1 Source Registry

Every pack must maintain a source registry entry per source with:

- source ID
- repo URL
- selected ref or commit
- parse mode
- trust tier
- engine target/version metadata where relevant
- overlap score
- parser success rate
- refresh cadence
- last reviewed time
- contribution notes
- retirement/deprecation state

### 9.2 Source trust model

Trust must be per source, not per pack.

Recommended tiers:

- **High**: authoritative engine/runtime source or extremely strong primary reference
- **Medium-High**: reputable repo with clear provenance and strong extraction value
- **Medium**: useful community reference with mixed authority
- **Low**: thin, obscure, mirrored, or poorly documented source
- **Quarantined**: not available for default retrieval

### 9.3 Source family registry

Track:

- forks
- mirrors
- renamed copies
- author families
- near-duplicates
- wrapper repos

This prevents fake breadth and duplicated trust.

### 9.4 Source retirement and tombstones

A source may become:

- deprecated
- retired
- quarantined
- removed

Deprecated/retired chunks should be excluded from default retrieval but remain auditable.

### 9.5 Unsafe source quarantine

A source enters quarantine for reasons such as:

- malformed parser input
- suspicious binary content
- weak provenance
- duplication with little new value
- severe extraction failure
- boundary-policy violation

Quarantined sources are not promoted into default pack retrieval.

---

## 10. Pack build system, transactions, and release discipline

### 10.1 Pack transaction model

Every pack operation must be transactional:

1. prepare
2. build
3. validate
4. promote
5. rollback

No staged build becomes live until validation and eval pass.

### 10.2 Pack lockfile

Every promoted or candidate build must emit a deterministic `pack.lock.json`:

```json
{
  "packId": "rpgmaker-mz",
  "packVersion": "1.0.0-draft",
  "builtUtc": "2026-04-12T22:00:00Z",
  "toolkitVersion": "0.9.0",
  "taxonomyVersion": "1",
  "sources": [
    {
      "repoUrl": "https://github.com/example/repo",
      "selectedRef": "abc1234",
      "parseMode": "plugin-catalog",
      "parserVersion": "2.1.0",
      "chunkCount": 418
    }
  ]
}
```

### 10.3 Human review gates

Require human review when:

- source deltas are large
- parser versions jump major versions
- trust tiers change materially
- visibility boundaries change
- eval regressions exist with caveats
- new low-confidence extraction modes are introduced

### 10.4 Pack build outputs

A validated pack build should produce:

- lockfile
- build manifest
- artifact counts
- structured extraction counts
- eval results
- pack status summary
- rollback target metadata

---

## 11. Parser sandbox and ingestion safety

No source ingestion step may execute repository code.

Parser controls must include:

- extension allowlist
- file size caps
- source size caps
- timeout budget per source
- process isolation where needed
- crash isolation per source
- binary refusal by default
- quarantine on parser failure or suspicious content

---

## 12. Structured extraction pipeline

### 12.1 Principle

Raw semantic chunking is not enough. Domain packs must produce normalized, queryable structural artifacts.

### 12.2 Extraction stages

1. raw file ingest
2. language-aware parsing
3. header extraction
4. API/method-touch extraction
5. command/param extraction
6. notetag extraction
7. conflict-signature extraction
8. compatibility extraction
9. canonical entity assignment
10. artifact normalization

### 12.3 Required normalized artifact families

- `plugin_headers.jsonl`
- `plugin_commands.jsonl`
- `plugin_params.jsonl`
- `notetag_catalog.jsonl`
- `method_touches.jsonl`
- `conflict_signatures.jsonl`
- `compatibility_rules.jsonl`
- `tool_patterns.jsonl`

### 12.4 Artifact schema registry

Every normalized artifact type must have a versioned schema.

Example:

```json
{
  "artifactType": "plugin-command-record",
  "schemaVersion": "2.0.0",
  "requiredFields": [
    "entityId",
    "pluginName",
    "commandName",
    "sourcePath",
    "sourceRevision"
  ],
  "compatibilityNotes": [
    "v1 records may omit arg schemas"
  ]
}
```

### 12.5 Lineage and derivation tracking

Every derived artifact must record:

- parent source chunk(s)
- transform type
- transform version
- determinism: deterministic | model-assisted

This applies to summaries, normalized records, and LLM-curated artifacts.

---

## 13. Canonical Entity Registry and contradiction handling

### 13.1 Canonical Entity Registry

The system must assign canonical IDs to extracted objects.

Entity types include:

- engine class
- engine method
- plugin
- plugin command
- plugin parameter
- notetag
- tool pattern
- conflict signature
- compatibility rule

This allows entity-level diffs, dedupe, and better retrieval.

### 13.2 Contradiction / dispute sets

The system must support explicit disagreement rather than flattening conflicting claims into one fake fact.

Each dispute set should include:

- disputed entity
- competing claims
- source and trust level per claim
- status: open | resolved | local-override
- preferred claim source if adjudicated

### 13.3 Human annotations and overrides

Humans must be able to add local/project-scoped notes without rewriting source provenance.

Supported annotation types:

- correction
- deprecation
- confidence downgrade
- compatibility note
- relevance boost
- caveat
- project-local override

---

## 14. Retrieval architecture and query routing

### 14.1 Query router

Different questions need different retrieval paths. The router must select retrieval profile, pack set, and ranking logic based on task type and workspace.

### 14.2 Retrieval profiles

Required profiles include:

- `api-lookup`
- `plugin-pattern`
- `conflict-diagnosis`
- `codegen`
- `private-project-first`
- `tooling-workflow`
- `reverse-format`

### 14.3 Cross-pack arbitration

The router must arbitrate across multiple packs. Rules:

- prefer domain-specific authoritative pack over generic pack
- prefer private-project pack when query is project-local
- mark cross-pack answers clearly
- do not let generic dev/reference packs drown out domain-specific evidence

### 14.4 Retrieval cache and invalidation

Retrieval caching is allowed only if keyed by:

- query hash
- retrieval profile
- active pack versions
- project/workspace context
- taxonomy version
- engine-target filters where relevant

Invalidate cache on:

- promoted pack build change
- deprecation/tombstone changes
- private-project pack update
- extraction schema or ranking changes

---

## 15. Answer-time control model

### 15.1 Answer plan

Before synthesis, the system must generate an answer plan including:

- selected retrieval profile
- packs to search
- required evidence types
- evidence classes to avoid
- private/public boundary checks
- confidence policy

### 15.2 Answer trace

After synthesis, the system must write an answer trace showing:

- evidence used
- evidence excluded and why
- answer mode
- confidence decision
- workspace context
- pack versions
- caveats attached
- abstain/escalate decision if applicable

### 15.3 Answer evidence policy

Rules:

- foundational claims prefer core/authoritative sources
- plugin repos are examples unless marked otherwise
- translation-only evidence cannot carry high confidence
- conflict diagnosis should include multi-source structural evidence where possible
- public examples must not override project-local evidence in local workspace contexts

### 15.4 Confidence threshold and abstain policy

The system must support:

- direct answer
- answer with caveat
- answer with dispute surfaced
- abstain
- escalate to human review

A system that always answers is less trustworthy than one that knows when not to.

### 15.5 Known caveats / falsehood registry

Maintain a registry of repeated misconceptions and compatibility caveats. Answers and evals must use it to avoid recurring falsehoods.

### 15.6 Answer incident bundles

Any bad-answer investigation should be reproducible via an incident bundle containing:

- user query
- workspace context
- retrieval profile
- answer plan
- answer trace
- pack versions
- selected/excluded evidence
- confidence decision
- final answer text
- linked feedback if any

---

## 16. Compatibility matrix and pack-specific correctness controls

Every relevant pack must support structured compatibility data.

For code-heavy packs this includes:

- engine target
- min/max engine version
- tested versions
- known incompatibilities
- dependency chain rules
- plugin order assumptions
- runtime caveats

This allows answers like:

- “this pattern exists, but your version combination is risky”
- “this method alias is common, but unsafe under this engine/plugin combination”

---

## 17. Operations, resilience, and continuous running

### 17.1 Watch mode and queue discipline

Watch mode must support:

- one loop per project by default
- graceful shutdown
- shared locks
- checkpoint flush on exit
- debounce and coalescing
- bounded queues
- saturation warnings and backpressure
- no overlap between scheduled/manual/watch runs

### 17.2 Incremental indexing

Support changed-files-only indexing via git diff where possible, hash cache fallback otherwise.

### 17.3 Sync idempotency

All retrying remote writes must carry deterministic idempotency keys or ledger entries.

### 17.4 Resource budgets and circuit breakers

Required controls:

- max runtime
- max writes
- max failures before abort
- max provider cost
- max queue depth
- breaker states: closed, open, half-open

### 17.5 Palace backup, restore, and encryption

Support:

- export/import
- pre-restore backup
- compatibility validation
- encrypted archive option
- checkpointed long-running restore jobs

### 17.6 Proactive heal watch

Allowed, but conservative by default. Unsafe repairs require approval or policy allow.

---

## 18. Telemetry, SLOs, caching, and compaction

### 18.1 Pack telemetry

Track:

- build success rate
- refresh latency
- parser failure rate
- extraction coverage
- provenance coverage
- answer grounding rate
- P95 retrieval latency
- feedback category counts

### 18.2 SLOs

Every promoted pack should define operational SLOs for quality and performance.

### 18.3 Garbage collection and compaction

Support:

- remove orphaned derived artifacts
- age out failed staging builds
- compact pack indexes safely
- preserve promoted evidence
- avoid unbounded growth

---

## 19. Eval system, replay, and feedback loop

### 19.1 Eval layers

Use four layers:

1. artifact-level validation
2. retrieval-level evaluation
3. answer-level evaluation
4. golden task end-to-end evaluation

### 19.2 Golden tasks

Golden tasks must reflect real work, not just question prompts.

Examples:

- generate a minimal plugin skeleton with one command and one parameter
- diagnose whether two plugins conflict and cite touched methods
- answer how a project-local plugin patches a specific engine surface
- extract all notetags from a source repo
- compare a public pattern to a private project implementation

### 19.3 Answer baselines

Use property-based expected behavior, not only exact text.

### 19.4 Upgrade replay harness

Every parser/ranking/pack upgrade should support before/after replay against:

- golden tasks
- known bad-answer incidents
- retrieval profiles
- evidence-selection behavior

### 19.5 Feedback-to-improvement loop

Feedback categories should include:

- bad retrieval
- wrong authority level
- contradiction not surfaced
- low-confidence should have abstained
- missing source
- extraction bug
- ranking bug
- privacy boundary issue

Recurring feedback patterns must feed source policy, extraction changes, eval updates, or pack governance changes.

---

## 20. Delivery order and roadmap

### Phase 1 — Reliability and control foundation

Build the non-negotiable operational core:

- structured logging
- run manifests
- journals/checkpoints
- file locking + atomic writes
- schema versioning + migrations
- effective-config explain/validate
- live key validation
- fake provider/service harness
- Docker ContextLattice fix
- CI coverage reporting

### Phase 2 — Operator workflow and guarded execution

Make the system understandable and safe to use manually:

- interactive init
- git hooks
- health score + concise summary
- planner/executor previews
- include/exclude rules
- runtime compatibility enforcement
- notification hooks
- policy and execution-mode enforcement
- workspaces and boundary policy

### Phase 3 — Safe continuous operation

Enable long-running and background behavior safely:

- watch sync
- debounce/backpressure queue
- incremental indexing
- sync idempotency keys
- sync telemetry
- backup/restore
- encrypted snapshots
- budgets/circuit breakers
- PII/secret scanning before sync
- proactive heal watch
- resumable long-running operations

### Phase 4 — Pack framework and structured extraction

Move from generic memory to governed knowledge products:

- domain pack manifests
- source registry
- source family registry
- pack lifecycle states
- pack transactions and lockfile
- parser sandbox
- structured extraction pipeline
- artifact schema registry
- canonical entity registry
- compatibility extraction
- conflict-signature extraction

### Phase 5 — Retrieval and answer integrity

Make the system answer correctly, not just store data:

- query router
- retrieval profiles
- cross-pack arbitration
- answer plan + trace
- answer evidence policy
- contradiction/dispute sets
- confidence + abstain policy
- caveat registry
- answer incident bundles
- retrieval cache + invalidation

### Phase 6 — Human trust, replay, and governance

Make long-term operation auditable and correctable:

- human annotations and overrides
- pack ownership/stewardship
- human review gates
- golden task evals
- answer baselines
- replay harness
- feedback loop
- pack SLOs
- compaction and GC

### Phase 7 — Platform expansion

Only after the above is stable:

- MCP-native toolkit server
- MCP composite gateway
- snapshots import/export
- dashboards and graph views
- external ingestion framework at scale
- federated/team memory
- natural-language config generation

---

## 21. What not to do early

Do not prioritize these before the earlier phases are real:

- heavy dashboard work
- graph visualizations
- broad federated memory
- natural-language auto-config apply
- background agents with broad self-mutation
- plugin ecosystem growth without lifecycle controls
- many source waves without extraction governance
- semantic upgrades without artifact schema/version tracking

These are multipliers. Multipliers amplify weak foundations.

---

## 22. Canonical domain-pack example: RPG Maker MZ

This is the first official worked example pack.

### 22.1 Pack identity

```json
{
  "packId": "rpgmaker-mz",
  "domain": "game-dev",
  "version": "1.0.0-draft",
  "taxonomyVersion": "1",
  "defaultCollections": [
    "rpgmaker_core_api",
    "rpgmaker_plugin_patterns",
    "rpgmaker_tooling",
    "rpgmaker_llm_workflows",
    "rpgmaker_private_project"
  ]
}
```

### 22.2 Scope

This pack is for:

- RPG Maker MZ plugin development
- engine API lookup
- battle/UI/map/audio extension patterns
- plugin conflict diagnosis
- plugin header/parameter reasoning
- data schema understanding
- LLM-assisted tooling around MZ projects
- local/private project code understanding

This pack is not for:

- storing binaries or encrypted assets
- redistributing proprietary plugin code
- treating community conventions as engine law
- replacing project-local private pack context

### 22.3 Collections

#### `rpgmaker_core_api`
Authoritative engine/runtime surfaces.  
Default trust: **high**

#### `rpgmaker_plugin_patterns`
Community plugin patterns and examples.  
Default trust: **medium**

#### `rpgmaker_tooling`
Conflict finders, translators, decrypters, and workflow tools.  
Default trust: **medium**

#### `rpgmaker_llm_workflows`
LLM-specific project tooling and translation workflows.  
Default trust: **medium**

#### `rpgmaker_private_project`
User-authored plugins, notes, and project-specific patterns.  
Default trust: **high** for originals, lower for generated summaries.

### 22.4 Required metadata for RPG Maker artifacts

In addition to core provenance fields, include when applicable:

- `engineTarget`
- `engineMinVersion`
- `engineMaxVersion`
- `pluginName`
- `pluginCategory`
- `pluginCommands`
- `pluginParams`
- `notetags`
- `mzApiSurface`
- `pluginDependencies`
- `originalAuthor`
- `sourceLanguage`
- `normalizedLanguage`
- `translationMode`
- `trustTier`



### 22.4.1 Additional RPG Maker–specific authority metadata

In addition to trust, every RPG Maker source and extracted artifact should carry an explicit `authorityRole` so the answer layer can distinguish between “useful” and “authoritative.”

Supported values:

- `core-runtime`
- `private-project`
- `exemplar-pattern`
- `tooling-analyzer`
- `reverse-format`
- `llm-workflow`
- `multilingual-summary-source`
- `bundled-collection`

Examples:
- P0 runtime files -> `core-runtime`
- `rpgmaker_private_project` -> `private-project`
- `Hudell/cyclone-engine`, `theoallen/RMMZ`, `nz-prism/RPG-Maker-MZ` -> `exemplar-pattern`
- `moonyoulove/rpgmaker-plugin-conflict-finder` -> `tooling-analyzer`
- `uuksu/RPGMakerDecrypter` -> `reverse-format`
- `fkiliver/RPGMaker_LLM_Translator` -> `llm-workflow`
- translated summaries derived from `Sigureya/RPGmakerMZ` and `MikanHako1024/RPGMaker-plugins-public` -> `multilingual-summary-source`
- `ikmalsaid/rpgmaker-plugins` -> `bundled-collection`

This field is required because trust alone is not enough. A repo can be useful and even fairly trustworthy while still being the wrong source to establish engine-law answers.

### 22.5 Source priority order

#### P0 — Core runtime and engine surfaces
Promote these ahead of community repos:

- MZ runtime JS files
- plugin manager/loading model
- engine data/schema references
- authoritative runtime notes where legally/practically available

#### P1 — Strong workflow/tooling references
Examples:

- translation pipelines
- decrypters
- runtime/API documentation helpers

#### P2 — High-value community plugin corpora
Use reputable, broad, well-structured plugin sources that add real extraction value.

#### P3 — Specialized/niche extensions
Use narrowly targeted sources for conflicts, input, CTB, title customization, spatial audio, and similar focused patterns.

#### P4 — Private project ingestion
The user’s own plugins, notes, and helper scripts. These are often the most valuable source during actual development.

### 22.6 Required extraction outputs for RPG Maker MZ

Mandatory outputs:

- plugin header extraction
- plugin parameter schemas
- plugin command extraction
- notetag extraction
- method-touch extraction
- conflict-signature extraction
- compatibility extraction
- engine-version applicability
- alias vs overwrite classification
- dependency relation extraction



### 22.6.1 Mandatory RPG Maker MZ header grammar extraction

Header extraction for MZ plugins must be specific, not generic. At minimum, the extraction layer must parse and normalize:

- `@target`
- `@base`
- `@orderAfter`
- `@orderBefore`
- `@plugindesc`
- `@author`
- `@help`
- `@command`
- `@arg`
- `@param`
- `@type`
- `@default`
- `@text`
- `@desc`

These fields matter directly for:
- plugin compatibility and install order reasoning
- code generation and plugin skeleton generation
- parameter UI/help reconstruction
- dependency and load-order analysis
- conflict diagnosis where plugin order hints are embedded in headers

### 22.6.2 TypeScript and declaration-file handling

The RPG Maker MZ pack must explicitly support TypeScript-heavy sources and `.d.ts` declaration files.

Rules:
- `.d.ts` files are parsed as API schema/reference artifacts
- TypeScript source should preserve symbol/type relationships
- Type relationships should be stored as structured artifacts where possible
- TS-to-JS compiled similarity must not create duplicate extraction records
- declaration files can strengthen signature authority, but do not by themselves establish runtime behavior

This matters especially for:
- `biud436/MZ` because of `lunalite-pixi-mz.d.ts`
- `Sodium-Aluminate/rpgmakerUserPlugins` because of TS-heavy source structure

### 22.7 Retrieval rules for RPG Maker pack

For foundational engine questions:
- prefer `rpgmaker_core_api`

For code examples and plugin idioms:
- prefer `rpgmaker_plugin_patterns`

For project-specific behavior:
- prefer `rpgmaker_private_project`

For workflow/tooling questions:
- prefer `rpgmaker_tooling` or `rpgmaker_llm_workflows`

For conflict diagnosis:
- require structural evidence from touched methods and plugin headers when possible



### 22.7.1 Repo-specific retrieval routing rules

The query router for the RPG Maker MZ pack must be repo-aware, not just collection-aware.

#### Conflict diagnosis
Preferred evidence order:
1. `rpgmaker_private_project`
2. `moonyoulove/rpgmaker-plugin-conflict-finder`
3. P0 runtime files
4. the exact plugin repos named in the question

#### Battle system and action-sequence questions
Preferred evidence order:
1. `rpgmaker_private_project`
2. `theoallen/RMMZ`
3. `MihailJP/mihamzplugin`
4. `PavlosDefoort/RPGMakerPluginSuite`
5. `Drakkonis-MZ/RPGMaker-MZ-plugins`
6. P0 runtime files

#### Movement / map / event-flow questions
Preferred evidence order:
1. `rpgmaker_private_project`
2. `Hudell/cyclone-engine`
3. `comuns-rpgmaker/GabeMZ`
4. `amateurgamedev/RegionReveal`
5. `BenMakesGames/RPG-Maker-MZ-Plugins`
6. P0 runtime files

#### Input / keyboard / control-remapping questions
Preferred evidence order:
1. `rpgmaker_private_project`
2. `davidmcasas/RPGMakerMZ-CustomKeyboardMapping`
3. `biud436/MZ`
4. P0 runtime files

#### Tooling / decryption / translation / workflow questions
Preferred evidence order:
1. `uuksu/RPGMakerDecrypter`
2. `fkiliver/RPGMaker_LLM_Translator`
3. `Justype/RPGMakerUtils`
4. `moonyoulove/rpgmaker-plugin-conflict-finder`

#### Fog / weather / layer / overlay questions
Preferred evidence order:
1. `rpgmaker_private_project`
2. `comuns-rpgmaker/GabeMZ`
3. `Hudell/cyclone-engine`
4. other map-visual repos only if directly relevant

These routing rules exist to make the concrete repo set operational rather than decorative.

### 22.8 RPG Maker eval suites

#### API lookup suite
Examples:
- standard plugin command registration pattern
- common `Window_Message` hooks
- `Scene_Battle` customization surfaces

#### Code generation suite
Examples:
- minimal plugin skeleton
- one plugin command example
- one notetag parser example
- title logo replacement skeleton

#### Conflict analysis suite
Examples:
- detect overlapping method patches
- distinguish alias-chain vs overwrite risk
- identify plugin-order sensitivity

#### Domain correctness negative suite
The system must not:

- invent nonexistent APIs
- treat plugin conventions as core engine requirements
- ignore engine-version boundaries
- confuse MV and MZ without warning

#### Retrieval provenance suite
The system must:

- cite source repo/path
- distinguish original vs translated summary
- prefer higher-trust/core sources for foundational claims



### 22.8.1 Repo-specific evaluation tasks

In addition to the general eval suites above, the RPG Maker pack must ship with repo-specific tasks that prove the named sources are being used correctly.

Examples:

- “Does `Cyclone-Movement` conflict with a plugin that also aliases `Game_CharacterBase.updateMove`?”
- “How does `theoallen/RMMZ` TBSE change the answer for custom battle action sequencing?”
- “How should `davidmcasas/RPGMakerMZ-CustomKeyboardMapping` affect input-layer answers versus generic `Input` examples?”
- “When a query is about fog or weather overlays, do `comuns-rpgmaker/GabeMZ` and `Cyclone-AdvancedMaps` rank above unrelated map plugins?”
- “Can the system explain why `moonyoulove/rpgmaker-plugin-conflict-finder` is evidence for collision diagnosis but not for engine API authority?”
- “If the user asks how their own plugin patches `Scene_Battle`, does `rpgmaker_private_project` outrank `theoallen/RMMZ`, `PavlosDefoort/RPGMakerPluginSuite`, and `MihailJP/mihamzplugin`?”
- “Does a JP or ZH source from `Sigureya/RPGmakerMZ` or `MikanHako1024/RPGMaker-plugins-public` keep original-source precedence over the English summary?”

These tasks should be tracked as stable golden tasks, not ad hoc spot checks.

### 22.9 Install profiles for RPG Maker pack

- `core-only`: engine/runtime surfaces only
- `minimal`: core + a few high-value tool/plugin sources
- `developer`: balanced public pack
- `full`: all promoted public waves
- `private-first`: minimal public + strong local project emphasis



#### `core-only`
Exact membership:
- `js/rmmz_core.js`
- `js/rmmz_managers.js`
- `js/rmmz_objects.js`
- `js/rmmz_scenes.js`
- `js/rmmz_sprites.js`
- `js/rmmz_windows.js`
- `js/plugins.js`

#### `minimal`
Exact membership:
- all `core-only` members
- `nz-prism/RPG-Maker-MZ`
- `comuns-rpgmaker/GabeMZ`
- `moonyoulove/rpgmaker-plugin-conflict-finder`
- `davidmcasas/RPGMakerMZ-CustomKeyboardMapping`

#### `developer`
Exact membership:
- all `minimal` members
- `Hudell/cyclone-engine`
- `theoallen/RMMZ`
- `biud436/MZ`
- `MihailJP/mihamzplugin`
- `BenMakesGames/RPG-Maker-MZ-Plugins`
- `LyraVultur/RPGMakerPlugins`
- `Drakkonis-MZ/RPGMaker-MZ-plugins`
- `uuksu/RPGMakerDecrypter`
- `Justype/RPGMakerUtils`

#### `full`
Exact membership:
- all promoted public sources in `22.11`

#### `private-first`
Exact membership:
- all `core-only` members
- `rpgmaker_private_project`
- fallback public set:
  - `nz-prism/RPG-Maker-MZ`
  - `comuns-rpgmaker/GabeMZ`
  - `moonyoulove/rpgmaker-plugin-conflict-finder`

The point of `private-first` is not breadth. It is to keep project-local truth ahead of public example repos.

### 22.10 Private-project policy for RPG Maker pack

Rules:

- separate collection or namespace
- strict secret scanning
- no sharing/federation by default
- highest retrieval priority in matching project context
- encrypted backups preferred
- public fallback must be labeled as fallback

### 22.11 Evaluated source registry

The following repositories were evaluated across four waves and accepted for ingestion into the RPG Maker MZ pack. This registry is the concrete source set that the priority tiers (22.5) draw from. The named repos below are not decorative; routing, extraction, authority, refresh, and eval behavior should be tied back to them explicitly.

#### P0 — Core runtime (pending ingestion)

| Source | Notes |
|--------|-------|
| `js/rmmz_core.js` | Engine core: graphics, input, audio, utility |
| `js/rmmz_managers.js` | DataManager, AudioManager, SceneManager, PluginManager |
| `js/rmmz_objects.js` | Game_* objects: actors, map, party, system |
| `js/rmmz_scenes.js` | Scene_* lifecycle: title, map, battle, menu |
| `js/rmmz_sprites.js` | Sprite_* rendering: characters, battlers, animations |
| `js/rmmz_windows.js` | Window_* UI: menus, messages, selectable lists |
| `js/plugins.js` | Plugin loader format, parameter resolution |

#### P1 — Workflow / tooling

| Source | Trust | License | Notes |
|--------|-------|---------|-------|
| `fkiliver/RPGMaker_LLM_Translator` | Medium-High | — | LLM-driven game text translation pipeline |
| `uuksu/RPGMakerDecrypter` | Medium | MIT | .rgss archive decryption (C#) |
| `Justype/RPGMakerUtils` | Medium | MIT | Project file utilities and helpers |
| `moonyoulove/rpgmaker-plugin-conflict-finder` | Medium | MIT | Plugin conflict detection tool |

#### P2 — High-value community plugin corpora

| Source | Trust | Stars | License | Key value |
|--------|-------|-------|---------|-----------|
| `nz-prism/RPG-Maker-MZ` | Medium-High | 30+ | MIT | 20+ polished plugins: map, menu, battle, options |
| `comuns-rpgmaker/GabeMZ` | Medium-High | 20+ | MIT | Fog, weather, CTB, map layers, MV→MZ patterns |
| `Sigureya/RPGmakerMZ` | Medium | 15+ | MIT | Japanese-language plugins; multilingual policy target |
| `MikanHako1024/RPGMaker-plugins-public` | Medium | 10+ | MIT | Chinese-language plugins; multilingual policy target |
| `LyraVultur/RPGMakerPlugins` | Medium | — | MIT | Map, battle, and UI extensions |
| `erri120/RPGMakerPlugins` | Medium | — | GPL-3.0 | Engine patches and quality-of-life fixes |
| `Drakkonis-MZ/RPGMaker-MZ-plugins` | Medium | — | MIT | Core-dependent plugin suite (Drak_Core base) |
| `Hudell/cyclone-engine` | Medium-High | 32 | Apache-2.0 | Pixel movement, advanced maps, time system, in-game map editor, async events, Steam integration |
| `theoallen/RMMZ` | Medium-High | 27 | Free/MIT | Battle Sequence Engine (TBSE), extensive plugin collection |
| `biud436/MZ` | Medium | 17 | MIT | 20+ plugins: HUD, face animation, event creation, lighting, wave filters, TypeScript defs, non-Latin input |
| `BenMakesGames/RPG-Maker-MZ-Plugins` | Medium | 0 | Free | 13 plugins: ScreenByScreen transitions, DanceInputs, pushable events, custom criticals |
| `ikmalsaid/rpgmaker-plugins` | Medium | — | — | Curated author collection |
| `GamesOfShadows/rpgmaker_mv-mz_plugins` | Medium | — | — | UI and audio utilities |

#### P3 — Specialized / niche

| Source | Trust | Stars | License | Key value |
|--------|-------|-------|---------|-----------|
| `PhobiaGH/RPGMZ_Proximity_MultiSound` | Medium | — | — | Spatial/proximity audio system |
| `cellicom/rpgmaker-plugins` | Medium | — | — | D&D mechanics (dice, stats, random encounters) |
| `davidmcasas/RPGMakerMZ-CustomKeyboardMapping` | Medium | — | MIT | Full keyboard input override |
| `amateurgamedev/RegionReveal` | Medium | — | — | Region-based map reveal mechanic |
| `PavlosDefoort/RPGMakerPluginSuite` | Medium | — | MIT | Battle portrait hooks, HP-based visual feedback |
| `jomarcenter-mjm/RPGMakerMZ-PublicPlugins` | Medium | — | — | Title screen logo/customization |
| `Sodium-Aluminate/rpgmakerUserPlugins` | Medium | — | — | User plugin utilities |
| `alderpaw/rmmz_custom_plugins` | Medium | — | — | Custom plugin collection |
| `SumRndmDde/MZPlugins` | Medium | 6 | — | MapMixer, event trigger extensions (well-known MV-era author) |
| `MihailJP/mihamzplugin` | Medium | 8 | Unlicense | 16 plugins: TPB mods, cut-ins, ZombieActor, battle speech |

#### Skipped / duplicate sources

| Source | Reason |
|--------|--------|
| `Viodow/rpgmaker_mv-mz_plugins` | Fork/duplicate of `GamesOfShadows` |

#### Key API surfaces across registered sources

The following engine surfaces are touched by multiple registered sources and represent high-value extraction targets:

- `Scene_Battle` / `BattleManager` / `Game_Action` — battle system extensions
- `Scene_Map` / `Game_Map` / `Game_Event` — map and event systems
- `Scene_Title` — title screen customization
- `Game_CharacterBase` / `Game_Player` — movement and character control
- `Window_Message` / `Window_Base` — UI/messaging hooks
- `Sprite_Character` / `Sprite_Battler` — visual rendering
- `Input` — keyboard/gamepad override
- `ImageManager` / `AudioManager` — asset loading
- `PluginManager` — plugin command registration
- PIXI filters — visual effects layer

---



### 22.12 Repo-by-repo extraction target matrix

This matrix defines what each named source is there to teach the system. It is one of the most important practical sections in the pack spec.

| Repo / Source | Primary value | Must-extract | Authority role | Risk notes |
|---|---|---|---|---|
| `js/rmmz_core.js` / `js/rmmz_managers.js` / `js/rmmz_objects.js` / `js/rmmz_scenes.js` / `js/rmmz_sprites.js` / `js/rmmz_windows.js` / `js/plugins.js` | Core runtime truth | classes, methods, inheritance, manager interactions, plugin loading semantics | `core-runtime` | must outrank public examples on foundational questions |
| `Hudell/cyclone-engine` | movement/map systems | `Game_Map`, `Game_CharacterBase`, `Scene_Map`, collision hooks, event creation patterns | `exemplar-pattern` | can dominate movement/map retrieval if weights are careless |
| `theoallen/RMMZ` | battle framework architecture | `Scene_Battle`, `BattleManager`, action-sequence patterns, battler hooks | `exemplar-pattern` | powerful but not engine law |
| `biud436/MZ` | broad UI/effects/input patterns | PIXI filters, title systems, TS defs, input/dialog hooks | `exemplar-pattern` | breadth can inflate relevance if unbounded |
| `nz-prism/RPG-Maker-MZ` | polished plugin patterns | headers, params, commands, scene/window patches | `exemplar-pattern` | pattern source, not authority |
| `comuns-rpgmaker/GabeMZ` | fog/weather/map layers/CTB | map render hooks, overlays, weather, battle/map features | `exemplar-pattern` | likely overlap with other visual/map repos |
| `moonyoulove/rpgmaker-plugin-conflict-finder` | conflict tooling | override chains, alias detection, touched prototypes | `tooling-analyzer` | do not use as runtime-behavior authority |
| `davidmcasas/RPGMakerMZ-CustomKeyboardMapping` | input layer | `Input`, mapping UI, persistence rules | `exemplar-pattern` | should dominate only input/control queries |
| `BenMakesGames/RPG-Maker-MZ-Plugins` | mechanic-specific patterns | input sequences, map transitions, notetags, event mechanics | `exemplar-pattern` | do not promote to engine authority |
| `PhobiaGH/RPGMZ_Proximity_MultiSound` | spatial audio | event notetags, BGS distance logic, audio parameter patterns | `exemplar-pattern` | should mostly stay in audio-oriented routing |
| `MihailJP/mihamzplugin` | TPB/cut-ins/battle UX | battle hooks, cast time, enemy analysis, cut-ins | `exemplar-pattern` | likely version-sensitive |
| `Drakkonis-MZ/RPGMaker-MZ-plugins` | dependency-based suite | `Drak_Core` dependency graph, TP systems, suite-level assumptions | `exemplar-pattern` | requires dependency extraction to be useful |
| `Sigureya/RPGmakerMZ` | multilingual plugin corpus | headers, commands, params, original JP text | `exemplar-pattern` + `multilingual-summary-source` | translated summaries must not outrank source |
| `MikanHako1024/RPGMaker-plugins-public` | multilingual plugin corpus | headers, commands, params, original ZH text | `exemplar-pattern` + `multilingual-summary-source` | same translation risk as above |
| `uuksu/RPGMakerDecrypter` | reverse/decryption tooling | file-format knowledge, decryption flow, archive semantics | `reverse-format` | keep out of normal plugin codegen answers |
| `fkiliver/RPGMaker_LLM_Translator` | LLM workflow | data JSON flow, translation pipeline, batching/error handling | `llm-workflow` | not engine/plugin authority |
| `Justype/RPGMakerUtils` | project utilities | file structure utilities, helper workflows | `tooling-analyzer` | useful for workflow answers, not runtime authority |
| `ikmalsaid/rpgmaker-plugins` | bundled collection | original author provenance, plugin grouping | `bundled-collection` | wrapper repo; authority must be downgraded unless original author traced |

### 22.13 Dependency and core-plugin map

The RPG Maker MZ pack must explicitly model repo-level and plugin-level dependency facts.

Known high-value dependency examples:
- `Drakkonis-MZ/RPGMaker-MZ-plugins` -> `Drak_Core` is foundational and should be extracted as a dependency root
- `MihailJP/mihamzplugin` -> selected plugins depend on `PluginCommonBase` and `ExtraWindow`
- `Hudell/cyclone-engine` -> shared architecture across Cyclone plugins should be modeled as a suite, not isolated one-offs
- `theoallen/RMMZ` -> TBSE-specific battle assumptions must be surfaced before codegen or compatibility advice
- `ikmalsaid/rpgmaker-plugins` -> bundled third-party author provenance should be extracted per plugin where possible

A retrieval answer should not recommend a plugin pattern while omitting its actual prerequisite core plugin or order dependency.

### 22.14 Repo-specific authority constraints

The following constraints are mandatory:

- do not use `GamesOfShadows/rpgmaker_mv-mz_plugins` to establish engine law
- do not use `BenMakesGames/RPG-Maker-MZ-Plugins` to define canonical engine behavior
- do not use `moonyoulove/rpgmaker-plugin-conflict-finder` as runtime-behavior authority
- do not let translated summaries from `Sigureya/RPGmakerMZ` or `MikanHako1024/RPGMaker-plugins-public` outrank original source code
- do not let `uuksu/RPGMakerDecrypter` bleed into normal plugin-pattern/codegen answers unless the query profile is reverse/decryption/tooling
- do not let `ikmalsaid/rpgmaker-plugins` outrank an original-author source when the same plugin lineage can be traced more directly elsewhere

These rules are what keep the named repos useful without letting them distort authority.

### 22.15 Multilingual precedence rules by named repo

Repo-specific multilingual handling rules:

- `Sigureya/RPGmakerMZ` -> original Japanese source is primary; English summary is helper only
- `MikanHako1024/RPGMaker-plugins-public` -> original Chinese source is primary; English summary is helper only
- `biud436/MZ` -> Korean-language documentation may be summarized, but `.d.ts` files and code artifacts should be parsed structurally rather than summarized as prose
- any translated summary derived from source code must be labeled as generated assistance, not primary authority

### 22.16 Refresh cadence and review policy by repo class

Use repo-aware refresh policy rather than one generic cadence:

- P0 runtime files -> refresh only when target RPG Maker MZ engine version changes
- `Hudell/cyclone-engine`, `theoallen/RMMZ`, `biud436/MZ` -> 30-day review cadence
- `nz-prism/RPG-Maker-MZ`, `comuns-rpgmaker/GabeMZ`, `MihailJP/mihamzplugin` -> 45–60 day cadence
- niche repos such as `RegionReveal`, `PavlosDefoort/RPGMakerPluginSuite`, `jomarcenter-mjm/RPGMakerMZ-PublicPlugins` -> manual / promote-on-change cadence
- `ikmalsaid/rpgmaker-plugins` -> higher scrutiny because it is a bundled collection and not a single original-author stream

### 22.17 Repo health and risk notes

Each named repo in the source registry should carry concise operational risk notes such as:

- multilingual source
- bundled collection
- unclear license
- depends on core plugin
- high overlap risk
- likely version-sensitive
- tooling-only
- reverse-format only
- example-only, not authority

These notes should influence review and promotion decisions.

### 22.18 Bundled-collection policy

Some repos, especially `ikmalsaid/rpgmaker-plugins`, are wrapper collections rather than original-author sources.

Rules:
- extract `originalAuthor` per plugin wherever possible
- bundled collections cannot inherit full authority from the wrapper repo itself
- if a plugin inside a bundled collection is later ingested from an original-author source, prefer the original-author source
- bundled collection entries should receive provenance downgrade if original-author tracing is missing

This prevents convenience bundles from distorting the pack’s authority model.

## 23. Suggested acceptance test matrix

### Scenario 1 — Fresh setup
- init run
- config preview shown
- effective config valid
- doctor healthy
- first dry-run sync succeeds

### Scenario 2 — Concurrent operations
- watch sync running
- manual sync invoked
- heal watch invoked
- no state corruption
- denied operations blocked by policy

### Scenario 3 — Interrupted execution
- kill process mid-write
- rerun with `--resume`
- journal resumes safely
- state remains readable

### Scenario 4 — Invalid provider
- bad key
- correct classification
- optional rotation prompt

### Scenario 5 — Secret-bearing content
- secret detected
- report-only, redact, strict modes behave correctly
- backups/manifests remain masked

### Scenario 6 — Runtime drift
- package outside lock range
- compatibility check warns
- health score degrades appropriately

### Scenario 7 — Backup and restore
- export palace
- encrypt archive
- wipe local target
- import backup
- counts and metadata preserved

### Scenario 8 — Pack refresh rollback
- build candidate
- fail validation or eval
- system reverts to prior promoted build
- no stale candidate becomes live

### Scenario 9 — High file churn
- branch checkout + generated file churn
- queue debounces/coalesces
- watch mode remains stable

### Scenario 10 — Re-embedding migration
- chunker/model version changes
- dry-run estimates work
- resumed batch completes
- cutover preserves searchability

### Scenario 11 — Delete propagation
- source removed or scrub requested
- tombstone created
- remote delete attempted/surfaced
- deleted item does not resurrect

### Scenario 12 — Query routing and answer evidence
- foundational question prefers core source
- project-local question prefers private pack
- conflict question includes multi-source structural evidence
- translation-only evidence lowers confidence

### Scenario 13 — Abstain/escalate behavior
- weak evidence
- contradictory evidence
- low-confidence codegen
- system abstains or escalates per policy

### Scenario 14 — Human annotation and replay
- local override added
- answer changes appropriately in local workspace
- replay harness shows evidence-path change

---



### Scenario 15 — Repo-specific routing and authority enforcement
- fog/weather query ranks `comuns-rpgmaker/GabeMZ` and `Hudell/cyclone-engine` ahead of unrelated map repos
- input query ranks `davidmcasas/RPGMakerMZ-CustomKeyboardMapping` ahead of generic `Input` examples
- conflict query uses `moonyoulove/rpgmaker-plugin-conflict-finder` for diagnosis but not for engine authority
- translated JP/ZH summaries from `Sigureya/RPGmakerMZ` and `MikanHako1024/RPGMaker-plugins-public` do not outrank original source code
- bundled-collection content from `ikmalsaid/rpgmaker-plugins` is downgraded when original-author provenance is missing

## 24. Final priority call

The highest-leverage work, in order:

1. journaling + checkpoints
2. file locking + atomic writes
3. effective-config explain/validate
4. policy and execution-mode enforcement
5. workspaces and visibility boundaries
6. pack manifest + source registry + lifecycle
7. pack transaction model + lockfile
8. structured extraction pipeline
9. canonical entity registry
10. query router + retrieval profiles
11. answer plan + trace
12. confidence + abstain policy
13. human annotations + replay
14. golden-task evals and feedback loop

The biggest risk is no longer lack of features.  
It is **losing control of state, evidence, pack promotion, and private/public boundaries as the system grows**.

This document is the canonical architecture intended to stop that from happening.
