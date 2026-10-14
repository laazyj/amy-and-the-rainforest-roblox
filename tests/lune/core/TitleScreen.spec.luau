--[[
	TitleScreen on the fixture Story: what a returning player is offered,
	what each Title choice does to their Save, and the view-model the
	client binder renders, confirmation of "Start again" included.
]]

local Save = require("../../../src/core/Save")
local Settings = require("../../../src/core/Settings")
local StoryEngine = require("../../../src/core/StoryEngine")
local TitleScreen = require("../../../src/core/TitleScreen")
local fixture = require("./fixtureStory")

local function savedAt(questId: string): Save.Save
	return Save.record(fixture, Save.new(), StoryEngine.progressAt(fixture, questId))
end

local function ended(): Save.Save
	local progress = StoryEngine.fresh()
	progress.completed = { "chapter1.greet", "chapter1.go_out", "chapter2.pick" }
	progress.ended = true
	return Save.record(fixture, Save.new(), progress)
end

local function ids(view: TitleScreen.View): { string }
	local list = {}
	for _, button in view.buttons do
		table.insert(list, button.id)
	end
	return list
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("TitleScreen.offer", function()
		it("offers nothing to a player who has not started: the Story starts at once", function()
			expect(TitleScreen.offer(fixture, Save.new())).toBeNil()
		end)

		it("offers a returning player Continue in the Chapter they are in", function()
			expect(TitleScreen.offer(fixture, savedAt("chapter2.pick"))).toEqual({
				chapter = "Two — The field",
				canContinue = true,
			})
		end)

		it("offers no Continue once the Story has ended, and the last Chapter to play again", function()
			expect(TitleScreen.offer(fixture, ended())).toEqual({ chapter = "Two — The field", canContinue = false })
		end)
	end)

	describe("TitleScreen.choose", function()
		it("continue: a Resume at the current Quest, the Save as it was", function()
			local save = savedAt("chapter1.go_out")
			local chosen, progress = TitleScreen.choose(fixture, save, "continue")
			expect(chosen).toEqual(save)
			expect(progress).toEqual(StoryEngine.progressAt(fixture, "chapter1.go_out"))
		end)

		it("replay: a Resume at the current Chapter's Checkpoint, saved as the Progress", function()
			local save = savedAt("chapter1.go_out")
			local chosen, progress = TitleScreen.choose(fixture, save, "replay")
			expect(progress).toEqual(StoryEngine.progressAt(fixture, "chapter1.greet"))
			expect(chosen.progress).toEqual(progress)
			expect(chosen.checkpoints).toEqual(save.checkpoints)
		end)

		it("replay after the Ending: the last Chapter from its Checkpoint", function()
			local _, progress = TitleScreen.choose(fixture, ended(), "replay")
			expect(progress).toEqual(StoryEngine.progressAt(fixture, "chapter2.pick"))
		end)

		it("restart: a new Save and fresh Progress", function()
			local chosen, progress = TitleScreen.choose(fixture, savedAt("chapter2.pick"), "restart")
			expect(chosen).toEqual(Save.new())
			expect(progress).toEqual(StoryEngine.fresh())
		end)

		it("restart keeps the player's Settings in the new Save", function()
			local save = Save.withSettings(savedAt("chapter2.pick"), Settings.change(Settings.DEFAULTS, "font", 1))
			local chosen = TitleScreen.choose(fixture, save, "restart")
			expect(Save.started(chosen)).toBe(false)
			expect(chosen.settings.font).toBe("dyslexia")
		end)

		it("knows exactly the three Title choices", function()
			expect(TitleScreen.CHOICES).toEqual({ continue = true, replay = true, restart = true })
		end)
	end)

	describe("the view-model", function()
		it("shows the title words while loading, with no buttons", function()
			local vm = TitleScreen.new()
			expect(TitleScreen.view(vm)).toEqual({ visible = true, note = nil, buttons = {} })
			expect(TitleScreen.WORDS.name).toBe("Amy")
			expect(TitleScreen.WORDS.the .. TitleScreen.WORDS.gold).toBe("& the Rain Forest")
			expect(TitleScreen.WORDS.pill).toBe("a little tale of the wild")
		end)

		it("closes for a player with no Save when the Story's first message arrives", function()
			local vm = TitleScreen.new()
			TitleScreen.close(vm)
			expect(TitleScreen.view(vm).visible).toBe(false)
		end)

		it("shows Continue, Play this chapter again and Start again, under the Chapter", function()
			local vm = TitleScreen.new()
			TitleScreen.show(vm, { chapter = "Two — The field", canContinue = true })
			local view = TitleScreen.view(vm)
			expect(view.note).toBe("Two — The field")
			expect(view.buttons).toEqual({
				{ id = "continue", label = "Continue", primary = true },
				{ id = "replay", label = "Play this chapter again", primary = false },
				{ id = "restart", label = "Start again", primary = false },
			})
		end)

		it("leaves out Continue when there is nothing to continue", function()
			local vm = TitleScreen.new()
			TitleScreen.show(vm, { chapter = "Two — The field", canContinue = false })
			expect(ids(TitleScreen.view(vm))).toEqual({ "replay", "restart" })
			expect(TitleScreen.press(vm, "continue")).toBeNil()
		end)

		for _, choice in { "continue", "replay" } do
			it(`sends {choice} at once and closes`, function()
				local vm = TitleScreen.new()
				TitleScreen.show(vm, { chapter = "One — The start", canContinue = true })
				expect(TitleScreen.press(vm, choice)).toBe(choice)
				expect(TitleScreen.view(vm).visible).toBe(false)
			end)
		end

		it("asks before Start again, and sends restart only when confirmed", function()
			local vm = TitleScreen.new()
			TitleScreen.show(vm, { chapter = "One — The start", canContinue = true })
			expect(TitleScreen.press(vm, "restart")).toBeNil()
			local asking = TitleScreen.view(vm)
			expect(asking.note).toBe(
				"Start the whole story again from the very beginning? Your place in the story will be gone."
			)
			expect(ids(asking)).toEqual({ "confirm", "cancel" })
			expect(TitleScreen.press(vm, "continue")).toBeNil()
			expect(TitleScreen.press(vm, "confirm")).toBe("restart")
			expect(TitleScreen.view(vm).visible).toBe(false)
		end)

		it("goes back to the choices when Start again is cancelled", function()
			local vm = TitleScreen.new()
			TitleScreen.show(vm, { chapter = "One — The start", canContinue = true })
			TitleScreen.press(vm, "restart")
			expect(TitleScreen.press(vm, "cancel")).toBeNil()
			expect(ids(TitleScreen.view(vm))).toEqual({ "continue", "replay", "restart" })
		end)

		it("ignores an offer that arrives once closed, and presses once closed", function()
			local vm = TitleScreen.new()
			TitleScreen.close(vm)
			TitleScreen.show(vm, { chapter = "One — The start", canContinue = true })
			expect(TitleScreen.view(vm).visible).toBe(false)
			expect(TitleScreen.press(vm, "continue")).toBeNil()
		end)
	end)
end
