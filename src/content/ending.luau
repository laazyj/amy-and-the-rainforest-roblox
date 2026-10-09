--!strict
-- The Ending: the closing Dialogue and the end card.

local Story = require("../core/Story")

local ending: Story.Ending = {
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
		{ speaker = "Sam", text = "Woof!" },
		{ speaker = "Amy", text = "Deal." },
	},
	title = "The end ♥",
	subtitle = "Amy and the Rain Forest — a story by Clara",
}

return ending
