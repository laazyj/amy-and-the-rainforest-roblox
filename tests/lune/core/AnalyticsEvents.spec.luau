--[[
	AnalyticsEvents: every Story event and every Fault, in the code and in
	the glossary, is mapped to an analytics event of its own name, with its
	payload as custom fields; and a visit's end is logged with its length.
]]

local AnalyticsEvents = require("../../../src/core/AnalyticsEvents")
local Events = require("../../../src/core/Events")
local Fault = require("../../../src/core/Fault")
local Files = require("../../../tools/lib/files")
local Glossary = require("../../../tools/lib/glossary")

local glossary = Glossary.parse(Files.read("docs/GLOSSARY.md"))

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	-- The fields of a Story event's schema, sorted.
	local function schemaFields(kind: string): { string }
		local fields = {}
		for field in Events.STORY_EVENTS[kind] do
			table.insert(fields, field)
		end
		table.sort(fields)
		return fields
	end

	describe("AnalyticsEvents", function()
		it("maps every Story event to an analytics event with every field of its payload", function()
			for kind in Events.STORY_EVENTS do
				local fields = AnalyticsEvents.STORY_FIELDS[kind]
				if not fields then
					error(`Story event {kind} has no analytics event`)
				end
				local sorted = table.clone(fields)
				table.sort(sorted)
				expect(sorted).toEqual(schemaFields(kind))
				expect(#fields <= AnalyticsEvents.MAX_FIELDS).toBe(true)
			end
			for kind in AnalyticsEvents.STORY_FIELDS do
				expect(Events.STORY_EVENTS[kind] ~= nil).toBe(true)
			end
		end)

		it("maps every Story event the glossary lists in use", function()
			for _, entry in glossary.inUse("Story events") do
				if not AnalyticsEvents.STORY_FIELDS[entry.name] then
					error(`the glossary's Story event {entry.name} has no analytics event`)
				end
			end
		end)

		-- Fault.spec holds Fault.NAMES to the glossary's Faults
		it("maps every Fault to an event of its name", function()
			for name: Fault.Name in Fault.NAMES do
				expect(AnalyticsEvents.forFault(name)).toEqual({ name = name, value = 1, fields = {} })
			end
		end)

		it("logs a Story event under its own name, its payload as fields", function()
			expect(AnalyticsEvents.forStoryEvent({ kind = "QuestCompleted", quest = "chapter3.meet_fox" })).toEqual({
				name = "QuestCompleted",
				value = 1,
				fields = { "chapter3.meet_fox" },
			})
			expect(AnalyticsEvents.forStoryEvent({ kind = "StoryEnded" })).toEqual({
				name = "StoryEnded",
				value = 1,
				fields = {},
			})
		end)

		it("logs the end of a visit as SessionEnded, its value the whole seconds played", function()
			expect(AnalyticsEvents.forSessionEnded(754.9)).toEqual({ name = "SessionEnded", value = 754, fields = {} })
			expect(AnalyticsEvents.forSessionEnded(-1).value).toBe(0)
		end)

		it("gives every analytics event a name of its own", function()
			local names = { [AnalyticsEvents.SESSION_ENDED] = true }
			for kind in AnalyticsEvents.STORY_FIELDS do
				expect(names[kind]).toBeNil()
				names[kind] = true
			end
			for name in Fault.NAMES do
				expect(names[name]).toBeNil()
				names[name] = true
			end
		end)
	end)
end
