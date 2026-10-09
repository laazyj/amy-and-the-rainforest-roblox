--[[
	Walkthrough of chapter1 (Chapter One, One Beautyfull Sunday) from its Checkpoint: the Quests it
	completes, what the player does, the Objectives shown, the Beats played
	and the World it leaves. tools/guard coverage requires one such spec
	per Chapter of the Story.
]]

local Chapter = require("./chapter")

local walk = Chapter.walk("chapter1")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("chapter1 from its Checkpoint", function()
		it("completes its Quests in order", function()
			expect(walk.quests).toEqual({
				"chapter1.ask_dad",
				"chapter1.sneak_out_1",
				"chapter1.sneak_out_2",
			})
		end)

		it("is played by TalkedTo(Dad), then EnteredZone(GardenGate) twice", function()
			expect(walk.played).toEqual({
				"TalkedTo(Dad)",
				"EnteredZone(GardenGate)",
				"EnteredZone(GardenGate)",
			})
		end)

		it("shows each Quest's Objective in order", function()
			expect(walk.objectives).toEqual({
				"Ask Dad if you can go outside",
				"Sneak out through the garden gate... quietly!",
				"Wait for Sam to look away, then try the gate again",
			})
		end)

		it("plays beat sam_catches after each sneak-out", function()
			expect(walk.beats).toEqual({
				"sam_catches",
				"sam_catches",
			})
		end)

		it("ends with Amy at spot GardenInside, Sam at spot SamGuardPost, in lighting:ordinary", function()
			expect(walk.world.player).toBe("GardenInside")
			expect(walk.world.characters.Sam).toBe("SamGuardPost")
			expect(walk.world.lighting).toBe("ordinary")
		end)

		it("goes on to chapter2", function()
			expect(walk.next).toBe("ChapterStarted(chapter2)")
		end)
	end)
end
