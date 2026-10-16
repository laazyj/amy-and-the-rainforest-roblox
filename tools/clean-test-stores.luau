--!strict
-- Delete what an engine-test run left in its test stores. See docs/OPEN_CLOUD.md.
-- lune run tools/clean-test-stores --universe <id> --place <id> --run-id <id>
local Cli = require("./lib/cli")
Cli.main(require("./lib/clean-test-stores").main)
