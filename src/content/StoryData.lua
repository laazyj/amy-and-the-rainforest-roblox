--!nonstrict
-- Legacy untyped code from the proof of concept. The project default is strict
-- (.luaurc); this file opts out until the Checkpoint B restructure gives it
-- types. Under strict mode luau-lsp reports only type-inference errors here,
-- no real bugs; non-strict mode reports nothing.
--[[
	StoryData
	=========
	Every word of the story lives in this one module: chapter titles,
	dialogue, objectives, and where things are placed in the world.

	Based on "Amy and the Rain Forest" by Clara Dineen-Duffett
	(clara.jasonduffett.net). Narrator lines quoted directly from the
	story keep Clara's original spelling on purpose -- they're part of
	its charm, just like the highlights on the website.

	Quest types understood by the engine (StoryServer):
	  "talk"    -> walk up to a character and press E (ProximityPrompt)
	  "collect" -> touch `count` glowing pickups spawned at `spawnPoints`
	  "reach"   -> walk into an invisible zone named in `zone`
]]

local StoryData = {}

StoryData.GameTitle = "Amy and the Rain Forest"
StoryData.Author = "a story by Clara"

----------------------------------------------------------------
-- World layout constants (shared by WorldBuilder + StoryServer)
----------------------------------------------------------------
StoryData.Map = {
	GroundY = 0,

	-- Amy's garden (spawn) and house
	SpawnPosition = Vector3.new(0, 4, -26),
	HousePosition = Vector3.new(0, 0, -44),
	GardenGateZ = -16, -- front fence line of the garden

	-- The looming wall of giant trees (like the hero drawing)
	ForestWallZ = 150,
	ForestGapHalfWidth = 6, -- the narrow squeeze-through at x = 0
	ForestEndZ = 420,

	-- Width of the playable world
	MapHalfWidth = 95,

	-- Where the tree-chopping machine parks in the finale
	MachinePosition = Vector3.new(0, 0, 95),
}

----------------------------------------------------------------
-- Characters
----------------------------------------------------------------
-- kind: "human" | "dog" | "squirrel" | "fox" | "lion"
StoryData.NPCs = {
	{
		id = "Dad",
		display = "Dad",
		kind = "human",
		shirt = Color3.fromRGB(90, 122, 80),
		position = Vector3.new(6, 0, -26),
		faceZ = -1,
	},
	{
		id = "Mum",
		display = "Mum",
		kind = "human",
		shirt = Color3.fromRGB(124, 77, 178), -- Clara's grape accent
		position = Vector3.new(-6, 0, -33),
		faceZ = 1,
	},
	{
		id = "Sam",
		display = "Sam the Dog",
		kind = "dog",
		position = Vector3.new(3, 0, -20),
		faceZ = -1,
	},
	{
		id = "Squirrel",
		display = "the Maroon Squirrel",
		kind = "squirrel",
		position = Vector3.new(-30, 0, 215),
		faceZ = -1,
	},
	{
		id = "Fox",
		display = "the Orange Fox",
		kind = "fox",
		position = Vector3.new(35, 0, 248),
		faceZ = -1,
	},
	{
		id = "Lion",
		display = "the Golden Lion",
		kind = "lion",
		position = Vector3.new(0, 0, 298),
		faceZ = -1,
	},
}

----------------------------------------------------------------
-- Trigger zones (invisible boxes the player can walk into)
----------------------------------------------------------------
StoryData.Zones = {
	-- the garden gate Amy keeps trying to sneak through
	{ name = "GardenGate", position = Vector3.new(0, 5, -13), size = Vector3.new(10, 10, 5) },
	-- the grass in front of the looming tree wall
	{ name = "ForestEdge", position = Vector3.new(0, 5, 136), size = Vector3.new(60, 10, 8) },
	-- just inside the narrow gap between the giant trunks
	{ name = "ForestGap", position = Vector3.new(0, 5, 160), size = Vector3.new(14, 12, 8) },
	-- the heart of the parallel world
	{ name = "HeartGlade", position = Vector3.new(0, 5, 255), size = Vector3.new(40, 10, 30) },
	-- back home in the garden
	{ name = "HomeGarden", position = Vector3.new(0, 5, -26), size = Vector3.new(26, 10, 16) },
	-- the patch of grass between the machine and the forest
	{ name = "MachineFront", position = Vector3.new(0, 5, 110), size = Vector3.new(16, 10, 9) },
}

----------------------------------------------------------------
-- The story, chapter by chapter
----------------------------------------------------------------
StoryData.Chapters = {

	----------------------------------------------------------------
	{
		id = "chapter1",
		title = "Chapter One",
		subtitle = "One Beautyfull Sunday",
		quests = {
			{
				id = "ask_dad",
				type = "talk",
				npc = "Dad",
				objective = "Ask Dad if you can go outside",
				intro = {
					{ speaker = "Narrator", text = "One beautyfull sunday, Amy asked to go outside." },
				},
				dialogue = {
					{
						speaker = "Amy",
						text = "Dad, can I go outside? Please? It's the most beautiful Sunday there has ever been!",
					},
					{ speaker = "Dad", text = "No, it to Dangerous because of the huge rain forest." },
					{ speaker = "Amy", text = "But Dad--" },
					{
						speaker = "Dad",
						text = "No buts, Amy. Nobody from the village ever goes near those trees. And besides... Sam is watching you.",
					},
					{
						speaker = "Narrator",
						text = "By the garden gate, Sam the dog tilted his head and thumped his tail. He was ALWAYS watching.",
					},
				},
			},
			{
				id = "sneak_out_1",
				type = "reach",
				zone = "GardenGate",
				objective = "Sneak out through the garden gate... quietly!",
				intro = {
					{
						speaker = "Amy",
						text = "Hmph. 'Too dangerous.' I'll just have a tiny little look. What Dad doesn't know can't worry him...",
					},
				},
				onComplete = {
					{ speaker = "Sam the Dog", text = "WOOF!" },
					{
						speaker = "Narrator",
						text = "She tryed to go out side but thier dog Sam always brought her back in.",
					},
					{ speaker = "Amy", text = "Saaaam! Let go of my jumper! Fine. FINE. I'm going." },
				},
			},
			{
				id = "sneak_out_2",
				type = "reach",
				zone = "GardenGate",
				objective = "Wait for Sam to look away, then try the gate again",
				intro = {
					{
						speaker = "Amy",
						text = "Okay. New plan. Tip-toes this time. Sam can't hear tip-toes. Nobody can hear tip-toes.",
					},
				},
				onComplete = {
					{ speaker = "Sam the Dog", text = "Woof woof!" },
					{ speaker = "Narrator", text = "She tryed again but Sam brang her back." },
					{
						speaker = "Amy",
						text = "You are the best guard dog in the whole world, Sam, and it is EXTREMELY annoying.",
					},
				},
			},
		},
	},

	----------------------------------------------------------------
	{
		id = "chapter2",
		title = "Chapter Two",
		subtitle = "The Unexplored World",
		quests = {
			{
				id = "walk_to_forest",
				type = "reach",
				zone = "ForestEdge",
				objective = "Sam is away at the farm -- cross the field to the rain forest!",
				intro = {
					{
						speaker = "Narrator",
						text = "One day when her dog was out at a farm, Amy managed to get outside.",
					},
					{ speaker = "Amy", text = "No Dad. No Sam. Just me, the grass, and... oh my. THAT." },
				},
				onComplete = {
					{ speaker = "Narrator", text = "Then suddenly a dark forest loomed infront of her." },
					{
						speaker = "Amy",
						text = "The trees are like a giant wall... they're holding hands so nobody can get in. But look -- there's a little gap. Just my size.",
					},
				},
			},
			{
				id = "enter_forest",
				type = "reach",
				zone = "ForestGap",
				objective = "Squeeze through the gap between the giant trees",
				intro = {
					{
						speaker = "Amy",
						text = "She decided to explore the unexplored world. That's me. I'm the she. Here goes nothing...",
					},
				},
				onComplete = {
					{
						speaker = "Narrator",
						text = "As soon as she went in Amy saw it was a world parallel to thier own!",
					},
					{ speaker = "Narrator", text = "It was a bautyfull paradise!" },
					{
						speaker = "Amy",
						text = "The colours! The flowers are singing... no wait, that's birds. no, wait. it might be the flowers.",
					},
				},
			},
			{
				id = "heart_glade",
				type = "reach",
				zone = "HeartGlade",
				objective = "Follow the glowing flowers deeper into the paradise",
			},
		},
	},

	----------------------------------------------------------------
	{
		id = "chapter3",
		title = "Chapter Three",
		subtitle = "So Many Animals!",
		quests = {
			{
				id = "meet_squirrel",
				type = "talk",
				npc = "Squirrel",
				promptText = "Say hello",
				objective = "Say hello to the maroon squirrel",
				intro = {
					{
						speaker = "Narrator",
						text = "Amy discoverd so many animals! Something maroon was hopping between the roots...",
					},
				},
				dialogue = {
					{
						speaker = "Amy",
						text = "A squirrel! A MAROON squirrel! You're the colour of my nanna's favourite cardigan.",
					},
					{
						speaker = "the Maroon Squirrel",
						text = "And you're the first human I've ever seen! Are all of you this leafless?",
					},
					{ speaker = "Amy", text = "You can TALK?!" },
					{
						speaker = "the Maroon Squirrel",
						text = "Everything talks on this side of the trees. You just have to come in and listen.",
					},
				},
			},
			{
				id = "meet_fox",
				type = "talk",
				npc = "Fox",
				promptText = "Say hello",
				objective = "Find the orange fox",
				dialogue = {
					{
						speaker = "the Orange Fox",
						text = "Ooooh, a visitor. I'm sorry about the squirrel. He says 'leafless' to everyone.",
					},
					{
						speaker = "Amy",
						text = "You're the orangest fox I have ever seen. You look like a sunset with a tail.",
					},
					{
						speaker = "the Orange Fox",
						text = "Thank you! We take very good care of our colours here. The forest looks after us, and we look after the forest.",
					},
				},
			},
			{
				id = "meet_lion",
				type = "talk",
				npc = "Lion",
				promptText = "Say hello (bravely)",
				objective = "Meet the golden lion in the deep glade",
				dialogue = {
					{
						speaker = "Amy",
						text = "A lion. A golden lion. Right. Be brave, Amy. He probably had a big breakfast.",
					},
					{
						speaker = "the Golden Lion",
						text = "Peace, little explorer. No one is eaten in the paradise. It is against the whole idea of a paradise.",
					},
					{
						speaker = "the Golden Lion",
						text = "You have seen our world now, Amy. When you go home... tell them what you saw. Tell them the truth about us.",
					},
					{ speaker = "Amy", text = "I will. I promise. Mum is NOT going to believe this!" },
				},
			},
			{
				id = "rush_home",
				type = "reach",
				zone = "HomeGarden",
				objective = "Rush home and tell Mum everything!",
				intro = {
					{ speaker = "Narrator", text = "She rushed Home..." },
				},
			},
			{
				id = "tell_mum",
				type = "talk",
				npc = "Mum",
				objective = "Tell Mum about the parallel world",
				dialogue = {
					{
						speaker = "Amy",
						text = "MUM! The rain forest isn't dangerous, it's a paradise! There's a maroon squirrel and an orange fox and a golden lion and they TALK!",
					},
					{
						speaker = "Mum",
						text = "A golden... lion? That talks? Oh Amy. WAIT until your father hears about this.",
					},
					{ speaker = "Narrator", text = "...and told her mum who told her dad who told the village." },
					{
						speaker = "Narrator",
						text = "But the village did not hear 'paradise'. The village heard 'LION'.",
					},
				},
			},
		},
	},

	----------------------------------------------------------------
	{
		id = "chapter4",
		title = "Chapter Four",
		subtitle = "The Giant Tree-Chopping Machine",
		quests = {
			{
				id = "stand_in_front",
				type = "reach",
				zone = "MachineFront",
				objective = "The machine is heading for the forest -- stand in front of it!",
				intro = {
					{
						speaker = "Narrator",
						text = "The village made a giant tree-chopping machine and they decided to chop down the forest because they thought it was a thret to humankind.",
					},
					{ speaker = "Amy", text = "No no no no NO. Not my paradise. Not my friends. MOVE, legs!" },
				},
				onComplete = {
					{
						speaker = "Narrator",
						text = "Amy planted her feet in the grass, right between the whirring blade and the giant trees, and did not move.",
					},
					{ speaker = "Amy", text = "STOP! Everybody just... STOP!" },
				},
			},
			{
				id = "explain",
				type = "talk",
				npc = "Dad",
				promptText = "Explain",
				objective = "Explain to Dad and the village why the forest must be saved",
				dialogue = {
					{ speaker = "Dad", text = "Amy! Get away from there, it isn't safe!" },
					{
						speaker = "Amy",
						text = "It IS safe, Dad. I've been inside. It isn't a threat -- it's a paradise, a whole world parallel to ours!",
					},
					{
						speaker = "Amy",
						text = "There's a squirrel the colour of nanna's cardigan, and a fox like a sunset, and the golden lion is GENTLE, Dad. Nobody is eaten in a paradise. It's against the whole idea.",
					},
					{
						speaker = "Amy",
						text = "You shouldn't be scared of the forest. You should be PROUD of it. We should take care of it!",
					},
					{
						speaker = "Narrator",
						text = "Lukily Amy managed to stop them by staying in front of it just long enugh to explain to them that they should be proud of it and take care of it.",
					},
					{
						speaker = "Dad",
						text = "...Proud of it. Well. I suppose it IS the biggest, greenest thing any village ever had.",
					},
					{ speaker = "Narrator", text = "They took her seriously and stoped." },
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
		{
			speaker = "Narrator",
			text = "The great machine rolled backwards, away from the trees, and its terrible blade went still.",
		},
		{
			speaker = "Narrator",
			text = "And from the very top of the giant trees, a maroon squirrel, an orange fox and a golden lion watched the girl who saved their world.",
		},
		{
			speaker = "Dad",
			text = "Alright, alright. But next time you explore a parallel universe, young lady... you take the dog.",
		},
		{ speaker = "Sam the Dog", text = "Woof!" },
		{ speaker = "Amy", text = "Deal." },
	},
	title = "The end ♥",
	subtitle = "Amy and the Rain Forest — a story by Clara",
}

return StoryData
