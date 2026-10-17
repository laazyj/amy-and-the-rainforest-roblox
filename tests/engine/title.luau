--!strict
-- The Dev shortcut /title (brief mac-003, Must A1): mid-Story, the Title
-- screen is offered at the player's current Progress as to a returning
-- player (ShowTitle), the Story waits for the Title choice, and Continue
-- carries on at the same Quest.
--
--   jumped to Chapter Three with "/chapter 3", the player asks for /title;
--   ShowTitle offers Chapter Three with Continue;
--   while it is offered, the Player events of the Quest change nothing;
--   Continue resumes at the Quest the player was at, and it plays on.

local Driver = include("tests/engine/_driver.luau")
local FakePlayer = include("tests/engine/_fakeplayer.luau")

local Net = (require :: any)(game:GetService("ReplicatedStorage"):WaitForChild("core"):WaitForChild("Net"))

local world = include("tests/engine/_world.luau").build(false, "title")
local server = world.StoryHost
local story = world.story
local play = Driver.new(server, world.CharacterHost)

local TIME_LIMIT = 60

local titles: { any } = {}
server.setSend(function(to, remote: RemoteEvent, ...)
	if remote.Name == "ShowDialogue" then
		task.defer(server.onDialogueFinished, to)
	elseif remote.Name == "ShowTitle" then
		table.insert(titles, table.pack(...))
	end
end)

local function waitIdle(player: any)
	local started = os.clock()
	while not server.idle(player) do
		assert(os.clock() - started < TIME_LIMIT, "the host never waited on the player")
		task.wait(0.1)
	end
end

describe("/title", function()
	local player = FakePlayer.new(world.spawn + Vector3.new(0, 0, -60), -11)
	local chapter = story.chapters[3]
	local quest = chapter.quests[1].id

	it("refuses before the Story has started", function()
		local offered, reason = world.DevShortcuts.onCommand(player, "/title")
		expect(offered).toBeNil()
		expect(reason).toBe("the Story has not started")
		expect(#titles).toBe(0)
	end)

	it("offers the Title screen at the current Progress, with Continue", function()
		expect(world.DevShortcuts.onCommand(player, "/chapter 3")).toBe(quest)
		waitIdle(player)
		local offered = world.DevShortcuts.onCommand(player, "/title")
		expect(offered).toBe(`{chapter.title} — {chapter.subtitle}`)
		expect(#titles).toBe(1)
		expect(Net.check("ShowTitle", titles[1])).toBe(true)
		expect(titles[1][1]).toBe(offered)
		expect(titles[1][2]).toBe(true)
		print(`  ShowTitle: {titles[1][1]}, can continue {titles[1][2]}`)
	end)

	it("waits for the Title choice: the player's actions change nothing", function()
		for _ = 1, 20 do
			play(player)
			task.wait(0.1)
		end
		expect(server.activeQuest(player)).toBe(quest)
		expect((server.progress(player) :: any).completed).toEqual(world.StoryEngine.progressAt(story, quest).completed)
	end)

	it("carries on where the player was on Continue", function()
		server.onTitleChoice(player, "continue")
		expect(server.activeQuest(player)).toBe(quest)
		local started = os.clock()
		while server.activeQuest(player) == quest do
			assert(os.clock() - started < TIME_LIMIT, `stuck at {quest} after Continue`)
			play(player)
			task.wait(0.1)
		end
		print(`  played on to {server.activeQuest(player)}`)
	end)
end)

finish()
