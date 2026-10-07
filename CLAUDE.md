# Amy and the Rain Forest

A gentle, single-player, story-driven Roblox game for ages 7–12, based on
Clara's story "Amy and the Rain Forest". Written in Luau, built with Rojo.
The plan that governs all work is `docs/DEVELOPMENT_PLAN.md`; task briefs
live in `docs/tasks/` (start with `docs/tasks/README.md`).

## Commands

Install the pinned toolchain once per clone (and after `rokit.toml` changes):

```sh
rokit install
```

| What | Command | Notes |
|---|---|---|
| Static checks (tier 0) | `tools/check.sh` | StyLua `--check`, Selene, luau-lsp strict types |
| Unit tests (tier 1) | `tools/test.sh [name filter]` | Lune runner, `tests/lune/**/*.spec.luau` |
| Build | `tools/build.sh` | Writes `build/AmyAndTheRainforest.rbxl` |
| Format | `stylua src tests` | Run before committing |

CI (`.github/workflows/ci.yml`) runs all three scripts on every PR and push
to `main` and uploads the place file as the `place` artifact. Run them
locally before pushing; a red CI costs a review cycle.

How to write tests and how to require `src/` modules under Lune is
documented at the top of `tests/lune/runner.luau`.

## Architecture rules (plan sections 2.1 and 2.4)

- **Pure core, thin adapters.** Logic that can be plain Luau data and
  functions lives in a core that never touches Roblox instances and is
  unit-tested under Lune. Only a thin adapter layer talks to the engine.
- `src/core/**` and `src/content/**` must not reference `game`, `Instance`
  or any service. Content stores positions and colours as plain tables
  (`{x, y, z}`, `{r, g, b}`), converted in the adapter.
- The server adapter drives the core through a small interface; client
  logic lives in a pure view-model and the client script is only a binder.
- A chapter is data plus hooks; Beats run at Hooks through the `World`
  interface. Single player is an invariant (Max Players = 1).
- **One ubiquitous language.** Use the nouns and verbs of plan section 2.4
  in code, tests, briefs and PR text. One name per concept, no synonyms
  (`Character`, not NPC; `Zone`, not trigger; `Beat`, not cutscene). Ids
  read like the language (`chapter3.meet_fox`, `zone:ForestGap`). A new
  term enters `docs/GLOSSARY.md` in the same PR.
- Canon Lines are Clara's exact words, spelling included, and are never
  changed.

The current `src/` is the proof of concept, before the Checkpoint B
restructure: its four files opt out of strict typing with a `--!nonstrict`
header. New code is strict (`.luaurc`).

## Rules

- **Only CI publishes.** Never publish to Roblox from Studio or from a
  local machine; agents never hold Open Cloud keys.
- **Run `/simplify` on your changes before each commit** and apply its fixes.
- Never commit secrets. Workflows use `pull_request`, never
  `pull_request_target`.
- Never merge a PR: the owner reviews and merges every PR.
