--!strict
-- Chapter Three's Beats.

local Story = require("../../../core/Story")

local beats: { [string]: Story.Beat } = {
	-- Amy meets each animal: it in full, facing her, before they talk.
	meet_squirrel = {
		{ kind = "FrameShot", shot = "MeetCharacter", character = "Squirrel" },
	},
	meet_fox = {
		{ kind = "FrameShot", shot = "MeetCharacter", character = "Fox" },
	},
	meet_lion = {
		{ kind = "FrameShot", shot = "MeetCharacter", character = "Lion" },
	},
	-- Back home: the ordinary world is a little greyer than she remembered.
	ordinary_world = {
		{ kind = "SetLighting", preset = "ordinary" },
	},
	-- The village arrives with the machine; Dad, Mum and Sam go to the field.
	machine_arrives = {
		{ kind = "SetPropState", prop = "Machine", state = "advancing" },
		{ kind = "SetPropState", prop = "Villagers", state = "gathered" },
		{ kind = "MoveCharacter", character = "Dad", spot = "DadAtMachine" },
		{ kind = "MoveCharacter", character = "Mum", spot = "MumAtMachine" },
		{ kind = "MoveCharacter", character = "Sam", spot = "SamAtMachine" },
	},
}

return beats
