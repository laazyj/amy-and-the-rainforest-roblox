--!strict
-- Chapter One: One Beautyfull Sunday. Amy asks to go outside, and twice
-- tries the garden gate. Lines marked canon are Clara's words, byte for
-- byte (docs/story/canon.md).

local Story = require("../../../core/Story")

local chapter: Story.ChapterData = {
	id = "chapter1",
	title = "Chapter One",
	subtitle = "One Beautyfull Sunday",
	quests = {
		{
			id = "chapter1.ask_dad",
			kind = "talk",
			character = "Dad",
			objective = "Ask Dad if you can go outside",
			intro = {
				{ speaker = "Narrator", text = "One beautyfull sunday, Amy asked to go outside.", canon = true },
			},
			dialogue = {
				{
					speaker = "Amy",
					text = "Dad, can I go outside? Please? It's the most beautiful Sunday there has ever been!",
				},
				{ speaker = "Dad", text = "No, it to Dangerous because of the huge rain forest.", canon = true },
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
			id = "chapter1.sneak_out_1",
			kind = "reach",
			zone = "GardenGate",
			objective = "Sneak out through the garden gate... quietly!",
			intro = {
				{
					speaker = "Amy",
					text = "Hmph. 'Too dangerous.' I'll just have a tiny little look. What Dad doesn't know can't worry him...",
				},
			},
			outro = {
				{ speaker = "Sam", text = "WOOF!" },
				{
					speaker = "Narrator",
					text = "She tryed to go out side but thier dog Sam always brought her back in.",
					canon = true,
				},
				{ speaker = "Amy", text = "Saaaam! Let go of my jumper! Fine. FINE. I'm going." },
			},
			hooks = { onComplete = { "sam_catches" } },
		},
		{
			id = "chapter1.sneak_out_2",
			kind = "reach",
			zone = "GardenGate",
			objective = "Wait for Sam to look away, then try the gate again",
			intro = {
				{
					speaker = "Amy",
					text = "Okay. New plan. Tip-toes this time. Sam can't hear tip-toes. Nobody can hear tip-toes.",
				},
			},
			outro = {
				{ speaker = "Sam", text = "Woof woof!" },
				{ speaker = "Narrator", text = "She tryed again but Sam brang her back.", canon = true },
				{
					speaker = "Amy",
					text = "You are the best guard dog in the whole world, Sam, and it is EXTREMELY annoying.",
				},
			},
			hooks = { onComplete = { "sam_catches" } },
		},
	},
}

return chapter
