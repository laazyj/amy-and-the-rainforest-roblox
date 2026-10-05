# Amy and the Rain Forest — Development Plan

**Status:** proposal for review · **Owner:** Jason Duffett · **Last updated:** 2026-10-05

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

Decisions already agreed (see "Decisions" at the end for the full list):
personal Roblox account, two separate experiences for Dev and Release, Open
Cloud API key stored as a GitHub secret, ages 7–12 and family-friendly,
strictly free, PC + mobile, single player first with co-op possible later,
exploration + animal companions + light puzzles, new chapters + collectibles
as the retention loop, agent drafts story in Clara's voice for approval with
her original text untouched, free Creator Store assets and Clara's
illustrations, review by playing Dev plus reading the PR, one chapter or
feature set per PR, on-demand agent runs plus a nightly Dev build, and a
MacBook self-hosted runner that may not always be on.

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
| Tests | None |
| CI / publishing | None; publish is a manual Studio step |
| Roblox presence | Not published |

The engine works and the story is intact. Everything else is missing, and
the current shape (one 1,100-line server script with world, quests and NPC
behaviour interleaved) is why each new feature is expensive. The plan is
not to rewrite the game from scratch, but to **re-house the working logic
into a modular, testable structure first**, then grow it.

---

## 2. Target architecture

### 2.1 Principle: a pure core with thin engine adapters

Everything that can be expressed as plain Luau data and functions lives in
a core that never touches Roblox instances. That core is fully testable on
Linux in milliseconds using Lune. Only a thin adapter layer talks to the
Roblox engine, and that layer is tested in the real engine through Open
Cloud and in Studio on the Mac.

```
┌───────────────────────────────────────────────────────────────┐
│ Content (data only)                                           │
│  chapters/*.luau · scenes/*.luau · dialogue · assets manifest │
├───────────────────────────────────────────────────────────────┤
│ Core (pure Luau, no Instances)                                │
│  StoryEngine (quest state machine) · DialogueRunner           │
│  SaveSchema + migrations · CompanionLogic · PuzzleLogic       │
├───────────────────────────────────────────────────────────────┤
│ Engine adapters (Roblox APIs)                                 │
│  Server: SceneBuilder, NpcController, PromptBridge, Persist   │
│  Client: UI (dialogue, objectives, chapter cards), Input,     │
│          Audio, Camera, Effects                               │
├───────────────────────────────────────────────────────────────┤
│ Shared: Net (typed remotes), Config, AssetIds (generated)     │
└───────────────────────────────────────────────────────────────┘
```

Rules that keep this honest, and that the tests enforce:

- `src/core/**` must not call `game`, `Instance.new`, or any service. A
  lint rule and a Lune smoke test fail the build if it does.
- The server adapter drives the core through a small interface
  (`StoryEngine.new(playerId, saveData)`, `:handle(event)`, `:snapshot()`),
  so a test can replace the player with a plain table.
- Content is data. Adding a chapter means adding a data file and a scene
  file; no engine code change should be needed for a typical chapter.

### 2.2 Repository layout after Phase 0

```
.
├── default.project.json      Rojo project (the only build path)
├── rokit.toml                Toolchain pins: rojo, lune, wally, stylua, selene, luau-lsp
├── wally.toml                Packages: jest-lua, promise, signal, profile store, fusion/react
├── selene.toml / stylua.toml Lint and format config
├── .luaurc                   Strict type mode
├── CLAUDE.md                 Agent conventions, commands, definition of done
├── src/
│   ├── core/                 Pure Luau (StoryEngine, Dialogue, Save, Companions, Puzzles)
│   ├── content/              Chapters, scenes, dialogue, collectibles (data only)
│   ├── server/               ServerScriptService adapters
│   ├── client/               StarterPlayerScripts adapters and UI
│   └── shared/               Net, Config, generated AssetIds
├── tests/
│   ├── unit/                 Lune: core + content invariants
│   ├── engine/               Luau Execution API: build world, drive story in-engine
│   └── studio/               Mac only: scripted playthrough, screenshots, perf
├── assets/
│   ├── manifest.json         Local file → Roblox asset id, kind, licence
│   └── images|audio|meshes/  Sources (Clara's illustrations, SFX, music)
├── tools/
│   ├── build.sh              rojo build → build/AmyAndTheRainforest.rbxl
│   ├── publish.lune          Open Cloud place publish (Saved or Published)
│   ├── run-engine-tests.lune Open Cloud Luau Execution runner
│   ├── upload-assets.lune    Open Cloud Assets API uploader, updates manifest + AssetIds
│   └── studio-playtest/      Mac runner scripts
├── docs/
│   ├── DEVELOPMENT_PLAN.md   This document
│   ├── DEFINITION_OF_DONE.md What every PR must satisfy
│   ├── RELEASE_CHECKLIST.md  Human promotion checklist, Dev → Release
│   ├── story/
│   │   ├── canon.md          Clara's original text, locked
│   │   ├── style-guide.md    Voice, spelling rules, what is off limits
│   │   └── proposals/        New chapters awaiting approval
│   └── tasks/                High-level task briefs for the agent
└── .github/workflows/        ci.yml, publish-dev.yml, release.yml, nightly.yml, studio.yml
```

The committed `AmyAndTheRainforest.rbxlx` and `tools/build_rbxlx.py` are
retired: CI builds the place file from source and attaches it to every PR as
a downloadable artifact, so the "open from file" path in the README keeps
working without a stale binary in git.

### 2.3 Gameplay architecture additions

| System | Approach |
|---|---|
| Saves | DataStore via a battle-tested wrapper (ProfileStore). Schema in `core/Save`, versioned with migrations and a unit test per migration. Dev and Release are separate experiences, so Dev saves can be wiped freely. |
| Input | Roblox `ContextActionService` with touch buttons on mobile; proximity prompts stay as the universal "talk" affordance. UI scales via `UIScale` + safe-area insets. |
| UI | One declarative UI library (Fusion or React-Lua, chosen in Phase 0 by a short spike). Dialogue, objectives, chapter cards, journal, settings, pause. |
| Audio | `AudioManager` with named cues from the asset manifest; music per scene with crossfades; SFX for prompts, pickups, footsteps. |
| World | Scenes defined as data (terrain painting instructions, placed models, zones, spawn points) and built by `SceneBuilder`. Hand-made meshes and terrain can be imported into a scene as `.rbxm` models checked into `assets/meshes` and referenced by the scene. |
| Characters | Rigged R15-compatible characters with animations (walk, idle, talk, Sam's "drag back"). Amy's look derived from Clara's illustration. |
| Companions | Animals as followers with simple state machines (idle, follow, react, lead to point of interest), logic in core, movement in adapter. |
| Collectibles | Data-driven (`content/collectibles`), journal UI, counts persisted, feed small rewards (cosmetic, never paid). |
| Puzzles | Small declarative puzzle types (order of actions, find and place, follow the animal) in core with engine triggers in adapters. |
| Analytics | Roblox Analytics custom events: chapter start/complete, quest complete, collectible found, session length. Used to judge "compelling". |

---

## 3. Channels: Dev and Release

Two separate experiences on your Roblox account, each with its own
universe ID, place ID, DataStores and analytics:

| Channel | Visibility | Who plays | What lands here |
|---|---|---|---|
| **Dev** | Private (friends only) | You, Clara, invited testers | Every merge to `main`, published automatically |
| **Release** | Public | Everyone | Only builds you promote, via a GitHub release with a manual approval gate |

Flow of a change:

```
PR opened/updated ──► CI: lint, types, unit tests, build
                  ──► publish build to Dev as a *Saved* version (not visible to players)
                  ──► engine tests via Luau Execution against that exact version
                  ──► (Mac awake?) Studio playthrough + screenshots attached to PR
Merge to main     ──► publish to Dev as *Published*  → you play it
Promote           ──► tag vX.Y.Z → GitHub "release" environment requires your approval
                  ──► publish same built file to Release as *Published*
                  ──► GitHub Release created with changelog and the .rbxl
Rollback          ──► re-run release workflow with a previous tag, or revert in Roblox version history
```

Using a *Saved* version for PRs matters: it gives the engine tests a real,
immutable place version to run against while players on Dev keep playing
the last merged build.

Secrets and config (GitHub repository secrets and variables):

| Name | Purpose |
|---|---|
| `ROBLOX_API_KEY` | Open Cloud key scoped to both experiences: `universe-places:write`, Luau Execution, Assets read/write |
| `DEV_UNIVERSE_ID`, `DEV_PLACE_ID` | Dev experience |
| `RELEASE_UNIVERSE_ID`, `RELEASE_PLACE_ID` | Release experience |

The key is created at create.roblox.com/credentials with IP restriction set
to allow all, because GitHub-hosted runners have no fixed IP. Audio upload
limits are 10 per month without Roblox ID verification and 100 with it, so
ID-verifying the account before Phase 1 is recommended.

---

## 4. The test harness

Four automated tiers plus one human tier. Tiers 0–2 run on every PR on
Linux with no Studio. Tier 3 runs when the Mac is awake. Tier 4 is you.

| Tier | Runs where | Runs when | Proves | Time |
|---|---|---|---|---|
| 0 Static | GitHub runner | Every push | StyLua formatting, Selene lint, luau-lsp strict types with Roblox API definitions, core-purity rule, content schema validation | < 1 min |
| 1 Unit | GitHub runner, Lune | Every push | Core logic: every chapter is completable from a fresh save and from every saved checkpoint; dialogue graphs have no dead ends; save migrations round-trip; canon text unchanged; collectible and puzzle logic | < 1 min |
| 2 Engine | Roblox servers via Open Cloud Luau Execution | Every PR, after build | The place loads; `SceneBuilder` produces the expected zones, NPCs, prompts and spawn points; the server story adapter drives a simulated player through all chapters using the same functions remotes call; no errors in the output log; instance and part counts within budget | 2–5 min |
| 3 Studio | Mac self-hosted runner | Opportunistic, label `needs-playtest`, and before release | A real client playthrough: scripted character walks each chapter, triggers prompts, dialogue advances; screenshots at chapter cards and key scenes; frame time and memory stats; mobile emulation screenshots | 5–10 min |
| 4 Human | You and Clara on Dev | Before promotion | It feels right: pacing, readability, fun; the `RELEASE_CHECKLIST.md` | as needed |

Design notes:

- **One test library for tiers 1 and 2.** Jest-Lua (the jsdotlua port) runs
  under both Lune and the Roblox engine, so core tests are written once and
  the engine suite reuses the same assertions. If Jest-Lua under Lune proves
  fragile, TestEZ is the fallback; the decision is made in the Phase 0 spike.
- **Engine tests cannot create real players.** The Luau Execution environment
  has no client and `Players` will not spawn anyone. The server adapters are
  therefore written to accept a "player-like" object (UserId, Character,
  position setter), and tier 2 drives them with a fake. Real client behaviour
  is tier 3's job.
- **Tier 3 is never on the critical path.** The Studio job uses
  `continue-on-error`, a short queue timeout, and reports "skipped: runner
  offline" rather than failing. The release workflow shows whether a
  playtest ran on the candidate build; promoting without one is allowed but
  visible.
- **Screenshots become review material.** Tier 3 uploads a contact sheet to
  the PR, so most visual review can happen from the PR without opening
  Studio.
- **Budgets are tests.** Part counts, texture memory, server frame time and
  client frame time have numeric budgets checked by tiers 2 and 3, so quality
  work can't silently degrade performance on mobile.
- **Flake policy.** Open Cloud is beta. Tier 2 retries once on transport
  errors only, never on assertion failures. Persistent Open Cloud outages
  are reported in the PR rather than hidden.

### Mac runner specifics

- A GitHub Actions self-hosted runner on the MacBook, labelled `studio`,
  with Roblox Studio installed and logged in.
- Studio is driven by a small automation layer: a Studio plugin that listens
  on localhost, plus `run-in-roblox` for script execution and macOS
  `screencapture` for images. Several open-source Roblox Studio automation
  bridges exist; Phase 0 picks one and wraps it so the rest of the harness
  never depends on which.
- Power settings: prevent sleep while on power; when the Mac is closed or
  off, jobs queue up to 30 minutes then skip.

---

## 5. Agent workflow: from high-level task to proven PR

The goal is that you write a brief and, without further guidance, receive a
PR that is green across all tiers, plays correctly on Dev, and is documented
well enough to review in minutes.

### 5.1 Task briefs

A task lives in `docs/tasks/NNN-short-name.md`:

```
# 012 — Chapter 5: The Night the Fireflies Came
Goal: a new chapter, 10–15 minutes of play, that follows Clara's story
proposal in docs/story/proposals/chapter-5.md (approved 2026-11-02).
Must: new scene (night-time paradise), 2 new collectibles, 1 puzzle,
      Sam companion behaviour, music and SFX, mobile-tested.
Must not: change any canon text; add paid items; exceed perf budgets.
Done when: DEFINITION_OF_DONE.md is satisfied and the chapter is
           completable in tier 2 and tier 3 from a Chapter 4 save.
```

### 5.2 What the agent does with it

1. Reads `CLAUDE.md`, the brief, the definition of done, and the story
   style guide.
2. Writes a short design note into the PR description first: scenes,
   quests, systems touched, assets needed.
3. Works on a branch, in small commits, running tiers 0–1 locally after each
   change and tier 2 via CI on each push.
4. Generates or sources assets within the agreed rules (free Creator Store,
   Clara's illustrations, synthesised or free-licence audio), uploads them
   with `upload-assets.lune`, and records licences in the manifest.
5. Iterates until every tier is green, then requests a tier 3 playtest by
   label. If the Mac is off, it says so in the PR and continues.
6. Produces the PR with: changelog, test report, screenshots or a note that
   none were possible, a "how to play-test this" section with the Dev link
   and a save-state shortcut, and any open questions as a short list at the
   end rather than as blockers.
7. Watches the PR: fixes CI, answers review comments, pushes follow-ups.

### 5.3 What makes this reliable

- `CLAUDE.md` holds the conventions, the exact commands for each tier, the
  architecture rules, and the definition of done, so every session starts
  with the same context.
- Repeated workflows become skills in `.claude/skills/`: `new-chapter`,
  `playtest`, `publish-dev`, `upload-assets`, `perf-report`.
- Content schemas are validated in tier 0, so a malformed chapter is caught
  before any engine time is spent.
- Debug shortcuts in Dev builds: a `/chapter N` command and a "jump to
  quest" menu let you and the tests reach any point of the story in seconds.
  Compiled out of Release builds.
- A nightly routine builds `main`, runs all tiers, publishes Dev, and posts
  a one-paragraph summary. If anything regresses with no PR to blame, it
  opens an issue.
- Large tasks are split by the agent into stacked PRs only when a single PR
  would exceed roughly 2,000 changed lines; otherwise one PR per brief.

---

## 6. Phased roadmap

Estimates assume agent-driven work with your review in between. Each phase
ends in a Dev build you can play, and from Phase 1 on, a Release.

### Phase 0 — Foundation (target: 2 weeks)

Outcome: the same four chapters, now built, tested and published by the
pipeline. No new gameplay.

- Toolchain: Rokit, Rojo, Wally, Lune, StyLua, Selene, luau-lsp; `CLAUDE.md`.
- Refactor into core / adapters / content with behaviour unchanged;
  chapters 1–4 as data files; canon text locked by test.
- Tier 0 and tier 1 green in CI with meaningful coverage of `StoryEngine`.
- You create the Dev and Release experiences and the API key; CI publishes
  Dev on merge and Saved versions on PRs.
- Tier 2 runner and the first engine tests (world builds, full story
  walkthrough with a fake player).
- Mac runner set up with one end-to-end smoke playthrough and screenshots.
- `DEFINITION_OF_DONE.md`, `RELEASE_CHECKLIST.md`, first skills.
- Spikes with written decisions: UI library, Jest-Lua under Lune, Studio
  automation bridge.

### Phase 1 — Public release candidate (target: 3–4 weeks)

Outcome: version 1.0 on the Release channel.

- Save system with chapter checkpoints and a "continue" title screen.
- Mobile and tablet support: touch controls, scaled UI, safe areas, tested
  in Studio device emulation on the Mac.
- Audio: ambient forest, village, paradise; music per chapter; SFX.
- Visual pass on the existing world: terrain and foliage, lighting and
  atmosphere, Clara's palette; chapter cards using her illustrations.
- Rigged Amy, Dad, Mum, villagers, Sam and the three animals with basic
  animations; Sam's catch becomes a short chase.
- Settings (volume, text size), pause, accessibility basics (large readable
  dialogue, no timed reading).
- Roblox store page: icon, thumbnails, description, age questionnaire
  completed, experience set to public.
- Analytics events wired; a dashboard note in `docs/` on what to watch.

### Phase 2 — Make it compelling (target: 6–8 weeks, several PRs)

Outcome: players return because there is more to discover.

- Hub: Amy's house and garden become a persistent home base with the
  journal, a map, and the animals visiting once befriended.
- Companions: squirrel, fox and lion each with a befriending arc and a
  helper ability (the squirrel finds hidden things, the fox leads the way at
  night, the lion clears a path).
- Collectibles across all scenes with journal entries written in Clara's
  voice; cosmetic rewards for Amy's outfit and the garden.
- Light puzzles per scene; no failure states, hints after a delay.
- Replayability: chapter select, time-of-day variations, a few optional side
  quests from villagers.
- Second visual pass driven by tier 3 screenshots and player feedback.
- Optional drop-in co-op spike: a friend joins as a second explorer. Only
  shipped if it doesn't compromise the single-player story.

### Phase 3 — Continual expansion (ongoing)

- Chapter pipeline: proposal → approval → brief → PR → Dev → Release, with
  one new chapter roughly every 4–6 weeks.
- Seasonal moments (rainy season, fireflies, a village fair) as content
  packs toggled by date.
- Monthly quality PR driven by analytics: where players drop off, what is
  slow on mobile, what is confusing.
- Regular dependency and platform upkeep (Roblox engine changes, Open Cloud
  API updates).

---

## 7. Story pipeline and content rules

- `docs/story/canon.md` holds Clara's original text. A tier 1 test asserts
  every canon line in the game matches it byte for byte, including her
  spelling.
- New story is proposed in `docs/story/proposals/` as a short treatment
  (one page: premise, beats, new characters, moral), drafted by the agent in
  her voice using `style-guide.md`. You and Clara approve, edit, or reject
  in the PR. Nothing enters a chapter brief until approved.
- Off limits unless Clara says otherwise: changing the ending, altering
  existing characters' personalities, any content outside a family-friendly
  rating, in-game purchases.
- Dialogue reading level: short lines, large text, no timers.

---

## 8. Quality bar and how we measure it

| Dimension | Bar | Measured by |
|---|---|---|
| Correctness | Every chapter completable from every checkpoint, on PC and mobile | Tiers 1–3 |
| Performance | 60 fps on a mid-range phone target, server frame < 8 ms, memory under budget | Tiers 2–3 budgets |
| Visual | Consistent with Clara's palette and illustration style; every scene has a screenshot in `docs/screens/` that is updated when it changes | Tier 3 + review |
| Audio | Every interaction has feedback; every scene has ambience and music | Content manifest test |
| Story | Canon untouched, new text approved, no dead ends | Tier 1 + proposals |
| Retention | Chapter completion funnel, median session length, day-7 return rate | Roblox Analytics, reviewed monthly |

---

## 9. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Open Cloud Luau Execution is beta and may change or have outages | Tier 2 is isolated behind one runner script; failures are reported, not hidden; tier 3 and Lune cover most of the same logic |
| Mac runner is often off | Tier 3 is optional on PRs, visible on releases; nothing blocks on it |
| Uploaded assets rejected by moderation | Upload early in a task; manifest records status; fall back to procedural art |
| Audio upload cap (10/month unverified) | ID-verify the account; batch audio uploads per phase |
| Refactor breaks the existing story | Phase 0 keeps behaviour identical, proven by the story walkthrough test before any new feature |
| Agent scope creep inside a task | Brief has "must not"; definition of done; PR size guideline |
| Roblox policy changes for public experiences | Release checklist includes a policy review line; experience questionnaire kept current |
| DataStore schema drift | Versioned saves with migration tests; Dev saves can be wiped |

---

## 10. What you need to do (one-time setup)

1. Create two experiences on your Roblox account: "Amy and the Rain Forest
   (Dev)" set to Friends, and "Amy and the Rain Forest" set to Private until
   1.0. Note both universe and place IDs.
2. Create an Open Cloud API key at create.roblox.com/credentials with
   Place Publishing (write), Luau Execution, and Assets (read, write) for
   both experiences; IP restriction "allow all".
3. Add the secrets and variables from section 3 to the GitHub repository.
4. Create a GitHub environment named `release` with yourself as required
   reviewer.
5. Optionally ID-verify the Roblox account (audio upload limit).
6. Share Clara's illustrations as image files (the hero image and any
   others) into `assets/images/` or a shared folder.
7. When convenient, install Roblox Studio and the self-hosted runner on the
   MacBook; the agent will provide a setup script and checklist in Phase 0.

Everything else in Phase 0 is agent work and starts as soon as item 3 is
done; items 1–2 can be done in parallel with the refactor.

---

## 11. Decisions log

| Decision | Choice |
|---|---|
| Roblox ownership | Personal account (a group can be adopted later; IDs are config) |
| Channels | Two separate experiences, Dev (friends) and Release (public) |
| Automation auth | One Open Cloud API key as a GitHub secret |
| Audience | Ages 7–12, family-friendly, no chat required |
| Monetization | None |
| Platforms | PC and mobile/tablet; console not targeted |
| Multiplayer | Single player; drop-in co-op evaluated in Phase 2 |
| Gameplay direction | Exploration, animal companions, light puzzles; hub world; saves |
| Retention | New chapters and collectibles |
| Story authorship | Agent drafts proposals in Clara's voice; Clara and Jason approve; canon locked |
| Assets | Free Creator Store, Clara's illustrations, free-licence or synthesised audio; uploads via Open Cloud |
| Review | Play Dev + read PR; release checklist gates promotion |
| Task size | One chapter or feature set per PR |
| Cadence | On demand plus nightly Dev build |
| Test machines | Linux CI for tiers 0–2; MacBook self-hosted runner for tier 3, opportunistic |
