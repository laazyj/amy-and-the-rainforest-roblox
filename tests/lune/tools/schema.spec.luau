--[[
	The content schema (tools/lib/schema.luau), run by `tools/guard schema`
	in tier 0: its enumerations come from docs/GLOSSARY.md's text, so a name
	the glossary does not list, or lists as *later*, fails; positions and
	colours are plain tables.
]]

local Glossary = require("../../../tools/lib/glossary")
local Schema = require("../../../tools/lib/schema")
local Walker = require("../core/walker")
local bootstrap = require("../bootstrap")

local GLOSSARY = bootstrap.readSource("docs/GLOSSARY.md")
local schema = Schema.fromGlossary(GLOSSARY)
local copy = Walker.deepCopy

-- Every content file, loaded as the guard loads it: path under src/content -> value.
local content: { [string]: any } = {}
for _, file in Schema.content() do
	content[file.path] = file.value
end

-- The glossary with the row whose first cell starts with `id` removed.
local function without(id: string): string
	local text, count = string.gsub(GLOSSARY, `\n| ` .. "`" .. id .. "`[^\n]*", "", 1)
	assert(count == 1, `no row {id}`)
	return text
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("the glossary parser", function()
		local glossary = Glossary.parse(GLOSSARY)

		it("reads a table's rows by their first backticked cell, with every cell by its header", function()
			local machine = glossary.entries("Props")[1]
			expect(machine.id).toBe("prop:Machine")
			expect(machine.name).toBe("Machine")
			expect(glossary.values(machine.cells["States, in order"])).toEqual({
				"absent",
				"advancing",
				"stopped",
				"retreating",
			})
		end)

		it("flags *later* rows, and leaves them out of names", function()
			local kinds = {}
			for _, entry in glossary.entries("Quest kinds") do
				kinds[entry.name] = entry.later
			end
			expect(kinds).toEqual({
				talk = false,
				reach = false,
				collect = false,
				follow = true,
				place = true,
				solve = true,
			})
			expect(glossary.names("Quest kinds")).toEqual({ talk = true, reach = true, collect = true })
		end)

		it("reads an enumeration with no table as empty", function()
			expect(glossary.entries("Cues")).toEqual({})
		end)

		it("raises on a heading the glossary does not have", function()
			t.expectError(function()
				glossary.entries("Gizmos")
			end, 'no "Gizmos" section')
		end)
	end)

	describe("the schema's enumerations", function()
		it("are the glossary's Quest kinds, Speakers, Hook names, Beats, Scenes and Lighting presets", function()
			expect(schema.questKinds).toEqual({ talk = true, reach = true, collect = true })
			expect(schema.speakers.Narrator).toBe(true)
			expect(schema.characters.Narrator).toBeNil()
			expect(schema.characters.Sam).toEqual({ kind = "dog", display = "Sam the Dog", home = "SamHome" })
			expect(schema.hooks).toEqual({ onStart = true, onComplete = true })
			expect(schema.beats.sam_catches).toBe(true)
			expect(schema.scenes.HeartGlade).toBe(true)
			expect(schema.lighting).toEqual({ ordinary = true, paradise = true })
		end)

		it("give each Spot and Zone its Scene, and each Prop its states", function()
			expect(schema.spots.Farm).toBe("Village")
			expect(schema.zones.ForestGap).toBe("ForestWall")
			expect(schema.props.Villagers).toEqual({ "absent", "gathered", "cheering" })
		end)

		it("give each World command in use its arguments", function()
			expect(schema.commands.MoveCharacter).toEqual({ character = true, spot = true })
			expect(schema.commands.SetObjective).toEqual({ text = true })
			expect(schema.commands.PlayCue).toBeNil()
			expect(schema.commands.FrameShot).toBeNil()
		end)

		it("have Shots and no Cues yet", function()
			expect(schema.shots.ForestWallReveal).toBe(true)
			expect(schema.cues).toEqual({})
		end)
	end)

	describe("the content", function()
		for _, file in Schema.content() do
			it(`src/content/{file.path} loads and holds to the schema`, function()
				expect(file.ok).toBe(true)
				expect(Schema.check(schema, file.path, file.value)).toEqual({})
			end)
		end
	end)

	describe("a term in content but not in the glossary", function()
		it("fails: chapter2's Zone ForestGap, once the glossary loses zone:ForestGap", function()
			local trimmed = Schema.fromGlossary(without("zone:ForestGap"))
			expect(Schema.check(trimmed, "chapters/2/data.luau", content["chapters/2/data.luau"])).toEqual({
				'src/content/chapters/2/data.luau: quests[2].zone "ForestGap" is not a Zone in docs/GLOSSARY.md',
			})
		end)

		it("fails: a new Zone in a Scene", function()
			local paradise = copy(content["scenes/Paradise.luau"])
			paradise.zones.FireflyPool = { centre = { x = 0, y = 5, z = 230 }, size = { x = 10, y = 10, z = 10 } }
			expect(Schema.check(schema, "scenes/Paradise.luau", paradise)).toEqual({
				'src/content/scenes/Paradise.luau: zones.FireflyPool "FireflyPool" is not a Zone in docs/GLOSSARY.md',
			})
		end)

		it("fails: a Zone or Spot declared in another Scene than the glossary's", function()
			local garden = copy(content["scenes/Garden.luau"])
			garden.spots.Farm = garden.spots.AmySpawn
			expect(Schema.check(schema, "scenes/Garden.luau", garden)).toEqual({
				"src/content/scenes/Garden.luau: spots.Farm Spot Farm is in scene:Village in docs/GLOSSARY.md, not scene:Garden",
			})
		end)

		it("fails: a *later* Quest kind, an unknown Speaker, Hook name and Beat", function()
			local chapter = copy(content["chapters/1/data.luau"])
			chapter.quests[2].kind = "follow"
			chapter.quests[2].outro[1].speaker = "Squirel"
			chapter.quests[3].hooks = { onArrive = { "sam_waves" } }
			expect(Schema.check(schema, "chapters/1/data.luau", chapter)).toEqual({
				'src/content/chapters/1/data.luau: quests[2].kind "follow" is not a Quest kind in docs/GLOSSARY.md',
				'src/content/chapters/1/data.luau: quests[2].outro[1].speaker "Squirel" is not a Speaker in docs/GLOSSARY.md',
				'src/content/chapters/1/data.luau: quests[3].hooks.onArrive "onArrive" is not a Hook name in docs/GLOSSARY.md',
				'src/content/chapters/1/data.luau: quests[3].hooks.onArrive[1] "sam_waves" is not a Beat in docs/GLOSSARY.md',
			})
		end)

		it("fails: a *later* World command, a Prop state and a Character the glossary does not have", function()
			local machineStops: { any } = {
				{ kind = "SetPropState", prop = "Machine", state = "exploded" },
				{ kind = "PlayCue", cue = "machine_stop" },
				{ kind = "MoveCharacter", character = "Owl", spot = "Farm" },
			}
			local beats = { machine_stops = machineStops }
			expect(Schema.check(schema, "chapters/4/hooks.luau", beats)).toEqual({
				'src/content/chapters/4/hooks.luau: machine_stops[1].state "exploded" is not a state of prop:Machine in docs/GLOSSARY.md',
				'src/content/chapters/4/hooks.luau: machine_stops[2].kind "PlayCue" is not a World command in docs/GLOSSARY.md',
				'src/content/chapters/4/hooks.luau: machine_stops[3].character "Owl" is not a Character in docs/GLOSSARY.md',
			})
		end)

		it("fails: a Character whose kind, display name or home Spot differs from the glossary's", function()
			local characters = copy(content["characters.luau"])
			characters[4].display = "Sam"
			expect(Schema.check(schema, "characters.luau", characters)).toEqual({
				'src/content/characters.luau: [4].display character:Sam has display "Sam the Dog" in docs/GLOSSARY.md, not "Sam"',
			})
		end)

		it("fails: a field the schema does not know, and a file with no role", function()
			local chapter = copy(content["chapters/3/data.luau"])
			chapter.quests[1].music = "paradise_theme"
			expect(Schema.check(schema, "chapters/3/data.luau", chapter)).toEqual({
				"src/content/chapters/3/data.luau: quests[1].music is not a field the content schema knows",
			})
			expect(Schema.check(schema, "collectibles.luau", {})).toEqual({
				"src/content/collectibles.luau: the file has no shape in the content schema; give it a role in tools/lib/schema.luau",
			})
		end)
	end)

	describe("positions and colours", function()
		it("fail as anything but plain tables", function()
			local field = copy(content["scenes/Field.luau"])
			field.spots.MachineBay.at = { x = 0, y = 0 }
			field.birds[1].at = vector.create(1, 2, 3)
			field.flowers.colours[1] = { r = 255, g = 300, b = 0 }
			expect(Schema.check(schema, "scenes/Field.luau", field)).toEqual({
				"src/content/scenes/Field.luau: birds[1].at is a vector; positions and colours are plain tables ({x, y, z}, {r, g, b})",
				"src/content/scenes/Field.luau: flowers.colours[1].g must be a colour channel, 0 to 255, got 300",
				"src/content/scenes/Field.luau: spots.MachineBay.at.z must be a number, got nil",
			})
		end)
	end)
end
