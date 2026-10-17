--!strict
--[[
	Narration: canon Lines read aloud. Each Chapter's canon Lines are
	recorded in one audio file, the Asset narration:<chapter id> (the last
	Chapter's also reads the Ending's), to stay within the audio upload
	limit (plan section 7). The Narration table (src/content/narration)
	gives each Line's start and end in its file, in seconds.

	The client plays a Line's part of its file while the dialogue
	view-model shows that Line, and stops it when the part ends or the
	player advances. Nothing is read under a Chapter card or the Title
	screen, and a reading pauses with the Pause screen. A Line with no
	part, or whose file has no asset id yet, is shown as text only: that is
	the fallback, and every Line is always shown as text. Narration never advances a Dialogue (no timed
	reading).
]]

local DialogueViewModel = require("./DialogueViewModel")
local Story = require("./Story")

-- One Line's part of a narration file.
export type Part = { text: string, from: number, to: number }
-- narration file (its Asset name) -> its Lines' parts, in order
export type Table = { [string]: { Part } }
-- Where a Line is read: the file and the part.
export type Reading = { asset: string, from: number, to: number }

local Narration = {}

Narration.PREFIX = "narration:"

-- Line text -> where it is read, for every part in `narration`.
function Narration.index(narration: Table): { [string]: Reading }
	local index = {}
	for asset, parts in narration do
		for _, part in parts do
			index[part.text] = { asset = asset, from = part.from, to = part.to }
		end
	end
	return index
end

-- Where the Line the view-model shows is read, or nil when the dialogue
-- box is closed, the Line has no part, or the box is `covered` (a Chapter
-- card or the Title screen over it): the reading starts, from its part's
-- start, once the cover lifts.
function Narration.reading(index: { [string]: Reading }, view: DialogueViewModel.View, covered: boolean?): Reading?
	return if view.open and not covered then index[view.text] else nil
end

-- Whether a reading `position` seconds into its file is still in its part.
function Narration.reads(reading: Reading, position: number): boolean
	return position < reading.to
end

-- The canon Line texts each narration file reads, in story order: its
-- Chapter's, and for the last Chapter the Ending's too.
function Narration.canonLines(story: Story.Story): { [string]: { string } }
	local byFile = {}
	local function add(file: string, lines: { Story.Line }?)
		byFile[file] = byFile[file] or {}
		for _, line in lines or {} :: { Story.Line } do
			if line.canon then
				table.insert(byFile[file], line.text)
			end
		end
	end
	for _, placed in Story.quests(story) do
		local file = Narration.PREFIX .. placed.chapter.id
		add(file, placed.quest.intro)
		add(file, placed.quest.dialogue)
		add(file, placed.quest.outro)
	end
	add(Narration.PREFIX .. story.chapters[#story.chapters].id, story.ending.lines)
	return byFile
end

-- Every problem with `narration`, sorted: a file that is no Chapter's, a
-- part that reads no canon Line of its Chapter, parts out of order or
-- overlapping, and a canon Line its Chapter's file leaves out. A Chapter
-- with no file is no problem: its Lines are shown as text only.
function Narration.problems(story: Story.Story, narration: Table): { string }
	local problems = {}
	local byFile = Narration.canonLines(story)
	for file, parts in narration do
		local lines = byFile[file]
		if not lines then
			table.insert(problems, `{file} is not narration:<chapter id> of a Chapter`)
			continue
		end
		local read: { [string]: boolean } = {}
		local last = 0
		for i, part in parts do
			if not table.find(lines, part.text) then
				table.insert(problems, `{file} part {i} reads no canon Line of its Chapter: "{part.text}"`)
			end
			if part.from < last or part.to <= part.from then
				table.insert(
					problems,
					`{file} part {i} must start at or after the last part ends and end after it starts`
				)
			end
			read[part.text] = true
			last = part.to
		end
		for _, text in lines do
			if not read[text] then
				table.insert(problems, `{file} does not read the canon Line "{text}"`)
			end
		end
	end
	table.sort(problems)
	return problems
end

return Narration
