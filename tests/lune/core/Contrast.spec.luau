-- Contrast: WCAG 2's contrast ratio of two plain colours.

local Contrast = require("../../../src/core/Contrast")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	local white = { r = 255, g = 255, b = 255 }
	local black = { r = 0, g = 0, b = 0 }

	describe("Contrast.ratio", function()
		it("is 21:1 for black on white and 1:1 for a colour on itself, either way round", function()
			expect(Contrast.ratio(black, white)).toBe(21)
			expect(Contrast.ratio(white, black)).toBe(21)
			expect(Contrast.ratio(white, white)).toBe(1)
		end)

		it("puts mid grey (#777) just under feel.md's 4.5:1 on white", function()
			local grey = { r = 0x77, g = 0x77, b = 0x77 }
			expect(Contrast.ratio(grey, white) < Contrast.MINIMUM).toBe(true)
			expect(Contrast.ratio(grey, white) > 4.4).toBe(true)
		end)
	end)

	describe("Contrast.over", function()
		it("is the colour itself when opaque, the backdrop when clear, and their mix between", function()
			local red = { r = 200, g = 0, b = 0 }
			expect(Contrast.over(red, 0, white)).toEqual(red)
			expect(Contrast.over(red, 1, white)).toEqual(white)
			expect(Contrast.over(red, 0.5, black)).toEqual({ r = 100, g = 0, b = 0 })
		end)

		it("asks 7:1 for the high-contrast Setting, above the usual 4.5:1", function()
			expect(Contrast.HIGH).toBe(7)
			expect(Contrast.HIGH > Contrast.MINIMUM).toBe(true)
		end)
	end)
end
