# 017 — Agent bootstrap: local toolchain and Selene's Roblox standard library

**Kind:** logic-provable. No Mac, no secrets. Independent of other briefs.

## Goal

Every build session can run `tools/check.sh`, `tools/test.sh` and
`tools/build.sh` locally, exactly as CI does, without network workarounds.

## Why

In the cloud containers api.github.com is blocked by the proxy, so
`rokit install` fails and sessions hand-download release zips. Selene's
`std = "roblox"` generates its standard library by downloading Roblox's API
dump with an HTTP client that ignores the proxy certificate, so Selene
either does not run locally or runs with the wrong library. Only CI lints
for real. That costs every session time and lets lint failures reach CI.

## Must

1. **Commit Selene's Roblox standard library.** Add a CI step (in the
   composite action or `ci.yml`) that runs `selene generate-roblox-std` and
   fails if the generated `roblox.yml` differs from the committed one at
   the repository root, with a clear message to run the update. Commit the
   file once by generating it in a `workflow_dispatch` run that opens a PR,
   or from CI's output artifact. Selene prefers a project-directory
   `roblox.yml` over its cache, so local runs need no network. Confirm
   `tests/engine/selene.toml` (`roblox+engine`) still resolves.
2. **Keep it fresh.** The weekly toolchain job runs
   `selene update-roblox-std` and includes any change to `roblox.yml` in its
   "Toolchain updates" PR.
3. **`tools/bootstrap-agent.sh`.** Installs the pinned toolchain into
   `~/.rokit/bin` or `build/bin` from the github.com release zips using the
   versions in `rokit.toml` and SHA-256 checksums kept in one file
   (`tools/toolchain-checksums.txt`, also used or cross-checked by the
   composite action so there is one source of truth), fetches the luau-lsp
   Roblox definitions for the pinned version, runs `lune setup`, installs
   actionlint and zizmor via the existing script, and prints what it did.
   Idempotent; skips what is present; works with and without the proxy;
   never pipes a remote script to a shell.
4. **SessionStart hook.** A repository `.claude/settings.json` hook that
   runs the bootstrap on session start (use the `session-start-hook`
   guidance: fast, idempotent, failures reported but non-fatal), so
   `tools/check.sh` works before the session reads its brief. Document in
   `CLAUDE.md` that local runs of all three scripts are expected before
   every push.
5. **Prove it.** From a fresh clone in a cloud container: run the bootstrap,
   then `tools/check.sh`, `tools/test.sh`, `tools/build.sh`, all green, and
   paste the output in the PR. CI stays green.

## Must not

- Weaken any check. Change pinned versions. Add a network dependency that
  the proxy blocks.

## Done when

- `tools/check.sh` passes locally in a cloud session with Selene using the
  committed library; CI's drift check passes; the toolchain job knows
  about `roblox.yml`.
