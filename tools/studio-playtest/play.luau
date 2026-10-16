--!strict
-- Tier 3 playthrough on the Mac runner (brief mac-002): plays a built place
-- in Roblox Studio from a fresh Save to the end card, once per device, and
-- writes a screenshot at every Shot, Chapter card and Scene entry under
-- <out>/<device>/ and <out>/report.json. Exits non-zero on any failure.
-- See docs/MAC_RUNNER.md.
-- lune run tools/studio-playtest/play --file build/AmyAndTheRainforest.rbxl --out build/studio-playtest [--devices pc,phone-portrait]
local fs = require("@lune/fs")

local Cli = require("../lib/cli")
local Playthrough = require("./playthrough")
local Studio = require("./studio")

local USAGE = "usage: lune run tools/studio-playtest/play --file <path.rbxl> --out <directory> [--devices <name,...>]"

Cli.main(function(ctx)
	local values, dryRun = Cli.options(ctx.args, USAGE, { "file", "out", "devices" })
	Studio.refuseDryRun(dryRun)
	local out = Cli.required(values, "out")

	local devices: { Playthrough.DeviceRun } = Playthrough.DEVICES
	if values.devices then
		devices = {}
		for _, name in string.split(values.devices, ",") do
			local found: Playthrough.DeviceRun? = nil
			for _, run in Playthrough.DEVICES do
				found = if run.name == name then run else found
			end
			table.insert(devices, found or error(`unknown device '{name}'`, 0))
		end
	end
	for _, run in devices do
		fs.writeDir(`{out}/{run.name}`)
	end

	local report = Playthrough.run(Studio.bridge({ ctx = ctx }), {
		placeFile = Cli.required(values, "file"),
		outDir = out,
		devices = devices,
		pinnedStudioVersion = Studio.pinnedVersion(),
		progress = function(sofar)
			Studio.writeReport(ctx, out, sofar)
		end,
		clock = os.clock,
		sleep = ctx.sleep,
		log = ctx.log,
	})
	Studio.finish(ctx, out, report)
end)
