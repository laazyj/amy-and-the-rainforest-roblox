# Glossary — the ubiquitous language

This is the single source of truth for the words used in Clara's story,
the content files, the core modules, the tests, the task briefs, the PR
descriptions, the analytics events and our conversations. It is derived
from section 2.4 of [`DEVELOPMENT_PLAN.md`](DEVELOPMENT_PLAN.md); where
the two disagree, change this file and the plan in the same PR.

**The glossary is the schema.** The enumerations below are the values
that tier 0 validates content against. A new noun, verb or enumeration
value enters this file in the same PR that introduces it in code, and the
PR description uses it (see [How to propose a new term](#how-to-propose-a-new-term)).

Related documents: [Definition of done](DEFINITION_OF_DONE.md) ·
[Canon](story/canon.md) · [Style guide](story/style-guide.md) ·
[Feel](design/feel.md) · [Release checklist](RELEASE_CHECKLIST.md)

---

## 1. The shape of the story

```
Story
 └─ Chapter (card, checkpoint)
     └─ Quest (kind, objective, intro, outro, hooks)
         ├─ Dialogue ── Line (speaker, text, canon?)
         └─ Beat (named list of World commands)

Scene (look + sound)                     Player
 ├─ Spot   (named place)                  ├─ Progress (where they are in the Story)
 ├─ Zone   (named volume)                 ├─ Journal  (what they have found)
 ├─ Prop   (object with states)           └─ Bonds    (with Companions)
 ├─ Character (home Spot, kind)
 │    └─ Companion (follows, helps, bond)
 ├─ Pickup / Collectible
 └─ Cue, Shot, Lighting preset
```

## 2. The nouns

| Term | Meaning | Example |
|---|---|---|
| **Story** | The whole experience: ordered Chapters plus the Ending. There is one. | Amy and the Rain Forest |
| **Ending** | The closing Dialogue and end card played after the last Chapter completes. | "The end ♥" |
| **Chapter** | A titled part of the Story with a card (title, subtitle), an ordered list of Quests, and a Checkpoint at its start. | `chapter2` "The Unexplored World" |
| **Chapter card** | The full-screen title and subtitle shown when a Chapter starts. | "Chapter One — One Beautyfull Sunday" |
| **Quest** | One objective the player must complete. Has a Kind, an Objective, optional intro and outro Dialogue, and Hooks. | `chapter1.sneak_out_1` |
| **Kind** (of Quest) | How a Quest is completed. One small module in core per Kind. See [enumeration](#quest-kinds). | `reach` |
| **Objective** | The one short instruction shown on screen while a Quest is active. Standard spelling, imperative, written for the player. | "Ask Dad if you can go outside" |
| **Dialogue** | An ordered list of Lines shown together. A Quest has up to three: `intro` (on start), `dialogue` (on `TalkedTo`, `talk` Quests only) and `outro` (on complete). | the five Lines when Amy asks Dad |
| **Line** | One thing said: Speaker, text, optional narration audio, and a `canon` flag. | Narrator: "She tryed again but Sam brang her back." |
| **Canon** | A property of a Line: the text is Clara's exact words and is locked. Every canon Line is checked byte for byte against [`story/canon.md`](story/canon.md). New Lines in Clara's voice are not canon until she says so. | |
| **Speaker** | Who says a Line: the Narrator, Amy, or another Character. Stored as a Character id, displayed by the Character's display name. See [enumeration](#characters-and-speakers). | `Narrator` |
| **Narrator** | The storyteller's voice. Canon Lines are almost always the Narrator's; a Narrator Line is not canon unless marked. | |
| **Beat** | A named, staged moment: a fixed list of World commands, with optional waits, played at a Hook. Beats are how the story moves the world. See [enumeration](#beats). | `beat:sam_catches` |
| **Hook** | A point in a Quest's life where Beats run. Declared in the Chapter's `hooks.luau`. See [enumeration](#hook-names). | `chapter1.sneak_out_1.onComplete → sam_catches` |
| **Scene** | A part of the world with its own look and sound: terrain, Props, Spots, Zones, ambience, music. See [enumeration](#scenes). | `scene:ForestWall` |
| **Spot** | A named position and facing inside a Scene. Content never holds raw coordinates; it names Spots. | `spot:GardenGateInside` |
| **Zone** | A named invisible volume the player can enter. Entering one is the Player event `EnteredZone`. See [enumeration](#zones). | `zone:ForestGap` |
| **Prop** | A placed object with named states. See [enumeration](#props). | `prop:Machine` |
| **Character** | A named being in the world with a kind, a display name and a home Spot. See [enumeration](#characters-and-speakers). | `character:Sam` "Sam the Dog" |
| **Player Character** | The Character the player controls. The player **is Amy**. | `character:Amy` |
| **Companion** | A Character that can follow Amy, help her, and whose Bond with her grows. | Sam; later Squirrel, Fox, Lion |
| **Bond** | A Companion's relationship level with Amy. Persisted. | Fox at `friend` |
| **Pickup** | A Quest-bound thing to touch, spawned at Spots for a `collect` Quest and removed when the Quest ends. | three glowing flowers |
| **Collectible** | A persistent discoverable with a Journal entry. Found once, remembered forever. | `collectible:maroon_acorn` |
| **Journal** | The player's record of Collectibles found and Characters met, with entries in Clara's voice. | |
| **Cue** | A named sound, music track or effect, resolved to an asset id through `assets/manifest.json`. | `cue:sam_bark`, `music:paradise_theme` |
| **Shot** | A named camera framing used by a Beat or a Dialogue. Specified in [`design/feel.md`](design/feel.md). See [enumeration](#shots). | `shot:ForestWallReveal` |
| **Lighting preset** | A named look for a Scene. See [enumeration](#lighting-presets). | `lighting:paradise` |
| **Progress** | Where a player is in the Story: current Chapter and Quest, completed Quest ids, Pickup counts, Collectibles, Bonds, and the Prop states that matter. Saved on every Story event and on leave. | |
| **Checkpoint** | The Progress snapshot taken at a Chapter start, kept alongside current Progress. "Play this chapter again" restarts from it. | |
| **Resume** | Rebuilding the world for a returning player from Progress alone: `StoryEngine.resume(progress)` returns the World commands that put every Character, Prop, Lighting preset and Pickup where the current Quest expects them, then shows the Objective. "Continue" on the title screen is a Resume. | |
| **World** | The one interface the core uses to act on the engine. Every Beat is written against it, one method per World command. | `World.moveCharacter(id, spot)` |
| **Device class** | One of the three first-class targets, each with its own layout and touch rules: `PC`, `Phone`, `Tablet`. Defined in [`design/feel.md`](design/feel.md). | `Tablet` |

## 3. The verbs

The core is a pure function of events:

```
StoryEngine.step(progress, playerEvent) → progress', storyEvents[], worldCommands[]
```

- **Player events** come *in* from the adapter, in the player's terms.
- **Story events** go *out* as facts about the story. Their names are also
  the analytics event names and the names used in test descriptions.
- **World commands** go *out* as instructions to the engine. The server
  adapter executes them; those that reach the client are rendered by the
  client binder.

### Player events

| Event | Payload | Sent when |
|---|---|---|
| `EnteredZone` | `zone` | The Player Character enters a Zone |
| `TalkedTo` | `character` | The player uses the talk affordance on a Character |
| `TouchedPickup` | `pickup` | The Player Character touches a Pickup |
| `DialogueFinished` | none | The client has shown the last Line of the current Dialogue and the player advanced past it |
| `FoundCollectible` | `collectible` | The Player Character finds a Collectible |
| `SolvedStep` | `puzzle`, `step` | The player completes one step of a puzzle |

### Story events

| Event | Payload | Meaning |
|---|---|---|
| `ChapterStarted` | `chapter` | A Chapter became `active` |
| `QuestStarted` | `quest` | A Quest became `active` |
| `QuestCompleted` | `quest` | A Quest became `completed` |
| `ChapterCompleted` | `chapter` | A Chapter became `completed` |
| `BeatPlayed` | `beat` | A Beat ran at a Hook |
| `CollectibleFound` | `collectible` | A Collectible went from `hidden` to `found` |
| `BondChanged` | `character`, `from`, `to` | A Companion's Bond moved one level |
| `StoryEnded` | none | The Ending finished |

### World commands

| Command | Arguments | Does |
|---|---|---|
| `ShowDialogue` | `lines` | Shows a Dialogue; the client replies with `DialogueFinished` |
| `SetObjective` | `text` or none | Shows or clears the Objective |
| `ShowChapterCard` | `title`, `subtitle` | Shows a Chapter card (also used for the end card) |
| `MoveCharacter` | `character`, `spot` | Puts a Character at a Spot |
| `TeleportPlayer` | `spot` | Puts the Player Character at a Spot |
| `SetPropState` | `prop`, `state` | Moves a Prop to one of its declared states |
| `PlayCue` | `cue` | Plays a Cue |
| `SetLighting` | `preset` | Applies a Lighting preset |
| `FrameShot` | `shot` | Frames a Shot; the follow camera returns when the Shot ends |
| `SpawnPickups` | `quest` | Spawns the Quest's Pickups at their Spots |
| `ClearPickups` | `quest` | Removes the Quest's remaining Pickups |
| `SaveProgress` | none | Writes Progress |
| `SaveCheckpoint` | `chapter` | Writes the Checkpoint for a Chapter |

If a Beat needs something these commands cannot do, the World interface
grows by one named command, recorded here in the same PR.

## 4. Enumerations

These are the closed lists the content schema is derived from. Every
table lists the prefixed id (see [§6](#6-ids)). Every value is in use now
unless marked *later*; *later* values are reserved names that tier 0
rejects in content until the PR that implements them removes the mark.

### Quest kinds

| Kind | Completed when |
|---|---|
| `talk` | `TalkedTo(character)` for the Quest's Character, then `DialogueFinished` |
| `reach` | `EnteredZone(zone)` for the Quest's Zone |
| `collect` | `TouchedPickup` for each of the Quest's `count` Pickups |
| `follow` *later* | Amy arrives at a Spot while following a Companion |
| `place` *later* | A thing is put at a Spot |
| `solve` *later* | Every step of the Quest's puzzle is `SolvedStep` |

### Characters and Speakers

A Speaker is `Narrator` or a Character id. Display names come from the
Character, never from the Line. Character kinds are the values of the
Kind column.

| Character | Kind | Display name | Notes |
|---|---|---|---|
| `Narrator` | none | Narrator | Speaker only; not a Character, never in the world |
| `character:Amy` | `human` | Amy | The Player Character; spawns in the garden |
| `character:Dad` | `human` | Dad | Home in the garden |
| `character:Mum` | `human` | Mum | Home in the garden |
| `character:Sam` | `dog` | Sam the Dog | Companion; home in the garden, by the gate |
| `character:Squirrel` | `squirrel` | the Maroon Squirrel | Home in the paradise |
| `character:Fox` | `fox` | the Orange Fox | Home in the paradise |
| `character:Lion` | `lion` | the Golden Lion | Home in the paradise, deep glade |

Home Spot ids are named in the Phase 0 refactor and added here then.

### Hook names

| Hook | Runs when |
|---|---|
| `onStart` | The Quest becomes `active`, before its Objective and intro Dialogue are shown |
| `onComplete` | The Quest becomes `completed`, after its outro Dialogue is queued |

### Beats

| Beat | Hook | Does |
|---|---|---|
| `beat:sam_catches` | `chapter1.sneak_out_1.onComplete`, `chapter1.sneak_out_2.onComplete` | Sam runs to the gate and brings Amy back into the garden |
| `beat:sam_goes_to_farm` | `chapter2.walk_to_forest.onStart` | Sam leaves for the farm |
| `beat:paradise_reveal` | `chapter2.enter_forest.onComplete` | `SetLighting(lighting:paradise)` |
| `beat:ordinary_world` | `chapter3.rush_home.onComplete` | `SetLighting(lighting:ordinary)` |
| `beat:machine_arrives` | `chapter3.tell_mum.onComplete` | The machine and villagers arrive; Dad, Mum and Sam move to the field |
| `beat:machine_stops` | `chapter4.explain.onComplete` | The blade stops, sparkles over the crowd, the machine reverses away |

### Zones

| Zone | Scene | Used by |
|---|---|---|
| `zone:GardenGate` | Garden | `chapter1.sneak_out_1`, `chapter1.sneak_out_2` |
| `zone:ForestEdge` | Field | `chapter2.walk_to_forest` |
| `zone:ForestGap` | Forest Wall | `chapter2.enter_forest` |
| `zone:HeartGlade` | Heart Glade | `chapter2.heart_glade` |
| `zone:HomeGarden` | Garden | `chapter3.rush_home` |
| `zone:MachineFront` | Field | `chapter4.stand_in_front` |

### Scenes

| Scene | What it is |
|---|---|
| `scene:Garden` | Amy's house and fenced garden, where she starts |
| `scene:Village` | The little houses behind Amy's |
| `scene:Field` | The scribbly-grass field between the garden and the trees |
| `scene:ForestWall` | The wall of giant trunks with one narrow gap |
| `scene:Paradise` | The parallel world beyond the wall |
| `scene:HeartGlade` | The ring of glowing flowers at the heart of the paradise |

### Props

| Prop | States, in order |
|---|---|
| `prop:Machine` | `absent`, `advancing`, `stopped`, `retreating` |

### Lighting presets

| Preset | Look |
|---|---|
| `lighting:ordinary` | Warm cream-sky afternoon, no colour grade |
| `lighting:paradise` | Saturation and contrast raised, warm tint |

### Shots

Framing and where each is used are specified in
[`design/feel.md`](design/feel.md#2-shots).

| Shot | Argument |
|---|---|
| `shot:Dialogue` | none |
| `shot:ForestWallReveal` | none |
| `shot:MeetCharacter` | the Character being met |
| `shot:MachineFinale` | none |

### Cues

None yet. Cue names (`cue:<name>` for sounds, `music:<name>` for music)
are added here with their manifest entry.

## 5. Lifecycles

| Thing | States, in order |
|---|---|
| Chapter | `locked`, `active`, `completed` |
| Quest | `pending`, `active`, `completed` |
| Bond | `stranger`, `curious`, `friend`, `companion` |
| Prop | declared per Prop in [Props](#props) |
| Collectible (per player) | `hidden`, `found` |

## 6. Ids

A reference from one concept to another is always by id, never by
position or raw coordinate.

| Concept | Form | Example |
|---|---|---|
| Chapter | `chapter<n>` | `chapter3` |
| Quest | `<chapter>.<snake_case>` | `chapter3.meet_fox` |
| Character | `character:<PascalCase>` | `character:Sam` |
| Zone | `zone:<PascalCase>` | `zone:ForestGap` |
| Spot | `spot:<PascalCase>` | `spot:HeartGladeCentre` |
| Scene | `scene:<PascalCase>` | `scene:Paradise` |
| Prop | `prop:<PascalCase>` | `prop:Machine` |
| Shot | `shot:<PascalCase>` | `shot:ForestWallReveal` |
| Beat | `beat:<snake_case>` | `beat:sam_catches` |
| Cue | `cue:<snake_case>`, `music:<snake_case>` | `cue:sam_bark` |
| Lighting preset | `lighting:<snake_case>` | `lighting:paradise` |
| Collectible | `collectible:<snake_case>` | `collectible:maroon_acorn` |

Inside content files the prefix is dropped where the field already says
what it is (`zone = "ForestGap"`, `speaker = "Sam"`); in prose, briefs and
PRs, use the prefixed form.

## 7. Words we do not use

| Say | Not |
|---|---|
| Character | NPC, actor, figure |
| Zone | trigger, region, area |
| Beat | cutscene, sequence, special, scripted moment |
| Quest | mission |
| Line | message |
| Shot | camera angle |

## 8. Migration from today's code

The proof of concept predates this language. Where the code and this
glossary disagree, **the glossary wins** and the Phase 0 refactor renames
the code. Until then, read the old name as the new one. This table is
the only map from old names to new; delete it once the refactor lands.

| Today (`src/`) | Becomes |
|---|---|
| `StoryData` module | Story: `content/chapters/<n>/data.luau` and friends |
| `StoryData.Ending` | Ending |
| `StoryData.NPCs` | `content/characters.luau` (Characters) |
| `npc = "Dad"` on a Quest | `character = "Dad"` |
| `npcModels`, `pivotNPC`, `NpcController` (in the plan's diagram) | `CharacterHost`, `World.moveCharacter` |
| `type = "talk"` on a Quest | `kind = "talk"` |
| `onComplete = { ...lines }` on a Quest | `outro = { ...lines }`; `onComplete` is reserved for the Hook |
| `speaker = "Sam the Dog"` (display name) | `speaker = "Sam"` (Character id) |
| `questStartedHooks[id]` / `questCompletedHooks[id]` | `onStart` / `onComplete` in `hooks.luau` |
| `samCatches`, `samGoesToFarm`, `paradiseReveal`, `ordinaryWorld`, `machineArrives`, `machineStops` | the [Beats](#beats) |
| the colour grades in `paradiseReveal` / `ordinaryWorld` | the [Lighting presets](#lighting-presets) |
| "Trigger zones" comment on `StoryData.Zones` | Zones |
| `ShowChapter` / `ShowEnding` remotes | `ShowChapterCard` |
| `ClientReady` remote | adapter detail, not a Player event |
| `promptText` | the talk affordance label, kept as content |
| `getState(player)` | Progress |
| `Map.*` coordinates, `position`, `faceZ`, `spawnPoints` | Spots |

## How to propose a new term

1. Check this file first. If a term already covers the idea, use it; do
   not add a synonym.
2. In the PR that first needs the term, add it to the right table here:
   meaning and one example; for an enumeration value, add it to the
   enumeration (marked *later* if it is reserved but not yet used).
3. Use the term, exactly as written here, in code names, content keys,
   tests and the PR description. The PR description says "New term:
   **X**" with one sentence of why.
4. If the term replaces a word people already use, add that word to
   [Words we do not use](#7-words-we-do-not-use).
5. If the term changes the shape of the story model (a new noun in the
   tree, a new kind of event), update section 2.4 of the plan in the same
   PR. The owner approves new terms when reviewing the PR.
