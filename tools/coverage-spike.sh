#!/usr/bin/env bash
# Brief 008's coverage spike (docs/MAINTENANCE.md): Luau VM line coverage of
# src/core from the core specs, through the plain Luau CLI. Not part of CI:
# the CLI is not in the pinned toolchain.
#
# Usage: tools/coverage-spike.sh <luau>
#   <luau> is the Luau CLI binary; MAINTENANCE.md names the release and its
#   checksum.
set -euo pipefail
cd "$(dirname "$0")/.."

luau="$(realpath "${1:?usage: tools/coverage-spike.sh <luau>}")"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

mapfile -t specs < <(find tests/lune/core -name '*.spec.luau' | sort)
repo="$PWD"
(cd "$out" && "$luau" --coverage "$repo/tools/coverage-spike.luau" -a "${specs[@]}")

# coverage.out is lcov: SF:<file>, then DA:<line>,<hits> per executable line.
awk -F'[:,]' '
	/^SF:/ { file = $0; sub(/^SF:.*\/src\/core\//, "src/core/", file); core = ($0 ~ /\/src\/core\//) }
	/^DA:/ && core { total[file]++; if ($3 > 0) hit[file]++ }
	END {
		for (f in total) { printf "%-36s %4d / %4d\n", f, hit[f], total[f] | "sort"; h += hit[f]; t += total[f] }
		close("sort")
		printf "src/core total: %d of %d lines (%.1f%%)\n", h, t, 100 * h / t
	}
' "$out/coverage.out"
