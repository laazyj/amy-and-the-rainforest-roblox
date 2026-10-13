--!strict
-- The live Bridge of smoke.luau: Roblox Studio on macOS, driven through its
-- built-in MCP server. Everything that knows how Studio is launched, what its
-- MCP tools are called and how its window is captured is in this file, so a
-- Studio update that breaks the bridge is fixed here (docs/MAC_RUNNER.md).

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local Bmp = require("./bmp")
local Mcp = require("./mcp")
local Smoke = require("./smoke")

local Studio = {}

local APP = "/Applications/RobloxStudio.app"
-- The app's own launcher only forwards roblox-studio: links, and a place file
-- opened through it lands on the start page. The binary takes the file itself.
local BINARY = `{APP}/Contents/MacOS/RobloxStudio`
-- A stdio MCP server that Studio connects to (on localhost:13469, retrying
-- every 3 seconds) once "Studio as MCP server" is enabled in the Assistant.
local MCP_PROXY = `{APP}/Contents/MacOS/StudioMCP`

local OPEN_TIMEOUT = 90
local PLAY_TIMEOUT = 60
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

local function exec(program: string, params: { string }): string
	local result = process.exec(program, params)
	if not result.ok then
		local detail = string.gsub(result.stderr .. result.stdout, "%s+$", "")
		error(`{program} failed ({result.code}): {detail}`, 0)
	end
	return (string.gsub(result.stdout, "%s+$", ""))
end

local function absolute(path: string): string
	return if string.sub(path, 1, 1) == "/" then path else process.cwd .. path
end

local function alive(pid: string): boolean
	return process.exec("kill", { "-0", pid }).ok
end

-- Polls `ready` every `interval` seconds; raises what `what` returns after `timeout`.
local function waitFor(what: () -> string, timeout: number, interval: number, ready: () -> boolean)
	local deadline = os.clock() + timeout
	while not ready() do
		if os.clock() > deadline then
			error(`{what()} (waited {timeout} seconds)`, 0)
		end
		task.wait(interval)
	end
end

-- Studio keeps the switch in its Assistant settings, one file per Roblox user.
local function mcpEnabled(): boolean
	local dir = `{process.env.HOME}/Library/Roblox/AssistantSettings`
	local names: { string } = if fs.isDir(dir) then fs.readDir(dir) else {}
	for _, name in names do
		local ok, settings = pcall(serde.decode, "json" :: "json", fs.readFile(`{dir}/{name}`))
		local server = if ok and type(settings) == "table" then settings["mcp-server"] else nil
		if type(server) == "table" and server.enabled == true then
			return true
		end
	end
	return false
end

local function version(): string
	return exec("plutil", { "-extract", "CFBundleShortVersionString", "raw", `{APP}/Contents/Info.plist` })
end

function Studio.bridge(log: (string) -> ()): Smoke.Bridge
	local client: Mcp.Client? = nil
	local studioId: string? = nil
	local pid: string? = nil

	local function mcp(): Mcp.Client
		local connected = client or Mcp.connect(MCP_PROXY, "studio-playtest")
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
		studioVersion = version,

		open = function(placeFile)
			local path = absolute(placeFile)
			if not fs.isFile(path) then
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
			log(`launched Studio (pid {launched}) on {path}`)

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
			local windowId =
				serde.decode("json", exec("osascript", { "-l", "JavaScript", "-e", WINDOW_SCRIPT, studioPid }))
			if not windowId then
				error("Studio has no window to capture", 0)
			end
			-- -l: only Studio's window, whatever else is on screen; -o: no shadow.
			exec("screencapture", { "-x", "-o", "-l", tostring(windowId), path })
			if not fs.isFile(path) then
				error("screencapture wrote no image; does the runner have Screen Recording permission?", 0)
			end
			local middle = `{path}.middle.bmp`
			exec("sips", { "-c", LUMINANCE_SQUARE, LUMINANCE_SQUARE, "-s", "format", "bmp", path, "--out", middle })
			local luminance = Bmp.luminance(fs.readFile(middle))
			fs.removeFile(middle)
			return luminance
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
				process.exec("kill", { "-9", studioPid })
			end
		end,
	}
	return bridge
end

return Studio
