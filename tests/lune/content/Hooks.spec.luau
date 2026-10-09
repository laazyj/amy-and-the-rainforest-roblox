--[[
	Hooks and Beats: every Beat a Hook names in a Chapter's data.luau is in
	that Chapter's hooks.luau, every Beat there is played by a Hook, every
	Hook name and Beat name is the glossary's, and the glossary's Beats
	table lists exactly the Hooks that play each Beat. Each Beat's World
	commands are well formed and name things that exist.
]]

local Events = require("../../../src/core/Events")
local Story = require("../../../src/content/Story")
local StoryTypes = require("../../../src/core/Story")
local glossary = require("./glossary")

local story = Story.story
local HOOK_NAMES = glossary.names("Hook names")
local BEATS = glossary.entries("Beats")

-- Beat name -> the Hooks that play it ("chapter1.sneak_out_1.onComplete"), sorted.
local playedBy: { [string]: { string } } = {}
-- Chapter id -> the Beats its Hooks play.
local playedIn: { [string]: { [string]: boolean } } = {}
for _, placed in StoryTypes.quests(story) do
	local quest = placed.quest
	playedIn[placed.chapter.id] = playedIn[placed.chapter.id] or {}
	for hook, names in (quest.hooks or {}) :: { [string]: { string } } do
		for _, name in names do
			playedBy[name] = playedBy[name] or {}
			table.insert(playedBy[name], `{quest.id}.{hook}`)
			playedIn[placed.chapter.id][name] = true
		end
	end
end

local characters = {}
for _, character in story.characters do
	characters[character.id] = not character.player
end

-- What a command names that must exist, or nil when it names nothing missing.
local function missing(command: any): string?
	if command.character and not characters[command.character] then
		return `Character {command.character}`
	elseif command.spot and not story.spots[command.spot] then
		return `Spot {command.spot}`
	elseif command.preset and not story.lighting[command.preset] then
		return `Lighting preset {command.preset}`
	elseif command.prop then
		local prop = story.props[command.prop]
		if not prop or not table.find(prop.states, command.state) then
			return `Prop {command.prop} in state {command.state}`
		end
	end
	return nil
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	for n, chapter in story.chapters do
		describe(`{chapter.id} hooks`, function()
			for _, quest in chapter.quests do
				for hook, names in (quest.hooks or {}) :: { [string]: { string } } do
					it(`{quest.id} uses the Hook name {hook}`, function()
						expect(HOOK_NAMES[hook]).toBe(true)
					end)

					for _, name in names do
						it(`{quest.id}.{hook} plays beat {name}, which chapters/{n}/hooks.luau has`, function()
							expect(chapter.beats[name]).never.toBeNil()
						end)
					end
				end
			end

			for name, beat in chapter.beats do
				it(`plays beat {name} at some Hook of {chapter.id}`, function()
					expect(playedIn[chapter.id][name]).toBe(true)
				end)

				for i, command in beat do
					it(`beat {name} command {i} ({command.kind}) is well formed and names what exists`, function()
						expect(Events.check(Events.WORLD_COMMANDS, command)).toBe(true)
						expect(missing(command)).toBeNil()
					end)
				end
			end
		end)
	end

	describe("the glossary's Beats", function()
		local listed = {}
		for _, entry in BEATS do
			listed[entry.name] = entry.cells.Hook
		end

		for name, hooks in playedBy do
			it(`lists beat:{name} with exactly the Hooks that play it`, function()
				local inGlossary = glossary.values(listed[name])
				table.sort(inGlossary)
				local sorted = table.clone(hooks)
				table.sort(sorted)
				expect(inGlossary).toEqual(sorted)
			end)
		end

		for _, entry in BEATS do
			it(`has {entry.id} played by a Hook`, function()
				expect(playedBy[entry.name]).never.toBeNil()
			end)
		end
	end)
end
