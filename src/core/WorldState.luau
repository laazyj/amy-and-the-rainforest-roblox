--!strict
--[[
	WorldState: what the World looks like to the Story, as plain data, and
	how World commands change it. It is the meaning of the commands without
	the engine: tests compare the state a walk produces with the state Resume
	produces, and Resume turns a state back into the commands that rebuild it.
]]

local Events = require("./Events")
local Story = require("./Story")

type WorldCommand = Events.WorldCommand

export type WorldState = {
	-- Character id -> the Spot it stands at
	characters: { [string]: string },
	-- Prop id -> its state
	props: { [string]: string },
	lighting: string,
	-- Quest id -> its Pickups still in the world
	pickups: { [string]: { [string]: true } },
	objective: string?,
	-- Character id -> the label on its offered talk affordance
	talk: { [string]: string },
	-- the Spot the Player Character was last put at, if any
	player: string?,
}

local WorldState = {}

-- The World as the scenes build it: every Character at home, every Prop in
-- its first state, the initial Lighting preset.
function WorldState.initial(story: Story.Story): WorldState
	local state: WorldState = {
		characters = {},
		props = {},
		lighting = story.initialLighting,
		pickups = {},
		objective = nil,
		talk = {},
		player = nil,
	}
	for _, character in story.characters do
		if not character.player then
			state.characters[character.id] = character.home
		end
	end
	for id, prop in story.props do
		state.props[id] = prop.states[1]
	end
	return state
end

-- Applies `command` to `state` in place. Commands that only show something
-- (dialogue, chapter cards) or pass time leave it as it is.
function WorldState.apply(story: Story.Story, state: WorldState, command: WorldCommand)
	if command.kind == "MoveCharacter" then
		state.characters[command.character] = command.spot
	elseif command.kind == "TeleportPlayer" then
		state.player = command.spot
	elseif command.kind == "SetPropState" then
		state.props[command.prop] = command.state
	elseif command.kind == "SetLighting" then
		state.lighting = command.preset
	elseif command.kind == "SetObjective" then
		state.objective = command.text
	elseif command.kind == "OfferTalk" then
		state.talk[command.character] = command.label
	elseif command.kind == "WithdrawTalk" then
		state.talk[command.character] = nil
	elseif command.kind == "SpawnPickups" then
		local quest = assert(Story.quest(story, command.quest), command.quest)
		local spawned: { [string]: true } = {}
		for _, pickup in (quest.pickups or {}) :: { string } do
			spawned[pickup] = true
		end
		state.pickups[command.quest] = spawned
	elseif command.kind == "RemovePickup" then
		for _, spawned in state.pickups do
			spawned[command.pickup] = nil
		end
	elseif command.kind == "ClearPickups" then
		state.pickups[command.quest] = nil
	end
end

local function sortedKeys(map: { [string]: any }): { string }
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- The commands that rebuild `state` in a World freshly built from the
-- scenes, in a fixed order: Characters, Props, Lighting, Pickups, Objective,
-- talk affordances. Where the Player Character stands is left to the player.
function WorldState.commands(story: Story.Story, state: WorldState): { WorldCommand }
	local commands: { WorldCommand } = {}
	for _, character in story.characters do
		local spot = state.characters[character.id]
		if spot then
			table.insert(commands, { kind = "MoveCharacter", character = character.id, spot = spot })
		end
	end
	for _, prop in sortedKeys(state.props) do
		table.insert(commands, { kind = "SetPropState", prop = prop, state = state.props[prop] })
	end
	table.insert(commands, { kind = "SetLighting", preset = state.lighting })
	for _, questId in sortedKeys(state.pickups) do
		table.insert(commands, { kind = "SpawnPickups", quest = questId })
		local quest = assert(Story.quest(story, questId), questId)
		for _, pickup in (quest.pickups or {}) :: { string } do
			if not state.pickups[questId][pickup] then
				table.insert(commands, { kind = "RemovePickup", pickup = pickup })
			end
		end
	end
	table.insert(commands, { kind = "SetObjective", text = state.objective })
	for _, character in sortedKeys(state.talk) do
		table.insert(commands, { kind = "OfferTalk", character = character, label = state.talk[character] })
	end
	return commands
end

return WorldState
