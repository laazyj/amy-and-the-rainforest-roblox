-- ChapterCardTimeline: a Chapter card's and the end card's fade in, hold and fade out.

local ChapterCardTimeline = require("../../../src/core/ChapterCardTimeline")
local StoryEngine = require("../../../src/core/StoryEngine")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	local chapterCard = ChapterCardTimeline.new(false)
	local endCard = ChapterCardTimeline.new(true)

	local function near(actual: number, expected: number)
		expect(math.abs(actual - expected) < 1e-9).toBe(true)
	end

	describe("ChapterCardTimeline", function()
		it("holds a Chapter card 2.4 s and the end card 6 s", function()
			expect(chapterCard.hold).toBe(2.4)
			expect(endCard.hold).toBe(6)
			near(ChapterCardTimeline.duration(chapterCard), 3.3)
			near(ChapterCardTimeline.duration(endCard), 6.9)
		end)

		it("is gone by the time the Chapter's first Quest has waited for it", function()
			-- The server waits CHAPTER_CARD_SECONDS after ShowChapterCard; the
			-- card is fully faded out by then (only the hidden flag lags).
			local frame = assert(ChapterCardTimeline.at(chapterCard, StoryEngine.CHAPTER_CARD_SECONDS))
			near(frame.textTransparency, 1)
		end)

		it("starts invisible and fades in, easing out", function()
			local first = ChapterCardTimeline.at(chapterCard, 0)
			expect(first).toEqual({ overlayTransparency = 1, textTransparency = 1 })
			local half = assert(ChapterCardTimeline.at(chapterCard, ChapterCardTimeline.FADE_IN / 2))
			near(half.textTransparency, 0.25) -- 1 - (1 - (1 - 0.5)^2)
			near(half.overlayTransparency, 1 - 0.75 * 0.75)
		end)

		it("holds fully shown over a dark overlay", function()
			for _, seconds in { ChapterCardTimeline.FADE_IN, 1.5, 2.39 } do
				local frame = assert(ChapterCardTimeline.at(chapterCard, seconds))
				near(frame.textTransparency, 0)
				near(frame.overlayTransparency, ChapterCardTimeline.OVERLAY_SHOWN)
			end
		end)

		it("fades out from the end of the hold, easing in", function()
			local half = assert(ChapterCardTimeline.at(chapterCard, 2.4 + ChapterCardTimeline.FADE_OUT / 2))
			near(half.textTransparency, 0.25)
			near(half.overlayTransparency, 0.25 + 0.75 * 0.25)
			local faded = assert(ChapterCardTimeline.at(chapterCard, 2.4 + ChapterCardTimeline.FADE_OUT))
			near(faded.textTransparency, 1)
			near(faded.overlayTransparency, 1)
		end)

		it("is hidden before it starts and once it is over", function()
			expect(ChapterCardTimeline.at(chapterCard, -0.1)).toBeNil()
			expect(ChapterCardTimeline.at(chapterCard, ChapterCardTimeline.duration(chapterCard))).toBeNil()
			expect(ChapterCardTimeline.at(endCard, 6.5)).never.toBeNil()
			expect(ChapterCardTimeline.at(endCard, 6.9)).toBeNil()
		end)
	end)
end
