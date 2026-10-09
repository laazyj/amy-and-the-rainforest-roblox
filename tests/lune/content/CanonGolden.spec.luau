--[[
	Every canon Line in docs/story/canon.md appears, byte for byte, in story
	order and in its Quest, in a Dialogue the game sends during the golden
	walkthrough (tests/fixtures/golden/walkthrough.json, recorded by
	tests/engine/walkthrough.luau). The game is the source; the walkthrough
	is what a player sees.
]]

local bootstrap = require("../bootstrap")
local serde = require("@lune/serde")

type CanonRow = { number: number, quest: string, line: string }

-- The rows of the "Canon Lines" table: number, Quest and the backticked Line
-- (canon.md: "the Line is the only backticked text in its row"). Also
-- returns every numbered row the pattern cannot read, so such a row fails
-- the test instead of vanishing.
local function canonRows(markdown: string): ({ CanonRow }, { string })
	local section = assert(string.match(markdown, "\n## Canon Lines\n(.-)\n## "), "no Canon Lines section")
	local rows, unreadable = {}, {}
	for text in string.gmatch(section, "[^\n]+") do
		if string.match(text, "^|%s*%d+%s*|") then
			local number, quest, line = string.match(text, "^|%s*(%d+)%s*|%s*([^|]-)%s*|[^`]*`([^`]+)`")
			if number then
				table.insert(
					rows,
					{ number = tonumber(number) :: number, quest = quest :: string, line = line :: string }
				)
			else
				table.insert(unreadable, text)
			end
		end
	end
	return rows, unreadable
end

type ShownLine = { quest: string?, text: string }

-- Every Line the game showed, with the Quest active when it was sent, in order.
local function shownLines(golden: { any }): { ShownLine }
	local shown = {}
	for _, message in golden do
		if message.remote == "ShowDialogue" then
			for _, line in message.args[1] do
				table.insert(shown, { quest = message.quest, text = line.text })
			end
		end
	end
	return shown
end

local canon, unreadable = canonRows(bootstrap.readSource("docs/story/canon.md"))
local shown = shownLines(serde.decode("json", bootstrap.readSource("tests/fixtures/golden/walkthrough.json")))

-- Where each canon Line is shown in its Quest, searching on from the previous
-- one, so a Line shown out of story order or in another Quest is not found.
local found: { number? } = {}
local from = 1
for i, row in canon do
	for at = from, #shown do
		if shown[at].text == row.line and shown[at].quest == row.quest then
			found[i] = at
			break
		end
	end
	from = (found[i] or from - 1) + 1
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("canon in the golden walkthrough", function()
		it("reads every row of canon.md's Canon Lines table, numbered from 1", function()
			expect(#canon > 0).toBe(true)
			expect(unreadable).toEqual({})
			for i, row in canon do
				expect(row.number).toBe(i)
			end
		end)

		for i, row in canon do
			it(`shows canon Line {row.number} in {row.quest}, in story order: {row.line}`, function()
				expect(found[i]).never.toBeNil()
			end)
		end
	end)
end
