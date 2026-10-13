# mac-001a — The Mac runner in an isolated virtual machine (amends mac-001)

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

Tier 3 runs on the MacBook **inside a macOS virtual machine** that holds
nothing of the owner's and does not take over the owner's screen, and a
workflow proves it from the cloud. The VM is also the portable form: the
owner intends to move the runner to a dedicated machine later, and a VM
image moves with a copy. If macOS or Studio will not cooperate inside a
VM, that is recorded with evidence and the fallbacks below are built in
order.

## The design

- A **macOS virtual machine** on the Mac through Apple's Virtualization
  framework, managed by [Tart](https://github.com/cirruslabs/tart)
  (scriptable; images are OCI artifacts that `tart push` and `tart pull`
  move between machines), or UTM if Tart will not do. One base image: the
  host's major macOS version, Roblox Studio installed, signed in to the
  separate Roblox account, "Studio as MCP server" enabled, Screen
  Recording approved for the wrapper, the GitHub runner installed and
  registered.
- The GitHub runner runs **inside the VM**, a launchd agent of the VM's
  one user, labels `self-hosted, macOS, studio`. On the host there is
  nothing of the runner's but the image and `tools/mac/vm.sh`.
- The host side is `tools/mac/vm.sh start|stop|status|reset`, run by the
  owner; a launchd agent in the owner's account that only starts the VM
  at login is optional. The VM runs headless if the spike shows a
  headless guest renders; otherwise its window lives on its own Space.
- **No shared folders** between host and guest. The guest reaches the
  network and nothing else of the owner's. A job's exposure is the VM's
  own disk and the Roblox account; `reset` restores the base image, which
  is the wipe between playtest campaigns.
- The separate Roblox account, local files only, no Open Cloud key, and
  the workflow rules in Must 7 are as the decisions below say.

## The spike, first: does Studio run and render inside the VM?

Everything else depends on this, so it is done before any other work.

1. Create the base VM from Tart's published macOS image or an IPSW
   (about 4 cores, 8 GB, 60 GB disk). Inside it: sign in, install Studio,
   enable the MCP server, approve Screen Recording.
2. Run the mac-001 wrapper inside the guest (over `ssh` into it). Pass:
   Studio launches, signs in, opens the place, Plays, and the PNG shows
   the game in Play, not a blank or black frame; checked by eye and
   mechanically (mean luminance of the viewport above a floor). Record
   Studio's reported frame time next to the same run on the host.
3. Repeat headless (`tart run --no-graphics`) and with the owner's screen
   locked. Record each result; neither is assumed to work.
4. Write down what is not known going in, and what was found: whether
   Roblox lets Studio sign in and run inside a VM (the Player's anti-cheat
   refuses VMs; Studio is believed not to carry it), whether the
   paravirtualised GPU renders Studio acceptably, and whether
   `screencapture` works in a headless guest.

**Fallback 1, if the VM fails:** the unprivileged account design in the
appendix, with its own spike (does a switched-out macOS session render?).
**Fallback 2, if that fails too:** the runner in the owner's account,
**not** started at login, started and stopped by hand
(`tools/mac/runner.sh start|stop`) for the length of a playtest session
with the owner present. The isolation is then lost and `docs/MAC_RUNNER.md`
says so plainly.

## Must

1. **`tools/mac/vm.sh`** (host, run by the owner): creates the base image
   from a pinned Tart image or IPSW, with Tart's version and the macOS
   build pinned in the script; `start`, `stop`, `status`, `reset` (back to
   the base); never mounts a host directory into the guest.
2. **`tools/mac/setup.sh`** (guest): installs the pinned runner with its
   SHA-256 checked, registers it with the token from the environment
   (`ACTIONS_RUNNER_INPUT_TOKEN`, so it never appears in `ps`), installs
   the launchd agent. It refuses to run as root. It may keep the *guest*
   awake; it never touches the host, whose power, screen-saver and lock
   settings stay as they are.
3. **`tools/mac/check-repo.sh`**, run by the owner: fails unless fork pull
   requests need approval for all external contributors, and fails if any
   workflow that targets `self-hosted` has a `pull_request` or
   `pull_request_target` trigger.
4. **`tools/studio-playtest/`** as mac-001 Must 3, from the existing
   branch, with its early-query defect fixed. Additions: it fails within
   seconds, with the reason, when the session it runs in cannot render,
   when Studio's MCP server is disabled, and when Studio exits to update.
5. **`.github/workflows/studio-smoke.yml`** as mac-001 Must 4:
   `workflow_dispatch` only, `[self-hosted, studio]`, no
   `continue-on-error`. It downloads the `place` artifact with the job's
   own token, so the guest needs no GitHub login.
6. **Proof before merge.** One commit on the branch adds a `push` trigger
   limited to that branch so the job runs in the VM from the cloud; the
   trigger is removed before review and the run is linked in the PR.
7. **Rules for every job that runs on the Mac**, this smoke and mac-002's
   playtest alike, checked by `check-repo.sh` where a script can:
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
     every job), so the VM is the isolation: `docs/MAC_RUNNER.md` says
     what persists between jobs (the runner's work directory inside the
     guest) and that `reset` wipes it.
8. **`docs/MAC_RUNNER.md`**: how the image was built and pinned, how to
   start, stop and reset it, how to move it to another machine (`tart
   push` and `pull`, or a copy of the VM directory), how to re-register
   and how to remove everything, the spike's results, and the failure
   modes (Studio auto-update inside the image, the host asleep, the VM
   not running after a reboot, a Tart or guest macOS update). It lists
   what a job in the VM **can** still reach: the network and the Roblox
   account signed in to Studio.

## For the owner (cannot be scripted)

- Install Tart from its own Homebrew tap, not the core formulae (which
  have no `tart`): `brew install openai/tools/tart` as its README says
  (the project moved from github.com/cirruslabs to github.com/openai;
  its base images still live at `ghcr.io/cirruslabs/`, for example
  `macos-tahoe-base`). Have about 60 GB free; the base image alone is
  about 25 GB. Homebrew asks you to `brew trust openai/tools` first; the
  tap's provenance was checked in PR #40: Cirrus Labs, Tart's authors,
  joined OpenAI in April 2026, the tap is generated by Tart's own release
  workflow, every formula pins a SHA-256 of a release asset on
  github.com/openai, and Tart's licence is FSL-1.1-ALv2 (free to use;
  becomes Apache 2.0 two years after each release). `softnet`, which the
  formula pulls in, is Tart's isolated-networking helper. The risk to
  record in `docs/MAC_RUNNER.md`: Tart no longer has a dedicated team, so
  UTM stays the named alternative if Tart stops working with a macOS
  update.
- Inside the guest, once: sign Studio in to the separate Roblox account,
  enable "Studio as MCP server", and approve the Screen Recording prompt
  on the wrapper's first run.
- Start the VM when a playtest campaign is wanted, or accept the optional
  login agent; after a host restart, start it again before expecting a
  run.
- Keep "fork pull requests need approval for all external contributors".

## Coordinator's decisions (PR #40)

1. **Sleep and lock on the owner's Mac stay untouched.** Plan section 4
   and section 6 are amended in PR #40, mac-001 is marked superseded, and
   nothing in this brief or in any script changes a host power,
   screen-saver or lock setting. Tier 3 runs when the Mac is awake, which
   was already the plan's position.
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
   starting point.
5. **The VM is the first route** (the owner's choice, 2026-10-13): it is
   the most isolated of the three and the one that moves to a dedicated
   machine later. The unprivileged-account design the brief was first
   written around is fallback 1, kept in the appendix.

## Done when

The spike's result is written down with its evidence, and either: the
coordinator triggers `studio-smoke.yml` from the cloud, it completes
green inside the VM, and the screenshot shows the game viewport; or a
fallback is in place and the same run is green there, with the loss of
isolation written down.

## Appendix: fallback 1, the unprivileged account

The design this brief was first written around, kept for the case where
the VM route fails.

- A **standard (non-admin) macOS account**, `studio-runner`, created by
  the owner, logged in in the background (fast user switching). The
  runner is that account's launchd agent; Studio runs in that account's
  GUI session, signed in to the separate Roblox account. The owner's
  account holds nothing of the runner's; the runner's account holds no
  `gh` login, no SSH key and no Open Cloud key, and its home folder is
  not readable by other accounts.
- **Its spike:** with `studio-runner` logged in and the owner switched
  back to their own session, run the wrapper in the `studio-runner`
  session (over `ssh studio-runner@localhost` or a one-off launchd job).
  Pass: the PNG shows the game in Play. Repeat with the owner's screen
  locked and with the display asleep; record each result.
- `tools/mac/setup.sh` then runs as `studio-runner` and refuses to run as
  an admin user; everything else in Must applies unchanged.
- For the owner: create the account, log in to it once, do the Studio
  sign-in, MCP switch and Screen Recording approval there, and log it in
  again after every restart.
