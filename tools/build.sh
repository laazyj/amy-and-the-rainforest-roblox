#!/usr/bin/env bash
# Builds the place file from source with Rojo.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build
rojo build default.project.json -o build/AmyAndTheRainforest.rbxl
