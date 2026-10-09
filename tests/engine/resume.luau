--!strict
-- Resume (plan section 4): for every Quest, the world a returning player
-- gets from their saved Progress is the world they had when they walked
-- there.
--
-- 1. Walk the Story with the fake player and the driver. As each Quest
--    becomes playable (the host idle, waiting on the player), save the
--    Progress, through JSON as a save would, and observe the world: where
--    each Character stands, which Props are out and in what state, and the
--    Lighting preset.
-- 2. Then, last Quest first, resume at each saved Progress in a fresh
--    StoryEngine (StoryHost.resume) and observe the world again; it must
--    match. Going backwards makes each Resume undo a later world (the
--    machine leaves, Sam comes home), as a returning player's fresh server
--    would not need to, so it is the harder test.
--
-- A task cannot load a fresh DataModel; each Resume rebuilds every
-- Character, Prop and the Lighting preset over whatever is there, which
-- is what StoryEngine.resume promises (src/core/WorldState.luau).

local Driver = include("tests/engine/_driver.luau")
local FakePlayer = include("tests/engine/_fakeplayer.luau")

local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local TIME_LIMIT = 200

local world = include("tests/engine/_world.luau").build(false)
local server = world.StoryHost
local story = world.story
local play = Driver.new(server, world.CharacterHost)

local player = FakePlayer.new(world.spawn)
server.setSend(function(to, remote: RemoteEvent)
	if remote.Name == "ShowDialogue" then
		task.defer(server.onDialogueFinished, to)
	end
end)

local function position(model: Model): string
	local at = model:GetPivot().Position
	return string.format("%.1f %.1f %.1f", at.X, at.Y, at.Z)
end

-- What a player would see of the Story in the world.
local function observe(): { [string]: any }
	local seen: { [string]: any } = { lighting = world.LightingHost.preset() }
	for _, model in Workspace:WaitForChild("StoryCharacters"):GetChildren() do
		seen[`character:{model.Name}`] = position(model :: Model)
	end
	local machine = Workspace:FindFirstChild("TreeChoppingMachine")
	local smoke = machine and machine:FindFirstChildWhichIsA("ParticleEmitter", true)
	seen["prop:Machine"] = if machine then `out, smoke {smoke and smoke.Enabled}` else "absent"
	local villagers = Workspace:FindFirstChild("Villagers")
	seen["prop:Villagers"] = if villagers then `{#villagers:GetChildren()} gathered` else "absent"
	return seen
end

local order: { string } = {}
local saved: { [string]: { progress: string, world: { [string]: any } } } = {}

describe("Resume", function()
	it("walks the Story, saving Progress and the world at every Quest", function()
		server.onClientReady(player)
		local started = os.clock()
		repeat
			local questId = server.activeQuest(player)
			if os.clock() - started > TIME_LIMIT then
				error(`stuck at Quest {questId or "(none)"}`)
			end
			if questId and not saved[questId] and server.idle(player) then
				saved[questId] = { progress = HttpService:JSONEncode(server.progress(player)), world = observe() }
				table.insert(order, questId)
			end
			play(player)
			task.wait(0.1)
		until (server.progress(player) :: any).ended
		print(`  saved {#order} Quests in {math.floor(os.clock() - started)} s`)
		expect(#order).toBe(#world.Story.quests(story))
	end)

	it("rebuilds, from each saved Progress, the world walked to, last Quest first", function()
		local mismatches = {}
		for i = #order, 1, -1 do
			local questId = order[i]
			server.resume(player, HttpService:JSONDecode(saved[questId].progress))
			expect(server.activeQuest(player)).toBe(questId)
			local resumed, walked = observe(), saved[questId].world
			local before = #mismatches
			for key, value in walked do
				if resumed[key] ~= value then
					table.insert(mismatches, `{questId} {key}: walked {value}, resumed {resumed[key]}`)
				end
			end
			-- a Character only the Resume has is a mismatch too
			for key, value in resumed do
				if walked[key] == nil then
					table.insert(mismatches, `{questId} {key}: walked nil, resumed {value}`)
				end
			end
			print(`  {questId}: {if #mismatches == before then "the same world" else "a different world"}`)
		end
		for _, mismatch in mismatches do
			print("  MISMATCH " .. mismatch)
		end
		expect(#mismatches).toBe(0)
	end)
end)

finish()
