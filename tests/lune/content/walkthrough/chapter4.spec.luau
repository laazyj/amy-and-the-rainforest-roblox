--[[
	Walkthrough of chapter4 (Chapter Four, The Giant Tree-Chopping Machine) from its Checkpoint: the Quests it
	completes, what the player does, the Objectives shown, the Beats played
	and the World it leaves. tools/guard coverage requires one such spec
	per Chapter of the Story.
]]

local Chapter = require("./chapter")

local walk = Chapter.walk("chapter4")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("chapter4 from its Checkpoint", function()
		it("completes its Quests in order", function()
			expect(walk.quests).toEqual({
				"chapter4.stand_in_front",
				"chapter4.explain",
			})
		end)

		it("is played by EnteredZone(MachineFront), then TalkedTo(Dad)", function()
			expect(walk.played).toEqual({
				"EnteredZone(MachineFront)",
				"TalkedTo(Dad)",
			})
		end)

		it("shows each Quest's Objective in order", function()
			expect(walk.objectives).toEqual({
				"The machine is heading for the forest -- stand in front of it!",
				"Explain to Dad and the village why the forest must be saved",
			})
		end)

		it("plays beat machine_stops", function()
			expect(walk.beats).toEqual({
				"machine_stops",
			})
		end)

		it("ends with the machine retreating, the villagers cheering and no Objective", function()
			expect(walk.world.props).toEqual({ Machine = "retreating", Villagers = "cheering" })
			expect(walk.world.objective).toBeNil()
			expect(walk.world.talk).toEqual({})
		end)

		it("goes on to the Ending", function()
			expect(walk.next).toBe("StoryEnded")
		end)
	end)
end
