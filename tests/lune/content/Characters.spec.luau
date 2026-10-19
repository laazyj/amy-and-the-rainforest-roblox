--[[
	How each Character is built (glossary: Character, Description, Character
	model, Placeholder): every human has a Description, every other
	Character a Placeholder to be drawn as until its Character model is in
	the place, every Character model in the manifest is a Character's, and
	the place file holds the folder of them. Story.build chooses which, and
	falls back to the Placeholder while there is no Character model.
]]

local Manifest = require("../../../tools/lib/manifest")
local Story = require("../../../src/content/Story")
local StoryTypes = require("../../../src/core/Story")
local bootstrap = require("../bootstrap")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local story = Story.story

local manifest = Manifest.decode(bootstrap.readSource(Manifest.PATH))
local project = serde.decode("json", bootstrap.readSource("default.project.json"))

-- The manifest's entries by Asset name, and its Character models by Character id.
local byName: { [string]: Manifest.Entry } = {}
local characterModels: { [string]: Manifest.Entry } = {}
for _, entry in manifest.assets do
	byName[entry.name] = entry
	local id = string.match(entry.name, "^character:(.+)$")
	if id then
		characterModels[id] = entry
	end
end

-- Every Description in the content: the Characters' and the villagers'.
local descriptions: { [string]: StoryTypes.Description } = {}
for _, character in story.characters do
	if character.description then
		descriptions[`character:{character.id}`] = character.description
	end
end
for k, description in (story.props.Villagers :: any).descriptions do
	descriptions[`prop:Villagers[{k}]`] = description
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("the Characters", function()
		for _, character in story.characters do
			if character.kind == "human" then
				it(`gives character:{character.id}, a human, a Description and no Placeholder`, function()
					expect(character.description).never.toBeNil()
					expect(character.placeholder).toBeNil()
					expect(characterModels[character.id]).toBeNil()
				end)
			else
				it(`gives character:{character.id} a Placeholder until its Character model is in the place`, function()
					expect(character.description).toBeNil()
					expect(character.placeholder ~= nil or characterModels[character.id] ~= nil).toBe(true)
				end)
			end
		end

		it("gives Amy's Description every Catalog slot", function()
			local amy = assert(StoryTypes.character(story, "Amy"))
			local description = assert(amy.description, "Amy has a Description")
			local catalog = assert(description.catalog, "Amy has Catalog slots") :: { [string]: string }
			for slot in StoryTypes.CATALOG_SLOTS do
				expect(catalog[slot]).never.toBeNil()
			end
			for slot in catalog do
				expect(StoryTypes.CATALOG_SLOTS[slot]).never.toBeNil()
			end
		end)

		it("names an avatar accessory type in each Catalog slot, a sweater in the shirt slot", function()
			local types: { [string]: boolean } = {}
			for _, item in roblox.Enum.AccessoryType:GetEnumItems() do
				types[item.Name] = true
			end
			for slot, kind in StoryTypes.CATALOG_SLOTS do
				if not types[kind.accessory] then
					error(`the {slot} slot holds {kind.accessory}, which is no Enum.AccessoryType`)
				end
			end
			-- "Red Sweater" (catalog:amy_shirt) is a SweaterAccessory, and a
			-- slot of another type would not wear it
			expect(StoryTypes.CATALOG_SLOTS.shirt.accessory).toBe("Sweater")
		end)

		for whose, description in descriptions do
			it(`names a Catalog item in the manifest in each of {whose}'s Catalog slots`, function()
				for slot, name in (description.catalog or {}) :: { [string]: string } do
					local entry = byName[name]
					if not entry or entry.kind ~= Manifest.CATALOG then
						error(`{whose}'s {slot} slot names {name}, which is no Catalog item in the manifest`)
					end
				end
			end)
		end

		it("names a Character that is not a human with every Character model in the manifest", function()
			for id in characterModels do
				local character = StoryTypes.character(story, id)
				expect(character and character.kind ~= "human").toBe(true)
			end
		end)

		it("puts the folder of Character models in the place, as ServerStorage.CharacterModels", function()
			local folder = project.tree.ServerStorage.CharacterModels
			expect(folder["$className"]).toBe("Folder")
			expect(folder["$path"]).toEqual({ optional = Manifest.CHARACTER_MODELS })
		end)
	end)

	describe("Story.build", function()
		local sam = assert(StoryTypes.character(story, "Sam"))
		local dad = assert(StoryTypes.character(story, "Dad"))

		it("builds a human from its Description", function()
			expect(StoryTypes.build(dad, false)).toBe("description")
			expect(StoryTypes.build(dad, true)).toBe("description")
		end)

		it("builds any other Character from its Character model when the place has one", function()
			expect(StoryTypes.build(sam, true)).toBe("model")
		end)

		it("falls back to the Placeholder when the place has no Character model", function()
			expect(StoryTypes.build(sam, false)).toBe("placeholder")
		end)
	end)
end
