--[[
	Every canon Line in docs/story/canon.md appears, byte for byte and in
	story order, in a Dialogue the game sends during the golden walkthrough
	(tests/fixtures/golden/walkthrough.json, recorded by
	tests/engine/walkthrough.luau). The game is the source; the walkthrough
	is what a player sees.
]]

local bootstrap = require("../bootstrap")
local serde = require("@lune/serde")

-- The one allowed difference. The owner respelt Clara's "vilage" as
-- "village" (docs/story/canon.md, "Decisions", 2026-10-08), and canon.md
-- already reads "village" while StoryData still reads "vilage". The
-- Checkpoint B refactor applies the respelling in content and removes this
-- allowance; nothing else may differ.
local function asTheGameSpellsIt(line: string): string
	return (string.gsub(line, "%f[%a]village%f[%A]", "vilage"))
end

-- The canon Lines: the number and backticked text of each row of the "Canon
-- Lines" table (canon.md: "the Line is the only backticked text in its row").
local function canonLines(markdown: string): { { number: number, line: string } }
	local section = assert(string.match(markdown, "\n## Canon Lines\n(.-)\n## "), "no Canon Lines section")
	local rows = {}
	for number, line in string.gmatch(section, "\n| (%d+) |[^\n`]*`([^`]+)`") do
		table.insert(rows, { number = tonumber(number) :: number, line = line :: string })
	end
	return rows
end

-- The text of every Line the game showed, in the order it was sent.
local function shownLines(golden: { any }): { string }
	local texts = {}
	for _, message in golden do
		if message.remote == "ShowDialogue" then
			for _, line in message.args[1] do
				table.insert(texts, line.text)
			end
		end
	end
	return texts
end

local canon = canonLines(bootstrap.readSource("docs/story/canon.md"))
local shown = shownLines(serde.decode("json", bootstrap.readSource("tests/fixtures/golden/walkthrough.json")))

-- Where each canon Line is shown, searching on from the previous one, so a
-- Line shown out of story order is not found.
local found: { number? } = {}
local from = 1
for i, row in canon do
	found[i] = table.find(shown, asTheGameSpellsIt(row.line), from)
	from = (found[i] or from - 1) + 1
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("canon in the golden walkthrough", function()
		it("reads every row of canon.md's Canon Lines table, numbered from 1", function()
			expect(#canon > 0).toBe(true)
			for i, row in canon do
				expect(row.number).toBe(i)
			end
		end)

		for i, row in canon do
			it(`shows canon Line {row.number} in story order: {row.line}`, function()
				expect(found[i]).never.toBeNil()
			end)
		end
	end)
end
