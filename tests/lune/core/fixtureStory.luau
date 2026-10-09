--[[
	A small Story for the core specs: every Quest Kind, every Dialogue, Beats
	at both Hooks, a Prop, two Lighting presets and two Chapters. The real
	Story (src/content) is walked by the content specs.
]]

local Story = require("../../../src/core/Story")

local function spot(x: number, z: number): Story.Spot
	return { at = { x = x, y = 0, z = z }, facing = { x = 0, y = 0, z = 1 } }
end

local fixture: Story.Story = {
	title = "Fixture",
	author = "the specs",
	chapters = {
		{
			id = "chapter1",
			title = "One",
			subtitle = "The start",
			quests = {
				{
					id = "chapter1.greet",
					kind = "talk",
					character = "Guide",
					talkLabel = "Wave",
					objective = "Greet the Guide",
					intro = { { speaker = "Narrator", text = "Hello." } },
					dialogue = { { speaker = "Hero", text = "Hi!" }, { speaker = "Guide", text = "Welcome." } },
					outro = { { speaker = "Narrator", text = "Off you go." } },
					hooks = { onComplete = { "guide_leaves" } },
				},
				{
					id = "chapter1.go_out",
					kind = "reach",
					zone = "Gate",
					objective = "Go through the gate",
					hooks = { onStart = { "door_opens", "dusk_falls" } },
				},
			},
			beats = {
				guide_leaves = {
					{ kind = "MoveCharacter", character = "Guide", spot = "Field" },
					{ kind = "Wait", seconds = 0.5 },
					{ kind = "TeleportPlayer", spot = "HeroHome" },
				},
				door_opens = { { kind = "SetPropState", prop = "Door", state = "open" } },
				dusk_falls = { { kind = "SetLighting", preset = "dusk" } },
			},
		},
		{
			id = "chapter2",
			title = "Two",
			subtitle = "The field",
			quests = {
				{
					id = "chapter2.pick",
					kind = "collect",
					count = 2,
					pickups = { "FlowerA", "FlowerB", "FlowerC" },
					objective = "Pick flowers",
					intro = { { speaker = "Guide", text = "Pick two.", canon = true } },
				},
			},
			beats = {},
		},
	},
	characters = {
		{ id = "Hero", display = "the Hero", kind = "human", home = "HeroHome", player = true },
		{ id = "Guide", display = "the Guide", kind = "fox", home = "GuideHome" },
	},
	spots = {
		HeroHome = spot(0, 0),
		GuideHome = spot(5, 0),
		Field = spot(0, 50),
		FlowerA = spot(1, 60),
		FlowerB = spot(2, 60),
		FlowerC = spot(3, 60),
	},
	zones = { Gate = { centre = { x = 0, y = 5, z = 10 }, size = { x = 10, y = 10, z = 4 } } },
	props = { Door = { states = { "shut", "open" } } },
	lighting = {
		day = { saturation = 0, contrast = 0, tint = { r = 255, g = 255, b = 255 }, seconds = 2 },
		dusk = { saturation = 0.2, contrast = 0.1, tint = { r = 255, g = 220, b = 200 }, seconds = 1 },
	},
	initialLighting = "day",
	ending = { lines = { { speaker = "Narrator", text = "The end." } }, title = "The end", subtitle = "Fixture" },
}

return fixture
