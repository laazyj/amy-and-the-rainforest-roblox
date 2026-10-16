--!strict
--[[
	Prints, one per line, the changed paths that alter what is on screen
	(tools/lib/visual-paths.luau); nothing when there are none. The changed
	paths come from CHANGED_FILES, one per line, as for
	`lune run tools/guard test-change`.

	  CHANGED_FILES="$(git diff --no-renames --name-only HEAD^1 HEAD)" lune run tools/visual-paths
]]

local Cli = require("./lib/cli")
local VisualPaths = require("./lib/visual-paths")

Cli.main(function(ctx)
	for _, path in VisualPaths.matches(string.split(ctx.env.CHANGED_FILES or "", "\n")) do
		ctx.out(path)
	end
end)
