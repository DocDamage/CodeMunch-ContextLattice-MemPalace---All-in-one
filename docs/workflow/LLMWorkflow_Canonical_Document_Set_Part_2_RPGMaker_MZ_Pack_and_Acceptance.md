# LLM Workflow — Canonical Architecture, Pack Framework, and Delivery Plan

## Status

**This is the canonical source-of-truth document.**  
It supersedes the earlier implementation plans, review passes, and RPG Maker pack review notes. Earlier documents should be treated as archived design history after this one is adopted.

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

### Scenario 16 — Cross-engine comparative answer mode
- comparative query keeps evidence grouped by pack (`rpgmaker-mz`, `godot-engine`, `blender-engine`)
- answer surfaces authority-role differences explicitly
- engine-specific terminology is not flattened into false equivalence
- confidence is reduced when the answer relies on analogy rather than direct feature equivalence

## 24. Historical priority snapshot (superseded by §28)

### Superseded status snapshot

This section is kept only as historical context. Use **§28 Final priority call (REVISED)** as the canonical roadmap/priorities section.

### ✅ Phase 1 Complete (2026-04-12)

The following highest-leverage foundational work is now complete:

1. ✅ journaling + checkpoints
2. ✅ file locking + atomic writes
3. ✅ effective-config explain/validate
4. ✅ policy and execution-mode enforcement
5. ✅ workspaces and visibility boundaries

**Implementation:** `module/LLMWorkflow/core/` - 16 PowerShell modules, 100+ functions

---

### Next: Phase 2-7 Priorities

The remaining highest-leverage work, in order:

6. pack manifest + source registry + lifecycle
7. pack transaction model + lockfile
8. structured extraction pipeline
9. canonical entity registry
10. query router + retrieval profiles
11. answer plan + trace
12. confidence + abstain policy
13. human annotations + replay
14. golden-task evals and feedback loop

---

### Risk Statement

The biggest risk is no longer lack of features.  
It is **losing control of state, evidence, pack promotion, and private/public boundaries as the system grows**.

Phase 1 implementation addresses this risk through:
- **State integrity**: File locking, atomic writes, schema versioning
- **Operator trust**: Journaling, checkpoints, config explainability
- **Safe operation**: Policy gates, execution modes, safety levels
- **Boundary control**: Workspaces, visibility rules, secret scanning

This document remains the canonical architecture intended to stop uncontrolled growth from happening.

**See [PROGRESS.md](../../docs/implementation/PROGRESS.md) for detailed implementation status.**

---
