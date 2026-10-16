--!strict
--[[
	Audio: the client's sound, over the Soundscape view-model
	(src/core/Soundscape) and the Narration table (src/core/Narration).

	Every Cue is resolved by its Asset name (cue:, music:, narration:)
	through AssetIds, so a Cue whose asset id is absent (not uploaded yet)
	is silent, never an error. Every Sound plays through the SoundGroup
	`group` (SoundService.Master, whose volume is the volume Setting).

	  play(cue)        a sound Cue once: PlayCue, a prompt, a footstep
	  render(view)     the Soundscape's music and ambience, each change
	                   crossfaded over Soundscape.CROSSFADE_SECONDS
	  narrate(reading) a Line's part of its narration file, or none; the
	                   part stops at its end (tick) or at the next Line

	A ModuleScript, so the engine tests (tests/engine/audio.luau) can
	require it where the client binder does not run.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Core = ReplicatedStorage:WaitForChild("core")
local Narration = require(Core:WaitForChild("Narration"))
local Soundscape = require(Core:WaitForChild("Soundscape"))
local AssetIds = require(ReplicatedStorage:WaitForChild("shared"):WaitForChild("AssetIds"))

export type Audio = {
	play: (cue: string) -> (),
	render: (view: Soundscape.View) -> (),
	narrate: (reading: Narration.Reading?) -> (),
	tick: () -> (),
}

-- A looping layer: the Cue it plays and its Sound, if the Cue resolves.
type Layer = { cue: string?, sound: Sound?, volume: number }

local Audio = {}

-- A Sound for the Asset `name` in `group`, or nil while it has no asset id.
function Audio.sound(name: string, group: SoundGroup, volume: number, looped: boolean): Sound?
	local id = AssetIds[name]
	if not id then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.SoundGroup = group
	sound.Volume = volume
	sound.Looped = looped
	sound.Parent = group
	return sound
end

local function fadeTo(sound: Sound, volume: number): Tween
	local tween = TweenService:Create(sound, TweenInfo.new(Soundscape.CROSSFADE_SECONDS), { Volume = volume })
	tween:Play()
	return tween
end

-- The layer fades out what it plays and fades in `cue`, if that changed.
local function crossfade(layer: Layer, cue: string?, group: SoundGroup)
	if layer.cue == cue then
		return
	end
	layer.cue = cue
	local old = layer.sound
	if old then
		fadeTo(old, 0).Completed:Once(function()
			old:Destroy()
		end)
	end
	layer.sound = if cue then Audio.sound(cue, group, 0, true) else nil
	if layer.sound then
		layer.sound:Play()
		fadeTo(layer.sound, layer.volume)
	end
end

function Audio.new(group: SoundGroup): Audio
	local music: Layer = { cue = nil, sound = nil, volume = Soundscape.MUSIC_VOLUME }
	local ambience: Layer = { cue = nil, sound = nil, volume = Soundscape.AMBIENCE_VOLUME }
	-- each effect's Sound, made the first time it plays and played again after
	local effects: { [string]: Sound } = {}
	-- the reading last asked for, and its Sound until its part ends
	local asked: Narration.Reading? = nil
	local voice: Sound? = nil

	local function stopNarration()
		if voice then
			voice:Destroy()
		end
		voice = nil
	end

	return {
		play = function(cue)
			local sound = effects[cue] or Audio.sound(cue, group, Soundscape.EFFECT_VOLUME, false)
			if sound then
				effects[cue] = sound
				sound.TimePosition = 0
				sound:Play()
			end
		end,
		render = function(view)
			crossfade(music, view.music, group)
			crossfade(ambience, view.ambience, group)
		end,
		narrate = function(next)
			if next == asked then
				return
			end
			asked = next
			stopNarration()
			local sound = next and Audio.sound(next.asset, group, Soundscape.NARRATION_VOLUME, false)
			if next and sound then
				voice = sound
				sound.TimePosition = next.from
				sound:Play()
			end
		end,
		tick = function()
			if voice and asked and not Narration.reads(asked, voice.TimePosition) then
				stopNarration()
			end
		end,
	}
end

return Audio
