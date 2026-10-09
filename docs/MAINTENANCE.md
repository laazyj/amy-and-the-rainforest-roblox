# Maintenance

Regular upkeep (plan section 6, Phase 3): what keeps itself current, what
needs the owner, and when. The Open Cloud side is in
[`OPEN_CLOUD.md`](OPEN_CLOUD.md).

## Automated

Both jobs open a pull request and nothing else. CI runs the full check,
test and build against the new versions; nothing merges automatically, and
the owner reviews and merges as for any other PR.

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
| actionlint and zizmor | `tools/install-workflow-linters.sh` | Pinned by version and checksum per platform; the script's header says how to bump. |
| A pin in `rokit.toml` changed by hand | `tools/toolchain-checksums.txt` | Change the tool's tag, asset names and SHA-256s with it (the digests are on the release page); `tools/bootstrap-agent.sh` refuses a pin without matching lines. |
| Roblox Studio on the Mac | The Mac runner (brief mac-001) | Studio auto-updates weekly and can break the tier 3 bridge. The Mac job reports the Studio version with every run. When a tier 3 run fails after a Studio update, compare the reported version with the last green run's, and fix the wrapper in `tools/studio-playtest/` rather than holding Studio back. |
| Roblox engine and Open Cloud API changes | `tools/opencloud.luau` | Tier 2 fails on a changed endpoint. Re-check against the creator-docs OpenAPI specs (see "What was verified" in `OPEN_CLOUD.md`). |

## Repository settings (one-time, owner)

- **Require actions to be pinned to a full-length commit SHA**: Settings →
  Actions → General → "Require actions to be pinned to a full-length commit
  SHA". Every `uses:` already is (with the version as a trailing comment,
  which Dependabot keeps current); the setting stops an unpinned one from
  ever running. The local `./.github/actions/setup-tools` is exempt: it is
  this repository at the commit being run.
- **Make CI a required status check on `main`**: Settings → Branches (or a
  ruleset) → require the `Check, test, build` check, and enable "Require
  branches to be up to date before merging". See also
  [`OPEN_CLOUD.md`](OPEN_CLOUD.md#ci), which relies on it for the Dev
  publish.

## Workflow security checks

`tools/check.sh` runs actionlint and zizmor (pedantic persona) on every PR;
zizmor's online audits run in CI only. The few findings accepted rather than
fixed are in `.github/zizmor.yml`, each with its reason.

**Follow-up (owner):** the Roblox keys are repository secrets, which zizmor's
`secrets-outside-env` audit flags (auditor persona). For `publish-dev.yml`,
create a `dev` environment limited to the `main` branch, move
`ROBLOX_DEV_API_KEY` into it and set `environment: dev` on the publish job, so
a workflow edited on a PR branch cannot reach a publish path with the key.
`engine-tests.yml` runs on PRs by design, so it keeps the repository secret.

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
