# LLM Workflow — Canonical Architecture, Pack Framework, and Delivery Plan

## Status

**This is the canonical source-of-truth document.**  
It supersedes the earlier implementation plans, review passes, and RPG Maker pack review notes. Earlier documents should be treated as archived design history after this one is adopted.

## Related Docs
- [Canonical Document Index](./LLMWorkflow_Canonical_Document_Set_INDEX.md)
- [Post-0.9.6 Strategic Execution Plan](../implementation/LLMWorkflow_Post_0.9.6_Strategic_Execution_Plan.md)
- [Implementation Progress](../implementation/PROGRESS.md)
- [Remaining Work](../implementation/REMAINING_WORK.md)

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

Example SLO template:

```json
{
  "packId": "rpgmaker-mz",
  "slos": {
    "p95RetrievalLatencyMs": 1200,
    "answerGroundingRate": 0.95,
    "parserFailureRate": 0.02,
    "provenanceCoverage": 0.99,
    "goldenTaskPassRate": 0.90
  }
}
```

At minimum, every promoted pack should publish targets for:
- P95 retrieval latency
- answer grounding rate
- parser failure rate
- provenance coverage
- golden-task pass rate

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

### Phase 1 — Reliability and control foundation ✅ COMPLETE

Build the non-negotiable operational core:

- ✅ structured logging (`Write-StructuredLog`)
- ✅ run manifests (`New-RunManifest`)
- ✅ journals/checkpoints (`New-JournalEntry`, `Get-JournalState`)
- ✅ file locking + atomic writes (`Lock-File`, `Write-AtomicFile`)
- ✅ schema versioning + migrations (`Test-StateVersion`, `Migrate-StateFile`)
- ✅ effective-config explain/validate (`Get-EffectiveConfig`, `llmconfig`)
- ✅ live key validation (`Test-ProviderKey`)
- ✅ policy and execution-mode enforcement (`Test-PolicyPermission`)
- ✅ workspaces and boundary policy (`Get-CurrentWorkspace`, `Test-VisibilityRule`)
- 📝 CI coverage reporting (in progress)

**Implementation:** See `module/LLMWorkflow/core/` (16 files, 100+ functions)

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
