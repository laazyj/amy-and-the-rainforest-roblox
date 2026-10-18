--!strict
-- The Characters: kind, display name (how a Speaker is shown), home Spot,
-- and how each looks. A human has a Description; any other is drawn as its
-- Placeholder until its Character model (assets/meshes/characters) is in
-- the place. Amy is the Player Character.

local Story = require("../core/Story")
local layout = require("./layout")
local palette = require("./palette")

local rgb, dressed = layout.rgb, layout.dressed
local colours = palette.colours

local SKIN, TROUSERS = colours.skin, colours.trousers
local AMY_SKIN = rgb(219, 169, 126) -- #dba97e

local characters: { Story.Character } = {
	{
		id = "Amy",
		display = "Amy",
		kind = "human",
		home = "AmySpawn",
		player = true,
		-- as Clara drew her (ref:Amy): light skin, bare legs and the red
		-- jumper; her long dark brown hair, the jumper's long sleeves, the
		-- blue skirt and the brown shoes are Catalog items, worn once the
		-- Manifest has their ids
		description = {
			head = AMY_SKIN,
			torso = colours.red,
			arms = AMY_SKIN,
			legs = AMY_SKIN,
			catalog = {
				hair = "catalog:amy_hair",
				shirt = "catalog:amy_shirt",
				skirt = "catalog:amy_skirt",
				leftShoe = "catalog:amy_left_shoe",
				rightShoe = "catalog:amy_right_shoe",
			},
		},
	},
	{
		id = "Dad",
		display = "Dad",
		kind = "human",
		home = "DadHome",
		description = dressed(SKIN, rgb(90, 122, 80), TROUSERS),
	},
	-- Clara's grape accent
	{
		id = "Mum",
		display = "Mum",
		kind = "human",
		home = "MumHome",
		description = dressed(SKIN, rgb(124, 77, 178), TROUSERS),
	},
	{
		id = "Sam",
		display = "Sam the Dog",
		kind = "dog",
		home = "SamHome",
		-- the white dog
		placeholder = { body = rgb(238, 230, 214), belly = rgb(150, 110, 74), scale = 1.0, tail = "up" },
	},
	{
		id = "Squirrel",
		display = "the Maroon Squirrel",
		kind = "squirrel",
		home = "SquirrelHome",
		-- maroon! with a giant question-mark tail
		placeholder = { body = rgb(128, 32, 48), belly = rgb(214, 168, 150), scale = 0.55, tail = "fluff" },
	},
	{
		id = "Fox",
		display = "the Orange Fox",
		kind = "fox",
		home = "FoxHome",
		-- the orangest orange
		placeholder = { body = rgb(240, 120, 32), belly = rgb(248, 240, 226), scale = 0.85, tail = "brush" },
	},
	{
		id = "Lion",
		display = "the Golden Lion",
		kind = "lion",
		home = "LionHome",
		-- golden
		placeholder = { body = rgb(226, 178, 68), belly = rgb(240, 214, 150), scale = 1.5, tail = "tuft" },
	},
}

return characters
