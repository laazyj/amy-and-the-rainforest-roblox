--!strict
-- The Characters: kind, display name (how a Speaker is shown), home Spot,
-- and a shirt colour for the humans. Amy is the Player Character.

local Story = require("../core/Story")
local layout = require("./layout")

local rgb = layout.rgb

local characters: { Story.Character } = {
	{ id = "Amy", display = "Amy", kind = "human", home = "AmySpawn", player = true },
	{ id = "Dad", display = "Dad", kind = "human", home = "DadHome", shirt = rgb(90, 122, 80) },
	-- Clara's grape accent
	{ id = "Mum", display = "Mum", kind = "human", home = "MumHome", shirt = rgb(124, 77, 178) },
	{ id = "Sam", display = "Sam the Dog", kind = "dog", home = "SamHome" },
	{ id = "Squirrel", display = "the Maroon Squirrel", kind = "squirrel", home = "SquirrelHome" },
	{ id = "Fox", display = "the Orange Fox", kind = "fox", home = "FoxHome" },
	{ id = "Lion", display = "the Golden Lion", kind = "lion", home = "LionHome" },
}

return characters
