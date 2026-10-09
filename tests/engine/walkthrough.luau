--!strict
-- Golden walkthrough (brief 004): plays the current StoryServer from spawn to
-- the Ending with the fake player, and checks every server -> client message,
-- in order, with the Quest active when it was sent, against
-- tests/fixtures/golden/walkthrough.json. It characterizes today's game so
-- the Checkpoint B refactor can prove it changes no behaviour.
--
-- How the server is driven (Luau Execution runs no Scripts, no physics and
-- no client):
--   start            require the StoryServer's Server module, replace its
--                    send with a recorder (setSend), then call its
--                    ClientReady handler
--   DialogueFinished its handler, deferred, after every ShowDialogue
--   TalkedTo         the talk prompt's Triggered handler, for the prompt
--                    that is enabled
--   EnteredZone      move the Character into the active Quest's Zone; the
--                    server's own Zone poll (every 0.5 s) completes it
--   TouchedPickup    none: the Story has no `collect` Quest today
--
-- On a divergence the test prints the first differing message and then the
-- whole recorded walkthrough between GOLDEN BEGIN and GOLDEN END, ready to
-- become the golden file when a change is intended.

local FakePlayer = include("tests/engine/_fakeplayer.luau")
local GOLDEN = fixture("tests/fixtures/golden/walkthrough.json")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

-- A task runs for at most 300 s; today's playthrough takes well under a minute.
local TIME_LIMIT = 240
-- No message for this long means the Story is stuck.
local STALL_LIMIT = 30

-- JSON with sorted keys. Strings keep their UTF-8 bytes; control characters,
-- quotes and backslashes are escaped.
local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encode(value: any): string
	local kind = type(value)
	if value == nil then
		return "null"
	elseif kind == "string" then
		local escaped = string.gsub(value, '[%c"\\]', function(char)
			return ESCAPES[char] or string.format("\\u%04x", string.byte(char))
		end)
		return `"{escaped}"`
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "number" then
		return if value % 1 == 0 then string.format("%d", value) else string.format("%.17g", value)
	elseif kind == "table" then
		local parts = {}
		if #value > 0 then
			for i, item in value do
				assert(type(i) == "number", "a table mixes array and object keys")
				parts[i] = encode(item)
			end
			return `[{table.concat(parts, ",")}]`
		end
		local keys = {}
		for key in value do
			assert(type(key) == "string", "object keys must be strings")
			table.insert(keys, key)
		end
		table.sort(keys)
		for i, key in keys do
			parts[i] = `{encode(key)}:{encode(value[key])}`
		end
		return `\{{table.concat(parts, ",")}}`
	end
	error(`cannot encode a {typeof(value)}`)
end

-- One message as one line of the golden file. Only what is deterministic:
-- the remote, its arguments (nil kept as null) and the active Quest's id.
local function messageLine(remote: string, questId: string?, args: { n: number, [number]: any }): string
	local parts = {}
	for i = 1, args.n do
		parts[i] = encode(args[i])
	end
	return `\{"args":[{table.concat(parts, ",")}],"quest":{encode(questId)},"remote":{encode(remote)}}`
end

-- The golden file is a JSON array with one message per line.
local function goldenLines(text: string): { string }
	local lines = {}
	for line in string.gmatch(text, "[^\n]+") do
		line = string.gsub(line, ",$", "")
		if line ~= "[" and line ~= "]" then
			table.insert(lines, line)
		end
	end
	return lines
end

local StoryData = (require :: any)(ReplicatedStorage:WaitForChild("content"):WaitForChild("StoryData"))

-- Each message's line in the golden file, in the order sent.
local recorded: { string } = {}

describe("golden walkthrough", function()
	it("plays the Story from spawn to the Ending", function()
		assert(
			ReplicatedStorage:FindFirstChild("StoryRemotes") == nil,
			"StoryServer already ran in this task; the walkthrough must start it itself"
		)
		local server = (require :: any)(ServerScriptService:WaitForChild("StoryServer"):WaitForChild("Server"))
		local player = FakePlayer.new(StoryData.Map.SpawnPosition)

		local ended = false
		local lastMessageAt = os.clock()
		server.setSend(function(_, remote: RemoteEvent, ...: any)
			table.insert(recorded, messageLine(remote.Name, server.activeQuest(player), table.pack(...)))
			lastMessageAt = os.clock()
			if remote.Name == "ShowDialogue" then
				-- The client replies once the player has read the last Line.
				task.defer(server.onDialogueFinished, player)
			elseif remote.Name == "ShowEnding" then
				ended = true
			end
		end)

		-- Every talk prompt, by the Character it belongs to. StoryServer
		-- builds them all when it loads.
		local prompts: { [string]: ProximityPrompt } = {}
		for _, prompt in Workspace:WaitForChild("StoryNPCs"):GetDescendants() do
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
			if quest and quest.type == "talk" then
				-- Press whichever talk prompt is showing, as a player would.
				-- The handler disables it before it first yields.
				for character, prompt in prompts do
					if prompt.Enabled then
						task.spawn(server.onTalkPromptTriggered, character, player)
					end
				end
			elseif quest and quest.type == "reach" then
				FakePlayer.moveTo(player, (zones:FindFirstChild(quest.zone) :: BasePart).Position)
			elseif quest then
				error(`no driver for a {quest.type} Quest ({questId}); add one with the first such Quest`)
			end
			task.wait(0.1)
		end
		print(string.format("  walkthrough took %.1f s, %d messages", os.clock() - started, #recorded))
		expect(#Workspace:WaitForChild("StoryPickups"):GetChildren()).toBe(0)
	end)

	it("sends every message in the golden file, in order", function()
		local expected = goldenLines(GOLDEN)
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
