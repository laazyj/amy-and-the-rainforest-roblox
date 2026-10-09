--!strict
-- Isolation (plan section 2.1: single player is an invariant, and the
-- engine would not cross-talk if Max Players = 1 were ever lost). One
-- StoryHost, two kinds of player, each playing QUESTS_EACH Quests:
--
--   from a fresh start, in Chapter One
--   jumped to Chapter Three with the Dev shortcut "/chapter 3"
--   (DevShortcuts: a Resume at chapter3.meet_squirrel)
--
-- First each plays alone (Amy, Amy2); then two new players start the same
-- way and play at the same time (Amy3, Amy4). No cross-talk means the
-- second player changes nothing anyone gets: each player's messages
-- (objectives, Dialogue, cards) and Progress together are exactly her solo
-- counterpart's. The solo fresh start is also checked against the golden
-- file, and Sam's catch (TeleportPlayer) must move only the player caught.
--
-- Not covered, by design: Characters, Props and Lighting are one world
-- for the whole server, so a Beat one player plays is seen by the other.
-- Co-op is a redesign (plan section 2.1), not a property to test here.

local Driver = include("tests/engine/_driver.luau")
local FakePlayer = include("tests/engine/_fakeplayer.luau")
local Golden = include("tests/engine/_golden.luau")
local golden = Golden.lines(fixture("tests/fixtures/golden/walkthrough.json"))

local TIME_LIMIT = 60 -- for each run
local QUESTS_EACH = 3
local JUMP = "/chapter 3"

local world = include("tests/engine/_world.luau").build(false)
local server = world.StoryHost
local play = Driver.new(server, world.CharacterHost)

-- Each player's messages, as golden file lines.
local sent: { [any]: { string } } = {}
server.setSend(function(to, remote: RemoteEvent, ...: any)
	table.insert(sent[to], Golden.messageLine(remote.Name, server.activeQuest(to), table.pack(...)))
	if remote.Name == "ShowDialogue" then
		task.defer(server.onDialogueFinished, to)
	end
end)

local function completed(player: any): { string }
	return (server.progress(player) :: any).completed
end

-- A new player, started fresh or jumped with JUMP, and the number of
-- Quests she must have completed when she has played QUESTS_EACH.
local function join(userId: number, jumped: boolean): (any, number)
	-- behind the house, outside every Zone, so the Zone poll moves no one
	-- on by itself
	local player = FakePlayer.new(world.spawn + Vector3.new(-6 * userId, 0, -60), userId)
	sent[player] = {}
	if jumped then
		assert(world.DevShortcuts.onCommand(player, JUMP) == "chapter3.meet_squirrel", JUMP)
	else
		server.onClientReady(player)
	end
	return player, (if jumped then #completed(player) else 0) + QUESTS_EACH
end

-- Plays `players` at the same time until each has completed her Quests
-- and the host is waiting on her for the next.
local function playTogether(players: { { player: any, target: number } })
	local started = os.clock()
	while true do
		local done = true
		for _, entry in players do
			local player = entry.player
			if #completed(player) < entry.target then
				play(player)
				done = false
			elseif not server.idle(player) then
				done = false
			end
		end
		if done then
			return
		end
		if os.clock() - started > TIME_LIMIT then
			error(`stuck at Quest {server.activeQuest(players[1].player) or "(none)"}`)
		end
		task.wait(0.1)
	end
end

local amy, amy2, amy3, amy4

describe("two players at different Chapters", function()
	it("plays each alone first", function()
		local target
		amy, target = join(-1, false)
		playTogether({ { player = amy, target = target } })
		amy2, target = join(-2, true)
		playTogether({ { player = amy2, target = target } })
		print(`  alone: Amy got {#sent[amy]} messages, Amy2 {#sent[amy2]}`)
	end)

	it("plays two new players together, one in Chapter One and one in Chapter Three", function()
		local target3, target4
		amy3, target3 = join(-3, false)
		amy4, target4 = join(-4, true)
		local amy4Stands = amy4.Character:GetPivot().Position
		playTogether({ { player = amy3, target = target3 }, { player = amy4, target = target4 } })
		print(`  together: Amy3 got {#sent[amy3]} messages, Amy4 {#sent[amy4]}`)
		expect(table.find(completed(amy3), "chapter1.sneak_out_1") ~= nil).toBe(true)
		-- Sam caught Amy3 and put her back in the garden; Amy4 stayed put.
		expect(amy4.Character:GetPivot().Position).toBe(amy4Stands)
	end)

	-- `actual` is `expected` line for line, or (`prefix`) its start.
	local function sameLines(label: string, expected: { string }, actual: { string }, prefix: boolean?)
		for i = 1, if prefix then #actual else math.max(#expected, #actual) do
			assert(
				expected[i] == actual[i],
				`{label}, message {i}:\n  expected: {expected[i]}\n  actual:   {actual[i]}`
			)
		end
	end

	it("sends the fresh start exactly the golden file's messages, from its start", function()
		sameLines("Amy against the golden file", golden, sent[amy], true)
	end)

	it("sends each player together exactly what she got alone", function()
		sameLines("Amy3 against Amy", sent[amy], sent[amy3])
		sameLines("Amy4 against Amy2", sent[amy2], sent[amy4])
	end)

	it("leaves each player together with the Progress she had alone", function()
		expect(server.progress(amy3)).toEqual(server.progress(amy))
		expect(server.progress(amy4)).toEqual(server.progress(amy2))
	end)
end)

finish()
