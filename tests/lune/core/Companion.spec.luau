--[[
	Companion: the state machine a Companion goes about with Amy by (plan
	section 2.3): idle, follow, react, lead, and where each sends it.
]]

local Companion = require("../../../src/core/Companion")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	local function near(toAmy: number, toSpot: number?): Companion.Sense
		return { toAmy = toAmy, toSpot = toSpot }
	end

	describe("an idle Companion", function()
		it("stands where it is when it is not following", function()
			local sam = Companion.new()
			expect(Companion.step(sam, 0.1, near(40)).kind).toBe("stay")
			expect(sam.state).toBe("idle")
		end)

		it("stands while Amy is within FOLLOW_FROM, following or not", function()
			local sam = Companion.new(true)
			expect(Companion.step(sam, 0.1, near(Companion.FOLLOW_FROM)).kind).toBe("stay")
			expect(sam.state).toBe("idle")
		end)

		it("sets off after Amy once she is further than FOLLOW_FROM", function()
			local sam = Companion.new(true)
			expect(Companion.step(sam, 0.1, near(Companion.FOLLOW_FROM + 1))).toEqual({ kind = "toAmy", gait = "walk" })
			expect(sam.state).toBe("follow")
		end)
	end)

	describe("a following Companion", function()
		it("walks to Amy, and runs while she is further than RUN_FROM", function()
			local sam = Companion.new(true)
			expect(Companion.step(sam, 0.1, near(Companion.RUN_FROM + 1))).toEqual({ kind = "toAmy", gait = "run" })
			expect(Companion.step(sam, 0.1, near(Companion.RUN_FROM))).toEqual({ kind = "toAmy", gait = "walk" })
		end)

		it("keeps following between STOP_AT and FOLLOW_FROM, so it does not stop and start", function()
			local sam = Companion.new(true)
			Companion.step(sam, 0.1, near(Companion.FOLLOW_FROM + 1))
			expect(Companion.step(sam, 0.1, near(Companion.STOP_AT + 1)).kind).toBe("toAmy")
			expect(sam.state).toBe("follow")
		end)

		it("stands again within STOP_AT of Amy", function()
			local sam = Companion.new(true)
			Companion.step(sam, 0.1, near(Companion.FOLLOW_FROM + 1))
			expect(Companion.step(sam, 0.1, near(Companion.STOP_AT)).kind).toBe("stay")
			expect(sam.state).toBe("idle")
		end)

		it("stands where it is when told to stop following", function()
			local sam = Companion.new(true)
			Companion.step(sam, 0.1, near(30))
			Companion.follow(sam, false)
			expect(sam.state).toBe("idle")
			expect(Companion.step(sam, 0.1, near(30)).kind).toBe("stay")
		end)
	end)

	describe("a reacting Companion", function()
		it("stands for the reaction's seconds, then goes back to following", function()
			local sam = Companion.new(true)
			Companion.step(sam, 0.1, near(30))
			Companion.react(sam, 1)
			expect(Companion.step(sam, 0.6, near(30)).kind).toBe("stay")
			expect(sam.state).toBe("react")
			expect(Companion.step(sam, 0.6, near(30))).toEqual({ kind = "toAmy", gait = "run" })
			expect(sam.state).toBe("follow")
		end)

		it("goes back to what it did before a second reaction, not to reacting", function()
			local sam = Companion.new()
			Companion.react(sam, 1)
			Companion.react(sam, 1)
			Companion.step(sam, 2, near(3))
			expect(sam.state).toBe("idle")
		end)

		it("does not go back to following if told to stop while reacting", function()
			local sam = Companion.new(true)
			Companion.step(sam, 0.1, near(30))
			Companion.react(sam, 1)
			Companion.follow(sam, false)
			expect(Companion.step(sam, 2, near(30)).kind).toBe("stay")
			expect(sam.state).toBe("idle")
		end)
	end)

	describe("a leading Companion", function()
		it("walks to its Spot while Amy keeps up", function()
			local fox = Companion.new()
			Companion.lead(fox, "FireflyPool")
			expect(Companion.step(fox, 0.1, near(6, 20))).toEqual({
				kind = "toSpot",
				spot = "FireflyPool",
				gait = "walk",
			})
		end)

		it("waits while Amy is further behind than WAIT_FOR", function()
			local fox = Companion.new()
			Companion.lead(fox, "FireflyPool")
			expect(Companion.step(fox, 0.1, near(Companion.WAIT_FOR + 1, 20)).kind).toBe("stay")
			expect(fox.state).toBe("lead")
		end)

		it("stands once within ARRIVE_AT of its Spot, and leads no more", function()
			local fox = Companion.new()
			Companion.lead(fox, "FireflyPool")
			expect(Companion.step(fox, 0.1, near(6, Companion.ARRIVE_AT)).kind).toBe("stay")
			expect(fox.state).toBe("idle")
			expect(fox.spot).toBeNil()
		end)

		it("follows Amy again after arriving, when it was following", function()
			local fox = Companion.new(true)
			Companion.lead(fox, "FireflyPool")
			expect(Companion.step(fox, 0.1, near(Companion.FOLLOW_FROM + 1, 1)).kind).toBe("toAmy")
			expect(fox.state).toBe("follow")
		end)

		it("goes back to leading after a reaction", function()
			local fox = Companion.new()
			Companion.lead(fox, "FireflyPool")
			Companion.react(fox, 0.5)
			expect(Companion.step(fox, 1, near(6, 20)).kind).toBe("toSpot")
		end)
	end)
end
