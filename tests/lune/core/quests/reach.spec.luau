-- Quest Kind reach: EnteredZone for the Quest's Zone.

local reach = require("../../../../src/core/quests/reach")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect
	local quest: any =
		{ id = "chapter2.enter_forest", kind = "reach", zone = "ForestGap", objective = "Squeeze through" }

	describe("reach", function()
		it("needs nothing set up", function()
			expect(reach.begin(quest, {})).toEqual({})
		end)

		it("is done on EnteredZone(ForestGap)", function()
			expect(reach.handle(quest, {}, { kind = "EnteredZone", zone = "ForestGap" })).toEqual({
				commands = {},
				done = true,
			})
		end)

		it("ignores another Zone and other Player events", function()
			expect(reach.handle(quest, {}, { kind = "EnteredZone", zone = "ForestEdge" })).toBeNil()
			expect(reach.handle(quest, {}, { kind = "TalkedTo", character = "Dad" })).toBeNil()
		end)

		it("shows its Objective as written", function()
			expect(reach.objective(quest, {})).toBe("Squeeze through")
		end)
	end)
end
