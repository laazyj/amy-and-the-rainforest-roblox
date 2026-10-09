#!/usr/bin/env bash
# Tier 0 static checks: StyLua formatting, Selene lint, luau-lsp type checking,
# actionlint and zizmor (installed by tools/bootstrap-agent.sh) over .github,
# and the guards of tools/guard.luau (plan sections 2.1, 2.4 and 4).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/build/bin:$PATH" # where tools/bootstrap-agent.sh installs

defs="$(tools/roblox-types.sh)" # Roblox API types for the installed luau-lsp

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

echo "== Selene"
# Both configs use the committed roblox.yml in the working directory.
if [ ! -f roblox.yml ]; then
	echo "error: roblox.yml (Selene's Roblox standard library) is missing; see docs/MAINTENANCE.md" >&2
	exit 1
fi
selene src tests tools # selene.toml excludes tests/engine, which has its own config
selene --config tests/engine/selene.toml tests/engine # engine.yml declares the names the runner injects

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

echo "== Content schema (derived from docs/GLOSSARY.md)"
lune run tools/guard schema

echo "== Purity: src/core and src/content"
lune run tools/guard purity

echo "== No external links in content, core or client text"
lune run tools/guard links

echo "== Coverage guards: a spec per core module, glossary names in specs, a Walkthrough per Chapter"
lune run tools/guard coverage

echo "== Mutation check: every canned fault still applies (the nightly job runs them)"
lune run tools/guard faults
