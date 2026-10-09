# Open Cloud tooling

How this repository publishes places and runs engine tests (tier 2) through
Roblox Open Cloud, which keys it needs, and the safety rules built into it.
Plan background: `docs/DEVELOPMENT_PLAN.md` sections 3 and 4.

**Only CI publishes.** The agent never holds a key. The commands below with
a real key are for the owner, when debugging a CI failure. Everyone else uses
`--dry-run`.

## The pieces

| File | What it does |
|---|---|
| `tools/opencloud.luau` | Builds every Open Cloud request and parses every response. HTTP is injected, so tests mock it. Retry policy: a transport error is retried once, except for Create Asset (safety rule 7); a 5xx is retried once for GET only, never for a POST (publish, create task) that may already have been accepted; Roblox's "server busy" 409 is retried with backoff (safety rule 8); any other 4xx is never retried. |
| `tools/publish.luau` | Publishes a `.rbxl` as a `Saved` or `Published` version and prints the version number on stdout. |
| `tools/upload-assets.luau` | Uploads the pending assets in `assets/manifest.json` through the Assets API and writes their ids back. See [`ASSETS.md`](ASSETS.md). |
| `tools/run-engine-tests.luau` | Runs engine test scripts as Luau Execution tasks, up to 4 at once, and fails unless every one passes. |
| `tools/lib/` | Shared argument parsing and the Release guard (`cli.luau`), and the logic behind the tools. |
| `tests/engine/_prelude.luau` | `describe` / `it` / `expect`, `storeName`, `finish` for engine test scripts. |
| `tests/engine/*.luau` | Engine tests. Files starting with `_` are helpers and are not run. |
| `tests/fixtures/` | Files engine tests read through `fixture()`, such as the golden file of the walkthrough. |
| `tests/lune/tools/` | Unit tests for all of the above, against a mocked HTTP function. |
| `.github/workflows/publish-dev.yml` | After CI succeeds on a push to `main` (or a manual run from `main`): build the commit CI tested, publish it to Dev as `Published`. |
| `.github/workflows/upload-assets.yml` | By hand from `main`: upload pending assets with the Dev key and open the "Asset ids" PR. |
| `.github/workflows/engine-tests.yml` | Every PR: build, publish to Dev as `Saved`, run `tests/engine/` against that exact version. |

## Running locally

Run from the repository root, with the toolchain installed (`tools/bootstrap-agent.sh`).

```sh
# Unit tests (no network); they run with every other tier 1 spec
tools/test.sh

# Show the request a publish would make, without sending anything
lune run tools/publish --universe 1234 --place 5678 \
  --file build/AmyAndTheRainforest.rbxl --version-type Saved --dry-run

# Show the task an engine-test run would create, without sending anything
lune run tools/run-engine-tests --universe 1234 --place 5678 --version 12 \
  --dir tests/engine --dry-run
```

A dry run needs no key and prints the method, URL, headers (with the key
redacted) and body size.

### `tools/publish`

| Option | Meaning |
|---|---|
| `--universe <id>` `--place <id>` | Target place. |
| `--file <path>` | The binary `.rbxl` to publish. Open Cloud rejects files over 10 MiB. |
| `--version-type Saved\|Published` | `Saved` stores a version players do not see. `Published` makes it live. |
| `--key-env NAME` | Environment variable holding the API key. The default is `ROBLOX_DEV_API_KEY`. |
| `--dry-run` | Print the request and send nothing. |

The tool prints only the version number on stdout. Messages go to stderr, so
`version=$(lune run tools/publish ...)` works.

### `tools/run-engine-tests`

| Option | Meaning |
|---|---|
| `--universe <id>` `--place <id>` | Target place. |
| `--version <n>` | Place version to run against. If omitted, the version is left out of the URL and the server picks it. CI always passes the version it just saved. |
| `--script <path>` or `--dir <path>` | One script, or every `*.luau` in a directory except those starting with `_`. |
| `--timeout <seconds>` | Per-task script timeout, from 1 to 300. The default is 300. |
| `--run-id <id>` | Up to 32 letters, digits or hyphens. Defaults to `<GITHUB_RUN_ID>-<GITHUB_RUN_ATTEMPT>` when `GITHUB_RUN_ID` is set, otherwise `local-<time>-<random>`. The engine-tests workflow passes `pr<N>-<run>-<attempt>` explicitly. |
| `--prelude <path>` | The default is `tests/engine/_prelude.luau`. |
| `--key-env NAME`, `--dry-run` | As for publish. |

For each script the tool:

1. Builds one task script: `RUN_ID = "<id>"`, `PASS_MARKER = "ENGINE_TESTS_PASSED"`,
   then the prelude, then the test.
2. Creates the task, polls it every 3 seconds until it is `COMPLETE`,
   `FAILED` or `CANCELLED`, and reads every page of its logs.
3. Prints `--- <script>`, the logs, then `PASS <script>` or
   `FAIL <script>: <reason>`. The run ends with `N passed, M failed`.

A script passes only if its task is `COMPLETE` **and** the last non-blank
line it printed is exactly `ENGINE_TESTS_PASSED`. When a test fails,
`finish()` both prints the failures and raises, so the task fails as well.

Luau Execution limits: create allows 5 per minute per key owner, and a place
may have at most 10 incomplete tasks. Both answer HTTP 429. Each script gets
`timeout + 300` seconds of waiting in total, polls and 429s included. A 429
waits for `Retry-After`, or 15 seconds if that header is absent.
The whole run also has a wall-clock deadline: `timeout + 300` seconds, plus
the longest "server busy" wait (`OpenCloud.BUSY_WAIT_TOTAL`, safety rule 8), for each wave of
4 scripts, plus a minute. That catches a request that never
returns, because Lune's HTTP client has no timeout of its own. A script whose
worker raises counts as failed; it cannot stall the run.

## Writing an engine test

```lua
-- tests/engine/example.luau
describe("SceneBuilder", function()
	it("builds the garden gate zone", function()
		expect(workspace:FindFirstChild("Zones")).toBeTruthy()
	end)
end)

finish()
```

- Per the API spec, physics does not run in a task, and server and client
  scripts do not start on their own. The DataModel is a fresh copy of the
  place version, and changes are not saved. So `Touched` never fires, and
  game code a test needs must be a ModuleScript it can `require` (the
  StoryServer Script only requires and starts the `StoryHost` module for
  this reason).
- A task cannot read the repository. A script names the files it needs with
  string literals, and the runner embeds them in the task
  (`EngineTests.EMBED_FUNCTIONS`):
  - `include("tests/engine/_fakeplayer.luau")` runs a helper once and
    returns its value. A helper sees the prelude's locals, including the
    guarded `game`, and may name files of its own.
  - `fixture("tests/fixtures/golden/walkthrough.json")` returns a file's text.

  Only files under `tests/` can be embedded (a relative path with no empty,
  `.` or `..` segment), so a script cannot ship anything else from the runner,
  such as its environment. Calls inside comments are ignored, and helpers are
  linted like scripts. Any other use of `include` or `fixture` (another
  argument, a paren-less call, an alias), and a task script over Luau
  Execution's 4 MB limit (`OpenCloud.createTaskRequest` refuses it), stop the
  run before any task is created.
- `describe`, `it`, `expect`, `storeName` and `finish` are the prelude's
  exports, which the runner binds as locals before your script
  (`EngineTests.PRELUDE_EXPORTS`); `RUN_ID` and `PASS_MARKER` are globals.
  For the static checks, `tests/engine/engine.yml` declares them to Selene
  (`tests/engine/selene.toml`, scoped to this folder) and
  `tests/engine/globals.d.luau` declares them to luau-lsp, which analyzes
  `tests/engine` on the Roblox platform. A unit test checks the prelude,
  `engine.yml` and `globals.d.luau` against `PRELUDE_EXPORTS` and
  `EMBED_FUNCTIONS`.
- Line numbers in errors are counted from the start of the submitted task,
  which includes the prelude.
- **DataStores are live**, as are MemoryStore and Messaging. Always name
  stores with `storeName`, as in
  `game:GetService("DataStoreService"):GetDataStore(storeName("Saves"))`,
  which opens `test-<RUN_ID>-Saves`. Deleting test keys after a run is not
  built yet. No engine test opens a store today, so the
  cleanup step comes with the first test that does, and needs the DataStore
  permission described under [API key permissions](#api-key-permissions).

### What protects real DataStores, and what does not

Two checks apply to every engine test:

1. **A lint, before submitting.** The runner strips comments and string
   literals. A store-opening method (`GetDataStore`, `GetOrderedDataStore`,
   and MemoryStore's `GetQueue`, `GetSortedMap` and `GetHashMap`) may only
   appear as a call of the form `:GetDataStore(storeName(...), ...)`; any
   other mention, and any `GetGlobalDataStore`, is refused. That catches string-call and
   table-call syntax (`D:GetDataStore"x"`), indexing by name
   (`D["GetDataStore"]`), taking the method as a value
   (`local f = D.GetDataStore`), and expressions around `storeName`
   (`storeName("x") and "Real"`). Errors name the script and line.
2. **A proxy, at run time.** In the prelude, `game` is a proxy. Its
   `DataStoreService` and `MemoryStoreService` (reached through
   `GetService`, `FindService` or `game.X`) open only names that start with
   `test-<RUN_ID>-` (`GetDataStore`, `GetOrderedDataStore`, `GetQueue`,
   `GetSortedMap`, `GetHashMap`), and `GetGlobalDataStore` always errors.
   Everything else passes through to the real object.

The real guarantee is narrower than "engine tests cannot write to real
DataStores". The lint and the proxy cover test scripts, and any module that
reaches these services through the `game` the test hands it. **A module that
gets the real `DataStoreService` some other way** (its own `game`, which every
`require`d ModuleScript has, or a reference captured earlier) **is not
covered.** The rule that closes that gap belongs to Checkpoint B: the
`Persist` module takes its store prefix from config, as plan 2.3 already
says, and the engine harness sets that prefix to `test-<RUN_ID>-`. Until
then, engine tests must not exercise game code that opens stores.

## CI

Both workflows read the repository secret `ROBLOX_DEV_API_KEY` and the
repository variables `DEV_UNIVERSE_ID`, `DEV_PLACE_ID`,
`RELEASE_UNIVERSE_ID` and `RELEASE_PLACE_ID`. The last two arm the Release
refusal. Docs-only PRs (`docs/**`, `**/*.md`) skip the engine-tests
workflow. `upload-assets.yml` also reads the repository variable
`ROBLOX_CREATOR_USER_ID`, the owner's Roblox user id, which the assets are
created under.

The toolchain comes from the shared composite action
`.github/actions/setup-tools` (as in `ci.yml`), which runs
`tools/bootstrap-agent.sh`: each tool from its release zip, checked against
`tools/toolchain-checksums.txt`, and cached. It needs no token. Both
workflows build with `tools/build.sh`, the same entry point CI uses.

`publish-dev.yml` runs on `workflow_run`, so it checks out the exact commit
the successful CI run tested and never publishes a newer, untested `main`.
CI cancels superseded runs on `main`, so an older commit cannot be published
after a newer one. (GitHub reads `workflow_run` triggers from the default
branch only.)

**Owner setup for `main`'s branch protection** (Settings → Branches, or a
ruleset): make the CI check (`Check, test, build`) a required status
check, and enable "Require branches to be up to date before merging". Then
what CI tests on a PR is what lands on `main`, and what lands is what Dev
gets.

Until the key exists, a small `gate` job posts a notice ("skipped, no key")
and the real job is skipped, so nothing fails. PRs from forks get no secrets
and skip the same way. The key is passed only to the steps that call Open
Cloud. Neither workflow uses `pull_request_target`.

## API key permissions

Create keys at create.roblox.com/credentials. Set the IP restriction to
"allow all", because GitHub-hosted runners have no fixed IP. Set an expiry date.

| Key | Restricted to | Permissions (API system → operation) | Scope names in the API spec |
|---|---|---|---|
| Dev (`ROBLOX_DEV_API_KEY`) | The Dev experience only | **universe-places**: Write | `universe-places:write` |
| | | **universe.place.luau-execution-session**: Read, Write | `universe.place.luau-execution-session:read`, `…:write` (create needs write; get and logs accept either) |
| | | **assets**: Read, Write (for `upload-assets`) | `asset:read`, `asset:write` |
| | | **universe-datastores** (for the test-store cleanup): list stores, list entries, read, delete | `universe-datastores.control:list`, `universe-datastores.objects:list`, `…:read`, `…:delete` |
| Release (`ROBLOX_RELEASE_API_KEY`, `release` environment) | The Release experience only | **universe-places**: Write | `universe-places:write` |

The Assets API guide says to add **assets** to the key's access
permissions with Read and Write for the selected experience; pick the Dev
experience. Assets are created on the owner's account
(`ROBLOX_CREATOR_USER_ID`, see [CI](#ci)), not in the experience. Never add asset permissions to the Release key. The
publish and engine-test tools use no DataStore permission.

**Before the test-store cleanup is built, confirm the Dev key can list.** It
already has DataStore read and delete for the Dev experience; the cleanup must also find
the `test-<RUN_ID>-*` keys, which needs the two `:list` scopes in the table.
Never add DataStore permissions to the Release key.

## Safety rules

1. **The Release refusal.** Every Open Cloud tool refuses to run when `--universe`
   equals `RELEASE_UNIVERSE_ID`, or `--place` equals `RELEASE_PLACE_ID` when
   that is set, unless `RELEASE_JOB=1` is also set. Ids are compared as
   numbers, so `0123` matches `123`. The release workflow (not
   written yet) will be the only job that sets `RELEASE_JOB=1`; the Dev
   workflows never do. The refusal applies in dry runs too.
2. **The guard must be armed.** A real (non-dry) run refuses to start when
   `RELEASE_UNIVERSE_ID` is unset or empty (GitHub passes a missing
   variable as an empty string), and any run refuses a non-numeric value.
   A misconfigured job therefore cannot disable the guard by leaving the
   variable out.
3. **Two keys.** The Dev key cannot reach Release. The Release key lives only
   in the `release` environment, behind a required reviewer.
4. **Saved before Published.** PRs publish only `Saved` versions, which
   players never see. Only `main` publishes `Published` to Dev.
5. **One place builds URLs.** Nothing outside `tools/opencloud.luau`
   constructs an Open Cloud URL. When an endpoint changes, that is the only
   file to fix.
6. **Engine tests use run-prefixed stores and never target Release.**
   See "What protects real DataStores" above for exactly what is covered.
7. **A POST is never retried after a 5xx.** A publish or task creation that
   failed with a 5xx may still have been accepted, so retrying could publish
   twice or start a duplicate task. Only a transport error is retried once,
   as the plan and brief require. A transport error can, rarely, also follow
   an accepted request. The worst case is one extra Saved version, or one
   extra task under the same `RUN_ID`. Create Asset is the exception: a
   transport error there is not retried either, because an extra asset
   would sit in moderation on the owner's account; the run fails, and the
   next run uploads the entry again.
8. **"Server busy" is the one 4xx that is retried.** Roblox sometimes answers
   a publish with HTTP 409 `{"code":"Conflict","message":"Save failed. Server
   is busy ... Please try again in a couple minutes."}`. That is a request to
   retry, not a rejection. A 409 whose code is `Conflict` and whose message
   contains "try again" is retried after each wait in
   `OpenCloud.BUSY_BACKOFF` (30, 60, 120 and 240 seconds today), for any
   request, then reported as a failure. Every
   other 4xx, including any other 409, fails at once. The engine-test run
   deadline allows for this wait.

### What the guard is, and what it is not

The guard lives in code a pull request can change. A same-repository PR,
including one from an agent, can edit `tools/` or the workflows, so against
a malicious PR the guard is not a security boundary. It prevents mistakes,
which is its job. **The security boundary is key scoping.** The Dev key is
restricted to the Dev experience, so nothing that runs on a PR can publish
to Release. The Release key exists only in the `release` environment,
behind a required reviewer.

## What was verified against Roblox's documentation

`create.roblox.com/docs` is blocked from the build container. The details
were instead checked against the same documentation's source, the
`Roblox/creator-docs` repository on GitHub (commit `22a2642`,
2026-10-06):

- `content/en-us/reference/cloud/openapi.json` (Open Cloud v2: Luau Execution)
- `content/en-us/reference/cloud/universes-api/v1.json` (place publishing)
- `content/en-us/cloud/guides/usage-place-publishing.md`

Verified:

- **Publish.** `POST https://apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions?versionType=Saved|Published`,
  with header `x-api-key`, `Content-Type: application/octet-stream` for `.rbxl`,
  and the raw file as the body. The response is `{"versionNumber": n}`
  (documented as `text/plain` containing JSON). Scope `universe-places:write`,
  size limit 10 MiB. Errors: 400, 401, 403, 404, 409 (place not in
  universe), 500.
- **Create task.** `POST /cloud/v2/universes/{u}/places/{p}/luau-execution-session-tasks`
  and `…/places/{p}/versions/{v}/luau-execution-session-tasks`, with a JSON
  body `{ "script": "...", "timeout": "300s" }`. The response is the task
  resource with `path` and `state`. Scope `…luau-execution-session:write`.
  Rate limit: 5 per minute per key owner.
- **Task resource.** `state` is one of `QUEUED`, `PROCESSING`, `COMPLETE`,
  `FAILED`, `CANCELLED`. `error.code` is one of `SCRIPT_ERROR`,
  `DEADLINE_EXCEEDED`, `OUTPUT_SIZE_LIMIT_EXCEEDED`, `INTERNAL_ERROR`.
  Scripts can be up to 4 MB and run for up to 5 minutes. At most 10
  incomplete tasks per place (429 beyond that). 450 KB of logs are kept, and
  tasks are kept for 24 hours.
- **Logs.** `GET …/tasks/{t}/logs` returns `luauExecutionSessionTaskLogs[].messages[]`
  (FLAT view, one string per `print`), paginated with `maxPageSize` (up to
  10000), `pageToken` and `nextPageToken`.
- **Stability.** The spec marks Luau Execution `STABLE` and place publishing `BETA`.
- **Assets** (`content/en-us/reference/cloud/assets/v1.json` and
  `cloud/guides/usage-assets.md`, commit `9dc22ac`, 2026-10-08).
  `POST https://apis.roblox.com/assets/v1/assets`, `multipart/form-data`
  with a JSON `request` part (`assetType`, `displayName`, `description`,
  `creationContext.creator.userId`) and the file as `fileContent`; the
  response is an Operation `{path: "operations/{id}", done, response}`,
  polled with `GET /assets/v1/operations/{id}`. `GET
  /assets/v1/assets/{id}?readMask=...` reads `moderationResult`. Scopes
  `asset:read` and `asset:write`. 20 MB per file. Images and audio cannot
  be updated in place. Marked `BETA`. The schema gives `assetId` as an
  integer and states as `Approved`; the guide's example shows a string
  and `MODERATION_STATE_APPROVED`. `tools/opencloud.luau` reads both.

Proven against Dev (brief 004, engine-tests on PR #15):

- **Polling by the returned `path`.** Tasks created on the versioned endpoint
  were polled with `GET /cloud/v2/{task.path}` and their logs read from
  `{task.path}/logs`, to completion.
- **The place name in the smoke test.** `GetProductInfoAsync(game.PlaceId)`
  returns "Amy and the Rain Forest (Dev)" for the Dev place.

Not verified:

- **Uploading as `Image`.** The guide's table lists "Decal, Image" and its
  examples use `Decal`. The uploader sends `assetType: "Image"`, whose id an
  ImageLabel takes directly. The first real run on Dev proves it; if it is
  refused, `OpenCloud.ASSET_TYPES.image` is the one line to change.

- **The 429 `Retry-After` header.** Whether Open Cloud sends it is unknown.
  The tool falls back to 15 seconds.
- **The API key UI.** The labels on the Creator Dashboard key page come from
  the place-publishing guide ("universe-places", operation "Write"). The
  Luau Execution label is taken from its scope name.
