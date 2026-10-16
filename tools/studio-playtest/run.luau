--!strict
-- Tier 3 smoke run on the Mac runner: plays a built place in Roblox Studio
-- and writes <out>/viewport.png and <out>/report.json. Exits non-zero on any
-- failure. See docs/MAC_RUNNER.md.
-- lune run tools/studio-playtest/run --file build/AmyAndTheRainforest.rbxl --out build/studio-smoke
local fs = require("@lune/fs")

local Cli = require("../lib/cli")
local Smoke = require("./smoke")
local Studio = require("./studio")

local USAGE = "usage: lune run tools/studio-playtest/run --file <path.rbxl> --out <directory>"

Cli.main(function(ctx)
	local values, dryRun = Cli.options(ctx.args, USAGE, { "file", "out" })
	Studio.refuseDryRun(dryRun)
	local out = Cli.required(values, "out")
	fs.writeDir(out)
	local report = Smoke.run(Studio.bridge({ ctx = ctx }), {
		placeFile = Cli.required(values, "file"),
		screenshotPath = `{out}/viewport.png`,
		pinnedStudioVersion = Studio.pinnedVersion(),
		clock = os.clock,
		log = ctx.log,
	})
	Studio.finish(ctx, out, report)
end)
