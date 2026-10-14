--[[
	The volume Setting reaches every sound through one SoundGroup,
	SoundService.Master, which default.project.json puts in the place: the
	client binder sets its Volume, and every Sound plays through it.
]]

local Built = require("./built")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("built place", function()
		it("has the SoundGroup SoundService.Master the volume Setting sets", function()
			local master = Built.place():GetService("SoundService"):FindFirstChild("Master")
			expect(master ~= nil).toBe(true)
			expect(master.ClassName).toBe("SoundGroup")
		end)
	end)
end
