--[[
	The wiring a real player depends on, which the engine walkthrough
	(tests/engine/walkthrough.luau) cannot see: it starts StoryHost itself,
	replaces send and calls the handlers directly. Without these checks the
	game could lose a connection or stop starting while every tier stays
	green. The adapters need the engine, so their source is read as text and
	compared with whitespace collapsed.
]]

local Net = require("../../../src/core/Net")
local bootstrap = require("../bootstrap")
local fs = require("@lune/fs")

local function collapsed(text: string): string
	return (string.gsub(text, "%s+", " "))
end

local sources: { [string]: string } = {}

-- A file's code, comments removed, whitespace collapsed.
local function source(path: string): string
	if not sources[path] then
		local code = string.gsub(bootstrap.readSource(path), "%-%-%[%[.-%]%]", "")
		sources[path] = collapsed((string.gsub(code, "%-%-[^\n]*", "")))
	end
	return sources[path]
end

local SERVER = "src/server"

-- Each piece of wiring, exactly as written, by the file it is in.
local WIRING: { { file: string, label: string, code: string } } = {
	{
		file = "StoryHost.luau",
		label = "send delivers over the remote by default",
		code = "local send = function(player: any, remote: RemoteEvent, ...: any)\n\tremote:FireClient(player, ...)\nend",
	},
	{
		file = "StoryHost.luau",
		label = "a joining player gets a session",
		code = "Players.PlayerAdded:Connect(initPlayer)",
	},
	{
		file = "StoryHost.luau",
		label = "a leaving player's session ends",
		code = "Players.PlayerRemoving:Connect(removePlayer)",
	},
	{
		file = "StoryHost.luau",
		label = "talk prompts and Zones are connected to the host",
		code = "PromptBridge.connect(CharacterHost.prompts(), zones, StoryHost.handle, playersToPoll)",
	},
	{
		file = "StoryHost.luau",
		label = "a Pickup touch reaches the host as TouchedPickup",
		code = 'StoryHost.handle(player, { kind = "TouchedPickup", pickup = pickup })',
	},
	{
		file = "PromptBridge.luau",
		label = "every talk prompt reaches its handler",
		code = "prompt.Triggered:Connect(function(player)\n\tPromptBridge.onTalkPromptTriggered(character, player)\nend)",
	},
	{
		file = "PromptBridge.luau",
		label = "a Zone touch is EnteredZone",
		code = 'part.Touched:Connect(function(hit)\n\tlocal player = hit.Parent and Players:GetPlayerFromCharacter(hit.Parent)\n\tif player then\n\thandle(player, { kind = "EnteredZone", zone = zone })',
	},
	{
		file = "PromptBridge.luau",
		label = "the Zone poll raises EnteredZone for a Zone the player is inside",
		code = 'if inside(part, root) then\n\tlocal event: Events.PlayerEvent = { kind = "EnteredZone", zone = zone }\n\ttask.spawn(handle, player, event)',
	},
	{
		file = "PickupHost.luau",
		label = "a Pickup touch is handled",
		code = "part.Touched:Connect(function(hit)",
	},
}

-- The adapter files of src/server (its Dev folder is checked on its own).
local serverFiles = {}
for _, file in fs.readDir(`{bootstrap.REPO_ROOT}/{SERVER}`) do
	if string.match(file, "%.luau$") then
		table.insert(serverFiles, file)
	end
end
table.sort(serverFiles)

-- Every Script in src/server, and the one thing it does.
local SCRIPTS: { [string]: string } = {
	["StoryServer.server.luau"] = "require(script.Parent.StoryHost).start()",
	["SceneServer.server.luau"] = "require(script.Parent.SceneBuilder).build()",
}

local CLIENT = "src/client/StoryClient.client.luau"

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("server wiring", function()
		for _, file in serverFiles do
			if string.match(file, "%.server%.luau$") then
				it(`{file} is thin: it only {SCRIPTS[file] or "(not listed)"}`, function()
					expect(source(`{SERVER}/{file}`)).toBe(` {SCRIPTS[file]} `)
				end)
			end
		end

		it("Dev/DevServer.server.luau is thin: it only starts the Dev shortcuts", function()
			expect(source(`{SERVER}/Dev/DevServer.server.luau`)).toBe(" require(script.Parent.DevShortcuts).start() ")
		end)

		it("calls FireClient in one place only, inside send", function()
			local count = 0
			for _, file in serverFiles do
				local _, found = string.gsub(source(`{SERVER}/{file}`), ":FireClient%(", "")
				count += found
			end
			expect(count).toBe(1)
		end)

		for _, wire in WIRING do
			it(wire.label, function()
				expect(source(`{SERVER}/{wire.file}`)).toContain(collapsed(wire.code))
			end)
		end

		for name, remote in Net.REMOTES do
			if remote.direction == "toServer" then
				it(`hands {name} from the client, payload checked, to StoryHost.on{name}`, function()
					expect(source(`{SERVER}/StoryHost.luau`)).toContain(
						`made.{name}.OnServerEvent:Connect(fromClient("{name}", StoryHost.on{name}))`
					)
				end)
				it(`has the client send {name}`, function()
					expect(source(CLIENT)).toContain(`{name}:FireServer()`)
				end)
			else
				it(`has the client render {name}, payload checked`, function()
					expect(source(CLIENT)).toContain(`{name}.OnClientEvent:Connect(Net.guard("{name}", `)
				end)
			end
		end
	end)
end
