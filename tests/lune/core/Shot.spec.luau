--[[
	Shot: the Shots are the glossary's, and only the Shots that accompany
	a Dialogue hold; every other lasts at most 4 seconds.
]]

local Shot = require("../../../src/core/Shot")
local glossary = require("../content/glossary")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("Shot", function()
		it("names exactly the glossary's Shots", function()
			local names = {}
			for name in glossary.names("Shots") do
				table.insert(names, name)
			end
			table.sort(names)
			local ours = table.clone(Shot.NAMES)
			table.sort(ours)
			expect(ours).toEqual(names)
		end)

		it("holds shot:Dialogue and shot:MachineFinale until DialogueFinished", function()
			expect(Shot.HELD).toEqual({ Dialogue = true, MachineFinale = true })
		end)

		it("lasts at most 4 seconds, unless held until DialogueFinished", function()
			for _, name in Shot.NAMES do
				local seconds = Shot.SECONDS[name]
				expect(Shot.HELD[name] == true or (seconds ~= nil and seconds <= Shot.LONGEST)).toBe(true)
			end
		end)

		it("eases in and hands back over 0.5 s", function()
			expect(Shot.EASE_IN).toBe(0.5)
			expect(Shot.HAND_BACK).toBe(0.5)
		end)
	end)
end
