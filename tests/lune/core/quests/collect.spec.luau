-- Quest Kind collect: TouchedPickup for `count` of the Quest's Pickups.

local collect = require("../../../../src/core/quests/collect")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect
	local quest: any = {
		id = "chapter9.pick",
		kind = "collect",
		count = 2,
		pickups = { "FlowerA", "FlowerB", "FlowerC" },
		objective = "Pick flowers",
	}

	describe("collect", function()
		it("spawns the Quest's Pickups", function()
			expect(collect.begin(quest, {})).toEqual({ { kind = "SpawnPickups", quest = "chapter9.pick" } })
		end)

		it("removes the Pickups already touched when it begins again on a Resume", function()
			expect(collect.begin(quest, { "FlowerB" })).toEqual({
				{ kind = "SpawnPickups", quest = "chapter9.pick" },
				{ kind = "RemovePickup", pickup = "FlowerB" },
			} :: { any })
		end)

		it("counts the Pickups in its Objective", function()
			expect(collect.objective(quest, {})).toBe("Pick flowers  (0/2)")
			expect(collect.objective(quest, { "FlowerC" })).toBe("Pick flowers  (1/2)")
		end)

		it("removes a touched Pickup and updates the Objective, not yet done", function()
			expect(collect.handle(quest, {}, { kind = "TouchedPickup", pickup = "FlowerB" })).toEqual({
				commands = {
					{ kind = "RemovePickup", pickup = "FlowerB" },
					{ kind = "SetObjective", text = "Pick flowers  (1/2)" },
				} :: { any },
				collected = { "FlowerB" },
				done = false,
			})
		end)

		it("is done at the count", function()
			local outcome = collect.handle(quest, { "FlowerB" }, { kind = "TouchedPickup", pickup = "FlowerA" })
			expect(outcome and outcome.done).toBe(true)
			expect(outcome and outcome.collected).toEqual({ "FlowerB", "FlowerA" })
		end)

		it("does not change the list it is given", function()
			local collected = { "FlowerB" }
			collect.handle(quest, collected, { kind = "TouchedPickup", pickup = "FlowerA" })
			expect(collected).toEqual({ "FlowerB" })
		end)

		it("ignores a Pickup already touched, another Quest's Pickup and other events", function()
			expect(collect.handle(quest, { "FlowerB" }, { kind = "TouchedPickup", pickup = "FlowerB" })).toBeNil()
			expect(collect.handle(quest, {}, { kind = "TouchedPickup", pickup = "Acorn" })).toBeNil()
			expect(collect.handle(quest, {}, { kind = "EnteredZone", zone = "Field" })).toBeNil()
		end)
	end)
end
