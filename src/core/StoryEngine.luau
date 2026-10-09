--!strict
--[[
	StoryEngine: the Story as a pure function of events (plan section 2.4).

		StoryEngine.step(story, progress, playerEvent)
			-> progress', storyEvents, worldCommands

	No engine, no time: a Wait is a World command the adapter carries out,
	and a Dialogue is shown with ShowDialogue and finished by the Player event
	DialogueFinished. While a Dialogue is showing (`progress.showing`), every
	other Player event is ignored, so a Quest cannot complete under its own
	intro.

	A Quest's life, in the order the commands come out:

	  start     QuestStarted, its onStart Beats, SetObjective, then the intro
	            Dialogue; once that is finished, its Kind's begin commands
	  play      Player events go to its Kind (src/core/quests/<kind>.luau)
	  done      the `dialogue` Dialogue (talk Quests), then the outro
	  complete  QuestCompleted, its onComplete Beats, then the next Quest:
	            in a new Chapter, ChapterCompleted, ChapterStarted and the
	            Chapter card first; after the last, the Ending's Dialogue and
	            then its card

	Progress names the active Quest from the moment it starts, so everything
	sent for a new Quest, its Chapter card included, belongs to it.

	StoryEngine.new wraps the functions for one player, keeping their
	Progress between calls.
]]

local Beat = require("./Beat")
local Events = require("./Events")
local Story = require("./Story")
local WorldState = require("./WorldState")
local collect = require("./quests/collect")
local reach = require("./quests/reach")
local talk = require("./quests/talk")

type PlayerEvent = Events.PlayerEvent
type StoryEvent = Events.StoryEvent
type WorldCommand = Events.WorldCommand

-- Which Dialogue is showing, awaiting DialogueFinished.
export type Showing = "intro" | "dialogue" | "outro" | "ending"

-- Where a player is in the Story. Saved as it is (plan section 2.3).
export type Progress = {
	-- the active Chapter and Quest; nil before the start and after the last Quest
	chapter: string?,
	quest: string?,
	-- completed Quest ids, in story order
	completed: { string },
	-- Pickups touched in the active Quest
	collected: { string },
	showing: Showing?,
	ended: boolean,
}

local StoryEngine = {}

-- How long a Chapter card holds before the Chapter's first Quest starts.
StoryEngine.CHAPTER_CARD_SECONDS = 3.2

StoryEngine.KINDS = table.freeze({ talk = talk, reach = reach, collect = collect }) :: { [Story.QuestKind]: Story.Kind }

type Out = { events: { StoryEvent }, commands: { WorldCommand } }

function StoryEngine.fresh(): Progress
	return { chapter = nil, quest = nil, completed = {}, collected = {}, showing = nil, ended = false }
end

local function copy(progress: Progress): Progress
	local result = table.clone(progress)
	result.completed = table.clone(progress.completed)
	result.collected = table.clone(progress.collected)
	return result
end

local function kindOf(quest: Story.Quest): Story.Kind
	return StoryEngine.KINDS[quest.kind] or error(`{quest.id} has unknown Kind {quest.kind}`)
end

-- Shows `lines` if there are any and remembers which Dialogue it is.
local function show(story: Story.Story, progress: Progress, out: Out, lines: { Story.Line }?, showing: Showing): boolean
	if not lines or #lines == 0 then
		return false
	end
	table.insert(out.commands, { kind = "ShowDialogue", lines = Story.shownLines(story, lines) })
	progress.showing = showing
	return true
end

local function append(out: Out, commands: { WorldCommand })
	table.move(commands, 1, #commands, #out.commands + 1, out.commands)
end

local function startQuest(story: Story.Story, progress: Progress, out: Out, chapter: Story.Chapter, quest: Story.Quest)
	progress.chapter = chapter.id
	progress.quest = quest.id
	progress.collected = {}
	table.insert(out.events, { kind = "QuestStarted", quest = quest.id })
	Beat.play(chapter, quest.hooks and quest.hooks.onStart, out.events, out.commands)
	table.insert(out.commands, { kind = "SetObjective", text = kindOf(quest).objective(quest, progress.collected) })
	if not show(story, progress, out, quest.intro, "intro") then
		append(out, kindOf(quest).begin(quest, progress.collected))
	end
end

local function startChapter(story: Story.Story, progress: Progress, out: Out, chapter: Story.Chapter)
	table.insert(out.events, { kind = "ChapterStarted", chapter = chapter.id })
	table.insert(
		out.commands,
		{ kind = "ShowChapterCard", title = chapter.title, subtitle = chapter.subtitle, ending = false }
	)
	table.insert(out.commands, { kind = "Wait", seconds = StoryEngine.CHAPTER_CARD_SECONDS })
	startQuest(story, progress, out, chapter, chapter.quests[1])
end

local function endStory(story: Story.Story, progress: Progress, out: Out)
	progress.ended = true
	table.insert(
		out.commands,
		{ kind = "ShowChapterCard", title = story.ending.title, subtitle = story.ending.subtitle, ending = true }
	)
	table.insert(out.events, { kind = "StoryEnded" })
end

local function complete(story: Story.Story, progress: Progress, out: Out)
	local quest, chapter = Story.quest(story, progress.quest)
	assert(quest and chapter, "no active Quest to complete")
	table.insert(progress.completed, quest.id)
	table.insert(out.events, { kind = "QuestCompleted", quest = quest.id })
	Beat.play(chapter, quest.hooks and quest.hooks.onComplete, out.events, out.commands)

	local nextQuest, nextChapter = Story.after(story, quest.id)
	if nextChapter ~= chapter then
		table.insert(out.events, { kind = "ChapterCompleted", chapter = chapter.id })
	end
	if nextQuest and nextChapter == chapter then
		startQuest(story, progress, out, chapter, nextQuest)
	elseif nextChapter then
		startChapter(story, progress, out, nextChapter)
	else
		progress.chapter = nil
		progress.quest = nil
		progress.collected = {}
		table.insert(out.commands, { kind = "SetObjective", text = nil })
		if not show(story, progress, out, story.ending.lines, "ending") then
			endStory(story, progress, out)
		end
	end
end

-- The Quest is played: its outro, then completion.
local function finish(story: Story.Story, progress: Progress, out: Out)
	local quest = assert(Story.quest(story, progress.quest))
	if not show(story, progress, out, quest.outro, "outro") then
		complete(story, progress, out)
	end
end

-- Starts the Story from fresh Progress: the first Chapter's card and first
-- Quest. Progress that has already started is returned unchanged.
function StoryEngine.start(story: Story.Story, progress: Progress): (Progress, { StoryEvent }, { WorldCommand })
	local out: Out = { events = {}, commands = {} }
	if progress.quest or progress.ended or #progress.completed > 0 then
		return progress, out.events, out.commands
	end
	local result = copy(progress)
	startChapter(story, result, out, story.chapters[1])
	return result, out.events, out.commands
end

function StoryEngine.step(
	story: Story.Story,
	progress: Progress,
	event: PlayerEvent
): (Progress, { StoryEvent }, { WorldCommand })
	local out: Out = { events = {}, commands = {} }

	if event.kind == "DialogueFinished" then
		local result = copy(progress)
		local showing = result.showing
		result.showing = nil
		if showing == "intro" then
			local quest = assert(Story.quest(story, result.quest))
			append(out, kindOf(quest).begin(quest, result.collected))
		elseif showing == "dialogue" then
			finish(story, result, out)
		elseif showing == "outro" then
			complete(story, result, out)
		elseif showing == "ending" then
			endStory(story, result, out)
		end
		return result, out.events, out.commands
	end

	local quest = Story.quest(story, progress.quest)
	if progress.showing or not quest then
		return progress, out.events, out.commands
	end
	local outcome = kindOf(quest).handle(quest, progress.collected, event)
	if not outcome then
		return progress, out.events, out.commands
	end
	local result = copy(progress)
	result.collected = outcome.collected or result.collected
	append(out, outcome.commands)
	-- Once its Kind is satisfied, a Quest shows its `dialogue` (talk Quests).
	if outcome.done and not show(story, result, out, quest.dialogue, "dialogue") then
		finish(story, result, out)
	end
	return result, out.events, out.commands
end

-- The Progress of a player who has just started Quest `questId`, its intro
-- done: every Quest before it completed, nothing collected, no Dialogue
-- showing. What the Dev shortcuts (src/server/DevShortcuts) jump to and engine tests
-- resume at.
function StoryEngine.progressAt(story: Story.Story, questId: string): Progress
	local progress = StoryEngine.fresh()
	for _, placed in Story.quests(story) do
		if placed.quest.id == questId then
			progress.chapter = placed.chapter.id
			progress.quest = questId
			return progress
		end
		table.insert(progress.completed, placed.quest.id)
	end
	error(`no Quest {questId}`, 2)
end

-- Resume (plan section 2.4): the World commands that rebuild, in a World
-- freshly built from the scenes, the World the active Quest expects: every
-- Beat of the Quests before it and its own onStart Beats, then its Objective
-- and what its Kind sets up. Progress halfway through a Dialogue resumes as
-- the Quest being played; Dialogues are not shown again.
function StoryEngine.resume(story: Story.Story, progress: Progress): { WorldCommand }
	local commands: { WorldCommand } = {}
	local events = {}
	for _, placed in Story.quests(story) do
		local quest = placed.quest
		local hooks: Story.Hooks = quest.hooks or {}
		if table.find(progress.completed, quest.id) then
			Beat.play(placed.chapter, hooks.onStart, events, commands)
			Beat.play(placed.chapter, hooks.onComplete, events, commands)
		elseif quest.id == progress.quest then
			local kind = kindOf(quest)
			Beat.play(placed.chapter, hooks.onStart, events, commands)
			table.insert(commands, { kind = "SetObjective", text = kind.objective(quest, progress.collected) })
			local begun = kind.begin(quest, progress.collected)
			table.move(begun, 1, #begun, #commands + 1, commands)
		end
	end
	local state = WorldState.initial(story)
	for _, command in commands do
		WorldState.apply(story, state, command)
	end
	return WorldState.commands(story, state)
end

--[[ One player's Story: the functions above with their Progress kept. ]]

local Engine = {}
Engine.__index = Engine

export type Engine = typeof(setmetatable({} :: { playerId: number, story: Story.Story, progress: Progress }, Engine))

function StoryEngine.new(playerId: number, progress: Progress?, story: Story.Story): Engine
	return setmetatable({ playerId = playerId, story = story, progress = progress or StoryEngine.fresh() }, Engine)
end

local function keep(self: Engine, progress: Progress, events: { StoryEvent }, commands: { WorldCommand })
	self.progress = progress
	return copy(progress), events, commands
end

function Engine.start(self: Engine): (Progress, { StoryEvent }, { WorldCommand })
	return keep(self, StoryEngine.start(self.story, self.progress))
end

function Engine.step(self: Engine, event: PlayerEvent): (Progress, { StoryEvent }, { WorldCommand })
	return keep(self, StoryEngine.step(self.story, self.progress, event))
end

function Engine.snapshot(self: Engine): Progress
	return copy(self.progress)
end

-- The active Quest's id ("chapter1.ask_dad") and Quest; nil when none is.
function Engine.activeQuest(self: Engine): (string?, Story.Quest?)
	local quest = Story.quest(self.story, self.progress.quest)
	return if quest then quest.id else nil, quest
end

return StoryEngine
