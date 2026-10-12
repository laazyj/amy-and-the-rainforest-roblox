# mac-001a — The Mac runner under an unprivileged account (amends mac-001)

**Kind:** environment and one spike. Run on the MacBook. **Proposed by the
mac-001 session with the owner; accepted by the coordinator in PR #40, whose
decisions are at the end.** Nothing in it is built yet.

## Why this brief exists

mac-001 was written as if the MacBook were a dedicated machine. It is the
owner's own laptop, used for many other things. Half way through mac-001
the owner stopped the session, and three facts changed the brief:

1. **A runner installed as mac-001 says runs as the owner.** A job on it
   can read the owner's files, SSH keys, `gh` login and anything the
   keychain releases without a prompt. The repository is public.
2. **Studio takes over the owner's screen.** Every run opens a Studio
   window in front of the owner's work and takes keyboard focus for 15 to
   20 seconds.
3. **mac-001 Must 1 asks for sleep and screen lock to be disabled on
   power.** On a personal laptop that is a security cost the owner does
   not accept.

The owner's decisions, which this brief treats as constraints:

- The runner does **not** run as the owner's account.
- **No sleep, screen saver or screen lock setting is changed**, by a
  script or by hand. Tier 3 runs when the Mac is awake; that is already
  the plan's position ("Mac runner is often off", section 7).
- The session asks before it launches Studio in the owner's session.

## What mac-001 established (carry it forward)

All of this was observed on macOS 26.6.2, Apple silicon, Studio
0.742.0.7421053. The working code is on the mac-001 session's local
branch `mac-001-runner-bootstrap`, not pushed: the wrapper passed end to
end three times in the owner's session, in 13 to 17 seconds, with a
screenshot of the game in Play.

| Question | Answer |
|---|---|
| Where is Studio's MCP server? | A stdio proxy inside the app: `RobloxStudio.app/Contents/MacOS/StudioMCP`. It hosts a WebSocket on `localhost:13469`; each Studio connects to it, retrying every 3 seconds |
| How is it enabled? | A switch in Studio's Assistant settings ("Studio as MCP server"). It is stored per Roblox user in `~/Library/Roblox/AssistantSettings/<userId>.json` as `"mcp-server": {"enabled": true}`. No script enables it |
| Which tools does tier 3 need? | `list_roblox_studios`, `get_studio_state`, `start_stop_play`, `execute_luau` (Edit, Client or Server DataModel), `get_console_output`. There is **no** tool that opens a place file |
| How is a `.rbxl` opened? | By running the binary directly: `Contents/MacOS/RobloxStudio -task EditFile -localPlaceFile <path>`. `open file.rbxl` goes through a launcher that lands on Studio's start page ("Place is not open") |
| How is our Studio told apart from another? | Its id is the one `list_roblox_studios` did not list before the launch; a local file's instance has a `null` name at first. Confirmed by `game.Name` in Edit, which is the file name |
| What is the place called during Play? | `Game`. The file name is only visible in Edit |
| How is the frame captured? | `screencapture -x -o -l <window id>`, the window id found by process id through CoreGraphics (`osascript -l JavaScript`). It captures the Studio window only, never the rest of the screen, which matters because artifacts of a public repository are public |
| How does Studio quit? | Only by `kill -9`. After Play it answers a polite quit, and `SIGTERM`, with a "Save changes?" dialog that nothing unattended can dismiss. A killed Studio left no prompt on the next launch |
| Does Studio update itself? | Yes: an open Studio restarted itself for an update during the session. The wrapper is written to fail fast when the Studio it launched exits while starting; that path has not been seen happen |
| Can `studio-smoke.yml` be proven before it is merged? | No. `workflow_dispatch` needs the workflow on `main`. See Must 6 |

One repository setting was changed, with the owner's approval: fork pull
requests now need approval for **all** external contributors (it was
first-time contributors only). A self-hosted runner on a public
repository must keep it that way.

## Goal

Tier 3 runs on the MacBook in a macOS account that has no access to the
owner's data and does not appear on the owner's screen, and a workflow
proves it from the cloud. Or, if macOS will not render for such an
account, that is recorded with evidence and the fallback below is in
place.

## The design

- A **standard (non-admin) macOS account**, `studio-runner`, created by
  the owner. It stays logged in in the background (fast user switching).
- The GitHub runner is that account's launchd **agent**, labels
  `self-hosted, macOS, studio`. Studio runs in that account's GUI session.
- Studio there is logged in to a **separate Roblox account** with no
  access to the Dev or Release experiences. The smoke run plays a local
  file, which needs a login and nothing else.
- The owner's account holds nothing of the runner's, and the runner's
  account holds no `gh` login, no SSH key and no Open Cloud key.

## The spike, first: does a background session render?

Everything else depends on this, so it is done before any other work.

1. With `studio-runner` logged in and the owner switched back to their own
   session, run the mac-001 wrapper in the `studio-runner` session (over
   `ssh studio-runner@localhost` or a one-off launchd job; the session
   says which worked).
2. Pass: the PNG shows the game in Play, not a black or blank frame.
   The session looks at the image and also checks it mechanically (mean
   luminance of the viewport above a floor).
3. Repeat with the owner's screen **locked**, and with the display asleep.
   Record each result; a locked owner screen must not be assumed to work.
4. Record the frame time Studio reports in the background session next to
   the same figure in the foreground, since mac-002 and brief 016 will
   measure performance there.

**If it fails:** stop and write the evidence into `docs/MAC_RUNNER.md`.
Then try one more isolated route before giving isolation up: a macOS
virtual machine on the Mac (Apple's Virtualization framework through Tart
or UTM) with its own display, the runner and Studio inside it, the image
kept outside the owner's account. Whether Studio renders and signs in
inside a VM is not known to us; spend at most one session on it and
record the result either way. If it works it is the better design:
disposable per run, no screen takeover, nothing of the owner's reachable,
at the cost of a VM image to keep current with Studio's updates.

**If that fails too,** build the fallback: the runner in the owner's
account, **not** started at login, started and stopped by hand
(`tools/mac/runner.sh start|stop`) for the length of a playtest session
with the owner present. The isolation is then lost and the document says
so plainly.

## Must

1. **`tools/mac/setup.sh`**, run as `studio-runner`: installs the pinned
   runner with its SHA-256 checked, registers it with the token from the
   environment (`ACTIONS_RUNNER_INPUT_TOKEN`, so it never appears in
   `ps`), installs the launchd agent. It refuses to run as an admin user
   or as root, and it changes no power, screen saver or lock setting.
2. **`tools/mac/check-repo.sh`**, run by the owner: fails unless fork pull
   requests need approval for all external contributors. The runner
   account cannot make this check, having no admin token.
3. **`tools/studio-playtest/`** as mac-001 Must 3, from the existing
   branch. Additions: it fails within seconds, with the reason, when the
   session it runs in cannot render (locked or no window server), when
   Studio's MCP server is disabled, and when Studio exits to update.
4. **`.github/workflows/studio-smoke.yml`** as mac-001 Must 4:
   `workflow_dispatch` only, `[self-hosted, studio]`, no
   `continue-on-error`. It downloads the `place` artifact with the job's
   own token, so the runner account needs no GitHub login.
5. **`docs/MAC_RUNNER.md`**: the account and how to recreate it, what was
   installed and where, how to re-register and how to remove everything,
   the spike's results, and the failure modes (Studio auto-update, screen
   locked, MCP disabled, account not logged in after a reboot, Mac asleep).
   It lists what a job on this runner **can** still reach: the network,
   world-readable files, and the Roblox account logged in to Studio.
6. **Proof before merge.** One commit on the branch adds a `push` trigger
   limited to that branch so the job runs on the Mac from the cloud; the
   trigger is removed before review and the run is linked in the PR.
7. **Rules for every job that runs on the Mac**, this smoke and mac-002's
   playtest alike, checked by `tools/mac/check-repo.sh` where a script can:
   - it starts only from `workflow_dispatch`, a push to `main` or the
     `needs-playtest` label; no workflow that targets `self-hosted` has a
     `pull_request` or `pull_request_target` trigger that checks out a
     pull request's code;
   - it checks out the tools from `main` (`ref: main`) and acts on the
     built `place` artifact, never on a pull request's source; what a
     pull request can reach on the Mac is therefore what its Luau can do
     inside Studio, and `docs/MAC_RUNNER.md` says what that is;
   - `permissions: contents: read, actions: read`, no secrets, no Open
     Cloud key, a `timeout-minutes`, and `concurrency: studio` so one
     Studio runs at a time;
   - the runner is not ephemeral (re-registering needs a fresh token for
     every job), so the account is the isolation: `docs/MAC_RUNNER.md`
     says what persists between jobs (the work directory) and how to wipe
     it.

## For the owner (cannot be scripted)

- Create the standard account `studio-runner`; log in to it once.
- In it: sign Studio in to the separate Roblox account, enable "Studio as
  MCP server", and approve the Screen Recording prompt on the first run
  (macOS asks for an admin password).
- After a restart, log `studio-runner` in again before expecting a run.
- Confirm the home folder is not readable by other accounts (it is `750`
  today, which is right).

## Coordinator's decisions (PR #40)

1. **Sleep and lock stay untouched.** Plan section 4 and section 6 are
   amended in PR #40, mac-001 is marked superseded, and nothing in this
   brief or in any script changes a power, screen-saver or lock setting.
   Tier 3 runs when the Mac is awake, which was already the plan's
   position.
2. **A separate Roblox account** with no access to Dev or Release. Tier 3
   plays local files only; saves stay tier 2's job (Luau Execution on Dev
   under the test prefix). The plan's "Studio DataStore access on Dev" is
   for the owner's own playtests in the owner's account and now says so.
   mac-002's Creator Store insertion uses the runner's account too.
3. **No per-run approval gate.** Isolation comes from structure, not a
   click: Must 7. Every way a Mac job can start is already the owner's or
   the coordinator's doing, fork workflow runs need approval for all
   outside collaborators, and a job never runs pull-request code. If a
   second gate is ever wanted, a `studio` environment with the owner as
   required reviewer can be added without changing the jobs.
4. **This brief replaces mac-001.** mac-001 stays in the repository marked
   superseded; its row is gone from the table; mac-002 follows mac-001a.
   The working code on the local branch `mac-001-runner-bootstrap` (the
   wrapper and its tests, `tools/mac/setup.sh`, `studio-smoke.yml`) is the
   starting point, with its known early-query defect fixed first.

## Done when

The spike's result is written down with its evidence, and either: the
coordinator triggers `studio-smoke.yml` from the cloud, it completes
green on the `studio-runner` account (or inside the VM), and the
screenshot shows the game viewport; or the fallback is in place and the
same run is green with the runner started by hand.
