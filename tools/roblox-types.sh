#!/usr/bin/env bash
# Prints the path of the Roblox API type definitions for the installed
# luau-lsp version, downloading them into build/ first if they are missing.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build

version="$(luau-lsp --version)"
defs="build/globalTypes-$version.d.luau"
if [ ! -f "$defs" ]; then
	curl -fsSL -o "$defs.tmp" "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$version/scripts/globalTypes.d.luau"
	mv "$defs.tmp" "$defs"
fi
echo "$defs"
