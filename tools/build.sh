#!/usr/bin/env bash
# Builds the place file from source with Rojo, after installing the Wally
# packages pinned in wally.toml (ProfileStore) into ServerPackages/ when they
# are missing or older than wally.toml. The installed code (every .lua and
# .luau file, and each package's default.project.json, which says what Rojo
# builds of it) must match the SHA-256s in tools/package-checksums.txt: a pin
# is a version, and this pins the content too (docs/MAINTENANCE.md).
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
	elif [ -n "${GITHUB_ACTIONS:-}" ]; then
		echo "error: wally install failed" >&2
		exit 1
	else
		echo "warning: wally install failed; building without ServerPackages (no saves)" >&2
		rm -rf ServerPackages # so the next build tries again
	fi
fi
if [ -d ServerPackages/_Index ]; then
	if ! diff <(sort -k2 tools/package-checksums.txt) \
		<(find ServerPackages/_Index -type f \( -name '*.lua*' -o -name default.project.json \) \
			-exec sha256sum {} + | sort -k2) >&2; then
		echo "error: the installed Wally packages differ from tools/package-checksums.txt (above)" >&2
		exit 1
	fi
elif [ -n "${GITHUB_ACTIONS:-}" ]; then
	echo "error: no ServerPackages after wally install" >&2
	exit 1
fi

mkdir -p build
rojo build default.project.json -o build/AmyAndTheRainforest.rbxl
