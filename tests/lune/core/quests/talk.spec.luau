-- Quest Kind talk: TalkedTo the Quest's Character.

local talk = require("../../../../src/core/quests/talk")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect
	local quest: any = { id = "chapter1.ask_dad", kind = "talk", character = "Dad", objective = "Ask Dad" }

	describe("talk", function()
		it("offers the Character's talk affordance, labelled Talk by default", function()
			expect(talk.begin(quest, {})).toEqual({ { kind = "OfferTalk", character = "Dad", label = "Talk" } })
		end)

		it("uses the Quest's talk label", function()
			local labelled = table.clone(quest)
			labelled.talkLabel = "Explain"
			expect((talk.begin(labelled, {})[1] :: any).label).toBe("Explain")
		end)

		it("is done on TalkedTo(Dad), withdrawing the talk affordance", function()
			expect(talk.handle(quest, {}, { kind = "TalkedTo", character = "Dad" })).toEqual({
				commands = { { kind = "WithdrawTalk", character = "Dad" } },
				done = true,
			})
		end)

		it("ignores TalkedTo another Character and other Player events", function()
			expect(talk.handle(quest, {}, { kind = "TalkedTo", character = "Mum" })).toBeNil()
			expect(talk.handle(quest, {}, { kind = "EnteredZone", zone = "GardenGate" })).toBeNil()
		end)

		it("shows its Objective as written", function()
			expect(talk.objective(quest, {})).toBe("Ask Dad")
		end)
	end)
end
