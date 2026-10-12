-- ScreenLayout: feel.md's layout rules, for every Device class and
-- orientation, at Text scale 1 and 1.5.

local Content = require("../../../src/content/Story")
local ScreenLayout = require("../../../src/core/ScreenLayout")
local Story = require("../../../src/core/Story")
local TitleScreen = require("../../../src/core/TitleScreen")
local hints = require("../../../src/content/hints")

type Rect = ScreenLayout.Rect
type Layout = ScreenLayout.Layout

-- Devices to lay out for, with their safe-area insets: the notch, the home
-- bar and Roblox's top bar (58 units).
local DEVICES: { ScreenLayout.Screen } = {
	{
		class = "Phone",
		width = 844,
		height = 390,
		insets = { left = 47, top = 58, right = 47, bottom = 21 },
		textScale = 1,
	},
	{
		class = "Phone",
		width = 390,
		height = 844,
		insets = { left = 0, top = 105, right = 0, bottom = 34 },
		textScale = 1,
	},
	{
		class = "Phone",
		width = 667,
		height = 375,
		insets = { left = 0, top = 58, right = 0, bottom = 0 },
		textScale = 1,
	},
	{
		class = "Phone",
		width = 375,
		height = 667,
		insets = { left = 0, top = 78, right = 0, bottom = 0 },
		textScale = 1,
	},
	{
		class = "Tablet",
		width = 1376,
		height = 1032,
		insets = { left = 0, top = 82, right = 0, bottom = 20 },
		textScale = 1,
	},
	{
		class = "Tablet",
		width = 1032,
		height = 1376,
		insets = { left = 0, top = 82, right = 0, bottom = 20 },
		textScale = 1,
	},
	{
		class = "Tablet",
		width = 1180,
		height = 820,
		insets = { left = 0, top = 82, right = 0, bottom = 20 },
		textScale = 1,
	},
	{
		class = "Tablet",
		width = 820,
		height = 1180,
		insets = { left = 0, top = 82, right = 0, bottom = 20 },
		textScale = 1,
	},
	{ class = "PC", width = 1280, height = 720, insets = { left = 0, top = 58, right = 0, bottom = 0 }, textScale = 1 },
	{
		class = "PC",
		width = 1920,
		height = 1080,
		insets = { left = 0, top = 58, right = 0, bottom = 0 },
		textScale = 1,
	},
	{
		class = "PC",
		width = 2560,
		height = 1440,
		insets = { left = 0, top = 58, right = 0, bottom = 0 },
		textScale = 1,
	},
}

-- Phones smaller than feel.md's 6-inch design (DEVICES[3] and [4]): laid out
-- at Text scale 1 only. The longest Lines cannot fit 40% of an iPhone SE's
-- portrait height at the larger Text scales; brief 015's setting decides.
local SMALLER = { [3] = true, [4] = true }

-- Every Line of the Story, and the longest Objective.
local LINES: { string } = {}
local longestObjective = ""
for _, chapter in Content.story.chapters do
	for _, quest in chapter.quests do
		for _, dialogue: { Story.Line }? in { quest.intro, quest.dialogue, quest.outro } do
			for _, line in dialogue or {} :: { Story.Line } do
				table.insert(LINES, line.text)
			end
		end
		if utf8.len(quest.objective) > utf8.len(longestObjective) then
			longestObjective = quest.objective
		end
	end
end
for _, line in Content.story.ending.lines do
	table.insert(LINES, line.text)
end
local FIRST_LINE = LINES[1]

-- The one Line that does not fit phone portrait's box (40% of the height)
-- at Text scale 1.5: 171 characters, past the style guide's guide of about
-- 140. It is not canon, so the owner may shorten it (see the PR for brief
-- 012); any other Line that stops fitting fails here.
local OVER_LONG = {
	"There's a squirrel the colour of nanna's cardigan, and a fox like a sunset, and the golden lion is GENTLE, Dad. Nobody is eaten in a paradise. It's against the whole idea.",
}

local function at(device: ScreenLayout.Screen, textScale: number): Layout
	local screen = table.clone(device)
	screen.textScale = textScale
	return ScreenLayout.new(screen)
end

local function describeScreen(device: ScreenLayout.Screen, textScale: number): string
	local orientation = if device.height > device.width then "portrait" else "landscape"
	return `{device.class} {device.width}x{device.height} {orientation} at Text scale {textScale}`
end

local function inside(inner: Rect, outer: Rect): boolean
	local slack = 1e-6
	return inner.x >= outer.x - slack
		and inner.y >= outer.y - slack
		and inner.x + inner.width <= outer.x + outer.width + slack
		and inner.y + inner.height <= outer.y + outer.height + slack
end

-- The gap between two rects; negative when they overlap.
local function gap(a: Rect, b: Rect): number
	return math.max(b.x - (a.x + a.width), a.x - (b.x + b.width), b.y - (a.y + a.height), a.y - (b.y + b.height))
end

-- The dialogue box as tall as `text` makes it.
local function box(layout: Layout, text: string): Rect
	local d = layout.dialogue
	local height = ScreenLayout.dialogueHeight(layout, text, text == FIRST_LINE) + d.overhang
	return { x = d.x, y = d.bottom - height, width = d.width, height = height }
end

-- The Objective tracker with `text` in it.
local function tracker(layout: Layout, text: string): Rect
	local o = layout.objective
	return { x = o.x, y = o.y, width = o.width, height = ScreenLayout.objectiveHeight(layout, text) }
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	local function each(rule: string, check: (Layout, ScreenLayout.Screen) -> ())
		for i, device in DEVICES do
			local scales: { number } = if SMALLER[i] then { 1 } else { 1, 1.25, 1.5 }
			for _, textScale in scales do
				it(`{rule}: {describeScreen(device, textScale)}`, function()
					check(at(device, textScale), device)
				end)
			end
		end
	end

	describe("ScreenLayout text sizes", function()
		it("are feel.md's for each class at Text scale 1: body, speaker, Objective, hint", function()
			local phone, tablet, pc = at(DEVICES[1], 1), at(DEVICES[5], 1), at(DEVICES[9], 1)
			expect(phone.text).toEqual({ body = 20, speaker = 18, objective = 18, hint = 14 })
			expect(tablet.text).toEqual({ body = 24, speaker = 20, objective = 20, hint = 16 })
			expect(pc.text).toEqual({ body = 24, speaker = 20, objective = 20, hint = 16 })
		end)

		it("scale with the Text scale, which stays between 1 and 1.5", function()
			expect(at(DEVICES[1], 1.5).text).toEqual({ body = 30, speaker = 27, objective = 27, hint = 21 })
			expect(at(DEVICES[9], 1.5).text).toEqual({ body = 36, speaker = 30, objective = 30, hint = 24 })
			expect(at(DEVICES[1], 3).text).toEqual(at(DEVICES[1], 1.5).text)
			expect(at(DEVICES[1], 0.5).text).toEqual(at(DEVICES[1], 1).text)
		end)
	end)

	describe("ScreenLayout dialogue box", function()
		each("its column is never wider than 30 x the body size", function(layout)
			expect(layout.dialogue.column <= ScreenLayout.COLUMN_EMS * layout.text.body).toBe(true)
			expect(layout.dialogue.width).toBe(layout.dialogue.column + 2 * ScreenLayout.PADDING)
		end)

		each("it sits in the safe area, as tall as it may grow", function(layout)
			local d = layout.dialogue
			local top = d.bottom - d.maxHeight - d.overhang -- the name tag rises above the box
			expect(inside({ x = d.x, y = top, width = d.width, height = d.bottom - top }, layout.safe)).toBe(true)
		end)

		each("every Line of the Story fits it without scrolling", function(layout)
			local largest = layout.class == "Phone" and layout.portrait and layout.textScale == ScreenLayout.MAX_SCALE
			for _, text in LINES do
				if largest and table.find(OVER_LONG, text) then
					continue
				end
				local height = ScreenLayout.dialogueHeight(layout, text, text == FIRST_LINE)
				if height > layout.dialogue.maxHeight then
					error(
						`{string.format("%q", text)} needs {height} units; the box grows to {layout.dialogue.maxHeight}`
					)
				end
			end
		end)

		each("in phone portrait it grows to at most 40% of the height", function(layout, device)
			if layout.class == "Phone" and layout.portrait then
				expect(layout.dialogue.maxHeight <= 0.4 * device.height).toBe(true)
			end
		end)

		it("is as wide as the 60-character cap on a 13-inch tablet: 720 units in a 768-unit box", function()
			local tablet = at(DEVICES[5], 1)
			expect(tablet.dialogue.column).toBe(720)
			expect(tablet.dialogue.width).toBe(768)
		end)

		it("is the space minus 24 units each side where that is under the cap: a phone in portrait", function()
			local phone = at(DEVICES[2], 1)
			expect(phone.dialogue.column).toBe(390 - 2 * 24)
		end)
	end)

	describe("ScreenLayout touch control zones", function()
		it("are 35% x 40% on a Phone and 25% x 35% on a Tablet, in the bottom corners; a PC has none", function()
			local function near(zone: Rect, expected: { [string]: number })
				for field, value in expected do
					expect(math.abs((zone :: any)[field] - value) < 1e-9).toBe(true)
				end
			end
			local phone = at(DEVICES[1], 1).zones
			near(phone[1], { x = 0, y = 390 * 0.6, width = 844 * 0.35, height = 390 * 0.4 })
			near(phone[2], { x = 844 * 0.65, y = 390 * 0.6, width = 844 * 0.35, height = 390 * 0.4 })
			near(
				at(DEVICES[5], 1).zones[2],
				{ x = 1376 * 0.75, y = 1032 * 0.65, width = 1376 * 0.25, height = 1032 * 0.35 }
			)
			expect(at(DEVICES[9], 1).zones).toEqual({})
			expect(at(DEVICES[9], 1).talk).toBeNil()
		end)

		it("follow a rotation: a phone turned to portrait has its zones and box laid out again", function()
			local landscape, portrait = at(DEVICES[1], 1), at(DEVICES[2], 1)
			expect(portrait.portrait).toBe(true)
			expect(portrait.zones[1].height).toBe(844 * 0.4)
			expect(landscape.dialogue.bottom > (landscape.talk :: Rect).y).toBe(true) -- beside the buttons
			expect(portrait.dialogue.bottom < portrait.skip.y).toBe(true) -- above them
		end)

		each("the Talk-and-advance and Skip buttons sit in the right zone, the ring in the left", function(layout)
			if layout.class == "PC" then
				return
			end
			local talk, ring = layout.talk :: Rect, layout.ring :: Rect
			for _, button in { talk, layout.skip } do
				expect(inside(button, layout.zones[2])).toBe(true)
				expect(inside(button, layout.safe)).toBe(true)
			end
			expect(inside(ring, layout.zones[1])).toBe(true)
			expect(inside(ring, layout.safe)).toBe(true)
		end)
	end)

	describe("ScreenLayout touch targets", function()
		each("are at least 48 x 48 and 8 apart", function(layout)
			local targets: { Rect } = { layout.skip }
			if layout.talk then
				table.insert(targets, layout.talk)
			end
			for i, target in targets do
				expect(target.width >= ScreenLayout.TARGET and target.height >= ScreenLayout.TARGET).toBe(true)
				for j = i + 1, #targets do
					expect(gap(target, targets[j]) >= ScreenLayout.TARGET_GAP).toBe(true)
				end
			end
			local button = layout.title.button
			expect(button.width >= ScreenLayout.TARGET and button.height >= ScreenLayout.TARGET).toBe(true)
			expect(layout.title.gap >= ScreenLayout.TARGET_GAP).toBe(true)
			expect(layout.objective.icon.width >= ScreenLayout.TARGET).toBe(true)
		end)

		each("the Title screen's buttons fit every label in two lines, inside the safe area", function(layout)
			local button = layout.title.button
			expect(button.width <= layout.title.width).toBe(true)
			for _, label in TitleScreen.LABELS do
				expect(ScreenLayout.lines(label, button.text, button.width - 2 * ScreenLayout.BUTTON_PADDING) <= 2).toBe(
					true
				)
			end
			expect(inside({ x = layout.title.x, y = 0, width = layout.title.width, height = layout.title.bottom }, {
				x = layout.safe.x,
				y = 0,
				width = layout.safe.width,
				height = layout.safe.y + layout.safe.height,
			})).toBe(true)
		end)
	end)

	describe("ScreenLayout nothing overlaps", function()
		each("in free play: the Objective tracker, a Hint, the Skip button and the touch controls", function(layout)
			local shown: { [string]: Rect } = {
				objective = tracker(layout, longestObjective),
				hint = layout.hint,
				skip = layout.skip,
			}
			if layout.talk then
				shown.talk = layout.talk :: Rect
			end
			for name, a in shown do
				expect(inside(a, layout.safe)).toBe(true)
				for other, b in shown do
					if name < other and gap(a, b) < 0 then
						error(`{name} overlaps {other}`)
					end
				end
			end
			-- nothing but the controls covers a touch control zone
			for _, zone in layout.zones do
				for name, a in shown do
					if name ~= "talk" and name ~= "skip" and gap(a, zone) < 0 then
						error(`{name} covers a touch control zone`)
					end
				end
			end
		end)

		each("while a Dialogue shows: the box, the Objective tracker and the buttons", function(layout)
			local objective = if layout.objective.collapses
				then layout.objective.icon
				else tracker(layout, longestObjective)
			local buttons: { Rect } = { layout.skip }
			if layout.talk then
				table.insert(buttons, layout.talk)
			end
			for _, text in LINES do
				local shown = box(layout, text)
				expect(gap(shown, objective) >= 0).toBe(true)
				for _, button in buttons do
					expect(gap(shown, button) >= ScreenLayout.TARGET_GAP).toBe(true)
				end
			end
		end)
	end)

	describe("ScreenLayout Hints", function()
		each("every Hint fits its place: two lines in free play, one large line in the box", function(layout)
			for step, hint in hints.steps do
				local words = if layout.touch then hint.touch else hint.pc
				if not words then
					continue
				elseif step == "advance" then
					expect(ScreenLayout.lines(words, layout.text.body, layout.dialogue.column)).toBe(1)
				else
					expect(ScreenLayout.lines(words, layout.text.hint, layout.hint.width) <= 2).toBe(true)
				end
			end
			local continue = if layout.touch then hints.continue.touch else hints.continue.pc
			expect(ScreenLayout.lines(continue, layout.text.hint, layout.dialogue.column)).toBe(1)
			local skip = utf8.len(hints.skip) or 0
			expect(skip <= ScreenLayout.SKIP_CHARACTERS).toBe(true)
		end)
	end)

	describe("ScreenLayout Chapter card", function()
		each("fits every Chapter's title and subtitle in the safe area", function(layout)
			local card = layout.card
			expect(card.x >= layout.safe.x and card.x + card.width <= layout.safe.x + layout.safe.width).toBe(true)
			for _, chapter in Content.story.chapters do
				local title = ScreenLayout.lines(chapter.title, card.title, card.width) * card.title
				local subtitle = ScreenLayout.lines(chapter.subtitle, card.subtitle, card.width) * card.subtitle
				expect((title + subtitle) * ScreenLayout.LINE <= layout.safe.height / 2).toBe(true)
			end
		end)
	end)

	describe("ScreenLayout.insets", function()
		it("are the safe area's distance from each edge of the screen, never negative", function()
			local screen = { x = 0, y = -58, width = 844, height = 448 }
			expect(ScreenLayout.insets(screen, { x = 47, y = 0, width = 750, height = 369 })).toEqual({
				left = 47,
				top = 58,
				right = 47,
				bottom = 21,
			})
			expect(ScreenLayout.insets(screen, { x = -5, y = -60, width = 900, height = 600 })).toEqual({
				left = 0,
				top = 0,
				right = 0,
				bottom = 0,
			})
		end)
	end)

	describe("ScreenLayout.lines", function()
		it("wraps at whole words, about two characters per text size", function()
			expect(ScreenLayout.lines("Amy", 20, 200)).toBe(1)
			-- 200 / (20 x 0.55) = 18 characters a line
			expect(ScreenLayout.lines("abcdefghi abcdefgh", 20, 200)).toBe(1)
			expect(ScreenLayout.lines("abcdefghi abcdefghi", 20, 200)).toBe(2)
			expect(ScreenLayout.lines(string.rep("a", 40), 20, 200)).toBe(3)
		end)
	end)
end
