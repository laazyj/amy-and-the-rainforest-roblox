# 001 — Toolchain and CI (Checkpoint A, package A1)

**Kind:** logic-provable. No Roblox secrets, no Mac.

## Goal

The existing game builds from source with Rojo in CI, passes static
checks, and has a Lune unit-test runner with first real tests. Nothing
about the game's behaviour changes.

## Must

1. **Toolchain pinned with Rokit** in `rokit.toml`: rojo, lune, wally,
   stylua, selene, luau-lsp. Use current stable releases; record the
   versions in the PR. Add `wally.toml` with no dependencies yet.
2. **Build.** `tools/build.sh` runs `rojo build default.project.json -o
   build/AmyAndTheRainforest.rbxl`. `build/` is git-ignored. Keep
   `default.project.json` and the current `src/` layout as they are (the
   restructure is Checkpoint B).
3. **Retire the committed place file.** Delete `AmyAndTheRainforest.rbxlx`
   and `tools/build_rbxlx.py`. Update the README's "How to play it" to say
   the place file is downloaded from the latest CI run or release
   artifact, and keep the Rojo path.
4. **Static checks (tier 0).** `stylua.toml`, `selene.toml` with the
   Roblox standard library, `.luaurc` in strict mode. Format the existing
   code with StyLua in its own commit. Fix Selene and luau-lsp findings in
   the existing code only where they are real errors; suppress nothing
   silently. `tools/check.sh` runs all three.
5. **Lune test runner (tier 1).** `tests/lune/runner.luau` is a small
   `describe` / `it` / `expect` runner (about 150 lines, no dependencies)
   that discovers `tests/lune/**/*.spec.luau`, prints results, and exits
   non-zero on failure. `tools/test.sh` runs it. Document how to require
   modules from `src/` under Lune in a comment at the top of the runner.
6. **First tests.** Under `tests/lune/`, add real tests against
   `src/ReplicatedStorage/StoryData.lua` as it is today: every chapter has
   a unique id and at least one quest; every quest has a unique id, a
   known type (`talk`, `reach`, `collect`), an objective, and the fields
   its type needs; every `talk` quest names an NPC that exists; every
   `reach` quest names a zone (collect the set of zone names and assert
   each is used by at least one quest); every dialogue line has a speaker
   and text. If `StoryData` uses `Vector3` or `Color3` globals, provide
   them from `@lune/roblox` in the test bootstrap and say so in the PR.
7. **CI.** `.github/workflows/ci.yml` on `pull_request` and push to
   `main`: install Rokit and the pinned tools, run `tools/check.sh`,
   `tools/test.sh`, `tools/build.sh`, and upload the built `.rbxl` as an
   artifact named `place`. Cache tool downloads. Use `pull_request`, never
   `pull_request_target`.
8. **`CLAUDE.md`** at the repo root: what the project is, the exact
   commands for check, test and build, the architecture rules from the
   plan (sections 2.1 and 2.4 in brief), the rule that only CI publishes,
   the rule to run `/simplify` before each commit, and a pointer to
   `docs/tasks/README.md`.

## Must not

- Change game behaviour or the story text.
- Add dependencies beyond the toolchain.
- Add Open Cloud publishing (that is brief 003).

## Done when

- CI is green on the PR with all three steps and the artifact present.
- `tools/check.sh`, `tools/test.sh` and `tools/build.sh` each run clean
  from a fresh clone after `rokit install`.
- The PR description lists tool versions, the commands run, and their
  output summary.

## Proof the coordinator checks

The coordinator will clone the branch, run `rokit install`, then the
three scripts, and read the CI run. It will open the test file and expect
to see the StoryData invariants above, not placeholder tests.
