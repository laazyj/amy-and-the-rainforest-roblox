--!strict
-- Golden walkthrough (brief 004): plays the Story from spawn to the Ending
-- with the fake player, through the server adapters, and checks every
-- server -> client message, in order, with the Quest active when it was
-- sent, against tests/fixtures/golden/walkthrough.json. The golden file
-- was recorded from the proof of concept before the Checkpoint B refactor,
-- so passing it proves the refactor changed no behaviour.
--
-- How the server is driven (Luau Execution runs no Scripts, no physics and
-- no client):
--   start            require StoryHost, start it, replace its send with a
--                    recorder (setSend), then call its ClientReady handler
--   DialogueFinished its handler, deferred, after every ShowDialogue
--   TalkedTo,        the driver (_driver.luau): the talk prompt's Triggered
--   EnteredZone      handler once the prompt is offered, or the Character
--                    moved into the Zone, which the host's Zone poll (every
--                    0.5 s) turns into the event
--
-- On a divergence the test prints the first differing message and then the
-- whole recorded walkthrough between GOLDEN BEGIN and GOLDEN END.

local Driver = include("tests/engine/_driver.luau")
local FakePlayer = include("tests/engine/_fakeplayer.luau")
local Golden = include("tests/engine/_golden.luau")
local GOLDEN = fixture("tests/fixtures/golden/walkthrough.json")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- A task runs for at most 300 s; today's playthrough takes well under a minute.
local TIME_LIMIT = 240
-- No message for this long means the Story is stuck.
local STALL_LIMIT = 30

-- Each message's line in the golden file, in the order sent.
local recorded: { string } = {}

describe("golden walkthrough", function()
	it("plays the Story from spawn to the Ending", function()
		assert(
			ReplicatedStorage:FindFirstChild("StoryRemotes") == nil,
			"StoryHost already ran in this task; the walkthrough must start it itself"
		)
		local world = include("tests/engine/_world.luau").build(false)
		local server = world.StoryHost
		local play = Driver.new(server, world.CharacterHost)
		local player = FakePlayer.new(world.spawn)

		local ended = false
		local lastMessageAt = os.clock()
		server.setSend(function(_, remote: RemoteEvent, ...: any)
			table.insert(recorded, Golden.messageLine(remote.Name, server.activeQuest(player), table.pack(...)))
			lastMessageAt = os.clock()
			if remote.Name == "ShowDialogue" then
				-- The client replies once the player has read the last Line.
				task.defer(server.onDialogueFinished, player)
			elseif remote.Name == "ShowEnding" then
				ended = true
			end
		end)

		local started = os.clock()
		server.onClientReady(player)
		while not ended do
			if os.clock() - started > TIME_LIMIT or os.clock() - lastMessageAt > STALL_LIMIT then
				error(`stuck at Quest {server.activeQuest(player) or "(none)"} after {#recorded} messages`)
			end
			play(player)
			task.wait(0.1)
		end
		print(string.format("  walkthrough took %.1f s, %d messages", os.clock() - started, #recorded))
		expect(#Workspace:WaitForChild("StoryPickups"):GetChildren()).toBe(0)
	end)

	it("sends every message in the golden file, in order", function()
		local expected = Golden.lines(GOLDEN)
		for i = 1, math.max(#expected, #recorded) do
			if expected[i] ~= recorded[i] then
				print("GOLDEN BEGIN")
				print("[")
				for k, line in recorded do
					print(line .. if k < #recorded then "," else "")
				end
				print("]")
				print("GOLDEN END")
				error(
					`first divergence at message {i} of {#expected} (each line names its Quest):`
						.. `\n  expected: {expected[i] or "(no more messages)"}`
						.. `\n  actual:   {recorded[i] or "(no more messages)"}`,
					0
				)
			end
		end
	end)
end)

finish()
