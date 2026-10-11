#!/usr/bin/env bash
# Builds the place file from source with Rojo, after installing the Wally
# packages pinned in wally.toml (ProfileStore) into ServerPackages/ when they
# are missing or older than wally.toml.
#
# In CI a failed install fails the build. Elsewhere (a cloud session that
# cannot reach the Wally registry) it warns and builds without the packages:
# default.project.json maps ServerPackages as optional, and Persist then
# plays without saving.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/build/bin:$PATH" # where tools/bootstrap-agent.sh installs

if [ ! -d ServerPackages ] || [ wally.toml -nt ServerPackages ]; then
	if wally install; then
		touch ServerPackages
		# The installed packages, for the record (the PR quotes ProfileStore's).
		find ServerPackages/_Index -name '*.lua*' -type f -exec sha256sum {} + | sort -k2
	elif [ -n "${GITHUB_ACTIONS:-}" ]; then
		echo "error: wally install failed" >&2
		exit 1
	else
		echo "warning: wally install failed; building without ServerPackages (no saves)" >&2
		rm -rf ServerPackages # so the next build tries again
	fi
fi
if [ ! -d ServerPackages/_Index ] && [ -n "${GITHUB_ACTIONS:-}" ]; then
	echo "error: no ServerPackages after wally install" >&2
	exit 1
fi

mkdir -p build
rojo build default.project.json -o build/AmyAndTheRainforest.rbxl
