--!strict
-- Tier 3 smoke run on the Mac runner: plays a built place in Roblox Studio
-- and writes <out>/viewport.png and <out>/report.json. Exits non-zero on any
-- failure. See docs/MAC_RUNNER.md.
-- lune run tools/studio-playtest/run --file build/AmyAndTheRainforest.rbxl --out build/studio-smoke
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Smoke = require("./smoke")
local Studio = require("./studio")

local USAGE = "usage: lune run tools/studio-playtest/run --file <path.rbxl> --out <directory>"

Cli.main(function(ctx)
	local values, dryRun = Cli.options(ctx.args, USAGE, { "file", "out" })
	if dryRun then
		error("there is no --dry-run: this tool only drives the local Studio", 0)
	end
	local out = Cli.required(values, "out")
	fs.writeDir(out)
	local report = Smoke.run(Studio.bridge({ ctx = ctx }), {
		placeFile = Cli.required(values, "file"),
		screenshotPath = `{out}/viewport.png`,
		pinnedStudioVersion = (string.gsub(Files.read("tools/studio-playtest/studio-version.txt"), "%s+", "")),
		clock = os.clock,
		log = ctx.log,
	})
	fs.writeFile(`{out}/report.json`, serde.encode("json", report, true) .. "\n")

	if report.studioVersionDrift then
		local message = `Studio is {report.studioVersion}, the bridge was last proven on {report.pinnedStudioVersion}`
		ctx.log(
			if ctx.env.GITHUB_ACTIONS then `::warning title=Studio version drift::{message}` else `warning: {message}`
		)
	end
	if report.result ~= "pass" then
		error(`failed after {report.durationSeconds} seconds: {report.failure}`, 0)
	end
	ctx.log(`pass in {report.durationSeconds} seconds`)
end)
