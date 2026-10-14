--!strict
-- Analytics (plan section 2.3): on Dev, as built, the server logs each
-- Story event a player raises under its own name, and their visit's end
-- as SessionEnded, without an error. A Luau Execution task has no real
-- Player, and a custom event needs one, so the adapter's real call to
-- AnalyticsService is made for real players only; this test checks the
-- service is there, that logging for a fake player is a quiet no-op, and
-- what the adapter logged (Analytics.logged), which is what it would send.

local Driver = include("tests/engine/_driver.luau")
local FakePlayer = include("tests/engine/_fakeplayer.luau")

local world = include("tests/engine/_world.luau").build(false, "analytics")
local server, Analytics = world.StoryHost, world.Analytics
local play = Driver.new(server, world.CharacterHost)

server.setSend(function(to, remote: RemoteEvent)
	if remote.Name == "ShowDialogue" then
		task.defer(server.onDialogueFinished, to)
	end
end)

-- The names logged for `player`, in order.
local function namesFor(player: any): { string }
	local names = {}
	for _, entry in Analytics.logged do
		if entry.player == player then
			table.insert(names, entry.logged.name)
		end
	end
	return names
end

local quests = world.Story.quests(world.story)
local second = quests[2].quest.id

describe("analytics", function()
	it("reaches AnalyticsService's custom events on this server", function()
		local service = game:GetService("AnalyticsService")
		expect(typeof(service.LogCustomEvent)).toBe("function")
	end)

	local player = FakePlayer.new(world.spawn, -15)

	it("logs the Story events a player raises, under their own names, without an error", function()
		local ok, why = pcall(function()
			server.onClientReady(player)
			local started = os.clock()
			while server.activeQuest(player) ~= second do
				assert(os.clock() - started < 60, `timed out waiting for {second}`)
				if server.idle(player) then
					play(player)
				end
				task.wait(0.2)
			end
		end)
		expect(ok).toBe(true)
		if not ok then
			error(why)
		end
		local names = namesFor(player)
		print(`  logged: {table.concat(names, ", ")}`)
		for _, name in { "ChapterStarted", "QuestStarted", "QuestCompleted" } do
			expect(table.find(names, name) ~= nil).toBe(true)
		end
		local first: any = nil
		for _, entry in Analytics.logged do
			if entry.player == player and entry.logged.name == "QuestStarted" then
				first = entry.logged
				break
			end
		end
		expect(first.fields[1]).toBe(quests[1].quest.id)
	end)

	it("logs SessionEnded with the visit's length when the player leaves", function()
		server.onPlayerRemoving(player)
		local last = Analytics.logged[#Analytics.logged]
		expect(last.player).toBe(player)
		expect(last.logged.name).toBe("SessionEnded")
		expect(last.logged.value >= 0).toBe(true)
		print(`  SessionEnded after {last.logged.value} s`)
	end)
end)

finish()
