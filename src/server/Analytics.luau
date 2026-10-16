--!strict
--[[
	Analytics: logs what src/core/AnalyticsEvents maps to Roblox Analytics
	custom events (AnalyticsService:LogCustomEvent), for a player. StoryHost
	logs each Story event, a player's joining and their leaving (with the
	length of their visit); FaultLog logs each Fault. docs/ANALYTICS.md says
	what to watch and where in the Creator Hub.

	  storyEvents(player, events)  each Story event of a step
	  fault(name, player)          a Fault; one of the whole server (no
	                               player) is logged for each player who
	                               joins it, as they are the ones it affects
	  joined(player), left(player) a visit; left logs SessionEnded

	A custom event needs a real Player, so a fake player in an engine test
	is never sent to AnalyticsService; and logging never stops the Story:
	a failure is a warning line. The last few events logged are kept, for
	the engine tests, and `setSend` replaces the call to AnalyticsService.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = ReplicatedStorage:WaitForChild("core")
local AnalyticsEvents = require(Core:WaitForChild("AnalyticsEvents"))
local Events = require(Core:WaitForChild("Events"))
local Fault = require(Core:WaitForChild("Fault"))

export type Entry = { player: any, logged: AnalyticsEvents.Logged }

local KEPT = 100

-- The custom fields' keys, in order.
local FIELD_KEYS = {
	Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
}

local Analytics = {}

-- The last KEPT events logged, oldest first.
Analytics.logged = {} :: { Entry }

-- Faults of the whole server, logged for each player who joins it.
local serverFaults: { Fault.Name } = {}
-- When each player joined (os.clock()).
local joinedAt: { [any]: number } = {}

local send = function(player: any, logged: AnalyticsEvents.Logged)
	if not (typeof(player) == "Instance" and player:IsA("Player")) then
		return
	end
	local fields = {}
	for i, field in logged.fields do
		fields[FIELD_KEYS[i]] = field
	end
	local ok, why = pcall(AnalyticsService.LogCustomEvent, AnalyticsService, player, logged.name, logged.value, fields)
	if not ok then
		warn(`[Analytics] {logged.name} not logged: {why}`)
	end
end

function Analytics.setSend(replacement: (player: any, logged: AnalyticsEvents.Logged) -> ())
	send = replacement
end

local function log(player: any, logged: AnalyticsEvents.Logged)
	table.insert(Analytics.logged, { player = player, logged = logged })
	if #Analytics.logged > KEPT then
		table.remove(Analytics.logged, 1)
	end
	send(player, logged)
end

function Analytics.storyEvents(player: any, events: { Events.StoryEvent })
	for _, event in events do
		log(player, AnalyticsEvents.forStoryEvent(event))
	end
end

function Analytics.fault(name: Fault.Name, player: any?)
	if player then
		log(player, AnalyticsEvents.forFault(name))
	elseif not table.find(serverFaults, name) then
		table.insert(serverFaults, name)
		for present in joinedAt do
			log(present, AnalyticsEvents.forFault(name))
		end
	end
end

function Analytics.joined(player: any)
	joinedAt[player] = os.clock()
	for _, name: Fault.Name in serverFaults do
		log(player, AnalyticsEvents.forFault(name))
	end
end

function Analytics.left(player: any)
	local since = joinedAt[player]
	joinedAt[player] = nil
	if since then
		log(player, AnalyticsEvents.forSessionEnded(os.clock() - since))
	end
end

return Analytics
