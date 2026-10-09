--!strict
-- Chapter Three: So Many Animals! Amy meets the squirrel, the fox and the
-- lion, rushes home and tells Mum, and the village hears "LION".

local Story = require("../../../core/Story")

local chapter: Story.ChapterData = {
	id = "chapter3",
	title = "Chapter Three",
	subtitle = "So Many Animals!",
	quests = {
		{
			id = "chapter3.meet_squirrel",
			kind = "talk",
			character = "Squirrel",
			talkLabel = "Say hello",
			objective = "Say hello to the maroon squirrel",
			intro = {
				{
					speaker = "Narrator",
					text = "Amy discoverd so many animals! Something maroon was hopping between the roots...",
					canon = true,
				},
			},
			dialogue = {
				{
					speaker = "Amy",
					text = "A squirrel! A MAROON squirrel! You're the colour of my nanna's favourite cardigan.",
				},
				{
					speaker = "Squirrel",
					text = "And you're the first human I've ever seen! Are all of you this leafless?",
				},
				{ speaker = "Amy", text = "You can TALK?!" },
				{
					speaker = "Squirrel",
					text = "Everything talks on this side of the trees. You just have to come in and listen.",
				},
			},
		},
		{
			id = "chapter3.meet_fox",
			kind = "talk",
			character = "Fox",
			talkLabel = "Say hello",
			objective = "Find the orange fox",
			dialogue = {
				{
					speaker = "Fox",
					text = "Ooooh, a visitor. I'm sorry about the squirrel. He says 'leafless' to everyone.",
				},
				{
					speaker = "Amy",
					text = "You're the orangest fox I have ever seen. You look like a sunset with a tail.",
				},
				{
					speaker = "Fox",
					text = "Thank you! We take very good care of our colours here. The forest looks after us, and we look after the forest.",
				},
			},
		},
		{
			id = "chapter3.meet_lion",
			kind = "talk",
			character = "Lion",
			talkLabel = "Say hello (bravely)",
			objective = "Meet the golden lion in the deep glade",
			dialogue = {
				{
					speaker = "Amy",
					text = "A lion. A golden lion. Right. Be brave, Amy. He probably had a big breakfast.",
				},
				{
					speaker = "Lion",
					text = "Peace, little explorer. No one is eaten in the paradise. It is against the whole idea of a paradise.",
				},
				{
					speaker = "Lion",
					text = "You have seen our world now, Amy. When you go home... tell them what you saw. Tell them the truth about us.",
				},
				{ speaker = "Amy", text = "I will. I promise. Mum is NOT going to believe this!" },
			},
		},
		{
			id = "chapter3.rush_home",
			kind = "reach",
			zone = "HomeGarden",
			objective = "Rush home and tell Mum everything!",
			intro = {
				{ speaker = "Narrator", text = "She rushed Home...", canon = true },
			},
			hooks = { onComplete = { "ordinary_world" } },
		},
		{
			id = "chapter3.tell_mum",
			kind = "talk",
			character = "Mum",
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
				{
					speaker = "Narrator",
					text = "...and told her mum who told her dad who told the village.",
					canon = true,
				},
				{
					speaker = "Narrator",
					text = "But the village did not hear 'paradise'. The village heard 'LION'.",
				},
			},
			hooks = { onComplete = { "machine_arrives" } },
		},
	},
}

return chapter
