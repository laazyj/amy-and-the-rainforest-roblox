# 005 — Integrate the toolchain and the Open Cloud tooling (Checkpoint A)

**Kind:** logic-provable. No Roblox secrets, no Mac. **Starts after PRs #10
(brief 001) and #9 (brief 003) have both merged.**

## Goal

One command runs every unit test, CI runs them all, the secret-bearing
workflows share the pinned toolchain install, and the plan's wording
matches what was built.

## Must

1. **Port the Open Cloud unit tests to the Lune runner.** Rename
   `tests/lune/tools/*.test.luau` to `*.spec.luau` using `describe` /
   `it` / `expect` from `tests/lune/runner.luau`. Map the harness helpers:
   `H.eq` → `expect().toBe` or `toEqual`, `H.contains` → `toContain`,
   `H.fails` → a small `expectError(fn, needle)` helper added to the
   runner. Move the mock HTTP context into `tests/lune/fixtures/`. Delete
   `tests/lune/tools/_harness.luau` and `run.luau`. `tools/test.sh` then
   runs all tests (expect about 115 or more) and `ci.yml` runs them.
2. **Static checks cover `tools/`.** `tools/check.sh` runs StyLua, Selene
   and luau-lsp (standard platform) over `tools` as well as `src` and
   `tests`. Fix what they find.
3. **One shared toolchain install.** Extract the pinned Rokit install,
   job-token authentication, token removal and cache steps from `ci.yml`
   into a composite action `.github/actions/setup-tools`, and use it in
   `ci.yml`, `engine-tests.yml` and `publish-dev.yml`. No workflow may
   pipe a remote script to a shell.
4. **Build once, publish what was tested.** `engine-tests.yml` and
   `publish-dev.yml` call `tools/build.sh` (or download `ci.yml`'s `place`
   artifact for the same commit) instead of calling `rojo build`
   directly.
5. **Dev publish waits for CI.** `publish-dev.yml` triggers on
   `workflow_run` of CI with `conclusion == 'success'` on `main`, keeping
   `workflow_dispatch`. Document in `docs/OPEN_CLOUD.md` that the owner
   should also make the CI check required on `main` and enable "require
   branches to be up to date" in branch protection.
6. **Plan and docs wording.** In `docs/DEVELOPMENT_PLAN.md`: `.lune`
   becomes `.luau` for the tool scripts (sections 2.2 and 3), `RELEASE=1`
   becomes `RELEASE_JOB=1`, and section 4 states the DataStore guarantee
   as PR #9's docs now state it. Add the tool commands to `CLAUDE.md`'s
   command table.
7. **MemoryStore in the lint.** `checkDataStoreUse` flags DataStore call
   forms but not `GetQueue` / `GetSortedMap` / `GetHashMap`; the runtime
   proxy in the prelude already guards them. Extend the lint to the same
   three methods so a script that would be refused at run time is refused
   before submission, and add the unit tests.
8. **Dependency maintenance.** Add `.github/dependabot.yml` for the
   `github-actions` ecosystem (weekly, grouped into one PR, labelled
   `dependencies`) so every `uses:` line in the workflows and the
   composite action is kept current and CI proves each bump. Dependabot
   does not understand `rokit.toml` or `wally.toml`, so add
   `.github/workflows/toolchain-check.yml`: a weekly `schedule` job that
   compares each pin in `rokit.toml` (and any Wally dependency) with the
   latest release on GitHub and opens or updates a single PR titled
   "Toolchain updates" with the new pins, using `peter-evans/create-pull-request`
   or equivalent, so CI runs the full check, test and build against the
   new versions. Nothing auto-merges; the owner reviews. Document both in
   `docs/OPEN_CLOUD.md`'s neighbour `docs/MAINTENANCE.md` (new): what is
   automated, what Studio drift on the Mac still needs by hand, and the
   key-rotation dates.
9. **Brief 004 prerequisite.** Add to `docs/OPEN_CLOUD.md` that deleting
   `test-<RUN_ID>-*` keys after an engine run needs a DataStore permission
   on the Dev key, so the owner adds it before brief 004.

## Must not

- Change game behaviour or the story text.
- Change the request shapes in `tools/opencloud.luau`.

## Done when

- `tools/check.sh`, `tools/test.sh` and `tools/build.sh` pass locally and
  in CI, with every former `*.test.luau` test present as a spec.
- `actionlint` passes on all workflows.
- The PR lists the test count before and after the port.

## Proof the coordinator checks

The coordinator runs `tools/test.sh` and compares the test count to the
sum of PR #10's and PR #9's suites, and greps the workflows for `curl`
piped to `bash`.
