--!strict
-- Publish a place file through Open Cloud. See docs/OPEN_CLOUD.md.
-- lune run tools/publish --universe <id> --place <id> --file build/AmyAndTheRainforest.rbxl --version-type Saved
local Cli = require("./lib/cli")
Cli.main(require("./lib/publish").main)
