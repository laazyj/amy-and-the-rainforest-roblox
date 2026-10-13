#!/usr/bin/env bash
# The Mac runner's virtual machine, from the host (brief mac-001a). The GitHub
# runner and Roblox Studio live inside a macOS guest managed by Tart; the host
# only creates, starts, stops and resets it. See docs/MAC_RUNNER.md.
#
#   tools/mac/vm.sh create          clone the pinned base image into the VM
#   tools/mac/vm.sh start [window]  boot it headless, or in a window for the
#                                   steps that need a person (Studio sign-in)
#   tools/mac/vm.sh stop
#   tools/mac/vm.sh status
#   tools/mac/vm.sh exec <cmd...>   run a command in the guest
#   tools/mac/vm.sh push <file>...  copy files into the guest's ~/incoming
#   tools/mac/vm.sh seal            keep the VM as it is now as the base
#   tools/mac/vm.sh reset           throw the VM away and restore the base
#
# Run it as the Mac's owner, never with sudo. It never mounts a host
# directory into the guest (no `tart run --dir`), and it changes no power,
# screen saver or lock setting of the host.
#
# Environment:
#   STUDIO_VM       the VM's name (default: amy-studio); its base is <name>-base
#   STUDIO_VM_NET   softnet (default) or nat. Softnet keeps the guest off the
#                   host's local network; see docs/MAC_RUNNER.md for its
#                   one-time setup. nat lets the guest reach the LAN.
set -euo pipefail

VM="${STUDIO_VM:-amy-studio}"
BASE="$VM-base"
NET="${STUDIO_VM_NET:-softnet}"

# What the VM was built and proven with. A newer Tart is used with a warning;
# the image is pinned by digest, so `create` always clones the same macOS.
TART_VERSION="2.40.1"
IMAGE="ghcr.io/cirruslabs/macos-tahoe-base@sha256:87f3aa5ce21b5c876268f233bdfecf38b4c2a8116fe9bbb718e714cbae187377"
# macOS in that image, for the record: 26.6.2 (25G83).
CPUS=4
MEMORY_MB=8192
# The image's disk is 50 GB; the guest grows its volume to this at its next boot.
DISK_GB=60
# Studio's window, and so the screenshot, is at most this large.
DISPLAY_SIZE="1440x900"

LOG="$HOME/Library/Logs/$VM.log"

fail() {
	echo "error: $*" >&2
	exit 1
}

exists() {
	tart list --source local --quiet | grep -Fqx "$1"
}

running() {
	tart list --source local | awk -v vm="$VM" '$2 == vm && $NF == "running" { found = 1 } END { exit !found }'
}

need_vm() {
	exists "$VM" || fail "there is no VM '$VM'; run: tools/mac/vm.sh create"
}

need_running() {
	need_vm
	running || fail "the VM '$VM' is not running; run: tools/mac/vm.sh start"
}

[ "$(uname -s)" = "Darwin" ] || fail "this script manages a VM on a Mac"
[ "$(id -u)" != "0" ] || fail "run as the Mac's owner, not root"
command -v tart >/dev/null || fail "Tart is not installed: brew install openai/tools/tart (docs/MAC_RUNNER.md)"
installed="$(tart --version)"
if [ "$installed" != "$TART_VERSION" ]; then
	echo "warning: Tart is $installed, the VM was proven with $TART_VERSION" >&2
fi

command="${1:-}"
[ $# -gt 0 ] && shift
case "$command" in
create)
	if exists "$VM"; then
		fail "the VM '$VM' already exists; 'reset' restores its base, 'tart delete $VM' removes it"
	fi
	tart clone "$IMAGE" "$VM"
	tart set "$VM" --cpu "$CPUS" --memory "$MEMORY_MB" --disk-size "$DISK_GB" --display "$DISPLAY_SIZE"
	echo "created '$VM'; next: tools/mac/vm.sh start window, then tools/mac/setup.sh inside it (docs/MAC_RUNNER.md)"
	;;

start)
	need_vm
	if running; then
		echo "'$VM' is already running"
		exit 0
	fi
	options=(--no-audio --no-clipboard)
	case "${1:-}" in
	"") options+=(--no-graphics) ;;
	window) ;;
	*) fail "usage: tools/mac/vm.sh start [window]" ;;
	esac
	case "$NET" in
	softnet) options+=(--net-softnet) ;;
	nat) echo "warning: with STUDIO_VM_NET=nat the guest can reach this Mac's local network" >&2 ;;
	*) fail "STUDIO_VM_NET must be softnet or nat" ;;
	esac
	mkdir -p "$(dirname "$LOG")"
	nohup tart run "$VM" "${options[@]}" >"$LOG" 2>&1 &
	# Booted when the guest agent answers.
	for _ in $(seq 60); do
		if tart exec "$VM" true 2>/dev/null; then
			echo "'$VM' is running"
			exit 0
		fi
		if ! kill -0 $! 2>/dev/null; then
			cat "$LOG" >&2
			fail "'$VM' did not start (above)"
		fi
		sleep 2
	done
	fail "'$VM' did not answer within two minutes; see $LOG"
	;;

stop)
	need_vm
	if running; then
		tart stop "$VM"
	fi
	echo "'$VM' is stopped"
	;;

status)
	if ! exists "$VM"; then
		echo "'$VM' does not exist"
	elif running; then
		echo "'$VM' is running"
	else
		echo "'$VM' is stopped"
	fi
	echo "base '$BASE': $(exists "$BASE" && echo sealed || echo "not sealed yet")"
	;;

exec)
	need_running
	[ $# -gt 0 ] || fail "usage: tools/mac/vm.sh exec <command...>"
	tart exec -i "$VM" "$@"
	;;

push)
	# Nothing is shared with the guest; files go in through the guest agent.
	need_running
	[ $# -gt 0 ] || fail "usage: tools/mac/vm.sh push <file>..."
	tar -cf - "$@" | tart exec -i "$VM" /bin/sh -c 'mkdir -p "$HOME/incoming" && tar -xf - -C "$HOME/incoming"'
	echo "copied into the guest's ~/incoming: $*"
	;;

seal)
	need_vm
	running && fail "stop the VM first, so the base is a clean shutdown: tools/mac/vm.sh stop"
	if exists "$BASE"; then
		tart delete "$BASE"
	fi
	tart clone "$VM" "$BASE"
	echo "sealed: 'reset' now restores '$VM' to this state"
	;;

reset)
	exists "$BASE" || fail "there is no base '$BASE' to restore; run 'seal' once the VM is set up"
	if exists "$VM"; then
		running && tart stop "$VM"
		tart delete "$VM"
	fi
	tart clone "$BASE" "$VM"
	echo "'$VM' is restored from '$BASE'"
	;;

*)
	# The header comment, up to the first line that is not one.
	awk 'NR > 1 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"
	exit 1
	;;
esac
