--!strict
-- Quest Kind `talk`: TalkedTo the Quest's Character. The talk affordance is
-- offered once the intro is done and withdrawn when the player uses it;
-- the engine then shows the Quest's `dialogue`.

local Story = require("../Story")

local DEFAULT_LABEL = "Talk"

local talk: Story.Kind = {
	begin = function(quest)
		return {
			{
				kind = "OfferTalk",
				character = assert(quest.character, "a talk Quest needs a character"),
				label = quest.talkLabel or DEFAULT_LABEL,
			},
		}
	end,
	handle = function(quest, _collected, event)
		if event.kind == "TalkedTo" and event.character == quest.character then
			return { commands = { { kind = "WithdrawTalk", character = event.character } }, done = true }
		end
		return nil
	end,
	objective = function(quest)
		return quest.objective
	end,
}

return talk
