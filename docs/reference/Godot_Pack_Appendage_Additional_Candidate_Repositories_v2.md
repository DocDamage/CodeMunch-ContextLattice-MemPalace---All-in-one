# Godot Engine Pack — Appendage A: Additional Candidate Repositories

This appendage adds **new Godot source candidates** that were not already listed in the canonical Godot pack section.
It preserves repo names and assigns each one a concrete role, extraction target set, routing fit, and evaluation purpose.

---

## A.1 Adoption summary

### Strong adds
These are the best immediate additions to the Godot pack.

- `MikeSchulze/gdUnit4`
- `limbonaut/limboai`
- `dialogic-godot/dialogic`
- `shomykohai/quest-system`
- `expressobits/inventory-system`
- `maximkulkin/godot-rollback-netcode`
- `godotengine/godot-git-plugin`
- `Ericdowney/SignalVisualizer`

### Useful optional adds
These are worth preserving and may be promoted depending on how broad the Godot pack becomes.

- `AdamKormos/SaveMadeEasy`
- `hohfchns/DialogueQuest`

---

## A.2 Source priority proposal

### P2 — High-value gameplay systems / tooling
- `MikeSchulze/gdUnit4`
- `limbonaut/limboai`
- `dialogic-godot/dialogic`
- `shomykohai/quest-system`
- `expressobits/inventory-system`
- `maximkulkin/godot-rollback-netcode`
- `godotengine/godot-git-plugin`

### P3 — Debugging / auxiliary systems / optional specialized workflows
- `Ericdowney/SignalVisualizer`
- `AdamKormos/SaveMadeEasy`
- `hohfchns/DialogueQuest`

---

## A.3 Repo-by-repo extraction target matrix

| Repo | Primary value | Must-extract | Authority role | Risk notes |
|---|---|---|---|---|
| `MikeSchulze/gdUnit4` | embedded Godot testing framework | test suite structure, assertions, mocking/spying APIs, scene runner patterns, Godot version compatibility table | `testing-framework` | version-sensitive across Godot 4.x; should dominate testing queries, not gameplay architecture |
| `limbonaut/limboai` | AI behavior trees + state machines | BT node/task patterns, state machine contracts, visual debugger hooks, demo/tutorial references, Godot version range | `ai-behavior-system` | powerful framework; do not treat as stock engine AI behavior |
| `dialogic-godot/dialogic` | dialogue/narrative framework | dialogue resources, character/timeline structures, updater/install path, unit-test references, public vs private API rules | `dialogue-system` | should not define stock Godot UI or scene behavior |
| `shomykohai/quest-system` | quest/progression framework | quest resource schema, singleton/modular API, localization hooks, serialization/deserialization patterns, GDUnit4 relationship | `quest-system` | version-boundary important; avoid treating as generic save-state authority |
| `expressobits/inventory-system` | modular inventory/RPG system | item/resource schemas, UI-logic separation, crafting/equipment/hotbar systems, multiplayer compatibility, grid inventory patterns | `inventory-system` | broad gameplay-system repo; should not dominate non-inventory gameplay questions |
| `maximkulkin/godot-rollback-netcode` | rollback/prediction networking | input/state save-load hooks, mismatch detection, sync manager API, rollback lifecycle, debugging tools | `networking-system` | fork lineage matters; must stay scoped to rollback multiplayer questions |
| `godotengine/godot-git-plugin` | editor VCS integration | Godot VCS interface mapping, libgit2 backend role, install/build path, editor integration surfaces, Godot version requirements | `editor-tooling` | not engine gameplay authority; editor/tooling-only |
| `Ericdowney/SignalVisualizer` | signal/debugging tooling | signal graph model, scene signal introspection, debugger integration, tree/graph navigation patterns | `debug-visualization` | useful for signal/debug queries only |
| `AdamKormos/SaveMadeEasy` | save/load plugin | key-path storage model, nested variable/resource/array handling, encryption behavior, AutoLoad requirements | `save-system` | convenience plugin; should not outrank stock save architecture or project-local save logic |
| `hohfchns/DialogueQuest` | lightweight dialogue system | dialogue file format, user/developer manual split, standalone tester workflow, collaboration patterns | `dialogue-system` | overlaps with `dialogic-godot/dialogic`; should remain secondary unless query matches its feature set directly |

---

## A.4 Authority constraints

The following constraints are mandatory:

- do not use `MikeSchulze/gdUnit4` to define generic Godot runtime behavior; it is testing authority, not engine-law authority
- do not use `limbonaut/limboai` as stock Godot AI architecture authority; it is a framework/plugin
- do not use `dialogic-godot/dialogic` or `hohfchns/DialogueQuest` to define canonical scene/UI behavior outside dialogue-system questions
- do not use `shomykohai/quest-system` to define general serialization or save architecture authority
- do not let `expressobits/inventory-system` dominate generic UI or multiplayer answers unless the question is inventory-related
- do not use `maximkulkin/godot-rollback-netcode` for general networking answers that are not specifically rollback/prediction related
- do not let `godotengine/godot-git-plugin` bleed into generic Git workflow answers outside Godot editor tooling
- do not use `Ericdowney/SignalVisualizer` as signal API authority; it is a visualization/debugging tool, not the source of signal semantics
- do not let `AdamKormos/SaveMadeEasy` outrank project-local save logic or official engine persistence guidance when the question is architectural
- do not let `hohfchns/DialogueQuest` outrank `dialogic-godot/dialogic` by default on general dialogue-system questions unless the query better matches its collaboration/tester workflow

---

## A.5 Retrieval routing additions

### Testing / QA questions
Preferred evidence order:
1. `godot_private_project`
2. `MikeSchulze/gdUnit4`
3. P0 official docs/source
4. project-specific CI/test infrastructure repos if present

### AI behavior / state machine questions
Preferred evidence order:
1. `godot_private_project`
2. `limbonaut/limboai`
3. P0 official docs/source
4. other AI/gameplay framework repos only if directly relevant

### Dialogue / narrative system questions
Preferred evidence order:
1. `godot_private_project`
2. `dialogic-godot/dialogic`
3. `hohfchns/DialogueQuest`
4. P0 docs/source only where needed for underlying engine surfaces

### Quest / progression questions
Preferred evidence order:
1. `godot_private_project`
2. `shomykohai/quest-system`
3. P0 docs/source
4. save/inventory/dialogue systems only if directly tied to the question

### Inventory / item / equipment / crafting questions
Preferred evidence order:
1. `godot_private_project`
2. `expressobits/inventory-system`
3. P0 docs/source
4. quest/save repos only if directly relevant

### Rollback multiplayer questions
Preferred evidence order:
1. `godot_private_project`
2. `maximkulkin/godot-rollback-netcode`
3. P0 docs/source
4. other multiplayer/networking sources only if directly relevant

### Git / editor VCS workflow questions
Preferred evidence order:
1. `godot_private_project`
2. `godotengine/godot-git-plugin`
3. P0 docs/source
4. generic Git docs only as fallback

### Signal debugging / graph inspection questions
Preferred evidence order:
1. `godot_private_project`
2. `Ericdowney/SignalVisualizer`
3. P0 docs/source

### Save/load convenience-plugin questions
Preferred evidence order:
1. `godot_private_project`
2. `AdamKormos/SaveMadeEasy`
3. P0 docs/source

---

## A.6 Repo-specific evaluation tasks

These should be added as stable Godot golden tasks.

### gdUnit4
- “When the user asks how to test GDScript scenes, does `MikeSchulze/gdUnit4` outrank generic editor/plugin sources?”
- “Does the system preserve Godot-version compatibility caveats from `gdUnit4` instead of pretending all 4.x versions behave the same?”

### LimboAI
- “When the user asks about behavior trees or state machines in Godot 4, does `limbonaut/limboai` outrank generic gameplay examples?”
- “Can the system explain why `LimboAI` is framework authority, not stock engine AI-law authority?”

### Dialogic
- “When the user asks about dialogue-driven RPG or VN workflows, does `dialogic-godot/dialogic` outrank unrelated UI/story repos?”
- “Does the system preserve the Godot 4.3+ compatibility boundary for Dialogic 2?”

### Quest System
- “When the user asks about modular quest resources, localization, or quest serialization, does `shomykohai/quest-system` outrank unrelated gameplay repos?”
- “Can the system mention that QuestSystem is tested with GDUnit4 without turning that into generic testing authority?”

### Inventory System
- “When the query is about hotbars, crafting, equipment, or RE4-style grid inventory, does `expressobits/inventory-system` outrank generic UI/gameplay examples?”
- “Can the system distinguish inventory logic authority from generic multiplayer or save/load authority?”

### Rollback Netcode
- “When the user asks about rollback/prediction netcode, does `maximkulkin/godot-rollback-netcode` outrank general networking answers?”
- “Does the system preserve the distinction between rollback-specific tooling and stock multiplayer patterns?”

### Godot Git Plugin
- “When the user asks about Git inside the Godot editor, does `godotengine/godot-git-plugin` outrank generic Git workflow docs?”
- “Can the system explain why this plugin is editor/VCS authority but not gameplay/runtime authority?”

### SignalVisualizer
- “When the user asks how to inspect or debug scene signal connections, does `Ericdowney/SignalVisualizer` outrank unrelated debugging tools?”
- “Does the system keep signal visualization separate from signal API truth?”

### SaveMadeEasy
- “When the user asks about encrypted nested-value save plugins, does `AdamKormos/SaveMadeEasy` appear only as a convenience-plugin answer rather than a canonical save-architecture answer?”

### DialogueQuest
- “When the user asks about writer/coder collaboration or standalone dialogue testing, does `hohfchns/DialogueQuest` surface as a secondary dialogue-system source alongside or beneath Dialogic?”

---

## A.7 Install-profile additions

### Add to `developer`
Recommended additions:
- `MikeSchulze/gdUnit4`
- `limbonaut/limboai`
- `dialogic-godot/dialogic`
- `shomykohai/quest-system`
- `expressobits/inventory-system`
- `maximkulkin/godot-rollback-netcode`
- `godotengine/godot-git-plugin`
- `Ericdowney/SignalVisualizer`

### Add to `full`
Recommended additions:
- all `developer` additions
- `AdamKormos/SaveMadeEasy`
- `hohfchns/DialogueQuest`

### Keep out of `minimal`
Do not add these to `minimal` by default. They are valuable, but they are not foundational enough to justify the extra weight in the smallest profile.

---

## A.8 Recommendation

If you are adding them now, the cleanest order is:

1. `MikeSchulze/gdUnit4`
2. `limbonaut/limboai`
3. `dialogic-godot/dialogic`
4. `shomykohai/quest-system`
5. `expressobits/inventory-system`
6. `maximkulkin/godot-rollback-netcode`
7. `godotengine/godot-git-plugin`
8. `Ericdowney/SignalVisualizer`
9. `AdamKormos/SaveMadeEasy`
10. `hohfchns/DialogueQuest`

That gives you:
- testing
- AI behavior
- dialogue
- quests
- inventory
- rollback networking
- editor VCS tooling
- signal debugging
- save convenience
- optional second dialogue system

without adding random junk.


---

## A.9 Additional candidate repositories (second pass)

These repos add more coverage in areas that were still relatively thin:
- RPG data-model frameworks
- chunk/open-world streaming
- alternate voxel terrain implementations
- platform/backend service integration
- lightweight FSM-only patterns

### Strong adds
- `bitbrain/pandora`
- `SlashScreen/chunx`

### Useful optional adds
- `Syntaxxor/godot-voxel-terrain`
- `GamePushService/GamePush-Godot-plugin`
- `HexagonNico/Godot-FiniteStateMachine`

---

## A.10 Source priority additions

### P2 — High-value gameplay/data systems
- `bitbrain/pandora`
- `SlashScreen/chunx`

### P3 — Specialized alternatives / service integrations / lightweight frameworks
- `Syntaxxor/godot-voxel-terrain`
- `GamePushService/GamePush-Godot-plugin`
- `HexagonNico/Godot-FiniteStateMachine`

---

## A.11 Repo-by-repo extraction target matrix (second pass)

| Repo | Primary value | Must-extract | Authority role | Risk notes |
|---|---|---|---|---|
| `bitbrain/pandora` | RPG data-management framework | item/inventory/spell/mob/quest/NPC schemas, resource/data model, editor workflow, save/data boundaries | `rpg-data-framework` | broad RPG scope; should not become stock engine authority |
| `SlashScreen/chunx` | chunk/open-world streaming | chunk lifecycle, streaming triggers, world partition patterns, load/unload contracts, Godot 4 integration assumptions | `world-streaming-system` | should stay scoped to streaming/open-world questions |
| `Syntaxxor/godot-voxel-terrain` | alternate voxel terrain implementation | terrain chunk model, editor tooling, mesh generation, collision, save/load, GDExtension boundaries | `visual-system` | overlaps with `Zylann/godot_voxel`; keep as alternative source, not default voxel authority |
| `GamePushService/GamePush-Godot-plugin` | backend/platform service integration | achievements, analytics, ads, events, leaderboards, payments, storage, rewards, service API surface | `platform-service-integration` | broad services plugin; do not let it dominate unrelated gameplay/system answers |
| `HexagonNico/Godot-FiniteStateMachine` | lightweight FSM framework | node-based FSM/state structure, transition hooks, editor integration, Godot 4 plugin assumptions | `ai-behavior-system` | overlaps with `limbonaut/limboai`; should remain the lightweight FSM-specific alternative |

---

## A.12 Authority constraints (second pass)

The following constraints are mandatory:

- do not use `bitbrain/pandora` to define canonical Godot save/data architecture outside RPG data-framework questions
- do not use `SlashScreen/chunx` to define generic scene-loading or level-transition authority outside chunk/open-world streaming questions
- do not let `Syntaxxor/godot-voxel-terrain` outrank `Zylann/godot_voxel` by default unless the query is better matched to its addon/GDExtension/editor workflow
- do not use `GamePushService/GamePush-Godot-plugin` as generic backend or multiplayer authority; it is platform-service integration authority
- do not let `HexagonNico/Godot-FiniteStateMachine` outrank `limbonaut/limboai` on broad AI architecture questions unless the query is explicitly about lightweight FSM-only patterns

---

## A.13 Retrieval routing additions (second pass)

### RPG data / items / spells / mobs / quest-schema questions
Preferred evidence order:
1. `godot_private_project`
2. `bitbrain/pandora`
3. `expressobits/inventory-system`
4. `shomykohai/quest-system`
5. P0 docs/source

### Chunk streaming / open-world loading questions
Preferred evidence order:
1. `godot_private_project`
2. `SlashScreen/chunx`
3. P0 docs/source
4. terrain/world repos only if directly relevant

### Alternate voxel terrain / in-editor voxel editing questions
Preferred evidence order:
1. `godot_private_project`
2. `Zylann/godot_voxel`
3. `Syntaxxor/godot-voxel-terrain`
4. P0 docs/source

### Platform services / achievements / ads / analytics / leaderboards / payments questions
Preferred evidence order:
1. `godot_private_project`
2. `GamePushService/GamePush-Godot-plugin`
3. `GodotSteam/GodotSteam` when the query is Steam-specific
4. P0 docs/source

### Lightweight FSM-only questions
Preferred evidence order:
1. `godot_private_project`
2. `HexagonNico/Godot-FiniteStateMachine`
3. `limbonaut/limboai`
4. P0 docs/source

---

## A.14 Repo-specific evaluation tasks (second pass)

### Pandora
- “When the user asks about RPG data schemas for items, spells, mobs, quests, or NPCs, does `bitbrain/pandora` outrank unrelated gameplay repos?”
- “Can the system explain why `pandora` is a data-framework authority rather than stock engine authority?”

### Chunx
- “When the user asks about open-world chunk loading or world streaming, does `SlashScreen/chunx` outrank generic scene-loading examples?”
- “Does the system keep chunk streaming authority separate from generic level-loading authority?”

### Syntaxxor voxel terrain
- “When the user asks about in-editor voxel terrain editing in Godot 4, does `Syntaxxor/godot-voxel-terrain` surface as an alternative to `Zylann/godot_voxel` rather than disappearing?”
- “Can the system explain the overlap without flattening both voxel repos into one fake source?”

### GamePush plugin
- “When the query is about achievements, analytics, ads, leaderboards, payments, or cloud-style storage, does `GamePushService/GamePush-Godot-plugin` outrank unrelated gameplay repos?”
- “Does the system avoid treating GamePush as generic backend or networking authority?”

### HexagonNico FSM
- “When the query is explicitly about lightweight node-based FSM patterns, does `HexagonNico/Godot-FiniteStateMachine` outrank `limbonaut/limboai`?”
- “When the query is broad AI architecture, does `limbonaut/limboai` still outrank the FSM-only plugin?”

---

## A.15 Install-profile additions (second pass)

### Add to `developer`
Recommended additions:
- `bitbrain/pandora`
- `SlashScreen/chunx`

### Add to `full`
Recommended additions:
- all `developer` additions
- `Syntaxxor/godot-voxel-terrain`
- `GamePushService/GamePush-Godot-plugin`
- `HexagonNico/Godot-FiniteStateMachine`

### Keep out of `minimal`
Do not add these to `minimal` by default. They are useful, but they are too domain-specific for the smallest profile.

---

## A.16 Updated recommendation order

If you are adding this second batch now, the clean order is:

1. `bitbrain/pandora`
2. `SlashScreen/chunx`
3. `Syntaxxor/godot-voxel-terrain`
4. `GamePushService/GamePush-Godot-plugin`
5. `HexagonNico/Godot-FiniteStateMachine`

This adds:
- RPG data framework coverage
- chunk/open-world streaming
- an alternate voxel terrain implementation
- platform-service integration
- a lightweight FSM-only option

without turning the pack into random addon soup.
