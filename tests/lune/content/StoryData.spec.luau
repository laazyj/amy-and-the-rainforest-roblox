--[[
	Invariants of the story data in src/ReplicatedStorage/StoryData.lua.
	StoryServer trusts these; a broken one means a stuck or crashing story.
]]

local bootstrap = require("../bootstrap")

local StoryData = bootstrap.loadSource("src/ReplicatedStorage/StoryData.lua")

local QUEST_TYPES = { talk = true, reach = true, collect = true }

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function idSet(list: { any }, key: string): { [string]: boolean }
	local set = {}
	for _, item in list do
		set[item[key]] = true
	end
	return set
end

local npcIds = idSet(StoryData.NPCs, "id")
local zoneNames = idSet(StoryData.Zones, "name")

local reachedZones = {}
for _, chapter in StoryData.Chapters do
	for _, quest in chapter.quests do
		if quest.type == "reach" then
			reachedZones[quest.zone] = true
		end
	end
end

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	local function expectUnique(list: { any }, key: string)
		local seen = {}
		for i, item in list do
			local value = item[key]
			if not isNonEmptyString(value) then
				error(`entry {i} has no {key}`)
			elseif seen[value] then
				error(`duplicate {key} "{value}"`)
			end
			seen[value] = true
		end
	end

	local function expectLines(lines: any)
		expect(lines).toBeA("table")
		expect(#lines > 0).toBe(true)
		for i, line in lines do
			if not isNonEmptyString(line.speaker) or not isNonEmptyString(line.text) then
				error(`line {i} needs a speaker and text, got {line.speaker} / {line.text}`)
			end
		end
	end

	describe("StoryData", function()
		it("has at least one chapter", function()
			expect(#StoryData.Chapters > 0).toBe(true)
		end)

		it("gives every chapter a unique id", function()
			expectUnique(StoryData.Chapters, "id")
		end)

		it("gives every quest a unique id across the whole story", function()
			local allQuests = {}
			for _, chapter in StoryData.Chapters do
				table.move(chapter.quests, 1, #chapter.quests, #allQuests + 1, allQuests)
			end
			expectUnique(allQuests, "id")
		end)

		it("gives every character a unique id", function()
			expectUnique(StoryData.NPCs, "id")
		end)

		it("gives every zone a unique name", function()
			expectUnique(StoryData.Zones, "name")
		end)

		for _, zone in StoryData.Zones do
			it(`uses zone {zone.name} in at least one reach quest`, function()
				expect(reachedZones[zone.name]).toBe(true)
			end)
		end

		it("gives every ending line a speaker and text", function()
			expectLines(StoryData.Ending.lines)
		end)
	end)

	for _, chapter in StoryData.Chapters do
		describe(chapter.id, function()
			it("has at least one quest", function()
				expect(chapter.quests).toBeA("table")
				expect(#chapter.quests > 0).toBe(true)
			end)

			for _, quest in chapter.quests do
				describe(quest.id, function()
					it("has a known type", function()
						expect(QUEST_TYPES[quest.type]).toBe(true)
					end)

					it("has an objective", function()
						expect(isNonEmptyString(quest.objective)).toBe(true)
					end)

					if quest.type == "talk" then
						it("names a character that exists", function()
							expect(npcIds[quest.npc]).toBe(true)
						end)

						it("gives every dialogue line a speaker and text", function()
							expectLines(quest.dialogue)
						end)
					elseif quest.type == "reach" then
						it("names a zone that exists", function()
							expect(zoneNames[quest.zone]).toBe(true)
						end)
					elseif quest.type == "collect" then
						it("has enough spawn points for its count", function()
							expect(quest.count).toBeA("number")
							expect(quest.count >= 1).toBe(true)
							expect(quest.spawnPoints).toBeA("table")
							expect(#quest.spawnPoints >= quest.count).toBe(true)
							for _, point in quest.spawnPoints do
								expect(point).toBeA("Vector3")
							end
						end)
					end

					for _, field in { "intro", "onComplete" } do
						if quest[field] ~= nil then
							it(`gives every {field} line a speaker and text`, function()
								expectLines(quest[field])
							end)
						end
					end
				end)
			end
		end)
	end
end
