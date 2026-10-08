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
| The tool pins in `rokit.toml` (Rojo, Lune, Wally, StyLua, Selene, luau-lsp), the `@lune` typedefs alias in `.luaurc` that follows Lune, and any Wally dependency in `wally.toml` | `.github/workflows/toolchain-check.yml` running `tools/toolchain-check.luau` | Weekly (Monday 06:17 UTC), or by hand from the Actions tab | One PR titled "Toolchain updates", labelled `dependencies`, updated in place while open |

Dependabot does not understand `rokit.toml` or `wally.toml`, which is why the
second job exists. It compares each pin with the repository's latest GitHub
release (Wally dependencies with the Wally registry) and rewrites the pins
that are behind.

**A PR opened with the job's own token does not trigger CI** (a GitHub
rule that stops workflows triggering workflows). So that the "Toolchain
updates" PR is tested, create a fine-grained personal access token limited
to this repository with **Contents: read and write** and **Pull requests:
read and write**, give it an expiry date, and save it as the repository
secret `TOOLCHAIN_PR_TOKEN`. Without it the job still opens the PR, and you
start CI by closing and reopening it.

## By hand

| What | Where | How |
|---|---|---|
| actionlint and zizmor | `tools/install-workflow-linters.sh` | Pinned by version and checksum per platform; the script's header says how to bump. |
| Rokit itself | `.github/actions/setup-tools/action.yml` (`ROKIT_VERSION`, `ROKIT_SHA256`) | Pinned by version and checksum together. To bump: download the new `rokit-<version>-linux-x86_64.zip`, check it against the asset's SHA-256 digest on the release page, and change both lines in one PR. |
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

## Key rotation

Every key has an expiry date. Record it here when you create or rotate a
key, and rotate at least 30 days before it expires; the release checklist
checks this before every promotion.

| Secret | What it is | Expires | Rotate by |
|---|---|---|---|
| `ROBLOX_DEV_API_KEY` | Open Cloud key, Dev experience | _set when created_ | 30 days before |
| `ROBLOX_RELEASE_API_KEY` | Open Cloud key, Release experience (`release` environment) | _not created yet_ | 30 days before |
| `TOOLCHAIN_PR_TOKEN` | Fine-grained GitHub token for the toolchain PR | _set when created_ | 30 days before |

To rotate a Roblox key: create the new key at
create.roblox.com/credentials with the same permissions (see `OPEN_CLOUD.md`),
replace the secret, run the engine tests on any open PR (or a manual Dev
publish) to prove it, then delete the old key.
