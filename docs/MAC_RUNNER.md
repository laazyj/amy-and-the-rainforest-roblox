# The Mac runner

Tier 3 needs Roblox Studio, and Studio needs a Mac with a screen. This is
the self-hosted GitHub Actions runner that provides one: how it is
isolated, how it was built, how to run, move and remove it, and what can go
wrong. Brief: [`tasks/mac-001a-isolated-runner.md`](tasks/mac-001a-isolated-runner.md).
Plan background: `docs/DEVELOPMENT_PLAN.md` section 4.

**The runner lives in a macOS virtual machine on the owner's MacBook.**
The runner and Studio are inside the guest. On the host there is the VM's
disk image, [Tart](https://github.com/cirruslabs/tart) and
`tools/mac/vm.sh`, and nothing else of the runner's: no runner process, no
launchd agent, no shared folder, no changed setting. The host's sleep,
screen saver and lock settings are never touched, by script or by hand.

## The pieces

| File | Runs | What it does |
|---|---|---|
| `tools/mac/vm.sh` | on the host, as the owner | Creates the VM from the pinned image; `start`, `stop`, `status`, `exec`, `push`, `seal`, `reset`. Never mounts a host directory into the guest. |
| `tools/mac/setup.sh` | in the guest | `studio` installs Roblox Studio; `runner` installs the pinned runner (SHA-256 checked), registers it and installs its launchd agent. Refuses to run as root, and refuses to run outside a virtual machine. |
| `tools/mac/check-repo.sh` | on the host, as the owner | Fails unless fork pull requests need approval for all external contributors, the `studio` environment allows `main` only, and no workflow with a job on a self-hosted runner starts from a pull request. |
| `tools/lib/mac-workflows.luau` | in tier 0 (`tools/check.sh`), on every PR | The workflow half of that check: a job on anything but a GitHub-hosted runner must use `environment: studio`, declare its own permissions with none beyond `read`, and name no secret, and its workflow may start only from `workflow_dispatch`, `schedule` or a `push` to `main`. A GitHub-hosted job in the same workflow may write (the playtest's `publish`). |
| `tools/studio-playtest/` | in the guest, by the job | The bridge to Studio and what runs on it: `run.luau`, the smoke run (open a place, Play, run a script, capture, quit); `play.luau`, the playthrough (the Story from a fresh Save to the end card per device, a screenshot at every Shot, Chapter card and Scene entry); `fetch-model.luau`, a free Creator Store model saved as `.rbxm`. |
| `.github/workflows/studio-smoke.yml` | started by hand | The proof that the runner and the bridge work, from the cloud. |
| `.github/workflows/studio-playtest.yml` | started by hand, or by the `needs-playtest` label | The tier 3 playthrough of `main`'s place, or of a pull request's CI-built place, on the Mac; then, on GitHub's runners, its contact sheets and baseline comparison (`sheets`) and the pull request's comment (`publish`). See "Screenshots on a pull request". |
| `tools/screens.luau` | on GitHub's runners, by the `sheets` job and `baselines.yml` | The contact sheets and the comparison with `docs/screens/` through ImageMagick; the logic, and the comment, in `tools/lib/screens.luau`. |
| `.github/workflows/playtest-cleanup.yml` | on GitHub's runners, when a pull request closes | Deletes its `playtest/pr-<N>` branch. |
| `.github/workflows/baselines.yml` | started by hand, on GitHub's runners | Opens the "Baselines" pull request from a passing playtest of `main` ([`screens/README.md`](screens/README.md)). |
| `.github/workflows/playtest-label.yml` | on GitHub's runners, when a pull request gets `needs-playtest` | Dispatches `studio-playtest.yml` on `main` with the pull request's number. Never runs on the Mac. |

## The rules for every job on the Mac

The repository is public, so these hold for every workflow that targets
`self-hosted`, now and later (brief mac-001a, Must 7):

- It starts only from `workflow_dispatch`, a push to `main`, or the owner's
  `needs-playtest` label. Never from a plain pull request event.
  Tier 0 and `tools/mac/check-repo.sh` fail on any other trigger,
  `pull_request`, `pull_request_target` and `workflow_call` among them,
  and on a `push` to any branch but `main`. The label needs no exception:
  a label event runs the pull request's own copy of a workflow, so
  `playtest-label.yml` runs on GitHub's runners and only dispatches
  `studio-playtest.yml` on `main` with the pull request's number, and the
  Mac runs `main`'s file on CI's build of the pull request.
- Every Mac job has `environment: studio`, and the `studio` environment
  allows deployments from `main` only (Settings → Environments → studio →
  Deployment branches and tags → Selected branches and tags → `main`; no
  secrets in it). A manual run, or a push, runs the workflow file of its
  own branch, so without this any session with write access could run a
  changed copy of a Mac workflow from its branch; with it, GitHub refuses
  the job before a step runs ("Branch … is not allowed to deploy to
  studio"). Tier 0 requires the environment on every self-hosted job;
  `check-repo.sh` checks the environment's policy.
- The `studio` environment has the owner as its required reviewer, with
  self-review allowed (Settings → Environments → studio → Required
  reviewers; "Prevent self-review" off). Every Mac job waits, before its
  runner is even assigned, until the owner approves it under the run's
  "Review deployments". Why: the playtest runs a pull request's place,
  whose scripts run in Studio in the guest, and nothing else stops
  someone with write access dispatching it for any pull request, nor an
  agent session, which acts with the owner's own GitHub account. The
  approval is the moment the owner has read the diff. Self-review is
  allowed because the owner is the only reviewer: with it prevented,
  GitHub refuses the owner's approval of the runs the owner starts (a
  manual dispatch, the push of a merge to `main`), and they never run.
  It costs a click per job, the smoke run after each merge included. A
  session holding the owner's token can approve through GitHub's API as
  the owner can, so agents never approve a deployment to `studio`, just
  as they never merge (brief mac-001a, decision 3).
- The environment only gates jobs that declare it, and tier 0 runs after
  the fact, so the runner enforces the rule itself: its job-started hook
  (`~/actions-runner-studio/job-started.sh` in the guest, installed by
  `setup.sh runner`) fails any job whose workflow file is not on `main`
  (`GITHUB_WORKFLOW_REF` ending in `@refs/heads/main`) or whose event is
  not `workflow_dispatch`, `push` or `schedule`, before any step runs.
  Tested live with a throwaway branch whose workflow targeted the runner
  without the environment: "this runner runs only workflow files from
  main". The label route above passes it unchanged: the Mac job it
  starts is a `workflow_dispatch` on `main`.
- It checks out the tools from `main` (`ref: main`) and acts on the built
  `place` artifact. It never checks out or runs a pull request's source.
- `permissions: contents: read, actions: read`, no secrets, a
  `timeout-minutes`, and `concurrency: studio` (one Studio, one screen).
  Tier 0 fails a Mac job without its own permissions, with any permission
  beyond `read`, or naming a secret. A write token may live only in a job
  on GitHub's runners that runs nothing from the artifact (the playtest's
  `publish`; see "Screenshots on a pull request").
- Fork pull requests need the owner's approval before any workflow runs
  (Settings → Actions → General → "Require approval for all external
  contributors"). Keep it; `check-repo.sh` checks it.

Run `tools/mac/check-repo.sh` before registering a runner and whenever a
workflow that runs on the Mac changes.

## What a job in the VM can and cannot reach

The runner is not ephemeral: the same guest serves every job, so **the VM
is the isolation**.

| | |
|---|---|
| The owner's files, keychain, browser sessions, SSH and `gh` credentials | **No.** Nothing is shared with the guest; files only enter through `vm.sh push`. |
| The owner's screen | **No.** The VM runs headless; Studio's window exists only inside the guest. |
| The owner's home network | **No**, with the default Softnet networking: the guest reaches the internet and the host's VM gateway only. With `STUDIO_VM_NET=nat` it can reach devices on the local network; `vm.sh` warns. |
| The internet | **Yes**, all of it. A job can download and upload anything. |
| The guest itself | **Everything.** The guest's one user (`admin`, the image's default, password `admin`) has passwordless `sudo`, and System Integrity Protection is off in the image. A job can change or break anything inside the VM. |
| The Roblox account Studio is signed in to | **Yes.** It is a separate account made for the runner (`roblox_ci1234`), with no access to the Dev or Release experience. It must stay that way: never sign the guest's Studio in to the owner's account, and never give that account access to an experience. |
| An Open Cloud key | **No.** There is none in the guest. Studio only opens local place files; saves stay a tier 2 concern. |
| A GitHub token | The job's own short-lived token, read-only, for the length of the job. The guest's `gh` is not logged in. |

**What a pull request's Luau can do inside Studio.** The smoke job plays
the place CI built from `main`, so only merged code runs. The playtest
plays a pull request's place when the owner gives it the
`needs-playtest` label: that place's scripts run in Studio in
the guest with everything in the table above. The place does not enable `HttpService`, and a place file
can enable it for itself, in which case its scripts can make HTTP requests
to the internet from the guest (not to the home network, under Softnet).
That is why the label is the owner's to give after reading the diff.
`playtest-label.yml` dispatches only when the label's sender is the
repository owner (`github.actor`), so another account with write access
labels in vain. The check cannot tell the owner from a session acting with
the owner's own GitHub token, which is how the agent sessions here post
reviews, so agents never apply the label. The gate is the `studio`
environment's required reviewer (see the rules above): however the
playtest was started, it waits for the owner's approval.

**What persists between jobs:** everything in the guest: the runner's
`_work` directory (checkouts, downloaded place files, screenshots), the
cached toolchain, Studio's settings, logs and its Roblox sign-in. `reset`
wipes all of it back to the sealed base.

## How it was built

Done once, on 2026-10-13. The host is an Apple silicon MacBook on macOS
26.6.2.

1. **Tart, on the host** (the owner):
   `brew install openai/tools/tart` (after `brew trust openai/tools`),
   which also installs Softnet. The
   scripts were proven with Tart 2.40.1 and Softnet 0.24.0; `vm.sh` warns
   on another Tart version.
2. **Softnet, once** (the owner; it needs root to filter the guest's
   traffic):

   ```sh
   sudo chown root:wheel "$(brew --prefix)/Cellar/softnet/0.24.0/bin/softnet"
   sudo chmod u+s "$(brew --prefix)/Cellar/softnet/0.24.0/bin/softnet"
   ```

   Without it `vm.sh start` fails with "root privileges are required". A
   Homebrew upgrade of Softnet installs a new binary without the bit, so
   the two commands are run again with the new version's path.
3. **The VM:** `tools/mac/vm.sh create` clones Tart's published macOS
   image, pinned by digest in the script
   (`ghcr.io/cirruslabs/macos-tahoe-base@sha256:87f3aa5c…`, macOS 26.6.2,
   build 25G83), and gives it 4 cores, 8 GB of memory and a 60 GB disk.
   The first pull downloads about 25 GB. The image logs its user in
   automatically, never sleeps, and carries the Tart guest agent that
   `vm.sh exec` talks to, Homebrew, and the GitHub CLI (`gh`) the smoke
   job downloads the place artifact with; it is never logged in, the job
   passes its own token. `setup.sh studio` fails if `gh` is missing.
4. **The repository into the guest:** `tools/mac/vm.sh start`, then
   `git ls-files -z | xargs -0 tools/mac/vm.sh push` copies the tools into
   the guest's `~/incoming`.
5. **Studio:** `tools/mac/vm.sh exec /bin/sh -c 'cd ~/incoming && tools/mac/setup.sh studio'`.
   Roblox publishes only its current build and no checksum, so Studio
   cannot be pinned; the script checks that the download is signed and
   notarised by Roblox Corporation.
6. **By a person, in the VM's window** (`tools/mac/vm.sh stop`, then
   `tools/mac/vm.sh start window`): open Roblox Studio, sign in to the
   runner's Roblox account, and open any place once.
7. **Studio's MCP server:** Assistant → `…` → settings → MCP Servers →
   "Studio as MCP server". In the guest's small window the `…` button did
   nothing, so the switch was set in the file Studio keeps it in, with
   Studio closed: `"mcp-server": {"enabled": true}` in
   `~/Library/Roblox/AssistantSettings/<Roblox user id>.json`.
8. **The runner:** `tools/mac/check-repo.sh`, then, on the host:

   ```sh
   gh api -X POST repos/laazyj/amy-and-the-rainforest-roblox/actions/runners/registration-token --jq .token |
     tools/mac/vm.sh exec /bin/sh -c 'read -r RUNNER_TOKEN; export RUNNER_TOKEN; cd ~/incoming && tools/mac/setup.sh runner'
   ```

   The token travels on standard input and in the environment, never on a
   command line, and is valid for an hour. The runner (2.338.0 at install;
   it updates itself) registers with the labels `self-hosted`, `macOS`,
   `ARM64`, `studio` and runs as a launchd agent of the guest's logged-in
   user, so it starts whenever the VM boots. Two changes to the agent that
   the runner's own `svc.sh` writes: it stays in the desktop session
   (`SessionCreate` off; with it on, the job's session has no window server
   and the wrapper fails with "there is no desktop session here"), and
   launchd restarts it if it exits (`KeepAlive`). It installs the runner's
   job hooks (`job-started.sh`, `job-completed.sh`, named in the runner's
   `.env`): only workflow files from `main` run, and any leftover Studio is
   ended before and after each job. The guest is also told
   not to reopen apps at login, so a Studio left open in the VM's window
   does not come back and idle beside every job's. The script also installs
   the guest's clock job (see "The host sleeps" below), the one step that
   uses the guest's `sudo`.
9. **Screen Recording, by a person:** the first job's capture fails with
   "could not create image from window" and the guest shows "“node” would
   like to record this computer's screen". In the VM's window: System
   Settings → Privacy & Security → Screen & System Audio Recording → turn
   on **node** (the runner's own Node.js,
   `~/actions-runner-studio/externals/node24/bin/node`, which macOS holds
   responsible for every process of a job). A capture through `vm.sh exec`
   needs no approval; only the runner's does. Closing the VM's window
   stops the VM: `tools/mac/vm.sh start` afterwards.
10. **Seal:** `tools/mac/vm.sh stop`, `tools/mac/vm.sh seal` keeps the VM
   as it is then as the base that `reset` restores.

## Day to day (the owner)

```sh
tools/mac/vm.sh start     # boot the VM, headless; the runner comes online in about 30 seconds
tools/mac/vm.sh status
tools/mac/vm.sh stop      # shut it down; the runner goes offline and jobs queue
tools/mac/vm.sh reset     # throw the VM away and restore the sealed base
```

Nothing starts the VM by itself: after the Mac restarts, the runner is
offline until `vm.sh start`. While it runs, the VM holds 4 of the Mac's
cores and up to 8 GB of memory, and uses them only during a job; its disk
image takes about 35 GB under `~/.tart`. `tools/mac/vm.sh start window`
shows the guest's screen, for the rare step that needs a person.

A queued job waits (GitHub keeps it for up to 24 hours) while the VM is
stopped or the Mac sleeps.

## Moving it to another Mac

The VM is a directory, `~/.tart/vms/amy-studio` (and `amy-studio-base`).
With both Macs' VMs stopped, either copy that directory to the same place
on the new Mac, or `tart push amy-studio <registry>/<name>:<tag>` to a
**private** OCI registry and `tart pull` it there: the image holds the
runner's registration and the Roblox sign-in, so it is a secret. On the
new Mac install Tart and Softnet (steps 1 and 2 above) and run
`tools/mac/vm.sh start`. Never run both copies at once: they are the same
runner.

Apple's Virtualization framework ties a macOS guest to Apple silicon; the
new Mac must be one, on a macOS at least as new as the guest's.

## Registering again, and removing everything

Register again (after the runner was removed on GitHub, or to rename it):
in the guest, `cd ~/actions-runner-studio && ./svc.sh stop && ./svc.sh uninstall && rm .runner`,
then step 8 above.

Remove everything:

1. Settings → Actions → Runners → remove the runner, or
   `gh api -X DELETE repos/laazyj/amy-and-the-rainforest-roblox/actions/runners/<id>`.
2. `tools/mac/vm.sh stop`, `tart delete amy-studio`,
   `tart delete amy-studio-base`.
3. `tart prune` frees the cached base image; `brew uninstall tart softnet`
   removes the tools. `~/Library/Logs/amy-studio.log` is the only other
   file on the host.
4. Sign the runner's Roblox account out of all sessions on roblox.com if
   the image may have been copied.

## The wrapper

```sh
lune run tools/studio-playtest/run --file build/AmyAndTheRainforest.rbxl --out build/studio-smoke
```

It drives Studio through Studio's built-in MCP server
(`RobloxStudio.app/Contents/MacOS/StudioMCP`, a stdio proxy Studio
connects to on `localhost:13469`). `smoke.luau` is the sequence, pure and
unit-tested against a fake; `studio.luau` is everything that knows how
Studio is launched, what its tools are called and how its window is
captured; `mcp.luau` is the JSON-RPC client; `bmp.luau` reads the
screenshot's brightness.

`report.json` holds pass or fail and the reason, each step's seconds, the
Studio version and whether it differs from `studio-version.txt`, the
viewport size, the mean frame time over 60 frames of Play, and the mean
luminance of the middle of the screenshot. A run fails when that luminance
is under 0.03: Studio ran and rendered nothing. Only a black viewport is
caught: a light panel over the viewport (Studio's start page, an update
dialog) passes the floor, so read the screenshot when a run looks wrong.
The playthrough also fails a capture that is nearly white there (over
0.85). Every command the bridge runs (`plutil`,
`osascript`, `screencapture`, `sips`) is killed after 30 seconds.

It fails within seconds, with the reason, when:

- there is no desktop session or the session's screen is locked (Studio
  would render nothing);
- Studio's MCP server is not enabled;
- Studio exits while starting, which is what an update does.

A job that times out or is cancelled kills the wrapper but not Studio,
which launchd keeps. The runner's job hooks (below) end any Studio before
and after every job.

Two things about Studio that the wrapper works around:

- Right after a place opens, Studio reports its state and still refuses to
  run Luau ("Target is not reachable"). The wrapper waits until a trivial
  script runs in the Edit DataModel.
- Studio answers a polite quit with "Save changes?" after any Play. The
  wrapper ends the Studio it launched with `kill -9`; the place is a
  throwaway build, and Studio opens the next place without a recovery
  prompt.

It only ever ends the Studio it launched, so it is safe on a Mac where
another Studio is open.

## The playthrough

```sh
lune run tools/studio-playtest/play --file build/AmyAndTheRainforest.rbxl --out build/studio-playtest [--devices pc,phone-portrait]
```

It plays the Story on a real client in Studio, from a fresh Save (Studio
has no DataStores, so every Play is a new player) to the end card, as a
player would. `playthrough.luau` is the sequence, pure and unit-tested
against a scripted fake client:

- **Looking.** At every step a script on the client (`Playthrough.observeScript`)
  reports what is on screen: a Dialogue, a Chapter card and whether it
  has faded in, the Objective, Amy's position, and the Shots framed so
  far, which a recorder installed at the start of Play
  (`INSTALL_SCRIPT`) collects from `FrameShot`. The active Quest is the
  one whose Objective is on screen; its Zone or Character comes from the
  place's own content, so a pull request's Story is played as that pull
  request has it.
- **Acting,** through the input a player has: **E** advances a Dialogue
  and presses a talk prompt (Studio's MCP `user_keyboard_input`), and the
  Player Character walks to a Quest's Zone, or to beside its Character,
  with Studio's MCP `character_navigation`. A card is left to hold and
  fade, and a talk prompt that is not offered yet is waited for.
- **Capturing,** before anything moves on: each Shot once it has eased
  in (0.8 s after it was framed), each Chapter card and the end card once
  faded in, and each Scene the first time Amy stands in one of its Zones
  with nothing over the view. Screenshots are
  `<out>/<device>/<nn>-<shot|card|scene>-<name>.png`. The Title screen is
  the next capture (brief mac-003, Must B6, made on the Mac): after the
  first Chapter card the playthrough sends the Dev shortcut `/title`,
  which offers the Title screen at the current Progress, captures it as
  `<nn>-title-title.png` (kind `title`, which the `sheets` job puts in the
  title index), and presses Continue, which carries on where Amy was.
- **Failing** when the Story stops changing for 60 seconds (Amy moving or
  a Line still being written counts as change), takes over 10 minutes,
  reaches a Quest kind it cannot play (only reach and talk today), or a
  capture is black or nearly white, with what was on screen. A failed
  device is reported and the next one still plays, with two exceptions:
  when the Story does not end on `pc` the rest are skipped (it will not
  end on a phone either), and when Stop Play fails the rest are skipped
  (they would play in a session still in Play).
- **Checking the device.** After setting the simulator the bridge reads
  it back (`Studio.deviceScript`), and a device, orientation or scaling
  that did not take fails that device before Play; with no device active
  Studio names the device `"default"`. Once playing, the client's viewport
  must match the simulated device's size in points (within 2% on its
  short side). At the end the simulator is stopped again, and the smoke
  run checks no device is simulated before it plays.
- **Within the job's time.** The run has a 45-minute budget, Studio's
  start included, inside the job's 60 minutes: no device starts with
  under 7 minutes of it left (those are reported as skipped), and a
  device's 10 minutes shrink to what is left less a 3-minute teardown
  reserve, for the step in progress, Stop Play and stopping the simulator
  when Studio is slow. A report that cannot be written is logged and the
  run still stops Play and quits Studio. `report.json` is written
  after every device with `"finished": false`, so a job cut short still
  uploads what it played, and the summary says it stopped before the end.

The devices, one Play each, in order: `pc` (no simulation),
`phone-landscape` and `phone-portrait` (Studio's `iphone_16` preset, 852
x 393 units, the 6-inch phone of `feel.md`), `tablet-landscape` and
`tablet-portrait` (`ipad_10th_generation`, 1180 x 820). `report.json`
holds, per device, pass, fail or skipped, the seconds, what the simulator
reported (preset, orientation, scaling, size), the viewport and
orientation the client actually played in, any warning (portrait played
as landscape), each Quest as it became active and each capture with its
luminance and pixel size; and the Studio version against
`studio-version.txt`. The job summary shows the same, warnings included.

Run in the VM on 2026-10-15 (Studio 0.743.0.7431133), the place built from
`main` at 3debd6b plus this branch: every device passed, 13 Quests and 22
screenshots each, 936 s in all. After the review's fixes (the device read
back and checked, the budget), `pc`, `phone-portrait` and
`tablet-landscape` passed again in 521 s, 170 s each.

| Device | Seconds | The client played at |
|---|---|---|
| `pc` | 231 | 541 x 414 (Studio's viewport) |
| `phone-landscape` | 189 | 733 x 392, landscape |
| `phone-portrait` | 168 | 733 x 392, landscape (see "Device emulation") |
| `tablet-landscape` | 169 | 1178 x 819, landscape |
| `tablet-portrait` | 170 | 1178 x 819, landscape |

Studio updated itself in the guest overnight, from 0.742.0.7421053 to
0.743.0.7431133, between two runs: the first launch after it failed at
once with "Studio exited while starting", the installer took about 15
minutes in the guest, and the bridge then passed unchanged, so
`studio-version.txt` moved to 0.743.0.7431133 and the VM was sealed again.

Limits today:

- Studio's window in the guest is about 1024 x 680 points with its panels
  open, so the game's viewport is about half of each screenshot (on a
  simulated device, smaller again). A larger guest display, or the panels
  closed, is the next improvement.
- Roblox's own player name panel (`roblox_ci1234`) sits in the top right of
  the viewport in every frame.
- Level 1 assertions (plan section 4: text fits, safe areas, the camera
  rule) are not part of it yet (the baseline diffs are: "Screenshots on a
  pull request");
  `tests/studio/CameraRule.client.luau` and `DeviceLayout.client.luau` are
  the assertions to run inside it next.
- A Shot is captured 0.8 s after it was framed, not when the camera has
  settled, so a Shot queued behind another in the same step, or one that
  eases for longer, can be captured early, without failing. The recorder
  could log when the camera settles a Shot and the capture wait on that.
- A Chapter card shows for 2.4 s and a capture or a walk can cover it;
  nothing checks every Chapter's card was taken. A Scene entry is Amy
  standing in one of the Scene's Zones, so a Scene without Zones (Village,
  Paradise) is never captured. A count against the Story's Chapters and a
  signal from the Scene change itself would close both.
- Phone runs press E like a PC, so touch input is not exercised yet.

## Screenshots on a pull request

Brief mac-003. A playtest's Captures go where they are reviewed: one
comment on the pull request, with a **Contact sheet** per device and, for
every Capture that differs from its **Baseline** in `docs/screens/`, the
before, the after and the difference. The Mac keeps its read-only token.

**When.** On the owner's `needs-playtest` label (`playtest-label.yml`
dispatches `studio-playtest.yml` on `main` with the pull request's
number), or by hand. CI prompts for it: a pull request that changes a path
in `tools/lib/visual-paths.luau` (`src/client/`, `ScreenLayout.luau`,
`palette.luau`, `title.luau`, `hints.luau`, `feel.md`, `assets/images/`)
gets one comment from CI's `screen-prompt` job, updated in place: "This
pull request changes what is on screen. The owner's `needs-playtest` label
brings screenshots here." CI's own job finds the paths and holds no write
token; `screen-prompt` runs only `.github/actions/post-comment`, which
posts the comment or updates the one found by its first line, as
`publish` does. A fork's pull
request is skipped: its token cannot comment, and it is never played.

**The three jobs of `studio-playtest.yml`.**

| Job | Runs on | Token | Does |
|---|---|---|---|
| `playtest` | the Mac | `contents: read`, `actions: read` | Plays the place, uploads the `studio-playtest` artifact (`report.json` and the Captures) and gives its id and link as outputs. Its permissions are as before mac-003. |
| `sheets` | GitHub's runners | `contents: read` | Whenever the artifact was uploaded, whatever the playtest's result: `lune run tools/screens sheets` on the artifact and `main`'s `docs/screens/`. Makes `sheets/<device>.png` (ImageMagick `montage`, each Capture labelled with its name), `sheets/title.png` (the Title screen's Capture across devices), and, for each Capture that differs from its Baseline, `before/` and `diff/` (ImageMagick `compare`), and writes the comment. Uploads them as `studio-playtest-screens`. |
| `publish` | GitHub's runners | `contents: write`, `pull-requests: write` | Runs nothing from the artifact, and of this repository only `main`'s `.github/actions/post-comment`: commits the images as one commit with no parent, force-pushes it to the branch `sheets` named, `playtest/pr-<N>` (`playtest/main` for a run of `main`), and posts the comment on pull request N, or updates the one already there (found by the marker `<!-- studio-playtest-screens -->`). A run of `main` writes the comment to its job summary instead. |

The artifact holds what a pull request's place did in Studio, so it is
read only where there is no write token, and nothing in it is trusted: a
Capture whose file name is not `<device>/<nn>-<kind>-<name>.png` in lower
case is left out and listed, and every text from `report.json` (warnings,
failures, the Studio version) is shown in a code span, where Markdown,
HTML and mentions do nothing.

**The comment** has the playtest's result and time, the Studio version
against the pin, a table of each device's Captures, changed, new and
Baselines no Capture matched, the device warnings and failures, the title
index, each device's Contact sheet, a row of before, after and difference
for each changed Capture (at most 30; the rest are in the artifact), and
links to the run and the artifact. Its images are raw file links into the
`playtest/pr-<N>` branch, under a folder per run (`run-<id>/`), so a new
run's images are never an old one's from a cache. The branch is
force-pushed as one commit, so it never grows, and
`playtest-cleanup.yml` deletes it when the pull request closes; the
comment's images go with it.

**Changed** means more than 1% of the Capture's pixels moved by more than
10% (ImageMagick's `-fuzz`), or its size changed. Plan section 4 asks for
a structural-similarity measure; ImageMagick 6 on `ubuntu-latest` has
none, so this stands in until the tolerance is tuned per Capture. A
Capture is paired with the Baseline of the same device, kind and name, the
number ignored, so a Capture added early does not unpair the rest.

**Baselines** change only through a "Baselines" pull request, which
`baselines.yml` opens from a passing playtest of `main` that played every
device; the owner accepts them by merging it
([`screens/README.md`](screens/README.md)). Until the first one merges,
every Capture shows as new.

What only a real run proves (brief mac-003, Must B8): that
`raw.githubusercontent.com` serves the branch's images inline in the
comment, that the job token may push `playtest/*` (a branch ruleset that
covers `playtest/*` would refuse it), and the comparison's noise on real
Captures.

## Device emulation: scripted (spike, mac-002)

**Decided: Studio's device simulator can be switched from a script.** The
MCP server's `execute_luau` reaches `StudioDeviceSimulatorService` in the
Edit DataModel: `GetDeviceListAsync` lists Studio's presets (phones such
as `iphone_16`, tablets such as `ipad_10th_generation`), `SetDeviceAsync`
and `SetOrientationAsync` choose one, and `StopSimulationAsync` returns to
a PC. Set before Play, the client starts as that device: on `iphone_16`
it reported touch input and Studio's device frame showed in the capture.
The bridge sets the scaling mode to `FitToWindow`: at Studio's default,
`ScaleToPhysicalSize`, a tablet is larger than the guest's viewport and
only part of its screen is captured.
The setting can only change in Edit ("Edit datamodel is not available in
Play mode"), so each device and orientation is its own Play. The older
`StudioDeviceEmulatorService` is not reachable from the MCP server.

**Portrait does not play today, because the game holds itself to
landscape.** The place's `StarterGui.ScreenOrientation` is Roblox's
default, `LandscapeSensor`, and the simulator honours it as a real phone
would: asked for a portrait `iphone_16`, the client plays
`LandscapeRight`. So the `phone-portrait` and `tablet-portrait` runs play
landscape, and `report.json` records each device's actual viewport and
orientation, with a warning when portrait was asked for. `feel.md` says
the phone and tablet work in portrait too; making the game allow it
(`StarterGui.ScreenOrientation` set to `Sensor`) is a game change for a
later brief, after which these runs test portrait with no change here.

So no AppleScript window resizing is needed, and DPI-dependent checks can
use the simulated device's own units: the simulator emulates the device's
resolution and density, and `feel.md`'s physical sizes apply to it as
written. The real phone and tablet check (release checklist) still
confirms them.

## Fetching Creator Store models: Studio wins (spike, mac-002)

There is no Open Cloud endpoint to download a Creator Store model (plan
section 5.5). Both paths were tried on 2026-10-14 with the same free model,
"Low Poly Tree" (asset 12549617200, by Remadex Development):

- **(a) Luau Execution:** a task calling `InsertService:LoadAsset` in CI's
  engine-tests job (with the Dev key; draft PR #50's temporary test)
  failed with "User is not authorized to access Asset". A game server may
  load only assets its owner owns, so this path cannot fetch other
  creators' free models.
- **(b) Studio on the Mac:** the MCP server's `insert_asset` inserted it in
  about a second, `SerializationService:SerializeInstancesAsync` turned it
  into a 14,562-byte binary `.rbxm`, and Lune reads the file back. **This
  is the path.**

```sh
lune run tools/studio-playtest/fetch-model --asset 12549617200 --name prop:low_poly_tree --out assets/meshes/low-poly-tree.rbxm
```

`fetch-model.luau` runs on the Mac (in the guest, or on any Mac with Studio
signed in and its MCP server enabled). It refuses a model that is not free
(off sale counts as not free) or that carries any script, the model's own
root included (free models' scripts are the usual way malware reaches a
game; anything that `IsA("LuaSourceContainer")` counts), saves the
`.rbxm` and prints the manifest entry (`docs/ASSETS.md`). The model's
name is its creator's choice, so it never becomes Luau: the tool inserts
into a folder in ServerStorage that it names itself, and its scripts find
the model as that folder's one child. Fetching the tree again this way on
2026-10-15 gave the same parts and size as the committed file. The `.rbxm` holds the parts; a MeshPart's mesh stays on
Roblox under the creator's asset id (the tree references 12545269850 and
12545267056), so the model works in any game but its meshes are not ours
to re-upload. `prop:low_poly_tree` is in the manifest from this spike and
not yet used by the game.

## The spike: does Studio run and render inside the VM?

Yes. Run on 2026-10-13: host MacBook (M1 Max, macOS 26.6.2), guest macOS
26.6.2 with 4 cores and 8 GB, Studio 0.742.0.7421053 on both, the place
built from this branch.

| Run | Result | Duration | Frame time | Luminance |
|---|---|---|---|---|
| Guest, VM window open, first Play after install | pass | 47.5 s (Start Play 37.6 s) | not measured | 0.40 |
| Guest, headless (`tart run --no-graphics`) | pass | 18.7 s | 16.7 ms | 0.447 |
| Guest, headless, again | pass | 14.2 s | 16.7 ms | 0.448 |
| Host, in the owner's session | pass | 13.4 s | 16.7 ms | 0.396 |
| Guest, headless, the owner's screen locked for the whole run | pass | 17.8 s | 16.7 ms | 0.449 |
| From the cloud, `studio-smoke.yml` on the runner ([run](https://github.com/laazyj/amy-and-the-rainforest-roblox/actions/runs/38579335725)), place from CI on `main` | pass | 16.0 s | 16.7 ms | 0.386 |
| The same, after `vm.sh seal` and `vm.sh reset` | pass | 18.2 s | 16.7 ms | 0.387 |

`seal` and `reset` each take under a second (APFS clones), and the reset
guest kept the runner's registration, Studio's sign-in and the Screen
Recording approval. Every screenshot shows the game in Play: the Scene, the Characters, the
Objective and the first Line. Frame time is 16.7 ms in the guest and on
the host, which is the 60 frames a second both displays refresh at, so it
shows that the guest keeps up with this place and not how much headroom
either has.

What was not known going in, and what was found:

- **Does Roblox let Studio sign in and run in a VM?** Yes. Sign-in through
  the guest's browser worked and Studio played the place. Nothing refused
  the virtual machine.
- **Does the paravirtualised GPU render Studio?** Yes, at the display's
  refresh rate for this place. The first Play after installing took 38
  seconds (shaders compile once); later ones 3 to 4.
- **Does `screencapture` work in a headless guest?** Yes. With
  `--no-graphics` the guest still has a display and a logged-in desktop
  session; only the host shows no window. The runner needs Screen Recording
  approved once (step 9).
- **Does the guest keep rendering while the owner's screen is locked?**
  Yes: same frame time and the same picture as with it unlocked.
- **Does the guest run while the host sleeps?** No. The VM freezes with
  the host and carries on when it wakes; a run in progress stalls for the
  length of the sleep.

So the VM is the route, and neither fallback of the brief (an unprivileged
account; the runner in the owner's account) was built.

## The host sleeps

The VM freezes while the Mac sleeps and its clock stops with it, so on
wake the guest's clock is behind by the length of the sleep. On 2026-10-13
that was an hour, and GitHub refused the runner's signed token as expired
("The token expired on … Current server time is …"); the runner reported
this as "The runner registration has been deleted from the server" and
stopped for good. The registration had not been deleted.

Two guards, both in the guest, installed by `setup.sh runner`:

- a launchd daemon, `local.amy-studio.clock`, sets the guest's clock from
  `time.apple.com` every minute (nothing in the guest can tell it was frozen, so it is a plain interval);
- launchd restarts the runner whenever it exits.

They have not yet been through a real overnight sleep; if the runner is
offline after one, look for "token expired" in the newest
`~/actions-runner-studio/_diag/Runner_*.log` in the guest, and restart the
runner with `tools/mac/vm.sh stop && tools/mac/vm.sh start` rather than
registering it again.

GitHub removes a self-hosted runner that has not connected for 14 days.
Start the VM at least once a fortnight, or register it again (above) after
a longer gap. A job started while the runner is offline waits in the queue
for up to 24 hours, then fails.

Do not use `tart suspend`: resuming a suspended VM with Softnet failed
("The virtual machine failed to restore with error “invalid argument”"),
and the snapshot had to be discarded and the VM booted cold.

## Failure modes

| What happens | What you see | What to do |
|---|---|---|
| Studio updates itself in the guest | The wrapper fails with "Studio exited while starting", or passes with a version drift warning | Run the job again: the second launch is the new Studio. If it passes, bump `tools/studio-playtest/studio-version.txt`; if the bridge broke, fix `studio.luau`. Then `stop` and `seal` so `reset` does not bring the old Studio back. |
| The host is asleep, or the VM is not running after a restart | The job stays queued | Wake the Mac; `tools/mac/vm.sh start`. |
| Studio's sign-in has expired | "Studio did not open the place: no new Studio connected to the MCP server; is Studio signed in?" after 90 seconds | `vm.sh stop`, `vm.sh start window`, sign in again, `stop`, `seal`. |
| Studio's MCP server is switched off | "Studio's MCP server is not enabled" at once | Step 7 above. |
| The guest has no way out | `vm.sh start` warns "cannot reach GitHub; restarting it" | Nothing: `start` boots the VM a second time, which has always cured it. About one boot in four under Softnet came up with an address and gateway but no traffic getting through (cause not found). If both boots fail, `start` says so; try again, or `STUDIO_VM_NET=nat` to tell Softnet apart from the network. |
| The runner is offline although the VM runs | `vm.sh status` says running; GitHub shows the runner offline | `tools/mac/vm.sh stop && tools/mac/vm.sh start`. |
| Studio cannot capture | "could not create image from window" | Step 9: Screen Recording for `node`. A runner update that replaces its Node.js may ask again. |
| A future macOS drops `/usr/bin/perl` (Apple has called it deprecated since 10.15) | Every bridge command fails at once with "/usr/bin/perl" in the error | The wrapper's 30-second command timeout is a few lines of Perl (`TIMEOUT_SCRIPT` in `studio.luau`); install Perl in the guest or rewrite that wrapper. |
| A job is refused at "Set up job" | "this runner runs only workflow files from main" or "does not run jobs started by …" | Intended: the workflow ran from a branch or an event the Mac does not take. Run it from `main`. |
| A job left the guest in a bad state | Anything | `tools/mac/vm.sh reset`. |
| Tart is updated by Homebrew | `vm.sh` warns that the version differs | If the VM still starts and the smoke job passes, bump `TART_VERSION` in `vm.sh`. |
| Softnet is updated by Homebrew | `vm.sh start` fails with "root privileges are required" | Step 2 above, with the new path. |
| The guest's macOS offers an update | Nothing by itself | Leave it. To move to a newer macOS, pin a newer image in `vm.sh` and build the VM again. |

## Risks that stay

- **Tart's maintenance.** Tart's authors, Cirrus Labs, joined OpenAI in
  April 2026; Tart moved to github.com/openai and its own Homebrew tap
  (`openai/tools`, whose provenance was checked in PR #40), and no longer
  has a dedicated team. Its licence is FSL-1.1-ALv2: free to use, Apache
  2.0 two years after each release. If it stops working with a future
  macOS, [UTM](https://mac.getutm.app) drives
  the same Apple Virtualization framework: the guest would be rebuilt
  there with `setup.sh`, and `vm.sh` rewritten around `utmctl`.
- **The image is someone else's.** The guest's macOS comes from Cirrus
  Labs' published image, pinned by digest, with their choices in it
  (automatic login, `admin`/`admin`, passwordless `sudo`, SIP off, Remote
  Login on). Under Softnet the guest is reachable only from the host.
- **Studio cannot be pinned** and updates itself on launch; see the first
  failure mode.
