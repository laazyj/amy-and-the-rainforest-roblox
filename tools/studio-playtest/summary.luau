--!strict
-- Prints a playthrough's report.json as Markdown, for the job summary.
-- lune run tools/studio-playtest/summary build/studio-playtest/report.json
local serde = require("@lune/serde")

local Cli = require("../lib/cli")
local Playthrough = require("./playthrough")

Cli.main(function(ctx)
	local path = ctx.args[1] or error("usage: lune run tools/studio-playtest/summary <report.json>", 0)
	local text = ctx.readFile(path)
	ctx.out(
		if text
			then Playthrough.summary(serde.decode("json", text))
			else "No report: the run failed before Studio was played."
	)
end)
