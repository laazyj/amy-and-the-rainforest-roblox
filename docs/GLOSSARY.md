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
| **Talk affordance** | How the player talks to a Character: a prompt on the Character, offered while a `talk` Quest waits for `TalkedTo` (World commands `OfferTalk`, `WithdrawTalk`). | "Say hello (bravely)" on the Lion |
| **Talk label** | The words on a talk affordance; a `talk` Quest's `talkLabel`, "Talk" when it has none. | "Explain" |
| **Companion** | A Character that can follow Amy, help her, and whose Bond with her grows. | Sam; later Squirrel, Fox, Lion |
| **Bond** | A Companion's relationship level with Amy. Persisted. | Fox at `friend` |
| **Pickup** | A Quest-bound thing to touch, spawned at Spots for a `collect` Quest and removed when touched or when the Quest ends. Its id is the Spot it spawned at. | three glowing flowers |
| **Collectible** | A persistent discoverable with a Journal entry. Found once, remembered forever. | `collectible:maroon_acorn` |
| **Journal** | The player's record of Collectibles found and Characters met, with entries in Clara's voice. | |
| **Cue** | A named sound, music track or effect, resolved to an asset id through `assets/manifest.json`. | `cue:sam_bark`, `music:paradise_theme` |
| **Shot** | A named camera framing used by a Beat or a Dialogue. Specified in [`design/feel.md`](design/feel.md). See [enumeration](#shots). | `shot:ForestWallReveal` |
| **Lighting preset** | A named look for a Scene. See [enumeration](#lighting-presets). | `lighting:paradise` |
| **Progress** | Where a player is in the Story: current Chapter and Quest, completed Quest ids, the Pickups touched in the current Quest, which Dialogue is showing, and later Collectibles, Bonds, and the Prop states that matter. Saved on every Story event and on leave. | |
| **Checkpoint** | The Progress snapshot taken at a Chapter start, kept alongside current Progress. "Play this chapter again" restarts from it. | |
| **Resume** | Rebuilding the world for a returning player from Progress alone: `StoryEngine.resume(progress)` returns the World commands that put every Character, Prop, Lighting preset and Pickup where the current Quest expects them, then shows the Objective. "Continue" on the title screen is a Resume. | |
| **World state** | What the World looks like to the Story, as plain data: where each Character stands, each Prop's state, the Lighting preset, the Pickups out, the Objective, the offered talk affordances. What the World commands mean without the engine (`src/core/WorldState.luau`); a Resume rebuilds it. | Sam at `spot:Farm`, `lighting:paradise` |
| **World** | The one interface the core uses to act on the engine. Every Beat is written against it, one method per World command. | `World.moveCharacter(id, spot)` |
| **Objective tracker** | Where the client shows the active Quest's Objective, under the header "✦ Objective". | "Ask Dad if you can go outside" |
| **Client binder** | The client script (`src/client`): it builds the UI, renders the view-model and forwards the player's input. It holds no logic. | `StoryClient.client.luau` |
| **View-model** | The client's logic as plain data in core, which the client binder renders: the Dialogue as it types out and advances (`DialogueViewModel`), the Objective tracker (`ObjectiveText`) and how a Chapter card plays over time (`ChapterCardTimeline`). Tested in tier 1, no client needed. | `DialogueViewModel.view(vm)` |
| **Grapheme** | One character as a reader sees it, which may be several code points: "♥️", "👍🏽". Dialogue types out one grapheme at a time. | `DialogueViewModel.graphemes("♥️") == 1` |
| **Device class** | One of the three first-class targets, each with its own layout and touch rules: `PC`, `Phone`, `Tablet`. Defined in [`design/feel.md`](design/feel.md). | `Tablet` |
| **Walkthrough** | A test that plays the Story, or one Chapter, from start to end by driving a player's inputs, and checks what the server sends back. | `tests/engine/walkthrough.luau` |
| **Fake player** | A stand-in for a Player in a test, where there is no client: a Character to move, plus the identity fields a Player has. | `tests/engine/_fakeplayer.luau` |
| **Golden file** | The recorded, deterministic output of a Walkthrough: every message the server sends, in order, with the active Quest. A behaviour change shows as a diff to it. | `tests/fixtures/golden/walkthrough.json` |

## 3. The verbs

The core is a pure function of events:

```
StoryEngine.step(progress, playerEvent) → progress', storyEvents[], worldCommands[]
```

In code (`src/core/StoryEngine.luau`) the Story is passed too:
`StoryEngine.step(story, progress, event)`, `StoryEngine.start(story,
progress)` for the first Chapter card and Quest, and
`StoryEngine.resume(story, progress)` for a Resume. `StoryEngine.new`
keeps one player's Progress between steps. The types and payload schemas
of all three lists below are in `src/core/Events.luau`.

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
| `FoundCollectible` *later* | `collectible` | The Player Character finds a Collectible |
| `SolvedStep` *later* | `puzzle`, `step` | The player completes one step of a puzzle |

### Story events

| Event | Payload | Meaning |
|---|---|---|
| `ChapterStarted` | `chapter` | A Chapter became `active` |
| `QuestStarted` | `quest` | A Quest became `active` |
| `QuestCompleted` | `quest` | A Quest became `completed` |
| `ChapterCompleted` | `chapter` | A Chapter became `completed` |
| `BeatPlayed` | `beat` | A Beat ran at a Hook |
| `CollectibleFound` *later* | `collectible` | A Collectible went from `hidden` to `found` |
| `BondChanged` *later* | `character`, `from`, `to` | A Companion's Bond moved one level |
| `StoryEnded` | none | The Ending finished |

### World commands

| Command | Arguments | Does |
|---|---|---|
| `ShowDialogue` | `lines` | Shows a Dialogue; the client replies with `DialogueFinished`. Ends the commands of a step: the Story waits for the reply |
| `SetObjective` | `text` or none | Shows or clears the Objective |
| `ShowChapterCard` | `title`, `subtitle`, `ending` | Shows a Chapter card, or the end card when `ending` is true |
| `Wait` | `seconds` | Pauses `seconds` before the next command |
| `MoveCharacter` | `character`, `spot` | Puts a Character at a Spot |
| `TeleportPlayer` | `spot` | Puts the Player Character at a Spot |
| `SetPropState` | `prop`, `state` | Moves a Prop to one of its declared states |
| `PlayCue` *later* | `cue` | Plays a Cue |
| `SetLighting` | `preset` | Applies a Lighting preset |
| `FrameShot` *later* | `shot` | Frames a Shot; the follow camera returns when the Shot ends |
| `OfferTalk` | `character`, `label` | Offers the Character's talk affordance, with its Talk label |
| `WithdrawTalk` | `character` | Withdraws the Character's talk affordance |
| `SpawnPickups` | `quest` | Spawns the Quest's Pickups at their Spots |
| `RemovePickup` | `pickup` | Removes one touched Pickup |
| `ClearPickups` | `quest` | Removes the Quest's remaining Pickups |
| `SaveProgress` *later* | none | Writes Progress |
| `SaveCheckpoint` *later* | `chapter` | Writes the Checkpoint for a Chapter |

If a Beat needs something these commands cannot do, the World interface
grows by one named command, recorded here in the same PR. *Later*:
reserved, not yet implemented.

**On the wire.** `src/core/Net.luau` is the contract between server and
client. Three World commands reach the client, over remotes whose names
predate this glossary and are kept so the golden file still matches:
`ShowDialogue`, `SetObjective`, and `ShowChapterCard` as `ShowChapter`
(or `ShowEnding` for the end card). The client sends `DialogueFinished`,
and `ClientReady` once it has loaded, which starts the Story; that is an
adapter detail, not a Player event. Both sides hold every payload to the
contract: the server checks each World command against its schema in
`src/core/Events.luau` and each message before it sends it, and the client
binder wraps every remote it receives in `Net.guard`, which drops a
malformed payload; tier 2 (`tests/engine/contract.luau`) passes every
payload in the golden file through that guard.

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

| Character | Kind | Display name | Home Spot | Notes |
|---|---|---|---|---|
| `Narrator` | none | Narrator | none | Speaker only; not a Character, never in the world |
| `character:Amy` | `human` | Amy | `spot:AmySpawn` | The Player Character; spawns in the garden |
| `character:Dad` | `human` | Dad | `spot:DadHome` | Home in the garden |
| `character:Mum` | `human` | Mum | `spot:MumHome` | Home in the garden |
| `character:Sam` | `dog` | Sam the Dog | `spot:SamHome` | Companion; home in the garden, by the gate |
| `character:Squirrel` | `squirrel` | the Maroon Squirrel | `spot:SquirrelHome` | Home in the paradise |
| `character:Fox` | `fox` | the Orange Fox | `spot:FoxHome` | Home in the paradise |
| `character:Lion` | `lion` | the Golden Lion | `spot:LionHome` | Home in the paradise, deep glade |

### Hook names

| Hook | Runs when |
|---|---|
| `onStart` | The Quest becomes `active`, before its Objective and intro Dialogue are shown |
| `onComplete` | The Quest becomes `completed`, after its outro Dialogue has finished |

In a Chapter's `data.luau` a Quest names the Beats each Hook plays,
`hooks = { onComplete = { "sam_catches" } }`; the Beats themselves are in
its `hooks.luau`.

### Beats

| Beat | Hook | Does |
|---|---|---|
| `beat:sam_catches` | `chapter1.sneak_out_1.onComplete`, `chapter1.sneak_out_2.onComplete` | Sam runs to the gate and brings Amy back into the garden |
| `beat:sam_goes_to_farm` | `chapter2.walk_to_forest.onStart` | Sam leaves for the farm |
| `beat:paradise_reveal` | `chapter2.enter_forest.onComplete` | `SetLighting(lighting:paradise)` |
| `beat:ordinary_world` | `chapter3.rush_home.onComplete` | `SetLighting(lighting:ordinary)` |
| `beat:machine_arrives` | `chapter3.tell_mum.onComplete` | The machine and villagers arrive; Dad, Mum and Sam move to the field |
| `beat:machine_stops` | `chapter4.explain.onComplete` | The blade stops, sparkles over the crowd, the machine reverses away |

### Spots

| Spot | Scene | Used for |
|---|---|---|
| `spot:AmySpawn` | `scene:Garden` | Amy's home Spot: where she spawns |
| `spot:DadHome` | `scene:Garden` | Dad's home Spot |
| `spot:MumHome` | `scene:Garden` | Mum's home Spot |
| `spot:SamHome` | `scene:Garden` | Sam's home Spot, by the gate |
| `spot:GateOutside` | `scene:Garden` | `beat:sam_catches`: Sam bounds to just outside the gate |
| `spot:GardenInside` | `scene:Garden` | `beat:sam_catches`: Amy lands back in the garden |
| `spot:SamGuardPost` | `scene:Garden` | `beat:sam_catches`: Sam settles beside her |
| `spot:Farm` | `scene:Village` | `beat:sam_goes_to_farm` |
| `spot:MachineBay` | `scene:Field` | Where `prop:Machine` parks |
| `spot:DadAtMachine` | `scene:Field` | `beat:machine_arrives` |
| `spot:MumAtMachine` | `scene:Field` | `beat:machine_arrives` |
| `spot:SamAtMachine` | `scene:Field` | `beat:machine_arrives` |
| `spot:Villager1` | `scene:Field` | Where `prop:Villagers` stand, one each |
| `spot:Villager2` | `scene:Field` | |
| `spot:Villager3` | `scene:Field` | |
| `spot:Villager4` | `scene:Field` | |
| `spot:SquirrelHome` | `scene:Paradise` | The Squirrel's home Spot |
| `spot:FoxHome` | `scene:Paradise` | The Fox's home Spot |
| `spot:LionHome` | `scene:Paradise` | The Lion's home Spot, in the deep glade |

### Zones

| Zone | Scene | Used by |
|---|---|---|
| `zone:GardenGate` | `scene:Garden` | `chapter1.sneak_out_1`, `chapter1.sneak_out_2` |
| `zone:ForestEdge` | `scene:Field` | `chapter2.walk_to_forest` |
| `zone:ForestGap` | `scene:ForestWall` | `chapter2.enter_forest` |
| `zone:HeartGlade` | `scene:HeartGlade` | `chapter2.heart_glade` |
| `zone:HomeGarden` | `scene:Garden` | `chapter3.rush_home` |
| `zone:MachineFront` | `scene:Field` | `chapter4.stand_in_front` |

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
| `prop:Villagers` | `absent`, `gathered`, `cheering` |

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

## Invariants

Rules that hold in every version of the game. A change that would break
one is not a valid change.

| Invariant | Meaning | Checked by |
|---|---|---|
| Single player | Max Players = 1; the Story is never shared between players | Tier 2 |
| Amy's face is never seen | The Player Character is only ever seen from behind: the camera rule in [`design/feel.md`](design/feel.md#invariants), every Shot, and all art | Tier 3; release checklist for art |

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
