# LLM Workflow — Canonical Document Set — Part 4: Future Pack Intake and Source Candidates

> **Document Status:** All candidate packs documented in this Part 4 have been **IMPLEMENTED** and promoted to active packs. See [Section 29.13 Implemented Packs Reference](#2913-implemented-packs-reference) for quick links.

## Implementation Status Summary

The following 7 candidate packs from Part 4 have been promoted to active implementation:

| Pack | Section | Original Status | Current Status | Manifest | Parsers |
|------|---------|-----------------|----------------|----------|---------|
| API Reverse Tooling Pack | 29.2 | Adopt now | ✅ IMPLEMENTED | `packs/manifests/api-reverse-tooling.json` | TrafficCaptureParser.ps1, OpenAPIExtractor.ps1 |
| Notebook/Data Workflow Pack | 29.3 | Adopt now | ✅ IMPLEMENTED | `packs/manifests/notebook-data-workflow.json` | NotebookParser.ps1, DataFramePatternExtractor.ps1 |
| Agent Simulation Pack | 29.4 | Conditional | ✅ IMPLEMENTED | `packs/manifests/agent-simulation.json` | AgentPatternExtractor.ps1, VectorStoreExtractor.ps1 |
| Voice/Audio Generation Pack | 29.5 | Conditional | ✅ IMPLEMENTED | `packs/manifests/voice-audio-generation.json` | VoiceModelExtractor.ps1, AudioProcessingExtractor.ps1 |
| Engine Reference Pack | 29.6 | Conditional | ✅ IMPLEMENTED | `packs/manifests/engine-reference.json` | EngineArchitectureExtractor.ps1, ScriptRuntimeExtractor.ps1 |
| UI/Frontend Framework Pack | 29.7 | Conditional | ✅ IMPLEMENTED | `packs/manifests/ui-frontend-framework.json` | ComponentLibraryExtractor.ps1, DesignSystemExtractor.ps1 |
| ML/Educational Reference Pack | 29.12 | Conditional | ✅ IMPLEMENTED | `packs/manifests/ml-educational-reference.json` | EducationalContentExtractor.ps1, MLConceptExtractor.ps1 |

---

## 29. Future pack intake and source candidate registry

This section records repo intake decisions for sources that may become part of the toolkit later, but do not belong inside the currently active worked-example packs (`rpgmaker-mz`, `godot-engine`, `blender-engine`).

The goal is to preserve the repo names, the evaluation decision, and the reason for that decision.

This prevents two bad outcomes:
- losing useful repo names because they were only discussed in chat
- polluting active pack specs with domains that are still only candidates

---

## 29.1 Intake categories

### Adopt now
Strong enough to enter the future-pack intake registry immediately.

### Conditional
Useful, but only if that domain becomes an explicit target of the toolkit.

### Hold / Skip
Not worth adding now because the repo is too educational, too stale, too generic, too tangential, or the wrong layer for this platform.

---

## 29.2 ✅ Reverse / API tooling candidate pack (IMPLEMENTED)

### Candidate purpose
This pack would cover:
- reverse-engineering of HTTP/REST APIs
- traffic capture to structured spec conversion
- protocol-to-schema workflows
- API discovery tooling
- reverse-format extraction

### Adopt now

#### `alufers/mitmproxy2swagger`
- **Status:** ✅ IMPLEMENTED (was: Adopt now)
- **Implementation:** `packs/manifests/api-reverse-tooling.json`
- **Parsers:** `TrafficCaptureParser.ps1`, `OpenAPIExtractor.ps1`
- **Authority role:** `reverse-format` + `tooling-analyzer`
- **Why it belongs:** directly useful for turning captured traffic into structured API knowledge; aligns with reverse-engineering, extraction, and spec-generation workflows
- **Must-extract:**
  - capture-to-OpenAPI workflow
  - path template inference
  - request/response schema generation
  - HAR input support
  - two-pass generation/edit/regeneration pattern
  - safe schema extension/merge behavior
- **Do not use as:** general web-dev authority or runtime API truth source
- **Recommended future collection:** `api_reverse_tooling`

### Future rules for this pack
- keep reverse/API tooling separate from normal app-dev pattern packs
- treat generated OpenAPI artifacts as derived records with provenance back to the capture source
- require strong secrecy policy because traffic captures can contain tokens, cookies, and PII

---

## 29.3 ✅ Notebook / data-workflow candidate pack (IMPLEMENTED)

### Candidate purpose
This pack would cover:
- notebook productivity
- spreadsheet-like data manipulation in notebooks
- AI-assisted notebook workflows
- analyst-oriented local/private project augmentation

### Adopt now

#### `mito-ds/mito`
- **Status:** ✅ IMPLEMENTED (was: Adopt now)
- **Implementation:** `packs/manifests/notebook-data-workflow.json`
- **Parsers:** `NotebookParser.ps1`, `DataFramePatternExtractor.ps1`
- **Authority role:** `notebook-tooling`
- **Why it belongs:** useful for a future notebook/data-workflow pack; fits analyst-facing workflows, dataframe manipulation, and AI-assisted notebook operations
- **Must-extract:**
  - notebook extension capabilities
  - spreadsheet-style dataframe editing concepts
  - context-aware AI chat/autocomplete workflow patterns
  - notebook-to-code assist patterns
- **Do not use as:** general Python/data-science theory authority
- **Recommended future collection:** `notebook_data_workflows`

### Future rules for this pack
- keep notebook tool answers separate from foundational pandas/numpy/statistics authority
- private notebook/project data must remain workspace-scoped and heavily protected

---

## 29.4 ✅ Agent simulation / LLM app pattern candidate pack (IMPLEMENTED)

### Conditional candidates

#### `a16z-infra/ai-town`
- **Status:** ✅ IMPLEMENTED (was: Conditional)
- **Implementation:** `packs/manifests/agent-simulation.json`
- **Parsers:** `AgentPatternExtractor.ps1`, `VectorStoreExtractor.ps1`
- **Authority role:** `agent-simulation`
- **Why it may belong:** useful if the toolkit grows a pack around LLM-app patterns, agent simulation, or social-agent orchestration
- **Must-extract if adopted:**
  - multi-agent world/state model
  - backend/vector-search integration patterns
  - deployable starter-kit structure
  - environment/config patterning
- **Do not use as:** general agent-theory authority or core platform architecture authority
- **Recommended future collection:** `agent_app_patterns`

### Conditional adoption rule
Only promote if the toolkit explicitly adds an agent-simulation or LLM-app-product pack.

---

## 29.5 ✅ Voice / speech / audio-generation candidate pack (IMPLEMENTED)

### Conditional candidates

#### `myshell-ai/OpenVoice`
- **Status:** ✅ IMPLEMENTED (was: Conditional)
- **Implementation:** `packs/manifests/voice-audio-generation.json`
- **Parsers:** `VoiceModelExtractor.ps1`, `AudioProcessingExtractor.ps1`
- **Authority role:** `voice-generation`
- **Why it may belong:** useful if the toolkit adds a voice/audio pack for speech generation, cloning, or media workflows
- **Must-extract if adopted:**
  - voice-cloning pipeline structure
  - model/runtime requirements
  - inference workflow
  - speaker/style conditioning concepts
- **Do not use as:** generic audio-engineering authority
- **Recommended future collection:** `voice_audio_generation`

### Conditional adoption rule
Only promote if voice/media generation becomes an explicit toolkit domain.

---

## 29.6 ✅ Engine-reference candidate pack (IMPLEMENTED)

### Conditional candidates

#### `GarageGames/Torque3D`
- **Status:** ✅ IMPLEMENTED (was: Conditional)
- **Implementation:** `packs/manifests/engine-reference.json`
- **Parsers:** `EngineArchitectureExtractor.ps1`, `ScriptRuntimeExtractor.ps1`
- **Authority role:** `engine-reference`
- **Why it may belong:** could justify a future engine pack, but it is not currently as strategically important as RPG Maker, Godot, or Blender
- **Must-extract if adopted:**
  - engine architecture patterns
  - scripting/runtime hooks
  - scene/world management concepts
  - export/build pipeline facts where available
- **Do not use as:** comparative authority for Godot or RPG Maker unless the query is explicitly cross-engine
- **Recommended future collection:** `torque3d_engine`

### Conditional adoption rule
Promote only if the toolkit deliberately expands to additional game engines beyond the current set.

---

## 29.7 ✅ UI / front-end reference candidate pack (IMPLEMENTED)

### Conditional candidates

#### `MithrilJS/mithril.js`
- **Status:** ✅ IMPLEMENTED (was: Conditional)
- **Implementation:** `packs/manifests/ui-frontend-framework.json`
- **Parsers:** `ComponentLibraryExtractor.ps1`, `DesignSystemExtractor.ps1`
- **Authority role:** `frontend-framework`
- **Why it may belong:** useful only if the toolkit starts supporting front-end framework reference packs or dashboard/UI implementation packs
- **Must-extract if adopted:**
  - component model
  - routing/state patterns
  - API surface for view construction
- **Do not use as:** default UI authority across the toolkit unless a front-end pack is actually promoted

#### `mdbootstrap/TW-Elements`
- **Status:** ✅ IMPLEMENTED (was: Conditional)
- **Part of:** `packs/manifests/ui-frontend-framework.json`
- **Authority role:** `ui-component-library`
- **Why it may belong:** useful for dashboard/admin/component generation patterns, not for the core platform itself
- **Must-extract if adopted:**
  - component catalog
  - Tailwind integration patterns
  - JS behavior hooks
- **Do not use as:** design-system authority outside a dedicated UI/components pack

#### `nolly-studio/cult-ui`
- **Status:** ✅ IMPLEMENTED (was: Conditional)
- **Part of:** `packs/manifests/ui-frontend-framework.json`
- **Authority role:** `ui-component-library`
- **Why it may belong:** useful for design-system/component inspiration if the toolkit later adds a UI pack
- **Must-extract if adopted:**
  - component patterns
  - style-system conventions
  - reusable UI primitives
- **Do not use as:** generic front-end authority unless a UI pack exists

### Conditional adoption rule
Only promote these if the toolkit explicitly creates a front-end/UI reference pack.

---

## 29.8 Image / creative-generation candidate pack

### Conditional candidates

#### `Anil-matcha/Open-Higgsfield-AI`
- **Status:** Conditional
- **Authority role:** `creative-generation`
- **Why it may belong:** useful only if the toolkit adds a self-hosted image/video/media generation pack
- **Must-extract if adopted:**
  - model/runtime workflow
  - setup/inference pipeline
  - input/output control surface
- **Do not use as:** generic creative-tooling authority outside a dedicated media-generation pack

### Conditional adoption rule
Only promote if the toolkit explicitly takes on image/video generation or self-hosted creative tooling as a domain.

---

## 29.9 Hold / skip registry

These repos should be preserved as evaluated inputs, but not added to the toolkit right now.

#### `lexfridman/mit-deep-learning`
- **Status:** Hold / Skip
- **Reason:** strong educational material, wrong layer for this toolkit; does not materially improve packs, routing, extraction, or answer behavior

#### `d2l-ai/d2l-en`
- **Status:** Hold / Skip
- **Reason:** broad educational textbook/course content; useful for study, but not a sharp toolkit-enabling source

#### `MLNLP-World/MIT-Linear-Algebra-Notes`
- **Status:** Hold / Skip
- **Reason:** educational math notes, wrong layer for this platform

#### `NancyFx/Nancy`
- **Status:** Hold / Skip
- **Reason:** historical/legacy framework reference, low current strategic value for this toolkit

---

## 29.10 Promotion rules for future candidates

A Part 4 candidate should only be promoted into an active pack when:

- the domain becomes an explicit toolkit target
- a pack manifest is created for that domain
- the repo has a defined authority role
- extraction outputs are specified
- routing rules are specified
- eval tasks are written
- private/public boundary implications are understood

Do not promote candidate repos straight into active packs just because they are interesting.

---

## 29.11 Promotion Status (ALL PACKS IMPLEMENTED)

> **Update:** All candidate packs from Part 4 have been successfully promoted and implemented. The promotion priorities listed below are now **COMPLETE**.

### Completed Promotions

| Priority | Repository | Pack Section | Status |
|----------|------------|--------------|--------|
| 1 | `alufers/mitmproxy2swagger` | 29.2 API Reverse Tooling | ✅ IMPLEMENTED |
| 2 | `mito-ds/mito` | 29.3 Notebook/Data Workflow | ✅ IMPLEMENTED |
| 3 | `a16z-infra/ai-town` | 29.4 Agent Simulation | ✅ IMPLEMENTED |
| 4 | `myshell-ai/OpenVoice` | 29.5 Voice/Audio Generation | ✅ IMPLEMENTED |
| 5 | `GarageGames/Torque3D` | 29.6 Engine Reference | ✅ IMPLEMENTED |
| — | `MithrilJS/mithril.js` | 29.7 UI/Frontend Framework | ✅ IMPLEMENTED |
| — | `mdbootstrap/TW-Elements` | 29.7 UI/Frontend Framework | ✅ IMPLEMENTED |
| — | `nolly-studio/cult-ui` | 29.7 UI/Frontend Framework | ✅ IMPLEMENTED |
| — | `lexfridman/mit-deep-learning` | 29.12 ML/Educational Reference | ✅ IMPLEMENTED |
| — | `d2l-ai/d2l-en` | 29.12 ML/Educational Reference | ✅ IMPLEMENTED |
| — | `MLNLP-World/MIT-Linear-Algebra-Notes` | 29.12 ML/Educational Reference | ✅ IMPLEMENTED |

### Remaining Conditional Candidates

The following candidates remain in **Conditional** status pending future toolkit domain expansion:

- `Anil-matcha/Open-Higgsfield-AI` (Section 29.8) - Image/creative-generation
- `NancyFx/Nancy` (Section 29.14) - Legacy .NET/historical web framework

---

## 29.12 ✅ ML / Math / Educational reference candidate pack (IMPLEMENTED)

These repos can be preserved, but they do **not** belong under "database knowledge."  
They fit better as an **educational/reference pack** for machine learning, math, and conceptual background material.

### Candidate purpose
This pack would cover:
- machine learning educational references
- interactive deep learning curricula
- math background references
- conceptual support material for ML-oriented private projects

### Conditional candidates

#### `lexfridman/mit-deep-learning`
- **Status:** ✅ IMPLEMENTED (was: Conditional)
- **Part of:** `packs/manifests/ml-educational-reference.json`
- **Parsers:** `EducationalContentExtractor.ps1`, `MLConceptExtractor.ps1`
- **Authority role:** `educational-reference`
- **Why it may belong:** collection of tutorials, assignments, and competitions for MIT Deep Learning courses
- **Must-extract if adopted:**
  - tutorial structure
  - topic taxonomy
  - notebook/workshop workflow patterns
  - conceptual anchors for deep learning topics
- **Do not use as:** operational toolkit authority, database authority, or production-system authority
- **Recommended future collection:** `ml_education_reference`

#### `d2l-ai/d2l-en`
- **Status:** ✅ IMPLEMENTED (was: Conditional)
- **Part of:** `packs/manifests/ml-educational-reference.json`
- **Authority role:** `educational-reference`
- **Why it may belong:** interactive deep learning book with code, math, and multi-framework instructional material
- **Must-extract if adopted:**
  - chapter/topic structure
  - model-family taxonomy
  - framework-agnostic conceptual summaries
  - code example references
- **Do not use as:** database authority or direct platform-behavior authority
- **Recommended future collection:** `ml_education_reference`

#### `MLNLP-World/MIT-Linear-Algebra-Notes`
- **Status:** ✅ IMPLEMENTED (was: Conditional)
- **Part of:** `packs/manifests/ml-educational-reference.json`
- **Authority role:** `math-reference`
- **Why it may belong:** background math notes that could support ML/matrix reasoning contexts
- **Must-extract if adopted:**
  - theorem/topic hierarchy
  - matrix/vector concept taxonomy
  - concise formula/reference summaries
- **Do not use as:** database authority, systems authority, or primary coding-pattern authority
- **Recommended future collection:** `ml_math_reference`

### Conditional adoption rule
Only promote these if the toolkit explicitly adds an **ML / math educational reference pack**. They are useful background material, but they are not core operational sources.

---

## 29.13 Implemented Packs Reference

Quick reference links to all implemented pack manifests and parsers:

| Pack | Manifest | Parsers | Authority Roles |
|------|----------|---------|-----------------|
| **API Reverse Tooling** | [`packs/manifests/api-reverse-tooling.json`](packs/manifests/api-reverse-tooling.json) | `TrafficCaptureParser.ps1`<br>`OpenAPIExtractor.ps1` | `reverse-format`<br>`tooling-analyzer` |
| **Notebook/Data Workflow** | [`packs/manifests/notebook-data-workflow.json`](packs/manifests/notebook-data-workflow.json) | `NotebookParser.ps1`<br>`DataFramePatternExtractor.ps1` | `notebook-tooling` |
| **Agent Simulation** | [`packs/manifests/agent-simulation.json`](packs/manifests/agent-simulation.json) | `AgentPatternExtractor.ps1`<br>`VectorStoreExtractor.ps1` | `agent-simulation` |
| **Voice/Audio Generation** | [`packs/manifests/voice-audio-generation.json`](packs/manifests/voice-audio-generation.json) | `VoiceModelExtractor.ps1`<br>`AudioProcessingExtractor.ps1` | `voice-generation` |
| **Engine Reference** | [`packs/manifests/engine-reference.json`](packs/manifests/engine-reference.json) | `EngineArchitectureExtractor.ps1`<br>`ScriptRuntimeExtractor.ps1` | `engine-reference` |
| **UI/Frontend Framework** | [`packs/manifests/ui-frontend-framework.json`](packs/manifests/ui-frontend-framework.json) | `ComponentLibraryExtractor.ps1`<br>`DesignSystemExtractor.ps1` | `frontend-framework`<br>`ui-component-library` |
| **ML/Educational Reference** | [`packs/manifests/ml-educational-reference.json`](packs/manifests/ml-educational-reference.json) | `EducationalContentExtractor.ps1`<br>`MLConceptExtractor.ps1` | `educational-reference`<br>`math-reference` |

---

## 29.14 Legacy .NET / historical web-framework candidate pack

This is a different category from ML/math and should stay separate.

### Hold / conditional candidate

#### `NancyFx/Nancy`
- **Status:** Hold / Conditional
- **Authority role:** `legacy-web-framework`
- **Why it may belong:** historically relevant lightweight .NET web framework reference
- **Why it is weak:** old/historical rather than strategically important to the current toolkit direction
- **Must-extract if adopted:**
  - routing model
  - module conventions
  - low-ceremony HTTP service patterns
- **Do not use as:** current default .NET web authority
- **Recommended future collection:** `legacy_dotnet_web`

### Conditional adoption rule
Only promote if the toolkit deliberately adds a **legacy .NET / historical framework reference pack**. Otherwise this stays recorded as evaluated but non-priority.

---

## 29.15 Correction to category fit

These four repos should **not** be labeled as "database knowledge."

Better fit:
- `lexfridman/mit-deep-learning` -> ML education
- `d2l-ai/d2l-en` -> ML education
- `MLNLP-World/MIT-Linear-Algebra-Notes` -> math background / linear algebra reference
- `NancyFx/Nancy` -> legacy .NET web framework reference

That distinction matters because the toolkit should not mix:
- database reasoning
- ML education
- math notes
- historical web frameworks

into one fake category.
