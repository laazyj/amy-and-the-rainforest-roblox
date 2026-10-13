--!strict
-- Roblox's text chat (the owner's decision): on in Dev, where the Dev
-- shortcuts are chat commands, and off on Release. Config.chat follows the
-- Dev folder, which only a Release build lacks (tests/lune/place/Config.spec
-- checks both); here, on Dev as built, StoryHost turns the chat window and
-- input bar on.

include("tests/engine/_world.luau").build(false, "chat")

local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")

describe("chat on Dev", function()
	it("has the Dev folder, so Config.chat is on", function()
		local Config = (require :: any)(ServerScriptService:WaitForChild("Config"))
		expect(ServerScriptService:FindFirstChild("Dev") ~= nil).toBe(true)
		expect(Config.chat).toBe(true)
	end)

	it("shows Roblox's chat window and input bar, which the Dev shortcuts need", function()
		for _, class in { "ChatWindowConfiguration", "ChatInputBarConfiguration" } do
			local chat: any = TextChatService:FindFirstChildOfClass(class)
			expect(chat).toBeTruthy()
			expect(chat.Enabled).toBe(true)
		end
	end)
end)

finish()
