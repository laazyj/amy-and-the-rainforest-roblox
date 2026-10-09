--[[
	Events: the schemas name every Player event, Story event and World
	command in the glossary, and `check` rejects malformed messages.
]]

local Events = require("../../../src/core/Events")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	local function keys(map: { [string]: any }): { string }
		local list = {}
		for key in map do
			table.insert(list, key)
		end
		table.sort(list)
		return list
	end

	describe("Events schemas", function()
		it("name the Player events", function()
			expect(keys(Events.PLAYER_EVENTS)).toEqual({
				"DialogueFinished",
				"EnteredZone",
				"TalkedTo",
				"TouchedPickup",
			})
		end)

		it("name the Story events", function()
			expect(keys(Events.STORY_EVENTS)).toEqual({
				"BeatPlayed",
				"ChapterCompleted",
				"ChapterStarted",
				"QuestCompleted",
				"QuestStarted",
				"StoryEnded",
			})
		end)

		it("name the World commands", function()
			expect(keys(Events.WORLD_COMMANDS)).toEqual({
				"ClearPickups",
				"MoveCharacter",
				"OfferTalk",
				"RemovePickup",
				"SetLighting",
				"SetObjective",
				"SetPropState",
				"ShowChapterCard",
				"ShowDialogue",
				"SpawnPickups",
				"TeleportPlayer",
				"Wait",
				"WithdrawTalk",
			})
		end)
	end)

	describe("Events.check", function()
		local valid: { { any } } = {
			{ Events.PLAYER_EVENTS, { kind = "EnteredZone", zone = "GardenGate" } },
			{ Events.PLAYER_EVENTS, { kind = "DialogueFinished" } },
			{ Events.STORY_EVENTS, { kind = "BeatPlayed", beat = "sam_catches" } },
			{ Events.WORLD_COMMANDS, { kind = "SetObjective" } },
			{
				Events.WORLD_COMMANDS,
				{ kind = "ShowChapterCard", title = "The end ♥", subtitle = "Clara", ending = true },
			},
			{ Events.WORLD_COMMANDS, { kind = "ShowDialogue", lines = { { speaker = "Amy", text = "Deal." } } } },
			{ Events.WORLD_COMMANDS, { kind = "Wait", seconds = 0.5 } },
		}
		for i, case in valid do
			it(`accepts valid message {i} ({case[2].kind})`, function()
				expect(Events.check(case[1], case[2])).toBe(true)
			end)
		end

		local P, W = Events.PLAYER_EVENTS, Events.WORLD_COMMANDS
		local malformed: { { any } } = {
			{ P, "a string", "expected a table" },
			{ P, { kind = "Teleported" }, "unknown kind Teleported" },
			{ P, { kind = "EnteredZone" }, "EnteredZone.zone must be string" },
			{ P, { kind = "EnteredZone", zone = 3 }, "EnteredZone.zone must be string" },
			{ P, { kind = "EnteredZone", zone = "Gate", extra = true }, "has no field extra" },
			{ W, { kind = "ShowDialogue", lines = {} }, "ShowDialogue.lines must be lines" },
			{ W, { kind = "ShowDialogue", lines = { { speaker = "Amy" } } }, "must be lines" },
			{
				W,
				{ kind = "ShowDialogue", lines = { { speaker = "Amy", text = "Hi", canon = true } } },
				"must be lines",
			},
			{ W, { kind = "Wait", seconds = "0.5" }, "Wait.seconds must be number" },
			{ W, { kind = "ShowChapterCard", title = "a", subtitle = "b" }, "ShowChapterCard.ending must be boolean" },
		}
		for _, case in malformed do
			it(`rejects a malformed message: {case[3]}`, function()
				local ok, reason = Events.check(case[1], case[2])
				expect(ok).toBe(false)
				expect(reason).toContain(case[3])
			end)
		end
	end)
end
