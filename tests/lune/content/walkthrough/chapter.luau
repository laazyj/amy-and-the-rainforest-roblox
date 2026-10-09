--[[
	Walks one Chapter as a player would, from its Checkpoint: a Resume at
	its first Quest, then the walk (tests/lune/core/walker.luau) until the
	Chapter completes. Each Chapter's walkthrough spec reads what happened.
]]

local Events = require("../../../../src/core/Events")
local Story = require("../../../../src/content/Story")
local StoryEngine = require("../../../../src/core/StoryEngine")
local Walker = require("../../core/walker")
local WorldState = require("../../../../src/core/WorldState")

local story = Story.story

export type ChapterWalk = {
	-- the Quests completed, in order
	quests: { string },
	-- the Player events played, Dialogues aside: "TalkedTo(Dad)"
	played: { string },
	-- every Objective shown, in order
	objectives: { string },
	beats: { string },
	-- the World when the Chapter completes
	world: WorldState.WorldState,
	-- the Story event that follows ChapterCompleted
	next: string,
}

-- "TalkedTo(Dad)"; an event without a payload by its kind alone.
local function describeEvent(event: any): string
	local schema = Events.PLAYER_EVENTS[event.kind] or Events.STORY_EVENTS[event.kind] or {}
	local field = next(schema)
	return if field then `{event.kind}({event[field]})` else event.kind
end

-- The commands of a step up to the next Chapter's card: the step that
-- completes a Chapter goes on to start the next one.
local function beforeChapterCard(commands: { Events.WorldCommand }): { Events.WorldCommand }
	for i, command in commands do
		if command.kind == "ShowChapterCard" then
			return table.move(commands, 1, i - 1, 1, {})
		end
	end
	return commands
end

local Chapter = {}

function Chapter.walk(id: string): ChapterWalk
	local chapter
	for _, candidate in story.chapters do
		if candidate.id == id then
			chapter = candidate
		end
	end
	assert(chapter, `no Chapter {id}`)
	local checkpoint = StoryEngine.progressAt(story, chapter.quests[1].id)
	local resume = StoryEngine.resume(story, checkpoint)
	local walk = Walker.walk(story, checkpoint, Walker.rebuild(story, resume))

	local result: ChapterWalk = {
		quests = {},
		played = {},
		objectives = {},
		beats = {},
		world = Walker.rebuild(story, resume),
		next = "",
	}
	local function objectives(commands: { Events.WorldCommand })
		for _, command in commands do
			if command.kind == "SetObjective" and command.text then
				table.insert(result.objectives, command.text)
			end
		end
	end
	objectives(resume)

	local completed = false
	for _, step in walk.steps do
		if not completed then
			if step.event and step.event.kind ~= "DialogueFinished" then
				table.insert(result.played, describeEvent(step.event))
			end
			local commands = beforeChapterCard(step.commands)
			objectives(commands)
			for _, command in commands do
				WorldState.apply(story, result.world, command)
			end
		end
		for _, event in step.events do
			if completed then
				result.next = describeEvent(event)
				return result
			elseif event.kind == "QuestCompleted" then
				table.insert(result.quests, event.quest)
			elseif event.kind == "BeatPlayed" then
				table.insert(result.beats, event.beat)
			elseif event.kind == "ChapterCompleted" and event.chapter == id then
				completed = true
			end
		end
	end
	error(`{id} never completed, or nothing followed it`)
end

return Chapter
