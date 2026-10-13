--!strict
--[[
	ScreenLayout: where everything on screen goes, and how big its text is,
	for one Device class, orientation, safe area and Text scale
	(docs/design/feel.md sections 1, 3 and 4), as plain numbers. The client
	binder builds one whenever the viewport, the safe-area insets or the
	Device class change, and sets what it says; all the rules are here, so
	tier 1 checks them at Text scale 1 and 1.5 without a client.

	  new(screen)        the Screen layout: every Rect in UI units from the
	                     viewport's top left (the binder's ScreenGui ignores
	                     the top bar's inset; the safe area accounts for it)
	  lines(text, size, width)
	                     about how many lines `text` wraps to
	  dialogueHeight(layout, text, largeHint)
	                     about how tall the dialogue box grows for a Line
	  spill(layout, lines, first)
	                     the first Line that would not fit the box
	  largestScale(screen, lines, first)
	                     the largest Text scale at which every Line fits
	                     the screen's dialogue box: brief 015's setting is
	                     capped at it
	  ringAround(layout, control, area)
	                     where the Onboarding's ring goes: round Roblox's
	                     thumbstick as it really is on screen, or the left
	                     zone's bottom-left corner while it is not found

	The rules, the same for every class with its own numbers:

	  text sizes      body, speaker and Objective, and hints: 20/18/14 on
	                  a Phone, 24/20/16 on a Tablet and a PC, times the
	                  Text scale (1 to 1.5)
	  dialogue box    at the bottom; its text column is the space there
	                  minus 24 units of padding each side, never wider
	                  than 30 x the body size (60 characters); it grows up
	                  to fit its Line, its name tag staying below the
	                  head window of shot:Dialogue (the speaker's head is
	                  inside y 0.15-0.5 of the viewport), and to at most
	                  40% of the height in phone portrait
	  Objective       the top right; on a Phone it collapses to an icon
	  tracker         while a Dialogue shows
	  touch control   the bottom-left and bottom-right corners of the
	  zones           viewport: 35% x 40% on a Phone, 25% x 35% on a
	                  Tablet; none on a PC. Roblox's thumbstick has the
	                  left one, where the player module puts it (the binder
	                  never moves it); the Talk-and-advance button (and
	                  the Skip button while a Hint shows) sit in the right one
	  touch targets   at least 48 x 48, 8 apart

	While a Dialogue shows on touch, Amy listens: the player's controls are
	disabled (the old full-screen click catcher already took every touch),
	so the box may use the left zone, and keeps clear of the right zone's
	Talk-and-advance button, beside it in landscape and above it in
	portrait. The Skip button shows only in free play (the Onboarding's
	Hint on the first Line is skipped by tapping): above the Talk button on
	touch, and on a PC beside the Hint at the bottom centre.
]]

local DeviceClass = require("./DeviceClass")
local DialogueViewModel = require("./DialogueViewModel")
local TitleScreen = require("./TitleScreen")

type Class = DeviceClass.DeviceClass

export type Rect = { x: number, y: number, width: number, height: number }
-- The safe-area insets from each edge of the viewport: the notch, the home
-- bar, rounded corners and Roblox's top bar.
export type Insets = { left: number, top: number, right: number, bottom: number }
export type Screen = {
	class: Class,
	width: number,
	height: number,
	insets: Insets,
	-- 1 to 1.5; brief 015 adds the setting
	textScale: number,
}

export type TextSizes = { body: number, speaker: number, objective: number, hint: number }

export type Layout = {
	class: Class,
	-- a Phone or a Tablet: touch controls, and a tap on the box advances
	touch: boolean,
	portrait: boolean,
	textScale: number,
	safe: Rect,
	text: TextSizes,
	dialogue: {
		-- the box's left edge, width and bottom edge; it grows upwards
		x: number,
		width: number,
		bottom: number,
		maxHeight: number,
		-- the text column, inside the box's padding on each side
		column: number,
		-- how far the name tag rises above the box's top edge
		overhang: number,
		-- the name tag's height, and the hint row's under the Line: at the
		-- hint size, or the body size for the Onboarding's large Hint
		speaker: number,
		hintRow: number,
		largeHintRow: number,
	},
	objective: { x: number, y: number, width: number, collapses: boolean, icon: Rect },
	-- the touch control zones, left then right; none on a PC
	zones: { Rect },
	-- touch only: the Talk-and-advance button, the ring the Onboarding
	-- draws round where the thumb goes while the thumbstick is not found
	-- (ringAround has it where the thumbstick is), and the one it pulses
	-- round the button
	talk: Rect?,
	ring: Rect?,
	pulse: Rect?,
	-- the onboarding: where a Hint shows in free play, and its Skip button
	hint: Rect,
	skip: Rect,
	-- the title's bottom edge is at `centre`, the subtitle's top `gap` below
	card: { x: number, width: number, centre: number, gap: number, title: number, subtitle: number },
	title: {
		-- the pill label, as wide as its words and padding (estimated),
		-- centred at (x + width / 2, y + height / 2) and tilted by `rotation`
		-- degrees, its left end lower; its words at `text`
		pill: Rect & { text: number, rotation: number },
		x: number,
		width: number,
		bottom: number,
		note: number,
		button: { width: number, height: number, text: number },
		gap: number,
	},
}

local ScreenLayout = {}

-- A Tablet and a PC subtend the same angles (feel.md section 3), so they
-- share their sizes.
local LARGE: TextSizes = table.freeze({ body = 24, speaker = 20, objective = 20, hint = 16 })
ScreenLayout.SIZES = table.freeze({
	Phone = table.freeze({ body = 20, speaker = 18, objective = 18, hint = 14 }),
	Tablet = LARGE,
	PC = LARGE,
} :: { [Class]: TextSizes })

-- The card's title and subtitle, before the Text scale.
local LARGE_CARD = { title = 52, subtitle = 26 }
local CARD: { [Class]: { title: number, subtitle: number } } = {
	Phone = { title = 40, subtitle = 22 },
	Tablet = LARGE_CARD,
	PC = LARGE_CARD,
}

-- Each touch control zone's share of the viewport's width and height.
ScreenLayout.ZONES = table.freeze({
	Phone = table.freeze({ width = 0.35, height = 0.4 }),
	Tablet = table.freeze({ width = 0.25, height = 0.35 }),
} :: { [Class]: { width: number, height: number } })

ScreenLayout.MIN_SCALE = 1
ScreenLayout.MAX_SCALE = 1.5
-- 60 characters of about half the text size each.
ScreenLayout.COLUMN_EMS = 30
ScreenLayout.PADDING = 24
-- The tallest a box may grow in phone portrait, as a share of the height.
ScreenLayout.PORTRAIT_BOX = 0.4
-- Where shot:Dialogue frames the speaker's head (feel.md section 2), as
-- shares of the viewport; nothing covers it (section 1).
ScreenLayout.HEAD_WINDOW = table.freeze({ left = 0.33, right = 0.67, top = 0.15, bottom = 0.5 })
-- largestScale tries the Text scales from the largest down, this far apart.
ScreenLayout.SCALE_STEP = 0.05
ScreenLayout.TARGET = 48
ScreenLayout.TARGET_GAP = 8
-- The longest Skip label the Skip button is sized for, in characters: it
-- fits beside the phone's portrait zone at Text scale 1.5.
ScreenLayout.SKIP_CHARACTERS = 6

-- For the estimates: a character is a little over half the text size wide
-- (feel.md says about half; this leaves room), and a line of text is 1.1
-- times its size tall.
ScreenLayout.CHARACTER = 0.55
ScreenLayout.LINE = 1.1

-- The space between the safe area's edge and what sits at it, and above
-- the bottom edge for the dialogue box, a Hint and the Title screen on a PC.
local MARGIN = 12
local BOTTOM_MARGIN = 24
-- A Title screen button's padding each side of its label.
ScreenLayout.BUTTON_PADDING = 16
-- The title's lines over the safe area, as shares of it: the centre and
-- height of "Amy" and of "& the Rain Forest", and the pill label's centre
-- across (left of the middle, as the website has it); the pill sits just
-- above "Amy".
ScreenLayout.TITLE = table.freeze({
	pill = 0.44,
	name = table.freeze({ y = 0.29, height = 0.15 }),
	rest = table.freeze({ y = 0.43, height = 0.13 }),
})
-- The pill's padding each side of and above and below its words, and its
-- tilt in degrees.
ScreenLayout.PILL = table.freeze({ side = 18, ends = 6, rotation = -4 })
-- The Objective tracker's padding (above, below and each side) and the gap
-- under its header; and its width, in Objective text sizes.
ScreenLayout.TRACKER = table.freeze({ top = 8, bottom = 10, side = 14, between = 4 })
local TRACKER_EMS = 18
-- The dialogue box's padding above its text and below its hint row, and
-- the gap between them (its sides are PADDING); how far below the box's
-- top edge the Speaker's name tag ends (it rises above the box), and the
-- tag's padding round its name, above and below.
ScreenLayout.BOX = table.freeze({ top = 18, bottom = 10, between = 6, tag = 6, tagPadding = 12 })
local TALK: { [Class]: number } = { Phone = 64, Tablet = 72 }
local RING: { [Class]: number } = { Phone = 96, Tablet = 112 }

-- The longest Title screen label, in graphemes.
local LABEL_LENGTH = 0
for _, label in TitleScreen.LABELS do
	LABEL_LENGTH = math.max(LABEL_LENGTH, DialogueViewModel.graphemes(label))
end

local function rect(x: number, y: number, width: number, height: number): Rect
	return { x = x, y = y, width = width, height = height }
end

-- About how many lines `text` wraps to at `size` in a column `width` wide.
function ScreenLayout.lines(text: string, size: number, width: number): number
	local perLine = math.max(1, math.floor(width / (size * ScreenLayout.CHARACTER)))
	local lines, used = 1, 0
	for word in string.gmatch(text, "%S+") do
		local length = DialogueViewModel.graphemes(word)
		if used > 0 and used + 1 + length > perLine then
			lines += 1
			used = 0
		end
		used += if used > 0 then 1 + length else length
		while used > perLine do -- a word longer than a line breaks
			lines += 1
			used -= perLine
		end
	end
	return lines
end

-- About how tall a block of `text` is at `size` in a column `width` wide.
local function textHeight(text: string, size: number, width: number): number
	return ScreenLayout.lines(text, size, width) * size * ScreenLayout.LINE
end

-- About how tall the dialogue box grows for a Line of `text`, its hint row
-- at the body size when `largeHint` (the onboarding's first Line).
function ScreenLayout.dialogueHeight(layout: Layout, text: string, largeHint: boolean): number
	local hint = if largeHint then layout.text.body else layout.text.hint
	local box = ScreenLayout.BOX
	return box.top
		+ textHeight(text, layout.text.body, layout.dialogue.column)
		+ box.between
		+ hint * ScreenLayout.LINE
		+ box.bottom
end

-- About how tall the Objective tracker grows for an Objective.
function ScreenLayout.objectiveHeight(layout: Layout, text: string): number
	local size = layout.text.objective
	local tracker = ScreenLayout.TRACKER
	return tracker.top
		+ size * ScreenLayout.LINE
		+ tracker.between
		+ textHeight(text, size, layout.objective.width - 2 * tracker.side)
		+ tracker.bottom
end

local function round(size: number, scale: number): number
	return math.floor(size * scale + 0.5)
end

local function scaled(sizes: TextSizes, scale: number): TextSizes
	return {
		body = round(sizes.body, scale),
		speaker = round(sizes.speaker, scale),
		objective = round(sizes.objective, scale),
		hint = round(sizes.hint, scale),
	}
end

-- The safe-area insets of `safe` inside `screen`, both as the engine
-- measures them (absolute position and size); never negative.
function ScreenLayout.insets(screen: Rect, safe: Rect): Insets
	return {
		left = math.max(0, safe.x - screen.x),
		top = math.max(0, safe.y - screen.y),
		right = math.max(0, screen.x + screen.width - (safe.x + safe.width)),
		bottom = math.max(0, screen.y + screen.height - (safe.y + safe.height)),
	}
end

-- A text column as wide as `space` allows, padding taken off, up to the cap.
local function column(space: number, body: number): number
	return math.min(space - 2 * ScreenLayout.PADDING, ScreenLayout.COLUMN_EMS * body)
end

function ScreenLayout.new(screen: Screen): Layout
	local class: Class = screen.class -- annotated: the Roblox checker widens it through the sourcemap
	local width, height, insets = screen.width, screen.height, screen.insets
	local scale = math.clamp(screen.textScale, ScreenLayout.MIN_SCALE, ScreenLayout.MAX_SCALE)
	local portrait = DeviceClass.portrait(width, height)
	local text = scaled(ScreenLayout.SIZES[class], scale)
	local safe = rect(insets.left, insets.top, width - insets.left - insets.right, height - insets.top - insets.bottom)
	local right, bottom = safe.x + safe.width, safe.y + safe.height
	local touch = class ~= "PC"
	local collapses = class == "Phone"

	local objectiveWidth = math.min(safe.width - 2 * MARGIN, TRACKER_EMS * text.objective)
	local objectiveX = right - MARGIN - objectiveWidth
	local icon = rect(right - MARGIN - ScreenLayout.TARGET, safe.y + MARGIN, ScreenLayout.TARGET, ScreenLayout.TARGET)
	local skipWidth = math.max(
		ScreenLayout.TARGET,
		math.ceil(ScreenLayout.SKIP_CHARACTERS * ScreenLayout.CHARACTER * text.hint) + 2 * MARGIN
	)
	-- a Hint in free play is two lines high, at most 60 characters wide
	local hintHeight = 2 * text.hint * ScreenLayout.LINE + MARGIN
	local hintWidth = math.min(safe.width - 2 * MARGIN, ScreenLayout.COLUMN_EMS * text.hint)
	local zones: { Rect } = {}
	local talk, ring, pulse, skip, hint, box
	if touch then
		local share = ScreenLayout.ZONES[class]
		local zoneWidth, zoneHeight = width * share.width, height * share.height
		zones = {
			rect(0, height - zoneHeight, zoneWidth, zoneHeight),
			rect(width - zoneWidth, height - zoneHeight, zoneWidth, zoneHeight),
		}

		-- the right zone's buttons, in a column at the bottom-right corner
		local size = TALK[class]
		talk = rect(right - MARGIN - size, bottom - MARGIN - size, size, size)
		skip = rect(
			right - MARGIN - skipWidth,
			talk.y - ScreenLayout.TARGET_GAP - ScreenLayout.TARGET,
			skipWidth,
			ScreenLayout.TARGET
		)
		local around = 6
		pulse = rect(talk.x - around, talk.y - around, size + 2 * around, size + 2 * around)

		-- the left zone's bottom-left corner, inside the safe area, where
		-- Roblox puts its thumbstick
		local reach = RING[class]
		local left = zones[1]
		ring = rect(
			math.max(safe.x, left.x) + MARGIN,
			math.min(bottom, left.y + left.height) - MARGIN - reach,
			reach,
			reach
		)
		-- a Hint: just above the thumbstick's zone, at the left, and in
		-- landscape clear of the Objective tracker to its right
		if not portrait then
			hintWidth = math.min(hintWidth, objectiveX - ScreenLayout.TARGET_GAP - (safe.x + MARGIN))
		end
		hint = rect(safe.x + MARGIN, left.y - ScreenLayout.TARGET_GAP - hintHeight, hintWidth, hintHeight)

		if portrait then
			box = { left = safe.x, space = safe.width, bottom = talk.y - ScreenLayout.TARGET_GAP }
		else
			local space = talk.x - ScreenLayout.TARGET_GAP - (safe.x + MARGIN)
			box = { left = safe.x + MARGIN, space = space, bottom = bottom - MARGIN }
		end
	else
		hint = rect(safe.x + (safe.width - hintWidth) / 2, bottom - BOTTOM_MARGIN - hintHeight, hintWidth, hintHeight)
		-- beside the Hint, its bottom edge level with the Hint's: clear of
		-- the top-left corner, where Roblox's own buttons sit
		skip = rect(
			hint.x + hint.width + ScreenLayout.TARGET_GAP,
			hint.y + hint.height - ScreenLayout.TARGET,
			skipWidth,
			ScreenLayout.TARGET
		)
		box = { left = safe.x + MARGIN, space = safe.width - 2 * MARGIN, bottom = bottom - BOTTOM_MARGIN }
	end

	local speaker = text.speaker + ScreenLayout.BOX.tagPadding
	local overhang = speaker - ScreenLayout.BOX.tag
	local textColumn = column(box.space, text.body)
	local boxWidth = textColumn + 2 * ScreenLayout.PADDING
	local boxX = box.left + (box.space - boxWidth) / 2
	-- the name tag stays below the head window; in phone portrait the box
	-- also grows to at most 40% of the height
	local maxHeight = box.bottom - (height * ScreenLayout.HEAD_WINDOW.bottom + overhang)
	if class == "Phone" and portrait then
		maxHeight = math.min(maxHeight, ScreenLayout.PORTRAIT_BOX * height)
	end

	local titleWidth = safe.width - 2 * MARGIN
	-- the pill's words at the body size, smaller (down to the hint size)
	-- until the pill, tilted, fits across the safe area and above "Amy"
	local pill = ScreenLayout.PILL
	local tilt = math.rad(math.abs(pill.rotation))
	local pillCharacters = DialogueViewModel.graphemes(TitleScreen.WORDS.pill)
	local nameTop = safe.y + safe.height * (ScreenLayout.TITLE.name.y - ScreenLayout.TITLE.name.height / 2)
	local pillText, pillWidth, pillHeight, pillTall
	for size = text.body, text.hint, -1 do
		pillText = size
		pillWidth = math.ceil(pillCharacters * ScreenLayout.CHARACTER * size) + 2 * pill.side
		pillHeight = math.ceil(size * ScreenLayout.LINE) + 2 * pill.ends
		pillTall = pillWidth * math.sin(tilt) + pillHeight * math.cos(tilt)
		local pillWide = pillWidth * math.cos(tilt) + pillHeight * math.sin(tilt)
		if pillWide <= titleWidth and pillTall <= nameTop - safe.y then
			break
		end
	end
	local pillCentre = math.clamp(
		safe.x + safe.width * ScreenLayout.TITLE.pill,
		safe.x + MARGIN + pillWidth / 2,
		right - MARGIN - pillWidth / 2
	)
	local pillMiddle = math.max(safe.y + pillTall / 2, nameTop - pillTall / 2)

	return {
		class = class,
		touch = touch,
		portrait = portrait,
		textScale = scale,
		safe = safe,
		text = text,
		dialogue = {
			x = boxX,
			width = boxWidth,
			bottom = box.bottom,
			maxHeight = maxHeight,
			column = textColumn,
			overhang = overhang,
			speaker = speaker,
			hintRow = math.ceil(text.hint * ScreenLayout.LINE),
			largeHintRow = math.ceil(text.body * ScreenLayout.LINE),
		},
		objective = {
			x = objectiveX,
			y = icon.y,
			width = objectiveWidth,
			collapses = collapses,
			icon = icon,
		},
		zones = zones,
		talk = talk,
		ring = ring,
		pulse = pulse,
		hint = hint,
		skip = skip,
		card = {
			x = safe.x + 2 * MARGIN,
			width = safe.width - 4 * MARGIN,
			centre = safe.y + safe.height * 0.44,
			gap = ScreenLayout.TARGET_GAP,
			title = round(CARD[class].title, scale),
			subtitle = round(CARD[class].subtitle, scale),
		},
		title = {
			pill = {
				x = pillCentre - pillWidth / 2,
				y = pillMiddle - pillHeight / 2,
				width = pillWidth,
				height = pillHeight,
				text = pillText,
				rotation = pill.rotation,
			},
			x = safe.x + MARGIN,
			width = titleWidth,
			bottom = bottom - BOTTOM_MARGIN,
			note = text.body,
			button = {
				width = math.min(
					titleWidth,
					math.ceil(LABEL_LENGTH * ScreenLayout.CHARACTER * text.body) + 2 * ScreenLayout.BUTTON_PADDING
				),
				height = math.max(ScreenLayout.TARGET, 2 * text.body),
				text = text.body,
			},
			gap = ScreenLayout.TARGET_GAP + 2,
		},
	}
end

-- Where the Onboarding's ring goes round `control`, Roblox's thumbstick's
-- frame as it is on screen (in layout units), or nil while it is not
-- found: then the layout's ring, in the left zone's bottom-left corner.
-- The classic thumbstick's frame is the stick itself, and the ring is
-- centred on it; the dynamic thumbstick's (`area`) is its touch area, and
-- the ring sits in its bottom-left corner, where the stick rests. Always
-- inside the safe area; nil on a PC.
function ScreenLayout.ringAround(layout: Layout, control: Rect?, area: boolean): Rect?
	local fallback = layout.ring
	if not (fallback and control and control.width > 0 and control.height > 0) then
		return fallback
	end
	local reach = fallback.width
	local x, y
	if area then
		x, y = control.x + MARGIN, control.y + control.height - MARGIN - reach
	else
		x, y = control.x + (control.width - reach) / 2, control.y + (control.height - reach) / 2
	end
	local safe = layout.safe
	return rect(
		math.clamp(x, safe.x, safe.x + safe.width - reach),
		math.clamp(y, safe.y, safe.y + safe.height - reach),
		reach,
		reach
	)
end

-- The first Line of `lines` that would not fit `layout`'s dialogue box
-- without scrolling, `first` (the Onboarding's first Line) with its large
-- Hint; nil when every one fits.
function ScreenLayout.spill(layout: Layout, lines: { string }, first: string?): string?
	for _, text in lines do
		if ScreenLayout.dialogueHeight(layout, text, text == first) > layout.dialogue.maxHeight then
			return text
		end
	end
	return nil
end

-- The largest Text scale, from 1.5 down to 1 in steps of 0.05, at which
-- every Line of `lines` fits `screen`'s dialogue box; nil when even scale
-- 1 does not.
function ScreenLayout.largestScale(screen: Screen, lines: { string }, first: string?): number?
	local steps = math.round((ScreenLayout.MAX_SCALE - ScreenLayout.MIN_SCALE) / ScreenLayout.SCALE_STEP)
	for step = steps, 0, -1 do
		local atScale = table.clone(screen)
		atScale.textScale = ScreenLayout.MIN_SCALE + step * ScreenLayout.SCALE_STEP
		if not ScreenLayout.spill(ScreenLayout.new(atScale), lines, first) then
			return atScale.textScale
		end
	end
	return nil
end

return ScreenLayout
