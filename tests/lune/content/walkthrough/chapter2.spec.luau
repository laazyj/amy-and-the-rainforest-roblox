--[[
	Walkthrough of chapter2 (Chapter Two, The Unexplored World) from its Checkpoint: the Quests it
	completes, what the player does, the Objectives shown, the Beats played
	and the World it leaves. tools/guard coverage requires one such spec
	per Chapter of the Story.
]]

local Chapter = require("./chapter")

local walk = Chapter.walk("chapter2")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("chapter2 from its Checkpoint", function()
		it("completes its Quests in order", function()
			expect(walk.quests).toEqual({
				"chapter2.walk_to_forest",
				"chapter2.enter_forest",
				"chapter2.heart_glade",
			})
		end)

		it("is played by EnteredZone(ForestEdge), then EnteredZone(ForestGap), then EnteredZone(HeartGlade)", function()
			expect(walk.played).toEqual({
				"EnteredZone(ForestEdge)",
				"EnteredZone(ForestGap)",
				"EnteredZone(HeartGlade)",
			})
		end)

		it("shows each Quest's Objective in order", function()
			expect(walk.objectives).toEqual({
				"Sam is away at the farm -- cross the field to the rain forest!",
				"Squeeze through the gap between the giant trees",
				"Follow the glowing flowers deeper into the paradise",
			})
		end)

		it("plays beat paradise_reveal", function()
			expect(walk.beats).toEqual({
				"paradise_reveal",
			})
		end)

		it("ends with Sam at spot Farm (beat sam_goes_to_farm, replayed by the Resume) in lighting:paradise", function()
			expect(walk.world.characters.Sam).toBe("Farm")
			expect(walk.world.lighting).toBe("paradise")
			expect(walk.world.props).toEqual({ Machine = "absent", Villagers = "absent" })
		end)

		it("goes on to chapter3", function()
			expect(walk.next).toBe("ChapterStarted(chapter3)")
		end)
	end)
end
