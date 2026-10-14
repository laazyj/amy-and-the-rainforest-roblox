-- ChapterCardTimeline: a Chapter card's and the end card's fade in, hold and fade out.

local ChapterCardTimeline = require("../../../src/core/ChapterCardTimeline")
local StoryEngine = require("../../../src/core/StoryEngine")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	local chapterCard = ChapterCardTimeline.new(false)
	local endCard = ChapterCardTimeline.new(true)

	describe("ChapterCardTimeline", function()
		it("holds a Chapter card 2.4 s and the end card 6 s", function()
			expect(chapterCard.hold).toBe(2.4)
			expect(endCard.hold).toBe(6)
			expect(ChapterCardTimeline.duration(chapterCard)).toBeCloseTo(3.3)
			expect(ChapterCardTimeline.duration(endCard)).toBeCloseTo(6.9)
		end)

		it("is gone by the time the Chapter's first Quest has waited for it", function()
			-- The server waits CHAPTER_CARD_SECONDS after ShowChapterCard; the
			-- card is fully faded out by then (only the hidden flag lags).
			local frame = assert(ChapterCardTimeline.at(chapterCard, StoryEngine.CHAPTER_CARD_SECONDS))
			expect(frame.textTransparency).toBeCloseTo(1)
		end)

		it("starts invisible and fades in, easing out", function()
			local first = ChapterCardTimeline.at(chapterCard, 0)
			expect(first).toEqual({ overlayTransparency = 1, textTransparency = 1 })
			local half = assert(ChapterCardTimeline.at(chapterCard, ChapterCardTimeline.FADE_IN / 2))
			expect(half.textTransparency).toBeCloseTo(0.25) -- 1 - (1 - (1 - 0.5)^2)
			expect(half.overlayTransparency).toBeCloseTo(1 - 0.75 * 0.75)
		end)

		it("holds fully shown over a dark overlay", function()
			for _, seconds in { ChapterCardTimeline.FADE_IN, 1.5, 2.39 } do
				local frame = assert(ChapterCardTimeline.at(chapterCard, seconds))
				expect(frame.textTransparency).toBeCloseTo(0)
				expect(frame.overlayTransparency).toBeCloseTo(ChapterCardTimeline.OVERLAY_SHOWN)
			end
		end)

		it("fades out from the end of the hold, easing in", function()
			local half = assert(ChapterCardTimeline.at(chapterCard, 2.4 + ChapterCardTimeline.FADE_OUT / 2))
			expect(half.textTransparency).toBeCloseTo(0.25)
			expect(half.overlayTransparency).toBeCloseTo(0.25 + 0.75 * 0.25)
			local faded = assert(ChapterCardTimeline.at(chapterCard, 2.4 + ChapterCardTimeline.FADE_OUT))
			expect(faded.textTransparency).toBeCloseTo(1)
			expect(faded.overlayTransparency).toBeCloseTo(1)
		end)

		it("is hidden before it starts and once it is over", function()
			expect(ChapterCardTimeline.at(chapterCard, -0.1)).toBeNil()
			expect(ChapterCardTimeline.at(chapterCard, ChapterCardTimeline.duration(chapterCard))).toBeNil()
			expect(ChapterCardTimeline.at(endCard, 6.5)).never.toBeNil()
			expect(ChapterCardTimeline.at(endCard, 6.9)).toBeNil()
		end)
	end)

	describe("ChapterCardTimeline.skip", function()
		it("fades a Chapter card out from the moment it is skipped", function()
			local card = ChapterCardTimeline.new(false)
			expect(ChapterCardTimeline.skip(card, 1)).toBe(true)
			expect(ChapterCardTimeline.duration(card)).toBe(1 + ChapterCardTimeline.GONE_AFTER)
			expect(ChapterCardTimeline.at(card, 1 + ChapterCardTimeline.GONE_AFTER)).toBeNil()
		end)

		it("lets a card fade in first, so it never jumps to full", function()
			local card = ChapterCardTimeline.new(false)
			ChapterCardTimeline.skip(card, 0.1)
			expect(card.hold).toBe(ChapterCardTimeline.FADE_IN)
		end)

		it("never skips the end card", function()
			local card = ChapterCardTimeline.new(true)
			expect(ChapterCardTimeline.skip(card, 1)).toBe(false)
			expect(card.hold).toBe(ChapterCardTimeline.ENDING_HOLD)
		end)
	end)
end
