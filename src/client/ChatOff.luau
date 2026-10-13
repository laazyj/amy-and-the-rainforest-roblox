--!strict
--[[
	ChatOff: the chat is off (docs/design/feel.md section 5, "Chat off").
	The game is single player for ages 7 to 12, so there is no one to chat
	with: no chat window, and Roblox's Chat core GUI (the top bar's chat
	button and the input bar) is off. Both are the client's to set: StarterGui's
	SetCoreGuiEnabled works only on the client, and TextChatService's
	ChatWindowConfiguration and ChatInputBarConfiguration are read by each
	client's own chat UI.

	Dev builds only: the Dev shortcuts are chat commands (/chapter, /quest),
	so where DevShortcuts has marked TextChatService (DevShortcut's
	CHAT_ATTRIBUTE), the input bar stays to type them in; the window stays
	off. A Release place has no Dev folder, so no mark, and no chat at all.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local DevShortcut = require(ReplicatedStorage:WaitForChild("core"):WaitForChild("DevShortcut"))

-- Set on TextChatService by the server's DevShortcuts, in Dev builds only.
local DEV_ATTRIBUTE = DevShortcut.CHAT_ATTRIBUTE

local ChatOff = {}

local function apply()
	local dev = TextChatService:GetAttribute(DEV_ATTRIBUTE) == true
	local window = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if window then
		window.Enabled = false
	end
	local bar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
	if bar then
		bar.Enabled = dev
	end
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, dev)
end

function ChatOff.start()
	apply()
	-- the mark, and the configurations, can arrive after the client starts
	TextChatService:GetAttributeChangedSignal(DEV_ATTRIBUTE):Connect(apply)
	TextChatService.ChildAdded:Connect(apply)
end

return ChatOff
