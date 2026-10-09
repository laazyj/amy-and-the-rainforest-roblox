#!/usr/bin/env bash
# Installs everything tools/check.sh, tools/test.sh and tools/build.sh need,
# exactly as CI does (.github/actions/setup-tools runs this script):
#
# - each tool pinned in rokit.toml, from its github.com release zip, checked
#   against tools/toolchain-checksums.txt before it is unpacked;
# - the luau-lsp Roblox type definitions for the pinned version (into build/);
# - Lune's type definitions (`lune setup`);
# - actionlint and zizmor, through tools/install-workflow-linters.sh.
#
# Usage: tools/bootstrap-agent.sh [bin dir]   (default ~/.local/bin)
#
# Idempotent: a tool already in the bin directory at its pinned version is
# kept. Only github.com release downloads and raw.githubusercontent.com are
# used, never api.github.com, so it works behind the cloud sessions' proxy.
# Run by the SessionStart hook in .claude/settings.json.
set -euo pipefail
cd "$(dirname "$0")/.."

bin="${1:-$HOME/.local/bin}"
mkdir -p "$bin"
case ":$PATH:" in
*":$bin:"*) on_path=1 ;;
*) on_path= ;;
esac
export PATH="$bin:$PATH"

case "$(uname -s)-$(uname -m)" in
Linux-x86_64) platform=linux-x86_64 ;;
Darwin-arm64) platform=macos-aarch64 ;;
*)
	echo "error: no pinned toolchain for $(uname -s)-$(uname -m)" >&2
	exit 1
	;;
esac

if command -v sha256sum >/dev/null; then
	sha256() { sha256sum "$1" | cut -d' ' -f1; }
else
	sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# has_version <command> <version>: the command is in $bin and reports <version>.
has_version() {
	[ -x "$bin/$1" ] && "$bin/$1" --version 2>/dev/null | grep -qwF "$2"
}

# The [tools] pins of rokit.toml, one `name repo version` per line.
pins="$(sed -n 's/^\([A-Za-z0-9_-]*\) *= *"\([^"@]*\)@\([^"]*\)".*/\1 \2 \3/p' rokit.toml)"

while read -r name repo version; do
	if has_version "$name" "$version"; then
		echo "$name $version: present"
		continue
	fi
	read -r tag asset expected < <(awk -v t="$name" -v p="$platform" '$1 == t && $3 == p { print $2, $4, $5 }' tools/toolchain-checksums.txt) || true
	if [ "${tag:-}" = "" ] || [ "${tag#v}" != "$version" ]; then
		echo "error: tools/toolchain-checksums.txt has no $platform line for $name $version (rokit.toml)" >&2
		exit 1
	fi
	zip="$tmp/$asset"
	curl -fsSL -o "$zip" "https://github.com/$repo/releases/download/$tag/$asset"
	actual="$(sha256 "$zip")"
	if [ "$actual" != "$expected" ]; then
		echo "error: $asset has SHA-256 $actual, but tools/toolchain-checksums.txt pins $expected" >&2
		exit 1
	fi
	unzip -oq "$zip" "$name" -d "$tmp"
	chmod +x "$tmp/$name"
	mv "$tmp/$name" "$bin/$name"
	echo "$name $version: installed into $bin (SHA-256 verified)"
done <<<"$pins"

echo "luau-lsp Roblox types: $(tools/roblox-types.sh)"

lune_version="$(lune --version | cut -d' ' -f2)"
if [ -d "$HOME/.lune/.typedefs/$lune_version" ]; then
	echo "lune typedefs $lune_version: present"
else
	lune setup >/dev/null
	echo "lune typedefs $lune_version: written by lune setup"
fi

tools/install-workflow-linters.sh "$bin"

# Later commands of a Claude Code session see this PATH too.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
	echo "export PATH=\"$bin:\$PATH\"" >>"$CLAUDE_ENV_FILE"
fi
if [ -z "$on_path" ] && [ -z "${CLAUDE_ENV_FILE:-}" ]; then
	echo "note: $bin is not on PATH; add it before running tools/check.sh"
fi
