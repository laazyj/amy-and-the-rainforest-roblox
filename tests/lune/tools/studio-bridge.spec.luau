local F = require("../fixtures/opencloud")
local Studio = require("../../../tools/studio-playtest/studio")

local serde = require("@lune/serde")

local SETTINGS_DIR = "/home/Library/Roblox/AssistantSettings"
local NEW_STUDIO = "studio-new"
local LAYOUT_KEY = "LayoutSettings.Docking.3.edit_"

-- Studio's saved dock layout, cut down from a real one: Explorer docked on
-- the right, the Toolbox on the left, the Tag Editor closed, the Script
-- Analysis floating, and the place's own tab in the document area.
local DOCK_LAYOUT = [[
<?xml version="1.0" encoding="UTF-8"?>
<DockPanelLayouts xmlns:Qtitan="https://www.devmachines.com/qt/qtitan" type="layoutPanel" version="1.3">
    <Panels Count="8">
        <Panel ID="Layout1" Type="4" DockCX="-1" DockCY="-1" Horizontal="False">
            <Panels Count="1">
                <Panel ID="Layout23"/>
            </Panels>
        </Panel>
        <Panel ID="Layout23" Type="5" DockCX="-1" DockCY="-1">
            <Panels Count="1">
                <Panel ID="ideDocDocumentPanel"/>
            </Panels>
        </Panel>
        <Panel ID="Layout24" Type="2" DockCX="-1" DockCY="-1">
            <Panels Count="1">
                <Panel ID="rplg_sabuiltin_ExplorerPlugin.rbxm_ExplorerPlugin"/>
            </Panels>
        </Panel>
        <Panel ID="Layout27" Type="2" DockCX="-1" DockCY="-1">
            <Panels Count="1">
                <Panel ID="edit_builtin_Toolbox.rbxm_Toolbox"/>
            </Panels>
        </Panel>
        <Panel ID="rplg_sabuiltin_ExplorerPlugin.rbxm_ExplorerPlugin" Type="Qtitan::DockWidgetPanel" DockCX="-1" DockCY="-1" Active="True">
            <Layouts>
                <DockingLayout ID="Layout24"/>
                <FloatingLayout ID=""/>
                <LastLayout ID="Layout24"/>
            </Layouts>
        </Panel>
        <Panel ID="ideDocDocumentPanel" Type="Qtitan::DockDocumentPanel" DockCX="547" DockCY="456" Active="True">
            <Layouts>
                <DockingLayout ID="Layout23"/>
                <FloatingLayout ID=""/>
                <LastLayout ID="Layout23"/>
            </Layouts>
        </Panel>
        <Panel ID="edit_builtin_TagEditor.rbxm_TagEditor" Type="Qtitan::DockWidgetPanel" DockCX="-1" DockCY="-1">
            <Layouts>
                <DockingLayout ID=""/>
                <FloatingLayout ID=""/>
                <LastLayout ID=""/>
            </Layouts>
        </Panel>
        <Panel ID="scriptAnalysis" Type="Qtitan::DockWidgetPanel" DockCX="-1" DockCY="-1" Active="True">
            <Layouts>
                <DockingLayout ID=""/>
                <FloatingLayout ID="Layout40"/>
                <LastLayout ID="Layout40"/>
            </Layouts>
        </Panel>
        <Panel ID="edit_builtin_Toolbox.rbxm_Toolbox" Type="Qtitan::DockWidgetPanel" DockCX="-1" DockCY="-1" Active="True">
            <Layouts>
                <DockingLayout ID="Layout27"/>
                <FloatingLayout ID=""/>
                <LastLayout ID="Layout27"/>
            </Layouts>
        </Panel>
    </Panels>
    <Windows Count="0"/>
    <TopLayout ID="Layout0"/>
    <Client ID="Layout1"/>
</DockPanelLayouts>
]]

-- The same, with the Toolbox missing from the tab group it says it is in.
local BROKEN_LAYOUT = string.gsub(DOCK_LAYOUT, '%s*<Panel ID="edit_builtin_Toolbox.rbxm_Toolbox"/>', "", 1)

-- The ids a layout panel lists, and a panel's three layouts.
local function listed(xml: string, id: string): { string }
	local list = string.match(xml, `<Panel ID="{id}" [^>]*>%s*(<Panels.-</?Panels>)`) or ""
	local ids = {}
	for child in string.gmatch(list, '<Panel ID="([^"]+)"/>') do
		table.insert(ids, child)
	end
	return ids
end

local function layoutsOf(xml: string, id: string): { [string]: string }
	local at = string.find(xml, `<Panel ID="{id}" Type=`, 1, true)
	local block = string.match(xml, "<Layouts>(.-)</Layouts>", at) or ""
	local layouts = {}
	for _, kind in { "DockingLayout", "FloatingLayout", "LastLayout" } do
		layouts[kind] = string.match(block, `<{kind} ID="([^"]*)"/>`)
	end
	return layouts
end

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
	-- Each command as the bridge ran it, in order.
	local commands: { { string } } = {}
	local probes = 0
	local launched = false
	local system: Studio.System = {
		exec = function(program, params)
			table.insert(commands, { program, table.unpack(params) })
			local stdout, ok = "", true
			if program == "osascript" and string.find(params[4], "NSUserDefaults", 1, true) then
				stdout = serde.encode("json", {
					layouts = m.layouts or { [LAYOUT_KEY] = DOCK_LAYOUT },
					screen = { width = 1920, height = 1200 },
				})
			elseif program == "sysctl" then
				stdout = if m.notVirtual then "0\n" else "1\n"
			elseif program == "osascript" then
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
						return if m.answer then m.answer(arguments.code) else "true"
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
			commands = commands,
			log = mock.log,
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

		t.it("reads the device simulator back after setting or stopping it", function()
			local bridge = fakeMac({
				answer = function(code: string)
					return if string.find(code, "SetDeviceAsync", 1, true)
						then '{"device":"iphone_16","orientation":"LandscapeRight","scaling":"FitToWindow","width":852,"height":393}'
						elseif string.find(code, "StopSimulationAsync", 1, true) then "null"
						else "true"
				end,
			})
			bridge.open("build/Place.rbxl")
			local simulation = bridge.setDevice({ simulator = "iphone_16", orientation = "Landscape" })
			t.expect(simulation).toEqual({
				device = "iphone_16",
				orientation = "LandscapeRight",
				scaling = "FitToWindow",
				width = 852,
				height = 393,
			})
			t.expect(bridge.setDevice(nil)).toBeNil()
		end)

		t.it("moves every docked panel into the first one's tab group", function()
			local xml, moved = Studio.dockLayout(DOCK_LAYOUT)
			t.expect(moved).toEqual({ "edit_builtin_Toolbox.rbxm_Toolbox" })
			t.expect(listed(xml, "Layout24")).toEqual({
				"rplg_sabuiltin_ExplorerPlugin.rbxm_ExplorerPlugin",
				"edit_builtin_Toolbox.rbxm_Toolbox",
			})
			t.expect(
				string.find(
					xml,
					'<Panel ID="Layout27" Type="2" DockCX="-1" DockCY="-1">\n            <Panels Count="0"/>',
					1,
					true
				)
			).never
				.toBeNil()
			t.expect(layoutsOf(xml, "edit_builtin_Toolbox.rbxm_Toolbox")).toEqual({
				DockingLayout = "Layout24",
				FloatingLayout = "",
				LastLayout = "Layout24",
			})
			-- The place's tab, a closed panel and a floating one stay as they were.
			t.expect(listed(xml, "Layout23")).toEqual({ "ideDocDocumentPanel" })
			for _, id in { "ideDocDocumentPanel", "edit_builtin_TagEditor.rbxm_TagEditor", "scriptAnalysis" } do
				t.expect(layoutsOf(xml, id)).toEqual(layoutsOf(DOCK_LAYOUT, id))
			end
			-- Again, nothing is left to move.
			local again, movedAgain = Studio.dockLayout(xml)
			t.expect(movedAgain).toEqual({})
			t.expect(again).toBe(xml)
		end)

		t.it("refuses a dock layout whose tab group does not list its panel", function()
			t.expectError(function()
				Studio.dockLayout(BROKEN_LAYOUT)
			end, "Layout27 does not list edit_builtin_Toolbox.rbxm_Toolbox")
		end)

		t.it("writes Studio's window maximized as Qt's saveGeometry does", function()
			local bytes = Studio.windowGeometry(1920, 1200)
			t.expect({ string.unpack(">I4I2I2i4i4i4i4i4i4i4i4i4BBi4i4i4i4i4", bytes) }).toEqual({
				0x01D9D0CB,
				3,
				0,
				0,
				0,
				1919,
				1199,
				0,
				0,
				1919,
				1199,
				0,
				2,
				0,
				1920,
				0,
				0,
				1919,
				1199,
				67,
			})
		end)

		t.it("frames the viewport before it launches Studio", function()
			local bridge, machine = fakeMac()
			bridge.open("build/Place.rbxl")
			local writes, launchedAt = {}, nil
			for i, command in machine.commands do
				if command[1] == "defaults" then
					t.expect(launchedAt).toBeNil()
					writes[command[4]] = command[6]
				elseif command[1] == "/bin/sh" then
					launchedAt = i
				end
			end
			t.expect(launchedAt).never.toBeNil()
			t.expect(writes["LayoutSettings.window_geometry_ribbon"])
				.toBe(Studio.hex(Studio.windowGeometry(1920, 1200)))
			t.expect(writes[LAYOUT_KEY]).toBe(Studio.hex((Studio.dockLayout(DOCK_LAYOUT))))
		end)

		t.it("leaves Studio's panels and window alone outside a virtual machine", function()
			local bridge, machine = fakeMac({ notVirtual = true })
			bridge.open("build/Place.rbxl")
			for _, command in machine.commands do
				t.expect(command[1]).never.toBe("defaults")
			end
			t.expect(table.concat(machine.log, "\n")).toContain("not a virtual machine")
		end)

		t.it("writes no layout when there is nothing to move", function()
			local bridge, machine = fakeMac({ layouts = { [LAYOUT_KEY] = (Studio.dockLayout(DOCK_LAYOUT)) } })
			bridge.open("build/Place.rbxl")
			for _, command in machine.commands do
				t.expect(command[1] == "defaults" and command[4] == LAYOUT_KEY).toBe(false)
			end
		end)

		t.it("still opens the place, with a warning, when Studio's layout is not what it expects", function()
			local bridge, machine = fakeMac({ layouts = { [LAYOUT_KEY] = BROKEN_LAYOUT } })
			bridge.open("build/Place.rbxl")
			t.expect(table.concat(machine.log, "\n")).toContain(
				"warning: Studio's panels and window were left as they are: Layout27 does not list edit_builtin_Toolbox.rbxm_Toolbox"
			)
		end)

		t.it("ends only the Studio it launched", function()
			local bridge, machine = fakeMac()
			bridge.open("build/Place.rbxl")
			bridge.close()
			t.expect(machine.killed).toEqual({ "4242" })
		end)
	end)
end
