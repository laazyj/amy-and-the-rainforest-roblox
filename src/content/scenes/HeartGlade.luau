--!strict
-- scene:HeartGlade: the ring of big glowing flowers at the heart of the
-- paradise.

local Story = require("../../core/Story")
local layout = require("../layout")

local at = layout.at

local zones: { [string]: Story.Zone } = {
	HeartGlade = layout.zone(at(0, 5, 255), at(40, 10, 30)),
}

return {
	id = "HeartGlade",
	spots = {},
	zones = zones,
	props = {},
	centre = at(0, 0, 255),
	ring = { radius = 20, flowers = 9 },
	-- no trees or stray flowers this close to the centre
	clearRadius = 24,
}
