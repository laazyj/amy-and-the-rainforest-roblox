-- WorldState: the World as data, what each command does to it, and the
-- commands that rebuild it.

local WorldState = require("../../../src/core/WorldState")
local Walker = require("./walker")
local fixture = require("./fixtureStory")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("WorldState.initial", function()
		it("has every Character but the Player Character at home, every Prop in its first state", function()
			local state = WorldState.initial(fixture)
			expect(state.characters).toEqual({ Guide = "GuideHome" })
			expect(state.props).toEqual({ Door = "shut" })
			expect(state.lighting).toBe("day")
			expect(state.pickups).toEqual({})
			expect(state.talk).toEqual({})
			expect(state.objective).toBeNil()
			expect(state.player).toBeNil()
		end)
	end)

	describe("WorldState.apply", function()
		local state = WorldState.initial(fixture)
		for _, command in
			{
				{ kind = "MoveCharacter", character = "Guide", spot = "Field" },
				{ kind = "TeleportPlayer", spot = "HeroHome" },
				{ kind = "SetPropState", prop = "Door", state = "open" },
				{ kind = "SetLighting", preset = "dusk" },
				{ kind = "SetObjective", text = "Pick flowers" },
				{ kind = "OfferTalk", character = "Guide", label = "Wave" },
				{ kind = "SpawnPickups", quest = "chapter2.pick" },
				{ kind = "RemovePickup", pickup = "FlowerB" },
				{ kind = "ShowDialogue", lines = { { speaker = "Narrator", text = "x" } } },
				{ kind = "ShowChapterCard", title = "a", subtitle = "b", ending = false },
				{ kind = "Wait", seconds = 1 },
			} :: { any }
		do
			WorldState.apply(fixture, state, command)
		end

		it("moves Characters, the Player Character, Props and Lighting", function()
			expect(state.characters.Guide).toBe("Field")
			expect(state.player).toBe("HeroHome")
			expect(state.props.Door).toBe("open")
			expect(state.lighting).toBe("dusk")
		end)

		it("keeps the Objective and the offered talk affordances", function()
			expect(state.objective).toBe("Pick flowers")
			expect(state.talk).toEqual({ Guide = "Wave" })
		end)

		it("spawns a Quest's Pickups and removes the touched ones", function()
			expect(state.pickups).toEqual({ ["chapter2.pick"] = { FlowerA = true, FlowerC = true } })
		end)

		it("withdraws a talk affordance and clears a Quest's Pickups", function()
			WorldState.apply(fixture, state, { kind = "WithdrawTalk", character = "Guide" })
			WorldState.apply(fixture, state, { kind = "ClearPickups", quest = "chapter2.pick" })
			expect(state.talk).toEqual({})
			expect(state.pickups).toEqual({})
		end)
	end)

	describe("WorldState.commands", function()
		it("rebuilds a state from the initial World, all but the Player Character's position", function()
			local state = WorldState.initial(fixture)
			for _, command in
				{
					{ kind = "MoveCharacter", character = "Guide", spot = "Field" },
					{ kind = "TeleportPlayer", spot = "HeroHome" },
					{ kind = "SetLighting", preset = "dusk" },
					{ kind = "SpawnPickups", quest = "chapter2.pick" },
					{ kind = "RemovePickup", pickup = "FlowerA" },
					{ kind = "SetObjective", text = "Pick flowers  (1/2)" },
					{ kind = "OfferTalk", character = "Guide", label = "Wave" },
				} :: { any }
			do
				WorldState.apply(fixture, state, command)
			end
			expect(Walker.rebuild(fixture, WorldState.commands(fixture, state))).toEqual(Walker.withoutPlayer(state))
		end)

		it("lists Characters, Props, Lighting, Pickups, the Objective and talk in that order", function()
			expect(Walker.kinds(WorldState.commands(fixture, WorldState.initial(fixture)))).toEqual({
				"MoveCharacter",
				"SetPropState",
				"SetLighting",
				"SetObjective",
			})
		end)
	end)
end
