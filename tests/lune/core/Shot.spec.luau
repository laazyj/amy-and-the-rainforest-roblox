--[[
	Shot: the Shots are the glossary's, and only the Shots that accompany
	a Dialogue hold; every other lasts at most 4 seconds. shot:Dialogue
	frames every Dialogue whose Speaker is a Character in the world.
]]

local Shot = require("../../../src/core/Shot")
local glossary = require("../content/glossary")
local fixture = require("./fixtureStory")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("Shot", function()
		it("names exactly the glossary's Shots", function()
			local names = {}
			for name in glossary.names("Shots") do
				table.insert(names, name)
			end
			table.sort(names)
			local ours = table.clone(Shot.NAMES)
			table.sort(ours)
			expect(ours).toEqual(names)
		end)

		it("holds shot:Dialogue and shot:MachineFinale until DialogueFinished", function()
			expect(Shot.HELD).toEqual({ Dialogue = true, MachineFinale = true })
		end)

		it("holds its framing after easing in, within 4 seconds in all, unless held until DialogueFinished", function()
			for _, name in Shot.NAMES do
				local hold = Shot.HOLD[name]
				expect(Shot.HELD[name] == true or (hold ~= nil and Shot.EASE_IN + hold <= Shot.LONGEST)).toBe(true)
			end
		end)

		it("eases in and hands back over 0.5 s", function()
			expect(Shot.EASE_IN).toBe(0.5)
			expect(Shot.HAND_BACK).toBe(0.5)
		end)
	end)

	describe("Shot.forDialogue", function()
		local NARRATOR = { speaker = "Narrator", text = "Hello." }
		local HERO = { speaker = "Hero", text = "Hi!" }
		local GUIDE = { speaker = "Guide", text = "Welcome." }

		it("frames shot:Dialogue of the first Speaker who is a Character in the world", function()
			expect(Shot.forDialogue(fixture, { NARRATOR, HERO, GUIDE }, {})).toEqual({
				kind = "FrameShot",
				shot = "Dialogue",
				character = "Guide",
			})
		end)

		it("keeps the current camera for a Dialogue of the Narrator and the Player Character only", function()
			expect(Shot.forDialogue(fixture, { NARRATOR }, {})).toBeNil()
			expect(Shot.forDialogue(fixture, { HERO, NARRATOR }, {})).toBeNil()
		end)

		it("frames it after shot:MeetCharacter, which ends before the Dialogue does", function()
			local met = { { kind = "FrameShot", shot = "MeetCharacter", character = "Guide" } }
			expect(Shot.forDialogue(fixture, { GUIDE }, met :: any)).never.toBeNil()
		end)

		it("leaves a Dialogue that shot:MachineFinale accompanies to it", function()
			local finale: { any } = { { kind = "FrameShot", shot = "MachineFinale" }, { kind = "SetObjective" } }
			expect(Shot.forDialogue(fixture, { GUIDE }, finale)).toBeNil()
		end)
	end)
end
