--!strict
-- Chapter Four's Beats.

local Story = require("../../../core/Story")

local beats: { [string]: Story.Beat } = {
	-- Amy wins: the blade stops, the crowd cheers, the machine backs away.
	machine_stops = {
		{ kind = "SetPropState", prop = "Machine", state = "stopped" },
		{ kind = "SetPropState", prop = "Villagers", state = "cheering" },
		{ kind = "SetPropState", prop = "Machine", state = "retreating" },
	},
}

return beats
