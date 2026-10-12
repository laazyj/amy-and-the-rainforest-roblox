-- Onboarding: the first minute (feel.md section 6). Every step's Hint
-- shows when needed, hides on success, comes back after 10 s without
-- progress, and the Skip button ends it.

local Content = require("../../../src/content/Story")
local Onboarding = require("../../../src/core/Onboarding")
local Glossary = require("../../../tools/lib/glossary")
local bootstrap = require("../bootstrap")
local hints = require("../../../src/content/hints")

local FIRST = Content.story.chapters[1]
local FIRST_OBJECTIVE = FIRST.quests[1].objective
local NEXT_OBJECTIVE = FIRST.quests[2].objective

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	local function view(vm: Onboarding.Onboarding, touch: boolean?): Onboarding.View
		return Onboarding.view(vm, hints, touch == true)
	end

	-- A fresh Story, as the golden file sends it: the card, the first
	-- Objective, then the first Narrator Line.
	local function fresh(): Onboarding.Onboarding
		local vm = Onboarding.new(Content.story)
		Onboarding.chapterShown(vm, FIRST.title)
		Onboarding.objectiveShown(vm, FIRST_OBJECTIVE)
		Onboarding.dialogueShown(vm)
		return vm
	end

	-- On to the walk step: the card fades, the first Line is advanced past.
	local function walking(): Onboarding.Onboarding
		local vm = fresh()
		Onboarding.cardGone(vm)
		Onboarding.dialogueFinished(vm)
		return vm
	end

	describe("Onboarding shown once per Save", function()
		it("runs for a Story that begins with its first Chapter card: a fresh Save, or Start again", function()
			expect(fresh().state).toBe("running")
		end)

		it("never runs for a Resume, which begins with an Objective", function()
			local vm = Onboarding.new(Content.story)
			Onboarding.objectiveShown(vm, "Ask Mum about the forest")
			Onboarding.chapterShown(vm, FIRST.title)
			expect(vm.state).toBe("finished")
			expect(view(vm, true).ring).toBe(false)
			expect(view(vm).hint).toBeNil()
		end)

		it("never runs when the first card is another Chapter's", function()
			local vm = Onboarding.new(Content.story)
			Onboarding.chapterShown(vm, Content.story.chapters[2].title)
			expect(vm.state).toBe("finished")
		end)
	end)

	describe("Onboarding step card", function()
		it("shows no Hint while the chapter1 card shows, and is done when it fades", function()
			local vm = fresh()
			expect(view(vm).step).toBe("card")
			expect(view(vm).hint).toBeNil()
			expect(view(vm).skip).toBe(false)
			Onboarding.cardGone(vm)
			expect(view(vm).step).toBe("advance")
		end)
	end)

	describe("Onboarding step advance", function()
		it("shows the continue Hint large on the first Line, PC and touch", function()
			local vm = fresh()
			Onboarding.cardGone(vm)
			expect(view(vm)).toEqual({
				step = "advance",
				hint = nil,
				ring = false,
				pulse = false,
				marker = "Dad",
				row = "Click or press Space to continue",
				large = true,
				glow = false,
				skip = true,
			})
			expect(view(vm, true).row).toBe("Tap to continue")
		end)

		it("hides it on DialogueFinished, and the Objective tracker glows briefly", function()
			local vm = walking()
			expect(view(vm).step).toBe("walk") -- the objective step was done when the Objective was shown
			expect(view(vm).glow).toBe(true)
			Onboarding.tick(vm, Onboarding.GLOW_SECONDS)
			expect(view(vm).glow).toBe(false)
		end)

		it("keeps showing it until the player advances, however long", function()
			local vm = fresh()
			Onboarding.cardGone(vm)
			Onboarding.tick(vm, 60)
			expect(view(vm).row).toBe("Click or press Space to continue")
		end)

		it("gives the box its standing hint back once the step is done", function()
			local vm = walking()
			expect(view(vm).row).toBe(hints.continue.pc)
			expect(view(vm, true).row).toBe(hints.continue.touch)
			expect(view(vm).large).toBe(false)
		end)
	end)

	describe("Onboarding step objective", function()
		it("is done when the first Objective is shown, and puts a marker over its Character", function()
			local vm = Onboarding.new(Content.story)
			Onboarding.chapterShown(vm, FIRST.title)
			expect(view(vm).marker).toBeNil()
			Onboarding.objectiveShown(vm, FIRST_OBJECTIVE)
			expect(vm.done.objective).toBe(true)
			expect(view(vm).marker).toBe(FIRST.quests[1].character)
		end)
	end)

	describe("Onboarding step walk", function()
		it("shows the walk Hint, and on touch the ring on the thumbstick", function()
			local vm = walking()
			expect(view(vm).hint).toBe("W and S walk, A and D turn (or the arrow keys)")
			expect(view(vm).ring).toBe(false)
			local touch = view(vm, true)
			expect(touch.hint).toBe("Drag here to walk")
			expect(touch.ring).toBe(true)
			expect(touch.skip).toBe(true)
		end)

		it("hides it as soon as Amy walks, and brings it back after 10 s without progress", function()
			local vm = walking()
			Onboarding.moved(vm, 1)
			expect(view(vm, true).hint).toBeNil()
			expect(view(vm, true).ring).toBe(false)
			Onboarding.tick(vm, 9.9)
			expect(view(vm, true).hint).toBeNil()
			Onboarding.tick(vm, 0.1)
			expect(view(vm, true).hint).toBe("Drag here to walk")
			Onboarding.moved(vm, 0.5) -- progress again: hidden again
			expect(view(vm, true).hint).toBeNil()
		end)

		it("is done when Amy has moved 4 studs in all", function()
			local vm = walking()
			Onboarding.moved(vm, 2.5)
			expect(view(vm).step).toBe("walk")
			Onboarding.moved(vm, 1.5)
			expect(view(vm).step).toBe("talk")
		end)

		it("counts walking done before the step, during the card or the first Line", function()
			local vm = fresh()
			Onboarding.moved(vm, 5)
			Onboarding.cardGone(vm)
			Onboarding.dialogueFinished(vm)
			expect(view(vm).step).toBe("talk")
		end)
	end)

	describe("Onboarding step talk", function()
		local function talking(): Onboarding.Onboarding
			local vm = walking()
			Onboarding.moved(vm, Onboarding.WALK_STUDS)
			return vm
		end

		it("shows the talk Hint once Dad's prompt is shown, and on touch pulses the button", function()
			local vm = talking()
			expect(view(vm).hint).toBeNil() -- not needed yet: no prompt
			Onboarding.promptShown(vm, true)
			expect(view(vm).hint).toBe("Press E to talk")
			local touch = view(vm, true)
			expect(touch.hint).toBeNil()
			expect(touch.pulse).toBe(true)
			expect(touch.skip).toBe(true)
			Onboarding.promptShown(vm, false) -- Amy walked away
			expect(view(vm).hint).toBeNil()
			expect(view(vm, true).pulse).toBe(false)
		end)

		it("is done on TalkedTo(Dad), when his Dialogue arrives; the marker goes", function()
			local vm = talking()
			Onboarding.promptShown(vm, true)
			Onboarding.dialogueShown(vm)
			expect(view(vm).step).toBe("listen")
			expect(view(vm).hint).toBeNil()
			expect(view(vm).marker).toBeNil()
		end)

		it("does the walk step too when Amy talks to Dad before walking 4 studs", function()
			local vm = walking()
			Onboarding.dialogueShown(vm)
			expect(view(vm).step).toBe("listen")
		end)
	end)

	describe("Onboarding step listen", function()
		it("shows no Hint, and the Onboarding ends with the next Objective", function()
			local vm = walking()
			Onboarding.moved(vm, Onboarding.WALK_STUDS)
			Onboarding.dialogueShown(vm)
			Onboarding.dialogueFinished(vm)
			expect(view(vm).hint).toBeNil()
			Onboarding.objectiveShown(vm, FIRST_OBJECTIVE) -- the same Objective again changes nothing
			expect(vm.state).toBe("running")
			Onboarding.objectiveShown(vm, NEXT_OBJECTIVE)
			expect(vm.state).toBe("finished")
			expect(view(vm).step).toBeNil()
		end)
	end)

	describe("Onboarding skip", function()
		it("ends the Onboarding from any step: no Hint, ring, pulse or marker", function()
			for _, at in { fresh, walking } do
				local vm = at()
				Onboarding.skip(vm)
				local shown = view(vm, true)
				expect(shown.hint).toBeNil()
				expect(shown.ring).toBe(false)
				expect(shown.marker).toBeNil()
				expect(shown.row).toBe(hints.continue.touch)
				expect(shown.skip).toBe(false)
				Onboarding.objectiveShown(vm, NEXT_OBJECTIVE)
				Onboarding.dialogueShown(vm)
				expect(vm.state).toBe("finished")
			end
		end)
	end)

	describe("Onboarding.STEPS", function()
		it("are the glossary's Onboarding steps, in order", function()
			local names = {}
			for _, entry in Glossary.parse(bootstrap.readSource("docs/GLOSSARY.md")).inUse("Onboarding steps") do
				table.insert(names, entry.name)
			end
			expect(names).toEqual(Onboarding.STEPS)
		end)
	end)

	describe("the Hints", function()
		it("give a Hint for each step feel.md gives one: advance, walk, talk", function()
			local steps = {}
			for step in hints.steps do
				expect(table.find(Onboarding.STEPS, step)).never.toBeNil()
				table.insert(steps, step)
			end
			table.sort(steps)
			expect(steps).toEqual({ "advance", "talk", "walk" })
		end)
	end)
end
