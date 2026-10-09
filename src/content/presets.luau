--!strict
-- Lighting presets: the colour grade each one sets, and how long the change
-- into it takes.

local Story = require("../core/Story")
local layout = require("./layout")

local rgb = layout.rgb

local presets: { [string]: Story.LightingPreset } = {
	-- warm cream-sky afternoon, no colour grade
	ordinary = { saturation = 0, contrast = 0, tint = rgb(255, 255, 255), seconds = 2 },
	-- saturation and contrast raised, warm tint
	paradise = { saturation = 0.35, contrast = 0.06, tint = rgb(255, 250, 240), seconds = 2.5 },
}

return presets
