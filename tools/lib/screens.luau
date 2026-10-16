--!strict
--[[
	Screens: a Studio playtest's screenshots, put where they are reviewed
	(brief mac-003; docs/MAC_RUNNER.md, "Screenshots on a pull request").
	The pure half: which files of the playtest's artifact are captures,
	which baseline in docs/screens/ each is compared with, whether a
	comparison counts as changed, and the comment that shows it all.
	tools/screens.luau runs ImageMagick around it.

	The artifact comes from a run in which a pull request's place played in
	Studio, so nothing in it is trusted: a capture whose file name is not
	`<device>/<nn>-<kind>-<name>.png` in lower-case letters, digits and
	hyphens is left out and listed, and every text from report.json is
	shown in a code span, where Markdown, HTML and mentions do nothing.

	A capture is paired with the baseline of the same device, kind and name
	(the `<nn>` is left out, so a capture added before it does not unpair
	the rest), the first such capture with the first such baseline, and so
	on.
]]

local Screens = {}

-- The marker the comment is found by, so there is one per pull request.
Screens.MARKER = "<!-- studio-playtest-screens -->"

-- The kind of the title screen's capture (brief mac-003, Must B6):
-- `<nn>-title-title.png`, shown across devices in one index image.
Screens.TITLE_KIND = "title"

-- Level 2 tolerance (plan section 4). ImageMagick 6 on GitHub's runners
-- has no structural-similarity metric, so the stand-in is the share of
-- pixels whose colour moved by more than FUZZ; a capture whose share is
-- over SHARE, or whose size changed, has changed.
Screens.FUZZ = "10%"
Screens.SHARE = 0.01

-- The comment shows at most this many changed captures' rows; the rest
-- are in the artifact.
Screens.MAX_ROWS = 30

-- The contact sheet's tiles.
Screens.SHEET_COLUMNS = 4
Screens.TILE_WIDTH = 320
Screens.ROW_IMAGE_WIDTH = 240

export type Capture = {
	device: string,
	file: string, -- "<device>/<nn>-<kind>-<name>.png"
	kind: string,
	name: string,
}

export type Status = "same" | "changed" | "new"

export type Compared = {
	capture: Capture,
	baseline: string?, -- the baseline's file under docs/screens/
	status: Status,
	share: number?, -- of pixels changed, when compared
	resized: string?, -- "<before> to <after>" when the size changed
}

export type Device = {
	name: string,
	result: string,
	compared: { Compared },
	gone: { string }, -- baselines no capture pairs with
	baselines: number, -- how many the device had
}

export type Page = {
	report: any?, -- report.json, decoded; nil when there was none
	devices: { Device },
	rejected: { string }, -- files left out, as code spans already
	title: boolean, -- the title screen's index image was made
	baseUrl: string, -- where the published files are, no trailing "/"
	runUrl: string,
	artifactUrl: string?,
}

local FILE = "^([a-z0-9%-]+)/%d%d%-([a-z]+)%-([a-z0-9%-]*)%.png$"

-- The capture a file name is, or nil when it is not one.
function Screens.parse(file: string): Capture?
	local device, kind, name = string.match(file, FILE)
	if not device then
		return nil
	end
	return { device = device :: string, file = file, kind = kind :: string, name = name :: string }
end

-- Text from the artifact as an inline code span: one line, no backticks
-- and no table bar, at most `limit` characters.
function Screens.code(text: any, limit: number?): string
	local line = string.gsub(string.gsub(tostring(text), "[%c`]+", " "), "|", "/")
	local max = limit or 200
	if #line > max then
		line = string.sub(line, 1, max) .. "..."
	end
	return "`" .. line .. "`"
end

-- The devices a report lists; none when it is missing or broken.
local function devicesOf(report: any): { any }
	return if type(report) == "table" and type(report.devices) == "table" then report.devices else {}
end

-- A device of the report: its name, result and captures.
export type Played = { name: string, result: string, captures: { Capture } }

-- The devices of a report with their captures, and the files left out.
-- `exists` says whether a file is in the artifact.
function Screens.captures(report: any, exists: (file: string) -> boolean): ({ Played }, { string })
	local played: { Played } = {}
	local seen: { [string]: true } = {}
	local rejected: { string } = {}
	for _, device in devicesOf(report) do
		local name = type(device) == "table" and device.name
		if type(name) ~= "string" or not string.match(name, "^[a-z0-9%-]+$") or seen[name] then
			table.insert(rejected, `device {Screens.code(name)}`)
			continue
		end
		seen[name] = true
		local entry: Played = { name = name, result = tostring(device.result), captures = {} }
		table.insert(played, entry)
		for _, each in (if type(device.captures) == "table" then device.captures else {}) :: { any } do
			local file = if type(each) == "table" then each.file else nil
			local capture = if type(file) == "string" then Screens.parse(file) else nil
			if capture and capture.device == name and exists(file) then
				table.insert(entry.captures, capture)
			else
				table.insert(rejected, Screens.code(file))
			end
		end
	end
	return played, rejected
end

local function key(capture: Capture): string
	return `{capture.kind}-{capture.name}`
end

-- Each capture with the baseline it is compared with (nil: new), and the
-- baselines no capture pairs with. `baselines` are file names under
-- docs/screens/ for this device.
function Screens.pair(captures: { Capture }, baselines: { string }): ({ Compared }, { string })
	local waiting: { [string]: { string } } = {}
	local sorted = table.clone(baselines)
	table.sort(sorted)
	for _, file in sorted do
		local baseline = Screens.parse(file)
		if baseline then
			local list = waiting[key(baseline)] or {}
			waiting[key(baseline)] = list
			table.insert(list, file)
		end
	end
	local compared: { Compared } = {}
	for _, capture in captures do
		local list = waiting[key(capture)]
		local baseline = list and table.remove(list, 1)
		table.insert(compared, { capture = capture, baseline = baseline, status = "new" })
	end
	local gone = {}
	for _, list in waiting do
		table.move(list, 1, #list, #gone + 1, gone)
	end
	table.sort(gone)
	return compared, gone
end

-- Whether a comparison counts as changed: a `share` of its pixels moved by
-- more than FUZZ, or the size changed.
function Screens.changed(share: number, resized: boolean): boolean
	return resized or share > Screens.SHARE
end

-- A device's comparisons by status.
type Split = { same: { Compared }, changed: { Compared }, new: { Compared } }
local function byStatus(device: Device): Split
	local split: Split = { same = {}, changed = {}, new = {} }
	for _, each in device.compared do
		table.insert((split :: any)[each.status], each)
	end
	return split
end

local function image(url: string, alt: string, width: number?): string
	return if width then `<img src="{url}" alt="{alt}" width="{width}">` else `![{alt}]({url})`
end

-- The comment, or the job summary of a run of main.
function Screens.comment(page: Page): string
	local report = page.report
	local lines = { Screens.MARKER, "## Screenshots from the Studio playtest", "" }
	local function add(line: string)
		table.insert(lines, line)
	end
	if type(report) == "table" then
		local result = if report.finished == false then "stopped before the end" else Screens.code(report.result)
		local version = `Studio {Screens.code(report.studioVersion or "unknown")}`
		if report.studioVersionDrift then
			version ..= `, not the pinned {Screens.code(report.pinnedStudioVersion)}`
		end
		add(`**Playtest: {result}** in {tonumber(report.durationSeconds) or 0} s. {version}.`)
	else
		add("**No report.json**: the run failed before Studio was played.")
	end
	add(`[The run]({page.runUrl})` .. if page.artifactUrl then ` · [the artifact]({page.artifactUrl})` else "")
	add("")

	if #page.devices > 0 then
		add(
			`Compared with \`docs/screens/\`: a capture has changed when over {Screens.SHARE * 100}% of its pixels moved by more than {Screens.FUZZ}, or its size changed.`
		)
		add("")
		add("| Device | Result | Captures | Changed | New | Baselines gone |")
		add("|---|---|---|---|---|---|")
		for _, device in page.devices do
			local split = byStatus(device)
			add(
				`| {device.name} | {Screens.code(device.result, 20)} | {#device.compared} | {#split.changed} | {#split.new} | {#device.gone} |`
			)
		end
		add("")
	end

	for _, device in devicesOf(report) do
		if type(device) ~= "table" then
			continue
		end
		if type(device.warnings) == "table" then
			for _, warning in device.warnings do
				add(`> Warning, {Screens.code(device.name, 40)}: {Screens.code(warning)}`)
			end
		end
		if device.failure ~= nil then
			add(`> Failure, {Screens.code(device.name, 40)}: {Screens.code(device.failure)}`)
		end
	end
	if type(report) == "table" and report.failure ~= nil then
		add(`> Failure: {Screens.code(report.failure)}`)
	end
	if #page.rejected > 0 then
		add(`> Left out, not a capture's file name: {table.concat(page.rejected, ", ")}`)
	end
	add("")

	if page.title then
		add("### The title screen on every device")
		add(image(`{page.baseUrl}/sheets/title.png`, "The title screen on every device"))
		add("")
	end

	local rows = 0
	local hidden = 0
	for _, device in page.devices do
		add(`### {device.name}`)
		if #device.compared > 0 then
			add(image(`{page.baseUrl}/sheets/{device.name}.png`, `Contact sheet, {device.name}`))
		else
			add("No captures.")
		end
		if device.baselines == 0 and #device.compared > 0 then
			add("")
			add(`No baselines in \`docs/screens/{device.name}/\` yet: every capture is new.`)
		end
		local split = byStatus(device)
		local changed = split.changed
		if #changed > 0 then
			add("")
			add("| Changed | Before | After | Difference |")
			add("|---|---|---|---|")
			for _, each in changed do
				if rows >= Screens.MAX_ROWS then
					hidden += 1
					continue
				end
				rows += 1
				local file = each.capture.file
				local how = if each.resized
					then `size {each.resized}`
					else `{math.floor((each.share or 0) * 1000 + 0.5) / 10}% of pixels`
				local width = Screens.ROW_IMAGE_WIDTH
				add(
					`| \`{file}\`<br>{how} | {image(`{page.baseUrl}/before/{each.baseline}`, "before", width)} | {image(
						`{page.baseUrl}/captures/{file}`,
						"after",
						width
					)} | {image(`{page.baseUrl}/diff/{file}`, "difference", width)} |`
				)
			end
		end
		local new = {}
		for _, each in split.new do
			table.insert(new, `\`{each.capture.file}\``)
		end
		-- with no baselines at all, every capture is new and said so above
		if #new > 0 and device.baselines > 0 then
			add("")
			add(`New, no baseline: {table.concat(new, ", ")}`)
		end
		if #device.gone > 0 then
			local gone = {}
			for _, file in device.gone do
				table.insert(gone, `\`{file}\``)
			end
			add("")
			add(`Baselines no capture matched: {table.concat(gone, ", ")}`)
		end
		add("")
	end
	if hidden > 0 then
		add(`{hidden} more changed captures are not shown here; they are in the artifact.`)
		add("")
	end
	add(
		"Baselines change only through a Baselines pull request (docs/screens/README.md). The owner's `needs-playtest` label runs this again."
	)
	return table.concat(lines, "\n") .. "\n"
end

-- The files a Baselines pull request takes from a run of main: every
-- capture of a finished, passing report that played every device in
-- `devices`. Nil and why not otherwise.
function Screens.baselines(report: any, exists: (file: string) -> boolean, devices: { string }): ({ Capture }?, string?)
	if type(report) ~= "table" then
		return nil, "there is no report.json"
	elseif report.finished ~= true or report.result ~= "pass" then
		return nil, `the playtest did not pass to the end (result {Screens.code(report.result)})`
	end
	local played, rejected = Screens.captures(report, exists)
	if #rejected > 0 then
		return nil, `not a capture's file name: {table.concat(rejected, ", ")}`
	end
	local all = {}
	local missing = table.clone(devices)
	for _, device in played do
		table.move(device.captures, 1, #device.captures, #all + 1, all)
		local at = table.find(missing, device.name)
		if at then
			table.remove(missing, at)
		end
	end
	if #all == 0 then
		return nil, "the playtest made no captures"
	elseif #missing > 0 then
		return nil, `the playtest did not play every device: no {table.concat(missing, ", ")}`
	end
	return all, nil
end

return Screens
