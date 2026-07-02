# Amy and the Rainforest — a solo Roblox story game

A gentle, single-player, story-driven Roblox adventure. You play as Amy,
who arrives in a rainforest where the rain has stopped. Guided by Milo
the Monkey, Grandma Sloth, and Tiki the Toucan, Amy gathers the lost
petals of the Rain Flower, repairs the river bridge, climbs the Great
Kapok Tree, and brings the rain back.

**Five chapters, ~10–15 minutes of play:**

1. **The Edge of the Rainforest** — meet Milo, follow the path to the village
2. **The Village With No Rain** — Grandma Sloth explains the Great Dry; find 3 glowing petals
3. **The Broken Bridge** — help Tiki by gathering 3 planks, then cross the river
4. **The Great Kapok Tree** — climb the spiral of branch platforms
5. **The Rain Flower** — return the petals and watch the rain come back

## ⚠️ A note about the story

This draft was written to match the game's title. The original story at
`clara.jasonduffett.net` **could not be reached from the build
environment** (the host is blocked by the sandbox's network policy), so
the chapters, characters, and dialogue here are a placeholder narrative
in the same spirit. **Every word of story text lives in one file** —
[`src/ReplicatedStorage/StoryData.lua`](src/ReplicatedStorage/StoryData.lua)
— so the real story can be dropped in by editing dialogue lines, chapter
titles, and character names there, without touching the game engine.

## How to play it (easiest way)

1. Install [Roblox Studio](https://create.roblox.com/) (free).
2. Download **`AmyAndTheRainforest.rbxlx`** from this repo.
3. In Roblox Studio: **File → Open from File…** and pick it.
4. Press **Play** (F5). The whole rainforest is built by script when the
   game starts — no assets to install.

Controls: normal Roblox movement (WASD + Space). Walk up to characters
and press **E** to talk; click / **E** / **Space** to advance dialogue.

## Project layout

| Path | What it is |
|---|---|
| `AmyAndTheRainforest.rbxlx` | Ready-to-open Roblox place file (generated) |
| `src/ReplicatedStorage/StoryData.lua` | **The story**: chapters, quests, dialogue, positions |
| `src/ServerScriptService/WorldBuilder.server.lua` | Builds the map: village, river, bridge, Great Kapok Tree |
| `src/ServerScriptService/StoryServer.server.lua` | Quest engine: NPCs, prompts, pickups, zones, ending |
| `src/StarterPlayer/StarterPlayerScripts/StoryClient.client.lua` | Dialogue box, objective tracker, chapter cards |
| `tools/build_rbxlx.py` | Regenerates the `.rbxlx` from `src/` |
| `default.project.json` | [Rojo](https://rojo.space) project, if you prefer syncing |

## Editing the story

Open `src/ReplicatedStorage/StoryData.lua`. The engine understands three
quest types, so chapters are just data:

```lua
{ id = "meet_milo",  type = "talk",    npc = "Milo",  dialogue = { ... } }
{ id = "find_petals", type = "collect", item = "Rain Flower Petal", count = 3, spawnPoints = { ... } }
{ id = "cross_river", type = "reach",   zone = "FarBank" }
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
- NPCs are cute blocky animals built from parts, not rigged/animated
  characters.
- Written as a solo experience; multiple players each get their own
  story progress, but NPCs are shared in the world.
