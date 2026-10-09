-- World: World.execute calls the World method named for each command.

local Events = require("../../../src/core/Events")
local World = require("../../../src/core/World")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	-- A World that records each call as { method, ...arguments }.
	local calls: { { any } } = {}
	local recording: any = setmetatable({}, {
		__index = function(_, method: string)
			return function(...)
				table.insert(calls, { method, ... })
			end
		end,
	})

	local cases: { { any } } = {
		{ { kind = "ShowDialogue", lines = { { speaker = "Amy", text = "Deal." } } }, "showDialogue" },
		{ { kind = "SetObjective", text = "Go" }, "setObjective" },
		{ { kind = "ShowChapterCard", title = "a", subtitle = "b", ending = false }, "showChapterCard" },
		{ { kind = "MoveCharacter", character = "Sam", spot = "Farm" }, "moveCharacter" },
		{ { kind = "TeleportPlayer", spot = "GardenInside" }, "teleportPlayer" },
		{ { kind = "SetPropState", prop = "Machine", state = "advancing" }, "setPropState" },
		{ { kind = "SetLighting", preset = "paradise" }, "setLighting" },
		{ { kind = "SpawnPickups", quest = "chapter9.pick" }, "spawnPickups" },
		{ { kind = "RemovePickup", pickup = "FlowerA" }, "removePickup" },
		{ { kind = "ClearPickups", quest = "chapter9.pick" }, "clearPickups" },
		{ { kind = "OfferTalk", character = "Dad", label = "Explain" }, "offerTalk" },
		{ { kind = "WithdrawTalk", character = "Dad" }, "withdrawTalk" },
		{ { kind = "Wait", seconds = 0.5 }, "wait" },
	}

	describe("World.execute", function()
		it("covers every World command", function()
			local named = {}
			for _, case in cases do
				named[case[1].kind] = true
			end
			for kind in Events.WORLD_COMMANDS do
				expect(named[kind]).toBe(true)
			end
		end)

		for _, case in cases do
			it(`carries out {case[1].kind} with World.{case[2]}`, function()
				table.clear(calls)
				World.execute(recording, case[1])
				expect(#calls).toBe(1)
				expect(calls[1][1]).toBe(case[2])
			end)
		end

		it("passes the arguments in the glossary's order", function()
			table.clear(calls)
			World.execute(recording, { kind = "ShowChapterCard", title = "The end ♥", subtitle = "b", ending = true })
			World.execute(recording, { kind = "MoveCharacter", character = "Sam", spot = "Farm" })
			expect(calls[1]).toEqual({ "showChapterCard", "The end ♥", "b", true :: any })
			expect(calls[2]).toEqual({ "moveCharacter", "Sam", "Farm" })
		end)

		for _, case in
			{
				{ { kind = "Shout" }, "unknown kind Shout" },
				{ { kind = "MoveCharacter", character = "Sam" }, "MoveCharacter.spot must be string" },
				{ { kind = "ShowDialogue", lines = {} }, "ShowDialogue.lines must be lines" },
				{ { kind = "Wait", seconds = 1, extra = true }, "Wait has no field extra" },
			} :: { { any } }
		do
			it(`refuses a malformed World command: {case[2]}`, function()
				table.clear(calls)
				t.expectError(function()
					World.execute(recording, case[1])
				end, `malformed World command: {case[2]}`)
				expect(#calls).toBe(0)
			end)
		end
	end)
end
