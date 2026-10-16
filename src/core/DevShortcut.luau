--!strict
--[[
	DevShortcut: the Dev-only chat commands that jump to a point in the
	Story (plan section 5.3), as plain data. src/server/DevShortcuts turns
	a jump into a Resume there; Release builds have no Dev shortcuts at all
	(the publish job strips them, tools/lib/release.luau).

	  /chapter N    the first Quest of Chapter N
	  /quest <id>   that Quest ("/quest chapter3.meet_fox")
]]

local Story = require("./Story")

type Jump = (story: Story.Story, argument: string) -> (string?, string?)

-- Each chat command: the Quest its argument names, or nil and why not.
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

local DevShortcut = {}

-- The chat commands, as TextChatCommand aliases.
DevShortcut.COMMANDS = {}
for command in JUMPS do
	table.insert(DevShortcut.COMMANDS, command)
end
table.sort(DevShortcut.COMMANDS)
table.freeze(DevShortcut.COMMANDS)

local USAGE = `usage: {table.concat(DevShortcut.COMMANDS, " <argument> or ")} <argument>`

-- The Quest a chat message jumps to; nil and the reason when it names none.
function DevShortcut.parse(story: Story.Story, text: string): (string?, string?)
	local command, argument = string.match(text, "^%s*(/%a+)%s+(%S+)%s*$")
	local jump = command and JUMPS[command]
	if not jump then
		return nil, USAGE
	end
	return jump(story, argument :: string)
end

return DevShortcut
