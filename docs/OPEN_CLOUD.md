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
| `tools/opencloud.luau` | Builds every Open Cloud request and parses every response. HTTP is injected, so tests mock it. Retry policy: a transport error or 5xx is retried once; a 4xx never is. |
| `tools/publish.luau` | Publishes a `.rbxl` as a `Saved` or `Published` version and prints the version number on stdout. |
| `tools/run-engine-tests.luau` | Runs engine test scripts as Luau Execution tasks, up to 4 at once, and fails unless every one passes. |
| `tools/lib/` | Shared argument parsing and the Release guard (`cli.luau`), and the logic behind the two tools. |
| `tests/engine/_prelude.luau` | `describe` / `it` / `expect`, `storeName`, `finish` for engine test scripts. |
| `tests/engine/*.luau` | Engine tests. Files starting with `_` are helpers and are not run. |
| `tests/lune/tools/` | Unit tests for all of the above, against a mocked HTTP function. |
| `.github/workflows/publish-dev.yml` | Push to `main` (or a manual run from `main`): build, publish to Dev as `Published`. |
| `.github/workflows/engine-tests.yml` | Every PR: build, publish to Dev as `Saved`, run `tests/engine/` against that exact version. |

Two deviations from the plan's wording. The scripts are `.luau`, not
`.lune`, because Lune 0.10 runs only `.luau` and `.lua` files. The guard
variable is `RELEASE_JOB=1`, not `RELEASE=1`.

## Running locally

Run from the repository root, with Lune installed (`rokit install` once
brief 001's `rokit.toml` exists).

```sh
# Unit tests (no network)
lune run tests/lune/tools/run

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
  scripts do not start on their own. The DataModel is a fresh copy of the place version, and
  changes are not saved.
- **DataStores are live** (as are MemoryStore and Messaging). Always name stores with
  `DataStoreService:GetDataStore(storeName("Saves"))`, which gives
  `test-<RUN_ID>-Saves`. The runner refuses to submit a script that calls
  `GetDataStore` or `GetOrderedDataStore` without `storeName(...)`, or that
  calls `GetGlobalDataStore` at all. This is a lint, not a sandbox.
  Deleting test keys after a run is not built yet; plan section 4 assigns it
  to a cleanup step.
- Line numbers in errors are counted from the start of the submitted task,
  which includes the prelude.

## CI

Both workflows read the repository secret `ROBLOX_DEV_API_KEY` and the
repository variables `DEV_UNIVERSE_ID`, `DEV_PLACE_ID` and
`RELEASE_UNIVERSE_ID`. The last arms the Release refusal.

Until the key exists, a small `gate` job posts a notice ("skipped, no key")
and the real job is skipped, so nothing fails. PRs from forks get no secrets
and skip the same way. The key is passed only to the steps that call Open
Cloud. Neither workflow uses `pull_request_target`.

The build steps need `rokit.toml` from brief 001.

## API key permissions

Create keys at create.roblox.com/credentials. Set the IP restriction to
"allow all", because GitHub-hosted runners have no fixed IP. Set an expiry date.

| Key | Restricted to | Permissions (API system → operation) | Scope names in the API spec |
|---|---|---|---|
| Dev (`ROBLOX_DEV_API_KEY`) | The Dev experience only | **universe-places**: Write | `universe-places:write` |
| | | **universe.place.luau-execution-session**: Read, Write | `universe.place.luau-execution-session:read`, `…:write` (create needs write; get and logs accept either) |
| Release (`ROBLOX_RELEASE_API_KEY`, `release` environment) | The Release experience only | **universe-places**: Write | `universe-places:write` |

Asset upload permissions for the Dev key come with the asset-upload brief.
Neither key needs DataStore permissions for these tools.

## Safety rules

1. **The Release refusal.** Both tools refuse to run when `--universe`
   equals `RELEASE_UNIVERSE_ID`, unless `RELEASE_JOB=1` is also set. Ids are
   compared as numbers, so `0123` matches `123`. The release workflow (not
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
6. **Engine tests use run-prefixed DataStores and never target Release.**
   Store names go through `storeName()` (see above).

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

Not verified:

- **Polling by the returned `path`.** The tools poll `GET /cloud/v2/{task.path}`
  and read `{task.path}/logs`. The spec lists the task's resource patterns,
  including the short `…/luau-execution-session-tasks/{id}` forms a create
  can return. Its explicit GET operations, however, are written only for the
  `…/versions/{v}/luau-execution-sessions/{s}/tasks/{t}` form. Brief 004
  proves this against Dev. If it is wrong, the fix belongs in
  `OpenCloud.getTaskRequest`, `OpenCloud.listLogsRequest` and
  `OpenCloud.parseTaskResponse`, which checks the returned path.
- **The 429 `Retry-After` header.** Whether Open Cloud sends it is unknown.
  The tool falls back to 15 seconds.
- **The place name in the smoke test.** `tests/engine/smoke.luau` reads it
  with `MarketplaceService:GetProductInfo(game.PlaceId)` and expects it to
  start with "Amy and the Rain Forest", as named in plan section 10. Brief
  004 confirms this against the real Dev experience.
- **The API key UI.** The labels on the Creator Dashboard key page come from
  the place-publishing guide ("universe-places", operation "Write"). The
  Luau Execution label is taken from its scope name.
