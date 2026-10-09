# 006 — Checkpoint B, package B1: core and content (the refactor)

**Kind:** logic-provable. No Mac. Needs the Dev key only through CI.
**Starts after** the "village" respelling PR has merged, so the golden
file is final.

## Goal

The current game is re-housed into the plan's structure (section 2):
a pure core, thin engine adapters, and content as data plus hooks, with
behaviour proven unchanged by the golden walkthrough. No new gameplay.

## Must

1. **Layout** as plan section 2.2: `src/core`, `src/content`,
   `src/server`, `src/client`, `src/shared`, mapped in
   `default.project.json`. The committed `AmyAndTheRainforest.rbxlx` is
   already gone; keep `rojo build` the only build path. Update
   `CLAUDE.md`, `README.md` and `docs/OPEN_CLOUD.md` paths.
2. **Core: `StoryEngine`** (`src/core/StoryEngine.luau`), pure Luau,
   strict typed, no `game`, `Instance` or services:
   `StoryEngine.new(playerId, progress)`,
   `:step(playerEvent) -> progress, storyEvents, worldCommands`,
   `:snapshot()`, plus `resume(progress)` returning the World commands that
   re-establish the world (plan 2.4). Player events, Story events and World
   commands are the glossary's, as Luau types in `src/core/Events.luau`
   with payload schemas. Quest Kinds `talk`, `reach`, `collect` as one
   small module each under `src/core/quests/`.
3. **Content as data + hooks.** `src/content/chapters/<n>/data.luau` holds
   each Chapter's card, Quests, Objectives and Dialogue (Lines with
   `speaker`, `text`, and `canon = true` on Clara's Lines as listed in
   `docs/story/canon.md`). `src/content/chapters/<n>/hooks.luau` holds the
   Beats for that chapter's Hooks (`onStart`, `onComplete`) as lists of
   World commands: Sam's catch, Sam leaving for the farm, the paradise
   reveal, the machine arriving and stopping, each named `beat:<name>` in
   the glossary. `src/content/characters.luau` and
   `src/content/scenes/*.luau` hold Characters, Spots, Zones and Props
   with positions and colours as plain tables, converted in adapters.
   No raw `Vector3` or `Color3` in content.
4. **Server adapters** (`src/server/`): `StoryHost` feeds engine signals
   to `StoryEngine:step` as Player events and executes World commands
   through a `World` implementation (`WorldImpl`): `SceneBuilder` builds
   the world from scene data (today's `WorldBuilder`), `CharacterHost`
   builds and moves Characters, `PromptBridge` turns prompts into
   `TalkedTo`, zone entry into `EnteredZone`. Keep the fake-player send
   indirection and the handler exports the golden walkthrough relies on,
   adapted to the new modules.
5. **Client binder** (`src/client/`): today's client script becomes a
   binder that renders what it receives; the view-model extraction is
   package B2, so keep the client's behaviour identical here and change
   only what the new remotes require.
6. **Golden unchanged.** `tests/engine/walkthrough.luau` is updated to
   drive the new adapters (same event kinds, same fake player) and must
   pass against the **unchanged** `tests/fixtures/golden/walkthrough.json`.
   The wiring spec (`tests/lune/place/StoryServerWiring.spec.luau`) is
   replaced by equivalent checks on the new modules: the Script requires
   the host, one `FireClient` inside the default send, each event
   connection named, zone detection connected.
7. **Tier 1 for the core.** Specs under `tests/lune/core/`: every chapter
   completable from a fresh save and from a resume at every Quest; for
   every Quest the world state implied by walking there equals the state
   produced by `resume`; dialogue has no dead ends; Beats emit the expected
   World commands; the Net contract rejects malformed payloads. A per-core-
   module spec exists for every file under `src/core` (the coverage guard
   in package B3 will enforce this; meet it now).
8. **Canon test on content.** `tests/lune/content/Canon.spec.luau`: every
   Line marked `canon = true` matches `docs/story/canon.md` byte for byte,
   in story order, with no allowances; and every canon Line in the file is
   present in content. Keep `CanonGolden.spec.luau` too.
9. **Hooks exist.** A content spec asserts every hook name referenced in
   chapter data exists in that chapter's `hooks.luau`, and every Beat name
   is in the glossary's Beats list.
10. **Glossary.** Any term the code introduces that section 2.4 does not
    already name enters `docs/GLOSSARY.md` in the same PR. Ids read like
    the language (`chapter3.meet_fox`, `zone:ForestGap`, `beat:sam_catches`).

## Must not

- Change any Line's text, any Objective, any timing, or the order of any
  message (the golden file is the proof).
- Add gameplay, saves, UI, audio or camera work.
- Add dependencies beyond the current toolchain.

## Done when

- CI, tier 1 and engine-tests are green; the golden file is byte-identical
  to main; `tools/check.sh` passes with `src/core` and `src/content` under
  strict typing and no `--!nonstrict` anywhere in `src/`.
- The PR lists every module with one line on its role, the test counts
  before and after, and any place where the old code's behaviour was
  ambiguous and how it was preserved.

## Proof the coordinator checks

Golden file unchanged (`git diff main -- tests/fixtures/golden/`), no
`game`/`Instance`/`GetService` under `src/core` or `src/content`
(grep), canon spec present and passing, every `src/core` file has a spec,
engine-tests green on the PR.
