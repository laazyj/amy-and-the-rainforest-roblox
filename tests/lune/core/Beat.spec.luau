-- Beat: playing a Hook's Beats emits BeatPlayed and their commands in order.

local Beat = require("../../../src/core/Beat")
local fixture = require("./fixtureStory")

return function(t: any)
	local describe, it, expect, expectError = t.describe, t.it, t.expect, t.expectError
	local chapter = fixture.chapters[1]

	describe("Beat.play", function()
		it("plays beat guide_leaves: its commands in order, Waits included", function()
			local events, commands: { any } = {}, {}
			Beat.play(chapter, { "guide_leaves" }, events, commands)
			expect(events).toEqual({ { kind = "BeatPlayed", beat = "guide_leaves" } })
			expect(commands).toEqual(chapter.beats.guide_leaves)
		end)

		it("plays several Beats one after the other, after what is already there", function()
			local events, commands: { any } = {}, { { kind = "Wait", seconds = 1 } }
			Beat.play(chapter, { "door_opens", "dusk_falls" }, events, commands)
			expect(#events).toBe(2)
			expect(commands).toEqual({
				{ kind = "Wait", seconds = 1 },
				{ kind = "SetPropState", prop = "Door", state = "open" },
				{ kind = "SetLighting", preset = "dusk" },
			} :: { any })
		end)

		it("plays nothing for a Hook with no Beats", function()
			local events, commands = {}, {}
			Beat.play(chapter, nil, events, commands)
			expect(#events + #commands).toBe(0)
		end)

		it("rejects a Beat the Chapter does not have", function()
			expectError(function()
				Beat.play(chapter, { "fireworks" }, {}, {})
			end, "chapter1 has no Beat fireworks")
		end)
	end)
end
