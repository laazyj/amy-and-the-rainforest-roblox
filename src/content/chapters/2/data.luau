--!strict
-- Chapter Two: The Unexplored World. With Sam away at the farm, Amy crosses
-- the field, squeezes through the wall of trees and finds the paradise.

local Story = require("../../../core/Story")

local chapter: Story.ChapterData = {
	id = "chapter2",
	title = "Chapter Two",
	subtitle = "The Unexplored World",
	quests = {
		{
			id = "chapter2.walk_to_forest",
			kind = "reach",
			zone = "ForestEdge",
			objective = "Sam is away at the farm -- cross the field to the rain forest!",
			intro = {
				{
					speaker = "Narrator",
					text = "One day when her dog was out at a farm, Amy managed to get outside.",
					canon = true,
				},
				{ speaker = "Amy", text = "No Dad. No Sam. Just me, the grass, and... oh my. THAT." },
			} :: { Story.Line },
			outro = {
				{ speaker = "Narrator", text = "Then suddenly a dark forest loomed infront of her.", canon = true },
				{
					speaker = "Amy",
					text = "The trees are like a giant wall... they're holding hands so nobody can get in. But look -- there's a little gap. Just my size.",
				},
			} :: { Story.Line },
			hooks = { onStart = { "sam_goes_to_farm" } },
		},
		{
			id = "chapter2.enter_forest",
			kind = "reach",
			zone = "ForestGap",
			objective = "Squeeze through the gap between the giant trees",
			intro = {
				{
					speaker = "Amy",
					text = "She decided to explore the unexplored world. That's me. I'm the she. Here goes nothing...",
				},
			},
			outro = {
				{
					speaker = "Narrator",
					text = "As soon as she went in Amy saw it was a world parallel to thier own!",
					canon = true,
				},
				{ speaker = "Narrator", text = "It was a bautyfull paradise!", canon = true },
				{
					speaker = "Amy",
					text = "The colours! The flowers are singing... no wait, that's birds. no, wait. it might be the flowers.",
				},
			} :: { Story.Line },
			hooks = { onComplete = { "paradise_reveal" } },
		},
		{
			id = "chapter2.heart_glade",
			kind = "reach",
			zone = "HeartGlade",
			objective = "Follow the glowing flowers deeper into the paradise",
		},
	},
}

return chapter
