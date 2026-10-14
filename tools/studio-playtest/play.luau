--!strict
-- Tier 3 playthrough on the Mac runner (brief mac-002): plays a built place
-- in Roblox Studio from a fresh Save to the end card, once per device, and
-- writes a screenshot at every Shot, Chapter card and Scene entry under
-- <out>/<device>/ and <out>/report.json. Exits non-zero on any failure.
-- See docs/MAC_RUNNER.md.
-- lune run tools/studio-playtest/play --file build/AmyAndTheRainforest.rbxl --out build/studio-playtest [--devices pc,phone-portrait]
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Playthrough = require("./playthrough")
local Studio = require("./studio")

local USAGE = "usage: lune run tools/studio-playtest/play --file <path.rbxl> --out <directory> [--devices <name,...>]"

Cli.main(function(ctx)
	local values, dryRun = Cli.options(ctx.args, USAGE, { "file", "out", "devices" })
	if dryRun then
		error("there is no --dry-run: this tool only drives the local Studio", 0)
	end
	local out = Cli.required(values, "out")

	local devices = {}
	local wanted = if values.devices then string.split(values.devices, ",") else nil
	for _, run in Playthrough.DEVICES do
		if not wanted or table.find(wanted, run.name) then
			table.insert(devices, run)
		end
	end
	local names: { string } = wanted or {}
	for _, name in names do
		local known = false
		for _, run in Playthrough.DEVICES do
			known = known or run.name == name
		end
		if not known then
			error(`unknown device '{name}'`, 0)
		end
	end
	for _, run in devices do
		fs.writeDir(`{out}/{run.name}`)
	end

	local report = Playthrough.run(Studio.bridge({ ctx = ctx }), {
		placeFile = Cli.required(values, "file"),
		outDir = out,
		devices = devices,
		pinnedStudioVersion = (string.gsub(Files.read("tools/studio-playtest/studio-version.txt"), "%s+", "")),
		clock = os.clock,
		sleep = ctx.sleep,
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
