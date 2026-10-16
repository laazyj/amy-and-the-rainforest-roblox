--!strict
--[[
	ObjectiveText: what the Objective tracker shows for a SetObjective, as
	plain data (plan section 2.1). The client binder renders it.

	An Objective is shown under HEADER with the space around it
	trimmed (HEADER and ICON_MARK are plain ASCII, which every font of
	the client has); no text, or only space, hides the tracker. Each Objective
	shown "pops": the tracker starts opaque and fades to its resting
	transparency, so the player notices the change.
]]

export type View = { visible: boolean, text: string }

local ObjectiveText = {}

ObjectiveText.HEADER = "Objective"
-- The collapsed tracker's icon on a Phone: a drawn gold marker with this
-- mark on it, a character every font of the client has.
ObjectiveText.ICON_MARK = "!"

-- The pop: from fully opaque to the resting background transparency.
ObjectiveText.POP_SECONDS = 0.6
ObjectiveText.RESTING_TRANSPARENCY = 0.25

function ObjectiveText.view(text: string?): View
	local trimmed = if text then string.match(text, "^%s*(.-)%s*$") :: string else ""
	return { visible = trimmed ~= "", text = trimmed }
end

return ObjectiveText
