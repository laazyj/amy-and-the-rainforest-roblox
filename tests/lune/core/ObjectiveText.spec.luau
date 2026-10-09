-- ObjectiveText: what the Objective tracker shows for a SetObjective.

local ObjectiveText = require("../../../src/core/ObjectiveText")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("ObjectiveText.view", function()
		it("shows an Objective", function()
			expect(ObjectiveText.view("Ask Dad if you can go outside")).toEqual({
				visible = true,
				text = "Ask Dad if you can go outside",
			})
			expect(ObjectiveText.HEADER).toBe("✦ Objective")
		end)

		it("trims the space around an Objective", function()
			expect(ObjectiveText.view("  Pick flowers  (1/2)\n").text).toBe("Pick flowers  (1/2)")
		end)

		it("hides the tracker when SetObjective clears it", function()
			expect(ObjectiveText.view(nil).visible).toBe(false)
			expect(ObjectiveText.view("").visible).toBe(false)
			expect(ObjectiveText.view(" \t").visible).toBe(false)
		end)
	end)
end
