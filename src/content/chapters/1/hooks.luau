--!strict
-- Chapter One's Beats.

local Story = require("../../../core/Story")

local beats: { [string]: Story.Beat } = {
	-- Sam barks, runs after Amy through the gate (the Wait is his run, 8
	-- to 10 studs, and a beat at her side: at least Story.runSeconds of it,
	-- so the whole run is seen), and both of them end up back in the garden.
	sam_catches = {
		{ kind = "PlayCue", cue = "cue:sam_bark" },
		{ kind = "MoveCharacter", character = "Sam", spot = "GateOutside", run = true },
		{ kind = "Wait", seconds = 1.2 },
		{ kind = "TeleportPlayer", spot = "GardenInside" },
		{ kind = "MoveCharacter", character = "Sam", spot = "SamGuardPost" },
		{ kind = "Wait", seconds = 0.4 },
	},
}

return beats
