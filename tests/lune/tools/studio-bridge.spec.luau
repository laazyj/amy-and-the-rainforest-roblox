local F = require("../fixtures/opencloud")
local Studio = require("../../../tools/studio-playtest/studio")

local serde = require("@lune/serde")

local SETTINGS_DIR = "/home/Library/Roblox/AssistantSettings"
local NEW_STUDIO = "studio-new"

-- A Mac where everything works: a desktop session, the MCP server enabled,
-- and a Studio that opens the place. `machine` changes one thing.
local function fakeMac(machine: { [string]: any }?)
	local m: { [string]: any } = machine or {}
	local files: { [string]: string } = { ["/work/build/Place.rbxl"] = "" }
	if m.settings ~= false then
		files[`{SETTINGS_DIR}/1.json`] = m.settings or '{"mcp-server": {"enabled": true}}'
	end
	local mock = F.mock({ args = {}, env = { HOME = "/home" }, files = files })
	local now = 0
	mock.ctx.clock = function()
		return now
	end
	mock.ctx.sleep = function(seconds)
		now += seconds
	end

	local killed: { string } = {}
	local probes = 0
	local launched = false
	local system: Studio.System = {
		exec = function(program, params)
			local stdout, ok = "", true
			if program == "osascript" then
				stdout = serde.encode("json", m.cannotRender :: any)
			elseif program == "/bin/sh" then
				launched = true
				stdout = "4242\n"
			elseif program == "kill" and params[1] == "-0" then
				ok = not m.exitsWhileStarting
			elseif program == "kill" then
				table.insert(killed, params[2])
			end
			return { ok = ok, code = if ok then 0 else 1, stdout = stdout, stderr = "" }
		end,
		isFile = function(path)
			return files[path] ~= nil
		end,
		removeFile = function(path)
			files[path] = nil
		end,
		cwd = "/work/",
		connect = function()
			return {
				callTool = function(name, arguments)
					if name == "list_roblox_studios" then
						local studios = { { id = "studio-old" } }
						if launched then
							table.insert(studios, { id = NEW_STUDIO })
						end
						return serde.encode("json", { studios = studios })
					elseif name == "execute_luau" then
						probes += 1
						assert(arguments.studio_id == NEW_STUDIO, "only the Studio the bridge launched is used")
						if probes <= (m.unreachableProbes or 0) then
							error(
								"execute_luau: Target is not reachable (createExecuteLuauBridge_loadCodeAsync, Edit)",
								0
							)
						end
						return "true"
					end
					return ""
				end,
				close = function() end,
			}
		end,
	}
	return Studio.bridge({ ctx = mock.ctx, system = system }),
		{
			killed = killed,
			probes = function()
				return probes
			end,
		}
end

return function(t: any)
	t.describe("studio-playtest bridge", function()
		t.it("refuses at once when the session cannot render", function()
			local bridge = fakeMac({ cannotRender = "the screen is locked" })
			t.expectError(function()
				bridge.open("build/Place.rbxl")
			end, "the screen is locked, so Studio would render nothing; see docs/MAC_RUNNER.md")
		end)

		t.it("refuses at once when Studio's MCP server is not enabled", function()
			for _, settings in { '{"mcp-server": {"enabled": false}}', false } :: { any } do
				local bridge = fakeMac({ settings = settings })
				t.expectError(function()
					bridge.open("build/Place.rbxl")
				end, "Studio's MCP server is not enabled")
			end
		end)

		t.it("fails as soon as the Studio it launched exits", function()
			local bridge = fakeMac({ exitsWhileStarting = true })
			t.expectError(function()
				bridge.open("build/Place.rbxl")
			end, "Studio exited while starting")
		end)

		t.it("waits until the new Studio runs Luau, not only until it is listed", function()
			local bridge, machine = fakeMac({ unreachableProbes = 3 })
			bridge.open("build/Place.rbxl")
			t.expect(machine.probes()).toBe(4)
			t.expect(bridge.run("Edit", "return game.Name")).toBe("true")
		end)

		t.it("says what the new Studio last answered when it never becomes ready", function()
			local bridge = fakeMac({ unreachableProbes = 1000 })
			t.expectError(function()
				bridge.open("build/Place.rbxl")
			end, "Studio did not open the place: execute_luau: Target is not reachable")
		end)

		t.it("ends only the Studio it launched", function()
			local bridge, machine = fakeMac()
			bridge.open("build/Place.rbxl")
			bridge.close()
			t.expect(machine.killed).toEqual({ "4242" })
		end)
	end)
end
