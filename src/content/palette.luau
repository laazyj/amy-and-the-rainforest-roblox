--!strict
-- Clara's palette, from the hero illustration on her story page, and the
-- sky every Scene shares: a warm cream-sky afternoon.

local layout = require("./layout")

local rgb = layout.rgb

local palette = {
	deep = rgb(35, 64, 29), -- #23401d
	moss = rgb(90, 138, 68), -- #5a8a44
	bark = rgb(107, 68, 38), -- #6b4426
	gold = rgb(231, 181, 58), -- #e7b53a
	red = rgb(194, 64, 47), -- #c2402f
	grape = rgb(124, 77, 255), -- #7c4dff
	bubblegum = rgb(255, 93, 162), -- #ff5da2
	cream = rgb(240, 237, 217),
	grassGreen = rgb(74, 122, 56),
	grassLight = rgb(96, 148, 70),
	canopyDark = rgb(56, 108, 45),
	canopyLight = rgb(104, 158, 72),
}

local sky = {
	clockTime = 13.5,
	brightness = 2.2,
	ambient = rgb(118, 118, 100),
	outdoorAmbient = rgb(150, 148, 126),
	fog = palette.cream,
	fogEnd = 700,
	atmosphere = { density = 0.3, colour = rgb(227, 233, 191), haze = 1.6 }, -- the drawing's pale ground-sky tint
}

return { colours = palette, sky = sky }
