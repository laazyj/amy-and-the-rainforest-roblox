--!strict
-- Every Character spawns with a Humanoid and its animations load (brief
-- 014, plan section 2.3). A human is Roblox's R15 body in its Description's
-- colours, with Roblox's idle, walk and run animations loaded and idle
-- playing. Any other Character is its Character model when the place has
-- one, with the animations it brings, and else its Placeholder, which has
-- a Humanoid and no animations: so this passes while the animals are still
-- Placeholders. Then the Player Character is dressed as Amy, and Sam runs
-- to a Spot and stands there, though no physics steps in a task (see
-- physics.luau), within the 3 seconds a run is given.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local world = include("tests/engine/_world.luau").build(false, "characters")
local story = world.story
local CharacterHost = world.CharacterHost
local Convert = world.Convert

local built = Workspace:WaitForChild("StoryCharacters")
local characterModels = ServerStorage:FindFirstChild("CharacterModels")
-- how long an animation is given to load
local LOAD_SECONDS = 10

-- The part of `model` named `name`, as a BasePart.
local function part(model: Instance, name: string): BasePart
	local found = model:FindFirstChild(name)
	assert(found and found:IsA("BasePart"), `{model.Name} has no {name}`)
	return found
end

-- Waits for `track` to load: its Length is known once it has.
local function loaded(track: AnimationTrack): boolean
	local waited = 0
	while track.Length == 0 and waited < LOAD_SECONDS do
		waited += task.wait(0.1)
	end
	return track.Length > 0
end

describe("the Characters", function()
	for _, character in story.characters do
		if character.player then
			continue
		end
		local id = character.id
		local hasModel = characterModels ~= nil and characterModels:FindFirstChild(id) ~= nil
		local build = world.Story.build(character, hasModel)

		it(`builds character:{id} from its {build}, with a Humanoid and an Animator, anchored at its root`, function()
			local model = built:FindFirstChild(id) :: Model
			expect(model).toBeTruthy()
			local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
			expect(humanoid).toBeTruthy()
			expect(humanoid:FindFirstChildOfClass("Animator")).toBeTruthy()
			local root = model.PrimaryPart :: BasePart
			expect(root and root.Name).toBe("HumanoidRootPart")
			expect(root.Anchored).toBe(true)
		end)

		local tracks = CharacterHost.animations()[id] or {}
		if build == "description" then
			local description = character.description :: any
			it(`makes character:{id} Roblox's R15 body in its Description's colours`, function()
				local model = built:FindFirstChild(id) :: Model
				expect((model:FindFirstChildOfClass("Humanoid") :: Humanoid).RigType).toBe(Enum.HumanoidRigType.R15)
				expect(part(model, "Head").Color:ToHex()).toBe(Convert.colour(description.head):ToHex())
				expect(part(model, "UpperTorso").Color:ToHex()).toBe(Convert.colour(description.torso):ToHex())
				expect(part(model, "LeftUpperArm").Color:ToHex()).toBe(Convert.colour(description.arms):ToHex())
				expect(part(model, "RightLowerLeg").Color:ToHex()).toBe(Convert.colour(description.legs):ToHex())
			end)

			it(`loads character:{id}'s idle, walk and run animations, and plays idle`, function()
				for _, name in { "idle", "walk", "run" } do
					local track = tracks[name]
					print(`  {id} {name}: {if track then string.format("%.2f s", track.Length) else "none"}`)
					expect(track).toBeTruthy()
					expect(loaded(track)).toBe(true)
				end
				expect(tracks.idle.IsPlaying).toBe(true)
			end)
		else
			it(`loads every animation character:{id} has`, function()
				for name, track in tracks do
					print(`  {id} {name}: {string.format("%.2f s", track.Length)}`)
					expect(loaded(track)).toBe(true)
				end
			end)
		end
	end
end)

describe("the Player Character", function()
	it("is dressed as Amy: her Description on Roblox's body", function()
		local amy = assert(world.Story.character(story, "Amy")).description :: any
		local body =
			game:GetService("Players")
				:CreateHumanoidModelFromDescriptionAsync(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		body.Name = "FakeAmy"
		body.Parent = Workspace
		CharacterHost.dress(body)
		expect(part(body, "UpperTorso").Color:ToHex()).toBe(Convert.colour(amy.torso):ToHex())
		expect(part(body, "LeftLowerLeg").Color:ToHex()).toBe(Convert.colour(amy.legs):ToHex())
		body:Destroy()
	end)
end)

describe("a run", function()
	it("sets Sam running and returns, so the Beat's Wait gives the run its time", function()
		local started = os.clock()
		CharacterHost.moveCharacter("Sam", "GateOutside", true)
		expect(os.clock() - started < 0.1).toBe(true)
	end)

	it("stands Sam at the Spot he runs to within the 3 seconds a run is given, anchored", function()
		local sam = built:FindFirstChild("Sam") :: Model
		local spot = story.spots.GateOutside
		local root = sam.PrimaryPart :: BasePart
		local function there(): boolean
			local at = sam:GetPivot().Position
			return root.Anchored and math.abs(at.X - spot.at.x) < 0.01 and math.abs(at.Z - spot.at.z) < 0.01
		end
		local waited = 0
		while not there() and waited < 3.5 do
			waited += task.wait(0.1)
		end
		print(string.format("  Sam stood at spot:GateOutside after %.2f s", waited))
		expect(there()).toBe(true)
	end)
end)

finish()
