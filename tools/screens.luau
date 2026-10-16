--!strict
--[[
	A Studio playtest's screenshots, for review (brief mac-003; the logic
	is tools/lib/screens.luau, docs/MAC_RUNNER.md says where it runs).
	Needs ImageMagick 6 (`montage`, `compare`, `convert`, `identify`), as on
	GitHub's ubuntu-latest runners.

	  lune run tools/screens sheets --artifact <dir> --baselines docs/screens \
	    --files <dir> --comment <file> --status <file> --base-url <url> --run-url <url> [--artifact-url <url>]

	    From the playtest's artifact (report.json and the captures), writes
	    under --files: sheets/<device>.png, a contact sheet per device;
	    sheets/title.png, the title screen across devices; captures/, every
	    capture; and for each capture that differs from its baseline,
	    before/ (the baseline) and diff/ (the difference). Writes the comment
	    to --comment, its images linked under --base-url, and the commit
	    status's state and description to --status as JSON.

	  lune run tools/screens baselines --artifact <dir> --out <dir>

	    Copies every capture of a finished, passing run of every device
	    (Playthrough.DEVICES) to
	    <out>/<device>/<nn>-<kind>-<name>.png, for a Baselines pull request.
	    Fails, copying nothing, on anything else.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Cli = require("./lib/cli")
local Screens = require("./lib/screens")
local Playthrough = require("./studio-playtest/playthrough")

local USAGE =
	[[usage: lune run tools/screens sheets --artifact <dir> --baselines <dir> --files <dir> --comment <file> --status <file> --base-url <url> --run-url <url> [--artifact-url <url>]
       lune run tools/screens baselines --artifact <dir> --out <dir>]]

-- Runs an ImageMagick program; its result, failing on anything but the
-- exit codes in `ok` (0 when not given).
local function magick(program: string, args: { string }, ok: { number }?): process.ExecResult
	local result = process.exec(program, args)
	if not table.find(ok or { 0 }, result.code) then
		error(`{program} failed ({result.code}): {result.stderr}`, 0)
	end
	return result
end

local function size(file: string): string
	return magick("identify", { "-format", "%wx%h", file }).stdout
end

local function makeParent(path: string)
	local parent = string.match(path, "^(.*)/[^/]*$")
	if parent and not fs.isDir(parent) then
		fs.writeDir(parent)
	end
end

local function copy(from: string, to: string)
	makeParent(to)
	fs.copy(from, to, true)
end

local function readReport(artifact: string): any?
	local path = `{artifact}/report.json`
	return if fs.isFile(path) then serde.decode("json", fs.readFile(path)) else nil
end

-- The baselines of a device, as "<device>/<file>".
local function baselinesOf(dir: string, device: string): { string }
	local files = {}
	if fs.isDir(`{dir}/{device}`) then
		for _, name in fs.readDir(`{dir}/{device}`) do
			table.insert(files, `{device}/{name}`)
		end
	end
	return files
end

-- Compares a capture with its baseline; when it has changed, writes the
-- difference to diff/ and the baseline to before/.
local function compare(each: Screens.Compared, artifact: string, baselines: string, files: string)
	local after = `{artifact}/{each.capture.file}`
	local before = `{baselines}/{each.baseline}`
	local afterSize, beforeSize = size(after), size(before)
	local diff = `{files}/diff/{each.capture.file}`
	makeParent(diff)
	local stretched = nil
	if beforeSize ~= afterSize then
		-- the difference of the baseline stretched to the capture's size
		stretched = `{diff}.before.png`
		magick("convert", { before, "-resize", `{afterSize}!`, stretched })
		each.resized = `{beforeSize} to {afterSize}`
	end
	local function differ(out: string): process.ExecResult
		return magick("compare", { "-metric", "AE", "-fuzz", Screens.FUZZ, stretched or before, after, out }, { 0, 1 })
	end
	-- measured first with no image written: most captures are the same
	local width, height = string.match(afterSize, "^(%d+)x(%d+)$")
	local total = (tonumber(width) or 0) * (tonumber(height) or 0)
	local changed = tonumber(string.match(differ("null:").stderr, "^%s*(%S+)"))
	each.share = if total > 0 and changed then changed / total else 1
	if Screens.changed(each.share :: number, each.resized ~= nil) then
		each.status = "changed"
		differ(diff)
		copy(before, `{files}/before/{each.baseline}`)
	else
		each.status = "same"
	end
	if stretched then
		fs.removeFile(stretched)
	end
end

local function montage(args: { string }, out: string)
	makeParent(out)
	local all = {
		-- named, as ImageMagick without its recommended packages has no default font
		"-font",
		Screens.FONT,
		"-background",
		"#fbf6ea",
		"-pointsize",
		"14",
		"-tile",
		`{Screens.SHEET_COLUMNS}x`,
		"-geometry",
		`{Screens.TILE_WIDTH}x+6+6`,
	}
	table.move(args, 1, #args, #all + 1, all)
	table.insert(all, out)
	magick("montage", all)
end

local function sheets(values: { [string]: string })
	local artifact = Cli.required(values, "artifact")
	local baselines = Cli.required(values, "baselines")
	local files = Cli.required(values, "files")
	local report = readReport(artifact)
	-- made even with nothing to show, so a run with no captures still publishes
	fs.writeDir(files)
	local played, rejected = Screens.captures(report, function(file)
		return fs.isFile(`{artifact}/{file}`)
	end)
	local devices: { Screens.Device } = {}
	-- the title screen's index image: each device's first title capture
	local titles: { string } = {}
	for _, device in played do
		local known = baselinesOf(baselines, device.name)
		local compared, gone = Screens.pair(device.captures, known)
		local labelled = { "-label", "%t" }
		local titled = false
		for _, each in compared do
			local file = `{artifact}/{each.capture.file}`
			copy(file, `{files}/captures/{each.capture.file}`)
			table.insert(labelled, file)
			if each.baseline then
				compare(each, artifact, baselines, files)
			end
			if each.capture.kind == Screens.TITLE_KIND and not titled then
				titled = true
				table.move({ "-label", device.name, file }, 1, 3, #titles + 1, titles)
			end
		end
		if #compared > 0 then
			montage(labelled, `{files}/sheets/{device.name}.png`)
		end
		table.insert(
			devices,
			{ name = device.name, result = device.result, compared = compared, gone = gone, baselines = #known }
		)
	end
	if #titles > 0 then
		montage(titles, `{files}/sheets/title.png`)
	end
	local comment = Screens.comment({
		report = report,
		devices = devices,
		rejected = rejected,
		title = #titles > 0,
		baseUrl = Cli.required(values, "base-url"),
		runUrl = Cli.required(values, "run-url"),
		artifactUrl = values["artifact-url"],
	})
	local path = Cli.required(values, "comment")
	makeParent(path)
	fs.writeFile(path, comment)
	local state, description = Screens.status(report, devices)
	fs.writeFile(Cli.required(values, "status"), serde.encode("json", { state = state, description = description }))
end

local function baselines(values: { [string]: string })
	local artifact = Cli.required(values, "artifact")
	local out = Cli.required(values, "out")
	local devices = {}
	for _, device in Playthrough.DEVICES do
		table.insert(devices, device.name)
	end
	local captures, reason = Screens.baselines(readReport(artifact), function(file)
		return fs.isFile(`{artifact}/{file}`)
	end, devices)
	if not captures then
		error(`no baselines: {reason}`, 0)
	end
	for _, capture in captures do
		copy(`{artifact}/{capture.file}`, `{out}/{capture.file}`)
	end
	print(`{#captures} baselines written to {out}`)
end

Cli.main(function(ctx)
	local args = table.clone(ctx.args)
	local command = table.remove(args, 1)
	if command == "sheets" then
		sheets(
			(
				Cli.options(
					args,
					USAGE,
					{ "artifact", "baselines", "files", "comment", "status", "base-url", "run-url", "artifact-url" }
				)
			)
		)
	elseif command == "baselines" then
		baselines((Cli.options(args, USAGE, { "artifact", "out" })))
	else
		error(USAGE, 0)
	end
end)
