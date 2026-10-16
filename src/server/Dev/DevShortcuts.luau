--!strict
--[[
	DevShortcuts: Dev builds only (plan section 5.3). Reach any point of
	the Story in seconds: a jump is a Resume (StoryHost.resume) at the
	Progress of a player who has just started the Quest. The jump is
	saved: the player's Save then holds that Progress and the Checkpoints
	of every Chapter up to it, as if they had played there, so "Continue"
	on their next visit comes back to it.

	/title offers the Title screen at the current Progress, as to a
	returning player (StoryHost.offerTitle): the Story waits for the Title
	choice, and Continue carries on where the player was.

	  jumpTo(player, questId)    the jump-to-Quest entry point
	  onCommand(player, text)    a chat command, parsed by core/DevShortcut
	  start()                    makes the chat commands (/chapter, /quest,
	                             /title)

	DevServer.server.luau starts it. Both live in ServerScriptService.Dev,
	which the publish job strips from the Release place (RELEASE_JOB=1,
	tools/lib/release.luau), so a Release build has no shortcuts to call.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Core = ReplicatedStorage:WaitForChild("core")
local DevShortcut = require(Core:WaitForChild("DevShortcut"))
local StoryEngine = require(Core:WaitForChild("StoryEngine"))
local Content = require(ReplicatedStorage:WaitForChild("content"):WaitForChild("Story"))
local StoryHost = require(script.Parent.Parent.StoryHost)

local story = Content.story

local DevShortcuts = {}

function DevShortcuts.jumpTo(player: any, questId: string)
	StoryHost.resume(player, StoryEngine.progressAt(story, questId))
end

-- Does what `text` asks; returns the Quest jumped to or the Chapter the
-- Title screen offers, or nil and why not.
function DevShortcuts.onCommand(player: any, text: string): (string?, string?)
	local shortcut, reason = DevShortcut.parse(story, text)
	if not shortcut then
		return nil, reason
	elseif shortcut.kind == "title" then
		return StoryHost.offerTitle(player)
	end
	DevShortcuts.jumpTo(player, shortcut.quest)
	return shortcut.quest, nil
end

function DevShortcuts.start()
	for _, alias in DevShortcut.COMMANDS do
		local command = Instance.new("TextChatCommand")
		command.Name = `Dev{string.sub(alias, 2)}`
		command.PrimaryAlias = alias
		command.Triggered:Connect(function(source: TextSource, text: string)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player then
				local done, reason = DevShortcuts.onCommand(player, text)
				print(`[DevShortcuts] {player.Name}: {text} -> {done or reason}`)
			end
		end)
		command.Parent = TextChatService
	end
	print("[DevShortcuts] Dev shortcuts ready: " .. table.concat(DevShortcut.COMMANDS, ", "))
end

return DevShortcuts
