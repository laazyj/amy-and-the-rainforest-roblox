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

## How to play it (easiest way)

1. Install [Roblox Studio](https://create.roblox.com/) (free).
2. Download **`AmyAndTheRainforest.rbxlx`** from this repo.
3. In Roblox Studio: **File → Open from File…** and pick it.
4. Press **Play** (F5). The whole world is built by script when the
   game starts — no assets to install.

Controls: normal Roblox movement (WASD + Space). Walk up to characters
and press **E** to talk; click / **E** / **Space** to advance dialogue.

Everyone plays **as Amy herself** — a custom blocky character with the
red jumper, blue skirt and long brown hair from the drawing, in the
same style as the story's other characters. Profile avatars are not
loaded. (Delete `AmyStarterCharacter` from ServerScriptService to
restore normal avatars.)

## Project layout

| Path | What it is |
|---|---|
| `AmyAndTheRainforest.rbxlx` | Ready-to-open Roblox place file (generated) |
| `src/ReplicatedStorage/StoryData.lua` | **The story**: chapters, quests, dialogue, positions |
| `src/ServerScriptService/WorldBuilder.server.lua` | Builds the map: village, field, forest wall, paradise |
| `src/ServerScriptService/StoryServer.server.lua` | Quest engine: characters, prompts, zones, Sam, the machine |
| `src/ServerScriptService/AmyStarterCharacter.server.lua` | Everyone plays as blocky Amy herself (custom StarterCharacter) |
| `src/StarterPlayer/StarterPlayerScripts/StoryClient.client.lua` | Dialogue box, objective tracker, chapter cards |
| `tools/build_rbxlx.py` | Regenerates the `.rbxlx` from `src/` |
| `default.project.json` | [Rojo](https://rojo.space) project, if you prefer syncing |

## Editing the story

Open `src/ReplicatedStorage/StoryData.lua`. The engine understands three
quest types, so chapters are just data:

```lua
{ id = "ask_dad",     type = "talk",  npc = "Dad",       dialogue = { ... } }
{ id = "sneak_out_1", type = "reach", zone = "GardenGate" }
-- "collect" quests (touch N glowing pickups) are supported too
```

Change any `text = "..."` line to rewrite dialogue. Add or remove quests
and chapters freely. After editing, either paste the new module source
into the ModuleScript in Studio, or rebuild the place file:

```sh
python3 tools/build_rbxlx.py
```

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
