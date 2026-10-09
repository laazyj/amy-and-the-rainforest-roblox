--!strict
-- Reachability (plan section 4): the built world lets Amy walk from her
-- spawn to every Zone and to every Character she must talk to.
-- PathfindingService computes a path for an R15 agent from spot:AmySpawn
-- to the ground under each Zone's centre and under each Character's talk
-- prompt; every path must succeed, and end within the prompt's activation
-- distance. Path lengths are printed. The world is checked as the scenes
-- build it; Props a Beat brings in later (the machine, the villagers) are
-- not in place.
--
-- The world is built as the place's Scripts build it (_world.luau): the
-- map, the Zones and the Characters at their home Spots.

local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

-- Roblox's defaults for an R15 character.
local AGENT = { AgentRadius = 2, AgentHeight = 5, AgentCanJump = true }
-- The ground under a point is looked for from a little above it (not from
-- a roof or canopy over it) down to this far below.
local ABOVE, BELOW = 8, 60

local world = include("tests/engine/_world.luau").build(true)
local story = world.story
local prompts: { [string]: ProximityPrompt } = world.CharacterHost.prompts()

local zones = Workspace:WaitForChild("StoryZones")
local characters = Workspace:WaitForChild("StoryCharacters")

-- The ground under `point`: Zones, Characters and see-through parts are not ground.
local probe = RaycastParams.new()
probe.FilterType = Enum.RaycastFilterType.Exclude
probe.FilterDescendantsInstances = { zones, characters }
probe.RespectCanCollide = true

local function ground(point: Vector3): Vector3
	local hit = Workspace:Raycast(point + Vector3.new(0, ABOVE, 0), Vector3.new(0, -(ABOVE + BELOW), 0), probe)
	assert(hit, `no ground under {point}`)
	return hit.Position
end

local function pathLength(waypoints: { PathWaypoint }): number
	local length = 0
	for i = 2, #waypoints do
		length += (waypoints[i].Position - waypoints[i - 1].Position).Magnitude
	end
	return length
end

local start = ground(world.Convert.vector(story.spots.AmySpawn.at))

-- A path from spawn to the ground under `target` succeeds; its end is
-- within `reach` of `target` when given.
local function expectReachable(name: string, target: Vector3, reach: number?)
	local goal = ground(target)
	-- Pathfinding answers NoPath for a path of no length (zone:HomeGarden
	-- is centred on Amy's spawn); standing there is reaching it.
	if (goal - start).Magnitude < AGENT.AgentRadius then
		print(string.format("  %-28s at spawn", name))
		return
	end
	local path = PathfindingService:CreatePath(AGENT)
	path:ComputeAsync(start, goal)
	if path.Status ~= Enum.PathStatus.Success then
		print(string.format("  %-28s %s", name, path.Status.Name))
	end
	expect(path.Status).toBe(Enum.PathStatus.Success)
	local waypoints = path:GetWaypoints()
	local gap = (waypoints[#waypoints].Position - target).Magnitude
	print(string.format("  %-28s %6.1f studs, ends %.1f studs from it", name, pathLength(waypoints), gap))
	if reach then
		expect(gap <= reach).toBe(true)
	end
end

describe("reachability from spot:AmySpawn", function()
	local zoneIds = {}
	for id in story.zones do
		table.insert(zoneIds, id)
	end
	table.sort(zoneIds)
	for _, id in zoneIds do
		it(`reaches zone:{id}`, function()
			expectReachable(`zone:{id}`, (zones:FindFirstChild(id) :: BasePart).Position)
		end)
	end

	for _, character in story.characters do
		if not character.player then
			it(`reaches character:{character.id}'s talk prompt`, function()
				local prompt = prompts[character.id]
				expectReachable(
					`character:{character.id}`,
					(prompt.Parent :: BasePart).Position,
					prompt.MaxActivationDistance
				)
			end)
		end
	end
end)

finish()
