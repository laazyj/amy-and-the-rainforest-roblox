--!strict
--[[
	PickupHost: the glowing Pickups of a `collect` Quest, one per Spot, for
	one player each, bobbing and turning. Touching one is the Player event
	TouchedPickup; the Story removes it. None of today's Quests collect, but
	new Chapters can.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Story = require(ReplicatedStorage:WaitForChild("core"):WaitForChild("Story"))

type Pickup = { player: any, quest: string, id: string, baseY: number }

local PickupHost = {}

local story: Story.Story
local folder: Folder
local onTouched: (player: Player, pickup: string) -> ()
local active: { [BasePart]: Pickup } = {}

-- Builds the StoryPickups folder; `touched(player, pickupId)` is called when a
-- player's Character touches one of their Pickups.
function PickupHost.build(forStory: Story.Story, touched: (player: Player, pickup: string) -> ())
	story = forStory
	onTouched = touched
	folder = Instance.new("Folder")
	folder.Name = "StoryPickups"
	folder.Parent = Workspace

	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t = t + dt
		for part, pickup in active do
			if part.Parent then
				part.CFrame = CFrame.new(part.Position.X, pickup.baseY + math.sin(t * 2) * 0.5, part.Position.Z)
					* CFrame.Angles(0, t * 1.2, 0)
			end
		end
	end)
end

local function makePickup(player: any, quest: string, id: string, spot: Story.Spot)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Name = "Pickup"
	part.Size = Vector3.new(2.4, 0.6, 2.4)
	part.Color = Color3.fromRGB(255, 130, 190)
	part.Material = Enum.Material.Neon
	local baseY = spot.at.y + 2.2
	part.CFrame = CFrame.new(spot.at.x, baseY, spot.at.z)

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 170, 220))
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new(0.5)
	sparkle.Lifetime = NumberRange.new(0.8, 1.6)
	sparkle.Rate = 6
	sparkle.Speed = NumberRange.new(0.5, 1)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Parent = part

	local pickup = { player = player, quest = quest, id = id, baseY = baseY }
	active[part] = pickup
	part.Touched:Connect(function(hit)
		local character = hit.Parent
		local toucher = character and Players:GetPlayerFromCharacter(character)
		if toucher and toucher == pickup.player and active[part] then
			onTouched(toucher, id)
		end
	end)
	part.Parent = folder
end

-- Removes the player's Pickups that `matches` picks.
local function remove(player: any, matches: (Pickup) -> boolean)
	for part, pickup in active do
		if pickup.player == player and matches(pickup) then
			active[part] = nil
			part:Destroy()
		end
	end
end

function PickupHost.spawn(player: any, questId: string)
	local quest = assert(Story.quest(story, questId), questId)
	for _, spotId in (quest.pickups or {}) :: { string } do
		makePickup(player, questId, spotId, (assert(story.spots[spotId], spotId)))
	end
end

function PickupHost.remove(player: any, id: string)
	remove(player, function(pickup)
		return pickup.id == id
	end)
end

function PickupHost.clear(player: any, quest: string?)
	remove(player, function(pickup)
		return quest == nil or pickup.quest == quest
	end)
end

return PickupHost
