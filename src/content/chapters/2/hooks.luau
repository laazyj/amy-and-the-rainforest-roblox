--!strict
-- Chapter Two's Beats.

local Story = require("../../../core/Story")

local beats: { [string]: Story.Beat } = {
	-- Sam is off at the farm for the whole Chapter.
	sam_goes_to_farm = {
		{ kind = "MoveCharacter", character = "Sam", spot = "Farm" },
	},
	-- Stepping through the gap: the parallel world turns the colour up.
	paradise_reveal = {
		{ kind = "SetLighting", preset = "paradise" },
	},
}

return beats
