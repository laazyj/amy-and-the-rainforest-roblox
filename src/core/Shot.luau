--!strict
--[[
	Shot: the named camera framings (docs/design/feel.md section 2, the
	glossary's Shots), as the core knows them: their names, which hold
	until the Dialogue they accompany is finished, and how long the others
	last. CameraModel moves the camera through them.
]]

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

return Shot
