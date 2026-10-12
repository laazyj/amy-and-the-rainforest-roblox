--!strict
--[[
	Shot: the named camera framings (docs/design/feel.md section 2, the
	glossary's Shots), as the core knows them: their names, which hold
	until the Dialogue they accompany is finished, and how long the others
	last, and the one Shot the core frames itself: shot:Dialogue.
	CameraModel moves the camera through them.
]]

local Events = require("./Events")
local Story = require("./Story")

local Shot = {}

-- Every Shot by name, as FrameShot's `shot` carries it.
Shot.NAMES = table.freeze({ "Dialogue", "ForestWallReveal", "MeetCharacter", "MachineFinale" })

-- Shots that accompany a Dialogue: each holds until DialogueFinished.
Shot.HELD = table.freeze({ Dialogue = true, MachineFinale = true } :: { [string]: boolean })

-- How long each other Shot lasts, easing in included: at most 4 seconds.
Shot.SECONDS = table.freeze({ ForestWallReveal = 3.5, MeetCharacter = 3.5 } :: { [string]: number })

-- The longest any Shot that is not held may last.
Shot.LONGEST = 4

-- A Shot eases in from the camera before it over this long.
Shot.EASE_IN = 0.5
-- The follow camera returns over this long when the last Shot ends.
Shot.HAND_BACK = 0.5

-- The shot:Dialogue framing `lines`, played after `commands` in the same
-- step: of its first Speaker who is a Character in the world (not the
-- Narrator, not Amy), or nil when it has none, so a Narrator-only or
-- Amy-only Dialogue keeps the camera it has. A Dialogue that a held Shot
-- framed earlier in the step already accompanies (shot:MachineFinale and
-- the Ending) keeps that Shot.
function Shot.forDialogue(
	story: Story.Story,
	lines: { Story.Line },
	commands: { Events.WorldCommand }
): Events.WorldCommand?
	for _, command in commands do
		if command.kind == "FrameShot" and Shot.HELD[command.shot] then
			return nil
		end
	end
	for _, line in lines do
		local character = Story.character(story, line.speaker)
		if character and not character.player then
			return { kind = "FrameShot", shot = "Dialogue", character = character.id }
		end
	end
	return nil
end

return Shot
