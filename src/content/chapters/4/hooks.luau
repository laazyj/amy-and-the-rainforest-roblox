--!strict
-- Chapter Four's Beats.

local Story = require("../../../core/Story")

local beats: { [string]: Story.Beat } = {
	-- Amy wins: the blade stops, the crowd cheers, the machine backs away,
	-- seen wide from behind her; the Shot holds through the Ending's Lines.
	machine_stops = {
		{ kind = "FrameShot", shot = "MachineFinale" },
		{ kind = "SetPropState", prop = "Machine", state = "stopped" },
		{ kind = "PlayCue", cue = "cue:machine_stop" },
		{ kind = "SetPropState", prop = "Villagers", state = "cheering" },
		{ kind = "SetPropState", prop = "Machine", state = "retreating" },
	},
}

return beats
