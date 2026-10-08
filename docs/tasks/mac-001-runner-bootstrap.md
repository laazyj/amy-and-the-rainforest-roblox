# mac-001 — Self-hosted runner bootstrap (Phase 1, run on the MacBook)

**Kind:** environment. **Not needed until Phase 1.** Written now so the
Mac session can be started with a single pointer to this file.

## Goal

The MacBook is a GitHub Actions self-hosted runner labelled `studio`,
Roblox Studio is driven by its built-in MCP server, and a workflow proves
it from the cloud.

## Prerequisites (human)

- Roblox Studio installed and logged in to the owning account.
- The repository cloned, Claude Code running in it on the Mac.
- A GitHub runner registration token (Settings → Actions → Runners →
  New self-hosted runner). Paste it when the session asks; never commit it.

## Must

1. Install the runner as a **launchd agent in the logged-in GUI session**
   (not a daemon), labels `self-hosted, macOS, studio`. Disable sleep and
   screen lock while on power. Write the setup as `tools/mac/setup.sh`
   with the token taken from an environment variable.
2. Enable Studio's MCP server and record the Studio version.
3. `tools/studio-playtest/`: a wrapper that, given a built `.rbxl`, opens
   it in Studio through the MCP server, starts Play, runs a script that
   prints the place name and `RunService:IsStudio()`, captures the
   viewport with `screencapture`, stops Play, and exits non-zero on any
   failure. Everything Studio-specific lives in this directory.
4. `.github/workflows/studio-smoke.yml` on `workflow_dispatch`: runs on
   `[self-hosted, studio]`, downloads the latest `place` artifact from
   `main`, runs the wrapper, uploads the screenshot and a JSON report
   (Studio version, duration, pass/fail) as artifacts. `continue-on-error`
   is **not** set on this workflow; it is the proof.
5. `docs/MAC_RUNNER.md`: what was installed, how to re-register, known
   failure modes (Studio auto-update, screen locked, MCP disabled).

## Done when

The coordinator triggers `studio-smoke.yml` from the cloud, it completes
green, and the uploaded screenshot shows the game viewport.
