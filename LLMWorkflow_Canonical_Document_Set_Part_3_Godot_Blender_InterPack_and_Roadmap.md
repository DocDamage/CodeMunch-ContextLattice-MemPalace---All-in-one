# LLM Workflow — Canonical Architecture, Pack Framework, and Delivery Plan

## Status

**This is the canonical source-of-truth document.**  
It supersedes the earlier implementation plans, review passes, and RPG Maker pack review notes. Earlier documents should be treated as archived design history after this one is adopted.

---

## 25. Canonical domain-pack example: Godot Engine

This is the second official worked example pack, designed for Godot Engine game development alongside the RPG Maker MZ pack.

### 25.1 Pack identity

```json
{
  "packId": "godot-engine",
  "domain": "game-dev",
  "version": "1.0.0",
  "taxonomyVersion": "1",
  "status": "implemented",
  "defaultCollections": [
    "godot_core_api",
    "godot_plugin_patterns",
    "godot_language_bindings",
    "godot_tooling",
    "godot_visual_systems",
    "godot_deployment",
    "godot_private_project"
  ]
}
```

### 25.2 Scope

This pack is for:

- Godot Engine game development (2D, 3D, XR)
- GDScript and Godot scene/resource management
- Plugin/addon development and usage patterns
- Language binding workflows (Rust via gdext, C++ via godot-cpp)
- Shader, terrain, physics, and visual system integration
- Steam integration and game deployment pipelines
- CI/CD for automated Godot exports
- AI-assisted Godot development via MCP integration
- Local/private game project code understanding

This pack is not for:

- storing game binaries, assets, or exported builds
- redistributing proprietary game assets or code
- treating community addons as engine law
- replacing project-local private pack context

### 25.3 Collections

#### `godot_core_api`
Authoritative engine/runtime surfaces: GDScript API, node types, scene tree, rendering pipeline, physics, input, audio.
Default trust: **high**

#### `godot_plugin_patterns`
Community plugins, addons, templates, and game demos.
Default trust: **medium**

#### `godot_language_bindings`
Language binding APIs and patterns for Rust (gdext), C++ (godot-cpp), and Python (godot-python).
Default trust: **medium-high**

#### `godot_tooling`
MCP integration, editor plugins, CI/CD tooling, reverse-engineering tools, VS Code integration.
Default trust: **medium**

#### `godot_visual_systems`
Shaders, terrain systems (voxel, heightmap), ocean/water rendering, pixel renderers, physics engines (Jolt).
Default trust: **medium**

#### `godot_deployment`
Steam integration, CI/CD export pipelines, platform-specific deployment workflows.
Default trust: **medium-high**

#### `godot_private_project`
User-authored game scripts, scenes, shaders, and project-specific patterns.
Default trust: **high** for originals, lower for generated summaries.

### 25.4 Required metadata for Godot artifacts

In addition to core provenance fields, include when applicable:

- `engineTarget` (Godot 3 / Godot 4)
- `engineMinVersion`
- `engineMaxVersion`
- `scriptLanguage` (GDScript / C# / Rust / C++ / Python / Swift / JavaScript / TypeScript)
- `nodeType` (Node2D / Node3D / Control / etc.)
- `addonName`
- `addonCategory`
- `exportSignals`
- `exportProperties`
- `gdextensionInterface`
- `shaderType` (Spatial / CanvasItem / Particles / Sky)
- `pluginDependencies`
- `originalAuthor`
- `trustTier`

### 25.4.1 Authority roles for Godot

Supported `authorityRole` values:

- `core-engine` — Godot engine source code and official documentation
- `private-project` — user's own game project code and scenes
- `exemplar-pattern` — community plugins, templates, and demo projects
- `language-binding` — gdext, godot-cpp, godot-python bindings and API patterns
- `mcp-integration` — godot-mcp and AI-assisted development tooling
- `visual-system` — ocean, voxel, terrain, pixel renderer, shader libraries
- `physics-extension` — godot-jolt and other physics replacements
- `deployment-tooling` — GodotSteam, godot-ci, export pipeline tooling
- `reverse-format` — gdsdecomp and Godot reverse-engineering tools
- `starter-template` — game starter kits and project templates
- `curated-index` — awesome-godot and similar resource lists
- `testing-framework` — gdUnit4 and testing/QA tooling
- `ai-behavior-system` — LimboAI, Godot-FiniteStateMachine behavior frameworks
- `dialogue-system` — Dialogic, DialogueQuest narrative frameworks
- `quest-system` — quest/progression frameworks
- `inventory-system` — item/inventory/equipment systems
- `networking-system` — rollback netcode and multiplayer systems
- `editor-tooling` — editor VCS, Git integration plugins
- `debug-visualization` — signal visualization and debugging tools
- `save-system` — save/load convenience plugins
- `rpg-data-framework` — RPG data model frameworks
- `world-streaming-system` — chunk/open-world streaming systems
- `platform-service-integration` — platform service/achievement plugins

Examples:
- Godot engine source/docs -> `core-engine`
- `godot_private_project` -> `private-project`
- `godot-rust/gdext`, `godotengine/godot-cpp` -> `language-binding`
- `Coding-Solo/godot-mcp` -> `mcp-integration`
- `2Retr0/GodotOceanWaves`, `Zylann/godot_voxel` -> `visual-system`
- `godot-jolt/godot-jolt` -> `physics-extension`
- `GodotSteam/GodotSteam` -> `deployment-tooling`
- `GDRETools/gdsdecomp` -> `reverse-format`
- `KenneyNL/Starter-Kit-3D-Platformer` -> `starter-template`
- `godotengine/awesome-godot` -> `curated-index`
- `MikeSchulze/gdUnit4` -> `testing-framework`
- `limbonaut/limboai` -> `ai-behavior-system`
- `dialogic-godot/dialogic` -> `dialogue-system`
- `shomykohai/quest-system` -> `quest-system`
- `expressobits/inventory-system` -> `inventory-system`
- `maximkulkin/godot-rollback-netcode` -> `networking-system`
- `godotengine/godot-git-plugin` -> `editor-tooling`
- `Ericdowney/SignalVisualizer` -> `debug-visualization`
- `AdamKormos/SaveMadeEasy` -> `save-system`
- `bitbrain/pandora` -> `rpg-data-framework`
- `SlashScreen/chunx` -> `world-streaming-system`
- `GamePushService/GamePush-Godot-plugin` -> `platform-service-integration`

### 25.5 Source priority order

#### P0 — Core engine and documentation
Promote these ahead of community repos:

- Godot Engine source code (official repository)
- Official Godot documentation and API reference
- Official demo projects (`godotengine/godot-demo-projects`)

#### P1 — Strong workflow/tooling references
Examples:

- `Coding-Solo/godot-mcp` — MCP server for AI-assisted Godot dev
- `abarichello/godot-ci` — CI/CD export and deployment pipelines
- `godotengine/godot-vscode-plugin` — VS Code editor integration
- `GodotSteam/GodotSteam` — Steam platform integration

#### P2 — High-value language bindings and extensions
Use reputable, well-documented binding libraries:

- `godot-rust/gdext` — Rust bindings for Godot 4
- `godotengine/godot-cpp` — Official C++ bindings
- `godot-jolt/godot-jolt` — Jolt physics engine integration
- `MikeSchulze/gdUnit4` — Testing framework for Godot 4
- `limbonaut/limboai` — AI behavior trees and state machines
- `dialogic-godot/dialogic` — Dialogue and narrative framework
- `shomykohai/quest-system` — Quest/progression framework
- `expressobits/inventory-system` — Inventory/RPG systems
- `maximkulkin/godot-rollback-netcode` — Rollback networking
- `godotengine/godot-git-plugin` — Editor VCS integration
- `bitbrain/pandora` — RPG data management framework
- `SlashScreen/chunx` — Chunk/open-world streaming

#### P3 — Visual/terrain/rendering systems
- `2Retr0/GodotOceanWaves` — FFT ocean wave rendering
- `Zylann/godot_voxel` — Voxel terrain module
- `Zylann/godot_heightmap_plugin` — HeightMap terrain
- `bukkbeek/GodotPixelRenderer` — 3D to pixel art toolkit
- `Syntaxxor/godot-voxel-terrain` — Alternate voxel terrain
- `GamePushService/GamePush-Godot-plugin` — Platform services
- `HexagonNico/Godot-FiniteStateMachine` — Lightweight FSM
- `Ericdowney/SignalVisualizer` — Signal debugging
- `AdamKormos/SaveMadeEasy` — Save/load convenience
- `hohfchns/DialogueQuest` — Lightweight dialogue system

#### P4 — Community patterns and templates
- `godotengine/awesome-godot` — Curated plugin/resource index (source registry seed)
- `KenneyNL/Starter-Kit-3D-Platformer` — 3D platformer starter kit
- Community plugins discovered through awesome-godot

#### P5 — Private project ingestion
The user's own game projects, scripts, scenes, and shaders. Often the most valuable source during actual development.

### 25.6 Required extraction outputs for Godot Engine

Mandatory outputs:

- GDScript class/method extraction
- Scene tree structure extraction (`.tscn` files)
- Resource definition extraction (`.tres` files)
- Signal connection extraction
- Export property extraction
- Shader parameter extraction
- GDExtension interface extraction
- Node inheritance hierarchy extraction
- Addon/plugin manifest extraction (`plugin.cfg`)
- `project.godot` configuration extraction
- Input action mapping extraction
- Autoload/singleton extraction
- GraphNode / VisualScript logic extraction (Orchestrator)
- GDExtension FFI mapping (Swift/JS)
- Test suite structure extraction (gdUnit4)
- Behavior tree/state machine pattern extraction (LimboAI)
- Dialogue resource schema extraction (Dialogic)
- Quest/inventory schema extraction
- Network rollback pattern extraction

### 25.7 Retrieval rules for Godot Engine pack

For foundational engine questions:
- prefer `godot_core_api`

For GDScript patterns and game architecture:
- prefer `godot_plugin_patterns`

For language binding questions (Rust, C++, Python):
- prefer `godot_language_bindings`

For AI-assisted development and MCP integration:
- prefer `godot_tooling`

For shader, terrain, and visual system questions:
- prefer `godot_visual_systems`

For Steam integration and CI/CD deployment:
- prefer `godot_deployment`

For project-specific behavior:
- prefer `godot_private_project`

For testing and QA:
- prefer `testing-framework` sources

For AI behavior and state machines:
- prefer `ai-behavior-system` sources

For dialogue and narrative:
- prefer `dialogue-system` sources

### 25.7.1 Repo-specific retrieval routing rules

#### Shader / visual effects questions
Preferred evidence order:
1. `godot_private_project`
2. `2Retr0/GodotOceanWaves`
3. `bukkbeek/GodotPixelRenderer`
4. P0 engine docs on ShaderMaterial/VisualShader
5. awesome-godot shader plugins

#### Terrain / world generation questions
Preferred evidence order:
1. `godot_private_project`
2. `Zylann/godot_voxel`
3. `Zylann/godot_heightmap_plugin`
4. `Syntaxxor/godot-voxel-terrain`
5. P0 engine docs on Terrain3D/MeshInstance3D

#### Physics questions
Preferred evidence order:
1. `godot_private_project`
2. `godot-jolt/godot-jolt`
3. P0 engine docs on PhysicsServer3D/RigidBody3D

#### Rust / C++ binding questions
Preferred evidence order:
1. `godot-rust/gdext` (for Rust)
2. `godotengine/godot-cpp` (for C++)
3. P0 engine docs on GDExtension

#### Steam integration / deployment questions
Preferred evidence order:
1. `GodotSteam/GodotSteam`
2. `abarichello/godot-ci`
3. P0 engine docs on export presets

#### AI-assisted development / MCP questions
Preferred evidence order:
1. `Coding-Solo/godot-mcp`
2. `godotengine/godot-vscode-plugin`
3. general MCP protocol documentation

#### Testing / QA questions
Preferred evidence order:
1. `godot_private_project`
2. `MikeSchulze/gdUnit4`
3. P0 official docs/source

#### AI behavior / state machine questions
Preferred evidence order:
1. `godot_private_project`
2. `limbonaut/limboai`
3. `HexagonNico/Godot-FiniteStateMachine`
4. P0 official docs/source

#### Dialogue / narrative system questions
Preferred evidence order:
1. `godot_private_project`
2. `dialogic-godot/dialogic`
3. `hohfchns/DialogueQuest`
4. P0 docs/source

#### Quest / progression questions
Preferred evidence order:
1. `godot_private_project`
2. `shomykohai/quest-system`
3. P0 docs/source

#### Inventory / item / equipment questions
Preferred evidence order:
1. `godot_private_project`
2. `expressobits/inventory-system`
3. `bitbrain/pandora`
4. P0 docs/source

#### Rollback multiplayer questions
Preferred evidence order:
1. `godot_private_project`
2. `maximkulkin/godot-rollback-netcode`
3. P0 docs/source

#### Chunk streaming / open-world questions
Preferred evidence order:
1. `godot_private_project`
2. `SlashScreen/chunx`
3. P0 docs/source

### 25.8 Godot Engine eval suites

#### API lookup suite
Examples:
- standard Node lifecycle methods (`_ready`, `_process`, `_physics_process`)
- common signal patterns and connections
- `SceneTree` navigation and node management
- Input handling patterns (InputEvent, InputMap)

#### Code generation suite
Examples:
- minimal GDScript class extending Node2D
- custom Resource class with exported properties
- basic GDExtension setup with gdext (Rust)
- shader with uniform parameters
- scene with signal connections

#### Architecture suite
Examples:
- state machine implementation patterns
- component/composition vs inheritance patterns
- autoload singleton patterns
- scene instancing and dependency injection

#### Deployment suite
Examples:
- GitHub Actions workflow for multi-platform export
- Steam achievement integration via GodotSteam
- export preset configuration for Windows/Linux/macOS/Web

#### Domain correctness negative suite
The system must not:

- invent nonexistent Godot API methods or nodes
- treat plugin conventions as core engine requirements
- confuse Godot 3 and Godot 4 APIs without warning
- ignore breaking changes between engine versions
- recommend deprecated GDScript syntax (e.g., `onready` vs `@onready`)

### 25.9 Install profiles for Godot Engine pack

- `core-only`: engine API reference and documentation only
- `minimal`: core + `godot-mcp` + `godot-ci` + `GodotSteam`
- `developer`: balanced public pack with language bindings and visual systems
- `full`: all promoted public sources
- `private-first`: minimal public + strong local project emphasis

#### `core-only`
Exact membership:
- Godot Engine API reference
- Official documentation
- Official demo projects

#### `minimal`
Exact membership:
- all `core-only` members
- `Coding-Solo/godot-mcp`
- `abarichello/godot-ci`
- `GodotSteam/GodotSteam`
- `godotengine/godot-vscode-plugin`

#### `developer`
Exact membership:
- all `minimal` members
- `godot-rust/gdext`
- `godotengine/godot-cpp`
- `godot-jolt/godot-jolt`
- `2Retr0/GodotOceanWaves`
- `Zylann/godot_voxel`
- `Zylann/godot_heightmap_plugin`
- `bukkbeek/GodotPixelRenderer`
- `KenneyNL/Starter-Kit-3D-Platformer`
- `godotengine/awesome-godot` (as source registry seed)
- `MikeSchulze/gdUnit4`
- `limbonaut/limboai`
- `dialogic-godot/dialogic`
- `shomykohai/quest-system`
- `expressobits/inventory-system`
- `maximkulkin/godot-rollback-netcode`
- `godotengine/godot-git-plugin`
- `Ericdowney/SignalVisualizer`
- `bitbrain/pandora`
- `SlashScreen/chunx`

#### `full`
Exact membership:
- all promoted public sources in `25.11`

#### `private-first`
Exact membership:
- all `core-only` members
- `godot_private_project`
- fallback public set:
  - `Coding-Solo/godot-mcp`
  - `abarichello/godot-ci`
  - `GodotSteam/GodotSteam`

The point of `private-first` is not breadth. It is to keep project-local truth ahead of public example repos.

### 25.10 Private-project policy for Godot Engine pack

Rules:

- separate collection or namespace
- strict secret scanning (API keys, Steam credentials)
- no sharing/federation by default
- highest retrieval priority in matching project context
- encrypted backups preferred
- public fallback must be labeled as fallback

### 25.11 Evaluated source registry

The following repositories were evaluated and accepted for ingestion into the Godot Engine pack. This registry is the concrete source set that the priority tiers (25.5) draw from.

### 25.11.1 Canonical P0 source anchors

For the Godot pack, the P0 anchor set should resolve to concrete canonical sources rather than generic placeholders.

Required canonical anchors:
- `godotengine/godot` -> engine source of truth
- `godotengine/godot-docs` -> official documentation source of truth
- `godotengine/godot-demo-projects` -> official demo/reference projects

These three sources together define the authoritative baseline for:
- engine API truth
- node and scene behavior
- rendering, physics, input, and audio semantics
- official example patterns

Community repos must not outrank these anchors for foundational questions.

### 25.11.2 Curated-index and roadmap-source policy

Some Godot sources are valuable but must remain scoped correctly:

- `godotengine/awesome-godot` is a **curated discovery index**, not an engine authority
- `godotengine/godot-proposals` is **roadmap context**, not runtime truth
- both may influence source discovery, future-planning answers, and comparative context
- neither should establish canonical answers about current stock engine behavior unless corroborated by `godotengine/godot` or `godotengine/godot-docs`



#### P0 — Core engine (implemented)

| Source | Notes |
|--------|-------|
| Godot Engine source code | Core engine: nodes, rendering, physics, input, audio |
| Official API documentation | Class reference, tutorials, best practices |
| `godotengine/godot-demo-projects` | Official demos covering 2D, 3D, networking, shaders |

#### P1 — Workflow / tooling

| Source | Trust | Stars | License | Notes |
|--------|-------|-------|---------|-------|
| `Coding-Solo/godot-mcp` | Medium-High | 3k | MIT | MCP server: launch editor, run projects, create scenes, capture debug |
| `abarichello/godot-ci` | Medium-High | 1.1k | MIT | Docker + GitHub Actions/GitLab CI for automated exports |
| `godotengine/godot-vscode-plugin` | Medium-High | — | MIT | VS Code GDScript support, debugging, scene tree |
| `GodotSteam/GodotSteam` | High | 3.7k | MIT | Steamworks API bindings (moved to Codeberg) |
| `hhyyrylainen/GodotPckTool` | Medium-High | — | MIT | PCK file extraction/creation tool |
| `godotengine/godot-blender-exporter` | High | — | MIT | Official Blender-to-Godot scene exporter |

#### P2 — Language bindings and engine extensions

| Source | Trust | Stars | License | Key value |
|--------|-------|-------|---------|-----------|
| `godot-rust/gdext` | Medium-High | 4.7k | MPL-2.0 | Rust bindings for Godot 4; type-safe, high-performance GDExtension |
| `godotengine/godot-cpp` | High | — | MIT | Official C++ bindings for GDExtension |
| `godot-jolt/godot-jolt` | Medium-High | — | MIT | Jolt physics engine integration; drop-in physics replacement |
| `godotjs/GodotJS` | Medium | — | MIT | V8/QuickJS support for Godot 4.x |
| `migueldeicaza/SwiftGodot` | Medium-High | — | MIT | Swift bindings for Godot |

#### P2 — High-value gameplay systems / tooling (from Appendage A)

| Source | Trust | Stars | License | Key value |
|--------|-------|-------|---------|-----------|
| `MikeSchulze/gdUnit4` | Medium-High | — | MIT | Embedded Godot testing framework |
| `limbonaut/limboai` | Medium-High | — | MIT | AI behavior trees + state machines |
| `dialogic-godot/dialogic` | Medium-High | — | MIT | Dialogue/narrative framework |
| `shomykohai/quest-system` | Medium | — | MIT | Quest/progression framework |
| `expressobits/inventory-system` | Medium | — | MIT | Modular inventory/RPG system |
| `maximkulkin/godot-rollback-netcode` | Medium | — | MIT | Rollback/prediction networking |
| `godotengine/godot-git-plugin` | Medium-High | — | MIT | Editor VCS integration |
| `bitbrain/pandora` | Medium | — | MIT | RPG data-management framework |
| `SlashScreen/chunx` | Medium | — | MIT | Chunk/open-world streaming |

#### P3 — Visual / terrain / rendering systems

| Source | Trust | Stars | License | Key value |
|--------|-------|-------|---------|-----------|
| `2Retr0/GodotOceanWaves` | Medium | — | — | FFT-based ocean wave rendering |
| `Zylann/godot_voxel` | Medium-High | — | — | Voxel terrain module: smooth/blocky, LOD, infinite terrain |
| `Zylann/godot_heightmap_plugin` | Medium | — | MIT | HeightMap terrain with texture painting, LOD, grass |
| `bukkbeek/GodotPixelRenderer` | Medium | — | — | 3D to pixel art rendering toolkit |
| `ahopness/GodotRetro` | Medium | — | — | Retro shader pack (PS1/VHS/CRT effects) |
| `2Retr0/GodotGrass` | Medium | — | — | Per-blade Ghost of Tsushima style grass |
| `Syntaxxor/godot-voxel-terrain` | Medium | — | MIT | Alternate voxel terrain implementation |

#### P3 — Debugging / auxiliary systems / specialized workflows

| Source | Trust | Stars | License | Key value |
|--------|-------|-------|---------|-----------|
| `Ericdowney/SignalVisualizer` | Medium | — | MIT | Signal graph visualization/debugging |
| `AdamKormos/SaveMadeEasy` | Medium | — | MIT | Save/load convenience plugin |
| `hohfchns/DialogueQuest` | Medium | — | MIT | Lightweight dialogue system |
| `GamePushService/GamePush-Godot-plugin` | Medium | — | MIT | Backend/platform service integration |
| `HexagonNico/Godot-FiniteStateMachine` | Medium | — | MIT | Lightweight FSM framework |

#### P4 — Community patterns and templates

| Source | Trust | Stars | License | Key value |
|--------|-------|-------|---------|-----------|
| `godotengine/awesome-godot` | Medium-High | 9.7k | CC-BY-4.0 | Curated index: games, plugins, templates, tutorials |
| `KenneyNL/Starter-Kit-3D-Platformer` | Medium | — | — | 3D platformer starter kit with Kenney assets |
| `touilleMan/godot-python` | Low-Medium | — | MIT | Python bindings (Godot 3 era, less maintained) |
| `borndotcom/react-native-godot` | Low | — | — | Embed Godot in React Native (niche) |
| `CraterCrash/godot-orchestrator` | Medium-High | — | MIT | Advanced visual scripting for Godot 4 |
| `godot-extended-libraries/godot-next` | Medium | — | MIT | Basic node extension library (QoL) |
| `edbeeching/godot_rl_agents` | Medium | — | MIT | Reinforcement Learning / NPC AI framework |
| `godotengine/godot-proposals` | Medium-High | — | — | Engine roadmap and feature proposal context |

#### P5 — Reverse engineering / specialized

| Source | Trust | Stars | License | Key value |
|--------|-------|-------|---------|-----------|
| `GDRETools/gdsdecomp` | Medium | — | — | Godot PCK decompiler, GDScript bytecode RE |

### 25.12 Repo-by-repo extraction target matrix

| Repo / Source | Primary value | Must-extract | Authority role | Risk notes |
|---|---|---|---|---|
| Godot Engine source / docs | Core engine truth | classes, nodes, methods, signals, rendering pipeline, physics API | `core-engine` | must outrank community examples on foundational questions |
| `Coding-Solo/godot-mcp` | AI-assisted Godot dev | MCP tool definitions, GDScript operations API, scene management | `mcp-integration` | keep scoped to MCP/tooling queries |
| `GodotSteam/GodotSteam` | Steam platform integration | Steamworks API mappings, achievement/leaderboard patterns, networking | `deployment-tooling` | moved to Codeberg; track canonical URL |
| `abarichello/godot-ci` | CI/CD pipelines | Dockerfile, GitHub Actions workflow, export presets, deploy targets | `deployment-tooling` | config-heavy; extract workflow patterns, not boilerplate |
| `godot-rust/gdext` | Rust language binding | `#[derive(GodotClass)]` patterns, signal macros, node lifecycle, FFI | `language-binding` | fast-moving API; version-pin references |
| `godotengine/godot-cpp` | C++ language binding | GDExtension class registration, method binding, property export | `language-binding` | official but lower-level than gdext |
| `godot-jolt/godot-jolt` | Physics replacement | Jolt configuration, collision layer setup, physics material patterns | `physics-extension` | drop-in but may affect physics behavior |
| `2Retr0/GodotOceanWaves` | FFT ocean rendering | shader uniforms, compute shader patterns, wave simulation config | `visual-system` | shader-heavy; extract parameters and setup |
| `Zylann/godot_voxel` | Voxel terrain | VoxelTerrain node, generator patterns, LOD config, streaming | `visual-system` | C++ module; requires custom engine build |
| `Zylann/godot_heightmap_plugin` | HeightMap terrain | terrain painting, LOD, grass, hole support, GDScript patterns | `visual-system` | plugin; no engine rebuild needed |
| `bukkbeek/GodotPixelRenderer` | 3D-to-pixel rendering | viewport setup, pixel shader config, resolution scaling | `visual-system` | niche aesthetic; keep in visual-system routing |
| `godotengine/awesome-godot` | Source registry seed | plugin metadata, categorization, repo URLs, descriptions | `curated-index` | do not use for engine authority; use as discovery layer |
| `KenneyNL/Starter-Kit-3D-Platformer` | 3D platformer patterns | character controller, camera, level design, asset pipeline | `starter-template` | learning resource, not authority |
| `GDRETools/gdsdecomp` | Reverse engineering | PCK format, GDScript bytecode, scene/resource recovery | `reverse-format` | keep out of normal game-dev answers unless query is RE-specific |
| `touilleMan/godot-python` | Python bindings | Cython bridge, Python-GDScript interop | `language-binding` | Godot 3 era; lower priority |
| `borndotcom/react-native-godot` | Mobile embedding | RN bridge, Godot view embedding | `exemplar-pattern` | highly niche; low priority |
| `godotjs/GodotJS` | TS/JS Binding | FFI patterns, TS definitions, v8 interop | `language-binding` | v8 integration risk |
| `migueldeicaza/SwiftGodot` | Swift Binding | Swift properties, macros, GDExtension patterns | `language-binding` | high trust (Miguel de Icaza) |
| `ahopness/GodotRetro` | Retro shaders | shader uniforms, PS1/CRT effect logic | `visual-system` | purely visual |
| `2Retr0/GodotGrass` | Foliage logic | grass blade shaders, multithreaded rendering | `visual-system` | perf-heavy |
| `godotengine/godot-blender-exporter` | Pipeline | export logic, scene mapping, asset conversion | `pipeline-tool` | official tool |
| `hhyyrylainen/GodotPckTool` | PCK editing | PCK archive format, extraction/merging logic | `deployment-tooling` | RE/deployment tool |
| `CraterCrash/godot-orchestrator` | Visual Scripting | GraphNode structures, visual connection logic | `visual-scripting` | high weight for logic-search |
| `godot_rl_agents` | AI / RL | agent observations, training loops, NPC state | `npc-logic` | specialized AI |
| `godot-next` | QoL nodes | basic node extensions, common utility patterns | `exemplar-pattern` | broad but shallow |
| `godot-proposals` | Roadmap | feature context, missing API gaps, GIP logic | `roadmap-context` | read-only context |
| `MikeSchulze/gdUnit4` | Testing framework | test suite structure, assertions, mocking/spying APIs | `testing-framework` | version-sensitive; not gameplay authority |
| `limbonaut/limboai` | AI behavior | BT node/task patterns, state machine contracts | `ai-behavior-system` | framework; not stock engine AI |
| `dialogic-godot/dialogic` | Dialogue system | dialogue resources, character/timeline structures | `dialogue-system` | not canonical scene/UI behavior |
| `shomykohai/quest-system` | Quest framework | quest resource schema, singleton/modular API | `quest-system` | version-boundary important |
| `expressobits/inventory-system` | Inventory system | item/resource schemas, UI-logic separation | `inventory-system` | broad gameplay-system repo |
| `maximkulkin/godot-rollback-netcode` | Networking | input/state save-load hooks, rollback lifecycle | `networking-system` | rollback-specific |
| `godotengine/godot-git-plugin` | Editor VCS | VCS interface mapping, libgit2 backend | `editor-tooling` | editor-only; not gameplay |
| `Ericdowney/SignalVisualizer` | Debugging | signal graph model, scene introspection | `debug-visualization` | debugging queries only |
| `AdamKormos/SaveMadeEasy` | Save system | key-path storage, encryption behavior | `save-system` | convenience plugin |
| `hohfchns/DialogueQuest` | Dialogue | dialogue file format, standalone tester | `dialogue-system` | secondary to Dialogic |
| `bitbrain/pandora` | RPG data | item/spell/mob/quest/NPC schemas | `rpg-data-framework` | broad RPG scope |
| `SlashScreen/chunx` | Streaming | chunk lifecycle, streaming triggers | `world-streaming-system` | open-world specific |
| `Syntaxxor/godot-voxel-terrain` | Voxel terrain | terrain chunk model, editor tooling | `visual-system` | alternate to Zylann |
| `GamePushService/GamePush-Godot-plugin` | Platform services | achievements, analytics, ads, payments | `platform-service-integration` | services plugin |
| `HexagonNico/Godot-FiniteStateMachine` | FSM | node-based FSM, transition hooks | `ai-behavior-system` | lightweight FSM alternative |

### 25.13 Repo-specific authority constraints

The following constraints are mandatory:

- do not use `godotengine/awesome-godot` to establish engine law; it is a discovery index, not an authority source
- do not use `KenneyNL/Starter-Kit-3D-Platformer` to define canonical game architecture
- do not use `GDRETools/gdsdecomp` for game development guidance; it is reverse-engineering tooling only
- do not let `Coding-Solo/godot-mcp` bleed into engine API answers; it is MCP tooling, not engine reference
- do not let `touilleMan/godot-python` answers apply to Godot 4 without explicit version caveats (it targets Godot 3)
- do not confuse `godot-rust/gdext` API patterns with GDScript patterns; they are different languages with different idioms
- do not use `MikeSchulze/gdUnit4` to define generic Godot runtime behavior; it is testing authority
- do not use `limbonaut/limboai` as stock Godot AI architecture authority; it is a framework/plugin
- do not use `dialogic-godot/dialogic` to define canonical scene/UI behavior outside dialogue questions
- do not use `bitbrain/pandora` to define canonical save/data architecture outside RPG questions

### 25.14 Refresh cadence and review policy by repo class

- P0 engine source/docs -> refresh when target Godot engine version changes
- `Coding-Solo/godot-mcp`, `godot-rust/gdext` -> 30-day review cadence (fast-moving)
- `GodotSteam/GodotSteam`, `abarichello/godot-ci` -> refresh when new Godot stable release ships
- `Zylann/godot_voxel`, `Zylann/godot_heightmap_plugin` -> 45-60 day cadence
- niche repos (`GodotOceanWaves`, `GodotPixelRenderer`, `Starter-Kit-3D-Platformer`) -> manual / promote-on-change cadence
- `godotengine/awesome-godot` -> 30-day scan for new high-value entries to promote into source registry
- `MikeSchulze/gdUnit4`, `limbonaut/limboai`, `dialogic-godot/dialogic` -> 30-day review cadence
- `SlashScreen/chunx`, `bitbrain/pandora` -> 45-day cadence

### 25.15 GDScript and scene file handling

### 25.15.1 Mandatory Godot structural extraction grammar

In addition to general file parsing rules, the Godot extraction layer must explicitly normalize the constructs that matter most for retrieval and answer quality.

At minimum, extract and normalize:
- `extends`
- `class_name`
- `signal`
- `@export`
- `@onready`
- `@tool`
- `@icon`
- typed variable and function signatures
- autoload registrations from `project.godot`
- input actions from `InputMap`
- scene inheritance and instancing references
- node paths used in signal connections
- `.gdextension` manifest fields
- `plugin.cfg` addon metadata
- export preset definitions when present

This is required so the system can answer from real structural facts instead of only semantic chunks.

### 25.15.2 Godot dependency and extension map

The Godot pack must explicitly model repo-level dependency and extension facts so answers do not recommend patterns without their actual prerequisites.

Known high-value dependency / extension examples:

- `godot-rust/gdext` -> depends on Godot 4 GDExtension; Rust patterns must not be projected backward onto Godot 3
- `godotengine/godot-cpp` -> official C++ binding layer for GDExtension; lower-level than `gdext` and should be routed separately
- `godot-jolt/godot-jolt` -> physics replacement with behavior implications; answers must surface that it is not stock physics
- `GodotSteam/GodotSteam` -> Steamworks integration layer with platform/export dependencies
- `abarichello/godot-ci` -> depends on export templates, platform presets, and runner/container assumptions
- `godotengine/godot-blender-exporter` -> pipeline dependency for Blender -> Godot transfer
- `CraterCrash/godot-orchestrator` -> visual logic layer that should not be confused with stock engine scripting
- `touilleMan/godot-python` -> Godot 3 era binding; must be version-caveated before recommendation
- `godotjs/GodotJS` / `migueldeicaza/SwiftGodot` -> non-default language bindings; answers must surface that these are extension ecosystems, not stock engine paths
- `MikeSchulze/gdUnit4` -> testing framework dependency; must not be required for non-testing workflows
- `limbonaut/limboai` -> AI framework dependency; not required for stock Godot AI

A retrieval answer should not recommend a Godot pattern while omitting the binding, extension, export, or platform dependency that makes that pattern actually valid.

### 25.15.3 Godot version-boundary rules

Godot answers must be explicit about version boundaries when evidence crosses engine generations.

Required rules:
- do not mix Godot 3 and Godot 4 APIs without explicit caveat
- `@onready`, `@export`, typed GDScript, and GDExtension-era patterns must be treated as Godot 4-specific unless proven otherwise
- `touilleMan/godot-python` should default to Godot 3 compatibility context
- `godot-rust/gdext` and current `godot-cpp` guidance should default to Godot 4 compatibility context
- when a source is version-ambiguous, downgrade confidence and surface compatibility caveat
- scene, node, physics, shader, and export behavior should prefer exact engine-version matches when known



The Godot Engine pack must explicitly support GDScript source files and Godot scene/resource formats.

Rules:
- `.gd` files are parsed as GDScript source with class/method/signal extraction
- `.tscn` files are parsed as scene tree definitions with node hierarchy and property extraction
- `.tres` files are parsed as resource definitions with property extraction
- `.gdshader` files are parsed as shader source with uniform/parameter extraction
- `.cfg` files (especially `plugin.cfg`, `project.godot`) are parsed as configuration
- `.gdextension` files are parsed as GDExtension manifests
- scene files should preserve node paths and signal connections for retrieval
- GDScript class inheritance must be tracked across files
- `@tool`, `@onready`, `@export` annotations must be extracted as structural metadata

### 25.16 Cross-pack interaction with RPG Maker MZ

Since both the `rpgmaker-mz` and `godot-engine` packs share the `game-dev` domain:

- workspace-level pack selection determines which pack is active
- cross-pack queries (e.g., "how does Godot handle plugin loading compared to RPG Maker MZ?") must label evidence sources by pack
- do not mix RPG Maker MZ engine-specific answers into Godot queries or vice versa
- shared concepts (game loop, scene management, input handling) may reference both packs if the query is explicitly comparative
- private-project packs remain workspace-scoped and do not cross between game engine contexts

### 25.17 MCP integration architecture

The `Coding-Solo/godot-mcp` server provides direct AI-to-Godot communication. Integration rules:

- MCP server runs as `npx @coding-solo/godot-mcp`
- Supports tools: `launch_editor`, `run_project`, `get_debug_output`, `stop_project`, `get_godot_version`, `list_projects`, `get_project_info`, `create_scene`, `add_node`, `load_sprite`, `export_mesh_library`, `save_scene`, `get_uid`, `update_project_uids`
- In `mcp-readonly` execution mode: allow `get_godot_version`, `list_projects`, `get_project_info`, `get_debug_output`, `get_uid`
- In `mcp-mutating` execution mode: additionally allow `launch_editor`, `run_project`, `stop_project`, `create_scene`, `add_node`, `load_sprite`, `export_mesh_library`, `save_scene`, `update_project_uids`
- Environment variables: `GODOT_PATH` (path to Godot executable), `DEBUG` (enable verbose output)
- GDScript operations are handled via a bundled `godot_operations.gd` script that accepts JSON parameters

This integration maps directly to the platform's Phase 7 MCP-native toolkit server and MCP composite gateway architecture.

### 25.18 Repo-specific evaluation tasks

In addition to the general eval suites above, the Godot pack must ship with repo-specific tasks that prove the named sources are being used correctly.

Examples:

- "Does `godot-jolt/godot-jolt` change the answer for collision/physics setup compared with stock Godot physics?"
- "When the user asks about Rust bindings, does `godot-rust/gdext` outrank generic GDScript examples and `godotengine/godot-cpp`?"
- "When the user asks about Steam achievements or leaderboards, does `GodotSteam/GodotSteam` outrank generic deployment/export docs?"
- "Can the system explain why `Coding-Solo/godot-mcp` is evidence for MCP/editor control but not for engine API authority?"
- "If the user asks about voxel terrain, do `Zylann/godot_voxel` and `Zylann/godot_heightmap_plugin` outrank unrelated visual-system repos?"
- "If the query is about Godot 3 Python bindings, does `touilleMan/godot-python` stay version-caveated instead of leaking into Godot 4 answers?"
- "When the user asks how their own project configures scene transitions or autoloads, does `godot_private_project` outrank public templates such as `KenneyNL/Starter-Kit-3D-Platformer`?"
- "Does `godotengine/awesome-godot` stay a discovery/index source instead of being treated as engine-law authority?"
- "When the user asks how to test GDScript scenes, does `MikeSchulze/gdUnit4` outrank generic editor/plugin sources?"
- "When the user asks about behavior trees or state machines in Godot 4, does `limbonaut/limboai` outrank generic gameplay examples?"
- "When the user asks about RPG data schemas, does `bitbrain/pandora` outrank unrelated gameplay repos?"
- "When the user asks about open-world chunk loading, does `SlashScreen/chunx` outrank generic scene-loading examples?"

These tasks should be tracked as stable golden tasks, not ad hoc spot checks.

### 25.19 Repo health and risk notes

Each named repo in the Godot source registry should carry concise operational notes such as:

- fast-moving API surface
- engine-version sensitive
- extension/runtime replacement
- deployment-only
- reverse-format only
- curated index, not authority
- starter template / example-only
- niche embedding path
- moved canonical host (for example `GodotSteam/GodotSteam` -> Codeberg)
- testing framework, not engine authority
- AI behavior framework, not stock engine
- dialogue system, not canonical UI

These notes should influence review, promotion, and routing behavior.


---

## 26. Canonical domain-pack example: Blender Engine

This is the third official worked example pack, establishing Blender as a first-class knowledge domain for 3D asset generation and world-building.

### 26.1 Pack identity

```json
{
  "packId": "blender-engine",
  "domain": "3d-graphics",
  "version": "1.0.0",
  "taxonomyVersion": "1",
  "status": "implemented",
  "defaultCollections": [
    "blender_core_api",
    "blender_addons",
    "blender_tooling",
    "blender_visual_systems",
    "blender_synthetic_data",
    "blender_private_project"
  ]
}
```

### 26.2 Scope

This pack is for:

- 3D modeling, texturing, rigging, and animation workflows in Blender
- Python scripting and addon development for Blender
- Geometry Nodes and procedural generation logic
- Synthetic data generation (via BlenderProc)
- AI-assisted 3D development via MCP integration (blender-mcp)
- GPT-driven Blender control (BlenderGPT)
- GIS and geospatial modeling (BlenderGIS)
- MMD and specialized format conversions
- Export pipelines for game engines (especially Godot)

This pack is not for:

- storing high-poly meshes, raw textures, or binary .blend files
- redistributing proprietary addons or assets
- treating community addons as Blender core behavior

### 26.3 Collections

#### `blender_core_api`
Authoritative Blender Python API (`bpy`), operators, datablocks, and UI definitions.
Default trust: **high**

#### `blender_addons`
Community addons (MMD tools, GIS, etc.) and specialized script patterns.
Default trust: **medium**

#### `blender_tooling`
MCP integration, BlenderGPT logic, and synthetic data pipelines (BlenderProc).
Default trust: **medium-high**

#### `blender_visual_systems`
Geometry Nodes patterns, material node trees, and shader logic.
Default trust: **medium**

#### `blender_synthetic_data`
Photorealistic rendering pipelines and procedural data generation rules.
Default trust: **medium-high**

#### `blender_private_project`
User-authored scripts, custom geometry nodes, and local workflow patterns.
Default trust: **high**

### 26.4 Authority roles for Blender

Supported `authorityRole` values:

- `core-blender` — Blender API, official documentation, and source
- `mcp-integration` — blender-mcp and AI-assisted modeling tools
- `ai-agent-control` — BlenderGPT and LLM-to-bpy translation patterns
- `synth-proc` — BlenderProc and procedural rendering pipelines
- `gis-context` — BlenderGIS and geospatial modeling rules
- `pipeline-tool` — BlenderTools and engine export addons
- `curated-index` — awesome-blender and discovery layers
- `format-converter` — mmd_tools and interop extensions
- `private-project` — user's own Blender scripts, node graphs, export helpers, and asset workflows

### 26.5 Source priority order

#### P0 — Core Blender API and official references
Promote these ahead of community repos:

- official Blender Python API reference
- official Blender documentation
- official source and examples where practical

#### P1 — AI workflow and tooling
Examples:

- `ahujasid/blender-mcp`
- `gd3kr/BlenderGPT`

#### P2 — Synthetic data and procedural logic
Examples:

- `DLR-RM/BlenderProc`
- `domlysz/BlenderGIS`

#### P3 — Discovery, pipelines, and specialized conversion
Examples:

- `agmmnn/awesome-blender`
- `EpicGamesExt/BlenderTools`
- `sugiany/blender_mmd_tools`

#### P4 — Private project ingestion
The user's own Blender scripts, Geometry Nodes graphs, shader logic, export helpers, and asset-derivation metadata. These are often the most valuable source during real production work.

### 26.5.1 Blender version-boundary rules

Blender answers must be explicit about version boundaries.

Required rules:
- do not mix Blender 3.x and Blender 4.x API behavior without explicit caveat
- Geometry Nodes answers should prefer exact major-version matches when known
- addon registration and panel/operator patterns must be version-caveated when source code targets older Blender APIs
- exporter and pipeline behavior should be version-aware when tied to specific Blender releases
- when a source is version-ambiguous, downgrade confidence and surface compatibility caveat


### 26.10 Evaluated source registry (Blender)

The following repositories were evaluated and accepted for ingestion into the Blender Engine pack. This registry is the concrete source set that the priority tiers (26.5) draw from.

### 26.10.1 Blender dependency and addon map

The Blender pack must explicitly model repo-level dependency and addon facts so workflow answers do not omit actual prerequisites.

Known high-value examples:
- `ahujasid/blender-mcp` -> depends on a live Blender installation and MCP bridge configuration
- `gd3kr/BlenderGPT` -> depends on LLM-to-operator mapping and should not be treated as stock Blender behavior
- `DLR-RM/BlenderProc` -> depends on Blender Python automation and render/data-generation pipeline assumptions
- `domlysz/BlenderGIS` -> depends on GIS/geospatial context and projection handling
- `EpicGamesExt/BlenderTools` -> pipeline/export dependency chain for engine workflows
- `sugiany/blender_mmd_tools` -> format-conversion-specific workflow that should stay scoped to MMD/interop queries

A retrieval answer should not recommend a Blender workflow pattern while omitting the addon, exporter, or automation dependency that makes it valid.



#### P1 — AI Workflow & Tooling

| Source | Trust | Stars | License | Notes |
|--------|-------|-------|---------|-------|
| `ahujasid/blender-mcp` | Medium-High | — | MIT | MCP server for Blender: programmatic tool access |
| `gd3kr/BlenderGPT` | Medium-High | — | MIT | GPT-4 control logic for Blender operators |

#### P2 — Synthetic Data & Procedural Logic

| Source | Trust | Stars | License | Key value |
|--------|-------|-------|---------|-----------|
| `DLR-RM/BlenderProc` | Medium-High | — | MIT | Photorealistic pipeline for synthetic data generation |
| `domlysz/BlenderGIS` | Medium-High | — | MIT | Geospatial bridge for Blender modeling |

#### P3 — Discovery & Pipelines

| Source | Trust | Stars | License | Key value |
|--------|-------|-------|---------|-----------|
| `agmmnn/awesome-blender` | Medium | — | — | Master registry for addon discovery |
| `EpicGamesExt/BlenderTools` | Medium | — | MIT | Game dev pipeline (Unreal focus but good patterns) |
| `sugiany/blender_mmd_tools` | Medium | — | MIT | MikuMikuDance format interop patterns |

### 26.6 Extraction outputs for Blender Engine

Mandatory outputs:

- `bpy.ops` (Operator) call patterns
- Blender Python script logic (`.py`)
- Geometry Node tree structure (node types, socket connections)
- Shader Node tree structure
- Addon manifest metadata
- Synthetic data generation parameters (BlenderProc)
- GIS coordinate and mapping logic

### 26.6.1 Blender file and datablock handling

The Blender pack must explicitly define what is extracted from Blender-native artifacts and how binary-heavy project data is handled.

Rules:
- `.py` files are parsed as Blender Python source with operator, datablock, and registration extraction
- addon `__init__.py` / registration blocks must be parsed for panel/operator/property registration
- Geometry Nodes and shader node graphs should be represented as normalized node-tree artifacts where exported metadata is available
- `.blend` files are not stored as raw corpus content; instead, extract inspectable metadata/artifact summaries when tooling permits
- exported interchange files such as `.glb`, `.gltf`, `.fbx`, `.obj`, and manifest sidecars should be tracked as pipeline artifacts, not treated as authority sources
- material, rig, animation, camera, collection, and datablock relationships should be preserved in structured summaries when available
- BlenderGIS-derived geographic metadata should be preserved as structured mapping/projection artifacts
- BlenderProc pipelines should preserve scene generation parameters, camera sampling logic, render setup, and dataset output configuration

### 26.6.2 Mandatory Blender structural extraction

At minimum, the Blender extraction layer must normalize:

- `bl_info`
- addon name / version / category / author
- `bpy.types.Operator` registrations
- `bpy.types.Panel` registrations
- `bpy.props.*` property declarations
- Geometry Nodes node groups, node types, and socket links
- shader node trees, node types, and exposed parameters
- collection/object relationships where exported summaries exist
- export operators and pipeline hooks
- asset-derivation metadata for Blender -> engine export flows

### 26.7 Retrieval rules for Blender Engine

For foundational Blender API questions:
- prefer `blender_core_api`

For addon and workflow scripting patterns:
- prefer `blender_addons`

For MCP / GPT / agent-assisted Blender control:
- prefer `blender_tooling`

For Geometry Nodes, materials, and shader logic:
- prefer `blender_visual_systems`

For synthetic data and procedural render pipelines:
- prefer `blender_synthetic_data`

For project-specific behavior:
- prefer `blender_private_project`

### 26.7.1 Repo-specific retrieval routing rules

#### MCP / agent-control questions
Preferred evidence order:
1. `blender_private_project`
2. `ahujasid/blender-mcp`
3. `gd3kr/BlenderGPT`
4. official Blender Python API docs

#### Synthetic data / procedural rendering questions
Preferred evidence order:
1. `blender_private_project`
2. `DLR-RM/BlenderProc`
3. official Blender Python API docs
4. visual-system repos only if directly relevant

#### GIS / geospatial modeling questions
Preferred evidence order:
1. `blender_private_project`
2. `domlysz/BlenderGIS`
3. official Blender Python API docs
4. general addon examples only if needed

#### Engine export / pipeline questions
Preferred evidence order:
1. `blender_private_project`
2. `EpicGamesExt/BlenderTools`
3. `godotengine/godot-blender-exporter`
4. official Blender export/operator docs

#### MMD / format conversion questions
Preferred evidence order:
1. `blender_private_project`
2. `sugiany/blender_mmd_tools`
3. official import/export docs

#### Geometry Nodes / material / visual-system questions
Preferred evidence order:
1. `blender_private_project`
2. official Blender node/shader API docs
3. `DLR-RM/BlenderProc`
4. addon examples where directly relevant

### 26.8 Install profiles for Blender Engine

- `core-only`: Blender API/docs and official references only
- `minimal`: core + MCP/GPT/tooling + one strong procedural source
- `developer`: balanced public pack with GIS, synthetic data, and export tooling
- `full`: all promoted public sources
- `private-first`: minimal public + strong local project emphasis

#### `core-only`
Exact membership:
- official Blender Python API reference
- official Blender documentation
- official addon / operator reference where available

#### `minimal`
Exact membership:
- all `core-only` members
- `ahujasid/blender-mcp`
- `gd3kr/BlenderGPT`
- `DLR-RM/BlenderProc`

#### `developer`
Exact membership:
- all `minimal` members
- `domlysz/BlenderGIS`
- `EpicGamesExt/BlenderTools`
- `sugiany/blender_mmd_tools`
- `agmmnn/awesome-blender`

#### `full`
Exact membership:
- all promoted public sources in `26.10`

#### `private-first`
Exact membership:
- all `core-only` members
- `blender_private_project`
- fallback public set:
  - `ahujasid/blender-mcp`
  - `DLR-RM/BlenderProc`
  - `domlysz/BlenderGIS`

The point of `private-first` is not breadth. It is to keep project-local asset and pipeline truth ahead of public addon examples.

### 26.9 Private-project policy for Blender Engine

Rules:

- separate collection or namespace
- strict secret scanning for local automation credentials and pipeline tokens
- no sharing/federation by default
- highest retrieval priority in matching project context
- encrypted backups preferred
- exported engine-facing artifacts should retain derivation links back to Blender private-project evidence


### 26.11 Repo-by-repo extraction target matrix

| Repo / Source | Primary value | Must-extract | Authority role | Risk notes |
|---|---|---|---|---|
| official Blender API / docs | core Blender truth | operators, datablocks, types, panels, properties, node/shader APIs | `core-blender` | must outrank addon examples on foundational questions |
| `ahujasid/blender-mcp` | AI-assisted Blender control | MCP tool definitions, operator wrappers, scene/control API surface | `mcp-integration` | keep scoped to MCP/tooling queries |
| `gd3kr/BlenderGPT` | GPT-to-Blender control | operator translation patterns, prompt-to-action mapping, bpy usage | `ai-agent-control` | not core Blender authority |
| `DLR-RM/BlenderProc` | synthetic data pipelines | render configs, scene generation logic, camera sampling, dataset output params | `synth-proc` | should dominate synthetic-data queries only |
| `domlysz/BlenderGIS` | geospatial modeling | GIS import/export logic, projection handling, terrain mapping patterns | `gis-context` | should dominate GIS questions only |
| `EpicGamesExt/BlenderTools` | export/pipeline tooling | export logic, naming conventions, engine pipeline rules | `pipeline-tool` | pipeline authority, not core Blender behavior |
| `agmmnn/awesome-blender` | discovery/index | categorized source metadata, repo discovery records | `curated-index` | do not use as Blender-law authority |
| `sugiany/blender_mmd_tools` | format conversion | MMD import/export logic, rig/animation mapping, format rules | `format-converter` | specialized; keep scoped to conversion queries |

### 26.12 Repo-specific authority constraints

The following constraints are mandatory:

- do not use `agmmnn/awesome-blender` to establish Blender API truth; it is a discovery index
- do not use `gd3kr/BlenderGPT` to define canonical Blender operator behavior
- do not let `ahujasid/blender-mcp` bleed into foundational Blender API answers; it is MCP tooling
- do not let `DLR-RM/BlenderProc` define generic Blender material/shader behavior outside synthetic-data workflows
- do not let `EpicGamesExt/BlenderTools` define stock Blender behavior; it is pipeline/export tooling
- do not let `sugiany/blender_mmd_tools` influence non-MMD questions unless the retrieval profile is conversion/interop-focused

### 26.13 Refresh cadence and review policy by repo class

- official Blender docs / API -> refresh when target Blender version changes
- `ahujasid/blender-mcp`, `gd3kr/BlenderGPT` -> 30-day review cadence
- `DLR-RM/BlenderProc`, `domlysz/BlenderGIS` -> 45-day cadence
- `EpicGamesExt/BlenderTools`, `sugiany/blender_mmd_tools` -> manual / promote-on-change cadence
- `agmmnn/awesome-blender` -> 30-day scan for new high-value entries to promote into source registry

### 26.14 Repo-specific evaluation tasks

In addition to the general eval suites above, the Blender pack must ship with repo-specific tasks that prove the named sources are being used correctly.

Examples:

- "Can the system explain why `ahujasid/blender-mcp` is evidence for MCP/operator control but not for Blender API authority?"
- "When the user asks about photorealistic synthetic dataset generation, does `DLR-RM/BlenderProc` outrank generic addon examples?"
- "When the user asks about GIS terrain import or map projection workflows, does `domlysz/BlenderGIS` outrank unrelated procedural sources?"
- "When the query is about MMD conversion, does `sugiany/blender_mmd_tools` outrank generic export tooling?"
- "If the user asks how their own Geometry Nodes setup drives export into a game engine, does `blender_private_project` outrank public examples?"
- "Does `agmmnn/awesome-blender` stay a discovery/index source instead of being treated as Blender-law authority?"
- "If two answers mix Blender 3.x and Blender 4.x operator or Geometry Nodes behavior, does the system surface a version-boundary caveat instead of flattening them into one answer?"

These tasks should be tracked as stable golden tasks, not ad hoc spot checks.

### 26.15 Repo health and risk notes

Each named repo in the Blender source registry should carry concise operational notes such as:

- binary-heavy workflow
- addon / export dependency
- Geometry Nodes version sensitivity
- pipeline-only
- AI-agent control only
- synthetic-data-only
- GIS-specific
- curated index, not authority
- format-converter only

These notes should influence review, promotion, and routing behavior.

### 26.16 Cross-pack interaction with Godot

Because Blender is the primary asset-authoring domain for many Godot projects:

- Blender -> Godot pipeline answers should prefer `blender_private_project` and `godot_private_project` when both are present in the same workspace
- `EpicGamesExt/BlenderTools` and `godotengine/godot-blender-exporter` should be treated as pipeline tools, not engine-law sources
- Blender material, Geometry Nodes, and export answers must preserve derivation links into Godot scene/artifact outputs when a pipeline transfer occurs
- comparative or transport answers must label whether evidence comes from Blender API truth, Blender addon tooling, Godot engine truth, or Godot deployment/tooling


## 27. Canonical Inter-Pack Pipelines

Defining automated workflows across separate engine domain packs.

### 27.1 Blender -> Godot Scene Pipeline

Mapping Blender datablocks to Godot Nodes using the **godot-blender-exporter**.

- **Source**: `blender-engine` (Collection: `blender_private_project`)
- **Transport**: `pipeline-tool` (Collection: `blender_addons` / `godot_tooling`)
- **Target**: `godot-engine` (Collection: `godot_private_project`)
- **Automation**: Managed via `blender-mcp` (Blender side) and `godot-mcp` (Godot side).

### 27.2 Provenance across engines

When an asset is exported from Blender to Godot:
1. Generate an `AssetDerivationRecord` in the local workspace.
2. Link the Godot `SceneTree` node to the Blender `.py` or `.blend` source via run ID.
3. Ensure the `godot_private_project` pack can trace back to the `blender_private_project` evidence.

### 27.3 Canonical transport artifacts

Cross-pack workflows must not pass only opaque file references. They must emit structured transport artifacts that preserve provenance and replayability.

Required transport records include:
- `AssetDerivationRecord`
- `ExportPipelineRecord`
- `InterPackTransferRecord`

Example:

```json
{
  "recordType": "AssetDerivationRecord",
  "sourcePack": "blender-engine",
  "sourceCollection": "blender_private_project",
  "targetPack": "godot-engine",
  "targetCollection": "godot_private_project",
  "sourceArtifact": "blend-object:Environment/Cliff_A",
  "targetArtifact": "godot-scene:res://props/Cliff_A.tscn",
  "pipelineTool": "godotengine/godot-blender-exporter",
  "createdByRunId": "20260412T230501Z-a91f"
}
```

### 27.4 Inter-pack safety rules

Cross-pack answers and transfers must obey these rules:

- do not mix evidence from `rpgmaker-mz`, `godot-engine`, and `blender-engine` unless the query is explicitly comparative or pipeline-oriented
- inter-pack transport must preserve workspace boundaries and private/public visibility rules
- exported engine-facing artifacts should never sever provenance from source pack evidence
- public/reference packs may inform a pipeline answer, but must not override project-local transport facts
- answer traces for pipeline questions must show both source-pack and target-pack evidence explicitly

### 27.5 Comparative answer policy

When a user explicitly asks a comparative engine question, such as:
- "how does Godot handle plugin loading compared to RPG Maker MZ?"
- "what is the Blender -> Godot equivalent of this workflow?"
- "what does Godot call the thing RPG Maker handles through plugin commands?"

the system must:

- keep evidence grouped by pack
- avoid flattening one engine's conventions into another's terminology
- label pack-specific vocabulary explicitly
- preserve authority differences (`core-runtime`, `core-engine`, `core-blender`, `pipeline-tool`, etc.)
- prefer direct engine-truth sources before analogy or exemplar-pattern sources
- reduce confidence if the answer relies mainly on analogy rather than direct feature equivalence

Comparative answers should be treated as a distinct retrieval/answer mode, not as ordinary single-pack routing.


### 27.6 Inter-pack rollback and recovery

Cross-pack operations must follow the same transaction discipline as single-pack operations.

If a Blender -> Godot or other inter-pack pipeline partially completes, the system must be able to:
- identify which source artifacts were exported
- identify which target artifacts were created or updated
- roll back incomplete target-side promotion
- preserve source-side provenance and journals
- mark partially-completed transfers as recoverable rather than silently successful

At minimum, inter-pack flows must support:
1. `prepare`
2. `transfer/build`
3. `validate`
4. `promote`
5. `rollback`

A failed inter-pack transfer must never leave the target pack in a promoted-but-unverifiable state.

### 27.7 Extended Inter-Pack Pipelines

The platform now supports four canonical inter-pack pipelines beyond the core Blender -> Godot workflow:

#### 27.7.1 AI Generation Pipeline

Automated asset generation across packs using AI-assisted tooling.

- **Source**: `ml-educational-reference` / `agent-simulation` (AI models and patterns)
- **Transport**: `ai-generation` pipeline with `blender-mcp` and `godot-mcp`
- **Target**: `blender-engine` / `godot-engine` (generated assets and scenes)
- **Components**:
  - `blender-mcp` for procedural 3D generation
  - `godot-mcp` for scene population
  - Provenance tracking for AI-generated assets

Example workflow:
```json
{
  "recordType": "AIGenerationRecord",
  "sourcePack": "ml-educational-reference",
  "targetPack": "blender-engine",
  "generationType": "procedural-mesh",
  "prompt": "low-poly forest terrain with river",
  "pipelineTools": ["blender-mcp", "stable-diffusion-api"],
  "provenanceChain": ["ml-model:terrain-gen-v2", "blender-script:procedural-terrain.py"]
}
```

#### 27.7.2 Voice Animation Pipeline

Synchronizing voice/audio generation with character animation across packs.

- **Source**: `voice-audio-generation` (TTS, voice models)
- **Transport**: `voice-sync` pipeline with phoneme extraction
- **Target**: `godot-engine` / `blender-engine` (lip-sync animation, audio nodes)
- **Components**:
  - Phoneme extraction and timing data
  - Godot AnimationPlayer integration
  - Blender shape key animation

Example workflow:
```json
{
  "recordType": "VoiceAnimationRecord",
  "sourcePack": "voice-audio-generation",
  "targetPack": "godot-engine",
  "audioSource": "tts-output:character-dialogue.wav",
  "phonemeData": "phoneme-timeline.json",
  "animationTarget": "AnimationPlayer:face/mouth_shapes",
  "syncAccuracy": 0.95
}
```

#### 27.7.3 ML Deployment Pipeline

Deploying trained models from notebook workflows to runtime engines.

- **Source**: `notebook-data-workflow` (trained models, inference code)
- **Transport**: `ml-export` pipeline with format conversion
- **Target**: `godot-engine` / `agent-simulation` (runtime inference, NPC behavior)
- **Components**:
  - Model format conversion (ONNX, TensorFlow Lite)
  - Godot GDExtension integration
  - Performance profiling and optimization

Example workflow:
```json
{
  "recordType": "MLDeploymentRecord",
  "sourcePack": "notebook-data-workflow",
  "targetPack": "godot-engine",
  "modelFormat": "onnx",
  "sourceModel": "notebook:npc-behavior-model.pkl",
  "targetArtifact": "godot-addon:NPCBehaviorInference.gdextension",
  "inferenceLatency": "16ms",
  "accuracyMetrics": {"f1": 0.89, "precision": 0.91}
}
```

#### 27.7.4 Provenance Tracking System

All inter-pack pipelines are supported by a unified provenance tracking system:

- **ProvenanceTracker.ps1**: Central tracking of cross-pack artifact lineage
- **InterPackTransport.ps1**: Transport layer with rollback support
- **SnapshotManager.ps1**: Snapshot and recovery across pack boundaries

Required provenance fields:
- `sourcePack` and `targetPack` identifiers
- `sourceArtifact` and `targetArtifact` references
- `pipelineTool` chain for reproducibility
- `createdByRunId` for audit trail
- `derivationChain` for complex multi-hop pipelines

The provenance tracking system ensures that any artifact in a target pack can be traced back to its original source pack, enabling reproducibility, auditability, and rollback capabilities across the entire platform.

## 28. Final priority call (REVISED)

### ✅ All Phases 1-7 Complete

What is complete now:

- **Phase 1** — Operational core is implemented (`module/LLMWorkflow/core/`) with state integrity, operator trust, and safe operation policies
- **Phase 2** — Pack manifest, source registry, and lifecycle management implemented for 10 domain packs
- **Phase 3** — Operator workflow and guarded execution with transaction discipline
- **Phase 4** — Structured extraction pipeline with parsers for GDScript, scenes, shaders, APIs, notebooks, and more
- **Phase 5** — Retrieval and answer integrity with query routing, cross-pack arbitration, and confidence policies
- **Phase 6** — Human trust and governance with annotations, golden tasks, and review gates
- **Phase 7** — Platform expansion with MCP integration, inter-pack pipelines, and snapshot management

The platform now supports **10 domain packs**:
1. `rpgmaker-mz` — RPG Maker MZ game development
2. `godot-engine` — Godot Engine game development
3. `blender-engine` — Blender 3D asset creation
4. `api-reverse-tooling` — API reverse engineering
5. `notebook-data-workflow` — Data science and ML workflows
6. `agent-simulation` — AI agent and simulation frameworks
7. `voice-audio-generation` — Voice and audio AI generation
8. `engine-reference` — Cross-engine reference materials
9. `ui-frontend-framework` — UI and frontend development
10. `ml-educational-reference` — Machine learning education

### MCP Toolkit Servers Deployed

- `godot-mcp` — AI-assisted Godot editor control (✅ Operational)
- `blender-mcp` — AI-assisted Blender modeling control (✅ Operational)
- Composite gateway for multi-tool orchestration (✅ Implemented)

### Inter-Pack Pipelines Operational

1. **Blender -> Godot Scene Pipeline** — Asset export with provenance tracking
2. **AI Generation Pipeline** — Procedural asset generation across packs
3. **Voice Animation Pipeline** — TTS to lip-sync animation workflow
4. **ML Deployment Pipeline** — Model training to runtime inference

### Current Statistics

- **84 PowerShell modules** across all phases
- **800+ total functions**
- **Version 0.9.5**
- **All retrieval profiles** (7 profiles) operational
- **Golden task evaluation** framework active

### Risk statement

The biggest risk has been addressed through disciplined implementation:
- **State integrity**: file locking, atomic writes, schema versioning
- **Operator trust**: journaling, checkpoints, config explainability
- **Safe operation**: policy gates, execution modes, safety levels
- **Boundary control**: workspaces, visibility rules, secret scanning
- **Provenance tracking**: cross-pack lineage and rollback capabilities

The platform now maintains control of state, evidence, pack promotion, and private/public boundaries as it scales across multiple domain packs.

**See [PROGRESS.md](PROGRESS.md) and [PHASE5_PHASE6_IMPLEMENTATION_SUMMARY.md](PHASE5_PHASE6_IMPLEMENTATION_SUMMARY.md) for detailed implementation status.**
