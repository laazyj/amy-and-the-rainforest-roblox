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
| **Line** | One thing said: Speaker, text, and a `canon` flag; a canon Line may be narrated (see Narration). | Narrator: "She tryed again but Sam brang her back." |
| **Canon** | A property of a Line: the text is Clara's exact words and is locked. Every canon Line is checked byte for byte against [`story/canon.md`](story/canon.md). New Lines in Clara's voice are not canon until she says so. | |
| **Speaker** | Who says a Line: the Narrator, Amy, or another Character. Stored as a Character id, displayed by the Character's display name. See [enumeration](#characters-and-speakers). | `Narrator` |
| **Narrator** | The storyteller's voice. Canon Lines are almost always the Narrator's; a Narrator Line is not canon unless marked. | |
| **Beat** | A named, staged moment: a fixed list of World commands, with optional waits, played at a Hook. Beats are how the story moves the world. See [enumeration](#beats). | `beat:sam_catches` |
| **Hook** | A point in a Quest's life where Beats run. Declared in the Chapter's `hooks.luau`. See [enumeration](#hook-names). | `chapter1.sneak_out_1.onComplete → sam_catches` |
| **Scene** | A part of the world with its own look and sound: terrain, Props, Spots, Zones, and the music and ambience Cues that play while Amy is inside its **bounds**, a box in the Scene's file. See [enumeration](#scenes). | `scene:ForestWall` |
| **Spot** | A named position and facing inside a Scene. Content never holds raw coordinates; it names Spots. | `spot:GardenGateInside` |
| **Zone** | A named invisible volume the player can enter. Entering one is the Player event `EnteredZone`. See [enumeration](#zones). | `zone:ForestGap` |
| **Prop** | A placed object with named states. See [enumeration](#props). | `prop:Machine` |
| **Character** | A named being in the world with a kind, a display name and a home Spot. A human is built from its Description; any other Character from its Character model, or as its Placeholder until it has one (`Story.build`). Every Character has a Humanoid and plays its `idle` animation, and its `run` one while it runs. See [enumeration](#characters-and-speakers). | `character:Sam` "Sam the Dog" |
| **Description** | How a human Character looks: the colour of each part of its R15 body (head, torso, arms, legs), from Clara's palette, in `src/content/characters.luau` (the villagers' in `scene:Field`'s file). `server/CharacterHost` makes it a HumanoidDescription; the Player Character wears hers from the moment she spawns. Catalog items (hair, clothes) are to be added to it once chosen. | Amy: the red jumper, the blue skirt |
| **Character model** | A free Creator Store model a Character is built from, with its Humanoid and its animations (an Animations folder holding `idle`, `walk` and `run`): an Asset of kind `model`, named for its Character (`character:Sam`), at `assets/meshes/characters/<id>.rbxm`, which the place file holds in `ServerStorage.CharacterModels`. Fetched on the Mac ([`ASSETS.md`](ASSETS.md#character-models)). | `character:Sam` |
| **Player Character** | The Character the player controls. The player **is Amy**. | `character:Amy` |
| **Talk affordance** | How the player talks to a Character: a prompt on the Character, offered while a `talk` Quest waits for `TalkedTo` (World commands `OfferTalk`, `WithdrawTalk`). | "Say hello (bravely)" on the Lion |
| **Talk label** | The words on a talk affordance; a `talk` Quest's `talkLabel`, "Talk" when it has none. | "Explain" |
| **Companion** | A Character that can follow Amy, help her, and whose Bond with her grows. How it goes about with her is a state machine in core (`src/core/Companion.luau`), in the [Companion states](#companion-states); moving it is the adapter's. | Sam; later Squirrel, Fox, Lion |
| **Bond** | A Companion's relationship level with Amy. Persisted. | Fox at `friend` |
| **Pickup** | A Quest-bound thing to touch, spawned at Spots for a `collect` Quest and removed when touched or when the Quest ends. Its id is the Spot it spawned at. | three glowing flowers |
| **Collectible** | A persistent discoverable with a Journal entry. Found once, remembered forever. | `collectible:maroon_acorn` |
| **Journal** | The player's record of Collectibles found and Characters met, with entries in Clara's voice. | |
| **Cue** | A named sound, music track or effect, resolved to an Asset through the Manifest; a Cue with no asset id yet is silent, never an error. Content names Scenes' music and ambience and the Cues Beats play; `src/core/Cues.luau` names the rest. See [enumeration](#cues). | `cue:sam_bark`, `music:paradise` |
| **Soundscape** | What plays under the Story: the music and ambience of the Scene Amy is in (the one with the smallest bounds that hold her), the theme instead while the Title screen or a card shows, and her footsteps. A view-model (`src/core/Soundscape.luau`) rendered by the client's Audio adapter (`src/client/Audio.luau`), which crossfades each change. | the Garden's `music:home` under `cue:ambience_home` |
| **Narration** | Canon Lines read aloud: each Chapter's in one recorded file, `narration:<chapter id>` (the last Chapter's reads the Ending's too), played while the dialogue box shows the Line. The **Narration table** (`src/content/narration.luau`) gives each Line's part of its file in seconds. A Line with no part, or whose file has no id yet, is shown as text only; narration never advances a Dialogue. | `narration:chapter1` |
| **Asset** | An image, sound, model or font the game or its store page uses, listed in the Manifest and uploaded to Roblox by CI when the game shows it (a font, or a track from Roblox's audio library, is on the Creator Store, referenced by its id and never uploaded). Known by its Asset name, an id of the forms in [Ids](#6-ids). See [`ASSETS.md`](ASSETS.md). | `card:chapter2` |
| **Manifest** | `assets/manifest.json`: every Asset with its file, Roblox asset id, creator, licence, origin and Moderation status. | |
| **Moderation status** | Where Roblox moderation is with an Asset. See [Lifecycles](#5-lifecycles). | `approved` |
| **Placeholder** | A stand-in until the real piece replaces it: a plain palette-coloured image with no text for an illustration not drawn yet, or a Character built of parts until its Character model is in the place, its colours, size against the dog's and tail (`up`, `fluff`, `brush` or `tuft`) given in `src/content/characters.luau`. | `card:chapter1`; Sam as the white dog of parts |
| **Shot** | A named camera framing used by a Beat or a Dialogue. Specified in [`design/feel.md`](design/feel.md). See [enumeration](#shots). | `shot:ForestWallReveal` |
| **Camera rule** | The camera stays within 60° of directly behind Amy: unit(camera − Amy) · (−facing) ≥ 0.5, at every frame. Specified in [`design/feel.md`](design/feel.md#invariants). | |
| **Follow camera** | The camera in free play: behind Amy, who turns with the view as with shift-lock. Every Shot takes the camera from it and hands it back. | |
| **Camera model** | The camera as plain data (`src/core/CameraModel.luau`): a **Rig** is a camera placement relative to Amy (her facing, the camera's angles from directly behind her, its distance, its look-at), and a **Frame** is what one frame renders (camera, look-at, Amy's facing, the Shot). `src/client/Camera.luau` renders it. | `CameraModel.step(camera, seconds, amy, subject)` |
| **Lighting preset** | A named look for a Scene. See [enumeration](#lighting-presets). | `lighting:paradise` |
| **Progress** | Where a player is in the Story: current Chapter and Quest, completed Quest ids, the Pickups touched in the current Quest, which Dialogue is showing, and later Collectibles, Bonds, and the Prop states that matter. Kept in the Save. | |
| **Checkpoint** | The Progress snapshot taken at a Chapter start, kept in the Save alongside current Progress, one per Chapter reached. "Play this chapter again" restarts from it. | the Checkpoint of `chapter2`: every Chapter One Quest completed, `chapter2.walk_to_forest` just started |
| **Save** | What is kept for a player between visits: their Progress, their Checkpoints and their Settings, under a schema version (`src/core/Save.luau`). One Save per player, keyed by Roblox user id, kept by `src/server/Persist.luau` with ProfileStore and written on every Story event and on leave. | |
| **Schema version** | The version of a Save's shape. A version only adds fields, so code reads a Save one version newer as its own (Release can roll back one version); a Save two or more versions newer is not read and never written over. | version 3 |
| **Fault** | Something that went wrong for a player and is worth counting, by a name that reads as an analytics event name. See [enumeration](#faults). | `save_load_timeout` |
| **Migration** | Turns a Save of one schema version into the next, with a tier 1 test each. | 1 → 2 adds the Checkpoints, 2 → 3 the Settings |
| **Setting** | One of a player's choices about how the game looks and sounds, kept in their Save and applied by the client binder: the volume, the Text scale, high contrast and the dyslexia-friendly font. Its values are plain data (`src/core/Settings.luau`). The server sends a player's Settings when they join (`ApplySettings`) if they are not the defaults, and the client sends each change (`ChangeSettings`). See [enumeration](#settings). | `highContrast` on |
| **Pause screen** | What the pause button (top right of the safe area, or P on a PC) opens: Resume, and its Settings page with a row per Setting. While it is open the Story does not advance: the client takes no input to it, and the server, told by `SetPaused`, holds every Wait. Its view-model is `src/core/PauseScreen.luau`. | the Settings page |
| **Analytics event** | What the server logs to Roblox Analytics: a custom event named after a Story event, a Fault, or `SessionEnded` (a visit's end, its value the seconds played), with the payload as custom fields (`src/core/AnalyticsEvents.luau`, [`ANALYTICS.md`](ANALYTICS.md)). | `QuestCompleted` `chapter3.meet_fox` |
| **Title screen** | What a player sees first: feel.md's title over `ui:title_screen`, also shown while the client loads. A returning player is offered the Title choices on it; a player with no Save goes straight to the first Chapter card. Its view-model is `src/core/TitleScreen.luau`; its lettering (the font of the title and of the pill label) is in `src/content/title.luau`: Dancing Script, the manifest's `font:dancing_script`. | |
| **Title choice** | What a returning player picks on the Title screen: `continue` ("Continue", a Resume at the current Quest), `replay` ("Play this chapter again", a Resume at the Chapter's Checkpoint) or `restart` ("Start again", behind a confirmation: a new Save). | `replay` |
| **Resume** | Rebuilding the world for a returning player from Progress alone: `StoryEngine.resume(progress)` returns the World commands that put every Character, Prop, Lighting preset and Pickup where the current Quest expects them, then shows the Objective. "Continue" on the title screen is a Resume. | |
| **World state** | What the World looks like to the Story, as plain data: where each Character stands, each Prop's state, the Lighting preset, the Pickups out, the Objective, the offered talk affordances. What the World commands mean without the engine (`src/core/WorldState.luau`); a Resume rebuilds it. | Sam at `spot:Farm`, `lighting:paradise` |
| **World** | The one interface the core uses to act on the engine. Every Beat is written against it, one method per World command. | `World.moveCharacter(id, spot)` |
| **Objective tracker** | Where the client shows the active Quest's Objective, under the header "Objective" (on a Phone, collapsed to a gold marker while a Dialogue shows). | "Ask Dad if you can go outside" |
| **Client binder** | The client script (`src/client`): it builds the UI, renders the view-model and forwards the player's input. It holds no logic. | `StoryClient.client.luau` |
| **View-model** | The client's logic as plain data in core, which the client binder renders: the Dialogue as it types out and advances (`DialogueViewModel`), the Objective tracker (`ObjectiveText`), how a Chapter card plays over time (`ChapterCardTimeline`), the Title screen (`TitleScreen`), the Onboarding (`Onboarding`), the Talk-and-advance button (`TalkAndAdvance`), the Pause screen (`PauseScreen`) and the Settings page (`Settings`); the Screen layout (`ScreenLayout`) says where they go. Tested in tier 1, no client needed. | `DialogueViewModel.view(vm)` |
| **Grapheme** | One character as a reader sees it, which may be several code points: "♥️", "👍🏽". Dialogue types out one grapheme at a time. | `DialogueViewModel.graphemes("♥️") == 1` |
| **Dev shortcut** | A Dev-only way to reach any point of the Story in seconds: the chat commands `/chapter N` and `/quest <id>`, and the jump-to-Quest entry point (`DevShortcuts.jumpTo`). A jump is a Resume at the Progress of a player who has just started the Quest, and is saved: the Save holds that Progress and the Checkpoints of every Chapter up to it. `/title` offers the Title screen at the current Progress, as to a returning player; the Story waits for the Title choice, and Continue carries on where the player was (a jump instead, `/title` then `/chapter N`, leaves the Title screen showing until a button is pressed). Release builds have none: the release job strips them when it publishes. | `/chapter 3` |
| **Device class** | One of the three first-class targets, each with its own layout and touch rules: `PC`, `Phone`, `Tablet`. Defined in [`design/feel.md`](design/feel.md). Picked by `src/core/DeviceClass.luau` from the Input kind and the viewport's shorter side (under 600 units is a Phone), again on every viewport change. | `Tablet` |
| **Input kind** | What the player last used: `pointer` (a keyboard or a mouse), `touch` or `gamepad`. A Device class is picked from it. | `touch` |
| **Screen layout** | Where everything on screen goes and how big its text is, for one Device class, orientation, safe area and Text scale (`src/core/ScreenLayout.luau`): the dialogue box and its 60-character column, the Objective tracker, the touch control zones, the Chapter card and the Title screen. Tier 1 holds feel.md's rules on it. Not the content's `layout.luau`, which places things in the world. | `ScreenLayout.new(screen)` |
| **Safe area** | The part of the screen clear of the notch, the home bar, rounded corners and Roblox's top bar. All UI sits inside it. | |
| **Text scale** | How much larger than its size for the Device class all text is drawn: 1 to 1.5, the Text size Setting, capped on each device at the largest scale at which every Line fits the dialogue box (`ScreenLayout.largestScale`); the Settings page says when the cap applies. Every layout rule holds at every Text scale. | `1.5` |
| **Touch control zone** | The bottom-left (Roblox's thumbstick's, which stays where Roblox puts it) and bottom-right (the button row's) corners of the screen on a Phone (35% x 40%) or a Tablet (25% x 35%). A drag that starts outside them turns the view. | |
| **Talk-and-advance button** | The button in the button row on every class: it advances a Dialogue, or else uses the nearest talk prompt (`src/core/TalkAndAdvance.luau`). Its word is "Talk", or "Next" while a Dialogue shows. It shows only while a Dialogue shows or a prompt is within reach; with neither it would do nothing, so it hides. | "Talk", "Next" |
| **Button row** | The buttons at the bottom right of the screen on every class: the Talk-and-advance button in the corner, and the Onboarding's Skip button beside it while a Hint shows in free play (above it where a row would leave the right touch control zone). | |
| **Onboarding** | The first minute of a fresh Save, which teaches the three verbs (walk, talk, advance) inside Chapter One, in Onboarding steps with Hints (`src/core/Onboarding.luau`). Never blocks play and can be skipped. A Resume never shows it. | |
| **Onboarding step** | One step of the Onboarding, with what the player sees, its Hint and when it is done. See [enumeration](#onboarding-steps). | `onboarding:walk` |
| **Hint** | A short UI Line in Clara's voice that teaches a verb during the Onboarding, shown when needed and gone on success. Hints are kept in `src/content/hints.luau`; they are not canon. | "Drag here to walk" |
| **Contrast** | How well text stands out from what is behind it: WCAG 2's ratio of their luminances, at least 4.5:1 for all text, and 7:1 in the dialogue box with the high-contrast Setting (`src/core/Contrast.luau`). | name tags at 4.68:1 |
| **Walkthrough** | A test that plays the Story, or one Chapter, from start to end by driving a player's inputs, and checks what the server sends back. | `tests/engine/walkthrough.luau` |
| **Fake player** | A stand-in for a Player in a test, where there is no client: a Character to move, plus the identity fields a Player has. | `tests/engine/_fakeplayer.luau` |
| **Golden file** | The recorded, deterministic output of a Walkthrough: every message the server sends, in order, with the active Quest. A behaviour change shows as a diff to it. | `tests/fixtures/golden/walkthrough.json` |
| **Capture** | One screenshot the Studio playtest takes on one device: at a Shot, a Chapter card, a Scene entry or the Title screen, named `<device>/<nn>-<kind>-<name>.png`. | `pc/03-shot-gate-wide.png` |
| **Contact sheet** | One image of every Capture of one device, each labelled with its name, posted on the pull request the playtest played. | `sheets/pc.png` |
| **Baseline** | The accepted Capture a new one is compared with: one per Capture per device in `docs/screens/`, changed only by merging a Baselines pull request, never by hand. | `docs/screens/pc/03-shot-gate-wide.png` |

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
| `MoveCharacter` | `character`, `spot`, `run` or none | Puts a Character at a Spot. With `run`, the Character sets off running there with its run animation (`Humanoid:MoveTo`) and stands at the Spot once it arrives, or after at most 3 seconds; the Beat goes straight on, so it gives the run its time with a `Wait`, which the Pause screen holds |
| `TeleportPlayer` | `spot` | Puts the Player Character at a Spot |
| `SetPropState` | `prop`, `state` | Moves a Prop to one of its declared states |
| `PlayCue` | `cue` | Plays a sound Cue (`cue:`) once on the client; music and ambience follow the Soundscape |
| `SetLighting` | `preset` | Applies a Lighting preset |
| `FrameShot` | `shot`, `character` or none | Frames a Shot, of the Character when the Shot takes one; the follow camera returns when the Shot ends |
| `OfferTalk` | `character`, `label` | Offers the Character's talk affordance, with its Talk label |
| `WithdrawTalk` | `character` | Withdraws the Character's talk affordance |
| `SpawnPickups` | `quest` | Spawns the Quest's Pickups at their Spots |
| `RemovePickup` | `pickup` | Removes one touched Pickup |
| `ClearPickups` | `quest` | Removes the Quest's remaining Pickups |

Saving is not a World command: the server adapter writes the Save after
every step that raised Story events, so no Beat can save, skip a save, or
change what a fresh player is sent.

If a Beat needs something these commands cannot do, the World interface
grows by one named command, recorded here in the same PR. *Later*:
reserved, not yet implemented.

**On the wire.** `src/core/Net.luau` is the contract between server and
client. Five World commands reach the client: `FrameShot`, `PlayCue`, and three
over remotes whose names predate this glossary and are kept so the
golden file still matches: `ShowDialogue`, `SetObjective`, and
`ShowChapterCard` as `ShowChapter` (or `ShowEnding` for the end card).
The client sends `DialogueFinished`, and `ClientReady` once it has
loaded, which starts the Story; that is an adapter detail, not a Player
event. The Title screen travels the same way: `ShowTitle` (the Chapter a
returning player is in, and whether there is a Quest to continue) and
the client's `TitleChoice`; only a returning player is sent `ShowTitle`,
so the golden file has none. A player's Settings travel as `ApplySettings`
(to the client at join, only when they are not the defaults, so the
golden file has none either) and `ChangeSettings` (to the server, on each
change), held to every allowed value. The client's `SetPaused` says
the Pause screen opened or closed; a fresh player never pauses, so the
golden file has none of these. Both sides hold every payload to the
contract: the server checks each World command against its schema in
`src/core/Events.luau` and each message before it sends it, and the
client binder wraps every remote it receives in `Net.guard`, which drops
a malformed payload; tier 2 (`tests/engine/contract.luau`) passes every
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
| `onTalkedTo` | A `talk` Quest's Character is talked to (`TalkedTo`), before its `dialogue` Dialogue is shown |
| `onComplete` | The Quest becomes `completed`, after its outro Dialogue has finished |

In a Chapter's `data.luau` a Quest names the Beats each Hook plays,
`hooks = { onComplete = { "sam_catches" } }`; the Beats themselves are in
its `hooks.luau`.

### Beats

| Beat | Hook | Does |
|---|---|---|
| `beat:sam_catches` | `chapter1.sneak_out_1.onComplete`, `chapter1.sneak_out_2.onComplete` | `PlayCue(cue:sam_bark)`; Sam runs after Amy to the gate (`MoveCharacter(Sam, spot:GateOutside, run)`, then `Wait` 1 s) and brings her back into the garden |
| `beat:sam_goes_to_farm` | `chapter2.walk_to_forest.onStart` | Sam leaves for the farm |
| `beat:forest_wall_reveal` | `chapter2.walk_to_forest.onComplete` | `FrameShot(shot:ForestWallReveal)`: the wall of trees, the gap centred |
| `beat:paradise_reveal` | `chapter2.enter_forest.onComplete` | `PlayCue(cue:paradise_shimmer)`, `SetLighting(lighting:paradise)` |
| `beat:meet_squirrel` | `chapter3.meet_squirrel.onTalkedTo` | `FrameShot(shot:MeetCharacter, character:Squirrel)` |
| `beat:meet_fox` | `chapter3.meet_fox.onTalkedTo` | `FrameShot(shot:MeetCharacter, character:Fox)` |
| `beat:meet_lion` | `chapter3.meet_lion.onTalkedTo` | `FrameShot(shot:MeetCharacter, character:Lion)` |
| `beat:ordinary_world` | `chapter3.rush_home.onComplete` | `SetLighting(lighting:ordinary)` |
| `beat:machine_arrives` | `chapter3.tell_mum.onComplete` | `PlayCue(cue:machine_rumble)`; the machine and villagers arrive; Dad, Mum and Sam move to the field |
| `beat:machine_stops` | `chapter4.explain.onComplete` | Framed by `shot:MachineFinale`, which holds through the Ending's Lines: the blade stops (`PlayCue(cue:machine_stop)`), sparkles over the crowd, the machine reverses away |

### Spots

| Spot | Scene | Used for |
|---|---|---|
| `spot:AmySpawn` | `scene:Garden` | Amy's home Spot: where she spawns |
| `spot:DadHome` | `scene:Garden` | Dad's home Spot |
| `spot:MumHome` | `scene:Garden` | Mum's home Spot |
| `spot:SamHome` | `scene:Garden` | Sam's home Spot, by the gate |
| `spot:GateOutside` | `scene:Garden` | `beat:sam_catches`: Sam runs to Amy, just outside the gate |
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
| `shot:Dialogue` | the Dialogue's first Speaker who is a Character in the world; the core frames it before every such Dialogue (`src/core/Shot.luau`) |
| `shot:ForestWallReveal` | none |
| `shot:MeetCharacter` | the Character being met |
| `shot:MachineFinale` | none |

### Companion states

How a Companion goes about with Amy (`src/core/Companion.luau`). The
adapter steps it with how far it is from Amy (and from the Spot it leads
to), and it answers where it goes: nowhere, to Amy, or to the Spot, walking
or running.

| State | Does |
|---|---|
| `idle` | Stands where it is; while following, sets off once Amy is more than 10 studs away |
| `follow` | Goes to Amy, walking, running while she is more than 18 studs away; stands again within 5 studs |
| `react` | Stands and reacts (a bark, a look) for a while, then goes back to what it was doing |
| `lead` | Goes ahead to a Spot, waiting while Amy is more than 16 studs behind; stands once within 2 studs of it |

### Onboarding steps

In order; specified in [`design/feel.md`](design/feel.md#6-onboarding-the-first-minute).
`src/content/hints.luau` gives a Hint only for these steps.

| Step | Shows | Done when |
|---|---|---|
| `onboarding:card` | The `chapter1` card; a tap or click skips it | The card is gone |
| `onboarding:advance` | The first Narrator Line, with its Hint large | `DialogueFinished` |
| `onboarding:objective` | The first Objective, a marker over Dad; the tracker glows | The Objective is shown |
| `onboarding:walk` | The walk Hint; on touch a ring on the thumbstick | Amy has moved 4 studs |
| `onboarding:talk` | The talk Hint once Dad's prompt shows; on touch the Talk-and-advance button pulses | `TalkedTo(Dad)` |
| `onboarding:listen` | Dad's Dialogue, no Hint | The next Objective (`QuestCompleted(chapter1.ask_dad)`) |

### Cues

Each is an Asset in the Manifest (`cue:<name>` for sounds, `music:<name>`
for music), a synthesised placeholder until the owner's pick replaces it
([`ASSETS.md`](ASSETS.md#cues-the-placeholders-and-the-shopping-list)).
Tier 1 holds every Cue named in content and `src/core/Cues.luau` to this
table and to the Manifest.

| Cue | Layer | Plays |
|---|---|---|
| `music:theme` | music | While the Title screen, a Chapter card or the end card shows |
| `music:home` | music | `scene:Garden`, `scene:Village` |
| `music:field` | music | `scene:Field`, `scene:ForestWall` |
| `music:paradise` | music | `scene:Paradise`, `scene:HeartGlade` |
| `cue:ambience_home` | ambience | `scene:Garden`, `scene:Village` |
| `cue:ambience_field` | ambience | `scene:Field`, `scene:ForestWall` |
| `cue:ambience_paradise` | ambience | `scene:Paradise`, `scene:HeartGlade` |
| `cue:chapter_card` | effect | A Chapter card or the end card appears |
| `cue:prompt` | effect | The player uses a talk affordance |
| `cue:pickup` | effect | `TouchedPickup` in a `collect` Quest |
| `cue:footstep` | effect | Each of Amy's steps on the ground |
| `cue:sam_bark` | effect | `beat:sam_catches` |
| `cue:paradise_shimmer` | effect | `beat:paradise_reveal` |
| `cue:machine_rumble` | effect | `beat:machine_arrives` |
| `cue:machine_stop` | effect | `beat:machine_stops` |

### Settings

In the order the Settings page lists them; the defaults first in each
row's values (`src/core/Settings.luau`).

| Setting | Values | Does |
|---|---|---|
| `volume` | `1`, `0.75`, `0.5`, `0.25`, `0` | The volume of every sound, through the SoundGroup `SoundService.Master` |
| `textScale` | `1`, `1.25`, `1.5` | The Text scale, capped per device |
| `highContrast` | `false`, `true` | The dialogue box opaque and darker, every Line, name and hint on it at 7:1 |
| `font` | `standard`, `dyslexia` | The dyslexia-friendly font (Comic Neue Angular) on the Lines, the Objective, the Hints and the Pause screen's labels |

### Faults

What can go wrong for a player and is worth counting
(`src/core/Fault.luau`). The server reports each through
`src/server/FaultLog.luau`: a warning line, `[Fault] <name> player
<id>: <why>`, and an Analytics event of the same name.

| Fault | Reported when |
|---|---|
| `save_unreadable` | The player's data is no Save of any version: kept aside under `unreadable` in a new Save, and the player starts afresh |
| `save_too_new` | The player's Save is two or more schema versions newer: never written over, and the player plays without saving |
| `save_load_timeout` | The player's Save did not load within `Persist.LOAD_TIMEOUT`: the player plays without saving |
| `save_unavailable` | The server has no ProfileStore package: every player plays without saving |
| `save_close_unbound` | Persist could not bind its release to BindToClose |

## 5. Lifecycles

| Thing | States, in order |
|---|---|
| Chapter | `locked`, `active`, `completed` |
| Quest | `pending`, `active`, `completed` |
| Bond | `stranger`, `curious`, `friend`, `companion` |
| Prop | declared per Prop in [Props](#props) |
| Collectible (per player) | `hidden`, `found` |
| Moderation status (per Asset) | `pending`, `reviewing`, then `approved` or `rejected` |

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
| Onboarding step | `onboarding:<snake_case>` | `onboarding:walk` |
| Asset: Chapter card or end card | `card:<chapter id>`, `card:end` | `card:chapter2` |
| Asset: UI frame, motif or screen | `ui:<snake_case>` | `ui:dialogue_frame`, `ui:title_screen` |
| Asset: store page art | `store:<snake_case>` | `store:icon`, `store:thumbnail_1` |
| Asset: reference for building a Character or Prop | `ref:<the Character's or Prop's PascalCase name>` | `ref:Sam`, `ref:Machine` |
| Asset: a Character model, a Prop's model or a Cue's sound | the Character's, Prop's or Cue's own id | `character:Sam`, `prop:Machine`, `cue:sam_bark` |
| Asset: a Creator Store font family | `font:<snake_case>` | `font:dancing_script` |
| Asset: a Chapter's narration file | `narration:<chapter id>` | `narration:chapter1` |
| Collectible | `collectible:<snake_case>` | `collectible:maroon_acorn` |

Inside content files the prefix is dropped where the field already says
what it is (`zone = "ForestGap"`, `speaker = "Sam"`); in prose, briefs and
PRs, use the prefixed form.

## 7. Words we do not use

| Say | Not |
|---|---|
| Character | NPC, actor, figure |
| Character model | rig (a Rig is the Camera model's) |
| Zone | trigger, region, area |
| Beat | cutscene, sequence, special, scripted moment |
| Quest | mission |
| Line | message |
| Shot | camera angle |
| Setting | option, preference |

## Invariants

Rules that hold in every version of the game. A change that would break
one is not a valid change.

| Invariant | Meaning | Checked by |
|---|---|---|
| Single player | Max Players = 1; the Story is never shared between players | Tier 2 |
| Amy's face is never seen | The Player Character is only ever seen from behind: the camera rule in [`design/feel.md`](design/feel.md#invariants), every Shot, and all art | Tier 3; release checklist for art |
| No timed reading | A Dialogue never moves on by itself: each Line stays until the player advances it, the client binder reaches its advance only from the player's input, and the server waits for every `DialogueFinished`. (A Chapter card, which holds no Line, is timed and can be skipped.) | Tier 1 (`DialogueViewModel.spec`, the Wiring spec) and the mutation check |

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
