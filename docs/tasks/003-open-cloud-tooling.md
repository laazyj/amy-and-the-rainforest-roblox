# 003 — Open Cloud tooling (Checkpoint A, package A3)

**Kind:** logic-provable. Written and tested without secrets; proven
against Dev in brief 004 once secrets exist.

## Goal

The scripts that publish a place and run engine tests through Roblox
Open Cloud exist, are unit-tested against a mock of the API, and are
safe by construction: they cannot touch the Release experience unless
run by the release job, and engine tests cannot write to real DataStores.

## Context

- Place publishing: `POST https://apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions?versionType=Saved|Published`,
  header `x-api-key`, body is the `.rbxl` with content type
  `application/octet-stream`; response `{ "versionNumber": n }`.
- Luau Execution (beta): create a task with
  `POST /cloud/v2/universes/{u}/places/{p}/versions/{v}/luau-execution-session-tasks`
  (or without `/versions/{v}` for latest), body includes the script; then
  poll the returned operation path until done; read logs via the task's
  logs endpoint. Tasks run up to 5 minutes, 10 concurrent per place. Verify
  exact paths and payloads against
  https://create.roblox.com/docs/cloud/reference/features/luau-execution
  and the place-publishing usage guide, and record what you verified in
  the PR. If the docs are unreachable from your container, say so and
  implement from the shapes above with the endpoints isolated in one
  module so they are easy to correct.
- Brief 001 is building the Lune toolchain and `tests/lune/runner.luau`
  concurrently. If it has merged when you write tests, use its runner.
  If not, install Lune yourself (Rokit or a release binary) and write your
  tests as plain Lune scripts under `tests/lune/tools/` that exit non-zero
  on failure, and note in the PR that they should be ported to the runner.

## Must

1. **`tools/opencloud.luau`**: one module holding every endpoint path,
   header and payload shape, with an injectable HTTP function so tests
   can mock it. Nothing else in the repo constructs an Open Cloud URL.
2. **`tools/publish.lune`**: arguments `--universe`, `--place`,
   `--file`, `--version-type Saved|Published`, `--dry-run`. Reads the key
   from the environment variable named by `--key-env` (default
   `ROBLOX_DEV_API_KEY`). Prints the version number. **Refuses** to run
   if the universe equals `RELEASE_UNIVERSE_ID` from the environment
   unless `RELEASE_JOB=1` is also set, with a clear message. Retries
   transport errors once; never retries a 4xx.
3. **`tools/run-engine-tests.lune`**: arguments `--universe`, `--place`,
   `--version` (optional), `--script <path>` or `--dir <path>` of test
   scripts, `--timeout`. For each script: wrap it so that a `RUN_ID`
   global is injected (used for DataStore name prefixing), submit the
   task, poll, fetch logs, print them, and fail if the task errored or
   its output does not end with a line `ENGINE_TESTS_PASSED`. Same Release
   refusal as publish. Run up to 4 tasks concurrently.
4. **`tests/engine/_prelude.luau`**: the Luau helper that every engine
   test script will start with: a `describe` / `it` / `expect` that works
   inside Luau Execution, a `finish()` that prints `ENGINE_TESTS_PASSED`
   or the failure list, and a `storeName(base)` that returns
   `"test-" .. RUN_ID .. "-" .. base`. Also `tests/engine/smoke.luau`:
   asserts `game:GetService("Workspace")` exists and the place name, then
   `finish()`.
5. **Unit tests** against a mocked HTTP function: publish builds the right
   URL, headers and content type for Saved and Published; Release refusal
   fires with and without `RELEASE_JOB`; dry-run makes no request;
   run-engine-tests polls until done, treats missing
   `ENGINE_TESTS_PASSED` as failure, and injects `RUN_ID`.
6. **Workflows, committed but inert until secrets exist:**
   - `.github/workflows/publish-dev.yml`: on push to `main`, build
     (reuse the steps from `ci.yml` if merged, otherwise duplicate and
     note it), publish Published to Dev.
   - `.github/workflows/engine-tests.yml`: on `pull_request`, build,
     publish Saved to Dev, run `tests/engine/` against that version. Skip
     cleanly with a notice when `ROBLOX_DEV_API_KEY` is absent, so PRs
     from forks and the period before setup do not fail.
   - Both read `DEV_UNIVERSE_ID`, `DEV_PLACE_ID`, `RELEASE_UNIVERSE_ID`
     from repository variables and the key from secrets. No
     `pull_request_target`.
7. **`docs/OPEN_CLOUD.md`**: how the scripts are used locally and in CI,
   the exact permissions each key needs, and the safety rules.

## Must not

- Hard-code any id or key. Include any real universe or place id.
- Touch the Release universe in any code path other than the refusal.
- Add asset upload (later brief).

## Done when

- Unit tests pass locally; `--dry-run` of both scripts prints the request
  it would make.
- CI on the PR is green; the engine-tests workflow shows the "skipped,
  no key" notice rather than a failure.
- The PR description states which endpoint details were verified against
  the docs and which were not.

## Proof the coordinator checks

The coordinator will run the unit tests, run both scripts with
`--dry-run` and a fake Release universe id to see the refusal, and read
`opencloud.luau` to confirm it is the only place URLs are built.
