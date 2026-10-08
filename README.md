# Amy and the Rain Forest — a solo Roblox story game

A gentle, single-player, story-driven Roblox adventure based on
**"Amy and the Rain Forest" by Clara Dineen-Duffett**
([clara.jasonduffett.net](https://clara.jasonduffett.net)).

You play as Amy, who isn't allowed outside because of the huge rain
forest — and whose dog Sam keeps dragging her back every time she tries
to sneak out. When Sam is away at a farm, Amy slips out at last,
squeezes through the wall of giant trees, and discovers a world
parallel to their own: a beautiful paradise, home to a maroon squirrel,
an orange fox and a golden lion. But when the village hears about it,
they build a giant tree-chopping machine... and only Amy, standing in
front of it, can convince them the forest is something to be proud of
and take care of.

**Four chapters, ~10–15 minutes of play:**

1. **One Beautyfull Sunday** — Dad says no; Sam catches Amy at the gate (twice!)
2. **The Unexplored World** — Sam's at the farm; the dark forest looms; squeeze through the gap
3. **So Many Animals!** — meet the squirrel, the fox and the lion, then rush home to tell Mum
4. **The Giant Tree-Chopping Machine** — stand in front of it and save the paradise

Narrator lines quoted from Clara's story keep her original spelling on
purpose — "One beautyfull sunday", "Sam brang her back" — just like the
highlights on the website.

The scenery follows the site's hand-drawn hero illustration: a cream
sky with little black birds, a wide scribbly-grass field, and the rain
forest as a looming wall of giant trunks standing shoulder to shoulder,
round two-tone canopies on top (bird nests and all) with one narrow
gap, just Amy's size. The paradise inside uses the site's own palette:
moss, gold, bubblegum pink and grape purple.

## Where this is going

The game is an early proof of concept. The plan to take it to a public
release with Dev/Release channels, an automated test harness and
agent-driven feature development is in
[`docs/DEVELOPMENT_PLAN.md`](docs/DEVELOPMENT_PLAN.md).

## How to play it

1. Install [Roblox Studio](https://create.roblox.com/) (free).
2. Download the place file: open the latest successful
   [CI run](https://github.com/laazyj/amy-and-the-rainforest-roblox/actions/workflows/ci.yml)
   on `main` (or the latest release) and download the **`place`** artifact.
   Unzip it to get `AmyAndTheRainforest.rbxl`.
3. In Roblox Studio: **File → Open from File…** and pick it.
4. Press **Play** (F5). The whole world is built by script when the
   game starts — no assets to install.

Or build it yourself from source with [Rojo](https://rojo.space): install
[Rokit](https://github.com/rojo-rbx/rokit), run `rokit install`, then
`tools/build.sh`, which writes `build/AmyAndTheRainforest.rbxl`. To edit
live, run `rojo serve` and connect from the Rojo plugin in Studio.

Controls: normal Roblox movement (WASD + Space). Walk up to characters
and press **E** to talk; click / **E** / **Space** to advance dialogue.

## Project layout

| Path | What it is |
|---|---|
| `src/ReplicatedStorage/StoryData.lua` | **The story**: chapters, quests, dialogue, positions |
| `src/ServerScriptService/WorldBuilder.server.lua` | Builds the map: village, field, forest wall, paradise |
| `src/ServerScriptService/StoryServer.server.lua` | Quest engine: characters, prompts, zones, Sam, the machine |
| `src/StarterPlayer/StarterPlayerScripts/StoryClient.client.lua` | Dialogue box, objective tracker, chapter cards |
| `default.project.json` | [Rojo](https://rojo.space) project: the only build path |
| `tools/build.sh` | Builds `build/AmyAndTheRainforest.rbxl` with Rojo |
| `tools/check.sh`, `tools/test.sh` | Static checks (StyLua, Selene, luau-lsp) and unit tests |
| `tests/lune/` | Unit tests, run under [Lune](https://lune-org.github.io/docs) |

## Editing the story

Open `src/ReplicatedStorage/StoryData.lua`. The engine understands three
quest types, so chapters are just data:

```lua
{ id = "ask_dad",     type = "talk",  npc = "Dad",       dialogue = { ... } }
{ id = "sneak_out_1", type = "reach", zone = "GardenGate" }
-- "collect" quests (touch N glowing pickups) are supported too
```

Change any `text = "..."` line to rewrite dialogue. Add or remove quests
and chapters freely. After editing, run `tools/test.sh` to check the
story data, then rebuild the place file with `tools/build.sh` (or let
`rojo serve` sync it into Studio).

## First-draft limitations (known, deliberate)

- No save system — the story restarts each play session (a DataStore
  could be added to remember progress).
- No sound or music yet (uploaded audio assets need a Roblox account to
  publish under).
- Characters are cute blocky figures built from parts, not
  rigged/animated avatars; Sam "catching" Amy is a friendly teleport
  back to the garden rather than a chase.
- Written as a solo experience; multiple players each get their own
  story progress, but the characters and the machine are shared in the
  world.

## Documents

| Document | What it is |
|---|---|
| [`docs/DEVELOPMENT_PLAN.md`](docs/DEVELOPMENT_PLAN.md) | The plan: architecture, channels, test harness, roadmap |
| [`docs/GLOSSARY.md`](docs/GLOSSARY.md) | The ubiquitous language and the enumerations the content schema is derived from |
| [`docs/story/canon.md`](docs/story/canon.md) | Clara's words in the game, byte for byte and locked, and the game Lines that are not canon |
| [`docs/story/style-guide.md`](docs/story/style-guide.md) | How to write new Lines in Clara's voice |
| [`docs/DEFINITION_OF_DONE.md`](docs/DEFINITION_OF_DONE.md) | The checklist every PR must satisfy |
| [`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md) | The owner's checklist for promoting Dev to Release |
| [`docs/design/feel.md`](docs/design/feel.md) | Camera Shots, device classes, readability, touch targets, onboarding and the visual rubric |
