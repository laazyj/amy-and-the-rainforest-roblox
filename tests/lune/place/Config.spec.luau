--[[
	Config (src/server/Config.luau), loaded with a stand-in for its
	`script`: its shape, and that Roblox's text chat is on in a Dev build
	and off in a Release build, which has no ServerScriptService.Dev
	(tools/lib/release.luau strips it).
]]

local Release = require("../../../tools/lib/release")
local bootstrap = require("../bootstrap")
local luau = require("@lune/luau")

-- Config as the server would require it, in a ServerScriptService that has
-- the Dev folder or not.
local function config(hasDev: boolean): { [string]: any }
	local serverScripts = {
		FindFirstChild = function(_, name: string)
			return if hasDev and name == Release.DEV_ONLY then {} else nil
		end,
	}
	local source = bootstrap.readSource("src/server/Config.luau")
	return luau.load(source, { debugName = "Config", environment = { script = { Parent = serverScripts } } })()
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("Config", function()
		it("holds a store prefix and the chat switch, nothing else", function()
			local keys = {}
			for key, value in config(true) do
				table.insert(keys, `{key}:{typeof(value)}`)
			end
			table.sort(keys)
			expect(keys).toEqual({ "chat:boolean", "storePrefix:string" })
			expect(config(true).storePrefix).toBe("")
		end)

		it("turns Roblox's text chat on in a Dev build, where the Dev shortcuts are chat commands", function()
			expect(config(true).chat).toBe(true)
		end)

		it("turns it off in a Release build, which has no Dev folder", function()
			expect(config(false).chat).toBe(false)
		end)
	end)
end
