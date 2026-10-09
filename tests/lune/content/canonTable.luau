--[[
	Reads the tables of docs/story/canon.md: in each, a numbered row gives
	the Quest, the Dialogue, the Speaker and, as the only backticked text in
	the row, the Line.
]]

local bootstrap = require("../bootstrap")

export type Row = { number: number, quest: string, dialogue: string, speaker: string, line: string }

local CANON = bootstrap.readSource("docs/story/canon.md")

local canonTable = {}

-- The rows of the section headed `heading`, and every numbered row the
-- pattern cannot read, so such a row fails a test instead of vanishing.
function canonTable.rows(heading: string): ({ Row }, { string })
	local section = assert(string.match(CANON, `\n## {heading}\n(.-)\n## `), `no {heading} section`)
	local rows, unreadable = {}, {}
	for text in string.gmatch(section, "[^\n]+") do
		if string.match(text, "^|%s*%d+%s*|") then
			local number, quest, dialogue, speaker, line =
				string.match(text, "^|%s*(%d+)%s*|%s*([^|]-)%s*|%s*([^|]-)%s*|%s*([^|]-)%s*|[^`]*`([^`]+)`")
			if number then
				table.insert(rows, {
					number = tonumber(number) :: number,
					quest = quest :: string,
					dialogue = dialogue :: string,
					speaker = speaker :: string,
					line = line :: string,
				})
			else
				table.insert(unreadable, text)
			end
		end
	end
	return rows, unreadable
end

return canonTable
