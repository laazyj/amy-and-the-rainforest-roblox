--!strict
--[[
	The Story: "Amy and the Rain Forest", by Clara. Assembles the content
	into the one Story the core plays: each Chapter's data with its Beats,
	the Characters, every Scene's Spots, Zones and Props, the Lighting
	presets and the Ending.
]]

local Story = require("../core/Story")
local characters = require("./characters")
local ending = require("./ending")
local presets = require("./presets")

local Field = require("./scenes/Field")
local ForestWall = require("./scenes/ForestWall")
local Garden = require("./scenes/Garden")
local HeartGlade = require("./scenes/HeartGlade")
local Paradise = require("./scenes/Paradise")
local Village = require("./scenes/Village")

local CHAPTERS: { { data: Story.ChapterData, beats: { [string]: Story.Beat } } } = {
	{ data = require("./chapters/1/data"), beats = require("./chapters/1/hooks") },
	{ data = require("./chapters/2/data"), beats = require("./chapters/2/hooks") },
	{ data = require("./chapters/3/data"), beats = require("./chapters/3/hooks") },
	{ data = require("./chapters/4/data"), beats = require("./chapters/4/hooks") },
}

-- In the order SceneBuilder builds them.
local SCENES: { Story.Scene } = { Garden, Village, Field, ForestWall, Paradise, HeartGlade }

local story: Story.Story = {
	title = "Amy and the Rain Forest",
	author = "a story by Clara",
	chapters = {},
	characters = characters,
	spots = {},
	zones = {},
	props = {},
	lighting = presets,
	initialLighting = "ordinary",
	ending = ending,
}

for _, chapter in CHAPTERS do
	local assembled: any = table.clone(chapter.data)
	assembled.beats = chapter.beats
	table.insert(story.chapters, assembled)
end

-- Every Spot, Zone and Prop by its id, which is unique across the Scenes.
local function gather(into: { [string]: any }, from: { [string]: any }, what: string, scene: string)
	for id, value in from do
		if into[id] then
			error(`{what} {id} is declared twice (again in scene:{scene})`)
		end
		into[id] = value
	end
end
for _, scene in SCENES do
	gather(story.spots, scene.spots, "spot", scene.id)
	gather(story.zones, scene.zones, "zone", scene.id)
	gather(story.props, scene.props, "prop", scene.id)
end

return {
	story = story,
	scenes = SCENES,
}
