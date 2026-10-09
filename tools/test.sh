#!/usr/bin/env bash
# Runs the tier 1 unit tests under Lune. Optional argument: a name filter.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/build/bin:$PATH" # where tools/bootstrap-agent.sh installs

lune run tests/lune/runner.luau "$@"
