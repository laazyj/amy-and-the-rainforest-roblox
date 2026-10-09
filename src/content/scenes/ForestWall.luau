--!strict
-- scene:ForestWall: giant trunks standing shoulder to shoulder, topped with
-- two-tone canopies, nests and eggs, with one narrow gap just Amy's size.

local Story = require("../../core/Story")
local layout = require("../layout")

local at = layout.at

local zones: { [string]: Story.Zone } = {
	-- just inside the narrow gap between the giant trunks
	ForestGap = layout.zone(at(0, 5, 160), at(14, 12, 8)),
}

return {
	id = "ForestWall",
	spots = {},
	zones = zones,
	props = {},
	z = 150,
	gapHalfWidth = 6,
	-- which trees, counted out from the gap on each side, carry nests
	nests = { 2, 5 },
}
