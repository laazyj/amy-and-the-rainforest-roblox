--[[
	StoryData
	=========
	Every word of the story lives in this one module: chapter titles,
	dialogue, objectives, and where things are placed in the world.

	NOTE FOR THE AUTHOR:
	This is a first-draft narrative written to match the game's title,
	"Amy and the Rainforest". The original story at clara.jasonduffett.net
	could not be reached from the build environment, so treat every line
	below as a placeholder you can rewrite. Edit the text freely -- the
	game engine only cares about the structure (ids, types, counts).

	Quest types understood by the engine (StoryServer):
	  "talk"    -> walk up to an NPC and press E (ProximityPrompt)
	  "collect" -> touch `count` glowing pickups spawned at `spawnPoints`
	  "reach"   -> walk into an invisible zone named in `zone`
]]

local StoryData = {}

StoryData.GameTitle = "Amy and the Rainforest"

----------------------------------------------------------------
-- World layout constants (shared by WorldBuilder + StoryServer)
----------------------------------------------------------------
StoryData.Map = {
	GroundY = 0,
	SpawnPosition = Vector3.new(0, 4, -30),

	-- The river cuts across the map at these Z coordinates
	RiverNearZ = 235,
	RiverFarZ = 265,

	-- The Great Kapok Tree
	TreePosition = Vector3.new(0, 0, 400),
	TreeHeight = 110,
	TreeRadius = 10,
	ClimbRadius = 19, -- distance of the spiral platforms from tree centre
	TopPlatformY = 112,
}

----------------------------------------------------------------
-- Characters
----------------------------------------------------------------
-- kind: "monkey" | "sloth" | "toucan" | "flower" (how StoryServer draws them)
StoryData.NPCs = {
	{
		id = "Milo",
		display = "Milo the Monkey",
		kind = "monkey",
		position = Vector3.new(6, 0, 25),
		faceZ = -1, -- looks back toward the spawn
	},
	{
		id = "GrandmaSloth",
		display = "Grandma Sloth",
		kind = "sloth",
		position = Vector3.new(8, 0, 168),
		faceZ = -1,
	},
	{
		id = "Tiki",
		display = "Tiki the Toucan",
		kind = "toucan",
		position = Vector3.new(10, 0, 226),
		faceZ = -1,
	},
	{
		id = "RainFlower",
		display = "The Rain Flower",
		kind = "flower",
		-- placed on the tree-top platform by StoryServer using Map values
		position = Vector3.new(0, 113, 400),
		faceZ = -1,
	},
}

----------------------------------------------------------------
-- Trigger zones (invisible boxes the player can walk into)
----------------------------------------------------------------
StoryData.Zones = {
	{ name = "VillageGate", position = Vector3.new(0, 6, 120), size = Vector3.new(70, 12, 8) },
	{ name = "FarBank", position = Vector3.new(0, 6, 278), size = Vector3.new(70, 12, 8) },
	{ name = "TreeTop", position = Vector3.new(0, 116, 400), size = Vector3.new(30, 8, 30) },
}

----------------------------------------------------------------
-- The story, chapter by chapter
----------------------------------------------------------------
StoryData.Chapters = {

	----------------------------------------------------------------
	{
		id = "chapter1",
		title = "Chapter One",
		subtitle = "The Edge of the Rainforest",
		quests = {
			{
				id = "meet_milo",
				type = "talk",
				npc = "Milo",
				objective = "Say hello to the little monkey on the path",
				intro = {
					{ speaker = "Narrator", text = "Amy stepped off the riverboat and into a world of green. The rainforest hummed and whistled and buzzed all around her." },
					{ speaker = "Amy", text = "Wow... it's even bigger than in my books!" },
				},
				dialogue = {
					{ speaker = "Milo the Monkey", text = "Ooh-ooh! A visitor! We never get visitors anymore. I'm Milo!" },
					{ speaker = "Amy", text = "Hi Milo! I'm Amy. Why don't you get visitors anymore?" },
					{ speaker = "Milo the Monkey", text = "Because of the Great Dry, of course. It hasn't rained in the forest for a whole month. A MONTH!" },
					{ speaker = "Milo the Monkey", text = "Grandma Sloth will explain everything. Follow the path to our village -- I'll race you there!" },
				},
			},
			{
				id = "walk_to_village",
				type = "reach",
				zone = "VillageGate",
				objective = "Follow the jungle path to the animal village",
				intro = {
					{ speaker = "Narrator", text = "Milo scampered ahead, swinging from vine to vine. Amy hurried after him along the winding path." },
				},
			},
		},
	},

	----------------------------------------------------------------
	{
		id = "chapter2",
		title = "Chapter Two",
		subtitle = "The Village With No Rain",
		quests = {
			{
				id = "meet_grandma",
				type = "talk",
				npc = "GrandmaSloth",
				objective = "Talk to Grandma Sloth in the village",
				intro = {
					{ speaker = "Narrator", text = "The village was quiet. The flowers drooped, the stream had shrunk to a trickle, and everyone looked terribly thirsty." },
				},
				dialogue = {
					{ speaker = "Grandma Sloth", text = "Welcome, child. I am... Grandma... Sloth. Forgive me... I talk... slowly... even for a sloth. It is... too dry... to hurry." },
					{ speaker = "Amy", text = "Milo told me it hasn't rained in a month. What happened?" },
					{ speaker = "Grandma Sloth", text = "At the top of the Great Kapok Tree grows the Rain Flower. When its petals glow, the clouds come to drink, and then they water the whole forest." },
					{ speaker = "Grandma Sloth", text = "But a wild wind blew three of its petals away... and without them, the flower sleeps, and the sky has forgotten us." },
					{ speaker = "Amy", text = "Then I'll find the petals and carry them back up the tree!" },
					{ speaker = "Grandma Sloth", text = "You have... a brave heart, Amy. The petals still glow -- look for their pink light in the shadows of the forest." },
				},
			},
			{
				id = "find_petals",
				type = "collect",
				item = "Rain Flower Petal",
				pickupStyle = "petal",
				count = 3,
				objective = "Find the 3 glowing petals near the village",
				spawnPoints = {
					Vector3.new(-42, 0, 142),
					Vector3.new(38, 0, 192),
					Vector3.new(-28, 0, 212),
				},
				intro = {
					{ speaker = "Milo the Monkey", text = "I saw pink sparkles near the big rocks and under the old trees! Ooh-ooh, let's look everywhere!" },
				},
				onComplete = {
					{ speaker = "Amy", text = "That's all three petals! They're so warm... like little pieces of sunshine." },
					{ speaker = "Milo the Monkey", text = "Now we just have to cross the river. Umm. About that. You'd better come see the bridge." },
				},
			},
		},
	},

	----------------------------------------------------------------
	{
		id = "chapter3",
		title = "Chapter Three",
		subtitle = "The Broken Bridge",
		quests = {
			{
				id = "meet_tiki",
				type = "talk",
				npc = "Tiki",
				objective = "Talk to the toucan by the river",
				dialogue = {
					{ speaker = "Tiki the Toucan", text = "Halt! Who crosses the... oh. Nobody crosses anything. The wild wind smashed our bridge to bits." },
					{ speaker = "Amy", text = "But I have to get to the Great Kapok Tree! I'm carrying the Rain Flower's petals." },
					{ speaker = "Tiki the Toucan", text = "The PETALS?! Why didn't you say so! The wind scattered the bridge planks along the riverbank. Bring me three good ones and I'll lash them down with the strongest vines in the forest." },
				},
			},
			{
				id = "find_planks",
				type = "collect",
				item = "Bridge Plank",
				pickupStyle = "plank",
				count = 3,
				objective = "Gather 3 planks scattered along the riverbank",
				spawnPoints = {
					Vector3.new(-45, 0, 222),
					Vector3.new(48, 0, 230),
					Vector3.new(24, 0, 204),
				},
				onComplete = {
					{ speaker = "Tiki the Toucan", text = "Perfect planks! Stand back -- toucan at work!" },
					{ speaker = "Narrator", text = "Tiki tugged and knotted and tightened the vines, and in no time at all the bridge stood proud across the river again." },
					{ speaker = "Tiki the Toucan", text = "Off you go, Amy. And tell that old tree Tiki says hello!" },
				},
			},
			{
				id = "cross_river",
				type = "reach",
				zone = "FarBank",
				objective = "Cross the bridge to the far side of the river",
			},
		},
	},

	----------------------------------------------------------------
	{
		id = "chapter4",
		title = "Chapter Four",
		subtitle = "The Great Kapok Tree",
		quests = {
			{
				id = "climb_tree",
				type = "reach",
				zone = "TreeTop",
				objective = "Climb the winding branches to the top of the Great Kapok Tree",
				intro = {
					{ speaker = "Narrator", text = "And there it was: the Great Kapok Tree, taller than a hundred houses, its branches spiralling up into the clouds." },
					{ speaker = "Amy", text = "Okay, Amy. One branch at a time. Don't look down. Well... maybe look down a little, the view is amazing." },
				},
			},
		},
	},

	----------------------------------------------------------------
	{
		id = "chapter5",
		title = "Chapter Five",
		subtitle = "The Rain Flower",
		quests = {
			{
				id = "wake_flower",
				type = "talk",
				npc = "RainFlower",
				promptText = "Return the petals",
				objective = "Return the petals to the Rain Flower",
				dialogue = {
					{ speaker = "Narrator", text = "At the very top of the tree, in a nest of silver leaves, the Rain Flower slept. Amy knelt and gently pressed the three petals back into place." },
					{ speaker = "Amy", text = "There you go. All better now. Please wake up -- the whole forest is waiting for you." },
					{ speaker = "Narrator", text = "One by one, the petals began to glow. Pink, then gold, then every colour at once..." },
				},
			},
		},
	},
}

----------------------------------------------------------------
-- Ending
----------------------------------------------------------------
StoryData.Ending = {
	lines = {
		{ speaker = "Narrator", text = "The Rain Flower opened wide and sang a single, shimmering note. Far away, the clouds heard it -- and they came racing across the sky." },
		{ speaker = "Narrator", text = "Rain! Soft, warm, wonderful rain fell on every leaf and flower and thirsty little stream." },
		{ speaker = "Milo the Monkey", text = "Ooh-ooh! Amy did it! AMY DID IT!" },
		{ speaker = "Grandma Sloth", text = "Thank you... brave... Amy. The forest... will remember you... forever." },
		{ speaker = "Amy", text = "I'll come back and visit. I promise. Somebody has to teach Milo how to play tag properly!" },
	},
	title = "The End",
	subtitle = "Amy and the Rainforest",
}

return StoryData
