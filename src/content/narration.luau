--!strict
--[[
	The Narration table (src/core/Narration): each Chapter's narration file,
	narration:<chapter id>, with the part of it that reads each canon Line,
	in seconds. Empty until the recordings arrive, so every Line is shown as
	text only. Adding a Chapter's recording is its file in the manifest and
	an entry here, every canon Line of the Chapter in order:

		["narration:chapter1"] = {
			{ text = "One beautyfull sunday, Amy asked to go outside.", from = 0, to = 3.4 },
			...
		},
]]

local Narration = require("../core/Narration")

local narration: Narration.Table = {}

return narration
