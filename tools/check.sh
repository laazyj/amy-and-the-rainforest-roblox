#!/usr/bin/env bash
# Tier 0 static checks: StyLua formatting, Selene lint, luau-lsp type checking,
# the asset manifest (docs/ASSETS.md), and actionlint and zizmor (see
# tools/install-workflow-linters.sh) over .github.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build

# Roblox API type definitions, matched to the installed luau-lsp version.
version="$(luau-lsp --version)"
defs="build/globalTypes-$version.d.luau"
if [ ! -f "$defs" ]; then
	curl -fsSL -o "$defs.tmp" "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$version/scripts/globalTypes.d.luau"
	mv "$defs.tmp" "$defs"
fi

echo "== actionlint"
actionlint

echo "== zizmor"
# Online audits (impostor commits, known-vulnerable actions) need GitHub's API,
# so they run in CI, where GH_TOKEN is set; locally only the offline audits run.
# Accepted findings are listed, each with its reason, in .github/zizmor.yml.
if [ -n "${GITHUB_ACTIONS:-}" ]; then
	zizmor --persona=pedantic .github
else
	zizmor --persona=pedantic --offline .github
fi

echo "== StyLua"
stylua --check src tests tools

echo "== Assets: the manifest, and every rbxassetid:// in src/ is in it"
lune run tools/check-assets

echo "== Selene"
selene src tests tools # selene.toml excludes tests/engine, which has its own config
(cd tests/engine && selene .) # engine.yml declares the names the runner injects

echo "== luau-lsp: src (Roblox)"
rojo sourcemap default.project.json -o build/sourcemap.json
luau-lsp analyze --platform=roblox --sourcemap=build/sourcemap.json --definitions=@roblox="$defs" src

echo "== luau-lsp: tests/engine (Roblox, with the names the runner injects)"
luau-lsp analyze --platform=roblox --definitions=@roblox="$defs" \
	--definitions=@engine=tests/engine/globals.d.luau --ignore="**/*.d.luau" tests/engine

echo "== luau-lsp: tests/lune and tools (Lune)"
lune_version="$(lune --version | cut -d' ' -f2)"
if ! grep -q "typedefs/$lune_version/" .luaurc; then
	echo "error: the @lune alias in .luaurc must point at the typedefs of lune $lune_version" >&2
	exit 1
fi
lune setup >/dev/null # writes the @lune type definitions that .luaurc points at
luau-lsp analyze --platform=standard tests/lune tools
