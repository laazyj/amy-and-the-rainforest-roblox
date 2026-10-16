--!strict
--[[
	AnalyticsEvents: what the server logs to Roblox Analytics, as plain data
	(plan section 2.3, "Analytics"). The names are the glossary's: a Story
	event is logged under its own name (plan section 2.4), a Fault under
	its name, and the end of a player's visit as SessionEnded with its
	length. src/server/Analytics logs each as a custom event; tier 1 holds
	every Story event and every Fault to a mapping here.

	  forStoryEvent(event)   the Logged for a Story event: its payload's
	                         fields, in the order STORY_FIELDS lists them
	  forFault(name)         the Logged for a Fault: no fields (the reason
	                         is free text, too varied to count by)
	  forSessionEnded(seconds)
	                         the Logged for a visit's end, its value the
	                         whole seconds played

	A custom event carries a value (the count, 1, unless it is a length)
	and up to three custom fields, which the Creator Hub breaks it down by.
]]

local Events = require("./Events")
local Fault = require("./Fault")

export type Logged = { name: string, value: number, fields: { string } }

local AnalyticsEvents = {}

-- Roblox's limit on custom fields per event.
AnalyticsEvents.MAX_FIELDS = 3

AnalyticsEvents.SESSION_ENDED = "SessionEnded"

-- Each Story event's fields, in order: the custom fields it is logged with.
AnalyticsEvents.STORY_FIELDS = table.freeze({
	ChapterStarted = { "chapter" },
	QuestStarted = { "quest" },
	QuestCompleted = { "quest" },
	ChapterCompleted = { "chapter" },
	BeatPlayed = { "beat" },
	StoryEnded = {},
} :: { [string]: { string } })

function AnalyticsEvents.forStoryEvent(event: Events.StoryEvent): Logged
	local names = AnalyticsEvents.STORY_FIELDS[event.kind]
	assert(names, `no analytics event for Story event {event.kind}`)
	local fields = {}
	for _, field in names do
		table.insert(fields, tostring((event :: any)[field]))
	end
	return { name = event.kind, value = 1, fields = fields }
end

function AnalyticsEvents.forFault(name: Fault.Name): Logged
	assert(Fault.NAMES[name], `unknown Fault {name}`)
	return { name = name, value = 1, fields = {} }
end

function AnalyticsEvents.forSessionEnded(seconds: number): Logged
	return { name = AnalyticsEvents.SESSION_ENDED, value = math.max(0, math.floor(seconds)), fields = {} }
end

return AnalyticsEvents
