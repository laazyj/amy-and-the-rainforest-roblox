-- TalkAndAdvance: the Talk-and-advance button advances a Dialogue or uses
-- the nearest prompt.

local TalkAndAdvance = require("../../../src/core/TalkAndAdvance")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("TalkAndAdvance.press", function()
		it("advances the Dialogue while one shows, even with a prompt near", function()
			expect(TalkAndAdvance.press(true, { Dad = 3 })).toBe("advance")
			expect(TalkAndAdvance.press(true, {})).toBe("advance")
		end)

		it("uses the nearest prompt shown otherwise", function()
			expect(TalkAndAdvance.press(false, { Dad = 6, Mum = 2.5, Sam = 9 })).toBe("Mum")
			expect(TalkAndAdvance.press(false, { Dad = 6 })).toBe("Dad")
		end)

		it("does nothing with no Dialogue and no prompt", function()
			expect(TalkAndAdvance.press(false, {})).toBeNil()
		end)
	end)

	describe("TalkAndAdvance.title", function()
		it("says next while a Dialogue shows, talk otherwise", function()
			local labels = { talk = "Talk", next = "Next" }
			expect(TalkAndAdvance.title(true, labels)).toBe("Next")
			expect(TalkAndAdvance.title(false, labels)).toBe("Talk")
		end)
	end)
end
