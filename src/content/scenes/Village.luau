--!strict
-- scene:Village: the little houses behind Amy's, and the farm where Sam
-- spends Chapter Two.

local Story = require("../../core/Story")
local layout = require("../layout")
local palette = require("../palette")

local at, rgb = layout.at, layout.rgb
local colours = palette.colours

local spots: { [string]: Story.Spot } = {
	Farm = layout.spot(80, -58, layout.TOWARD_FOREST),
}

return {
	id = "Village",
	spots = spots,
	zones = {},
	props = {},
	houses = {
		{ at = at(-44, 0, -50), walls = rgb(222, 196, 150), roof = colours.deep, scale = 0.9 },
		{ at = at(44, 0, -44), walls = rgb(196, 176, 208), roof = colours.bark, scale = 0.85 },
		{ at = at(-64, 0, -20), walls = rgb(176, 196, 160), roof = colours.bark, scale = 0.8 },
		{ at = at(62, 0, -24), walls = rgb(228, 180, 120), roof = colours.deep, scale = 0.9 },
	},
}
