--[[
	Save on the fixture Story: the schema versions and their Migrations, the
	tolerance of a one-version-newer Save, the Checkpoints a Save records,
	and the Progress a Resume restores from it. The real Story's Saves are
	walked in tests/lune/content/Story.spec.luau.
]]

local Save = require("../../../src/core/Save")
local Story = require("../../../src/core/Story")
local StoryEngine = require("../../../src/core/StoryEngine")
local fixture = require("./fixtureStory")
local serde = require("@lune/serde")

-- Through JSON, as a DataStore keeps it.
local function stored(data: any): any
	return serde.decode("json", serde.encode("json", data))
end

local function progressAt(questId: string)
	return StoryEngine.progressAt(fixture, questId)
end

-- Every Quest of the fixture, in order.
local ALL_QUESTS = {}
for _, placed in Story.quests(fixture) do
	table.insert(ALL_QUESTS, placed.quest.id)
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("Save.new", function()
		it("is a Save of this version with fresh Progress and no Checkpoints", function()
			expect(Save.new()).toEqual({ version = Save.VERSION, progress = StoryEngine.fresh(), checkpoints = {} })
			expect(Save.started(Save.new())).toBe(false)
		end)
	end)

	describe("the Migrations", function()
		it("has one Migration for every schema version before this one", function()
			for version = 1, Save.VERSION - 1 do
				expect(type(Save.MIGRATIONS[version])).toBe("function")
			end
			expect(Save.MIGRATIONS[Save.VERSION]).toBeNil()
		end)

		describe("version 1 -> 2", function()
			it("adds a Checkpoint at the start of every Chapter the Progress has reached", function()
				local progress = progressAt("chapter2.pick")
				progress.collected = { "FlowerA" }
				local save = assert(Save.read(fixture, stored({ version = 1, progress = progress })))
				expect(save.version).toBe(2)
				expect(save.progress).toEqual(progress)
				expect(save.checkpoints).toEqual({
					chapter1 = progressAt("chapter1.greet"),
					chapter2 = progressAt("chapter2.pick"),
				})
			end)

			it("adds no Checkpoint for a player who had not started", function()
				local save = assert(Save.read(fixture, stored({ version = 1, progress = StoryEngine.fresh() })))
				expect(save.checkpoints).toEqual({})
			end)

			it("adds every Chapter's Checkpoint once the Story has ended", function()
				local ended = StoryEngine.fresh()
				ended.completed = table.clone(ALL_QUESTS)
				ended.ended = true
				local save = assert(Save.read(fixture, stored({ version = 1, progress = ended })))
				expect(save.checkpoints.chapter2).toEqual(progressAt("chapter2.pick"))
			end)
		end)
	end)

	describe("Save.read", function()
		it("reads an empty table, ProfileStore's new profile, as a new Save", function()
			expect(Save.read(fixture, {})).toEqual(Save.new())
		end)

		it("reads back what Save.write stored, through JSON", function()
			local save = Save.record(fixture, Save.new(), progressAt("chapter1.go_out"))
			expect(Save.read(fixture, stored(Save.write(save)))).toEqual(save)
		end)

		it("reads a Save one version newer as its own, keeping its version and the fields it does not know", function()
			local newer = Save.write(Save.record(fixture, Save.new(), progressAt("chapter2.pick")))
			newer.version = Save.VERSION + 1
			newer.bonds = { Guide = "friend" }
			newer.progress.journal = { "acorn" }
			local save = assert(Save.read(fixture, stored(newer)))
			expect(save.version).toBe(Save.VERSION + 1)
			expect(save.bonds).toEqual({ Guide = "friend" })
			expect(Save.restore(fixture, save.progress)).toEqual(progressAt("chapter2.pick"))
			-- and what it writes back still holds them
			local written = Save.write(Save.record(fixture, save, save.progress))
			expect(written.version).toBe(Save.VERSION + 1)
			expect(written.bonds).toEqual({ Guide = "friend" })
			expect(written.progress.journal).toEqual({ "acorn" })
		end)

		local unreadable: { { any } } = {
			{ "a string", "hello", "a Save is a table" },
			{ "two versions newer", { version = Save.VERSION + 2, progress = StoryEngine.fresh() }, "newer" },
			{ "no version", { progress = StoryEngine.fresh() }, "unknown schema version nil" },
			{ "version 0", { version = 0, progress = StoryEngine.fresh() }, "unknown schema version 0" },
			{ "no Progress", { version = 2, checkpoints = {} }, "progress: expected a table" },
			{
				"a Quest that is not an id",
				{ version = 2, progress = { quest = 3, completed = {}, collected = {}, ended = false } },
				"quest must be a string",
			},
			{
				"an unknown Dialogue showing",
				{ version = 2, progress = { completed = {}, collected = {}, showing = "song", ended = false } },
				"showing cannot be song",
			},
			{
				"completed not a list of ids",
				{ version = 2, progress = { completed = { 1 }, collected = {}, ended = false } },
				"lists of ids",
			},
			{
				"a malformed Checkpoint",
				{ version = 2, progress = StoryEngine.fresh(), checkpoints = { chapter1 = { ended = "no" } } },
				"checkpoint chapter1",
			},
		}
		for _, case in unreadable do
			it(`does not read {case[1]}`, function()
				local save, reason = Save.read(fixture, case[2])
				expect(save).toBeNil()
				expect(reason).toContain(case[3])
			end)
		end
	end)

	describe("Save.open", function()
		it("opens a Save as Save.read reads it", function()
			local save = Save.record(fixture, Save.new(), progressAt("chapter2.pick"))
			expect(Save.open(fixture, stored(Save.write(save)))).toEqual(save)
		end)

		it("keeps data that is no Save aside, under unreadable, in a new Save, and says why", function()
			local corrupt = { version = 2, progress = { quest = 3 } }
			local save, reason = Save.open(fixture, corrupt)
			expect(reason).toContain("progress")
			expect(Save.started(save :: Save.Save)).toBe(false)
			expect((save :: any).unreadable).toEqual(corrupt)
			-- and what is kept aside survives the next records
			local later = Save.record(fixture, save :: Save.Save, progressAt("chapter1.go_out"))
			expect(later.unreadable).toEqual(corrupt)
			expect(Save.open(fixture, "garbage")).toEqual(
				{ version = Save.VERSION, progress = StoryEngine.fresh(), checkpoints = {}, unreadable = "garbage" } :: any
			)
		end)

		it("opens nothing for a Save two versions newer, which must never be written over", function()
			local save, reason = Save.open(fixture, { version = Save.VERSION + 2, progress = StoryEngine.fresh() })
			expect(save).toBeNil()
			expect(reason).toContain("newer")
		end)
	end)

	describe("Save.write", function()
		it("shares no table with the Save", function()
			local save = Save.record(fixture, Save.new(), progressAt("chapter1.go_out"))
			local written = Save.write(save)
			table.insert(written.progress.completed, "chapter1.go_out")
			expect(#save.progress.completed).toBe(1)
		end)
	end)

	describe("Save.record", function()
		it("takes a Checkpoint when a Chapter starts: its first Quest just started, no Dialogue showing", function()
			local progress = StoryEngine.start(fixture, StoryEngine.fresh())
			expect(progress.showing).toBe("intro")
			local save = Save.record(fixture, Save.new(), progress)
			expect(save.progress).toEqual(progress)
			expect(save.checkpoints).toEqual({ chapter1 = progressAt("chapter1.greet") })
			expect(Save.started(save)).toBe(true)
		end)

		it("keeps a Checkpoint once taken while the Chapter is played", function()
			local first = Save.record(fixture, Save.new(), progressAt("chapter1.greet"))
			first.checkpoints.chapter1.collected = { "kept" }
			local later = Save.record(fixture, first, progressAt("chapter1.go_out"))
			expect(later.checkpoints.chapter1.collected).toEqual({ "kept" })
		end)

		it("gives a jump to a later Chapter the Checkpoints of every Chapter up to it", function()
			local save = Save.record(fixture, Save.new(), progressAt("chapter2.pick"))
			expect(save.checkpoints).toEqual({
				chapter1 = progressAt("chapter1.greet"),
				chapter2 = progressAt("chapter2.pick"),
			})
		end)

		it("drops the Checkpoints of Chapters after the Progress", function()
			local later = Save.record(fixture, Save.new(), progressAt("chapter2.pick"))
			local back = Save.record(fixture, later, progressAt("chapter1.go_out"))
			expect(back.checkpoints).toEqual({ chapter1 = progressAt("chapter1.greet") })
		end)

		it("never records unstarted Progress over a started Save: a session still at the Title screen", function()
			local saved = Save.record(fixture, Save.new(), progressAt("chapter2.pick"))
			expect(Save.record(fixture, saved, StoryEngine.fresh())).toEqual(saved)
			-- a new Save takes it, as Start again's does
			expect(Save.record(fixture, Save.new(), StoryEngine.fresh())).toEqual(Save.new())
		end)

		it("leaves the Save it was given as it was", function()
			local save = Save.new()
			Save.record(fixture, save, progressAt("chapter2.pick"))
			expect(save).toEqual(Save.new())
		end)
	end)

	describe("Save.restore", function()
		it("resumes the active Quest as just started, keeping the Pickups it had touched", function()
			local progress = progressAt("chapter2.pick")
			progress.collected = { "FlowerB", "Gone" }
			local restored = Save.restore(fixture, progress)
			expect(restored.quest).toBe("chapter2.pick")
			expect(restored.completed).toEqual({ "chapter1.greet", "chapter1.go_out" })
			expect(restored.collected).toEqual({ "FlowerB" })
		end)

		for _, showing in { "intro", "dialogue", "outro" } do
			it(`resumes a Save made with the {showing} Dialogue showing as the Quest being played`, function()
				local progress = progressAt("chapter1.greet")
				progress.showing = showing :: any
				expect(Save.restore(fixture, progress)).toEqual(progressAt("chapter1.greet"))
			end)
		end

		it("resumes a Save made during the Ending as ended", function()
			local progress = StoryEngine.fresh()
			progress.completed = table.clone(ALL_QUESTS)
			progress.showing = "ending"
			local restored = Save.restore(fixture, progress)
			expect(restored.ended).toBe(true)
			expect(restored.quest).toBeNil()
			expect(restored.showing).toBeNil()
		end)

		it("resumes a Quest the Story no longer has at the first Quest not completed", function()
			local progress = progressAt("chapter1.go_out")
			progress.quest = "chapter1.renamed"
			expect(Save.restore(fixture, progress)).toEqual(progressAt("chapter1.go_out"))
			progress.completed = table.clone(ALL_QUESTS)
			expect(Save.restore(fixture, progress).ended).toBe(true)
		end)

		it("restores fresh Progress as fresh", function()
			expect(Save.restore(fixture, StoryEngine.fresh())).toEqual(StoryEngine.fresh())
		end)
	end)
end
