--!strict
--[[
	Save: what a player's Save holds, as plain data (plan sections 2.3 and
	2.4). One Save per player (one slot): their Progress and a Checkpoint
	for each Chapter they have reached, under a schema version.
	src/server/Persist stores it with ProfileStore; this module never
	touches a store.

	  read     stored data -> a Save of this version, through the
	           Migrations; nil and why when it cannot be read
	  open     what a server plays from the stored data: `read`, or for
	           data that is not a Save at all, a new Save keeping it aside
	  write    a Save -> the data to store
	  record   a Save with new Progress and its Chapters' Checkpoints;
	           never unstarted Progress over a started Save
	  restore  the Progress a Resume starts from

	Schema versions. A Migration turns a Save of version n into version
	n + 1; each has a tier 1 test (tests/lune/core/Save.spec.luau).

	  1  { version = 1, progress = Progress }
	  2  adds `checkpoints`: Chapter id -> the Progress when it started

	Rolling back one version (plan section 3). A version only ever adds
	fields, so code of version N reads a version N + 1 Save as its own:
	it keeps the fields it does not know and the version number, so its
	writes lose nothing the newer code needs. A Save two or more versions
	newer is not read, and Persist then never writes over it.

	Data that is no Save of any version (corrupt, or hand-edited) is kept
	whole under `unreadable` in a new Save, so it can be repaired by hand,
	and the player starts the Story afresh rather than never saving again.
]]

local Story = require("./Story")
local StoryEngine = require("./StoryEngine")

type Progress = StoryEngine.Progress

export type Save = {
	version: number,
	progress: Progress,
	-- Chapter id -> the Progress when the Chapter started
	checkpoints: { [string]: Progress },
	-- fields of a newer version, kept as they were read
	[string]: any,
}

local Save = {}

Save.VERSION = 2

-- The Chapters, in order, that `progress` has reached.
local function reached(story: Story.Story, progress: Progress): { Story.Chapter }
	local chapters = {}
	if not StoryEngine.started(progress) then
		return chapters
	end
	for _, chapter in story.chapters do
		table.insert(chapters, chapter)
		if chapter.id == progress.chapter then
			break
		end
	end
	return chapters
end

-- The Checkpoint of a player who has just started `chapter`.
local function startOf(story: Story.Story, chapter: Story.Chapter): Progress
	return StoryEngine.progressAt(story, chapter.quests[1].id)
end

type Migration = (story: Story.Story, data: { [string]: any }) -> { [string]: any }

-- Migrations[n] turns a Save of version n into one of version n + 1.
Save.MIGRATIONS = {
	-- 1 -> 2: a Checkpoint for every Chapter the Progress has reached.
	[1] = function(story: Story.Story, data: { [string]: any }): { [string]: any }
		local checkpoints = {}
		for _, chapter in reached(story, data.progress) do
			checkpoints[chapter.id] = startOf(story, chapter)
		end
		data.checkpoints = checkpoints
		data.version = 2
		return data
	end,
} :: { [number]: Migration }

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in value do
		result[key] = copy(item)
	end
	return result
end

local function isStrings(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	for key, item in value do
		if type(key) ~= "number" or type(item) ~= "string" then
			return false
		end
	end
	return true
end

-- Why `value` is not a Progress, or nil when it is one.
local function progressProblem(value: any): string?
	if type(value) ~= "table" then
		return `expected a table, got {typeof(value)}`
	elseif value.chapter ~= nil and type(value.chapter) ~= "string" then
		return "chapter must be a string"
	elseif value.quest ~= nil and type(value.quest) ~= "string" then
		return "quest must be a string"
	elseif not isStrings(value.completed) or not isStrings(value.collected) then
		return "completed and collected must be lists of ids"
	elseif value.showing ~= nil and not (StoryEngine.SHOWINGS :: any)[value.showing] then
		return `showing cannot be {tostring(value.showing)}`
	elseif type(value.ended) ~= "boolean" then
		return "ended must be a boolean"
	end
	return nil
end

-- A Save with fresh Progress and no Checkpoints: a player who has not
-- started.
function Save.new(): Save
	return { version = Save.VERSION, progress = StoryEngine.fresh(), checkpoints = {} }
end

-- Stored data as a Save of this version, migrated as needed. An empty table,
-- which is what ProfileStore gives a new player, is a new Save. Nil and the
-- reason when the data is not a Save, or is two or more versions newer.
function Save.read(story: Story.Story, stored: any): (Save?, string?)
	if type(stored) ~= "table" then
		return nil, `a Save is a table, not {typeof(stored)}`
	elseif next(stored) == nil then
		return Save.new(), nil
	end
	local version = stored.version
	if type(version) ~= "number" or version < 1 or version % 1 ~= 0 then
		return nil, `unknown schema version {tostring(version)}`
	elseif version > Save.VERSION + 1 then
		return nil, `schema version {version} is newer than {Save.VERSION} + 1`
	end
	local problem = progressProblem(stored.progress)
	if problem then
		return nil, `progress: {problem}`
	end
	local data = copy(stored)
	for from = version, Save.VERSION - 1 do
		data = Save.MIGRATIONS[from](story, data)
	end
	if type(data.checkpoints) ~= "table" then
		return nil, "checkpoints must be a table"
	end
	for chapter, checkpoint in data.checkpoints do
		local wrong = if type(chapter) == "string" then progressProblem(checkpoint) else "not a Chapter id"
		if wrong then
			return nil, `checkpoint {tostring(chapter)}: {wrong}`
		end
	end
	return data :: Save, nil
end

-- Whether `stored` claims a schema version newer than this code's: never
-- to be written over, whether this code can read it (one newer) or not.
local function newer(stored: any): boolean
	return type(stored) == "table" and type(stored.version) == "number" and stored.version > Save.VERSION
end

-- What a server plays from `stored`: the Save `read` gives; for data that
-- is no Save of any version, a new Save keeping it under `unreadable`, and
-- why; nil and why for a Save too new to read, which must not be written.
function Save.open(story: Story.Story, stored: any): (Save?, string?)
	local save, reason = Save.read(story, stored)
	if save then
		return save, nil
	elseif newer(stored) then
		return nil, reason
	end
	local fresh = Save.new()
	fresh.unreadable = copy(stored)
	return fresh, reason
end

-- The data to store for `save`: plain tables only, nothing shared with it.
function Save.write(save: Save): { [string]: any }
	return copy(save)
end

-- Whether the player has started the Story.
function Save.started(save: Save): boolean
	return StoryEngine.started(save.progress)
end

-- `save` with `progress`: a Checkpoint for each Chapter the Progress has
-- reached, the one already taken kept, and none for a Chapter after it. A
-- Chapter reached without being started (a Dev shortcut's jump) gets the
-- Checkpoint of a player who has just started it.
function Save.record(story: Story.Story, save: Save, progress: Progress): Save
	if Save.started(save) and not StoryEngine.started(progress) then
		-- a session that has not begun (the Title screen still showing) has
		-- nothing to save; only a new Save, Start again, is unstarted
		return save
	end
	local result = table.clone(save)
	result.progress = copy(progress)
	local checkpoints = {}
	for _, chapter in reached(story, progress) do
		local kept = save.checkpoints[chapter.id]
		checkpoints[chapter.id] = if kept then copy(kept) else startOf(story, chapter)
	end
	result.checkpoints = checkpoints
	return result
end

-- The Progress of a player who has seen the Ending.
local function ended(story: Story.Story): Progress
	local progress = StoryEngine.fresh()
	for _, placed in Story.quests(story) do
		table.insert(progress.completed, placed.quest.id)
	end
	progress.ended = true
	return progress
end

-- The Progress a Resume of `progress` starts from, held to the Story as it
-- is now. The active Quest is resumed as just started, with every Quest
-- before it completed and the Pickups it had touched; a Dialogue that was
-- showing is not shown again. A Quest the Story no longer has resumes at
-- the first Quest not completed; a save made during the Ending has ended.
function Save.restore(story: Story.Story, progress: Progress): Progress
	if progress.ended or progress.showing == "ending" then
		return ended(story)
	elseif not StoryEngine.started(progress) then
		return StoryEngine.fresh()
	end
	local quest = Story.quest(story, progress.quest)
	if not quest then
		for _, placed in Story.quests(story) do
			if not table.find(progress.completed, placed.quest.id) then
				return StoryEngine.progressAt(story, placed.quest.id)
			end
		end
		return ended(story)
	end
	local result = StoryEngine.progressAt(story, quest.id)
	local pickups = quest.pickups or {}
	for _, pickup in progress.collected do
		if table.find(pickups, pickup) then
			table.insert(result.collected, pickup)
		end
	end
	return result
end

return Save
