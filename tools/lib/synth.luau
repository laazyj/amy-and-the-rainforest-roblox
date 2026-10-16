--!strict
--[[
	The placeholder Cues (docs/ASSETS.md, "Cues: the placeholders and the
	shopping list"): each a few seconds of gentle, quiet sound made from
	plain waveform code, so every Cue is heard before the owner picks the
	real ones. tools/synth-cues.luau writes them under assets/audio/.

	Each recipe renders mono samples in -1..1 at RATE, normalised to its
	peak (quiet: music and ambience sit under the Lines), as 16-bit PCM
	WAV. A looping one (music, ambience) is seamless: its tones complete
	whole cycles in the loop, its notes' tails wrap round to the start, and
	its filtered noise is taken from a second pass over a repeating noise
	table, once the filter has settled.

	Pure and deterministic: no randomness but a fixed-seed generator, no
	clock, no files.
]]

local Synth = {}

Synth.RATE = 16000

export type Recipe = {
	name: string,
	seconds: number,
	loop: boolean,
	-- the loudest sample, as a fraction of full scale
	peak: number,
	-- what it is, for the manifest's origin
	sound: string,
	render: (n: number) -> { number },
}

local TAU = 2 * math.pi

-- A note's frequency, in Hz, from its MIDI number (69 is A4, 440 Hz).
local function hz(midi: number): number
	return 440 * 2 ^ ((midi - 69) / 12)
end

-- `f` nudged to complete whole cycles in `seconds`, so a loop is seamless.
local function periodic(f: number, seconds: number): number
	return math.max(1, math.floor(f * seconds + 0.5)) / seconds
end

-- A fixed-seed generator of numbers in -1..1 (a linear congruential one).
local function noiseTable(n: number, seed: number): { number }
	local values, state = table.create(n), seed
	for i = 1, n do
		state = (state * 1103515245 + 12345) % 2147483648
		values[i] = state / 1073741824 - 1
	end
	return values
end

-- `n` samples of noise through a one-pole low-pass filter (`alpha` near 0 is
-- darker). Looping, the filter runs over the table twice and the second
-- pass is kept, so the end flows into the start.
local function filteredNoise(n: number, seed: number, alpha: number, loop: boolean): { number }
	local raw = noiseTable(n, seed)
	local out, y = table.create(n), 0
	for _ = 1, if loop then 2 else 1 do
		for i = 1, n do
			y += alpha * (raw[i] - y)
			out[i] = y
		end
	end
	return out
end

-- A soft note: a sine and its octave, a quick attack and an exponential decay.
local function tone(age: number, f: number, decay: number): number
	if age < 0 then
		return 0
	end
	local attack = math.min(1, age / 0.012)
	return attack * math.exp(-age * decay) * (math.sin(TAU * f * age) + 0.25 * math.sin(TAU * 2 * f * age))
end

-- A tune: `notes` (MIDI numbers, 0 a rest) one every `beat` seconds over a
-- pad of `chord`, the pad's level breathing once a loop. Each note also
-- sounds `echo` seconds later at a third of its level. Tails wrap round.
local function tune(notes: { number }, beat: number, chord: { number }, decay: number, echo: number?)
	return function(n: number): { number }
		local seconds = n / Synth.RATE
		local pads = {}
		for i, midi in chord do
			pads[i] = periodic(hz(midi), seconds)
		end
		local out = table.create(n, 0)
		for i = 1, n do
			local t = (i - 1) / Synth.RATE
			local pad = 0
			for _, f in pads do
				pad += math.sin(TAU * f * t)
			end
			local breath = 0.75 + 0.25 * math.sin(TAU * t / seconds)
			local sum = 0.18 * breath * pad / #pads
			for k, midi in notes do
				if midi > 0 then
					local f, start = hz(midi), (k - 1) * beat
					for _, wrap in { 0, seconds } do
						sum += 0.5 * tone(t + wrap - start, f, decay)
						if echo then
							sum += 0.17 * tone(t + wrap - start - echo, f, decay)
						end
					end
				end
			end
			out[i] = sum
		end
		return out
	end
end

-- A bird's chirp: a short falling then rising whistle.
local function chirp(age: number, f: number): number
	if age < 0 or age > 0.14 then
		return 0
	end
	local sweep = f * (1 + 0.25 * math.sin(TAU * age / 0.14))
	return math.sin(math.pi * age / 0.14) * math.sin(TAU * sweep * age)
end

-- Wind: filtered noise swelling once a loop, with birds or shimmer over it.
local function ambience(alpha: number, seed: number, over: (t: number, seconds: number) -> number)
	return function(n: number): { number }
		local seconds = n / Synth.RATE
		local wind = filteredNoise(n, seed, alpha, true)
		local out = table.create(n)
		for i = 1, n do
			local t = (i - 1) / Synth.RATE
			out[i] = wind[i] * (0.7 + 0.3 * math.sin(TAU * t / seconds)) + over(t, seconds)
		end
		return out
	end
end

-- A one-off effect: `at(t)` for each sample.
local function effect(at: (t: number, seconds: number) -> number)
	return function(n: number): { number }
		local seconds = n / Synth.RATE
		local out = table.create(n)
		for i = 1, n do
			out[i] = at((i - 1) / Synth.RATE, seconds)
		end
		return out
	end
end

-- A sine sweeping from `from` to `to` Hz over `seconds`, at time `t`.
local function sweep(t: number, from: number, to: number, seconds: number): number
	return math.sin(TAU * (from * t + (to - from) * t * t / (2 * seconds)))
end

-- The fade in and out every effect has, so none clicks.
local function fade(t: number, seconds: number, edge: number): number
	return math.min(1, t / edge, (seconds - t) / edge)
end

local footstepNoise = filteredNoise(Synth.RATE, 7, 0.25, false)
local rumbleNoise = filteredNoise(3 * Synth.RATE, 11, 0.04, false)
local clunkNoise = filteredNoise(Synth.RATE, 13, 0.3, false)

Synth.RECIPES = {
	{
		name = "music:theme",
		seconds = 8,
		loop = true,
		peak = 0.3,
		sound = "a slow C major pentatonic tune over a soft C chord",
		render = tune({ 72, 76, 79, 81, 79, 76, 74, 0, 72, 74, 76, 79, 76, 74, 72, 0 }, 0.5, { 48, 55, 64 }, 2.2, 0.25),
	},
	{
		name = "music:home",
		seconds = 8,
		loop = true,
		peak = 0.25,
		sound = "a music-box G major tune over a soft G chord",
		render = tune({ 79, 0, 83, 0, 86, 0, 83, 0, 81, 0, 79, 0, 76, 0, 74, 0 }, 0.5, { 43, 50, 59 }, 3),
	},
	{
		name = "music:field",
		seconds = 8,
		loop = true,
		peak = 0.25,
		sound = "an airy D major tune, sparse, over an open D fifth",
		render = tune({ 74, 0, 0, 78, 0, 81, 0, 0, 83, 0, 0, 81, 0, 78, 0, 0 }, 0.5, { 50, 57, 62 }, 1.6, 0.375),
	},
	{
		name = "music:paradise",
		seconds = 8,
		loop = true,
		peak = 0.25,
		sound = "a high, echoing E major tune over a soft E chord",
		render = tune({ 88, 83, 80, 0, 85, 80, 76, 0, 83, 80, 76, 0, 80, 76, 73, 0 }, 0.5, { 52, 59, 68 }, 2.5, 0.25),
	},
	{
		name = "cue:ambience_home",
		seconds = 6,
		loop = true,
		peak = 0.2,
		sound = "a soft breeze with three birds",
		render = ambience(0.02, 3, function(t)
			return 0.5 * (chirp(t - 0.7, 3200) + chirp(t - 2.9, 2700) + chirp(t - 4.3, 3600))
		end),
	},
	{
		name = "cue:ambience_field",
		seconds = 6,
		loop = true,
		peak = 0.2,
		sound = "an open, swelling wind with one far bird",
		render = ambience(0.05, 5, function(t)
			return 0.25 * chirp(t - 3.1, 2900)
		end),
	},
	{
		name = "cue:ambience_paradise",
		seconds = 6,
		loop = true,
		peak = 0.2,
		sound = "a warm hush under a slow, high shimmer",
		render = ambience(0.015, 9, function(t, seconds)
			local a, b = periodic(1760, seconds), periodic(2217, seconds)
			local tremolo = 0.5 + 0.5 * math.sin(TAU * 2 * t / seconds)
			return 0.12 * tremolo * (math.sin(TAU * a * t) + math.sin(TAU * b * t))
		end),
	},
	{
		name = "cue:chapter_card",
		seconds = 1.8,
		loop = false,
		peak = 0.4,
		sound = "a soft bell chord, C E G",
		render = effect(function(t, seconds)
			return fade(t, seconds, 0.05)
				* (tone(t, hz(72), 2.2) + tone(t - 0.04, hz(76), 2.2) + tone(t - 0.08, hz(79), 2.2))
		end),
	},
	{
		name = "cue:prompt",
		seconds = 0.45,
		loop = false,
		peak = 0.35,
		sound = "two soft rising notes, E6 then A6",
		render = effect(function(t, seconds)
			return fade(t, seconds, 0.02) * (tone(t, hz(88), 9) + tone(t - 0.12, hz(93), 9))
		end),
	},
	{
		name = "cue:pickup",
		seconds = 0.7,
		loop = false,
		peak = 0.4,
		sound = "a quick rising sparkle, C6 E6 G6",
		render = effect(function(t, seconds)
			return fade(t, seconds, 0.02) * (tone(t, hz(84), 8) + tone(t - 0.08, hz(88), 8) + tone(t - 0.16, hz(91), 6))
		end),
	},
	{
		name = "cue:footstep",
		seconds = 0.15,
		loop = false,
		peak = 0.25,
		sound = "a soft thud on grass",
		render = effect(function(t, seconds)
			local i = math.floor(t * Synth.RATE) + 1
			return fade(t, seconds, 0.005) * math.exp(-t * 35) * (footstepNoise[i] + 0.6 * math.sin(TAU * 90 * t))
		end),
	},
	{
		name = "cue:sam_bark",
		seconds = 0.6,
		loop = false,
		peak = 0.45,
		sound = "two gentle woofs: a falling, buzzy tone",
		render = effect(function(t, seconds)
			local function woof(age: number): number
				if age < 0 or age > 0.16 then
					return 0
				end
				local f = 480 - 1400 * age
				local shape = math.sin(math.pi * age / 0.16)
				local phase = TAU * (480 * age - 700 * age * age)
				return shape * (math.sin(phase) + 0.5 * math.sin(2 * phase) + 0.25 * math.sin(3 * phase)) * f / 480
			end
			return fade(t, seconds, 0.01) * (woof(t) + woof(t - 0.28))
		end),
	},
	{
		name = "cue:paradise_shimmer",
		seconds = 2,
		loop = false,
		peak = 0.35,
		sound = "a rising glissando with sparkles",
		render = effect(function(t, seconds)
			local sparkles = tone(t - 0.6, hz(96), 5) + tone(t - 0.9, hz(100), 5) + tone(t - 1.2, hz(103), 5)
			return fade(t, seconds, 0.3) * (0.6 * sweep(t, 500, 2000, seconds) + 0.5 * sparkles)
		end),
	},
	{
		name = "cue:machine_rumble",
		seconds = 3,
		loop = false,
		peak = 0.35,
		sound = "a low engine rumble that swells and fades",
		render = effect(function(t, seconds)
			local i = math.floor(t * Synth.RATE) + 1
			local hum = math.sin(TAU * 45 * t) + 0.5 * math.sin(TAU * 60 * t)
			return fade(t, seconds, 0.8) * (2 * rumbleNoise[i] + 0.4 * hum)
		end),
	},
	{
		name = "cue:machine_stop",
		seconds = 1.5,
		loop = false,
		peak = 0.35,
		sound = "an engine winding down, then a soft clunk",
		render = effect(function(t, seconds)
			local wind = math.exp(-t * 1.5) * sweep(t, 220, 40, 1.2)
			local age = t - 1.15
			local clunk = if age >= 0 then math.exp(-age * 25) * clunkNoise[math.floor(age * Synth.RATE) + 1] else 0
			return fade(t, seconds, 0.03) * (0.6 * wind + clunk)
		end),
	},
} :: { Recipe }

-- The file a Cue's placeholder is written to: "cue:sam_bark" ->
-- "assets/audio/sam_bark.wav", "music:home" -> "assets/audio/music_home.wav".
function Synth.path(name: string): string
	local prefix, rest = string.match(name, "^(%l+):(.+)$")
	assert(prefix and rest, `not an Asset name: {name}`)
	return `assets/audio/{if prefix == "cue" then rest else `{prefix}_{rest}`}.wav`
end

-- The recipe's samples, scaled so the loudest is its peak.
function Synth.samples(recipe: Recipe): { number }
	local samples = recipe.render(math.floor(recipe.seconds * Synth.RATE + 0.5))
	local loudest = 0
	for _, sample in samples do
		loudest = math.max(loudest, math.abs(sample))
	end
	local scale = if loudest > 0 then recipe.peak / loudest else 0
	for i, sample in samples do
		samples[i] = sample * scale
	end
	return samples
end

-- Samples in -1..1 as a mono 16-bit PCM WAV file.
function Synth.wav(samples: { number }): string
	local bytes = 2 * #samples
	local out = buffer.create(44 + bytes)
	buffer.writestring(out, 0, "RIFF")
	buffer.writeu32(out, 4, 36 + bytes)
	buffer.writestring(out, 8, "WAVEfmt ")
	buffer.writeu32(out, 16, 16) -- the fmt chunk's size
	buffer.writeu16(out, 20, 1) -- PCM
	buffer.writeu16(out, 22, 1) -- mono
	buffer.writeu32(out, 24, Synth.RATE)
	buffer.writeu32(out, 28, Synth.RATE * 2) -- bytes a second
	buffer.writeu16(out, 32, 2) -- bytes a frame
	buffer.writeu16(out, 34, 16) -- bits a sample
	buffer.writestring(out, 36, "data")
	buffer.writeu32(out, 40, bytes)
	for i, sample in samples do
		buffer.writei16(out, 42 + 2 * i, math.round(math.clamp(sample, -1, 1) * 32767))
	end
	return buffer.tostring(out)
end

-- A mono 16-bit WAV's samples in -1..1 (what Synth.wav writes), or nil
-- for any other file.
function Synth.read(file: string): { number }?
	if #file < 44 or string.sub(file, 1, 4) ~= "RIFF" or string.sub(file, 37, 40) ~= "data" then
		return nil
	end
	local data = buffer.fromstring(file)
	if buffer.readu16(data, 22) ~= 1 or buffer.readu16(data, 34) ~= 16 then
		return nil
	end
	local samples = {}
	for i = 1, buffer.readu32(data, 40) // 2 do
		samples[i] = buffer.readi16(data, 42 + 2 * i) / 32767
	end
	return samples
end

return Synth
