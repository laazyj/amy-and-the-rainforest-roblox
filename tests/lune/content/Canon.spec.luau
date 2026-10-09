--[[
	Canon on content (docs/story/canon.md, rule 3): every Line marked canon
	in content equals a row of the Canon Lines table, byte for byte, in
	story order, in its Quest and Dialogue, by its Speaker; and every row is
	in content as a canon Line. No allowances. The other Lines match the
	Game Lines table the same way, so canon.md stays the whole script.
]]

local Story = require("../../../src/content/Story")
local canonTable = require("./canonTable")

type Said = { quest: string, dialogue: string, speaker: string, line: string, canon: boolean }

-- Every Line in content, in the order a player sees them: each Quest's
-- intro, dialogue and outro, then the Ending.
local function said(): { Said }
	local lines = {}
	local function add(quest: string, dialogue: string, list: { any }?)
		for _, line in (list or {}) :: { any } do
			table.insert(lines, {
				quest = quest,
				dialogue = dialogue,
				speaker = line.speaker,
				line = line.text,
				canon = line.canon == true,
			})
		end
	end
	for _, chapter in Story.story.chapters do
		for _, quest in chapter.quests do
			add(quest.id, "intro", quest.intro)
			add(quest.id, "dialogue", quest.dialogue)
			add(quest.id, "outro", quest.outro)
		end
	end
	add("Ending", "Ending", Story.story.ending.lines)
	return lines
end

local function only(lines: { Said }, canon: boolean): { canonTable.Row }
	local rows = {}
	for _, line in lines do
		if line.canon == canon then
			table.insert(rows, {
				number = #rows + 1,
				quest = line.quest,
				dialogue = line.dialogue,
				speaker = line.speaker,
				line = line.line,
			})
		end
	end
	return rows
end

local inContent = said()

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	for _, case in { { heading = "Canon Lines", canon = true }, { heading = "Game Lines, not canon", canon = false } } do
		local heading, canon = case.heading, case.canon
		local rows, unreadable = canonTable.rows(heading)
		local content = only(inContent, canon)

		describe(`canon.md "{heading}"`, function()
			it("reads every row, numbered from 1", function()
				expect(#rows > 0).toBe(true)
				expect(unreadable).toEqual({})
				for i, row in rows do
					expect(row.number).toBe(i)
				end
			end)

			it(`has as many rows as content has {if canon then "canon" else "other"} Lines`, function()
				expect(#content).toBe(#rows)
			end)

			for i, row in rows do
				it(`is Line {i} of content, byte for byte: {row.line}`, function()
					expect(content[i]).toEqual(row)
				end)
			end
		end)
	end
end
