--!strict
--[[
	Events: the three kinds of message the core speaks (glossary section 3).

	  Player events  come in from the adapter, in the player's terms
	  Story events   go out as facts about the story
	  World commands go out as instructions to the engine

	Each is a tagged table, `kind` naming it. The schemas below list every
	field of every kind with its type, and `check` holds a value to them, so
	an adapter or a test can reject a malformed message by name.
]]

-- A Line as the client shows it: the Speaker's display name and the text.
export type ShownLine = { speaker: string, text: string }

export type PlayerEvent =
	{ kind: "EnteredZone", zone: string }
	| { kind: "TalkedTo", character: string }
	| { kind: "TouchedPickup", pickup: string }
	| { kind: "DialogueFinished" }

export type StoryEvent =
	{ kind: "ChapterStarted", chapter: string }
	| { kind: "QuestStarted", quest: string }
	| { kind: "QuestCompleted", quest: string }
	| { kind: "ChapterCompleted", chapter: string }
	| { kind: "BeatPlayed", beat: string }
	| { kind: "StoryEnded" }

export type WorldCommand =
	{ kind: "ShowDialogue", lines: { ShownLine } }
	| { kind: "SetObjective", text: string? }
	| { kind: "ShowChapterCard", title: string, subtitle: string, ending: boolean }
	| { kind: "MoveCharacter", character: string, spot: string }
	| { kind: "TeleportPlayer", spot: string }
	| { kind: "SetPropState", prop: string, state: string }
	| { kind: "SetLighting", preset: string }
	| { kind: "SpawnPickups", quest: string }
	| { kind: "RemovePickup", pickup: string }
	| { kind: "ClearPickups", quest: string }
	| { kind: "OfferTalk", character: string, label: string }
	| { kind: "WithdrawTalk", character: string }
	| { kind: "Wait", seconds: number }

-- A field's type: "string", "number", "boolean", "lines" (a non-empty list
-- of ShownLines), and "string?" for a string that may be absent.
export type FieldType = "string" | "string?" | "number" | "boolean" | "lines"
export type Schemas = { [string]: { [string]: FieldType } }

local Events = {}

Events.PLAYER_EVENTS = table.freeze({
	EnteredZone = { zone = "string" },
	TalkedTo = { character = "string" },
	TouchedPickup = { pickup = "string" },
	DialogueFinished = {},
} :: Schemas)

Events.STORY_EVENTS = table.freeze({
	ChapterStarted = { chapter = "string" },
	QuestStarted = { quest = "string" },
	QuestCompleted = { quest = "string" },
	ChapterCompleted = { chapter = "string" },
	BeatPlayed = { beat = "string" },
	StoryEnded = {},
} :: Schemas)

Events.WORLD_COMMANDS = table.freeze({
	ShowDialogue = { lines = "lines" },
	SetObjective = { text = "string?" },
	ShowChapterCard = { title = "string", subtitle = "string", ending = "boolean" },
	MoveCharacter = { character = "string", spot = "string" },
	TeleportPlayer = { spot = "string" },
	SetPropState = { prop = "string", state = "string" },
	SetLighting = { preset = "string" },
	SpawnPickups = { quest = "string" },
	RemovePickup = { pickup = "string" },
	ClearPickups = { quest = "string" },
	OfferTalk = { character = "string", label = "string" },
	WithdrawTalk = { character = "string" },
	Wait = { seconds = "number" },
} :: Schemas)

local function isShownLine(value: any): boolean
	if type(value) ~= "table" or type(value.speaker) ~= "string" or type(value.text) ~= "string" then
		return false
	end
	for key in value do
		if key ~= "speaker" and key ~= "text" then
			return false
		end
	end
	return true
end

-- Whether `value` has the type `fieldType`.
function Events.matches(fieldType: string, value: any): boolean
	if fieldType == "string?" then
		return value == nil or type(value) == "string"
	elseif fieldType == "lines" then
		if type(value) ~= "table" or #value == 0 then
			return false
		end
		for key, line in value do
			if type(key) ~= "number" or not isShownLine(line) then
				return false
			end
		end
		return true
	end
	return type(value) == fieldType
end

-- Holds `message` to `schemas`: a known kind, every field of its type, and no
-- other field. Returns false and the reason when it does not hold.
function Events.check(schemas: Schemas, message: any): (boolean, string?)
	if type(message) ~= "table" then
		return false, `expected a table, got {typeof(message)}`
	end
	local schema = schemas[message.kind]
	if not schema then
		return false, `unknown kind {tostring(message.kind)}`
	end
	for field, fieldType in schema do
		if not Events.matches(fieldType, message[field]) then
			return false, `{message.kind}.{field} must be {fieldType}, got {typeof(message[field])}`
		end
	end
	for field in message do
		if field ~= "kind" and schema[field] == nil then
			return false, `{message.kind} has no field {tostring(field)}`
		end
	end
	return true, nil
end

return Events
