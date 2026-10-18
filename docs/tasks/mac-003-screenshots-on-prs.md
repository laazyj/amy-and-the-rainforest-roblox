# mac-003 — Screenshots on pull requests

**Kind:** tooling, one small game change, and the first baselines. Two
PRs: **A** from a cloud session (the Dev shortcut, the publishing job,
the baselines workflow, the CI prompt), then **B** on the MacBook (the
title capture, the guest's display). **Source:** the owner's ask of
2026-10-16 after PR #49 changed the title screen with no picture of it
on the PR; mac-002 (#50) made the pictures, this brief puts them where
they are reviewed. **Owner's decision (2026-10-16):** the title screen is
reached through a `/title` Dev shortcut, not a separate flag.

## Goal

A pull request that changes what is on screen gets, on the owner's
`needs-playtest` label, one comment with a contact sheet per device
(the title screen included) and, for every capture that differs from
`main`'s baseline, the before, the after and the difference. Baselines
live in the repository and change only through a pull request. The Mac
keeps read-only permissions and no secrets.

## Must

### A. Cloud session

1. **The `/title` Dev shortcut** (`src/core/DevShortcut.luau`,
   `src/server/Dev/DevShortcuts.luau`): no argument; the server offers
   the Title screen as it does to a returning player at the current
   Progress (`ShowTitle`, the Story waiting for the Title choice), so the
   title with its buttons can be seen at any point of the Story on any
   device. `Continue` carries on where the player was. Tier 1 covers the
   parse (`DevShortcut.spec`) and the host's offer and wait. Release
   builds strip the Dev folder, so nothing reaches Release and the golden
   file is unchanged. The glossary's Dev shortcut row and the Dev
   shortcut comment in `DevShortcut.luau` list it.
2. **The publishing job** in `.github/workflows/studio-playtest.yml`: a
   second job, `publish`, on `ubuntu-latest`, `needs: playtest`, run
   whenever the Mac job uploaded its artifact (`if: always()` with the
   artifact present), with `contents: write` and `pull-requests: write`
   on that job alone; the Mac job's permissions and secrets stay as they
   are (brief mac-001a, Must 7, and the tier 0 guard `mac-workflows`
   still passes). It:
   - downloads the `studio-playtest` artifact;
   - builds one contact sheet per device with ImageMagick (`montage`),
     each capture labelled with its name, and a small index image of the
     title screen across devices;
   - compares every capture with its baseline in `docs/screens/` (Must
     A3) with ImageMagick `compare`, at the plan's level 2 tolerance
     (section 4), writing a difference image for each capture that
     differs and a count of changed captures per device;
   - pushes the sheets, the captures and the differences to the branch
     `playtest/pr-<N>` (force-pushed, one commit, so the branch never
     grows), or to `playtest/main` for a run with no `pr` input;
   - posts **one** comment on pull request N, found and updated in place
     by a marker, with the contact sheets inline (raw file links to the
     branch), then for each changed capture a row of before, after and
     difference, the counts, the Studio version against the pin, the
     device warnings from `report.json`, and the artifact link. For a
     run of `main` it writes the same to the job summary instead.
   - A small workflow on `pull_request: closed` (GitHub's runners,
     `contents: write`) deletes `playtest/pr-<N>`. Fork pull requests
     never reach any of this.
3. **Baselines** in `docs/screens/<device>/<nn>-<kind>-<name>.png` (plan
   section 2.2), one per capture per device, title screen included. A
   workflow `baselines.yml` on `workflow_dispatch` (GitHub's runners)
   takes the latest `studio-playtest` artifact of a `main` run and opens
   a "Baselines" pull request replacing `docs/screens/`, the way
   `upload-assets.yml` opens its "Asset ids" PR; the owner accepts a
   baseline by merging it. The first set is made this way once Must B is
   on `main`. `docs/screens/README.md` says what the files are, how they
   are made and that they are never edited by hand.
4. **The CI prompt**: a step in `ci.yml`'s pull request job that, when
   the PR's changed files include `src/client/**`,
   `src/core/ScreenLayout.luau`, `src/content/palette.luau`,
   `src/content/title.luau`, `src/content/hints.luau`,
   `docs/design/feel.md` or `assets/images/**`, posts one comment
   (updated in place by a marker, `pull-requests: write` on that job):
   "This pull request changes what is on screen. The owner's
   `needs-playtest` label brings screenshots here." The list of paths is
   one table in `tools/lib/visual-paths.luau` with a spec, shared with
   the guard that reads `CHANGED_FILES` today (`tools/guard test-change`
   shows the pattern). A fork's read-only token makes the comment step
   skip, not fail.
5. **Docs:** `docs/MAC_RUNNER.md` gains "Screenshots on a pull request"
   (the publishing job, the branches, the comment, the baselines) and the
   playthrough section lists the title capture; plan section 4's
   "contact sheet" and "baselines change deliberately" lines point here;
   `docs/tasks/README.md` rows.

6. **Commit status** (the owner's decision, 2026-10-16, added while A
   was in review): the playtest runs on `main` from a dispatch, so GitHub
   never ties it to the pull request's commit; a commit status under the
   context "Studio playtest" does. `playtest-label.yml` sets it `pending`
   on the pull request's head commit right after the dispatch
   ("Asked the Mac to play this pull request", linking the workflow's
   runs, since the run's id is not known yet), with `statuses: write` on
   that job only. The `publish` job sets it `success` or `failure` when the
   run ends, on the commit the place was built from (the one
   `download-place` resolved, not the pull request's head now, so a push
   during the run never gets a status for a place it was not built from),
   with the outcome in a few words and a link to the run, with
   `statuses: write` on that job only. A run of `main`'s place sets none.
   The Mac job gains no permission and no secret. **The status is never a
   required check in the ruleset** (it exists only on labelled pull
   requests, so requiring it would block every other pull request); the
   owner reads it in the merge box. A status is per commit: after a new
   push the pull request shows no result until the owner labels it again.

### B. Mac session (after A is on `main`)

6. **The title capture** in `tools/studio-playtest/playthrough.luau`: on
   each device, after the first Chapter card, the playthrough sends
   `/title` through the Dev shortcut (the chat command as a player types
   it; if the bridge cannot type into chat, through `DevShortcuts`'s
   entry point in the server DataModel, and the doc says which), waits
   for the Title screen as the observe script reports it (the buttons
   built), captures `title`, and presses Continue as a player would (a
   click or tap through the bridge; if the bridge has no pointer input,
   the Title choice through the client's button handler, recorded in the
   doc). The capture list, `report.json` and the contact sheet gain the
   title. A spec drives it through the fake bridge: the title is
   captured once per device and the Story goes on from where it was.
7. **The frame**: the guest's display and Studio's window are set so the
   viewport fills most of the capture (`DISPLAY_SIZE` in
   `tools/mac/vm.sh`; Studio's panels closed or collapsed before Play by
   the bridge; both recorded in the doc), and Roblox's player list is
   hidden in Play by the install script
   (`StarterGui:SetCoreGuiEnabled(PlayerList, false)` in the Play
   DataModel only), so the owner's name panel is not in every frame.
   The device presets' sizes in the report are unchanged; the pixel
   sizes grow and the doc's limits paragraph is rewritten.
8. **Proof**: a full five-device run from the cloud on `main` with the
   title captured; then the owner labels one open visual PR (or a
   throwaway one that moves the title by a few pixels) and the comment
   appears with the sheets and the title's before and after.

## Must not

- Give the Mac job anything beyond `contents: read` and `actions: read`,
  or any secret; the write token lives only in the publishing job on
  GitHub's runners.
- Commit screenshots anywhere but `docs/screens/` (through the Baselines
  PR) and the `playtest/*` branches.
- Let an agent apply `needs-playtest` or approve a `studio` deployment
  (brief mac-001a, decision 3).
- Change a canon Line, the title's words, or the golden file. `/title`
  is Dev only.

## Decisions

- **`/title` over a flag** (the owner, 2026-10-16): one Dev shortcut
  beside `/chapter` and `/quest`, useful to a person testing on Dev too.
- **Per-PR branches in this repository** rather than another repository
  or an external host: no token to manage; force-pushed and deleted on
  close, so the repository does not grow with them.
- **Baselines in `docs/screens/`** as plan section 2.2 says, accepted by
  merging a Baselines PR, never pushed by a job.
- **One comment per PR, updated in place**, so a PR with three playtests
  has one picture of the latest, not three threads.

## Done when

- A pull request the owner labels gets one comment with five contact
  sheets, the title screen on each, within the playtest's run; a changed
  title (as in PR #49) shows its before, after and difference against
  `docs/screens/`.
- `docs/screens/` holds the first baselines, merged through a Baselines
  PR.
- `tools/check.sh` (the `mac-workflows` guard included), `tools/test.sh`
  and `tools/build.sh` are green; zizmor reports nothing new; the Mac
  job's permissions are unchanged.
- The CI prompt comments once on a PR that touches a visual path and
  not on one that does not.
