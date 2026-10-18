--[[
	The Story's sound: every Scene names an ambience and a music Cue, and
	every Spot and Zone it declares is inside its own sound; every Cue
	named in content (Scenes, Beats) or by the core (src/core/Cues) is in
	the glossary's Cues and in the manifest, and the manifest has no Cue
	the glossary lacks; the Narration table holds to the canon Lines.
]]

local Cues = require("../../../src/core/Cues")
local Glossary = require("../../../tools/lib/glossary")
local Manifest = require("../../../tools/lib/manifest")
local Narration = require("../../../src/core/Narration")
local Soundscape = require("../../../src/core/Soundscape")
local Story = require("../../../src/content/Story")
local StoryTypes = require("../../../src/core/Story")
local bootstrap = require("../bootstrap")
local glossary = require("./glossary")
local narration = require("../../../src/content/narration")

local story, scenes = Story.story, Story.scenes

local manifest = Manifest.decode(bootstrap.readSource(Manifest.PATH))
local inManifest: { [string]: boolean } = {}
for _, entry in manifest.assets do
	inManifest[entry.name] = true
end
local inGlossary = glossary.names("Cues")

local named = Cues.named(story, scenes)

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("every Scene", function()
		for _, scene in scenes do
			it(`scene:{scene.id} names a music and an ambience Cue, each in the manifest`, function()
				expect(string.match(scene.music, "^music:")).never.toBeNil()
				expect(string.match(scene.ambience, "^cue:")).never.toBeNil()
				expect(inManifest[scene.music]).toBe(true)
				expect(inManifest[scene.ambience]).toBe(true)
			end)

			it(`scene:{scene.id} sounds its own at each of its Spots and Zones`, function()
				local places: { StoryTypes.Vec3 } = {}
				for _, spot in scene.spots do
					table.insert(places, spot.at)
				end
				for _, zone in scene.zones do
					table.insert(places, zone.centre)
				end
				for _, at in places do
					local found = Soundscape.sceneAt(scenes, at)
					expect(found and found.id).toBe(scene.id)
				end
			end)
		end
	end)

	describe("every Cue the game names", function()
		it("is a Cue in docs/GLOSSARY.md and an Asset in the manifest", function()
			local missing = {}
			for cue, where in named do
				if not inGlossary[Glossary.name(cue)] or not inManifest[cue] then
					table.insert(missing, `{cue} ({where})`)
				end
			end
			table.sort(missing)
			expect(missing).toEqual({})
		end)

		it("covers the glossary's Cues, and the manifest has no other", function()
			for name in inGlossary do
				expect(named[`cue:{name}`] or named[`music:{name}`]).never.toBeNil()
			end
			for _, entry in manifest.assets do
				local prefix = string.match(entry.name, "^(%l+):")
				if prefix == "cue" or prefix == "music" then
					expect(named[entry.name]).never.toBeNil()
				end
			end
		end)
	end)

	describe("the Narration table", function()
		it("covers every canon Line of each Chapter it has a file for (none yet: text only)", function()
			expect(Narration.problems(story, narration)).toEqual({})
		end)

		it("names files the manifest has", function()
			for file in narration do
				expect(inManifest[file]).toBe(true)
			end
		end)
	end)
end
