--!strict
-- Plays a fake player's active Quest as a player would, one action per
-- call: presses the talk prompt of a `talk` Quest's Character once it is
-- offered, or stands the player in a `reach` Quest's Zone (the host's Zone
-- poll turns that into EnteredZone). Shared by the walkthrough and the
-- tests that walk the Story (isolation, resume). A test gets it with
-- include("tests/engine/_driver.luau").new(StoryHost, CharacterHost).
--
-- TouchedPickup has no driver yet: the Story has no `collect` Quest.

local FakePlayer = include("tests/engine/_fakeplayer.luau")

local Workspace = game:GetService("Workspace")

local Driver = {}

function Driver.new(server: any, characterHost: any): (player: any) -> ()
	local prompts: { [string]: ProximityPrompt } = characterHost.prompts()
	local zones = Workspace:WaitForChild("StoryZones")
	return function(player)
		local questId, quest = server.activeQuest(player)
		if not quest then
			return
		elseif quest.kind == "talk" then
			-- The handler withdraws the prompt before it first yields.
			if prompts[quest.character].Enabled then
				task.spawn(server.onTalkPromptTriggered, quest.character, player)
			end
		elseif quest.kind == "reach" then
			FakePlayer.moveTo(player, (zones:FindFirstChild(quest.zone) :: BasePart).Position)
		else
			error(`no driver for a {quest.kind} Quest ({questId}); add one with the first such Quest`)
		end
	end
end

return Driver
