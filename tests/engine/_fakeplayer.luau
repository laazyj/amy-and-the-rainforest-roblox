--!strict
-- The fake player: stands in for a Player in an engine test, where Luau
-- Execution has no client and Players spawns no one. A test gets it with
-- include("tests/engine/_fakeplayer.luau").
--
-- It is a table, not an Instance: StoryServer only keys its per-player state
-- by it and reads its Character, and the test replaces StoryServer's send,
-- since FireClient needs a real Player. Each field, and why:
--
--   Character  a Model with an anchored HumanoidRootPart, the one field the
--              current StoryServer (src/ServerScriptService/StoryServer/Server.lua)
--              reads. The Zone poll reads its position to complete `reach`
--              Quests, and Sam's catch (samCatches) moves it back into the garden.
--   UserId     not read by StoryServer today; every Player has them, and a
--   Name       negative UserId can never be a real account.

export type FakePlayer = {
	UserId: number,
	Name: string,
	Character: Model,
}

local FakePlayer = {}

-- A fake player standing at `position`, its Character parented to Workspace.
function FakePlayer.new(position: Vector3): FakePlayer
	local character = Instance.new("Model")
	character.Name = "FakeAmy"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Anchored = true -- no physics runs in a task; only the position matters
	root.CanCollide = false
	root.Parent = character
	character.PrimaryPart = root
	character:PivotTo(CFrame.new(position))
	character.Parent = game:GetService("Workspace")
	return { UserId = -1, Name = "FakeAmy", Character = character }
end

-- Puts the Character's HumanoidRootPart at `position`.
function FakePlayer.moveTo(player: FakePlayer, position: Vector3)
	player.Character:PivotTo(CFrame.new(position))
end

return FakePlayer
