--!strict
-- scene:Paradise: the parallel world beyond the wall, in the site's palette
-- (moss, gold, bubblegum pink, grape purple), where the animals live.

local Story = require("../../core/Story")
local layout = require("../layout")
local palette = require("../palette")

local spot, rgb = layout.spot, layout.rgb
local HOME = layout.TOWARD_HOME
local colours = palette.colours

local spots: { [string]: Story.Spot } = {
	SquirrelHome = spot(-30, 215, HOME),
	FoxHome = spot(35, 248, HOME),
	LionHome = spot(0, 298, HOME),
}

return {
	id = "Paradise",
	spots = spots,
	zones = {},
	props = {},
	endZ = 420,
	grassTufts = 120,
	trees = 90,
	leafColours = { colours.moss, rgb(120, 190, 90), colours.bubblegum, colours.grape, rgb(90, 200, 170), colours.gold },
	glowFlowers = 40,
	-- a trail of glowing flowers from the gap to scene:HeartGlade
	trail = { stepZ = 12, untilZ = 240, offsetX = 5 },
	lightShafts = 8,
	sparkles = { count = 16, colours = { colours.bubblegum, colours.gold, rgb(190, 240, 255) } },
	-- the walking line from the gap to the glade stays free of trunks, and so
	-- does the ground around each animal's home
	clearPath = { halfWidth = 10, untilZ = 265 },
	clearAroundCharacters = 12,
}
