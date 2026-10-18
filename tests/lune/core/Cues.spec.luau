-- Cues: the Cues the core and the client binder name themselves.

local Cues = require("../../../src/core/Cues")
local fixture = require("./fixtureStory")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("Cues", function()
		it("names the theme as music and the rest as sounds, each an Asset name", function()
			expect(Cues.THEME).toBe("music:theme")
			for name, where in Cues.named(fixture, {}) do
				local prefix = if where == "src/core/Cues THEME" then "music" else "cue"
				expect(string.match(name, `^{prefix}:[a-z_]+$`)).toBe(name)
			end
		end)

		it("names every Scene's music and ambience and every Beat's PlayCue, with where", function()
			local scene: any = { id = "Meadow", music = "music:meadow", ambience = "cue:ambience_meadow" }
			local story = table.clone(fixture)
			story.chapters = { table.clone(fixture.chapters[1]) }
			story.chapters[1].beats = { bark = { { kind = "PlayCue", cue = "cue:bark" } } }
			local named = Cues.named(story, { scene })
			expect(named["music:meadow"]).toBe("scene:Meadow music")
			expect(named["cue:ambience_meadow"]).toBe("scene:Meadow ambience")
			expect(named["cue:bark"]).toBe("beat:bark")
			expect(named[Cues.PICKUP]).toBe("src/core/Cues PICKUP")
		end)
	end)
end
