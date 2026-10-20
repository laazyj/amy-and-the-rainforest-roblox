--!strict
-- scene:Garden: Amy's house and fenced garden, where she starts. Sam guards
-- the gate in the front fence.

local Story = require("../../core/Story")
local layout = require("../layout")
local palette = require("../palette")

local spot, zone, at = layout.spot, layout.zone, layout.at
local FOREST, HOME = layout.TOWARD_FOREST, layout.TOWARD_HOME

local AMY_SPAWN = spot(0, -26, FOREST)

local spots: { [string]: Story.Spot } = {
	AmySpawn = AMY_SPAWN,
	-- Dad faces Amy, who walks up from where she spawns to ask him
	DadHome = layout.spotToward(6, -26, AMY_SPAWN.at),
	MumHome = spot(-6, -33, FOREST),
	-- Sam watches the gate, beside the way to it, so he faces Amy when she
	-- tries it
	SamHome = spot(2.5, -21, FOREST),
	-- Sam's catch: he runs through the middle of the gate, clear of its
	-- posts, to just outside it; Amy lands back in the garden, and Sam
	-- settles beside her, watching the gate again
	GateOutside = spot(0, -13, HOME),
	GardenInside = spot(0, -28, FOREST),
	SamGuardPost = spot(2.5, -23, FOREST),
}

local zones: { [string]: Story.Zone } = {
	-- the garden gate Amy keeps trying to sneak through
	GardenGate = zone(at(0, 5, -13), at(10, 10, 5)),
	-- back home in the garden
	HomeGarden = zone(at(0, 5, -26), at(26, 10, 16)),
}

return {
	id = "Garden",
	spots = spots,
	zones = zones,
	props = {},
	music = "music:home",
	ambience = "cue:ambience_home",
	-- inside the fence, and the gate
	bounds = zone(at(0, 40, -32.5), at(32, 100, 45)),
	-- Amy's house: red like her jumper in the drawing, with a bark roof
	house = { at = at(0, 0, -44), walls = layout.rgb(206, 92, 74), roof = palette.colours.bark, scale = 1 },
	-- the fence: front line with the gate in the middle, sides, and back
	-- (its posts are `post` studs square)
	fence = { frontZ = -16, backZ = -54, halfWidth = 15, gateHalfWidth = 3, post = 0.8 },
}
