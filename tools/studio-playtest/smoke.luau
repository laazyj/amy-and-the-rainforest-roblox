--!strict
-- The Studio smoke run (tier 3's first proof, brief mac-001): open a built
-- place in Roblox Studio, start Play, run a script that prints the place name
-- and RunService:IsStudio(), capture the Studio window, stop Play, and report.
-- Pure: everything that touches Studio goes through the Bridge, which
-- studio.luau implements and the spec replaces with a fake.

export type DataModel = "Edit" | "Client" | "Server"

export type Bridge = {
	studioVersion: () -> string,
	-- Launches Studio on the place file and returns once the place is open.
	open: (placeFile: string) -> (),
	startPlay: () -> (),
	stopPlay: () -> (),
	-- Runs Luau in one of Studio's DataModels and returns what it returned.
	run: (dataModel: DataModel, code: string) -> string,
	consoleOutput: () -> string,
	-- Writes a PNG of the Studio window, viewport included, to `path`, and
	-- returns the mean luminance (0 to 1) of the middle of it, where the
	-- viewport is.
	capture: (path: string) -> number,
	-- Quits the Studio this bridge launched. Safe to call at any point.
	close: () -> (),
}

export type Options = {
	placeFile: string,
	screenshotPath: string,
	pinnedStudioVersion: string,
	clock: () -> number, -- seconds, fractional
	log: (string) -> (),
}

export type Step = { name: string, ok: boolean, seconds: number }

export type Report = {
	result: "pass" | "fail",
	failure: string?,
	studioVersion: string?,
	pinnedStudioVersion: string,
	studioVersionDrift: boolean,
	durationSeconds: number,
	placeFile: string,
	placeName: string?, -- the Edit DataModel's name: the file name of a local place
	printed: string?, -- the line the script printed during Play
	isStudio: boolean?,
	viewport: string?, -- the client's viewport, "<width>x<height>" in points
	frameMilliseconds: number?, -- the client's mean frame time during Play
	screenshot: string?,
	screenshotLuminance: number?, -- of the middle of the screenshot, 0 to 1

	steps: { Step },
}

local Smoke = {}

-- A session that renders nothing gives a black viewport (near 0); the game's
-- darkest Scene is far above this.
Smoke.LUMINANCE_FLOOR = 0.03

-- Run on the server during Play. A local file's DataModel is named "Game"
-- there; the file name is checked in Edit, before Play starts.
Smoke.PLAY_SCRIPT = [[
local isStudio = game:GetService("RunService"):IsStudio()
local line = `studio-smoke place={game.Name} isStudio={isStudio}`
print(line)
return line
]]

-- Run on the client before the capture, so the frame shows the game and not
-- a loading screen: waits for the place and Amy, lets the first Line appear,
-- then times 60 frames.
Smoke.CLIENT_READY_SCRIPT = [[
if not game:IsLoaded() then
	game.Loaded:Wait()
end
local player = game:GetService("Players").LocalPlayer
local _ = player.Character or player.CharacterAdded:Wait()
task.wait(2)
local renderStepped = game:GetService("RunService").RenderStepped
local frames, seconds = 60, 0
for _ = 1, frames do
	seconds += renderStepped:Wait()
end
local size = workspace.CurrentCamera.ViewportSize
return `{size.X}x{size.Y} {seconds / frames * 1000}`
]]

local function round(seconds: number): number
	return math.round(seconds * 10) / 10
end

local function baseName(path: string): string
	return string.match(path, "([^/]+)$") or path
end

function Smoke.run(bridge: Bridge, options: Options): Report
	local started = options.clock()
	local report: Report = {
		result = "pass",
		pinnedStudioVersion = options.pinnedStudioVersion,
		studioVersionDrift = false,
		durationSeconds = 0,
		placeFile = options.placeFile,
		steps = {},
	}

	-- Runs one step. The first failure is the report's failure; later steps
	-- are skipped by the caller, cleanup steps still run.
	local function step(name: string, fn: () -> ()): boolean
		options.log(`== {name}`)
		local stepStarted = options.clock()
		local ok, err = pcall(fn :: () -> any)
		table.insert(report.steps, { name = name, ok = ok, seconds = round(options.clock() - stepStarted) })
		if not ok then
			options.log(`failed: {err}`)
			if report.result == "pass" then
				report.result = "fail"
				report.failure = `{name}: {err}`
			end
		end
		return ok
	end

	local playing = false
	local sequence: { { name: string, run: () -> () } } = {
		{
			name = "Read the Studio version",
			run = function()
				local version = bridge.studioVersion()
				report.studioVersion = version
				report.studioVersionDrift = version ~= options.pinnedStudioVersion
				options.log(`Studio {version} (pinned {options.pinnedStudioVersion})`)
			end,
		},
		{
			name = "Open the place in Studio",
			run = function()
				bridge.open(options.placeFile)
				local name = bridge.run("Edit", "return game.Name")
				if name ~= baseName(options.placeFile) then
					error(`Studio has '{name}' open, not {baseName(options.placeFile)}`, 0)
				end
				report.placeName = name
			end,
		},
		{
			name = "Start Play",
			run = function()
				playing = true -- stop even if the start only half happened
				bridge.startPlay()
			end,
		},
		{
			name = "Run the script that prints the place name and IsStudio",
			run = function()
				local line = string.gsub(bridge.run("Server", Smoke.PLAY_SCRIPT), "%s+$", "")
				local isStudio = string.match(line, "^studio%-smoke place=.+ isStudio=(%a+)$")
				if not isStudio then
					error(`the script returned '{line}'`, 0)
				end
				report.printed = line
				report.isStudio = isStudio == "true"
				if not report.isStudio then
					error("RunService:IsStudio() is false", 0)
				end
				if not string.find(bridge.consoleOutput(), line, 1, true) then
					error(`the Studio console does not show '{line}'`, 0)
				end
				options.log(line)
			end,
		},
		{
			name = "Capture the viewport",
			run = function()
				local ready = bridge.run("Client", Smoke.CLIENT_READY_SCRIPT)
				local viewport, frame = string.match(ready, "^(%d+x%d+) ([%d.]+)$")
				if not viewport then
					error(`the client returned '{ready}'`, 0)
				end
				report.viewport = viewport
				report.frameMilliseconds = round(tonumber(frame) :: number)
				local luminance = bridge.capture(options.screenshotPath)
				report.screenshot = options.screenshotPath
				report.screenshotLuminance = math.round(luminance * 1000) / 1000
				options.log(`frame time {report.frameMilliseconds} ms, luminance {report.screenshotLuminance}`)
				if luminance < Smoke.LUMINANCE_FLOOR then
					error("the screenshot is black where the viewport should be: Studio rendered nothing", 0)
				end
			end,
		},
	}
	for _, entry in sequence do
		if not step(entry.name, entry.run) then
			break
		end
	end

	if playing then
		step("Stop Play", bridge.stopPlay)
	end
	step("Quit Studio", bridge.close)

	report.durationSeconds = round(options.clock() - started)
	return report
end

return Smoke
