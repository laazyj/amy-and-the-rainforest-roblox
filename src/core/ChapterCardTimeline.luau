--!strict
--[[
	ChapterCardTimeline: how a Chapter card (or the end card) plays out over
	time, as plain data (plan section 2.1). The client binder samples it
	every frame and sets what it returns.

	  0 .. FADE_IN          the overlay darkens and the title and subtitle
	                        fade in (quadratic, easing out)
	  .. hold               the card holds, counted from its start: 2.4 s
	                        for a Chapter card, 6 s for the end card
	  hold .. +FADE_OUT     everything fades out (quadratic, easing in)
	  hold + GONE_AFTER     the overlay is hidden; the card is over

	Transparency is Roblox's: 0 is opaque, 1 is invisible.
]]

export type Card = { hold: number }

export type Frame = { overlayTransparency: number, textTransparency: number }

local ChapterCardTimeline = {}

ChapterCardTimeline.FADE_IN = 0.7
ChapterCardTimeline.FADE_OUT = 0.8
ChapterCardTimeline.GONE_AFTER = 0.9
ChapterCardTimeline.CHAPTER_HOLD = 2.4
ChapterCardTimeline.ENDING_HOLD = 6
-- The overlay's transparency while the card holds.
ChapterCardTimeline.OVERLAY_SHOWN = 0.25

function ChapterCardTimeline.new(ending: boolean): Card
	return { hold = if ending then ChapterCardTimeline.ENDING_HOLD else ChapterCardTimeline.CHAPTER_HOLD }
end

-- How long the card lasts, from its start until it is hidden.
function ChapterCardTimeline.duration(card: Card): number
	return card.hold + ChapterCardTimeline.GONE_AFTER
end

-- The card `seconds` after it started; nil before it starts and once it is over.
function ChapterCardTimeline.at(card: Card, seconds: number): Frame?
	if seconds < 0 or seconds >= ChapterCardTimeline.duration(card) then
		return nil
	end
	-- how fully the card shows, from 0 to 1
	local shown
	if seconds < card.hold then
		shown = 1 - (1 - math.min(seconds / ChapterCardTimeline.FADE_IN, 1)) ^ 2
	else
		shown = 1 - math.min((seconds - card.hold) / ChapterCardTimeline.FADE_OUT, 1) ^ 2
	end
	return {
		overlayTransparency = 1 - (1 - ChapterCardTimeline.OVERLAY_SHOWN) * shown,
		textTransparency = 1 - shown,
	}
end

return ChapterCardTimeline
