#!/usr/bin/env bash
# Sets up the Mac runner's virtual machine from the inside (brief mac-001a):
# Roblox Studio and the GitHub Actions self-hosted runner labelled `studio`.
# Run it in the guest, as the guest's one user, never on the owner's Mac
# itself and never with sudo. See docs/MAC_RUNNER.md.
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
# server), started at login. A runner that is already registered is left
# registered, and RUNNER_TOKEN is then not needed.
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

	echo
	echo "Left for a person, in the VM's window (tools/mac/vm.sh start window):"
	echo "  - Open Roblox Studio and sign in to the runner's own Roblox account, never the owner's."
	echo "  - Open any place, then Assistant -> settings -> MCP Servers -> enable 'Studio as MCP server'."
	echo "  - Approve the Screen Recording prompt the first time the wrapper captures the window."
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

	echo "== launchd agent"
	# svc.sh writes ~/Library/LaunchAgents/actions.runner.*.plist and loads it
	# into this user's GUI session; it captures the current PATH for the jobs.
	if ./svc.sh status 2>/dev/null | grep -q "Started:"; then
		echo "already running"
	else
		[ -f .service ] || ./svc.sh install
		# svc.sh asks launchd for a session of the runner's own, which has no
		# window server: Studio would render nothing. Stay in the desktop session.
		plutil -replace SessionCreate -bool false "$(cat .service)"
		./svc.sh start
	fi
	echo "Runner '$RUNNER_NAME' is set up."
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
