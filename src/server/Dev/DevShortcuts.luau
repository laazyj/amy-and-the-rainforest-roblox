--!strict
--[[
	DevShortcuts: Dev builds only (plan section 5.3). Reach any point of
	the Story in seconds: a jump is a Resume (StoryHost.resume) at the
	Progress of a player who has just started the Quest.

	  jumpTo(player, questId)    the jump-to-Quest entry point
	  onCommand(player, text)    a chat command, parsed by core/DevShortcut
	  start()                    makes the chat commands (/chapter, /quest)

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

-- Jumps where `text` says; returns the Quest, or nil and why not.
function DevShortcuts.onCommand(player: any, text: string): (string?, string?)
	local questId, reason = DevShortcut.parse(story, text)
	if questId then
		DevShortcuts.jumpTo(player, questId)
	end
	return questId, reason
end

function DevShortcuts.start()
	for _, alias in DevShortcut.COMMANDS do
		local command = Instance.new("TextChatCommand")
		command.Name = `Dev{string.sub(alias, 2)}`
		command.PrimaryAlias = alias
		command.Triggered:Connect(function(source: TextSource, text: string)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player then
				local questId, reason = DevShortcuts.onCommand(player, text)
				print(`[DevShortcuts] {player.Name}: {text} -> {questId or reason}`)
			end
		end)
		command.Parent = TextChatService
	end
	print("[DevShortcuts] Dev shortcuts ready: " .. table.concat(DevShortcut.COMMANDS, ", "))
end

return DevShortcuts
