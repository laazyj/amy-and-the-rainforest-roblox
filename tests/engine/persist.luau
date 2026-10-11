--!strict
-- Saves (plan sections 2.3 and 4): Persist keeps a fake player's Save in
-- this run's test store through ProfileStore, as a real server would.
--
--   - a player with no Save starts the Story at once, with no Title screen;
--   - Progress is written on Story events, without being asked to;
--   - leaving writes the last Progress and releases the session lock;
--   - a returning player who leaves at the Title screen keeps their Save;
--   - a Save that cannot be loaded in time means playing without saving,
--     and the Save is left as it was;
--   - a returning player is offered the Title screen, and each Title
--     choice (Continue, Play this chapter again, Start again) leads where
--     it should;
--   - BindToClose releases every session lock: a task cannot shut its
--     server down, so the test calls the function Persist.start bound.
--
-- A test player rejoins as a new fake player with the same UserId, so the
-- same Save, once the last one has left and its lock is released.

local Driver = include("tests/engine/_driver.luau")
local FakePlayer = include("tests/engine/_fakeplayer.luau")

local Net = (require :: any)(game:GetService("ReplicatedStorage"):WaitForChild("core"):WaitForChild("Net"))

local world = include("tests/engine/_world.luau").build(false, "persist")
local server = world.StoryHost
local story = world.story
local Persist, Save = world.Persist, world.Save
local play = Driver.new(server, world.CharacterHost)

local USER_ID = -7

-- What each fake player was sent: the remote names, and the ShowTitle payloads.
local sent: { [any]: { string } } = {}
local titles: { [any]: { any } } = {}
server.setSend(function(to, remote: RemoteEvent, ...)
	sent[to] = sent[to] or {}
	table.insert(sent[to], remote.Name)
	if remote.Name == "ShowDialogue" then
		task.defer(server.onDialogueFinished, to)
	elseif remote.Name == "ShowTitle" then
		titles[to] = table.pack(...)
	end
end)

-- Polls `done` every `every` seconds (default 0.2); a poll that reads the
-- store waits longer, to stay within the DataStore read budget.
local function waitFor(what: string, seconds: number, done: () -> boolean, every: number?)
	local started = os.clock()
	while not done() do
		if os.clock() - started > seconds then
			error(`timed out after {seconds} s waiting for {what}`)
		end
		task.wait(every or 0.2)
	end
end

-- The Save in the store, and whether a session holds it.
local function stored(player: any): (any, boolean)
	local data, locked = Persist.stored(player)
	return data and assert(Save.read(story, data)), locked
end

local function join(): any
	local player = FakePlayer.new(world.spawn, USER_ID)
	server.onClientReady(player)
	return player
end

local function leave(player: any)
	server.onPlayerRemoving(player)
	waitFor("the lock to be released", 40, function()
		local _, locked = stored(player)
		return not locked
	end, 2)
end

-- Plays until `questId` is active and the host waits on the player. The
-- player acts only while the host waits on them, as a real one can, so it
-- never plays on into the Quest after `questId` during a Beat.
local function playTo(player: any, questId: string)
	waitFor(questId, 120, function()
		if not server.idle(player) then
			return false
		elseif server.activeQuest(player) == questId then
			return true
		end
		play(player)
		return false
	end)
end

local quests = world.Story.quests(story)
local first, third = quests[1].quest.id, quests[3].quest.id
local chapter2 = story.chapters[2]

describe("Saves", function()
	print(`  store {Persist.storeName()}, player {USER_ID}`)
	local player = join()

	it("starts a player with no Save at the first Chapter card, with no Title screen", function()
		waitFor("the first Quest", 30, function()
			return server.activeQuest(player) == first
		end)
		expect((sent[player] or {})[1]).toBe("ShowChapter")
		expect(table.find(sent[player], "ShowTitle")).toBeNil()
	end)

	it("writes Progress to the store on Story events, unasked", function()
		playTo(player, third)
		waitFor(`a Save at {third} in the store`, 30, function()
			local save, locked = stored(player)
			return locked and save ~= nil and save.progress.quest == third
		end, 2)
		local save = stored(player)
		expect(save.checkpoints[story.chapters[1].id] ~= nil).toBe(true)
		print(`  stored at {third}: {#save.progress.completed} Quests completed`)
	end)

	it("writes the last Progress and releases the session lock on leave", function()
		leave(player)
		local save, locked = stored(player)
		expect(locked).toBe(false)
		expect(save.progress.quest).toBe(third)
	end)

	it("keeps the Save of a returning player who leaves at the Title screen, choosing nothing", function()
		local back = join()
		waitFor("ShowTitle", 30, function()
			return titles[back] ~= nil
		end)
		leave(back)
		local save = stored(back)
		expect(save.progress.quest).toBe(third)
		expect(save.checkpoints[story.chapters[1].id] ~= nil).toBe(true)
	end)

	it("plays without saving when the Save does not load in time, leaving it as it was", function()
		local timeout = Persist.LOAD_TIMEOUT
		Persist.LOAD_TIMEOUT = 0
		local back = join()
		waitFor("the first Quest", 30, function()
			return server.activeQuest(back) == first
		end)
		Persist.LOAD_TIMEOUT = timeout
		expect(titles[back]).toBeNil()
		expect(sent[back][1]).toBe("ShowChapter")
		playTo(back, quests[2].quest.id)
		leave(back)
		expect(stored(back).progress.quest).toBe(third)
	end)

	it("offers a returning player the Title screen; Continue resumes at their Quest", function()
		local back = join()
		waitFor("ShowTitle", 30, function()
			return titles[back] ~= nil
		end)
		local args = titles[back]
		expect(Net.check("ShowTitle", args)).toBe(true)
		expect(args[2]).toBe(true)
		print(`  ShowTitle: {args[1]}, can continue {args[2]}`)
		expect(server.activeQuest(back)).toBeNil()
		server.onTitleChoice(back, "continue")
		expect(server.activeQuest(back)).toBe(third)
		leave(back)
	end)

	it("Play this chapter again resumes at the Chapter's Checkpoint", function()
		local back = join()
		waitFor("ShowTitle", 30, function()
			return titles[back] ~= nil
		end)
		server.onTitleChoice(back, "replay")
		local _, chapter = world.Story.quest(story, third)
		expect(server.activeQuest(back)).toBe(chapter.quests[1].id)
		leave(back)
	end)

	it("Start again begins the Story from a new Save, its first Chapter card first", function()
		local back = join()
		waitFor("ShowTitle", 30, function()
			return titles[back] ~= nil
		end)
		server.onTitleChoice(back, "restart")
		waitFor("the first Quest", 30, function()
			return server.activeQuest(back) == first
		end)
		local after = table.find(sent[back], "ShowTitle") :: number
		expect(sent[back][after + 1]).toBe("ShowChapter")
		leave(back)
		local save = stored(back)
		expect(save.progress.quest).toBe(first)
		expect(save.checkpoints[chapter2.id]).toBeNil()
	end)

	it("ignores a Title choice that was not offered", function()
		local back = join()
		waitFor("ShowTitle", 30, function()
			return titles[back] ~= nil
		end)
		server.onTitleChoice(back, "teleport")
		expect(server.activeQuest(back)).toBeNil()
		titles[back] = nil
		-- the BindToClose test goes on with this player's session open
		server.onTitleChoice(back, "continue")
		expect(server.activeQuest(back)).toBe(first)
		player = back
	end)

	it("releases every session lock on BindToClose", function()
		local _, locked = stored(player)
		expect(locked).toBe(true)
		expect(Persist.close(server.progress)).toBe(true)
		local _, after = stored(player)
		expect(after).toBe(false)
	end)
end)

finish()
