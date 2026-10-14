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
| `tools/lib/mac-workflows.luau` | in tier 0 (`tools/check.sh`), on every PR | The workflow half of that check: a job on anything but a GitHub-hosted runner must use `environment: studio`, and its workflow may start only from `workflow_dispatch`, `schedule` or a `push` to `main`. |
| `tools/studio-playtest/` | in the guest, by the job | The wrapper: opens a place file in Studio, starts Play, runs a script, captures the Studio window, stops Play, quits Studio, writes `viewport.png` and `report.json`. |
| `.github/workflows/studio-smoke.yml` | started by hand | The proof that all of the above works from the cloud. |

## The rules for every job on the Mac

The repository is public, so these hold for every workflow that targets
`self-hosted`, now and later (brief mac-001a, Must 7):

- It starts only from `workflow_dispatch`, a push to `main`, or the owner's
  `needs-playtest` label. Never from a plain pull request event.
  Tier 0 and `tools/mac/check-repo.sh` fail on any other trigger,
  `pull_request`, `pull_request_target` and `workflow_call` among them,
  and on a `push` to any branch but `main`; the label trigger will need
  the rule widened, deliberately, in mac-002.
- Every Mac job has `environment: studio`, and the `studio` environment
  allows deployments from `main` only (Settings → Environments → studio →
  Deployment branches and tags → Selected branches and tags → `main`; no
  secrets in it). A manual run, or a push, runs the workflow file of its
  own branch, so without this any session with write access could run a
  changed copy of a Mac workflow from its branch; with it, GitHub refuses
  the job before a step runs ("Branch … is not allowed to deploy to
  studio"). Tier 0 requires the environment on every self-hosted job;
  `check-repo.sh` checks the environment's policy.
- The environment only gates jobs that declare it, and tier 0 runs after
  the fact, so the runner enforces the rule itself: its job-started hook
  (`~/actions-runner-studio/job-started.sh` in the guest, installed by
  `setup.sh runner`) fails any job whose workflow file is not on `main`
  (`GITHUB_WORKFLOW_REF` ending in `@refs/heads/main`) or whose event is
  not `workflow_dispatch`, `push` or `schedule`, before any step runs.
  Tested live with a throwaway branch whose workflow targeted the runner
  without the environment: "this runner runs only workflow files from
  main". mac-002's label trigger needs this hook widened too.
- It checks out the tools from `main` (`ref: main`) and acts on the built
  `place` artifact. It never checks out or runs a pull request's source.
- `permissions: contents: read, actions: read`, no secrets, a
  `timeout-minutes`, and `concurrency: studio` (one Studio, one screen).
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

**What a pull request's Luau can do inside Studio.** Today the smoke job
plays the place CI built from `main`, so only merged code runs. When a job
plays a pull request's place (mac-002, on the owner's `needs-playtest`
label), that place's scripts run in Studio in the guest with everything in
the table above. The place does not enable `HttpService`, and a place file
can enable it for itself, in which case its scripts can make HTTP requests
to the internet from the guest (not to the home network, under Softnet).
That is why the label is the owner's to give after reading the diff.

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
mac-002 adds a second check. Every command the bridge runs (`plutil`,
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
