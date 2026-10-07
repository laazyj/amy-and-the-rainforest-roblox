--!strict
-- Run tests/engine/ scripts in a place through Open Cloud Luau Execution. See docs/OPEN_CLOUD.md.
-- lune run tools/run-engine-tests --universe <id> --place <id> --version <n> --dir tests/engine
local Cli = require("./lib/cli")
Cli.main(require("./lib/engine-tests").main)
