# Maintenance

Regular upkeep (plan section 6, Phase 3): what keeps itself current, what
needs the owner, and when. The Open Cloud side is in
[`OPEN_CLOUD.md`](OPEN_CLOUD.md).

## Automated

Both jobs open a pull request and nothing else, and CI runs the full check,
test and build against the new versions. Dependabot's PRs are merged by
**DependaBuddy** ([laazyj/buddies](https://github.com/laazyj/buddies)),
the owner's own automation: a patch or minor action bump merges once the
required checks are green, a major one is escalated to the owner with an
impact summary. The "Toolchain updates" PR is not Dependabot's, so the
owner reviews and merges it as any other PR. DependaBuddy merges nothing
else, and the `main` ruleset gates its merges like anyone's (the App is
never a bypass actor), so a bump still has to pass every tier 0 guard.

| What | Kept current by | When | PR |
|---|---|---|---|
| Every `uses:` line in `.github/workflows/` and `.github/actions/setup-tools/` | Dependabot (`.github/dependabot.yml`) | Weekly | One grouped PR, labelled `dependencies` |
| The tool pins in `rokit.toml` (Rojo, Lune, Wally, StyLua, Selene, luau-lsp), their lines in `tools/toolchain-checksums.txt`, the `@lune` typedefs alias in `.luaurc` that follows Lune, any Wally dependency in `wally.toml`, and Selene's Roblox standard library `roblox.yml` | `.github/workflows/toolchain-check.yml` running `tools/toolchain-check.luau` and `selene generate-roblox-std` | Weekly (Monday 06:17 UTC), or by hand from the Actions tab | One PR titled "Toolchain updates", labelled `dependencies`, updated in place while open |

Dependabot does not understand `rokit.toml` or `wally.toml`, which is why the
second job exists. It compares each pin with the repository's latest GitHub
release (Wally dependencies with the Wally registry) and rewrites the pins
that are behind. For each bumped tool it rewrites the checksum lines with the
new release's asset names and the SHA-256 digests GitHub records for them,
and `tools/bootstrap-agent.sh` checks them when CI installs the new tools.

`roblox.yml` is generated from Roblox's API dump, which changes with Roblox's
weekly releases, not with this repository. CI regenerates it on every run
(`tools/roblox-std.sh check`) and **warns**, without failing the PR, when it
differs from the committed file beyond its timestamps: a stale file only
means Selene lacks Roblox's newest globals. The warning's step uploads the
fresh file as the `roblox-std` artifact. The weekly toolchain job keeps it
current and fails hard if it cannot generate it.

**A PR opened with the job's own token does not trigger CI** (a GitHub
rule that stops workflows triggering workflows). So that the "Toolchain
updates" PR is tested, create a fine-grained personal access token limited
to this repository with **Contents: read and write** and **Pull requests:
read and write**, give it an expiry date, and save it as the repository
secret `TOOLCHAIN_PR_TOKEN`. Without it the job still opens the PR, and you
start CI by closing and reopening it. The `upload-assets` workflow opens its
"Asset ids" PR with the same token, so keep it when rotating.

## By hand

| What | Where | How |
|---|---|---|
| actionlint and zizmor | `tools/install-workflow-linters.sh` | Pinned by version and checksum per platform; the script's header says how to bump. actionlint is the kjanat/actionlint fork. |
| A pin in `rokit.toml` changed by hand | `tools/toolchain-checksums.txt` | Change the tool's tag, asset names and SHA-256s with it (the digests are on the release page); `tools/bootstrap-agent.sh` refuses a pin without matching lines. |
| The runner image of CI's `ci` job and the playtest's `sheets` and `publish` jobs | `runs-on: ubuntu-24.04` in `.github/workflows/ci.yml` and `.github/workflows/studio-playtest.yml` | Pinned, not `ubuntu-latest`, which moves to 26.04 in November 2026; ImageMagick (installed by the `sheets` job and by CI) is not in the 24.04 image, and ImageMagick 7 renames `convert` and `montage` behind `magick`. So the bump is a deliberate change, with `tests/lune/tools/screens.spec.luau`'s end-to-end specs, which fail in CI without ImageMagick, as the proof. |
| Roblox Studio on the Mac | The Mac runner's virtual machine ([`MAC_RUNNER.md`](MAC_RUNNER.md)) | Studio auto-updates weekly and can break the tier 3 bridge. The Mac job reports the Studio version with every run. When a tier 3 run fails after a Studio update, compare the reported version with the last green run's, and fix the wrapper in `tools/studio-playtest/` rather than holding Studio back. |
| Roblox engine and Open Cloud API changes | `tools/opencloud.luau` | Tier 2 fails on a changed endpoint. Re-check against the creator-docs OpenAPI specs (see "What was verified" in `OPEN_CLOUD.md`). |

## Repository settings (one-time, owner)

- **Require actions to be pinned to a full-length commit SHA**: Settings →
  Actions → General → "Require actions to be pinned to a full-length commit
  SHA". Every `uses:` already is (with the version as a trailing comment,
  which Dependabot keeps current); the setting stops an unpinned one from
  ever running. The local `$/.github/actions/setup-tools` is exempt: it is
  this repository at the commit being run.
- **Make CI a required status check on `main`**: Settings → Rules →
  Rulesets → the `main` ruleset → require the `Check, test, build`,
  `Core changes come with test changes`, `Check for the Dev key and a code
  change` and `Publish a Saved version and run the engine tests` checks
  (the engine-tests workflow runs on every PR; its gate skips the test job
  for docs-only and keyless runs, and a skipped job satisfies a required
  check; requiring the gate too means a gate that fails, say on the API
  call that lists the PR's files, still blocks the merge). Leave
  **"Require branches to be up to date before merging" off**: DependaBuddy
  enables auto-merge
  on a Dependabot PR, Dependabot rebases only on a conflict, so with the
  rule on every bump would wait behind `main` and be raised as stuck. The
  cost is that a PR can merge with CI that ran against an older `main`;
  CI runs again on the push to `main`, and the Dev publish starts only
  after that run is green ([`OPEN_CLOUD.md`](OPEN_CLOUD.md#ci)), so a bad
  combination leaves `main` red and never reaches Dev. **A red `main` is
  fixed or reverted before anything else merges.** The "Update branch"
  button stays; use it on a PR that has fallen behind.

## Coverage guards and the mutation check

The guards of plan section 4 are `tools/guard coverage` (tier 0),
`.github/workflows/test-change.yml` and the nightly
`.github/workflows/mutation.yml`. They are structural: they prove a spec
exists and names what it should (in code or strings, not comments), not
that it tests anything. A spec that is trivial on purpose passes them;
review and the mutation check are what catch that.

Owner, once: create the label `no-test-change` (Issues → Labels). A PR
carrying it also needs a line "No test change: <why>" in its body.

The canned faults live in `tools/lib/mutate.luau`. `tools/guard faults`
(tier 0) fails a PR that leaves a fault no longer matching the code; update
the fault's edit in the same PR. "Break a save migration" removes the
Checkpoints Migration 1 -> 2 adds; when a schema version is added, point it
at the newest Migration.

### Luau line coverage (spike, not a gate)

Result of brief 008's spike, 2026-10-09:

- **Lune 0.10.5 cannot.** `luau.compile` accepts `coverageLevel`, but
  nothing reads the counters back, and `lune run` has no coverage flag.
- **The Luau CLI can.** `luau --coverage <script>` writes lcov to
  `coverage.out` for every module the script requires. The core specs
  import nothing from Lune, so they run under it with
  `tools/coverage-spike.luau`, a stand-in for the runner's test API. To
  reproduce, take `luau` from luau-lang/luau release **0.741**
  (`luau-ubuntu.zip`, SHA-256
  `134dc762ad26232af83e43f98dec03ff6030dd3a4452f9408b9d50ccea025503`) and
  run `tools/coverage-spike.sh path/to/luau`. It prints each core module's
  lines reached and the total. The spike measured 593 of 594 lines of
  `src/core`; the one line missed (an Ending with no Lines) now has a
  test in `StoryEngine.spec`, and the script reports 594 of 594 (100%).
- **Not wired in yet.** The content, place and tools specs need `@lune/*`,
  which the CLI lacks, so only the core can be measured this way. Doing it
  for real means pinning the CLI in `rokit.toml` and
  `tools/toolchain-checksums.txt`, then a `tools/coverage.sh` that reports
  the percentage in the job summary.

## Saves

### ProfileStore (Wally)

`wally.toml` pins `lm-loleris/profilestore` exactly (`=1.0.3`, published from
github.com/MadStudioRoblox/ProfileStore). `tools/build.sh` runs
`wally install` when `ServerPackages/` is missing or older than `wally.toml`,
and fails unless every installed file matches its SHA-256 in
`tools/package-checksums.txt` (the version pins the name, the checksums pin
the content); CI fails the build if the install fails. Locally, without the Wally registry (`api.wally.run`; cloud
sessions are denied it), the build warns and leaves ProfileStore out, and the
game then plays without saves. `ServerPackages/` and `wally.lock` are not
committed. The weekly toolchain job bumps the pin like any other.

When the pin moves (by hand, or in the weekly "Toolchain updates" PR, whose
build then fails on the checksums until they are updated), read
ProfileStore's changes against the parts Persist uses (the types at the top
of `src/server/Persist.luau`), then replace the lines in
`tools/package-checksums.txt` with the new files' SHA-256s from a CI build;
`tests/engine/persist.luau` is what proves the new version. The registry
copy is published from Windows and carries CRLF line endings, so its
SHA-256 never matches the file on GitHub; `diff -w` against the GitHub
file is the comparison that shows whether the code is the same (it was for
1.0.3, see PR #33).

### A new schema version

Change `src/core/Save.luau` and its spec together: bump `Save.VERSION`,
add `Save.MIGRATIONS[old]`, add a test for it in
`tests/lune/core/Save.spec.luau`, and keep the change additive (new fields
only), so the previous version still reads the new Save (glossary,
**Schema version**). Never ship two schema versions between Release
promotions.

### A Save that is not a Save

Data in a player's key that is no Save of any version (corrupt, or edited
by hand) is kept whole under `unreadable` in a new Save, and the server logs
`[Persist] <name>'s Save: <why>`; the player starts the Story afresh and
saves from then on. To repair one, read the key in the Creator Dashboard's
data store manager (Dev or Release, store `Progress`, key
`Player_<user id>`), fix the `unreadable` value into a Save, and write it
back while the player is away. A Save two or more versions newer is never
touched (that player plays without saving until the server catches up).

### Studio DataStore access on Dev (Mac playtests)

Studio reaches DataStores only when the experience allows it. Owner, once,
for the **Dev** experience only: open the Dev place in Studio, then **File →
Game Settings → Security**, turn on **Enable Studio Access to API Services**
and **Save**. The setting belongs to the experience, so it holds for every
Studio session on Dev, the Mac runner's included. Only the setting is
saved; nothing is published (only CI publishes). Never turn it on for
Release.

With it on, a Studio playtest of the Dev place (the Mac runner's tier 3,
or the owner by hand) saves to the Dev experience's real `Progress` store
under the tester's own user id, exactly as a Dev server does: the Title
screen appears on the next playtest, with Continue. To start over, use
"Start again" on the Title screen. With it off, ProfileStore prints
"Roblox API services unavailable - data will not be saved" and every
playtest starts fresh, which is fine for a tier 3 run that wants the golden
first minute. Dev saves never reach Release: each experience has its own
DataStores (plan section 3).

## The camera rule in Studio (tier 3, by hand until the Mac runner)

`tests/studio/CameraRule.client.luau` is the tier 3 assertion for "Amy's
face is never seen" (feel.md, Invariants and section 2). Until the Mac
runner ([`MAC_RUNNER.md`](MAC_RUNNER.md)) runs it, the owner runs it by hand on the Mac:

1. Build the place (`tools/build.sh`, or download the `place` artifact
   of the PR's CI run) and open `build/AmyAndTheRainforest.rbxl` in
   Studio. Do not publish it: only CI publishes.
2. In the Explorer, add a **LocalScript** under **StarterPlayer →
   StarterPlayerScripts**, name it `CameraRule`, and paste the file's
   contents into it.
3. Press **Play** and play the Story to the end card, or jump with the
   Dev shortcuts (`/chapter 2`, `/quest chapter3.meet_fox`) to the Shots.
   For phone and tablet, use **Test → Device** emulation (a phone and a
   tablet preset, both orientations) and turn the view by dragging.
4. Read the Output: every failure is a `[CameraRule] FAIL` line, and a
   summary (`N checks, M failures`) prints every 30 s and at the end card.
   A pass is `0 failures` with checks from every Shot.

What it checks, and when, is in the script's header. Close the place
without saving the script into anything you keep.

## Device classes and the Onboarding in Studio (tier 3, by hand until the Mac runner)

`tests/studio/DeviceLayout.client.luau` holds the tier 3 assertions for the
Screen layout (feel.md sections 1, 3 and 4): text fits, the 60-character
column, the safe area, contrast of at least 4.5:1, no overlapping
interactive elements and touch targets of at least 44 units. It also
follows the Onboarding of a fresh Save (section 6). Until brief mac-001's
runner runs it, the owner runs it by hand on the Mac:

1. Build the place (`tools/build.sh`, or download the `place` artifact
   of the PR's CI run) and open `build/AmyAndTheRainforest.rbxl` in
   Studio. Do not publish it: only CI publishes.
2. In the Explorer, add a **LocalScript** under **StarterPlayer →
   StarterPlayerScripts**, name it `DeviceLayout`, and paste the file's
   contents into it. It can run beside `CameraRule`.
3. Open **Test → Device** (the device emulator) and pick a phone preset
   (an iPhone of about 844 × 390, such as iPhone 14) in landscape.
4. Press **Play**. With no Save in Studio the Story is fresh, so the
   Onboarding runs: let the Chapter card fade (or tap it), tap past the
   first Line, walk, and talk to Dad. Then rotate to portrait with the
   emulator's rotate button and play on: the layout is checked again on
   every viewport change.
5. Stop, switch to a tablet preset (an iPad Pro of about 1366 × 1024),
   and repeat in landscape and portrait. Use **Start again** on the Title
   screen to see the Onboarding again on a Save that has one.
6. Read the Output: every failure is a `[DeviceLayout] FAIL` line, every
   Onboarding expectation met is a `[DeviceLayout] ok:` line, and a
   summary (`N checks, M failures`, with the viewport) prints every 30 s.
   A pass is `0 failures`, with the four Onboarding `ok:` lines on a fresh
   Save, on each preset and orientation.

Contrast is computed as feel.md section 3 says, against the 3D world at
its worst (black or white), because a LocalScript cannot read pixels;
text over an image (the Title screen's words) is counted, not measured,
and is the visual rubric's to judge. Close the place without saving the
script into anything you keep.

## Workflow security checks

`tools/check.sh` runs actionlint and zizmor (pedantic persona) on every PR;
zizmor's online audits run in CI only. The few findings accepted rather than
fixed are in `.github/zizmor.yml`, each with its reason.

**Where the Dev key lives.** `ROBLOX_DEV_API_KEY` exists twice, with the
same value: as a secret of the `dev` environment (limited to the `main`
branch, no required reviewers), which `publish-dev.yml` and
`upload-assets.yml` read through `environment: dev`, so a workflow edited
on a PR branch cannot reach a publish or upload path with the key; and as a
repository secret, which `engine-tests.yml` reads, because engine tests run
on PR branches by design. Rotate both together. If the repository secret is
missing, every engine-tests run skips at its gate with "ROBLOX_DEV_API_KEY
is not available to this run"; if the environment secret is missing, Dev
publishes and uploads skip the same way.

## Key rotation

Every key has an expiry date. Record it here when you create or rotate a
key, and rotate at least 30 days before it expires; the release checklist
checks this before every promotion.

| Secret | What it is | Expires | Rotate by |
|---|---|---|---|
| `ROBLOX_DEV_API_KEY` | Open Cloud key, Dev experience | _set when created_ | 30 days before |
| `ROBLOX_RELEASE_API_KEY` | Open Cloud key, Release experience (`release` environment) | _not created yet_ | 30 days before |
| `TOOLCHAIN_PR_TOKEN` | Fine-grained GitHub token for the toolchain and Asset ids PRs | _set when created_ | 30 days before |

To rotate a Roblox key: create the new key at
create.roblox.com/credentials with the same permissions (see `OPEN_CLOUD.md`),
replace the secret, run the engine tests on any open PR (or a manual Dev
publish) to prove it, then delete the old key.
