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
--   TalkedTo         the talk prompt's Triggered handler, for the prompt
--                    that is enabled
--   EnteredZone      move the Character into the active Quest's Zone; the
--                    host's Zone poll (every 0.5 s) turns that into the event
--   TouchedPickup    none: the Story has no `collect` Quest today
--
-- On a divergence the test prints the first differing message and then the
-- whole recorded walkthrough between GOLDEN BEGIN and GOLDEN END.

local FakePlayer = include("tests/engine/_fakeplayer.luau")
local Golden = include("tests/engine/_golden.luau")
local GOLDEN = fixture("tests/fixtures/golden/walkthrough.json")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

-- A task runs for at most 300 s; today's playthrough takes well under a minute.
local TIME_LIMIT = 240
-- No message for this long means the Story is stuck.
local STALL_LIMIT = 30

local Content = (require :: any)(ReplicatedStorage:WaitForChild("content"):WaitForChild("Story"))

-- Each message's line in the golden file, in the order sent.
local recorded: { string } = {}

describe("golden walkthrough", function()
	it("plays the Story from spawn to the Ending", function()
		assert(
			ReplicatedStorage:FindFirstChild("StoryRemotes") == nil,
			"StoryHost already ran in this task; the walkthrough must start it itself"
		)
		local server = (require :: any)(ServerScriptService:WaitForChild("StoryHost"))
		server.start()
		-- Amy's spawn, with the root 4 studs above the ground as before
		local spawn = Content.story.spots.AmySpawn.at
		local player = FakePlayer.new(Vector3.new(spawn.x, spawn.y + 4, spawn.z))

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

		-- Every talk prompt, by the Character it belongs to. StoryHost
		-- builds them all when it starts.
		local prompts: { [string]: ProximityPrompt } = {}
		for _, prompt in Workspace:WaitForChild("StoryCharacters"):GetDescendants() do
			if prompt:IsA("ProximityPrompt") then
				prompts[(prompt:FindFirstAncestorOfClass("Model") :: Model).Name] = prompt
			end
		end
		local zones = Workspace:WaitForChild("StoryZones")

		local started = os.clock()
		server.onClientReady(player)
		while not ended do
			local questId, quest = server.activeQuest(player)
			if os.clock() - started > TIME_LIMIT or os.clock() - lastMessageAt > STALL_LIMIT then
				error(`stuck at Quest {questId or "(none)"} after {#recorded} messages`)
			end
			if quest and quest.kind == "talk" then
				-- Press whichever talk prompt is showing, as a player would.
				-- The handler disables it before it first yields.
				for character, prompt in prompts do
					if prompt.Enabled then
						task.spawn(server.onTalkPromptTriggered, character, player)
					end
				end
			elseif quest and quest.kind == "reach" then
				FakePlayer.moveTo(player, (zones:FindFirstChild(quest.zone) :: BasePart).Position)
			elseif quest then
				error(`no driver for a {quest.kind} Quest ({questId}); add one with the first such Quest`)
			end
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
