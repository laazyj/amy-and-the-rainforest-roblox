--!strict
-- Chapter Four: The Giant Tree-Chopping Machine. Amy stands in front of the
-- machine and explains, and the village stops.

local Story = require("../../../core/Story")

local chapter: Story.ChapterData = {
	id = "chapter4",
	title = "Chapter Four",
	subtitle = "The Giant Tree-Chopping Machine",
	quests = {
		{
			id = "chapter4.stand_in_front",
			kind = "reach",
			zone = "MachineFront",
			objective = "The machine is heading for the forest -- stand in front of it!",
			intro = {
				{
					speaker = "Narrator",
					text = "The village made a giant tree-chopping machine and they decided to chop down the forest because they thought it was a thret to humankind.",
					canon = true,
				},
				{ speaker = "Amy", text = "No no no no NO. Not my paradise. Not my friends. MOVE, legs!" },
			} :: { Story.Line },
			outro = {
				{
					speaker = "Narrator",
					text = "Amy planted her feet in the grass, right between the whirring blade and the giant trees, and did not move.",
				},
				{ speaker = "Amy", text = "STOP! Everybody just... STOP!" },
			},
		},
		{
			id = "chapter4.explain",
			kind = "talk",
			character = "Dad",
			talkLabel = "Explain",
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
					canon = true,
				},
				{
					speaker = "Dad",
					text = "...Proud of it. Well. I suppose it IS the biggest, greenest thing any village ever had.",
				},
				{ speaker = "Narrator", text = "They took her seriously and stoped.", canon = true },
			},
			hooks = { onComplete = { "machine_stops" } },
		},
	},
}

return chapter
