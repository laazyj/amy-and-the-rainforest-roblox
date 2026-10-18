--[[
	TextChatService.ChatVersion is place-level, like Lighting.Technology
	(lighting.spec): only default.project.json can set it, so this spec reads
	it back from the built place. Unset, a Rojo build gets the legacy chat,
	in which the Dev shortcuts' TextChatCommands never fire and StoryHost's
	Config.chat switch (ChatWindowConfiguration, ChatInputBarConfiguration)
	hides nothing.
]]

local Built = require("./built")
local roblox = require("@lune/roblox") :: any

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("built place", function()
		it("chats through TextChatService, which the Dev shortcuts and Config.chat need", function()
			local chat = Built.place():GetService("TextChatService")
			expect(chat.ChatVersion).toBe(roblox.Enum.ChatVersion.TextChatService)
		end)
	end)
end
