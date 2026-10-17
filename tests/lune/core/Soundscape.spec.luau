-- Soundscape: the Scene's music and ambience, the theme under a screen or
-- card, and footsteps, as plain data.

local Soundscape = require("../../../src/core/Soundscape")
local Story = require("../../../src/core/Story")

local function scene(id: string, centre: number, size: number): Story.Scene
	return {
		id = id,
		spots = {},
		zones = {},
		props = {},
		music = `music:{string.lower(id)}`,
		ambience = `cue:ambience_{string.lower(id)}`,
		bounds = { centre = { x = 0, y = 0, z = centre }, size = { x = size, y = size, z = size } },
	}
end

-- A meadow with a glade inside it, and a lake beyond.
local meadow, glade, lake = scene("Meadow", 0, 100), scene("Glade", 10, 20), scene("Lake", 200, 50)
local scenes = { meadow, glade, lake }

local function at(z: number): Story.Vec3
	return { x = 0, y = 0, z = z }
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("Soundscape.sceneAt", function()
		it("finds the Scene whose bounds hold a place", function()
			expect(Soundscape.sceneAt(scenes, at(-40))).toBe(meadow)
			expect(Soundscape.sceneAt(scenes, at(210))).toBe(lake)
		end)

		it("picks the smallest bounds where Scenes overlap, so a Scene inside another has its own sound", function()
			expect(Soundscape.sceneAt(scenes, at(12))).toBe(glade)
			expect(Soundscape.sceneAt({ glade, meadow }, at(12))).toBe(glade)
		end)

		it("finds none outside every Scene's bounds", function()
			expect(Soundscape.sceneAt(scenes, at(120))).toBeNil()
			expect(Soundscape.sceneAt(scenes, { x = 0, y = 60, z = -40 })).toBeNil()
		end)
	end)

	describe("Soundscape.view", function()
		it("plays nothing before Amy is in a Scene", function()
			expect(Soundscape.view(Soundscape.new())).toEqual({})
		end)

		it("plays the music and ambience of the Scene Amy is in, and keeps them between Scenes", function()
			local soundscape = Soundscape.new()
			Soundscape.moved(soundscape, scenes, at(-40))
			expect(Soundscape.view(soundscape)).toEqual({ music = "music:meadow", ambience = "cue:ambience_meadow" })
			Soundscape.moved(soundscape, scenes, at(12))
			expect(Soundscape.view(soundscape)).toEqual({ music = "music:glade", ambience = "cue:ambience_glade" })
			Soundscape.moved(soundscape, scenes, at(120))
			expect(Soundscape.view(soundscape).music).toBe("music:glade")
		end)

		it(
			"plays the theme over the Scene's ambience while a screen or card shows, and the Scene's music after",
			function()
				local soundscape = Soundscape.new()
				Soundscape.screen(soundscape, true)
				expect(Soundscape.view(soundscape)).toEqual({ music = "music:theme" })
				Soundscape.moved(soundscape, scenes, at(210))
				expect(Soundscape.view(soundscape)).toEqual({ music = "music:theme", ambience = "cue:ambience_lake" })
				Soundscape.screen(soundscape, false)
				expect(Soundscape.view(soundscape).music).toBe("music:lake")
			end
		)
	end)

	describe("Soundscape.step", function()
		it("sounds a footstep at once when Amy starts walking, then every STEP_SECONDS", function()
			local soundscape = Soundscape.new()
			local step = Soundscape.STEP_SECONDS
			expect(Soundscape.step(soundscape, 1 / 60, true)).toBe(true)
			local steps = 0
			for _ = 1, 3 * 60 do
				if Soundscape.step(soundscape, 1 / 60, true) then
					steps += 1
				end
			end
			expect(steps).toBe(math.floor(3 / step))
		end)

		it("sounds none while Amy stands, and starts afresh when she walks again", function()
			local soundscape = Soundscape.new()
			Soundscape.step(soundscape, 1 / 60, true)
			expect(Soundscape.step(soundscape, 5, false)).toBe(false)
			expect(Soundscape.step(soundscape, 1 / 60, true)).toBe(true)
		end)
	end)

	describe("the levels", function()
		it("keep music and ambience under the effects, and narration loudest", function()
			expect(Soundscape.MUSIC_VOLUME < Soundscape.EFFECT_VOLUME).toBe(true)
			expect(Soundscape.AMBIENCE_VOLUME < Soundscape.EFFECT_VOLUME).toBe(true)
			expect(Soundscape.NARRATION_VOLUME >= Soundscape.EFFECT_VOLUME).toBe(true)
			expect(Soundscape.CROSSFADE_SECONDS > 0).toBe(true)
		end)
	end)
end
