--!strict
--[[
	World: the one interface the core uses to act on the engine, one method
	per World command. The server adapter implements it (src/server/WorldImpl);
	a test can implement it with a table that records the calls.
]]

local Events = require("./Events")

export type World = {
	showDialogue: (lines: { Events.ShownLine }) -> (),
	setObjective: (text: string?) -> (),
	showChapterCard: (title: string, subtitle: string, ending: boolean) -> (),
	moveCharacter: (character: string, spot: string) -> (),
	teleportPlayer: (spot: string) -> (),
	setPropState: (prop: string, state: string) -> (),
	setLighting: (preset: string) -> (),
	spawnPickups: (quest: string) -> (),
	removePickup: (pickup: string) -> (),
	clearPickups: (quest: string) -> (),
	offerTalk: (character: string, label: string) -> (),
	withdrawTalk: (character: string) -> (),
	wait: (seconds: number) -> (),
}

local World = {}

-- Carries out `command` through `world`.
function World.execute(world: World, command: Events.WorldCommand)
	if command.kind == "ShowDialogue" then
		world.showDialogue(command.lines)
	elseif command.kind == "SetObjective" then
		world.setObjective(command.text)
	elseif command.kind == "ShowChapterCard" then
		world.showChapterCard(command.title, command.subtitle, command.ending)
	elseif command.kind == "MoveCharacter" then
		world.moveCharacter(command.character, command.spot)
	elseif command.kind == "TeleportPlayer" then
		world.teleportPlayer(command.spot)
	elseif command.kind == "SetPropState" then
		world.setPropState(command.prop, command.state)
	elseif command.kind == "SetLighting" then
		world.setLighting(command.preset)
	elseif command.kind == "SpawnPickups" then
		world.spawnPickups(command.quest)
	elseif command.kind == "RemovePickup" then
		world.removePickup(command.pickup)
	elseif command.kind == "ClearPickups" then
		world.clearPickups(command.quest)
	elseif command.kind == "OfferTalk" then
		world.offerTalk(command.character, command.label)
	elseif command.kind == "WithdrawTalk" then
		world.withdrawTalk(command.character)
	elseif command.kind == "Wait" then
		world.wait(command.seconds)
	end
end

return World
