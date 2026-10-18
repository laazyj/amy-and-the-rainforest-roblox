--!strict
--[[
	DevShortcut: the Dev-only chat commands that jump to a point in the
	Story or show the Title screen (plan section 5.3), as plain data.
	src/server/DevShortcuts turns a jump into a Resume there, and the Title
	screen into StoryHost.offerTitle; Release builds have no Dev shortcuts
	at all (the publish job strips them, tools/lib/release.luau).

	  /chapter N    the first Quest of Chapter N
	  /quest <id>   that Quest ("/quest chapter3.meet_fox")
	  /title        the Title screen, offered at the current Progress as to
	                a returning player; Continue carries on from there
]]

local Story = require("./Story")

-- What a chat command asks for: a jump to a Quest, or the Title screen.
export type Shortcut = { kind: "jump", quest: string } | { kind: "title" }

type Jump = (story: Story.Story, argument: string) -> (string?, string?)

-- Each chat command with an argument: the Quest it names, or nil and why not.
local JUMPS: { [string]: Jump } = {
	["/chapter"] = function(story, argument)
		local chapter = story.chapters[tonumber(argument) or 0]
		if not chapter then
			return nil, `there is no Chapter {argument}; try 1 to {#story.chapters}`
		end
		return chapter.quests[1].id, nil
	end,
	["/quest"] = function(story, argument)
		if not Story.quest(story, argument) then
			return nil, `there is no Quest {argument}`
		end
		return argument, nil
	end,
}

local TITLE = "/title"

local DevShortcut = {}

-- The chat commands, as TextChatCommand aliases.
DevShortcut.COMMANDS = { TITLE }
for command in JUMPS do
	table.insert(DevShortcut.COMMANDS, command)
end
table.sort(DevShortcut.COMMANDS)
table.freeze(DevShortcut.COMMANDS)

local USAGE = (function()
	local forms = {}
	for _, command in DevShortcut.COMMANDS do
		table.insert(forms, if JUMPS[command] then `{command} <argument>` else command)
	end
	return `usage: {table.concat(forms, ", ")}`
end)()

-- What a chat message asks for; nil and the reason when it asks for nothing.
function DevShortcut.parse(story: Story.Story, text: string): (Shortcut?, string?)
	local command, rest = string.match(text, "^%s*(/%a+)(.-)%s*$")
	if command == TITLE and rest == "" then
		return { kind = "title" }, nil
	end
	local jump = command and JUMPS[command]
	local argument = rest and string.match(rest, "^%s+(%S+)$")
	if not jump or not argument then
		return nil, USAGE
	end
	local quest, reason = jump(story, argument)
	return if quest then { kind = "jump", quest = quest } else nil, reason
end

return DevShortcut
