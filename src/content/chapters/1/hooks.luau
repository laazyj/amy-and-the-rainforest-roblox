--!strict
-- Chapter One's Beats.

local Story = require("../../../core/Story")

local beats: { [string]: Story.Beat } = {
	-- Sam barks, bounds to the gate, and both of them end up back in the garden.
	sam_catches = {
		{ kind = "PlayCue", cue = "cue:sam_bark" },
		{ kind = "MoveCharacter", character = "Sam", spot = "GateOutside" },
		{ kind = "Wait", seconds = 0.5 },
		{ kind = "TeleportPlayer", spot = "GardenInside" },
		{ kind = "MoveCharacter", character = "Sam", spot = "SamGuardPost" },
		{ kind = "Wait", seconds = 0.4 },
	},
}

return beats
