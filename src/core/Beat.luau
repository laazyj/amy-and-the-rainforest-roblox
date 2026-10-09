--!strict
--[[
	Beat: plays the Beats a Hook names. Each Beat is a list of World commands,
	with Waits, from the Chapter's hooks.luau; playing it emits BeatPlayed and
	appends its commands in order.
]]

local Events = require("./Events")
local Story = require("./Story")

local Beat = {}

-- Appends to `events` and `commands` what playing the Beats `names` of
-- `chapter` emits, in order.
function Beat.play(
	chapter: Story.Chapter,
	names: { string }?,
	events: { Events.StoryEvent },
	commands: { Events.WorldCommand }
)
	for _, name in (names or {}) :: { string } do
		local beat = chapter.beats[name]
		if not beat then
			error(`{chapter.id} has no Beat {name}`, 2)
		end
		table.insert(events, { kind = "BeatPlayed", beat = name })
		table.move(beat, 1, #beat, #commands + 1, commands)
	end
end

return Beat
