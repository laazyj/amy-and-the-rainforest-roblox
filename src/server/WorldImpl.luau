--!strict
--[[
	WorldImpl: the World interface (src/core/World) for one player, over the
	engine adapters. Commands that reach the client go through `toClient`,
	which carries them over Net; the rest move Characters, Props, Lighting,
	Pickups and the Player Character in the world.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = ReplicatedStorage:WaitForChild("core")
local Events = require(Core:WaitForChild("Events"))
local Story = require(Core:WaitForChild("Story"))
local World = require(Core:WaitForChild("World"))
local CharacterHost = require(script.Parent.CharacterHost)
local Convert = require(script.Parent.Convert)
local LightingHost = require(script.Parent.LightingHost)
local PickupHost = require(script.Parent.PickupHost)
local PropHost = require(script.Parent.PropHost)

-- the Player Character's root stands this high above a Spot's ground
local ROOT_HEIGHT = 3.5

local WorldImpl = {}

function WorldImpl.new(story: Story.Story, player: any, toClient: (command: Events.WorldCommand) -> ()): World.World
	return {
		showDialogue = function(lines)
			toClient({ kind = "ShowDialogue", lines = lines })
		end,
		setObjective = function(text)
			toClient({ kind = "SetObjective", text = text })
		end,
		showChapterCard = function(title, subtitle, ending)
			toClient({ kind = "ShowChapterCard", title = title, subtitle = subtitle, ending = ending })
		end,
		moveCharacter = CharacterHost.moveCharacter,
		teleportPlayer = function(spotId)
			local spot = assert(story.spots[spotId], spotId)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				root.CFrame = Convert.standing(spot, ROOT_HEIGHT)
			end
		end,
		setPropState = PropHost.setState,
		setLighting = LightingHost.set,
		spawnPickups = function(quest)
			PickupHost.spawn(player, quest)
		end,
		removePickup = function(pickup)
			PickupHost.remove(player, pickup)
		end,
		clearPickups = function(quest)
			PickupHost.clear(player, quest)
		end,
		offerTalk = CharacterHost.offerTalk,
		withdrawTalk = CharacterHost.withdrawTalk,
		wait = function(seconds)
			task.wait(seconds)
		end,
	}
end

return WorldImpl
