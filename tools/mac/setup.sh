#!/usr/bin/env bash
# Sets up the Mac runner's virtual machine from the inside (brief mac-001a):
# Roblox Studio and the GitHub Actions self-hosted runner labelled `studio`.
# Run it in the guest, as the guest's one user, never on the owner's Mac
# itself, and not with sudo: the script asks for the guest's sudo itself for
# the one step that needs it. See docs/MAC_RUNNER.md.
#
#   tools/mac/setup.sh studio                         install Roblox Studio
#   RUNNER_TOKEN=<token> tools/mac/setup.sh runner    install and register the runner
#
# `studio` downloads the current Roblox Studio into /Applications. Signing in
# and enabling "Studio as MCP server" need a person; the script says so.
#
# `runner` downloads the pinned runner, verifies its SHA-256, registers it
# with the labels self-hosted, macOS, studio, and installs it as a launchd
# agent of the logged-in GUI session (not a daemon: Studio needs a window
# server), started at login and restarted whenever it exits. A runner that
# is already registered is left registered, and RUNNER_TOKEN is then not
# needed. It also installs the guest's clock job (below), the one step that
# uses the guest's sudo.
#
# Environment:
#   RUNNER_TOKEN  registration token, made on the host by the owner:
#                 `gh api -X POST repos/<repo>/actions/runners/registration-token --jq .token`
#                 or Settings -> Actions -> Runners -> New self-hosted runner.
#                 Valid for one hour. Never commit it.
#   RUNNER_REPO   owner/name (default: laazyj/amy-and-the-rainforest-roblox)
#   RUNNER_DIR    where the runner lives (default: ~/actions-runner-studio)
#   RUNNER_NAME   the runner's name on GitHub (default: <this machine's name>-studio)
set -euo pipefail

REPO="${RUNNER_REPO:-laazyj/amy-and-the-rainforest-roblox}"
RUNNER_DIR="${RUNNER_DIR:-$HOME/actions-runner-studio}"
RUNNER_NAME="${RUNNER_NAME:-$(scutil --get LocalHostName)-studio}"

# The runner updates itself once registered; this pin is only what is installed first.
RUNNER_VERSION="2.338.0"
case "$(uname -m)" in
arm64)
	RUNNER_ARCH="arm64"
	RUNNER_SHA256="df4cebda25c86a886ed204e49fee63f5c2e7cec5f447b5c98440a826bbdf9df2"
	;;
x86_64)
	RUNNER_ARCH="x64"
	RUNNER_SHA256="dea7a58796ce215fc424a8b27c0fdd9b813fa5fc03d109a4a1d38131d6bfa1a3"
	;;
*)
	echo "error: unsupported architecture $(uname -m)" >&2
	exit 1
	;;
esac

STUDIO_APP="/Applications/RobloxStudio.app"
ROBLOX_TEAM_ID="2CFABCH843"

fail() {
	echo "error: $*" >&2
	exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "this script sets up a Mac"
[ "$(id -u)" != "0" ] || fail "run as the logged-in user, not root: the runner must be a launchd agent of the GUI session"
# The runner must never land in the owner's own account (brief mac-001a).
[ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" = "1" ] ||
	fail "this is not a virtual machine. Run it inside the guest: tools/mac/vm.sh (docs/MAC_RUNNER.md)"

studio_version() {
	plutil -extract CFBundleShortVersionString raw "$STUDIO_APP/Contents/Info.plist"
}

install_studio() {
	echo "== Roblox Studio"
	if [ -d "$STUDIO_APP" ]; then
		echo "already installed: $(studio_version) (Studio updates itself when it starts)"
	else
		# Roblox publishes no checksum and only its current build, so Studio
		# cannot be pinned: its notarised Roblox signature is checked instead,
		# and the wrapper reports the version of every run.
		case "$(uname -m)" in
		arm64) studio_path="mac/arm64" ;;
		*) studio_path="mac" ;;
		esac
		upload="$(curl -fsSL https://clientsettings.roblox.com/v2/client-version/MacStudio |
			sed -n 's/.*"clientVersionUpload":"\([^"]*\)".*/\1/p')"
		[ -n "$upload" ] || fail "could not read Studio's current version from clientsettings.roblox.com"
		work="$(mktemp -d)"
		curl -fsSL -o "$work/studio.zip" "https://setup.rbxcdn.com/$studio_path/$upload-RobloxStudioApp.zip"
		ditto -x -k "$work/studio.zip" "$work/app"
		[ -d "$work/app/RobloxStudio.app" ] || fail "the download holds no RobloxStudio.app"
		spctl --assess --type execute -vv "$work/app/RobloxStudio.app" 2>&1 | grep -q "Roblox Corporation ($ROBLOX_TEAM_ID)" ||
			fail "the download is not signed and notarised by Roblox Corporation ($ROBLOX_TEAM_ID)"
		mv "$work/app/RobloxStudio.app" "$STUDIO_APP"
		rm -rf "$work"
		echo "installed Roblox Studio $(studio_version)"
	fi
	[ -x "$STUDIO_APP/Contents/MacOS/StudioMCP" ] || fail "this Studio has no built-in MCP server (Contents/MacOS/StudioMCP)"
	# The Dock hidden, so Studio's maximized window, and so each capture, has
	# the screen's full height.
	defaults write com.apple.dock autohide -bool true
	killall Dock 2>/dev/null || true
	# The smoke job downloads the place with it; the Tart image has it.
	command -v gh >/dev/null || fail "the GitHub CLI is missing: brew install gh"

	echo
	echo "Left for a person, in the VM's window (tools/mac/vm.sh start window):"
	echo "  - Open Roblox Studio and sign in to the runner's own Roblox account, never the owner's."
	echo "  - Open any place, then Assistant -> settings -> MCP Servers -> enable 'Studio as MCP server'."
	echo "  - Approve the Screen Recording prompt the first time the wrapper captures the window."
}

# The guest's clock stops while the host sleeps and is behind when it wakes;
# GitHub then refuses the runner's signed token as expired and the runner
# stops. macOS's own network time (timed) corrects the clock only every few
# hours, too late, so a launchd daemon of the guest sets it every minute.
# Nothing in the guest can tell that it was frozen (its clock stopped too), so
# it is a plain interval; launchd restarts the runner meanwhile.
install_clock() {
	echo "== Guest clock"
	local label="local.amy-studio.clock"
	local plist="/Library/LaunchDaemons/$label.plist"
	sudo tee "$plist" >/dev/null <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$label</string>
	<key>ProgramArguments</key>
	<array><string>/usr/bin/sntp</string><string>-sS</string><string>time.apple.com</string></array>
	<key>StartInterval</key><integer>60</integer>
</dict>
</plist>
PLIST
	sudo launchctl bootout "system/$label" 2>/dev/null || true
	sudo launchctl bootstrap system "$plist"
	echo "the guest's clock is set every minute"
}

# Runner hooks: the runner runs these before and after every job, whatever
# the workflow says. A job starts only from a workflow file on main (the
# `studio` environment gates only jobs that declare it, and a branch can run
# its own copy of a workflow) and from an allowed event; and any Studio left
# by a job that timed out or was cancelled is ended.
install_hooks() {
	echo "== Job hooks"
	cat >job-completed.sh <<'HOOK'
#!/bin/bash
# Installed by tools/mac/setup.sh (docs/MAC_RUNNER.md): after every job.
if pkill -9 -x RobloxStudio; then echo "ended a Studio the job left running"; fi
exit 0
HOOK
	cat >job-started.sh <<'HOOK'
#!/bin/bash
# Installed by tools/mac/setup.sh (docs/MAC_RUNNER.md): before every job.
if pkill -9 -x RobloxStudio; then echo "ended a Studio an earlier job left running"; fi
case "${GITHUB_WORKFLOW_REF:-}" in
"$GITHUB_REPOSITORY"/.github/workflows/*@refs/heads/main) ;;
*)
	echo "::error::this runner runs only workflow files from main, not '${GITHUB_WORKFLOW_REF:-unknown}'"
	exit 1
	;;
esac
case "${GITHUB_EVENT_NAME:-}" in
workflow_dispatch | push | schedule) ;;
*)
	echo "::error::this runner does not run jobs started by '${GITHUB_EVENT_NAME:-unknown}'"
	exit 1
	;;
esac
HOOK
	chmod +x job-started.sh job-completed.sh
	# .env is read by the runner at start; keep any other lines in it.
	touch .env
	grep -v '^ACTIONS_RUNNER_HOOK_JOB_' .env >.env.new || true
	{
		echo "ACTIONS_RUNNER_HOOK_JOB_STARTED=$RUNNER_DIR/job-started.sh"
		echo "ACTIONS_RUNNER_HOOK_JOB_COMPLETED=$RUNNER_DIR/job-completed.sh"
	} >>.env.new
	mv .env.new .env
}

install_runner() {
	[ -d "$STUDIO_APP" ] || fail "install Studio first: tools/mac/setup.sh studio"

	echo "== Runner $RUNNER_VERSION in $RUNNER_DIR"
	mkdir -p "$RUNNER_DIR"
	cd "$RUNNER_DIR"
	if [ ! -x ./config.sh ]; then
		archive="actions-runner-osx-$RUNNER_ARCH-$RUNNER_VERSION.tar.gz"
		curl -fsSL -o "$archive" "https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/$archive"
		echo "$RUNNER_SHA256  $archive" | shasum -a 256 -c -
		tar xzf "$archive"
		rm "$archive"
	fi

	if [ -f .runner ]; then
		echo "already registered; to register again see docs/MAC_RUNNER.md"
	else
		[ -n "${RUNNER_TOKEN:-}" ] || fail "RUNNER_TOKEN is not set (see the top of this script)"
		# The token goes through the environment, not the command line, so it
		# never shows in `ps`. The labels self-hosted, macOS and the
		# architecture are added by the runner itself.
		ACTIONS_RUNNER_INPUT_TOKEN="$RUNNER_TOKEN" ./config.sh --unattended \
			--url "https://github.com/$REPO" --name "$RUNNER_NAME" --labels studio --work _work --replace
	fi

	install_hooks

	echo "== launchd agent"
	# svc.sh writes ~/Library/LaunchAgents/actions.runner.*.plist and loads it
	# into this user's GUI session; it captures the current PATH for the jobs.
	# Running this again restarts the runner, ending any job it is running.
	[ -f .service ] || ./svc.sh install
	local agent
	agent="$(cat .service)"
	# svc.sh asks launchd for a session of the runner's own, which has no
	# window server: Studio would render nothing. Stay in the desktop session.
	plutil -replace SessionCreate -bool false "$agent"
	# The runner exits for good on some errors (an expired token after the
	# host slept); launchd starts it again.
	plutil -replace KeepAlive -bool true "$agent"
	./svc.sh stop >/dev/null 2>&1 || true
	./svc.sh start
	# A Studio left open in the VM's window would reopen at the next login
	# and idle beside every job's own; the guest reopens nothing.
	defaults write com.apple.loginwindow TALLogoutSavesState -bool false
	defaults write com.apple.loginwindow LoginwindowLaunchesRelaunchApps -bool false
	install_clock
	echo "The runner is set up."
}

case "${1:-}" in
studio) install_studio ;;
runner) install_runner ;;
*)
	# The header comment, up to the first line that is not one.
	awk 'NR > 1 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"
	exit 1
	;;
esac
