--!strict
-- Resume (plan section 4): for every Quest, the world a returning player
-- gets from their saved Progress is the world they had when they walked
-- there.
--
-- 1. Walk the Story with the fake player and the driver. As each Quest
--    becomes playable (the host idle, waiting on the player), write the
--    player's Save to its DataStore through Persist and ProfileStore, read
--    it back from the store, and observe the world: where each Character
--    stands, which Props are out and in what state, and the Lighting
--    preset. The store is this run's test store (tests/engine/_world.luau).
-- 2. Then, last Quest first, resume from each stored Save (core/Save read
--    and restored) in a fresh StoryEngine (StoryHost.resume) and observe
--    the world again; it must match. Going backwards makes each Resume undo a later world (the
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

-- the walk, with a DataStore write and read at every Quest (a key takes
-- about one write every 6 s)
local TIME_LIMIT = 220

local world = include("tests/engine/_world.luau").build(false, "resume")
local server = world.StoryHost
local story = world.story
local Persist, Save = world.Persist, world.Save
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
local saved: { [string]: { save: string, world: { [string]: any } } } = {}

describe("Resume", function()
	it("walks the Story, writing the Save to its DataStore at every Quest and reading it back", function()
		server.onClientReady(player)
		local started = os.clock()
		repeat
			local questId = server.activeQuest(player)
			if os.clock() - started > TIME_LIMIT then
				error(`stuck at Quest {questId or "(none)"}`)
			end
			-- A Quest is played only once it is saved, so none can finish between
			-- two polls unsaved. (A `reach` Quest could also finish with the player
			-- already standing in its Zone; no Quest starts that way today, as
			-- Sam's catch moves Amy out of the gate.)
			if questId and not saved[questId] then
				if not server.idle(player) then
					task.wait(0.1)
					continue
				end
				assert(Persist.flush(player), `the Save at {questId} was not written`)
				local stored, locked = Persist.stored(player)
				assert(locked, "the Save is not locked to this server's session")
				local save = assert(Save.read(story, stored))
				expect(save.progress.quest).toBe(questId)
				saved[questId] = { save = HttpService:JSONEncode(stored), world = observe() }
				table.insert(order, questId)
			end
			play(player)
			task.wait(0.1)
		until (server.progress(player) :: any).ended
		print(`  saved {#order} Quests to {Persist.storeName()} in {math.floor(os.clock() - started)} s`)
		expect(#order).toBe(#world.Story.quests(story))
	end)

	it("rebuilds, from each stored Save, the world walked to, last Quest first", function()
		local mismatches = {}
		for i = #order, 1, -1 do
			local questId = order[i]
			local save = assert(Save.read(story, HttpService:JSONDecode(saved[questId].save)))
			server.resume(player, Save.restore(story, save.progress))
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
