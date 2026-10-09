--!strict
--[[
	Story: the shape content gives the Story (plan section 2.4), as Luau
	types, and the lookups the core makes on it. Content builds a Story out
	of plain tables (src/content/Story.luau); positions are Vec3 and colours
	RGB tables, never engine datatypes.
]]

local Events = require("./Events")

type PlayerEvent = Events.PlayerEvent
type WorldCommand = Events.WorldCommand

export type Vec3 = { x: number, y: number, z: number }
export type RGB = { r: number, g: number, b: number }

-- One thing said. `speaker` is "Narrator" or a Character id; `canon` marks
-- Clara's exact words (docs/story/canon.md).
-- A Dialogue whose first Line is canon and others are not is written
-- `{ ... } :: { Story.Line }`: the type checker takes an optional list's
-- item type from its first item.
export type Line = { speaker: string, text: string, canon: boolean? }

export type QuestKind = "talk" | "reach" | "collect"

-- The Beats each Hook plays, by name; the Beats are in the Chapter's hooks.luau.
export type Hooks = { onStart: { string }?, onComplete: { string }? }

export type Quest = {
	id: string,
	kind: QuestKind,
	objective: string,
	-- talk: the Character to talk to, and the label on its talk affordance
	character: string?,
	talkLabel: string?,
	-- reach: the Zone to enter
	zone: string?,
	-- collect: how many Pickups to touch, and the Spots they spawn at
	count: number?,
	pickups: { string }?,
	-- Dialogues: on start, on TalkedTo (talk Quests only), on complete
	intro: { Line }?,
	dialogue: { Line }?,
	outro: { Line }?,
	hooks: Hooks?,
}

-- A Beat: World commands, with Waits, played in order at a Hook.
export type Beat = { WorldCommand }

-- A Chapter as its data.luau declares it; its hooks.luau adds the Beats.
export type ChapterData = { id: string, title: string, subtitle: string, quests: { Quest } }

export type Chapter = {
	id: string,
	title: string,
	subtitle: string,
	quests: { Quest },
	beats: { [string]: Beat },
}

-- A Scene's Spots, Zones and Props (src/content/scenes/<Scene>.luau). The
-- scene files also hold the layout SceneBuilder builds from.
export type Scene = {
	id: string,
	spots: { [string]: Spot },
	zones: { [string]: Zone },
	props: { [string]: Prop },
}

export type Character = {
	id: string,
	display: string,
	kind: string,
	home: string,
	shirt: RGB?,
	-- the Player Character (Amy): a Speaker, never built in the world
	player: boolean?,
}

-- A named position on the ground and the direction it faces.
export type Spot = { at: Vec3, facing: Vec3 }
-- A named invisible box, by its centre and size.
export type Zone = { centre: Vec3, size: Vec3 }
-- A Prop's states in lifecycle order; the first is the state it starts in.
export type Prop = { states: { string } }
export type LightingPreset = { saturation: number, contrast: number, tint: RGB, seconds: number }
export type Ending = { lines: { Line }, title: string, subtitle: string }

export type Story = {
	title: string,
	author: string,
	chapters: { Chapter },
	characters: { Character },
	spots: { [string]: Spot },
	zones: { [string]: Zone },
	props: { [string]: Prop },
	lighting: { [string]: LightingPreset },
	initialLighting: string,
	ending: Ending,
}

-- A Quest Kind (src/core/quests/<kind>.luau): how a Quest of that Kind is
-- played once its intro is done.
export type Outcome = {
	commands: { WorldCommand },
	-- the Pickups touched so far, when the event touched one
	collected: { string }?,
	-- whether the Kind is satisfied and the Quest moves on
	done: boolean,
}
export type Kind = {
	-- World commands that make the Quest playable, with the Pickups already
	-- touched (none when it starts; some on a Resume)
	begin: (quest: Quest, collected: { string }) -> { WorldCommand },
	-- what a Player event does to the Quest; nil when it does nothing
	handle: (quest: Quest, collected: { string }, event: PlayerEvent) -> Outcome?,
	-- the Objective text shown while the Quest is active
	objective: (quest: Quest, collected: { string }) -> string,
}

local Story = {}

Story.NARRATOR = "Narrator"

export type Placed = { quest: Quest, chapter: Chapter }

-- Every Quest with its Chapter, in story order.
function Story.quests(story: Story): { Placed }
	local placed = {}
	for _, chapter in story.chapters do
		for _, quest in chapter.quests do
			table.insert(placed, { quest = quest, chapter = chapter })
		end
	end
	return placed
end

-- The Quest with `id` and its Chapter, or nil.
function Story.quest(story: Story, id: string?): (Quest?, Chapter?)
	for _, placed in Story.quests(story) do
		if placed.quest.id == id then
			return placed.quest, placed.chapter
		end
	end
	return nil, nil
end

-- The Quest after `id` in story order and its Chapter; nil after the last.
function Story.after(story: Story, id: string): (Quest?, Chapter?)
	local placed = Story.quests(story)
	for i, entry in placed do
		if entry.quest.id == id and placed[i + 1] then
			return placed[i + 1].quest, placed[i + 1].chapter
		end
	end
	return nil, nil
end

function Story.character(story: Story, id: string): Character?
	for _, character in story.characters do
		if character.id == id then
			return character
		end
	end
	return nil
end

-- How a Speaker is shown: the Narrator as itself, a Character by its display name.
function Story.displayName(story: Story, speaker: string): string
	if speaker == Story.NARRATOR then
		return speaker
	end
	local character = Story.character(story, speaker)
	if not character then
		error(`unknown Speaker {speaker}`, 2)
	end
	return character.display
end

-- Lines as the client shows them.
function Story.shownLines(story: Story, lines: { Line }): { Events.ShownLine }
	local shown = table.create(#lines)
	for i, line in lines do
		shown[i] = { speaker = Story.displayName(story, line.speaker), text = line.text }
	end
	return shown
end

return Story
