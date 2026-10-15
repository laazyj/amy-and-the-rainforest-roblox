--!strict
-- The Studio smoke run (tier 3's first proof, brief mac-001): open a built
-- place in Roblox Studio, start Play, run a script that prints the place name
-- and RunService:IsStudio(), capture the Studio window, stop Play, and report.
-- Pure: everything that touches Studio goes through the Bridge, which
-- studio.luau implements and the spec replaces with a fake.

export type DataModel = "Edit" | "Client" | "Server"

export type Vector = { x: number, y: number, z: number }

-- A device Studio's device simulator plays as: its preset id (from
-- StudioDeviceSimulatorService:GetDeviceListAsync) and its orientation.
export type Device = { simulator: string, orientation: "Landscape" | "Portrait" }

-- What Studio's device simulator says it is set to, read back after setting
-- it: the preset id, the orientation and scaling mode (Enum item names) and
-- the device's size in points.
export type Simulation = { device: string, orientation: string, scaling: string, width: number, height: number }

-- A screenshot's mean luminance (0 to 1) in the middle, where the viewport
-- is, and its size in pixels ("<width>x<height>").
export type Screenshot = { luminance: number, pixels: string }

-- What tools/studio-playtest drives Studio through; studio.luau is the live one.
export type Bridge = {
	studioVersion: () -> string,
	-- Launches Studio on the place file and returns once the place is open.
	open: (placeFile: string) -> (),
	startPlay: () -> (),
	stopPlay: () -> (),
	-- Runs Luau in one of Studio's DataModels and returns what it returned.
	run: (dataModel: DataModel, code: string) -> string,
	consoleOutput: () -> string,
	-- Writes a PNG of the Studio window, viewport included, to `path`.
	capture: (path: string) -> Screenshot,
	-- Quits the Studio this bridge launched. Safe to call at any point.
	close: () -> (),
	-- The device the next Play simulates, or nil for none (a PC). Only in
	-- Edit: Studio takes it at the start of Play. Returns what the simulator
	-- then reports, nil when no device is active.
	setDevice: (device: Device?) -> Simulation?,
	-- During Play: a key press, as the player's keyboard sends it.
	press: (key: string) -> (),
	-- During Play: walks the Player Character to `position`.
	walkTo: (position: Vector) -> (),
	-- In Edit: inserts a Creator Store asset under `parentPath`, as Studio's
	-- Toolbox does. Where it lands is found from the parent, never from the
	-- name its creator gave it.
	insertAsset: (assetId: string, parentPath: string) -> (),
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
	screenshotPixels: string?,

	steps: { Step },
}

local Smoke = {}

-- A session that renders nothing gives a black viewport (near 0); the game's
-- darkest Scene is far above this.
Smoke.LUMINANCE_FLOOR = 0.03
-- A Studio panel or dialog over the viewport (the start page, an update
-- prompt) is nearly white; the game's brightest frames are under 0.5.
Smoke.LUMINANCE_CEILING = 0.85

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
-- ViewportSize is fractional on a scaled display.
local size = workspace.CurrentCamera.ViewportSize
return `{math.round(size.X)}x{math.round(size.Y)} {seconds / frames * 1000}`
]]

-- What the simulator reported after setting it (Bridge.setDevice), checked
-- against what was asked: raises unless they agree.
function Smoke.checkSimulation(device: Device?, simulation: Simulation?): Simulation?
	if not device then
		if simulation then
			error(`Studio still simulates {simulation.device} after the simulator was stopped`, 0)
		end
		return nil
	end
	if not simulation or simulation.device ~= device.simulator then
		error(`Studio simulates {if simulation then simulation.device else "no device"}, not {device.simulator}`, 0)
	elseif not string.find(simulation.orientation, device.orientation, 1, true) then
		error(`Studio simulates {simulation.orientation}, not {device.orientation}`, 0)
	elseif simulation.scaling ~= "FitToWindow" then
		error(`Studio scales the device {simulation.scaling}, not FitToWindow`, 0)
	end
	return simulation
end

-- Seconds to one decimal, as the reports keep them.
function Smoke.round(seconds: number): number
	return math.round(seconds * 10) / 10
end
local round = Smoke.round

-- A luminance to three decimals, as the reports keep it.
function Smoke.roundLuminance(luminance: number): number
	return math.round(luminance * 1000) / 1000
end

-- Reads Studio's version into a report and logs it against the pinned one.
function Smoke.readVersion(
	bridge: Bridge,
	report: { studioVersion: string?, studioVersionDrift: boolean, pinnedStudioVersion: string },
	log: (string) -> ()
)
	local version = bridge.studioVersion()
	report.studioVersion = version
	report.studioVersionDrift = version ~= report.pinnedStudioVersion
	log(`Studio {version} (pinned {report.pinnedStudioVersion})`)
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
				Smoke.readVersion(bridge, report, options.log)
			end,
		},
		{
			name = "Open the place in Studio",
			run = function()
				bridge.open(options.placeFile)
				-- A PC: no device a previous run left simulated.
				Smoke.checkSimulation(nil, bridge.setDevice(nil))
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
				local viewport, frame = string.match(ready, "^(%d+x%d+) (%S+)$")
				local milliseconds = tonumber(frame)
				if not viewport or not milliseconds then
					error(`the client returned '{ready}'`, 0)
				end
				report.viewport = viewport
				report.frameMilliseconds = round(milliseconds)
				local shot = bridge.capture(options.screenshotPath)
				report.screenshot = options.screenshotPath
				report.screenshotLuminance = Smoke.roundLuminance(shot.luminance)
				report.screenshotPixels = shot.pixels
				options.log(`frame time {report.frameMilliseconds} ms, luminance {report.screenshotLuminance}`)
				if shot.luminance < Smoke.LUMINANCE_FLOOR then
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
