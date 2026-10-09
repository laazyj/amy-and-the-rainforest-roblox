--[[
	DialogueViewModel: the dialogue queue, the Line index, typing by
	grapheme (emoji and ♥ included), skipping and advancing, the Speaker
	styles, and DialogueFinished once per Dialogue.
]]

local DialogueViewModel = require("../../../src/core/DialogueViewModel")

local STEP = DialogueViewModel.SECONDS_PER_GRAPHEME

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	local function lines(...: string): { any }
		local list = {}
		for _, text in { ... } do
			table.insert(list, { speaker = "Narrator", text = text })
		end
		return list
	end

	-- Advances until the Dialogue finishes; returns how many advances that took.
	local function finish(vm: DialogueViewModel.DialogueViewModel): number
		for count = 1, 100 do
			if DialogueViewModel.advance(vm) then
				return count
			end
		end
		error("the Dialogue never finished")
	end

	describe("DialogueViewModel.graphemes", function()
		for _, case in
			{
				{ "plain text", "Deal.", 5 },
				{ "an empty Line", "", 0 },
				{ "♥ on its own", "The end ♥", 9 },
				{ "♥ with the emoji selector", "The end ♥️", 9 },
				{ "an emoji outside the basic plane", "Sam 🐶!", 6 },
				{ "a skin-tone modifier", "👍🏽", 1 },
				{ "a family joined by zero-width joiners", "👨‍👩‍👧", 1 },
				{ "a flag of two regional indicators", "🇬🇧🇫🇷", 2 },
				{ "a letter with a combining accent", "cafe\u{301}", 4 },
				{ "an em dash", "Amy and the Rain Forest — a story by Clara", 42 },
			} :: { { any } }
		do
			it(`counts {case[3]} for {case[1]}`, function()
				expect(DialogueViewModel.graphemes(case[2])).toBe(case[3])
			end)
		end

		it("counts bytes for text that is not UTF-8", function()
			expect(DialogueViewModel.graphemes("\255\254")).toBe(2)
		end)
	end)

	describe("a Dialogue", function()
		it("is closed until a Dialogue arrives", function()
			local view = DialogueViewModel.view(DialogueViewModel.new())
			expect(view.open).toBe(false)
			expect(view.speaker).toBe("")
		end)

		it("shows the first Line of a Dialogue as soon as it arrives", function()
			local vm = DialogueViewModel.new()
			DialogueViewModel.enqueue(
				vm,
				{ { speaker = "Dad", text = "No." }, { speaker = "Amy", text = "But Dad--" } }
			)
			local view = DialogueViewModel.view(vm)
			expect(view.open).toBe(true)
			expect(view.speaker).toBe("Dad")
			expect(view.text).toBe("No.")
			expect(vm.index).toBe(1)
		end)

		it("types a Line one grapheme at a time, the first at once", function()
			local vm = DialogueViewModel.new()
			DialogueViewModel.enqueue(vm, lines("WOOF!"))
			expect(DialogueViewModel.view(vm).visibleGraphemes).toBe(1)
			DialogueViewModel.tick(vm, STEP * 2.5)
			expect(DialogueViewModel.view(vm).visibleGraphemes).toBe(3)
			DialogueViewModel.tick(vm, STEP * 2)
			expect(DialogueViewModel.view(vm).visibleGraphemes).toBe(-1)
		end)

		it("types ♥ and an emoji as one grapheme each", function()
			local vm = DialogueViewModel.new()
			DialogueViewModel.enqueue(vm, lines("♥️👍🏽!"))
			expect(DialogueViewModel.view(vm).visibleGraphemes).toBe(1)
			DialogueViewModel.tick(vm, STEP)
			expect(DialogueViewModel.view(vm).visibleGraphemes).toBe(2)
			DialogueViewModel.tick(vm, STEP)
			expect(DialogueViewModel.view(vm).visibleGraphemes).toBe(-1)
		end)

		it("shows a typing Line in full on advance, then goes to the next Line", function()
			local vm = DialogueViewModel.new()
			DialogueViewModel.enqueue(vm, lines("She tryed again but Sam brang her back.", "WOOF!"))
			expect(DialogueViewModel.advance(vm)).toBe(false)
			expect(vm.index).toBe(1)
			expect(DialogueViewModel.view(vm).visibleGraphemes).toBe(-1)
			expect(DialogueViewModel.advance(vm)).toBe(false)
			expect(vm.index).toBe(2)
			expect(DialogueViewModel.view(vm).visibleGraphemes).toBe(1)
		end)

		it("finishes after the last Line, once, and closes", function()
			local vm = DialogueViewModel.new()
			DialogueViewModel.enqueue(vm, lines("One.", "Two."))
			-- each Line: one advance to show it in full, one to go on
			expect(finish(vm)).toBe(4)
			expect(DialogueViewModel.view(vm).open).toBe(false)
			expect(DialogueViewModel.advance(vm)).toBe(false)
		end)

		it("goes straight on from a Line that has finished typing", function()
			local vm = DialogueViewModel.new()
			DialogueViewModel.enqueue(vm, lines("Hi"))
			DialogueViewModel.tick(vm, 1)
			expect(DialogueViewModel.advance(vm)).toBe(true)
		end)

		it("finishes an empty Line with one advance", function()
			local vm = DialogueViewModel.new()
			DialogueViewModel.enqueue(vm, lines(""))
			expect(DialogueViewModel.view(vm).visibleGraphemes).toBe(-1)
			expect(DialogueViewModel.advance(vm)).toBe(true)
		end)

		it("does not type while closed", function()
			local vm = DialogueViewModel.new()
			DialogueViewModel.tick(vm, 10)
			DialogueViewModel.enqueue(vm, lines("Hello"))
			expect(DialogueViewModel.view(vm).visibleGraphemes).toBe(1)
		end)
	end)

	describe("the dialogue queue", function()
		it("holds a Dialogue that arrives while another shows, then shows it from its first Line", function()
			local vm = DialogueViewModel.new()
			DialogueViewModel.enqueue(vm, lines("First."))
			DialogueViewModel.enqueue(
				vm,
				{ { speaker = "Amy", text = "Second." }, { speaker = "Amy", text = "Third." } }
			)
			expect(DialogueViewModel.view(vm).text).toBe("First.")
			expect(finish(vm)).toBe(2)
			local view = DialogueViewModel.view(vm)
			expect(view.open).toBe(true)
			expect(view.text).toBe("Second.")
			expect(view.visibleGraphemes).toBe(1)
			expect(finish(vm)).toBe(4)
			expect(DialogueViewModel.view(vm).open).toBe(false)
		end)

		it("finishes each Dialogue once, in the order they arrived", function()
			local vm = DialogueViewModel.new()
			for _, text in { "a", "b", "c" } do
				DialogueViewModel.enqueue(vm, lines(text))
			end
			local finished = {}
			for _ = 1, 3 do
				table.insert(finished, DialogueViewModel.view(vm).text)
				finish(vm)
			end
			expect(finished).toEqual({ "a", "b", "c" })
			expect(#vm.queue).toBe(0)
		end)
	end)

	describe("speaker style", function()
		it("gives the Narrator and Amy their own styles", function()
			expect(DialogueViewModel.style("Narrator").tag).toEqual({ r = 120, g = 110, b = 160 })
			expect(DialogueViewModel.style("Amy").tag).toEqual({ r = 214, g = 120, b = 140 })
		end)

		it("gives every other Speaker the Character style", function()
			expect(DialogueViewModel.style("Sam the Dog")).toBe(DialogueViewModel.style("the Golden Lion"))
			expect(DialogueViewModel.style("Dad").tag).toEqual({ r = 94, g = 160, b = 80 })
		end)

		it("styles the view by the Line's Speaker", function()
			local vm = DialogueViewModel.new()
			DialogueViewModel.enqueue(vm, { { speaker = "Amy", text = "Deal." } })
			expect(DialogueViewModel.view(vm).style).toBe(DialogueViewModel.style("Amy"))
		end)
	end)
end
