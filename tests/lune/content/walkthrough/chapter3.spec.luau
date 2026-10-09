--[[
	Walkthrough of chapter3 (Chapter Three, So Many Animals!) from its Checkpoint: the Quests it
	completes, what the player does, the Objectives shown, the Beats played
	and the World it leaves. tools/guard coverage requires one such spec
	per Chapter of the Story.
]]

local Chapter = require("./chapter")

local walk = Chapter.walk("chapter3")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("chapter3 from its Checkpoint", function()
		it("completes its Quests in order", function()
			expect(walk.quests).toEqual({
				"chapter3.meet_squirrel",
				"chapter3.meet_fox",
				"chapter3.meet_lion",
				"chapter3.rush_home",
				"chapter3.tell_mum",
			})
		end)

		it(
			"is played by TalkedTo(Squirrel), then TalkedTo(Fox), then TalkedTo(Lion), then EnteredZone(HomeGarden), then TalkedTo(Mum)",
			function()
				expect(walk.played).toEqual({
					"TalkedTo(Squirrel)",
					"TalkedTo(Fox)",
					"TalkedTo(Lion)",
					"EnteredZone(HomeGarden)",
					"TalkedTo(Mum)",
				})
			end
		)

		it("shows each Quest's Objective in order", function()
			expect(walk.objectives).toEqual({
				"Say hello to the maroon squirrel",
				"Find the orange fox",
				"Meet the golden lion in the deep glade",
				"Rush home and tell Mum everything!",
				"Tell Mum about the parallel world",
			})
		end)

		it("plays beat ordinary_world, beat machine_arrives", function()
			expect(walk.beats).toEqual({
				"ordinary_world",
				"machine_arrives",
			})
		end)

		it(
			"ends in lighting:ordinary with the machine advancing, the villagers gathered and Dad, Mum and Sam at the machine",
			function()
				expect(walk.world.lighting).toBe("ordinary")
				expect(walk.world.props).toEqual({ Machine = "advancing", Villagers = "gathered" })
				expect(walk.world.characters.Dad).toBe("DadAtMachine")
				expect(walk.world.characters.Mum).toBe("MumAtMachine")
				expect(walk.world.characters.Sam).toBe("SamAtMachine")
			end
		)

		it("goes on to chapter4", function()
			expect(walk.next).toBe("ChapterStarted(chapter4)")
		end)
	end)
end
