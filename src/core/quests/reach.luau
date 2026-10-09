--!strict
-- Quest Kind `reach`: EnteredZone for the Quest's Zone. Zones are always
-- there, so nothing needs setting up.

local Story = require("../Story")

local reach: Story.Kind = {
	begin = function()
		return {}
	end,
	handle = function(quest, _collected, event)
		if event.kind == "EnteredZone" and event.zone == quest.zone then
			return { commands = {}, done = true }
		end
		return nil
	end,
	objective = function(quest)
		return quest.objective
	end,
}

return reach
