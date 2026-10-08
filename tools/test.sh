#!/usr/bin/env bash
# Runs the tier 1 unit tests under Lune. Optional argument: a name filter.
set -euo pipefail
cd "$(dirname "$0")/.."

lune run tests/lune/runner.luau "$@"
