-- Narration: the Narration table checked against the Story's canon Lines,
-- and a Line's reading followed through the dialogue view-model.

local DialogueViewModel = require("../../../src/core/DialogueViewModel")
local Narration = require("../../../src/core/Narration")
local story = require("./fixtureStory")

-- Every canon Line of the fixture Story, by the narration file that reads it.
local canon = Narration.canonLines(story)
local last = `narration:{story.chapters[#story.chapters].id}`

-- A Narration table reading every canon Line of each file, a second each.
local function covering(): Narration.Table
	local narration = {}
	for file, texts in canon do
		local parts = {}
		for i, text in texts do
			parts[i] = { text = text, from = i - 1, to = i - 0.1 }
		end
		narration[file] = parts
	end
	return narration
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("Narration.canonLines", function()
		it(
			"gives each Chapter's file its canon Lines in story order, and the last Chapter's the Ending's too",
			function()
				expect(canon).toEqual({
					["narration:chapter1"] = {},
					["narration:chapter2"] = { "Pick two.", "The end." },
				})
			end
		)
	end)

	describe("Narration.problems", function()
		it("finds none in an empty table: every Line is shown as text only", function()
			expect(Narration.problems(story, {})).toEqual({})
		end)

		it("finds none in a table that covers every canon Line of each Chapter it has a file for", function()
			expect(Narration.problems(story, covering())).toEqual({})
		end)

		it("finds a canon Line a Chapter's file leaves out", function()
			local narration = covering()
			local parts = narration[last]
			local dropped = table.remove(parts) :: Narration.Part
			expect(Narration.problems(story, narration)).toEqual({
				`{last} does not read the canon Line "{dropped.text}"`,
			})
		end)

		it("finds a part that reads no canon Line, and parts out of order", function()
			local narration = covering()
			local parts = narration[last]
			parts[1].text = "Hello there."
			parts[2].from = parts[1].from
			expect(Narration.problems(story, narration)).toEqual({
				`{last} does not read the canon Line "{canon[last][1]}"`,
				`{last} part 1 reads no canon Line of its Chapter: "Hello there."`,
				`{last} part 2 must start at or after the last part ends and end after it starts`,
			})
		end)

		it("finds a file that is no Chapter's", function()
			expect(Narration.problems(story, { ["narration:chapter99"] = {} })).toEqual({
				"narration:chapter99 is not narration:<chapter id> of a Chapter",
			})
		end)
	end)

	describe("a Line's reading, in step with the dialogue view-model", function()
		local narration = covering()
		local index = Narration.index(narration)
		local text = canon[last][1]

		it("is the Line's part of its Chapter's file while the box shows it, typing or not", function()
			local vm = DialogueViewModel.new()
			DialogueViewModel.enqueue(
				vm,
				{ { speaker = "Narrator", text = text }, { speaker = "Amy", text = "Not canon." } }
			)
			local reading = Narration.reading(index, DialogueViewModel.view(vm))
			expect(reading).toEqual({ asset = last, from = 0, to = 0.9 })
			DialogueViewModel.tick(vm, 10)
			expect(Narration.reading(index, DialogueViewModel.view(vm))).toBe(reading)
		end)

		it("is none for a Line with no part, and none once the box closes", function()
			local vm = DialogueViewModel.new()
			DialogueViewModel.enqueue(
				vm,
				{ { speaker = "Narrator", text = text }, { speaker = "Amy", text = "Not canon." } }
			)
			DialogueViewModel.tick(vm, 10)
			DialogueViewModel.advance(vm)
			expect(Narration.reading(index, DialogueViewModel.view(vm))).toBeNil()
			DialogueViewModel.tick(vm, 10)
			DialogueViewModel.advance(vm)
			expect(DialogueViewModel.view(vm).open).toBe(false)
			expect(Narration.reading(index, DialogueViewModel.view(vm))).toBeNil()
		end)

		it("is none for every Line with an empty table: the text-only fallback", function()
			local vm = DialogueViewModel.new()
			DialogueViewModel.enqueue(vm, { { speaker = "Narrator", text = text } })
			expect(Narration.reading(Narration.index({}), DialogueViewModel.view(vm))).toBeNil()
		end)

		it("reads until its part ends", function()
			local reading = assert(index[text], "the Line has a part")
			expect(Narration.reads(reading, 0.5)).toBe(true)
			expect(Narration.reads(reading, 0.9)).toBe(false)
		end)

		it("never advances the Dialogue: the box shows the Line after its part has ended", function()
			local vm = DialogueViewModel.new()
			DialogueViewModel.enqueue(vm, { { speaker = "Narrator", text = text } })
			DialogueViewModel.tick(vm, 60)
			expect(DialogueViewModel.view(vm).text).toBe(text)
		end)
	end)
end
