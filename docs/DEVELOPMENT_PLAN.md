# Amy and the Rain Forest — Development Plan

**Status:** proposal for review · **Owner:** Jason Duffett · **Last updated:** 2026-10-06 (revision 3: adds the story model and ubiquitous language, section 2.4; revision 2 followed an independent critique, see `docs/plan-review/`)

This plan turns the current proof of concept into a publicly released Roblox
game that can be continually expanded by an autonomous agent, with every
change proven by tests before a human looks at it.

It answers five requirements:

1. Release the game to the public.
2. Keep a **Dev** channel and a **Release** channel so new versions are tested
   before players see them.
3. A strong automated test harness so an agent can build and test changes
   on its own.
4. Hand a capable agent a high-level task and get back a large set of
   new, proven features for review, with no intermediate guidance.
5. Reach and sustain a very high quality of gameplay, with continual
   enhancement and extension.

Decisions already agreed are in the log at the end. In short: personal
Roblox account, two separate experiences for Dev and Release, Open Cloud
keys as GitHub secrets, ages 7–12 and family-friendly, strictly free, PC,
phone and tablet, single player first, exploration + animal companions + light
puzzles, new chapters + collectibles as the retention loop, agent drafts
story in Clara's voice for approval with her original text untouched, free
assets and Clara's illustrations, review by playing Dev plus reading the
PR, one chapter or feature set per PR, on-demand agent runs plus a nightly
Dev build, and a MacBook self-hosted runner that may not always be on.

One honest limit, stated up front: **the agent runs on Linux and can
neither see nor hear the game.** Correctness, reachability, performance
budgets and story logic can be proven headlessly. Look, feel, pacing and
audio mix cannot, though with the Mac awake the agent can assert a good
deal about what is on screen, diff frames against baselines, and look at
the pictures itself before you do. The plan separates those two kinds of work (section 5.4)
and makes the perceptual loop depend on the Mac being awake and on your
eyes, rather than pretending it is autonomous.

---

## 1. Where we are

| Area | Today |
|---|---|
| Code | 4 Luau files, ~2.5k lines: `StoryData`, `WorldBuilder`, `StoryServer`, `StoryClient` |
| Build | `tools/build_rbxlx.py` packs the scripts into a committed `.rbxlx`; Rojo project exists but is not the build path |
| World | Entirely procedural parts, no terrain, no meshes, no textures |
| Characters | Blocky part figures, no rigs or animations |
| Audio | None |
| Saves | None; story restarts every session |
| Platforms | PC keyboard only (E to interact) |
| Multiplayer | World state (NPC prompts, Sam's position, the machine, lighting) is **shared and mutated per player**, so a second player in the same server breaks the story |
| Tests | None |
| CI / publishing | None; publish is a manual Studio step |
| Roblox presence | Not published |

The engine works and the story is intact. Everything else is missing, and
the current shape (one 1,100-line server script with world, quests and NPC
behaviour interleaved) is why each new feature is expensive. The plan is
not to rewrite the game, but to **re-house the working logic into a
modular, testable structure first, under a characterization test that
proves behaviour is unchanged**, then grow it.

---

## 2. Target architecture

### 2.1 Principle: a pure core with thin engine adapters

Everything that can be expressed as plain Luau data and functions lives in
a core that never touches Roblox instances. That core is fully testable on
Linux in under a minute using Lune. Only a thin adapter layer talks to the
Roblox engine, and that layer is tested in the real engine through Open
Cloud and in Studio on the Mac.

```
┌───────────────────────────────────────────────────────────────┐
│ Content = data + hooks                                        │
│  chapters/<n>/data.luau · chapters/<n>/hooks.luau             │
│  scenes/*.luau · collectibles · assets manifest               │
├───────────────────────────────────────────────────────────────┤
│ Core (pure Luau, no Instances)                                │
│  StoryEngine (quest state machine) · DialogueViewModel        │
│  ObjectiveText · ChapterCardTimeline · SaveSchema+migrations  │
│  CompanionLogic · PuzzleLogic · Net contract (payload schemas)│
├───────────────────────────────────────────────────────────────┤
│ Engine adapters (Roblox APIs)                                 │
│  Server: SceneBuilder, NpcController, PromptBridge, Persist,  │
│          World interface used by chapter hooks                │
│  Client: UI binder, Input, Audio, Camera, Effects             │
├───────────────────────────────────────────────────────────────┤
│ Shared: Net (thin typed remotes), Config, AssetIds (generated)│
└───────────────────────────────────────────────────────────────┘
```

Rules that keep this honest, and that the tests enforce:

- `src/core/**` and `src/content/**` must not reference `game`,
  `Instance`, or any service. Roblox datatypes (`Vector3`, `Color3`) are
  allowed in core but content stores positions and colours as plain tables
  (`{x, y, z}`, `{r, g, b}`) converted in the adapter, so content loads
  under Lune with no bootstrap tricks. A lint rule and a Lune smoke test
  fail the build on violations.
- The server adapter drives the core through a small interface
  (`StoryEngine.new(playerId, saveData)`, `:handle(event)`, `:snapshot()`),
  so a test can replace the player with a plain table.
- **Client logic lives in core too.** The dialogue queue, line index,
  visible-grapheme count, speaker style, objective text and chapter-card
  timeline are a pure view-model, unit-tested in Lune. The client script is
  a binder that renders the view-model and forwards input. This is how
  client bugs get caught without a client.
- **A chapter is data plus hooks, not data only.** Each chapter so far needs
  bespoke moments (Sam dragging Amy back, Sam leaving for the farm, the
  paradise reveal, the machine arriving and stopping). Those live in a
  per-chapter `hooks.luau` exporting `onQuestStart` / `onQuestComplete`
  handlers that receive a `World` interface (move NPC, set lighting preset,
  play cue, spawn pickup). The pure parts stay in core, the engine calls in
  the adapter, and tier 0 checks that every hook named in data exists.
- **Single player is an invariant.** The experience is configured with
  Max Players = 1, tier 2 asserts it, and a tier 2 test runs two fake
  players at different chapters to prove the engine would not cross-talk if
  the setting were ever lost. Co-op (Phase 2 spike) is a redesign that
  instances NPCs, prompts and lighting per player, not a toggle.
- **Amy's face is never seen.** This is a quirk of Clara's story and an
  invariant from the first release onward: the player always sees Amy
  from behind, the camera stays locked behind her, and no Shot, chapter
  card, illustration, icon, thumbnail or reflection shows her face. The
  camera system is built around it (section 2.3), tier 3 asserts it at
  every Shot and throughout a playthrough, and the release checklist
  covers the store assets. The proof of concept does not yet follow it;
  Phase 1 makes it true. Future chapters may play with the rule (a mirror
  that still does not show her face), never break it.

### 2.2 Repository layout after Phase 0

```
.
├── default.project.json      Rojo project (the only build path)
├── rokit.toml                Toolchain pins: rojo, lune, wally, stylua, selene, luau-lsp
├── wally.toml                Packages: ProfileStore (+ an in-engine test runner)
├── selene.toml / stylua.toml Lint and format config
├── .luaurc                   Strict type mode
├── CLAUDE.md                 Agent conventions, commands, definition of done
├── src/
│   ├── core/                 Pure Luau (StoryEngine, DialogueViewModel, Save, Companions, Puzzles, Net contract)
│   ├── content/              Chapters (data + hooks), scenes, dialogue, collectibles
│   ├── server/               ServerScriptService adapters
│   ├── client/               StarterPlayerScripts binder and UI
│   └── shared/               Net, Config, generated AssetIds
├── tests/
│   ├── lune/                 Tier 1: runner (~150 lines) + core and content tests
│   ├── engine/               Tier 2: Luau Execution tests (in-engine runner)
│   ├── fixtures/             Shared: chapter fixtures, fake player, event scripts, golden files
│   └── studio/               Tier 3 (Mac): scripted playthrough, screenshots, stats
├── assets/
│   ├── manifest.json         Local file → Roblox asset id, kind, creator, licence, moderation status
│   └── images|audio|meshes/  Sources (Clara's illustrations, SFX, music, .rbxm models)
├── tools/
│   ├── build.sh              rojo build → build/AmyAndTheRainforest.rbxl
│   ├── publish.lune          Open Cloud place publish (Saved or Published); refuses Release IDs unless RELEASE=1
│   ├── run-engine-tests.lune Open Cloud Luau Execution runner
│   ├── upload-assets.lune    Assets API uploader, run only by CI (workflow_dispatch)
│   ├── fetch-model.lune      Creator Store model → assets/meshes/*.rbxm (see 5.5)
│   └── studio-playtest/      Mac runner scripts (Studio MCP wrapper, screencapture)
├── docs/
│   ├── DEVELOPMENT_PLAN.md   This document
│   ├── GLOSSARY.md           The ubiquitous language (section 2.4); source of the content schema
│   ├── DEFINITION_OF_DONE.md What every PR must satisfy
│   ├── RELEASE_CHECKLIST.md  Human promotion checklist, Dev → Release
│   ├── design/feel.md        Camera, input affordances, text rules, onboarding
│   ├── screens/              One baseline screenshot per scene (tier 3 diffs against these)
│   ├── story/
│   │   ├── canon.md          Clara's original text, locked
│   │   ├── style-guide.md    Voice, spelling rules, what is off limits
│   │   └── proposals/        New chapters awaiting approval
│   ├── plan-review/          Critiques of this plan and responses
│   └── tasks/                High-level task briefs for the agent
└── .github/workflows/        ci.yml, publish-dev.yml, release.yml, nightly.yml, studio.yml, upload-assets.yml
```

The committed `AmyAndTheRainforest.rbxlx` and `tools/build_rbxlx.py` are
retired: CI builds the place file from source and attaches it to every PR
and release as a downloadable artifact.

Dependencies are kept deliberately small for a ~3k-line game: the toolchain
above, ProfileStore for saves, and one in-engine test runner. Promise,
signal and typed-remote libraries are replaced by ~100 lines of wrappers we
own. A UI framework (Fusion or React-Lua) is adopted only when a screen
actually needs reactive state; the Phase 1 screens do not.

### 2.3 Gameplay architecture additions

| System | Approach |
|---|---|
| Saves | DataStore via ProfileStore, keyed by Roblox user id so progress follows the account across PC, phone and tablet. **Progress is written on every Story event** (quest started or completed, collectible found, bond changed) and on leave, so a player who quits mid-chapter resumes at their current Quest, not at the chapter start. Resuming re-establishes the world from Progress alone (see **Resume** in 2.4): Sam at the farm, the machine on the field, the paradise lit. One save slot per player with a "start again" option behind a confirmation; chapter select for completed chapters arrives in Phase 2. Schema in `core/Save`, versioned with migrations and a unit test per migration, plus a tolerance test that old code can read a one-version-newer save (so Release can roll back one schema version). Dev and Release have separate stores, so Dev progress never carries over. Store names carry a prefix from config so tests never touch tester data. |
| Player identity | The player **is Amy**: a forced `HumanoidDescription` (free catalog items, body colours from Clara's palette). Decided now because dialogue speaker labels and the camera depend on it. |
| Input | `ContextActionService` with touch buttons on phone and tablet; proximity prompts stay the universal "talk" affordance. UI scales via `UIScale` + safe-area insets with separate layouts for the three **device classes** below; a minimum dialogue text size on a 6-inch phone and a maximum line length on a 13-inch tablet are specified in `docs/design/feel.md`. |
| Device classes | Three first-class targets, each with its own UI layout, touch-target rules and test coverage: **PC** (keyboard and mouse, gamepad later), **Phone** (small touch screen, portrait and landscape), **Tablet** (large touch screen, landscape first; iPad and Android tablets). Tablet is not "a big phone": thumbs reach from the edges, so controls sit at the corners, dialogue is centred and wider, and text is scaled to viewing distance rather than screen size. The client binder picks the class from screen size and input type, and every screen is laid out for all three. |
| UI | Plain Roblox UI driven by the core view-model. Dialogue, objectives, chapter cards, journal, settings, pause. |
| Audio | `AudioManager` with named cues from the manifest; music per scene with crossfades; SFX for prompts, pickups, footsteps. Narration (see section 7) as the largest quality lever for non-fluent readers. |
| World | Scenes as data (terrain instructions, placed models, zones, spawn points) built by `SceneBuilder`. Meshes and models checked in as `.rbxm` under `assets/meshes` and referenced by id in the manifest. |
| Characters | Phase 1: R15 avatars from `HumanoidDescription` with Roblox's built-in animation set; Sam's catch is a `Humanoid:MoveTo` chase with the built-in run animation; animals from free Creator Store rigs that ship with animations. Custom rigs and keyframed animations are Phase 2 and are explicitly a human-in-Studio task. |
| Companions | Animals as followers with simple state machines (idle, follow, react, lead to point of interest); logic in core, movement in adapter. |
| Collectibles | Data-driven (`content/collectibles`), journal UI, counts persisted, cosmetic rewards only. |
| Puzzles | Small declarative puzzle types (order of actions, find and place, follow the animal) in core with engine triggers in adapters. No failure states; hints after a delay. |
| Camera | A custom follow camera that stays in Amy's rear hemisphere at all times: the player may turn the view, and Amy turns with it, so she is always seen from behind (the same feel as Roblox's shift-lock, on every device class). Every Shot (forest-wall reveal, meeting each animal, the machine finale, the dialogue two-shot) is framed from behind or over Amy's shoulder; a Shot that would show her face is not a valid Shot. Specified in `docs/design/feel.md`. |
| Analytics | Roblox Analytics custom events: chapter start/complete, quest complete, collectible found, session length. |

### 2.4 The story model: one language for the story, the code and the conversation

Everything in this game is a story being told through a world. The code
should say so. This section defines the **ubiquitous language**: the
single set of nouns and verbs used by Clara's story, the content files,
the core modules, the tests, the task briefs, the PR descriptions, the
analytics events and our conversations. When you say "add a Beat after
Amy meets the Fox where Sam gets jealous", that sentence names the exact
type, file, hook and test involved, and the agent needs no translation.

The model is grounded in what the proof of concept already does
(chapters, quests of kind talk / reach / collect, zones, dialogue,
objectives, scripted moments keyed by quest id). It gives those things
proper names and adds the few concepts Phases 1 and 2 need.

#### The nouns

```
Story
 └─ Chapter (card, checkpoint)
     └─ Quest (kind, objective, intro, outro, hooks)
         ├─ Dialogue ── Line (speaker, text, canon?)
         └─ Beat (named sequence of World commands)

Scene (look + sound)                     Player
 ├─ Spot   (named place)                  ├─ Progress (where they are in the Story)
 ├─ Zone   (named volume)                 ├─ Journal  (what they have found)
 ├─ Prop   (object with states)           └─ Bonds    (with Companions)
 ├─ Character (home Spot, kind)
 │    └─ Companion (follows, helps, bond)
 ├─ Pickup / Collectible
 └─ Cue, Shot, Lighting preset
```

| Term | Meaning | Today's equivalent | Example |
|---|---|---|---|
| **Story** | The whole experience: ordered Chapters plus the Ending. There is one. | `StoryData` | Amy and the Rain Forest |
| **Chapter** | A titled part of the Story with a card (title, subtitle), an ordered list of Quests, and a checkpoint at its start. | `StoryData.Chapters[i]` | `chapter2` "The Unexplored World" |
| **Quest** | One objective the player must complete. Has a **Kind**, an Objective line, optional intro and outro Dialogue, and Hooks. | quest entries | `chapter1.sneak_out_1` |
| **Kind** (of Quest) | How the Quest is completed: `talk`, `reach`, `collect` today; `follow`, `place`, `solve` later. Each Kind is one small module in core. | `type` | `reach` |
| **Dialogue** | An ordered list of Lines shown together. | `intro`, `dialogue`, `onComplete` | the five Lines when Amy asks Dad |
| **Line** | One thing said: Speaker, text, optional narration audio. **Canon** Lines are Clara's exact words and are locked. | `{ speaker, text }` | Narrator: "She tryed again but Sam brang her back." |
| **Speaker** | Who says a Line: Amy, the Narrator, or a Character. | `speaker` | `Narrator` |
| **Beat** | A named, staged moment: a fixed sequence of World commands played at a Hook. Beats are how the story *moves the world*. | `samCatches`, `samGoesToFarm`, `paradiseReveal`, `machineArrives`, `machineStops` | `beat:sam_catches` |
| **Hook** | A point in a Quest's life where Beats run: `onStart`, `onComplete`. Declared in the chapter's `hooks.luau`. | `questStartedHooks[...]`, `onComplete` | `chapter1.sneak_out_1.onComplete → sam_catches` |
| **Scene** | A region of the world with its own look and sound: terrain, Props, Spots, Zones, ambience, music. | implicit in `WorldBuilder` | Garden, Village, Field, Forest Wall, Paradise, Heart Glade |
| **Spot** | A named position and facing inside a Scene. Content never holds raw coordinates; it names Spots. | `position`, `faceZ`, `spawnPoints` | `spot:GardenGateInside` |
| **Zone** | A named invisible volume the player can enter. Entering one is a Player event. | `zone` | `zone:ForestGap` |
| **Prop** | A placed object with named states. | the house, the machine | `prop:Machine` states `parked`, `advancing`, `stopped` |
| **Character** | A named being in the world with a Kind (human, dog, squirrel, fox, lion), a display name and a home Spot. Amy is the **Player Character**. | `NPCs` | `character:Sam` "Sam the Dog" |
| **Companion** | A Character that can follow Amy, help her, and whose **Bond** with her grows. | Sam (partly) | Sam, later Squirrel, Fox, Lion |
| **Bond** | A Companion's relationship level with Amy: `stranger` → `curious` → `friend` → `companion`. Persisted. | none | Fox at `friend` |
| **Pickup** | A quest-bound thing to touch, spawned at Spots for a `collect` Quest and gone when the Quest ends. | pickups | three glowing flowers |
| **Collectible** | A persistent discoverable with a Journal entry. Found once, remembered forever. | none | `collectible:maroon_acorn` |
| **Journal** | The player's record of Collectibles found and Characters met, with entries in Clara's voice. | none | |
| **Cue** | A named sound, music track or effect, resolved to an asset through the manifest. | none | `cue:sam_bark`, `music:paradise_theme` |
| **Shot** | A named camera framing used by a Beat or a Dialogue. | none | `shot:ForestWallReveal` |
| **Lighting preset** | A named look for a Scene. | `paradiseReveal` / `ordinaryWorld` | `lighting:paradise` |
| **Progress** | Where a player is in the Story: current Chapter and Quest, completed Quest ids, Pickup counts, Collectibles, Bonds, Prop states that matter (machine present or not). This is what gets saved, on every Story event and on leave. | `getState(player)` | |
| **Resume** | Rebuilding the world for a returning player from Progress alone: `StoryEngine.resume(progress)` returns the World commands that put every Character, Prop, lighting preset and Pickup where the current Quest expects them, then shows the objective. "Continue" on the title screen is a Resume at the current Quest. | none | |
| **Checkpoint** | The Progress snapshot taken at a Chapter start, kept alongside current Progress; "Play this chapter again" restarts from it. | none | |
| **World** | The one interface the core uses to act on the engine. Every Beat is written against it. | scattered engine calls | `World.moveCharacter(id, spot)` |

#### The verbs

The core is a pure function of events:

```
StoryEngine.step(progress, playerEvent) → progress', storyEvents[], worldCommands[]
```

- **Player events** come *in* from the adapter, in the player's terms:
  `EnteredZone(zone)`, `TalkedTo(character)`, `TouchedPickup(pickup)`,
  `DialogueFinished`, `FoundCollectible(collectible)`,
  `SolvedStep(puzzle, step)`.
- **Story events** go *out* as facts about the story: `ChapterStarted`,
  `QuestStarted`, `QuestCompleted`, `ChapterCompleted`, `BeatPlayed`,
  `CollectibleFound`, `BondChanged`, `StoryEnded`. Their names are also the
  analytics event names and the names used in test descriptions.
- **World commands** go *out* as instructions to the engine:
  `ShowDialogue`, `SetObjective`, `ShowChapterCard`, `MoveCharacter`,
  `TeleportPlayer`, `SetPropState`, `PlayCue`, `SetLighting`, `FrameShot`,
  `SpawnPickups`, `ClearPickups`, `SaveProgress`, `SaveCheckpoint`.

A Beat is a list of World commands with optional waits. A Hook maps a
Quest moment to Beats. The server adapter's only jobs are to turn engine
signals into Player events, feed them to `step`, and execute the returned
World commands. The client binder's only jobs are to render the commands
that reach it and to send `DialogueFinished` back.

This is also what makes the tests readable in the same language. The
characterization golden file from Phase 0 is literally the sequence of
World commands for a full playthrough. A unit test reads:

```
describe("chapter1.sneak_out_1", function()
  it("plays beat sam_catches and teleports Amy to spot GardenInside on EnteredZone(GardenGate)", ...)
end)
```

#### Lifecycles

| Thing | States |
|---|---|
| Chapter | `locked` → `active` → `completed` |
| Quest | `pending` → `active` → `completed` |
| Bond | `stranger` → `curious` → `friend` → `companion` |
| Prop | declared per Prop, e.g. Machine: `absent` → `advancing` → `stopped` → `retreating` |
| Collectible (per player) | `hidden` → `found` |

#### Where each concept lives

| Concept | Content (data) | Core (logic) | Adapter (engine) | Tests |
|---|---|---|---|---|
| Chapter, Quest, Dialogue, Line | `content/chapters/<n>/data.luau` | `core/StoryEngine`, `core/quests/<kind>.luau` | `server/StoryHost` | tier 1 walkthroughs, canon test |
| Beat, Hook | `content/chapters/<n>/hooks.luau` | `core/Beat` (sequencing) | `server/WorldImpl` executes commands | tier 1 (commands emitted), tier 2 (world changed) |
| Scene, Spot, Zone, Prop | `content/scenes/<scene>.luau` | `core/SceneSchema` | `server/SceneBuilder` | tier 0 schema, tier 2 build + reachability |
| Character, Companion, Bond | `content/characters.luau` | `core/Companion` | `server/CharacterHost` | tier 1 bond logic, tier 2 follow |
| Pickup, Collectible, Journal | `content/collectibles.luau` | `core/Journal` | `server/PickupHost`, `client/JournalView` | tier 1 |
| Cue, Shot, Lighting preset | `assets/manifest.json`, `content/presets.luau` | names only | `client/Audio`, `client/Camera`, `server/Lighting` | tier 0 manifest, tier 3 screenshots |
| Progress, Checkpoint | | `core/Save` (schema, migrations) | `server/Persist` (ProfileStore) | tier 1 migrations, tier 2 lock release |
| Player events, Story events, World commands | | `core/Events` (types + payload schemas) | `shared/Net` | tier 2 remote contract |

#### Rules that keep the language ubiquitous

1. **One name per concept, everywhere.** The same word appears in content
   keys, Luau type names, module names, test descriptions, analytics event
   names, briefs, PR text and conversation. No synonyms: it is `Character`,
   not NPC, actor or figure; `Zone`, not trigger or region; `Beat`, not
   cutscene, sequence or special. The current `npc` field becomes
   `character` in the Phase 0 refactor.
2. **Ids read like the language.** `chapter3.meet_fox`, `zone:ForestGap`,
   `beat:sam_catches`, `cue:sam_bark`, `spot:HeartGladeCentre`. A reference
   from one concept to another is always by id, never by position or raw
   coordinate.
3. **The glossary is the schema.** `docs/GLOSSARY.md` holds this table and
   is the source for the content schema that tier 0 validates: Quest Kinds,
   Speakers, Zone names, Cue names and Hook names are enumerations derived
   from it. A new noun or verb enters the glossary in the same PR that
   introduces it in code, and the PR description uses it.
4. **Content is written in the language, not in engine terms.** A chapter
   file never mentions parts, CFrames, prompts or remotes. If a Beat needs
   something the World interface cannot do, the interface grows by one
   named command, and the glossary records it.
5. **Briefs and reviews use the language.** A brief says "Chapter 5 has four
   Quests; Quest 2 is a `follow` Quest where Companion Fox leads Amy to
   Spot FireflyPool; its `onComplete` Hook plays Beat `fireflies_rise` and
   places Collectible `firefly_jar`." A review comment says "Beat
   `fireflies_rise` should FrameShot `FireflyPoolWide` before PlayCue."
6. **Canon is a property of a Line, not a file.** Any Line marked canon is
   checked byte for byte against `docs/story/canon.md`. New Lines in
   Clara's voice are not canon until she says so.

#### A worked example

You say: *"When Amy meets the Fox, Sam should be a bit jealous."*

In the language that is: add a Beat to the `onComplete` Hook of Quest
`chapter3.meet_fox`. The agent then:

- adds `beat:sam_jealous` to `content/chapters/3/hooks.luau`:
  `MoveCharacter(Sam, spot:FoxGladeEdge)`, `PlayCue(sam_whine)`,
  `ShowDialogue` with two new non-canon Lines for Sam and Amy;
- adds `spot:FoxGladeEdge` to `content/scenes/paradise.luau` and
  `cue:sam_whine` to the asset manifest;
- adds a tier 1 test: given Progress at `chapter3.meet_fox`, on
  `TalkedTo(Fox)` then `DialogueFinished`, the World commands include
  `PlayCue(sam_whine)` and `BeatPlayed(sam_jealous)` is emitted;
- tier 2 confirms `spot:FoxGladeEdge` is reachable and the cue resolves;
- the PR description says exactly the sentence above, plus "two new Lines,
  not canon, for approval".

Nothing in that exchange needed the words part, remote, prompt or script.
That is the test of whether the language is working.

---

## 3. Channels: Dev and Release

Two separate experiences on your Roblox account, each with its own
universe ID, place ID, DataStores and analytics:

| Channel | Visibility | Who plays | What lands here |
|---|---|---|---|
| **Dev** | Friends | You, Clara, invited testers (they must be friends of the owning account; note under-13 friend restrictions if Clara's own account is used) | Every merge to `main`, published automatically |
| **Release** | Public | Everyone | Only builds you promote, via a GitHub release with a manual approval gate |

Flow of a change:

```
PR opened/updated ──► branch must be up to date with main (merge queue or "require branches up to date"),
                      so what is tested is what will land
                  ──► CI: lint, types, unit tests, build → artifact
                  ──► publish build to Dev as a *Saved* version (not visible to players)
                  ──► engine tests via Luau Execution against that exact version
                  ──► (Mac awake?) Studio playthrough + screenshots attached to PR
Merge to main     ──► publish to Dev as *Published*  → you play it
Promote           ──► tag vX.Y.Z → release workflow downloads the artifact built at that tag by SHA,
                      verifies its checksum; GitHub "release" environment requires your approval;
                      tier 3 must have run on this build; checklist ticked
                  ──► publish that same file to Release as *Published*
                  ──► GitHub Release created with changelog and the .rbxl
Rollback          ──► re-run the release workflow with a previous tag (allowed across at most one save-schema version)
                      Reverting in the Roblox dashboard is not used: it is unaudited and bypasses the checklist.
```

**Only CI publishes.** Nobody publishes from Studio to either experience;
a Studio publish would silently overwrite CI's version. This goes in
`CLAUDE.md` and the release checklist.

### Secrets and permissions

| Name | Where | Scope |
|---|---|---|
| `ROBLOX_DEV_API_KEY` | Repository secret | Dev universe only: place publish (write), Luau Execution, Assets (read/write) |
| `ROBLOX_RELEASE_API_KEY` | `release` environment secret, required reviewer = you | Release universe only: place publish (write) |
| `DEV_UNIVERSE_ID`, `DEV_PLACE_ID`, `RELEASE_UNIVERSE_ID`, `RELEASE_PLACE_ID` | Repository variables | Config |

- Two keys, so nothing that runs on a PR can touch Release. Both keys get
  an expiry date; rotation is a line in the release checklist.
- **The agent never holds a key.** Publishing, engine tests and asset
  uploads are CI jobs. The agent triggers asset uploads by pushing a
  manifest change that a `workflow_dispatch` job acts on.
- Workflows use `pull_request`, never `pull_request_target`; PRs from forks
  do not get secrets.
- Keys are created at create.roblox.com/credentials with IP restriction
  "allow all", because GitHub-hosted runners have no fixed IP.
- `publish.lune` and `run-engine-tests.lune` refuse to run if the target
  universe equals `RELEASE_UNIVERSE_ID` unless invoked by the release job.

---

## 4. The test harness

Four automated tiers plus one human tier. Tiers 0–2 run on every PR on
Linux with no Studio. Tier 3 runs when the Mac is awake and is **required
for a Release promotion**. Tier 4 is you, on a real phone and a real tablet.

| Tier | Runs where | Runs when | Proves | Time |
|---|---|---|---|---|
| 0 Static | GitHub runner | Every push | StyLua, Selene, luau-lsp strict types with Roblox definitions, core/content purity, content schema validation (every hook referenced exists, every `rbxassetid://` is in the manifest, no `http` strings in content or UI text) | < 1 min |
| 1 Unit (Lune) | GitHub runner | Every push | Core and view-model logic: every chapter completable from a fresh save, from every checkpoint and from a Resume at every Quest; for every Quest, the world state implied by walking there equals the world state produced by `resume` from the saved Progress; dialogue graphs have no dead ends; save migrations round-trip and one-version tolerance; canon text byte-identical; collectible, puzzle and companion logic; dialogue view-model with emoji and `♥` graphemes | < 1 min |
| 2 Engine (Open Cloud Luau Execution) | Roblox servers | Every PR, after build | Place loads; `SceneBuilder` produces expected zones, NPCs, prompts, spawns; **reachability**: `PathfindingService` finds a path from spawn to every zone and prompt with R15 agent parameters; story walkthrough with a fake player through all chapters via the server adapter; save at every Quest, resume in a fresh DataModel, and assert the same Characters, Props and lighting are in place; two fake players at different chapters do not cross-talk; `Players.MaxPlayers == 1`; remote payloads validate against the core Net contract; no errors in the log; instance, part and triangle counts within budget; ProfileStore session lock released on `BindToClose` | 2–5 min |
| 3 Studio (Mac) | Self-hosted runner | Opportunistic on PRs (label `needs-playtest`), **mandatory for Release** | Real client playthrough: scripted character walks each chapter, prompts fire, dialogue advances, touch input works under device emulation for a phone and a tablet preset in both orientations; **Amy's face is never visible**: at every Shot and sampled throughout the playthrough, the camera lies in Amy's rear hemisphere (the dot product of her facing vector and the vector from her to the camera is negative) and her head is never framed from the front; on-screen assertions (text fits, safe areas, contrast, visibility, animations playing, nothing floating, lighting range, cues playing); screenshots at every Shot, chapter card and Scene entry per device class, diffed against `docs/screens/` baselines with a tolerance and a palette check; the agent reviews new frames against the `feel.md` rubric; client frame time, memory and `Stats` texture memory | 5–10 min |
| 4 Human | You and Clara, on Dev, on PC, a real phone and a real tablet | Before promotion | Feel, pacing, readability, fun; `RELEASE_CHECKLIST.md` | as needed |

Design notes:

- **Tier 1 and tier 2 use different runners, shared fixtures.** Jest-Lua
  runs only inside the Roblox engine, not under Lune, so tier 1 uses a small
  Lune-native `describe/it/expect` runner (about 150 lines, checked in) and
  tier 2 uses Jest-Lua or TestEZ in-engine. What is shared is the assertion
  helpers, chapter fixtures, the fake player and the event scripts, so a
  walkthrough is written once as data and executed by both runners.
- **Engine tests cannot create real players and have no client.** Luau
  Execution has no client, and `Players` spawns no one. Server adapters
  accept a "player-like" object (UserId, Character, position setter) and
  tier 2 drives them with a fake. Real client behaviour is tier 3's job;
  client logic is covered in tier 1 through the view-model.
- **Reachability is tested, traversal may be.** Whether physics and
  `Heartbeat` step inside Luau Execution is unverified. Phase 0 spike:
  if they do, tier 2 drives a Humanoid with `MoveTo` through each chapter;
  if not, pathfinding is the ceiling in tier 2 and real traversal is tier 3
  only. The answer gets written into this document.
- **Engine tests have real side effects on DataStores.** The DataModel is
  not persisted, but `DataStoreService`, `MemoryStoreService` and
  `MessagingService` are live. Tier 2 uses stores prefixed `test-<runId>`
  and deletes its keys at the end (Open Cloud DataStore API in a cleanup
  step). Never against Release.
- **Tier 3 is never on the critical path for PRs**, but it is for releases.
  On PRs the Studio job uses `continue-on-error`, a 30-minute queue timeout,
  and reports "skipped: runner offline". The release workflow refuses to
  promote a build that has no tier 3 result.
- **Screenshots are review material and agent feedback.** Tier 3 uploads a
  contact sheet to the PR. For perceptual tasks the agent reads it and
  iterates against the per-scene checklist in `docs/design/feel.md`.
- **Budgets are tests, measured where they can be.** Tier 2 checks instance
  and part counts, triangle counts from the mesh manifest and server
  Heartbeat time. Tier 3 checks client frame time and texture memory on the
  Mac. The "smooth on a mid-range phone and tablet" target is a
  release-checklist item observed on real devices, because no automated
  tier can measure it.
- **Coverage guards, not a coverage percentage.** There is no mature
  line-coverage tool for Luau in this toolchain (Lune does not expose the
  VM's coverage hooks and the in-engine runner has none), so the harness
  enforces coverage structurally in tier 0 rather than by a number:
  every module under `src/core` has a matching spec; every Quest kind,
  Hook, World command and Player event in the glossary appears in at
  least one spec by name; every chapter in content has a walkthrough
  spec; and a PR that changes `src/core` without changing `tests/` fails,
  with an explicit opt-out label and a written reason for the rare
  justified case. A nightly **mutation check** applies a dozen canned
  faults (rename a quest, drop a hook, break a migration, blank a canon
  line) and asserts the suite fails for each, so the tests are proven to
  bite. A non-blocking spike looks at exposing Luau VM coverage through
  Lune for the pure core tests; if it stabilises, the number is reported
  in PRs and only then considered as a gate. These guards arrive with the
  Checkpoint B refactor, when `src/core` comes into being.
- **Flake policy.** Open Cloud is beta. Tier 2 retries once on transport
  errors only, never on assertion failures. Outages are reported in the PR.

### Mac runner specifics

- A GitHub Actions self-hosted runner on the MacBook, labelled `studio`,
  with Roblox Studio installed and logged in, running as a launchd *agent*
  in a logged-in GUI session (never a daemon), with screen lock and sleep
  disabled while on power.
- The bridge of record is **Roblox Studio's built-in MCP server** (which
  exposes run code, run script in play mode, start/stop play, console
  output and Creator Store insertion), wrapped behind
  `tools/studio-playtest/` so nothing else depends on it. `run-in-roblox`
  is not used: its last release was 2021 and it runs in edit mode only.
  Images come from macOS `screencapture`.
- Studio auto-updates weekly and can break automation. The Mac job pins
  and reports the Studio version; "Studio version drift" is a tracked risk.
- When the Mac is closed or off, PR jobs queue up to 30 minutes then skip.

### Autonomous visual testing on the Mac

The Mac is the only place a frame gets rendered, so it is where visual
autonomy lives. There are three levels, from fully deterministic to
judgement, and the agent can run all three without you when the Mac is
on. Only the last step, accepting a new look, stays human.

**Level 1: assertions the engine can make about what is on screen.**
These run as part of the tier 3 playthrough script and fail the job like
any other test. No images are needed.

| Check | How |
|---|---|
| Text fits and is readable | `TextLabel.TextFits` true for every visible Line; text height in physical pixels at the emulated device's DPI meets the `feel.md` minimum; line length on tablet under the maximum |
| Layout | Every UI element inside the safe area; no two interactive elements overlap; touch targets at least 44 points on phone and tablet |
| Contrast | Text colour versus dialogue-box colour meets a contrast ratio of at least 4.5:1, computed from the actual colours in the frame |
| The right things are visible | For each Shot and each Dialogue, a raycast from the camera reaches the speaker's head and the objective target without occlusion; the on-screen objective marker is within the viewport |
| Characters look alive | Humanoid animation tracks are playing (no T-pose); the speaker faces Amy during Dialogue; Companions are within follow distance |
| Amy's face is never seen | Camera position is in Amy's rear hemisphere at every sampled frame and every Shot; no Dialogue, Beat or respawn camera breaks it; reflective surfaces, if any, never render her face |
| Nothing floats or sinks | For every Prop and Character, a downward raycast finds ground within a tolerance; no Prop intersects another unexpectedly |
| Lighting sanity | Average frame luminance per Scene within a range (not too dark on a phone in daylight; not blown out); no fully black frames during Beats |
| Audio present | Each Scene has an ambience and a music Cue playing; `PlaybackLoudness` above zero when a Cue fires |
| Client performance | Frame time and memory from `Stats` within budget, as a proxy for mobile |

**Level 2: image checks against baselines.** The script captures a
screenshot at every Shot, chapter card and Scene entry, for each device
class and orientation, and compares it to the baseline in
`docs/screens/` with a structural-similarity measure and a tolerance.
Pixel-exact comparison is useless in Roblox (particles, animation
phase, cloud movement), so captures freeze time where possible (pause
particles, fix the animation frame, fixed time of day) and the tolerance
is tuned per shot. A diff over tolerance fails the job and attaches the
pair with the changed regions highlighted. This is **regression**
testing: it proves a change did not alter scenes it was not meant to
alter, and it is fully autonomous. In addition, a palette check samples
each frame's dominant colours and asserts they fall within Clara's
palette, which catches a stray default-grey part or an off-brand model.

**Level 3: the agent looks at the pictures.** The agent can read images.
When the contact sheet comes back, the agent reviews each new or changed
frame against a written rubric in `feel.md` (composition: subject in the
middle third and not cut off; readability: dialogue legible at the
device's size; style: hand-drawn feel, palette, scribbly grass, round
canopies like the hero illustration; clutter: nothing distracting behind
the speaker), scores it, and iterates on the scene until the rubric
passes. This is judgement, not proof, so it gates the agent's own loop
and not the release. It is also what makes a perceptual brief finish
without your involvement: the agent builds, plays, looks, adjusts, and
repeats, and you see the result once.

**What this gives us**

| Situation | Autonomy |
|---|---|
| A change to logic or content that should not alter any scene | Fully autonomous: levels 1 and 2 pass or fail the PR |
| A new or changed scene, shot or UI screen | Autonomous iteration: levels 1 to 3 run until green, baseline proposed; you accept the new baseline in the PR |
| Taste: is it fun, is the pacing right, does it feel like Clara's book | Human, on a real phone and tablet |
| Audio quality and mix | Human; the Mac only proves cues play |

**Mechanics and limits**

- Capture uses macOS `screencapture` of the Studio viewport rectangle
  driven through the Studio MCP server; in-engine `CaptureService` is
  not relied on because it is unreliable in Studio.
- Device classes are emulated with Studio's device emulation; whether it
  can be switched from a script is a Phase 1 spike. The fallback is
  resizing the Studio window to each device's aspect ratio by AppleScript,
  which tests layout but not DPI; DPI-dependent text checks then use the
  emulated scale factor from `feel.md`.
- A full visual pass takes 5 to 10 minutes, so the agent batches scene
  changes and runs it per batch, not per edit.
- Baselines change deliberately: a PR that changes a baseline shows the
  before and after in its description and lists the rubric scores.
- All of it depends on the Mac being awake and on Studio not having
  auto-updated into a breaking change that week. A perceptual brief
  states up front that it needs the Mac on for its duration.

---

## 5. Agent workflow: from high-level task to proven PR

The goal is that you write a brief and, without further guidance, receive a
PR that is green across all tiers, plays correctly on Dev, and is documented
well enough to review in minutes.

### 5.1 Task briefs

A task lives in `docs/tasks/NNN-short-name.md` and declares its kind:

```
# 012 — Chapter 5: The Night the Fireflies Came
Kind: logic + perceptual (Mac required for the perceptual part)
Goal: a new chapter, 10–15 minutes of play, that follows Clara's story
proposal in docs/story/proposals/chapter-5.md (approved 2026-11-02).
Must: new scene (night-time paradise), 2 new collectibles, 1 puzzle,
      Sam companion behaviour, music and SFX, tested on PC, phone and tablet.
Must not: change any canon text; add paid items; exceed budgets.
Done when: DEFINITION_OF_DONE.md is satisfied and the chapter is
           completable in tier 2 and tier 3 from a Chapter 4 save.
```

### 5.2 What the agent does with it

1. Reads `CLAUDE.md`, the brief, the definition of done, the story style
   guide and `docs/design/feel.md`.
2. Writes a short design note into the PR description first: scenes,
   quests, hooks, systems touched, assets needed.
3. Works on a branch in small commits, running tiers 0–1 locally after each
   change and tier 2 via CI on each push.
4. Declares needed assets in the manifest (Clara's illustrations, free
   Creator Store models fetched per 5.5, free-licence or synthesised audio)
   with creator and licence; CI uploads them and writes back the ids.
5. Iterates until every tier is green, then requests a tier 3 playtest by
   label. If the Mac is off, it says so in the PR and continues with what
   can be proven.
6. For perceptual scope, runs the Mac visual pass per batch of scene
   changes, fixes any on-screen assertion or baseline failure, reviews the
   new frames against the `feel.md` rubric by looking at them, and iterates
   until the rubric passes; proposes new baselines in the PR.
7. Produces the PR with: changelog, test report, screenshots or a note that
   none were possible, a "how to play-test this" section with the Dev link
   and a save-state shortcut, and open questions as a short list.
8. Watches the PR: fixes CI, answers review comments, pushes follow-ups.

### 5.3 What makes this reliable

- `CLAUDE.md` holds the conventions, the exact commands for each tier, the
  architecture rules, the "only CI publishes" rule, and the definition of
  done, so every session starts with the same context.
- Repeated workflows become skills in `.claude/skills/`: `new-chapter`,
  `playtest`, `publish-dev`, `request-assets`, `perf-report`.
- Content schemas are validated in tier 0, so a malformed chapter is caught
  before any engine time is spent.
- Debug shortcuts in Dev builds: a `/chapter N` command and a "jump to
  quest" menu let you and the tests reach any point of the story in
  seconds. Compiled out of Release builds.
- A nightly routine builds `main`, runs all tiers, publishes Dev, and posts
  a one-paragraph summary. If anything regresses with no PR to blame, it
  opens an issue.
- Large tasks are split by the agent into stacked PRs only when a single PR
  would exceed roughly 2,000 changed lines; otherwise one PR per brief.

### 5.4 Logic-provable versus perceptual work

| Scope | Examples | Who proves it |
|---|---|---|
| Logic-provable | Quest flow, saves, collectibles, puzzles, reachability, budgets, remote contracts, canon integrity | Tiers 0–2, fully autonomous on Linux |
| Perceptual | Scene composition, lighting, readability on a phone and a tablet, animation feel, audio mix, pacing | Tier 3 with the Mac awake: on-screen assertions and baseline diffs are automatic, and the agent iterates against the `feel.md` rubric by looking at the frames (see "Autonomous visual testing on the Mac"); you and Clara accept the result |

A brief that is purely logic-provable can be delivered end to end without
the Mac. A perceptual brief needs the Mac on during the run; with it on,
the agent can iterate on visuals by itself and you review once at the end.
Taste and audio mix stay human. This is a real constraint, not a wording
choice.

### 5.5 Sourcing free Creator Store assets from Linux

There is no Open Cloud endpoint to download a Creator Store model. Phase 0
spikes two paths and records the winner here:

- (a) A Luau Execution task calls `InsertService:LoadAsset(id)`, serialises
  the result with `SerializationService`, and returns it for CI to write to
  `assets/meshes/`, chunked if the return-size limit requires it.
- (b) The Mac runner's Studio MCP `insert_model` plus save-to-`.rbxm`.

Either way the manifest records asset id, creator, licence and moderation
status, and tier 0 fails on any `rbxassetid://` not in the manifest.

---

## 6. Phased roadmap

Estimates assume agent-driven work with your review in between. Each phase
ends in a Dev build you can play, and from Phase 1 on, a Release.

### Phase 0 — Foundation (target: 3 weeks, Linux only)

Outcome: the same four chapters, now built, tested and published by the
pipeline. No new gameplay.

1. **Characterization test first.** A Luau Execution test drives the
   *current* `StoryServer` with a fake player through all four chapters and
   records the sequence of `ShowDialogue` / `SetObjective` / `ShowChapter`
   payloads to a golden file. The refactor is done when the golden file
   still matches byte for byte.
2. Toolchain: Rokit, Rojo, Wally, Lune, StyLua, Selene, luau-lsp;
   `CLAUDE.md`.
3. Refactor into core / adapters / content with behaviour unchanged;
   chapters 1–4 as data + hooks; client view-model extracted; canon text
   locked by test; content positions as plain tables.
4. Tier 0 and tier 1 green in CI with meaningful coverage of `StoryEngine`
   and the view-model.
5. You create the Dev and Release experiences and the two API keys; CI
   publishes Dev on merge and Saved versions on PRs.
6. Tier 2 runner and the engine suite: world builds, reachability, story
   walkthrough, two-player isolation, MaxPlayers, remote contracts, budgets,
   DataStore prefixing and cleanup.
7. Spikes with written decisions: physics in Luau Execution, asset fetch
   path (5.5), in-engine runner (Jest-Lua vs TestEZ), Luau VM coverage
   through Lune (non-blocking).
8. Coverage guards in tier 0 and the nightly mutation check, as defined
   in section 4, landing with the refactor.
9. `GLOSSARY.md` (from section 2.4) with the content schema derived from
   it; `DEFINITION_OF_DONE.md`, `RELEASE_CHECKLIST.md`,
   `docs/design/feel.md`, first skills.

### Phase 1 — Public release candidate (target: 5–6 weeks)

Outcome: version 1.0 on the Release channel.

- **Mac runner** set up with the Studio MCP bridge, one end-to-end smoke
  playthrough, screenshots, baselines for the existing scenes.
- Save system: Progress written on every Story event and on leave, Resume
  at the current Quest with the world rebuilt from Progress, chapter
  checkpoints, a "continue" title screen, and "start again" behind a
  confirmation. Studio DataStore access enabled on the Dev experience so
  Mac playtests can exercise it under the test prefix.
- Phone and tablet support as separate device classes: touch controls,
  per-class UI layouts, safe areas, first-minute onboarding (where the
  thumbstick is, how to talk), tested under Studio device emulation on the
  Mac for at least one phone and one tablet preset in both orientations,
  and on a real phone and a real tablet.
- Audio: ambient forest, village, paradise; music per chapter; SFX;
  narration of canon lines (see section 7).
- Visual pass on the existing world: terrain and foliage, lighting and
  atmosphere, Clara's palette; chapter cards from her illustrations; the
  camera shots in `feel.md`. Choose the lighting technology (`ShadowMap`
  or `Future`) against the mobile frame-time budget; it is set in the Rojo
  project file, never left to the engine default.
- The locked-behind camera that makes "Amy's face is never seen" true on
  PC, phone and tablet, including spawn, respawn, Dialogue and every Shot;
  chapter cards and store assets checked against the same rule.
- Characters via `HumanoidDescription` and built-in animations; Sam's
  catch becomes a short chase; animals from free rigs with animations.
- Settings (volume, text size, high-contrast dialogue box), pause,
  accessibility basics (large readable dialogue, no timed reading,
  dyslexia-friendly font option).
- **Roblox compliance**, which gates visibility to the target audience:
  - Account at least 30 days old (required to complete the questionnaire).
  - Experience Guidelines questionnaire completed with a result suitable
    for all ages. Without it the experience is treated as 13+ and is not
    recommended to younger players. Redone whenever content changes
    materially (new chapters with new themes).
  - No external URLs anywhere: not in the description, credits, ending
    card or dialogue. The website link stays in the GitHub README only.
    Tier 0 enforces this in content and UI strings.
  - Credits use "Clara" only, never a full name, in line with Roblox rules
    on minors' personal information.
  - Max Players = 1; "Allow copying" off; automatic translation **off**
    (it would "correct" Clara's deliberate spellings).
  - Icon, thumbnails and description pre-checked against moderation rules.
- Analytics events wired; a note in `docs/` on what to watch.

### Phase 2 — Make it compelling (target: 6–8 weeks, several PRs)

Outcome: players return because there is more to discover.

- Hub: Amy's house and garden become a persistent home base with the
  journal, a map, and the animals visiting once befriended.
- Companions: squirrel, fox and lion each with a befriending arc and a
  helper ability (the squirrel finds hidden things, the fox leads the way
  at night, the lion clears a path).
- Collectibles across all scenes with journal entries written in Clara's
  voice; cosmetic rewards for Amy's outfit and the garden.
- Light puzzles per scene; no failure states, hints after a delay.
- Replayability: chapter select, time-of-day variations, a few optional
  side quests from villagers.
- Custom rigs and keyframed animations for Amy and Sam: a human-in-Studio
  task scoped and reviewed by the agent, authored by a person.
- Second visual pass driven by tier 3 screenshots and player feedback.
- Co-op spike: a friend joins as a second explorer. Requires per-player
  instancing of NPCs, prompts and lighting; shipped only if it does not
  compromise the single-player story.

### Phase 3 — Continual expansion (ongoing)

- Chapter pipeline: proposal → approval → brief → PR → Dev → Release, with
  one new chapter roughly every 4–6 weeks.
- Seasonal moments (rainy season, fireflies, a village fair) as content
  packs toggled by date.
- Monthly quality PR driven by analytics: where players drop off, what is
  slow on phone or tablet, what is confusing.
- Regular upkeep: Roblox engine changes, Open Cloud API updates, Studio
  version drift on the Mac, key rotation. Dependencies are kept current
  automatically: Dependabot for GitHub Actions, and a weekly toolchain
  job that opens a pinned-version bump PR for Rokit and Wally (which
  Dependabot does not support). CI proves each bump; the owner merges.

---

## 7. Story, narration and content rules

- `docs/story/canon.md` holds Clara's original text. A tier 1 test asserts
  every canon line in the game matches it byte for byte, including her
  spelling.
- **Narration.** Many 7 to 12 year olds will not read fluently. Recorded
  narration of the canon lines (ideally Clara reading her own story) is the
  cheapest large quality win and keeps canon intact. Lines are batched per
  chapter into single audio files with timestamps to stay within upload
  limits. Audio upload limits are 10 per month without Roblox ID
  verification and 100 with it, so **ID verification is a Phase 1
  prerequisite**, not optional. Uploaded audio is private to the uploading
  account's experiences and would need re-uploading if ownership ever
  moves to a group.
- New story is proposed in `docs/story/proposals/` as a one-page
  treatment (premise, beats, new characters, moral), drafted by the agent in
  her voice using `style-guide.md`. You and Clara approve, edit, or reject
  in the PR. Nothing enters a chapter brief until approved.
- Off limits unless Clara says otherwise: changing the ending, altering
  existing characters' personalities, any content outside an all-ages
  rating, in-game purchases.
- Dialogue reading level: short lines, large text, no timers.

---

## 8. Quality bar and how we measure it

| Dimension | Bar | Measured by |
|---|---|---|
| Correctness | Every chapter completable from every checkpoint, on PC, phone and tablet | Tiers 1–3 |
| Reachability | Every zone and prompt reachable by an R15 character | Tier 2 pathfinding, tier 3 traversal |
| Amy's face | Never seen, in game or in any art asset | Tier 3 camera assertion at every Shot and sampled frames; release checklist for icon, thumbnails and cards |
| Performance | Instance, part, triangle and texture budgets; server Heartbeat under 8 ms; smooth on a mid-range phone and tablet | Tiers 2–3 budgets; real device on the release checklist |
| Visual | Consistent with Clara's palette and illustration style; one baseline screenshot per scene in `docs/screens/`, updated deliberately when a scene changes | Tier 3 diff + your review |
| Audio | Every interaction has feedback; every scene has ambience and music; canon lines narrated | Manifest test + review |
| Readability | Minimum dialogue text size on a 6-inch phone, maximum line length on a 13-inch tablet; high-contrast option | `feel.md` spec, tier 3 device emulation for phone and tablet presets, real devices |
| Story | Canon untouched, new text approved, no dead ends | Tier 1 + proposals |
| Retention | Chapter completion funnel, median session length, day-7 return rate | Roblox Analytics, reviewed monthly |

---

## 9. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Open Cloud Luau Execution is beta and may change or have outages | Tier 2 is isolated behind one runner script; failures are reported, not hidden; tier 3 and Lune cover most of the same logic |
| Mac runner is often off | Tier 3 optional on PRs, mandatory for releases; perceptual briefs scheduled when the Mac is on |
| Studio version drift breaks the Mac bridge | Studio version pinned and reported by the job; bridge wrapped behind one module |
| Agent cannot see or hear the game | Perceptual scope declared per brief; contact sheets and baselines; human review is part of the definition of done for perceptual work |
| A PR job could publish to the public experience | Separate Dev and Release keys; Release key only in the gated environment; agent never holds a key; no `pull_request_target` |
| Engine tests pollute Dev DataStores | Prefixed test stores with cleanup; runner refuses Release IDs |
| Uploaded assets rejected by moderation | Upload early in a task; manifest records status; fall back to procedural art |
| Audio upload cap | ID-verify before Phase 1; batch narration per chapter |
| Refactor breaks the existing story | Characterization golden test written before the refactor |
| Multiple players in one server break the story | Max Players = 1 asserted in tier 2; two-player isolation test |
| Agent scope creep inside a task | Brief has "must not"; definition of done; PR size guideline |
| Roblox policy and questionnaire | Compliance list in Phase 1 and the release checklist; questionnaire redone on material content change |
| DataStore schema drift | Versioned saves with migration and tolerance tests; rollback limited to one schema version |

---

## 10. What you need to do (one-time setup)

1. Create two experiences on your Roblox account: "Amy and the Rain Forest
   (Dev)" set to Friends, and "Amy and the Rain Forest" set to Private until
   1.0. Set Max Players = 1 and "Allow copying" off on both. Note both
   universe and place IDs.
2. Create two Open Cloud API keys at create.roblox.com/credentials:
   a Dev key with Place Publishing (write), Luau Execution and Assets
   (read, write) for the Dev experience only; a Release key with Place
   Publishing (write) for the Release experience only. IP restriction
   "allow all"; set expiry dates.
3. Add the Dev key, IDs and variables from section 3 to the GitHub
   repository. Create a GitHub environment named `release` with yourself as
   required reviewer and put the Release key there.
4. ID-verify the Roblox account (needed for narration uploads) and confirm
   the account is at least 30 days old before Phase 1 ends.
5. Share Clara's illustrations as image files (the hero image and any
   others) into `assets/images/` or a shared folder.
6. Add testers as friends of the owning account when Dev is ready.
7. In Phase 1, install Roblox Studio and the self-hosted runner on the
   MacBook; the agent provides a setup script and checklist.

Phase 0 agent work starts as soon as item 3 is done; items 1–2 can be done
in parallel with the characterization test and refactor.

---

## 11. Decisions log

| Decision | Choice |
|---|---|
| Roblox ownership | Personal account (a group can be adopted later; IDs are config; audio would need re-upload) |
| Channels | Two separate experiences, Dev (friends) and Release (public) |
| Automation auth | Two Open Cloud keys as GitHub secrets; Release key only in the gated environment; agent never holds a key |
| Audience | Ages 7–12, all-ages rating, no chat required |
| Monetization | None |
| Platforms | PC, phone and tablet as three first-class device classes; console not targeted |
| Multiplayer | Single player, Max Players = 1; co-op evaluated in Phase 2 as a redesign |
| Player identity | The player is Amy (forced `HumanoidDescription`) |
| Amy's face | Never seen: camera locked behind her, every Shot from behind, no art shows her face. Invariant from the first release; future chapters may play with it, never break it |
| Gameplay direction | Exploration, animal companions, light puzzles; hub world; saves |
| Retention | New chapters and collectibles |
| Story authorship | Agent drafts proposals in Clara's voice; Clara and Jason approve; canon locked; credits say "Clara" only |
| Narration | Canon lines narrated; ID verification required |
| Assets | Free Creator Store, Clara's illustrations, free-licence or synthesised audio; uploads by CI only |
| Test runners | Lune-native runner for tier 1; Jest-Lua or TestEZ in-engine for tier 2; shared fixtures |
| Mac bridge | Roblox Studio built-in MCP server, wrapped; not `run-in-roblox` |
| Review | Play Dev on PC, a real phone and a real tablet + read PR; release checklist gates promotion; tier 3 mandatory for release |
| Task size | One chapter or feature set per PR |
| Cadence | On demand plus nightly Dev build |
| Test machines | Linux CI for tiers 0–2; MacBook self-hosted runner for tier 3, opportunistic on PRs |
