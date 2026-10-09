--[[
	The content's invariants, which the core trusts (a broken one is a stuck
	or crashing Story), and its agreement with the glossary's enumerations:
	Quest Kinds, Characters, Zones, Scenes, Props and Lighting presets.
]]

local Story = require("../../../src/content/Story")
local StoryTypes = require("../../../src/core/Story")
local glossary = require("./glossary")

local story = Story.story
local QUEST_KINDS = glossary.names("Quest kinds")

local function isText(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local speakers: { [string]: boolean } = { Narrator = true }
local inWorld: { [string]: boolean } = {}
for _, character in story.characters do
	speakers[character.id] = true
	inWorld[character.id] = not character.player
end

local reached: { [string]: { string } } = {}
for _, placed in StoryTypes.quests(story) do
	local zone = placed.quest.zone
	if zone then
		reached[zone] = reached[zone] or {}
		table.insert(reached[zone], placed.quest.id)
	end
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	local function expectLines(lines: { any })
		expect(#lines > 0).toBe(true)
		for i, line in lines do
			if not speakers[line.speaker] or not isText(line.text) then
				error(`Line {i} needs a known Speaker and text, got {line.speaker} / {line.text}`)
			end
			if line.canon ~= nil and line.canon ~= true then
				error(`Line {i}: canon is true or absent, got {line.canon}`)
			end
		end
	end

	describe("the Story", function()
		it("gives every Chapter and every Quest a unique id", function()
			local seen = {}
			for _, chapter in story.chapters do
				expect(seen[chapter.id]).toBeNil()
				seen[chapter.id] = true
				for _, quest in chapter.quests do
					expect(seen[quest.id]).toBeNil()
					seen[quest.id] = true
				end
			end
		end)

		it("gives every Ending Line a Speaker and text, and the end card a title and subtitle", function()
			expectLines(story.ending.lines)
			expect(isText(story.ending.title) and isText(story.ending.subtitle)).toBe(true)
		end)

		it("starts in a Lighting preset it has", function()
			expect(story.lighting[story.initialLighting]).never.toBeNil()
		end)

		it("places the machine and the villagers at Spots that exist", function()
			local machine, villagers = story.props.Machine :: any, story.props.Villagers :: any
			expect(story.spots[machine.spot]).never.toBeNil()
			for _, spot in villagers.spots do
				expect(story.spots[spot]).never.toBeNil()
			end
			expect(#villagers.shirts).toBe(#villagers.spots)
		end)

		for _, character in story.characters do
			it(`puts character:{character.id} at a home Spot that exists`, function()
				expect(story.spots[character.home]).never.toBeNil()
			end)
		end
	end)

	for _, chapter in story.chapters do
		describe(chapter.id, function()
			it("reads chapter<n> and has a card title and subtitle", function()
				expect(string.match(chapter.id, "^chapter%d+$")).never.toBeNil()
				expect(isText(chapter.title) and isText(chapter.subtitle)).toBe(true)
			end)

			it("has at least one Quest", function()
				expect(#chapter.quests > 0).toBe(true)
			end)

			for _, quest in chapter.quests do
				describe(quest.id, function()
					it(`reads {chapter.id}.<snake_case>`, function()
						expect(string.match(quest.id, `^{chapter.id}%.[a-z0-9_]+$`)).never.toBeNil()
					end)

					it("has a Kind in the glossary and an Objective", function()
						expect(QUEST_KINDS[quest.kind]).toBe(true)
						expect(isText(quest.objective)).toBe(true)
					end)

					if quest.kind == "talk" then
						it("talks to a Character in the world, and has a dialogue", function()
							expect(inWorld[quest.character or ""]).toBe(true)
							expectLines(quest.dialogue or {})
						end)
					elseif quest.kind == "reach" then
						it("names a Zone that exists", function()
							expect(story.zones[quest.zone or ""]).never.toBeNil()
						end)
					elseif quest.kind == "collect" then
						it("spawns at least `count` Pickups at Spots that exist", function()
							expect(#(quest.pickups or {}) >= (quest.count or 1)).toBe(true)
							for _, pickup in (quest.pickups or {}) :: { string } do
								expect(story.spots[pickup]).never.toBeNil()
							end
						end)
					end

					if quest.kind ~= "talk" then
						it("has no `dialogue` (only talk Quests do)", function()
							expect(quest.dialogue).toBeNil()
						end)
					end

					for _, field in { "intro", "dialogue", "outro" } do
						local lines = (quest :: any)[field]
						if lines ~= nil then
							it(`gives every {field} Line a known Speaker and text`, function()
								expectLines(lines)
							end)
						end
					end
				end)
			end
		end)
	end

	describe("against the glossary", function()
		it("has the glossary's Characters, with their kinds, display names and home Spots", function()
			local listed = {}
			for _, entry in glossary.entries("Characters and Speakers") do
				if entry.id ~= entry.name then
					local cells = entry.cells
					listed[entry.name] = `{glossary.values(cells.Kind)[1]}/{cells["Display name"]}/{glossary.values(
						cells["Home Spot"]
					)[1]}`
				end
			end
			local ours = {}
			for _, character in story.characters do
				ours[character.id] = `{character.kind}/{character.display}/spot:{character.home}`
			end
			expect(ours).toEqual(listed)
		end)

		it("has the glossary's Scenes, one file each", function()
			local ids = {}
			for _, scene in Story.scenes do
				ids[scene.id] = true
			end
			expect(ids).toEqual(glossary.names("Scenes"))
		end)

		-- Id -> its Scene, for the Spots or Zones of every Scene.
		local function sceneOf(field: string): { [string]: string }
			local scenes = {}
			for _, scene in Story.scenes do
				for id in (scene :: any)[field] do
					scenes[id] = `scene:{scene.id}`
				end
			end
			return scenes
		end

		it("has the glossary's Spots, each in its Scene", function()
			local listed = {}
			for _, entry in glossary.entries("Spots") do
				listed[entry.name] = glossary.values(entry.cells.Scene)[1]
			end
			expect(sceneOf("spots")).toEqual(listed)
		end)

		it("has the glossary's Zones, each in its Scene and used by the Quests listed", function()
			local listed = {}
			for _, entry in glossary.entries("Zones") do
				listed[entry.name] = {
					scene = glossary.values(entry.cells.Scene)[1],
					quests = glossary.values(entry.cells["Used by"]),
				}
			end
			local ours = {}
			for id, scene in sceneOf("zones") do
				ours[id] = { scene = scene, quests = reached[id] or {} }
			end
			expect(ours).toEqual(listed)
		end)

		it("has the glossary's Props, with their states in order", function()
			local listed = {}
			for _, entry in glossary.entries("Props") do
				listed[entry.name] = glossary.values(entry.cells["States, in order"])
			end
			local ours = {}
			for id, prop in story.props do
				ours[id] = prop.states
			end
			expect(ours).toEqual(listed)
		end)

		it("has the glossary's Lighting presets", function()
			local ids = {}
			for id in story.lighting do
				ids[id] = true
			end
			expect(ids).toEqual(glossary.names("Lighting presets"))
		end)
	end)
end
