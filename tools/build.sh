#!/usr/bin/env bash
# Builds the place file from source with Rojo.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/build/bin:$PATH" # where tools/bootstrap-agent.sh installs

mkdir -p build
rojo build default.project.json -o build/AmyAndTheRainforest.rbxl
