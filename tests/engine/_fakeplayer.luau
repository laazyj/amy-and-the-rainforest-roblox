--!strict
-- The fake player: stands in for a Player in an engine test, where Luau
-- Execution has no client and Players spawns no one. A test gets it with
-- include("tests/engine/_fakeplayer.luau").
--
-- It is a table, not an Instance: StoryHost (src/server/StoryHost.luau)
-- only keys its per-player sessions by it and reads its fields, and the test
-- replaces StoryHost's send, since FireClient needs a real Player. Each
-- field, and why:
--
--   Character  a Model with an anchored HumanoidRootPart. The Zone poll
--              (src/server/PromptBridge.luau) reads its position to raise
--              EnteredZone, and TeleportPlayer (Sam's catch) moves it back
--              into the garden.
--   UserId     the id the player's StoryEngine is made with; a negative
--              UserId can never be a real account. -1 unless given.
--   Name       every Player has one: FakeAmy, or FakeAmy2 for UserId -2.

export type FakePlayer = {
	UserId: number,
	Name: string,
	Character: Model,
}

local FakePlayer = {}

-- A fake player standing at `position`, its Character parented to Workspace.
function FakePlayer.new(position: Vector3, userId: number?): FakePlayer
	local id = userId or -1
	local name = if id == -1 then "FakeAmy" else `FakeAmy{-id}`
	local character = Instance.new("Model")
	character.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Anchored = true -- no physics runs in a task; only the position matters
	root.CanCollide = false
	root.Parent = character
	character.PrimaryPart = root
	character:PivotTo(CFrame.new(position))
	character.Parent = game:GetService("Workspace")
	return { UserId = id, Name = name, Character = character }
end

-- Puts the Character's HumanoidRootPart at `position`.
function FakePlayer.moveTo(player: FakePlayer, position: Vector3)
	player.Character:PivotTo(CFrame.new(position))
end

return FakePlayer
