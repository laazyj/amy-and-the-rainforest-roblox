--!strict
-- scene:Garden: Amy's house and fenced garden, where she starts. Sam guards
-- the gate in the front fence.

local Story = require("../../core/Story")
local layout = require("../layout")
local palette = require("../palette")

local spot, zone, at = layout.spot, layout.zone, layout.at
local FOREST, HOME = layout.TOWARD_FOREST, layout.TOWARD_HOME

local spots: { [string]: Story.Spot } = {
	AmySpawn = spot(0, -26, FOREST),
	DadHome = spot(6, -26, HOME),
	MumHome = spot(-6, -33, FOREST),
	SamHome = spot(3, -20, HOME),
	-- Sam's catch: he bounds to just outside the gate, Amy lands back in the
	-- garden, and Sam settles beside her
	GateOutside = spot(2, -14, HOME),
	GardenInside = spot(0, -28, FOREST),
	SamGuardPost = spot(3, -22, HOME),
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
	-- Amy's house: red like her jumper in the drawing, with a bark roof
	house = { at = at(0, 0, -44), walls = layout.rgb(206, 92, 74), roof = palette.colours.bark, scale = 1 },
	-- the fence: front line with the gate in the middle, sides, and back
	fence = { frontZ = -16, backZ = -54, halfWidth = 15, gateHalfWidth = 3 },
}
