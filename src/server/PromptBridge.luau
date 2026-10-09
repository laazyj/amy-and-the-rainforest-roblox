--!strict
--[[
	PromptBridge: turns what the engine sees into Player events. A talk
	prompt's Triggered is TalkedTo(character); a Character touching a Zone,
	or found inside one by the Zone poll, is EnteredZone(zone).

	The poll runs every 0.5 s because Touched does not fire for a player
	already standing in a Zone when a `reach` Quest starts, and it is how
	the engine walkthrough's fake player, which has no physics, enters
	Zones.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = require(ReplicatedStorage:WaitForChild("core"):WaitForChild("Events"))

type Handle = (player: any, event: Events.PlayerEvent) -> ()

local POLL_SECONDS = 0.5
-- a Character's root counts as inside a Zone up to this far above its top
local ABOVE_ZONE = 3

local PromptBridge = {}

local handle: Handle = function(_player, _event) end

-- The talk prompt of `character` was used by `player`.
function PromptBridge.onTalkPromptTriggered(character: string, player: any)
	handle(player, { kind = "TalkedTo", character = character })
end

local function inside(zone: BasePart, root: BasePart): boolean
	local offset = zone.Position - root.Position
	local half = zone.Size / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y + ABOVE_ZONE and math.abs(offset.Z) <= half.Z
end

-- Connects the talk prompts and the Zones to `onEvent`. `players()` lists
-- the players the Zone poll looks at.
function PromptBridge.connect(
	prompts: { [string]: ProximityPrompt },
	zones: { [string]: BasePart },
	onEvent: Handle,
	players: () -> { any }
)
	handle = onEvent

	for character, prompt in prompts do
		prompt.Triggered:Connect(function(player)
			PromptBridge.onTalkPromptTriggered(character, player)
		end)
	end

	for zone, part in zones do
		part.Touched:Connect(function(hit)
			local player = hit.Parent and Players:GetPlayerFromCharacter(hit.Parent)
			if player then
				handle(player, { kind = "EnteredZone", zone = zone })
			end
		end)
	end

	task.spawn(function()
		while true do
			task.wait(POLL_SECONDS)
			for _, player in players() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					for zone, part in zones do
						if inside(part, root) then
							local event: Events.PlayerEvent = { kind = "EnteredZone", zone = zone }
							task.spawn(handle, player, event)
						end
					end
				end
			end
		end
	end)
end

return PromptBridge
