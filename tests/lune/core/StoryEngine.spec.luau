--[[
	StoryEngine on the fixture Story: the order of what it emits, what it
	ignores, the Chapter card, the Ending, Resume, and the per-player wrapper.
	The real Story is walked in tests/lune/content/Story.spec.luau.
]]

local Story = require("../../../src/core/Story")
local StoryEngine = require("../../../src/core/StoryEngine")
local WorldState = require("../../../src/core/WorldState")
local Walker = require("./walker")
local fixture = require("./fixtureStory")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("StoryEngine.start", function()
		local progress, events, commands = StoryEngine.start(fixture, StoryEngine.fresh())

		it("shows the first Chapter card, waits 3.2 s, then starts the first Quest", function()
			expect(Walker.kinds(commands)).toEqual({ "ShowChapterCard", "Wait", "SetObjective", "ShowDialogue" })
			expect(commands[1]).toEqual({
				kind = "ShowChapterCard",
				ending = false,
				title = "One",
				subtitle = "The start",
			})
			expect(commands[2]).toEqual({ kind = "Wait", seconds = 3.2 })
			expect(commands[3]).toEqual({ kind = "SetObjective", text = "Greet the Guide" })
		end)

		it("emits ChapterStarted and QuestStarted", function()
			expect(events).toEqual({
				{ kind = "ChapterStarted", chapter = "chapter1" },
				{ kind = "QuestStarted", quest = "chapter1.greet" },
			} :: { any })
		end)

		it("makes the first Quest active with its intro showing", function()
			expect(progress.quest).toBe("chapter1.greet")
			expect(progress.chapter).toBe("chapter1")
			expect(progress.showing).toBe("intro")
		end)

		it("shows Lines by the Speaker's display name, without the canon flag", function()
			expect(commands[4]).toEqual({ kind = "ShowDialogue", lines = { { speaker = "Narrator", text = "Hello." } } })
		end)

		it("does nothing for Progress that has already started", function()
			local again, againEvents, againCommands = StoryEngine.start(fixture, progress)
			expect(again).toBe(progress)
			expect(#againEvents + #againCommands).toBe(0)
		end)

		it("does not change the Progress it is given", function()
			local fresh = StoryEngine.fresh()
			StoryEngine.start(fixture, fresh)
			expect(fresh).toEqual(StoryEngine.fresh())
		end)
	end)

	describe("chapter1.greet (talk)", function()
		local started = StoryEngine.start(fixture, StoryEngine.fresh())

		it("ignores TalkedTo(Guide) while the intro is showing", function()
			local progress, events, commands =
				StoryEngine.step(fixture, started, { kind = "TalkedTo", character = "Guide" })
			expect(progress).toBe(started)
			expect(#events + #commands).toBe(0)
		end)

		local playable, _, offered = StoryEngine.step(fixture, started, { kind = "DialogueFinished" })

		it("offers the talk affordance with its label once the intro is finished", function()
			expect(offered).toEqual({ { kind = "OfferTalk", character = "Guide", label = "Wave" } })
			expect(playable.showing).toBeNil()
		end)

		it("ignores TalkedTo another Character", function()
			local progress = StoryEngine.step(fixture, playable, { kind = "TalkedTo", character = "Hero" })
			expect(progress).toBe(playable)
		end)

		local talking, _, talked = StoryEngine.step(fixture, playable, { kind = "TalkedTo", character = "Guide" })

		it("withdraws the talk affordance and shows the dialogue on TalkedTo(Guide)", function()
			expect(Walker.kinds(talked)).toEqual({ "WithdrawTalk", "ShowDialogue" })
			expect(talked[2]).toEqual({
				kind = "ShowDialogue",
				lines = { { speaker = "the Hero", text = "Hi!" }, { speaker = "the Guide", text = "Welcome." } },
			})
			expect(talking.showing).toBe("dialogue")
			expect(talking.quest).toBe("chapter1.greet")
		end)

		local outro, _, outroCommands = StoryEngine.step(fixture, talking, { kind = "DialogueFinished" })

		it("shows the outro while the Quest is still active", function()
			expect(Walker.kinds(outroCommands)).toEqual({ "ShowDialogue" })
			expect(outro.showing).toBe("outro")
			expect(outro.quest).toBe("chapter1.greet")
			expect(outro.completed).toEqual({})
		end)

		local after, events, commands = StoryEngine.step(fixture, outro, { kind = "DialogueFinished" })

		it("plays beat guide_leaves at onComplete, then starts chapter1.go_out with its onStart Beats", function()
			expect(Walker.kinds(commands)).toEqual({
				"MoveCharacter",
				"Wait",
				"TeleportPlayer",
				"SetPropState",
				"SetLighting",
				"SetObjective",
			})
			expect(events).toEqual({
				{ kind = "QuestCompleted", quest = "chapter1.greet" },
				{ kind = "BeatPlayed", beat = "guide_leaves" },
				{ kind = "QuestStarted", quest = "chapter1.go_out" },
				{ kind = "BeatPlayed", beat = "door_opens" },
				{ kind = "BeatPlayed", beat = "dusk_falls" },
			} :: { any })
		end)

		it("makes chapter1.go_out active and playable at once (no intro)", function()
			expect(after.quest).toBe("chapter1.go_out")
			expect(after.showing).toBeNil()
			expect(after.completed).toEqual({ "chapter1.greet" })
		end)
	end)

	describe("chapter1.go_out (reach) into chapter2", function()
		local walk = Walker.walk(fixture)
		local index: number?
		for i, step in walk.steps do
			if step.event and step.event.kind == "EnteredZone" then
				index = i
			end
		end
		local step = walk.steps[assert(index, "no EnteredZone step")]

		it("completes on EnteredZone(Gate) and shows the next Chapter's card before its first Quest", function()
			expect(Walker.kinds(step.commands)).toEqual({
				"ShowChapterCard",
				"Wait",
				"SetObjective",
				"ShowDialogue",
			})
			expect(Walker.kinds(step.events)).toEqual({
				"QuestCompleted",
				"ChapterCompleted",
				"ChapterStarted",
				"QuestStarted",
			})
		end)

		it("names the new Quest as active for the Chapter card", function()
			expect(step.quest).toBe("chapter2.pick")
		end)

		it("ignores EnteredZone for another Zone", function()
			local progress = walk.playable["chapter1.go_out"].progress
			expect(StoryEngine.step(fixture, progress, { kind = "EnteredZone", zone = "Elsewhere" })).toBe(progress)
		end)
	end)

	describe("chapter2.pick (collect) and the Ending", function()
		local walk = Walker.walk(fixture)
		local touches = {}
		for _, step in walk.steps do
			if step.event and step.event.kind == "TouchedPickup" then
				table.insert(touches, step)
			end
		end

		it("spawns the Pickups once the intro is finished", function()
			local playable = walk.playable["chapter2.pick"]
			expect(playable.world.pickups["chapter2.pick"]).toEqual({ FlowerA = true, FlowerB = true, FlowerC = true })
			expect(playable.world.objective).toBe("Pick flowers  (0/2)")
		end)

		it("removes each Pickup touched and counts it in the Objective", function()
			expect(touches[1].commands).toEqual({
				{ kind = "RemovePickup", pickup = "FlowerA" },
				{ kind = "SetObjective", text = "Pick flowers  (1/2)" },
			} :: { any })
		end)

		it("completes at the count, clears the Objective and shows the Ending's Dialogue", function()
			expect(#touches).toBe(2)
			expect(Walker.kinds(touches[2].commands)).toEqual({
				"RemovePickup",
				"SetObjective",
				"SetObjective",
				"ShowDialogue",
			})
			expect(touches[2].commands[3]).toEqual({ kind = "SetObjective", text = nil })
			expect(touches[2].quest).toBeNil()
		end)

		it("shows the end card after the Ending's Dialogue and ends the Story", function()
			local last = walk.steps[#walk.steps]
			expect(last.commands).toEqual({
				{ kind = "ShowChapterCard", title = "The end", subtitle = "Fixture", ending = true },
			})
			expect(last.events).toEqual({ { kind = "StoryEnded" } })
			expect(walk.progress.ended).toBe(true)
		end)

		it("ignores a Pickup already touched", function()
			local progress = walk.playable["chapter2.pick"].progress
			local once = StoryEngine.step(fixture, progress, { kind = "TouchedPickup", pickup = "FlowerC" })
			expect(StoryEngine.step(fixture, once, { kind = "TouchedPickup", pickup = "FlowerC" })).toBe(once)
		end)

		it("ignores Player events after the Story has ended", function()
			expect(StoryEngine.step(fixture, walk.progress, { kind = "DialogueFinished" }).ended).toBe(true)
			expect(StoryEngine.step(fixture, walk.progress, { kind = "EnteredZone", zone = "Gate" })).toBe(
				walk.progress
			)
		end)
	end)

	describe("StoryEngine.resume", function()
		local walk = Walker.walk(fixture)
		for _, placed in Story.quests(fixture) do
			local quest = placed.quest
			local playable = walk.playable[quest.id]

			it(`rebuilds the World the walk had at {quest.id}`, function()
				local resumed = Walker.rebuild(fixture, StoryEngine.resume(fixture, playable.progress))
				expect(resumed).toEqual(Walker.withoutPlayer(playable.world))
			end)

			it(`completes the Story from a Resume at {quest.id}`, function()
				local world = Walker.rebuild(fixture, StoryEngine.resume(fixture, playable.progress))
				expect(Walker.walk(fixture, playable.progress, world).progress.ended).toBe(true)
			end)
		end

		it("rebuilds the scenes' initial World for fresh Progress", function()
			local resumed = Walker.rebuild(fixture, StoryEngine.resume(fixture, StoryEngine.fresh()))
			expect(resumed).toEqual(WorldState.initial(fixture))
		end)

		it("keeps the Pickups already touched out of the World", function()
			local progress = Walker.deepCopy(walk.playable["chapter2.pick"].progress)
			progress.collected = { "FlowerB" }
			local resumed = Walker.rebuild(fixture, StoryEngine.resume(fixture, progress))
			expect(resumed.pickups["chapter2.pick"]).toEqual({ FlowerA = true, FlowerC = true })
			expect(resumed.objective).toBe("Pick flowers  (1/2)")
		end)
	end)

	describe("StoryEngine.progressAt", function()
		local walk = Walker.walk(fixture)
		for _, placed in Story.quests(fixture) do
			it(`is the Progress the walk had once {placed.quest.id} was playable`, function()
				expect(StoryEngine.progressAt(fixture, placed.quest.id)).toEqual(
					walk.playable[placed.quest.id].progress
				)
			end)
		end

		it("refuses a Quest the Story does not have", function()
			t.expectError(function()
				StoryEngine.progressAt(fixture, "chapter9.fly")
			end, "no Quest chapter9.fly")
		end)
	end)

	describe("StoryEngine.new", function()
		local engine = StoryEngine.new(-1, nil, fixture)

		it("starts from fresh Progress", function()
			expect(engine:snapshot()).toEqual(StoryEngine.fresh())
			expect(engine:activeQuest()).toBeNil()
		end)

		it("keeps the Progress between steps", function()
			engine:start()
			expect(engine:activeQuest()).toBe("chapter1.greet")
			engine:step({ kind = "DialogueFinished" })
			expect(engine:snapshot().showing).toBeNil()
		end)

		it("returns the active Quest with its id", function()
			local id, quest = engine:activeQuest()
			expect(id).toBe("chapter1.greet")
			expect(quest and quest.kind).toBe("talk")
		end)

		it("hands out copies of its Progress", function()
			local snapshot = engine:snapshot()
			table.insert(snapshot.completed, "changed")
			expect(engine:snapshot().completed).toEqual({})
		end)

		it("keeps the player id", function()
			expect(engine.playerId).toBe(-1)
		end)
	end)
end
