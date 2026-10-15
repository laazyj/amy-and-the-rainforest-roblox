--!strict
-- The live Bridge of smoke.luau: Roblox Studio on macOS, driven through its
-- built-in MCP server. Everything that knows how Studio is launched, what its
-- MCP tools are called and how its window is captured is in this file, so a
-- Studio update that breaks the bridge is fixed here (docs/MAC_RUNNER.md).

local serde = require("@lune/serde")

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Bmp = require("./bmp")
local Mcp = require("./mcp")
local Smoke = require("./smoke")

local Studio = {}

export type ExecResult = { ok: boolean, code: number, stdout: string, stderr: string }

-- What the bridge needs of the machine beyond the tools' shared context
-- (Cli.Context: files, clock, sleep, env, log), so the spec can replace it.
export type System = {
	exec: (program: string, params: { string }) -> ExecResult,
	isFile: (path: string) -> boolean,
	removeFile: (path: string) -> (),
	cwd: string,
	connect: (program: string, clientName: string) -> Mcp.Client,
}

export type Options = {
	ctx: Cli.Context,
	system: System?,
}

local APP = "/Applications/RobloxStudio.app"
-- The app's own launcher only forwards roblox-studio: links, and a place file
-- opened through it lands on the start page. The binary takes the file itself.
local BINARY = `{APP}/Contents/MacOS/RobloxStudio`
-- A stdio MCP server that Studio connects to (on localhost:13469, retrying
-- every 3 seconds) once "Studio as MCP server" is enabled in the Assistant.
local MCP_PROXY = `{APP}/Contents/MacOS/StudioMCP`

local OPEN_TIMEOUT = 90
local PLAY_TIMEOUT = 60
-- For each command the bridge runs: a TCC prompt or a wedged window server
-- would otherwise hold the step until the job's own timeout.
local COMMAND_TIMEOUT = 30
-- The square in the middle of the screenshot whose brightness is measured, in
-- pixels: inside the viewport in Studio's default layout.
local LUMINANCE_SQUARE = "400"

-- Both run with `osascript -l JavaScript` and print JSON.
-- Why this login session cannot render Studio, or null when it can.
local SESSION_SCRIPT = [[
ObjC.import("CoreGraphics");
function run() {
	const session = ObjC.deepUnwrap(ObjC.castRefToObject($.CGSessionCopyCurrentDictionary()));
	if (!session) return JSON.stringify("there is no desktop session here (no window server)");
	if (session.CGSSessionScreenIsLocked) return JSON.stringify("the screen is locked");
	return JSON.stringify(null);
}
]]
-- The id of the largest window of the process `argv[0]`, or null.
local WINDOW_SCRIPT = [[
ObjC.import("CoreGraphics");
function run(argv) {
	const pid = parseInt(argv[0], 10);
	const windows = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionAll, 0)))
		.filter((w) => w.kCGWindowOwnerPID === pid && w.kCGWindowLayer === 0)
		.sort((a, b) => b.kCGWindowBounds.Width * b.kCGWindowBounds.Height - a.kCGWindowBounds.Width * a.kCGWindowBounds.Height);
	return JSON.stringify(windows.length > 0 ? windows[0].kCGWindowNumber : null);
}
]]

-- Runs argv[2..] in its own process group and kills the group after argv[1]
-- seconds, exiting 124 (macOS has no timeout command). A signal becomes a failing exit code: Lune reports a
-- process killed by a signal as having succeeded.
local TIMEOUT_SCRIPT = [[
my $t = shift; my $pid = fork // die "fork: $!";
if (!$pid) { setpgrp; exec @ARGV or die "$ARGV[0]: $!\n" }
$SIG{ALRM} = sub { kill 9, -$pid; print STDERR "timed out after $t seconds\n"; exit 124 };
alarm $t; waitpid $pid, 0; alarm 0;
exit($? & 127 ? 128 + ($? & 127) : $? >> 8)
]]

-- The real machine. Every command but kill is ended after COMMAND_TIMEOUT.
function Studio.liveSystem(): System
	local fs = require("@lune/fs")
	local process = require("@lune/process")
	return {
		exec = function(program, params)
			-- kill cannot hang, and is polled every second while Studio opens.
			return if program == "kill"
				then process.exec(program, params)
				else process.exec("/usr/bin/perl", {
					"-e",
					TIMEOUT_SCRIPT,
					tostring(COMMAND_TIMEOUT),
					program,
					table.unpack(params),
				})
		end,
		isFile = fs.isFile,
		removeFile = fs.removeFile,
		cwd = process.cwd,
		connect = Mcp.connect,
	}
end

-- The Studio version the bridge was last proven on.
function Studio.pinnedVersion(): string
	return (string.gsub(Files.read("tools/studio-playtest/studio-version.txt"), "%s+", ""))
end

-- For the entry points: none has a dry run, since each only drives the local Studio.
function Studio.refuseDryRun(dryRun: boolean)
	if dryRun then
		error("there is no --dry-run: this tool only drives the local Studio", 0)
	end
end

-- For the entry points: writes <out>/report.json, warns of Studio version
-- drift (a GitHub annotation in Actions), and raises unless it passed.
-- `report` is a Smoke.Report or a Playthrough.Report: both have result,
-- failure, durationSeconds and the Studio version fields used here.
function Studio.finish(ctx: Cli.Context, out: string, report: any)
	ctx.writeFile(`{out}/report.json`, serde.encode("json", report, true) .. "\n")
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
end

function Studio.bridge(options: Options): Smoke.Bridge
	local system = options.system or Studio.liveSystem()
	local ctx = options.ctx

	local function exec(program: string, params: { string }): string
		local result = system.exec(program, params)
		if not result.ok then
			local detail = string.gsub(result.stderr .. result.stdout, "%s+$", "")
			error(`{program} failed ({result.code}): {detail}`, 0)
		end
		return (string.gsub(result.stdout, "%s+$", ""))
	end

	local function absolute(path: string): string
		return if string.sub(path, 1, 1) == "/" then path else system.cwd .. path
	end

	local function alive(pid: string): boolean
		return system.exec("kill", { "-0", pid }).ok
	end

	-- Polls `ready` every `interval` seconds; raises what `what` returns after `timeout`.
	local function waitFor(what: () -> string, timeout: number, interval: number, ready: () -> boolean)
		local deadline = ctx.clock() + timeout
		while not ready() do
			if ctx.clock() > deadline then
				error(`{what()} (waited {timeout} seconds)`, 0)
			end
			ctx.sleep(interval)
		end
	end

	-- Studio keeps the switch in its Assistant settings, one file per Roblox user.
	local function mcpEnabled(): boolean
		local dir = `{ctx.env.HOME}/Library/Roblox/AssistantSettings`
		local names: { string } = ctx.listDir(dir) or {}
		for _, name in names do
			local ok, settings = pcall(serde.decode, "json" :: "json", ctx.readFile(`{dir}/{name}`) or "")
			local server = if ok and type(settings) == "table" then settings["mcp-server"] else nil
			if type(server) == "table" and server.enabled == true then
				return true
			end
		end
		return false
	end

	local client: Mcp.Client? = nil
	local studioId: string? = nil
	local windowId: number? = nil -- Studio's window, for capture
	local pid: string? = nil

	local function mcp(): Mcp.Client
		local connected = client or system.connect(MCP_PROXY, "studio-playtest")
		client = connected
		return connected
	end

	local function studioIds(): { string }
		local listed = serde.decode("json", mcp().callTool("list_roblox_studios", {}))
		local ids = {}
		for _, studio in listed.studios do
			table.insert(ids, studio.id)
		end
		return ids
	end

	local function tool(name: string, arguments: { [string]: any }, id: string?): string
		arguments.studio_id = id or studioId or error("no place is open in Studio", 0)
		return mcp().callTool(name, arguments)
	end

	-- "Edit" or "Play", and whether both of Play's DataModels are there yet.
	local function state(): (string, boolean)
		local text = tool("get_studio_state", {})
		local mode = string.match(text, "Current Studio Mode: (%a+)") or error(`unexpected Studio state: {text}`, 0)
		local dataModels = string.match(text, "Available DataModels: ([^\n]*)") or ""
		return mode, string.find(dataModels, "Client") ~= nil and string.find(dataModels, "Server") ~= nil
	end

	local function run(dataModel: Smoke.DataModel, code: string, id: string?): string
		return tool("execute_luau", { datamodel_type = dataModel, code = code }, id)
	end

	local function setPlaying(playing: boolean)
		tool("start_stop_play", { is_start = playing })
		local what = function()
			return `Studio did not {if playing then "start" else "stop"} Play`
		end
		waitFor(what, PLAY_TIMEOUT, 0.5, function()
			local mode, clientAndServer = state()
			return if playing then mode == "Play" and clientAndServer else mode == "Edit"
		end)
	end

	local bridge: Smoke.Bridge = {
		studioVersion = function()
			return exec("plutil", { "-extract", "CFBundleShortVersionString", "raw", `{APP}/Contents/Info.plist` })
		end,

		open = function(placeFile)
			local path = absolute(placeFile)
			if not system.isFile(path) then
				error(`place file not found: {path}`, 0)
			end
			local cannotRender = serde.decode("json", exec("osascript", { "-l", "JavaScript", "-e", SESSION_SCRIPT }))
			if cannotRender then
				error(`{cannotRender}, so Studio would render nothing; see docs/MAC_RUNNER.md`, 0)
			end
			if not mcpEnabled() then
				error(
					"Studio's MCP server is not enabled: in Studio, Assistant -> settings -> MCP Servers -> "
						.. "'Studio as MCP server'; see docs/MAC_RUNNER.md",
					0
				)
			end
			local before = studioIds()
			-- Studio runs in the background and the shell prints its pid; `close`
			-- ends it. caffeinate wakes the display, then keeps it and the Mac
			-- awake for as long as that Studio lives.
			local launched = exec("/bin/sh", {
				"-c",
				'"$0" -task EditFile -localPlaceFile "$1" >/dev/null 2>&1 & pid=$!; '
					.. "caffeinate -u -t 5 >/dev/null 2>&1 & "
					.. 'caffeinate -dis -w "$pid" >/dev/null 2>&1 & echo "$pid"',
				BINARY,
				path,
			})
			pid = launched
			windowId = nil
			ctx.log(`launched Studio (pid {launched}) on {path}`)

			-- What the last probe of a new Studio answered, for the failure.
			local answer = "no new Studio connected to the MCP server; is Studio signed in?"
			local what = function()
				return `Studio did not open the place: {answer}; see docs/MAC_RUNNER.md`
			end
			waitFor(what, OPEN_TIMEOUT, 1, function()
				if not alive(launched) then
					error("Studio exited while starting (an auto-update restarts it); see docs/MAC_RUNNER.md", 0)
				end
				for _, id in studioIds() do
					-- A Studio on its start page answers "Place is not open", and one
					-- still loading the place "Target is not reachable".
					if not table.find(before, id) then
						local ok, err = pcall(run, "Edit" :: Smoke.DataModel, "return true", id)
						if ok then
							studioId = id
							return true
						end
						answer = tostring(err)
					end
				end
				return false
			end)
		end,

		startPlay = function()
			setPlaying(true)
		end,

		stopPlay = function()
			setPlaying(false)
		end,

		run = run,

		consoleOutput = function()
			return tool("get_console_output", {})
		end,

		capture = function(path)
			local studioPid = pid or error("Studio is not running", 0)
			local function lookUp(): number
				return serde.decode("json", exec("osascript", { "-l", "JavaScript", "-e", WINDOW_SCRIPT, studioPid }))
					or error("Studio has no window to capture", 0)
			end
			-- The window is looked up once per Studio, and again if it has gone.
			windowId = windowId or lookUp()
			-- -l: only Studio's window, whatever else is on screen; -o: no shadow.
			local arguments = function()
				return { "-x", "-o", "-l", tostring(windowId), path }
			end
			if not system.exec("screencapture", arguments()).ok then
				windowId = lookUp()
				exec("screencapture", arguments())
			end
			if not system.isFile(path) then
				error("screencapture wrote no image; does the runner have Screen Recording permission?", 0)
			end
			local middle = `{path}.middle.bmp`
			exec("sips", { "-c", LUMINANCE_SQUARE, LUMINANCE_SQUARE, "-s", "format", "bmp", path, "--out", middle })
			local luminance = Bmp.luminance(ctx.readFile(middle) or error("sips wrote no image", 0))
			system.removeFile(middle)
			return luminance
		end,

		setDevice = function(device)
			local lines = { 'local s = game:GetService("StudioDeviceSimulatorService")' }
			if device then
				local orientation = if device.orientation == "Portrait" then "Portrait" else "LandscapeRight"
				table.insert(lines, `s:SetDeviceAsync({string.format("%q", device.simulator)})`)
				table.insert(lines, `s:SetOrientationAsync(Enum.ScreenOrientation.{orientation})`)
				-- The whole device in the viewport: at physical size a tablet
				-- overflows Studio's window and only part of it is captured.
				table.insert(lines, "s:SetScalingModeAsync(Enum.DeviceSimulatorScalingMode.FitToWindow)")
			else
				table.insert(lines, "pcall(s.StopSimulationAsync, s) -- it raises when no device is active")
			end
			table.insert(lines, "return true")
			run("Edit", table.concat(lines, "\n"))
		end,

		press = function(key)
			tool(
				"user_keyboard_input",
				{ datamodel_type = "Client", actions = { { action = "keyPress", key_code = key } } }
			)
		end,

		walkTo = function(position)
			tool("character_navigation", { datamodel_type = "Client", x = position.x, y = position.y, z = position.z })
		end,

		insertAsset = function(assetId)
			local result = serde.decode(
				"json",
				tool("insert_asset", { assetId = assetId, assetType = "Model", parentPath = "game.ServerStorage" })
			)
			local inserted = result.insertedInstances and result.insertedInstances[1]
			if result.status ~= "success" or not inserted then
				error(`Studio did not insert asset {assetId}: {serde.encode("json", result)}`, 0)
			end
			return inserted.fullPath
		end,

		close = function()
			if client then
				client.close()
				client = nil
			end
			local studioPid = pid
			if studioPid then
				pid = nil
				-- Studio answers a polite quit with a "Save changes?" dialog that
				-- nothing here can dismiss, and the place is a throwaway build.
				system.exec("kill", { "-9", studioPid })
			end
		end,
	}
	return bridge
end

return Studio
