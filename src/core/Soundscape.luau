--!strict
--[[
	Soundscape: what plays under the Story, as plain data, for the client's
	Audio adapter (src/client/Audio) to render.

	  music     the Scene's music Cue while Amy is in it; the theme
	            (Cues.THEME) instead while the Title screen, a Chapter card
	            or the end card shows
	  ambience  the Scene's ambience Cue, looping under the music
	  steps     a footstep (Cues.FOOTSTEP) every STEP_SECONDS while Amy
	            walks on the ground

	Amy is in the Scene with the smallest bounds that hold her, so a Scene
	inside another (the Garden in the Village, the Heart Glade in the
	Paradise) has its own sound. Outside every Scene's bounds she keeps the
	last Scene's. A change of music or ambience is crossfaded over
	CROSSFADE_SECONDS by the adapter.
]]

local Cues = require("./Cues")
local Story = require("./Story")

export type Soundscape = {
	-- the Scene Amy was last inside
	scene: Story.Scene?,
	-- the Title screen, a Chapter card or the end card is showing
	screen: boolean,
	-- seconds walked since the last footstep
	stride: number,
}

export type View = { music: string?, ambience: string? }

local Soundscape = {}

Soundscape.CROSSFADE_SECONDS = 2
Soundscape.STEP_SECONDS = 0.38
-- Each layer's volume before the volume Setting (SoundService.Master):
-- quiet under the Lines, so a Cue or narration is heard over them.
Soundscape.MUSIC_VOLUME = 0.35
Soundscape.AMBIENCE_VOLUME = 0.3
Soundscape.EFFECT_VOLUME = 0.6
Soundscape.NARRATION_VOLUME = 1

local function holds(box: Story.Box, at: Story.Vec3): boolean
	local c, s = box.centre, box.size
	return math.abs(at.x - c.x) <= s.x / 2 and math.abs(at.y - c.y) <= s.y / 2 and math.abs(at.z - c.z) <= s.z / 2
end

local function volume(box: Story.Box): number
	return box.size.x * box.size.y * box.size.z
end

-- The Scene with the smallest bounds that hold `at`, or nil outside them all.
function Soundscape.sceneAt(scenes: { Story.Scene }, at: Story.Vec3): Story.Scene?
	local found: Story.Scene? = nil
	for _, scene in scenes do
		if holds(scene.bounds, at) and (not found or volume(scene.bounds) < volume(found.bounds)) then
			found = scene
		end
	end
	return found
end

function Soundscape.new(): Soundscape
	return { scene = nil, screen = false, stride = Soundscape.STEP_SECONDS }
end

-- Amy is at `at`: she is in the Scene there, or still in the last one.
function Soundscape.moved(soundscape: Soundscape, scenes: { Story.Scene }, at: Story.Vec3)
	soundscape.scene = Soundscape.sceneAt(scenes, at) or soundscape.scene
end

-- Whether the Title screen, a Chapter card or the end card is showing.
function Soundscape.screen(soundscape: Soundscape, showing: boolean)
	soundscape.screen = showing
end

function Soundscape.view(soundscape: Soundscape): View
	local scene = soundscape.scene
	return {
		music = if soundscape.screen then Cues.THEME elseif scene then scene.music else nil,
		ambience = if scene then scene.ambience else nil,
	}
end

-- `seconds` pass with Amy walking on the ground or not; whether a footstep
-- falls in them. The first step of a walk sounds at once.
function Soundscape.step(soundscape: Soundscape, seconds: number, walking: boolean): boolean
	if not walking then
		soundscape.stride = Soundscape.STEP_SECONDS
		return false
	end
	soundscape.stride += seconds
	if soundscape.stride < Soundscape.STEP_SECONDS then
		return false
	end
	soundscape.stride %= Soundscape.STEP_SECONDS
	return true
end

return Soundscape
