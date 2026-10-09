--!strict
-- Quest Kind `collect`: TouchedPickup for `count` of the Quest's Pickups,
-- which spawn at its `pickups` Spots once the intro is done. A Pickup's id
-- is the Spot it spawned at. The Objective counts them: "Find them  (1/3)".
-- On a Resume, the Pickups already touched are removed again.

local Events = require("../Events")
local Story = require("../Story")

local function count(quest: Story.Quest): number
	return assert(quest.count, "a collect Quest needs a count")
end

local collect: Story.Kind
collect = {
	begin = function(quest, collected)
		local commands: { Events.WorldCommand } = { { kind = "SpawnPickups", quest = quest.id } }
		for _, pickup in collected do
			table.insert(commands, { kind = "RemovePickup", pickup = pickup })
		end
		return commands
	end,
	handle = function(quest, collected, event)
		if
			event.kind ~= "TouchedPickup"
			or not table.find(quest.pickups or {}, event.pickup)
			or table.find(collected, event.pickup)
		then
			return nil
		end
		local now = table.clone(collected)
		table.insert(now, event.pickup)
		return {
			commands = {
				{ kind = "RemovePickup", pickup = event.pickup },
				{ kind = "SetObjective", text = collect.objective(quest, now) },
			},
			collected = now,
			done = #now >= count(quest),
		}
	end,
	objective = function(quest, collected)
		return `{quest.objective}  ({#collected}/{count(quest)})`
	end,
}

return collect
