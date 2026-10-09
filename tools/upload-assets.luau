--!strict
-- Upload pending assets through Open Cloud and write their ids back. Only CI
-- runs this (.github/workflows/upload-assets.yml). See docs/ASSETS.md.
-- lune run tools/upload-assets --universe <id> --place <id> --creator-user <id> [--dry-run]
local Cli = require("./lib/cli")
Cli.main(require("./lib/upload-assets").main)
