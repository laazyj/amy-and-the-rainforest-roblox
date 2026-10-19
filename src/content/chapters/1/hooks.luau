--!strict
-- Chapter One's Beats.

local Story = require("../../../core/Story")

local beats: { [string]: Story.Beat } = {
	-- Sam barks, runs after Amy to the gate (the Wait is his run, about 8
	-- studs, and a beat at her side), and both of them end up back in the
	-- garden.
	sam_catches = {
		{ kind = "PlayCue", cue = "cue:sam_bark" },
		{ kind = "MoveCharacter", character = "Sam", spot = "GateOutside", run = true },
		{ kind = "Wait", seconds = 1 },
		{ kind = "TeleportPlayer", spot = "GardenInside" },
		{ kind = "MoveCharacter", character = "Sam", spot = "SamGuardPost" },
		{ kind = "Wait", seconds = 0.4 },
	},
}

return beats
