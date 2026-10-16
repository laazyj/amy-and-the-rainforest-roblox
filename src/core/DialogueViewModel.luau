--!strict
--[[
	DialogueViewModel: the client's Dialogue, as plain data (plan section
	2.1). The client binder (src/client) feeds it what arrives over Net and
	the player's input, and renders what `view` returns; all the logic is
	here, so tier 1 tests it without a client.

	  enqueue  a Dialogue arrives (ShowDialogue); it shows at once, or after
	           the Dialogues already queued
	  tick     time passes: the Line types out, one grapheme at a time
	  advance  the player clicks or presses a key: a Line still typing shows
	           in full, a typed Line gives way to the next; after the last
	           Line the Dialogue is finished, `advance` returns true and the
	           binder sends DialogueFinished
	  view     what the dialogue box shows now, in the high-contrast
	           styles when that Setting is on
	  box      the dialogue box's own colours, usual or high-contrast

	No timed reading (docs/story/style-guide.md section 3): only `advance`,
	the player's input, ever moves a Dialogue on. `tick` types a Line out
	and nothing more, however much time passes; tier 1 holds it to that.

	Typing counts graphemes, the characters a reader sees, as Roblox's
	MaxVisibleGraphemes does: "♥️" and "👍🏽" are one each, though they are
	two code points.
]]

local Events = require("./Events")
local Story = require("./Story")

type ShownLine = Events.ShownLine

-- How a Speaker's Lines look: the colours of the name tag and of the text.
export type Style = { tag: Story.RGB, text: Story.RGB }

-- The dialogue box behind the Lines: its colour and how much of the world
-- shows through it, its border, and the hint row's text colour.
export type Box = { background: Story.RGB, transparency: number, stroke: Story.RGB, hint: Story.RGB }

export type View = {
	-- whether the dialogue box is showing
	open: boolean,
	-- the Speaker's display name; the name tag is hidden when it is ""
	speaker: string,
	text: string,
	-- how many graphemes of `text` show; -1 when all of them do
	visibleGraphemes: number,
	style: Style,
}

export type DialogueViewModel = {
	-- Dialogues waiting their turn
	queue: { { ShownLine } },
	-- the Dialogue showing, and its Line
	lines: { ShownLine }?,
	index: number,
	-- seconds since the Line started typing, and its length in graphemes
	elapsed: number,
	graphemes: number,
}

local DialogueViewModel = {}

-- How long each grapheme takes to type: about 30 a second, the pace players
-- saw before the view-model. The old binder waited task.wait(0.022) per
-- grapheme, which resumes on the first frame after the wait, so at 60 fps
-- each grapheme took two frames. A different pace is a feel decision
-- (briefs 011 and 016), not a refactor's.
DialogueViewModel.SECONDS_PER_GRAPHEME = 1 / 30

-- The Speaker's name on the name tag; every tag is dark enough for it to
-- read at 4.5:1 (feel.md section 3).
DialogueViewModel.NAME_TEXT = table.freeze({ r = 255, g = 255, b = 245 }) :: Story.RGB

local DEFAULT_STYLE: Style = table.freeze({
	tag = table.freeze({ r = 75, g = 128, b = 64 }),
	text = table.freeze({ r = 240, g = 248, b = 235 }),
})

DialogueViewModel.DEFAULT_STYLE = DEFAULT_STYLE

-- Speaker display name -> Style; every other Speaker has DEFAULT_STYLE.
local STYLES: { [string]: Style } = table.freeze({
	Narrator = table.freeze({
		tag = table.freeze({ r = 120, g = 110, b = 160 }),
		text = table.freeze({ r = 225, g = 225, b = 245 }),
	}),
	Amy = table.freeze({
		tag = table.freeze({ r = 167, g = 94, b = 109 }),
		text = table.freeze({ r = 248, g = 240, b = 240 }),
	}),
})

DialogueViewModel.STYLES = STYLES

-- The high-contrast Setting (feel.md section 3, 7:1): the same Speakers'
-- colours, darker tags under the same name text.
local HIGH_CONTRAST_DEFAULT: Style = table.freeze({
	tag = table.freeze({ r = 40, g = 84, b = 34 }),
	text = DEFAULT_STYLE.text,
})

local HIGH_CONTRAST_STYLES: { [string]: Style } = table.freeze({
	Narrator = table.freeze({ tag = table.freeze({ r = 80, g = 66, b = 120 }), text = STYLES.Narrator.text }),
	Amy = table.freeze({ tag = table.freeze({ r = 120, g = 50, b = 70 }), text = STYLES.Amy.text }),
})

function DialogueViewModel.style(speaker: string, highContrast: boolean?): Style
	if highContrast then
		return HIGH_CONTRAST_STYLES[speaker] or HIGH_CONTRAST_DEFAULT
	end
	return STYLES[speaker] or DEFAULT_STYLE
end

-- The usual box lets a little of the world through; the high-contrast one
-- is opaque and darker, so its contrast never depends on what is behind it.
DialogueViewModel.BOX = table.freeze({
	background = table.freeze({ r = 24, g = 44, b = 30 }),
	transparency = 0.12,
	stroke = table.freeze({ r = 140, g = 200, b = 120 }),
	hint = table.freeze({ r = 190, g = 215, b = 180 }),
} :: Box)

DialogueViewModel.HIGH_CONTRAST_BOX = table.freeze({
	background = table.freeze({ r = 8, g = 16, b = 10 }),
	transparency = 0,
	stroke = table.freeze({ r = 255, g = 226, b = 150 }),
	hint = table.freeze({ r = 255, g = 226, b = 150 }),
} :: Box)

function DialogueViewModel.box(highContrast: boolean?): Box
	return if highContrast then DialogueViewModel.HIGH_CONTRAST_BOX else DialogueViewModel.BOX
end

local function between(code: number, low: number, high: number): boolean
	return code >= low and code <= high
end

-- Code points that extend the grapheme before them: combining marks,
-- variation selectors, the zero-width joiner, skin-tone modifiers and tags.
local function extends(code: number): boolean
	return between(code, 0x0300, 0x036F)
		or between(code, 0x1AB0, 0x1AFF)
		or between(code, 0x1DC0, 0x1DFF)
		or between(code, 0x20D0, 0x20FF)
		or between(code, 0xFE00, 0xFE0F)
		or between(code, 0xFE20, 0xFE2F)
		or code == 0x200D
		or between(code, 0x1F3FB, 0x1F3FF)
		or between(code, 0xE0020, 0xE007F)
		or between(code, 0xE0100, 0xE01EF)
end

local function isRegionalIndicator(code: number): boolean
	return between(code, 0x1F1E6, 0x1F1FF)
end

-- How many graphemes `text` has. A simplification of Unicode's rules that
-- covers what Lines hold: letters with accents, ♥ with or without its
-- emoji selector, skin tones, joined emoji (👨‍👩‍👧) and flags (🇬🇧).
-- Text that is not valid UTF-8 counts one per byte.
function DialogueViewModel.graphemes(text: string): number
	if utf8.len(text) == nil then
		return #text
	end
	local count = 0
	local joined = false -- the code point before was a zero-width joiner
	local pendingFlag = false -- an odd regional indicator awaits its pair
	for _, code in utf8.codes(text) do
		if joined or extends(code) or (pendingFlag and isRegionalIndicator(code)) then
			pendingFlag = false
		else
			count += 1
			pendingFlag = isRegionalIndicator(code)
		end
		joined = code == 0x200D
	end
	return count
end

function DialogueViewModel.new(): DialogueViewModel
	return { queue = {}, lines = nil, index = 0, elapsed = 0, graphemes = 0 }
end

local function showLine(vm: DialogueViewModel, index: number)
	local lines = vm.lines :: { ShownLine }
	vm.index = index
	vm.elapsed = 0
	vm.graphemes = DialogueViewModel.graphemes(lines[index].text)
end

local function showNext(vm: DialogueViewModel)
	vm.lines = table.remove(vm.queue, 1)
	if vm.lines then
		showLine(vm, 1)
	end
end

-- A Dialogue arrives. It shows now if none is showing.
function DialogueViewModel.enqueue(vm: DialogueViewModel, lines: { ShownLine })
	table.insert(vm.queue, lines)
	if not vm.lines then
		showNext(vm)
	end
end

-- How many graphemes of the Line show; the first shows at once.
local function typed(vm: DialogueViewModel): number
	return math.min(vm.graphemes, math.floor(vm.elapsed / DialogueViewModel.SECONDS_PER_GRAPHEME) + 1)
end

-- `seconds` pass.
function DialogueViewModel.tick(vm: DialogueViewModel, seconds: number)
	if vm.lines then
		vm.elapsed += seconds
	end
end

-- The player asks to go on. Returns true when that finished the Dialogue.
function DialogueViewModel.advance(vm: DialogueViewModel): boolean
	local lines = vm.lines
	if not lines then
		return false
	end
	if typed(vm) < vm.graphemes then
		vm.elapsed = math.huge
		return false
	end
	if vm.index < #lines then
		showLine(vm, vm.index + 1)
		return false
	end
	showNext(vm)
	return true
end

local CLOSED: View =
	table.freeze({ open = false, speaker = "", text = "", visibleGraphemes = -1, style = DEFAULT_STYLE })

function DialogueViewModel.view(vm: DialogueViewModel, highContrast: boolean?): View
	local lines = vm.lines
	if not lines then
		return CLOSED
	end
	local line = lines[vm.index]
	local shown = typed(vm)
	return {
		open = true,
		speaker = line.speaker,
		text = line.text,
		visibleGraphemes = if shown < vm.graphemes then shown else -1,
		style = DialogueViewModel.style(line.speaker, highContrast),
	}
end

return DialogueViewModel
