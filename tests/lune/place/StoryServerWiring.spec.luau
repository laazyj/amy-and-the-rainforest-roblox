--[[
	The wiring a real player depends on, which the golden walkthrough
	(tests/engine/walkthrough.luau) cannot see: it requires the Server module
	itself, replaces send and calls the handlers directly. Without these
	checks the game could lose a connection or stop starting while every
	tier stays green. StoryServer needs the engine, so its source is read as
	text, as StoryHooks.spec does, and compared with whitespace collapsed.
	Temporary: the Checkpoint B restructure makes the wiring data the tests
	can drive, and this spec goes with it.
]]

local bootstrap = require("../bootstrap")

local SCRIPT = "src/ServerScriptService/StoryServer/init.server.lua"
local MODULE = "src/ServerScriptService/StoryServer/Server.lua"

local function collapsed(text: string): string
	return (string.gsub(text, "%s+", " "))
end

local scriptSource = collapsed(bootstrap.readSource(SCRIPT))
local moduleSource = collapsed(bootstrap.readSource(MODULE))

-- Each piece of wiring, exactly as written in Server.lua.
local WIRING: { [string]: string } = {
	["send delivers over the remote by default"] = "local send = function(player, remote, ...)\n\tremote:FireClient(player, ...)\nend",
	["DialogueFinished reaches its handler"] = "DialogueFinished.OnServerEvent:Connect(onDialogueFinished)",
	["ClientReady reaches its handler"] = "ClientReady.OnServerEvent:Connect(onClientReady)",
	["every talk prompt reaches its handler"] = "prompt.Triggered:Connect(function(player)\n\t\tonTalkPromptTriggered(npcId, player)\n\tend)",
	["a Zone touch completes a reach Quest"] = "zonePart.Touched:Connect(function(hit)",
	["a Pickup touch is handled"] = "part.Touched:Connect(function(hit)",
	["a joining player gets story state"] = "Players.PlayerAdded:Connect(initPlayer)",
}

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("StoryServer wiring", function()
		it("the StoryServer Script starts the Server module", function()
			expect(string.find(scriptSource, " require(script.Server) ", 1, true)).never.toBeNil()
		end)

		it("calls FireClient in one place only, inside send", function()
			local _, count = string.gsub(moduleSource, ":FireClient%(", "")
			expect(count).toBe(1)
		end)

		for label, code in WIRING do
			it(label, function()
				expect(string.find(moduleSource, collapsed(code), 1, true)).never.toBeNil()
			end)
		end
	end)
end
