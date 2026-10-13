--!strict
-- The Pause screen holds the Story on the server too (plan section 2.3):
-- a player who pauses during the first Chapter card's Wait is sent nothing
-- more until they resume, and then the Story goes on where it was. A fresh
-- player never pauses, so the golden file has none of this.

local world = include("tests/engine/_world.luau").build(false, "pause")
local server = world.StoryHost
local FakePlayer = include("tests/engine/_fakeplayer.luau")

local sent: { string } = {}
server.setSend(function(_, remote: RemoteEvent)
	table.insert(sent, remote.Name)
end)

describe("the Pause screen on the server", function()
	local player = FakePlayer.new(world.spawn, -21)

	it("holds the first Chapter card's Wait while the player has paused, and goes on after", function()
		server.onClientReady(player)
		local started = os.clock()
		while #sent == 0 do
			assert(os.clock() - started < 30, "timed out waiting for the first Chapter card")
			task.wait(0.05)
		end
		expect(sent[1]).toBe("ShowChapter")
		server.onSetPaused(player, true)
		task.wait(6) -- the card's Wait is 3.2 s
		print(`  paused for 6 s: sent {table.concat(sent, ", ")}`)
		expect(#sent).toBe(1)
		server.onSetPaused(player, false)
		started = os.clock()
		while not table.find(sent, "SetObjective") do
			assert(os.clock() - started < 10, "the Story did not go on after resuming")
			task.wait(0.05)
		end
		print(`  resumed: sent {table.concat(sent, ", ")}`)
		expect(table.find(sent, "SetObjective") ~= nil).toBe(true)
	end)

	server.onPlayerRemoving(player)
end)

finish()
