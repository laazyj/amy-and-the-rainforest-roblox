--!strict
-- scene:Field: the scribbly-grass field between the garden and the trees,
-- under a cream sky with birds and clouds. The machine comes here in the
-- finale.

local Story = require("../../core/Story")
local layout = require("../layout")
local palette = require("../palette")

local spot, zone, at, rgb = layout.spot, layout.zone, layout.at, layout.rgb
local FOREST = layout.TOWARD_FOREST
local colours = palette.colours

local spots: { [string]: Story.Spot } = {
	MachineBay = spot(0, 95, FOREST),
	DadAtMachine = spot(9, 108, FOREST),
	MumAtMachine = spot(-9, 106, FOREST),
	SamAtMachine = spot(13, 104, FOREST),
	Villager1 = spot(-14, 84, FOREST),
	Villager2 = spot(-5, 80, FOREST),
	Villager3 = spot(6, 81, FOREST),
	Villager4 = spot(15, 85, FOREST),
}

local zones: { [string]: Story.Zone } = {
	-- the grass in front of the looming tree wall
	ForestEdge = zone(at(0, 5, 136), at(60, 10, 8)),
	-- the patch of grass between the machine and the forest
	MachineFront = zone(at(0, 5, 110), at(16, 10, 9)),
}

-- Each Prop's states, and how PropHost places it: prop:Machine parks at
-- its Spot and reverses away; prop:Villagers stand at theirs, in these
-- shirts, and cheer with sparkles over the crowd.
local machine = {
	states = { "absent", "advancing", "stopped", "retreating" },
	spot = "MachineBay",
	retreatDistance = 34,
	retreatSeconds = 6,
}
local villagers = {
	states = { "absent", "gathered", "cheering" },
	spots = { "Villager1", "Villager2", "Villager3", "Villager4" },
	shirts = { rgb(180, 120, 70), rgb(96, 130, 170), rgb(170, 96, 96), rgb(120, 150, 96) },
	sparkles = {
		{ at = at(-10, 12, 100), colour = colours.bubblegum },
		{ at = at(0, 12, 100), colour = colours.gold },
		{ at = at(10, 12, 100), colour = colours.grape },
	},
	sparkleSeconds = 6,
}
export type Machine = typeof(machine)
export type Villagers = typeof(villagers)

local props: { [string]: Story.Prop } = { Machine = machine, Villagers = villagers }

return {
	id = "Field",
	spots = spots,
	zones = zones,
	props = props,
	-- the playable world: from behind the village to the far end of the
	-- paradise (scene:Paradise), this wide
	ground = { y = 0, startZ = -75, halfWidth = 95 },
	grassTufts = 160,
	flowers = { count = 26, colours = { colours.gold, colours.red } },
	-- the dirt path from the garden gate toward the forest gap
	path = { at(0, 0, -14), at(6, 0, 20), at(-8, 0, 60), at(4, 0, 100), at(0, 0, 144) },
	birds = {
		{ at = at(-40, 72, 100), scale = 1.2 },
		{ at = at(-28, 66, 112), scale = 0.9 },
		{ at = at(52, 78, 90), scale = 1.1 },
		{ at = at(38, 70, 60), scale = 0.8 },
		{ at = at(10, 82, 130), scale = 1.0 },
	},
	clouds = {
		{ at = at(-60, 85, 40), scale = 1.2 },
		{ at = at(65, 92, 110), scale = 1.0 },
		{ at = at(-20, 95, 170), scale = 1.4 },
	},
}
