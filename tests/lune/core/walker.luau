--[[
	Walks a Story through StoryEngine as a player would: finishes every
	Dialogue, and plays the active Quest by its Kind (talks to its Character,
	enters its Zone, touches its Pickups in order). Records every step, and
	the WorldState at the moment each Quest becomes playable.
]]

local Events = require("../../../src/core/Events")
local Story = require("../../../src/core/Story")
local StoryEngine = require("../../../src/core/StoryEngine")
local WorldState = require("../../../src/core/WorldState")

export type Step = {
	-- the active Quest after the step
	quest: string?,
	event: Events.PlayerEvent?,
	events: { Events.StoryEvent },
	commands: { Events.WorldCommand },
}
export type Walk = {
	steps: { Step },
	progress: StoryEngine.Progress,
	-- Quest id -> the World and Progress when it became playable
	playable: { [string]: { world: WorldState.WorldState, progress: StoryEngine.Progress } },
}

local MAX_STEPS = 500

local Walker = {}

function Walker.deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in value do
		result[key] = Walker.deepCopy(item)
	end
	return result
end

-- The Player event that plays `quest` on, given the Pickups touched so far.
function Walker.playerEvent(quest: Story.Quest, collected: { string }): Events.PlayerEvent
	if quest.kind == "talk" then
		return { kind = "TalkedTo", character = assert(quest.character, quest.id) }
	elseif quest.kind == "reach" then
		return { kind = "EnteredZone", zone = assert(quest.zone, quest.id) }
	end
	for _, pickup in assert(quest.pickups, quest.id) do
		if not table.find(collected, pickup) then
			return { kind = "TouchedPickup", pickup = pickup }
		end
	end
	error(`{quest.id} has no Pickup left to touch`)
end

-- Walks from `progress` (fresh when nil) to the end of the Story. `world`
-- is the World the walk starts in: the scenes' initial World when nil.
-- Errors when the Story stops moving (a dead end) or runs too long.
function Walker.walk(story: Story.Story, progress: StoryEngine.Progress?, world: WorldState.WorldState?): Walk
	local state = world or WorldState.initial(story)
	local walk: Walk = { steps = {}, progress = progress or StoryEngine.fresh(), playable = {} }

	local function markPlayable(next: StoryEngine.Progress)
		if next.quest and not next.showing and not walk.playable[next.quest] then
			walk.playable[next.quest] = { world = Walker.deepCopy(state), progress = Walker.deepCopy(next) }
		end
	end

	local function record(event: Events.PlayerEvent?, next: StoryEngine.Progress, events, commands)
		walk.progress = next
		for _, command in commands do
			WorldState.apply(story, state, command)
		end
		table.insert(walk.steps, { quest = next.quest, event = event, events = events, commands = commands })
		markPlayable(next)
	end

	if not walk.progress.quest and not walk.progress.ended then
		record(nil, StoryEngine.start(story, walk.progress))
	else
		markPlayable(walk.progress)
	end
	while not walk.progress.ended do
		if #walk.steps > MAX_STEPS then
			error(`no Ending after {MAX_STEPS} steps`)
		end
		local event: Events.PlayerEvent
		if walk.progress.showing then
			event = { kind = "DialogueFinished" }
		else
			local quest = Story.quest(story, walk.progress.quest)
			if not quest then
				error(`dead end: no Dialogue showing and no active Quest after {#walk.steps} steps`)
			end
			event = Walker.playerEvent(quest, walk.progress.collected)
		end
		local before = walk.progress
		local next, events, commands = StoryEngine.step(story, before, event)
		if next == before then
			error(`dead end: {event.kind} changed nothing at {tostring(before.quest)}`)
		end
		record(event, next, events, commands)
	end
	return walk
end

-- The World freshly built from the scenes, after `commands`.
function Walker.rebuild(story: Story.Story, commands: { Events.WorldCommand }): WorldState.WorldState
	local state = WorldState.initial(story)
	for _, command in commands do
		WorldState.apply(story, state, command)
	end
	return state
end

-- A WorldState without the Player Character's position, which Resume leaves
-- to the player.
function Walker.withoutPlayer(world: WorldState.WorldState): WorldState.WorldState
	local copy = Walker.deepCopy(world)
	copy.player = nil
	return copy
end

-- The kind of each command or event in `list`, in order.
function Walker.kinds(list: { any }): { string }
	local kinds = {}
	for _, item in list do
		table.insert(kinds, item.kind)
	end
	return kinds
end

return Walker
