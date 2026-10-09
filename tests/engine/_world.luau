--!strict
-- The world as the place's Scripts build it, for an engine test. Luau
-- Execution runs no Scripts, so a test that needs the world calls this:
-- include("tests/engine/_world.luau").build(withMap). It requires what
-- SceneServer and StoryServer require and starts them the same way: the
-- map (SceneBuilder.build, when `withMap`), then the Story (StoryHost.start:
-- the Zones, Characters at their home Spots, Props and Lighting).
--
-- Returns the Story, the core modules a test drives it with, and the server
-- modules, which are the same instances
-- the hosts use, since a ModuleScript runs once per task.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local World = {}

local function server(name: string): any
	return (require :: any)(ServerScriptService:WaitForChild(name))
end

function World.build(withMap: boolean)
	if withMap then
		server("SceneBuilder").build()
	end
	local StoryHost = server("StoryHost")
	StoryHost.start()
	local story = (require :: any)(ReplicatedStorage:WaitForChild("content"):WaitForChild("Story")).story
	local Convert = server("Convert")
	return {
		story = story,
		-- where a fake player stands at the start: Amy's spawn, the root 4
		-- studs above the ground
		spawn = Convert.vector(story.spots.AmySpawn.at) + Vector3.new(0, 4, 0),
		Story = (require :: any)(ReplicatedStorage:WaitForChild("core"):WaitForChild("Story")),
		StoryEngine = (require :: any)(ReplicatedStorage:WaitForChild("core"):WaitForChild("StoryEngine")),
		StoryHost = StoryHost,
		CharacterHost = server("CharacterHost"),
		Convert = Convert,
		LightingHost = server("LightingHost"),
	}
end

return World
