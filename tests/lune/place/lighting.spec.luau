--[[
	Lighting.Technology is place-level: only default.project.json can set it,
	and engine tests cannot check it, because Luau Execution scripts lack the
	capability to read it. So this spec builds the place with Rojo and reads the
	property back from the built file, which is what Studio and players load.
]]

local Built = require("./built")
local roblox = require("@lune/roblox") :: any

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("built place", function()
		it("uses the ShadowMap lighting technology set in default.project.json", function()
			local lighting = Built.place():GetService("Lighting")
			expect(lighting.Technology).toBe(roblox.Enum.Technology.ShadowMap)
		end)
	end)
end
