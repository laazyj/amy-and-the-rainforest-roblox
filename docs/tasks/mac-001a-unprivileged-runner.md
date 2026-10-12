# mac-001a — The Mac runner under an unprivileged account (amends mac-001)

**Kind:** environment and one spike. Run on the MacBook. **Proposed by the
mac-001 session with the owner; awaiting the coordinator's feedback.**
Nothing in it is built yet.

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

**If it fails:** stop, write the evidence into `docs/MAC_RUNNER.md`, and
build the fallback instead: the runner in the owner's account, **not**
started at login, started and stopped by hand
(`tools/mac/runner.sh start|stop`) for the length of a playtest session.
The isolation is then lost and the document says so plainly.

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

## For the owner (cannot be scripted)

- Create the standard account `studio-runner`; log in to it once.
- In it: sign Studio in to the separate Roblox account, enable "Studio as
  MCP server", and approve the Screen Recording prompt on the first run
  (macOS asks for an admin password).
- After a restart, log `studio-runner` in again before expecting a run.
- Confirm the home folder is not readable by other accounts (it is `750`
  today, which is right).

## Questions for the coordinator

1. **mac-001's sleep and lock requirement is dropped.** Plan section 4
   ("with screen lock and sleep disabled while on power") and mac-001
   Must 1 need amending to match. Should this brief do it, or will you?
2. **Which Roblox account does tier 3 use?** A throwaway account is enough
   for the smoke. mac-002 item 3 (insert a Creator Store model) probably
   works with any account. The plan's "Studio DataStore access enabled on
   the Dev experience so Mac playtests can exercise it" (section 6) needs
   an account with edit access to Dev, which gives a job on a public
   repository's runner a route to the Dev experience. Proposal: tier 3
   plays local files only and saves stay tier 2's job.
3. **Should each run need the owner's approval?** A GitHub environment
   `studio` with the owner as required reviewer would make every job on
   the Mac wait for a click. It costs autonomy for perceptual briefs
   (011, 012, 014, 016), which expect to run the Mac unattended.
4. **Does this replace mac-001 or follow it?** Proposal: mac-001 closes as
   superseded, one PR delivers this brief, and its status row replaces
   mac-001's.

## Done when

The spike's result is written down with its evidence, and either: the
coordinator triggers `studio-smoke.yml` from the cloud, it completes
green on the `studio-runner` account, and the screenshot shows the game
viewport; or the fallback is in place and the same run is green with the
runner started by hand.
