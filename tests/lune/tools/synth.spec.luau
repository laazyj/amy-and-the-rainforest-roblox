--[[
	The placeholder Cues (tools/lib/synth.luau): the WAV format, each
	recipe's manifest entry, and each committed file being what its recipe
	renders today (to within one step of 16-bit rounding).
]]

local Manifest = require("../../../tools/lib/manifest")
local Synth = require("../../../tools/lib/synth")
local bootstrap = require("../bootstrap")

local manifest = Manifest.decode(bootstrap.readSource(Manifest.PATH))
local entries: { [string]: Manifest.Entry } = {}
for _, entry in manifest.assets do
	entries[entry.name] = entry
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("Synth.wav", function()
		it("writes mono 16-bit PCM that reads back", function()
			local file = Synth.wav({ 0, 0.5, -0.5, 1, -1 })
			expect(#file).toBe(44 + 10)
			expect(string.sub(file, 1, 4)).toBe("RIFF")
			expect(string.sub(file, 9, 16)).toBe("WAVEfmt ")
			local samples = assert(Synth.read(file), "reads back")
			expect(#samples).toBe(5)
			expect(samples[2]).toBeCloseTo(0.5, 1e-4)
			expect(samples[5]).toBeCloseTo(-1, 1e-4)
		end)

		it("reads no other file", function()
			expect(Synth.read("\137PNG")).toBeNil()
		end)
	end)

	describe("Synth.path", function()
		it("keeps sounds by their name and prefixes music", function()
			expect(Synth.path("cue:sam_bark")).toBe("assets/audio/sam_bark.wav")
			expect(Synth.path("music:home")).toBe("assets/audio/music_home.wav")
		end)
	end)

	for _, recipe in Synth.RECIPES do
		describe(recipe.name, function()
			it("is a synthesised placeholder in the manifest, at its path", function()
				local entry = entries[recipe.name]
				expect(entry and entry.kind).toBe("audio")
				expect(entry.path).toBe(Synth.path(recipe.name))
				expect(entry.licence).toBe("synthesised")
				expect(entry.placeholder).toBe(true)
				expect(entry.origin).toContain(recipe.sound)
			end)

			it("is committed as its recipe renders it, quiet and with no clicks at its ends", function()
				local committed = assert(Synth.read(bootstrap.readSource(Synth.path(recipe.name))), "a WAV")
				local rendered = Synth.samples(recipe)
				expect(#committed).toBe(#rendered)
				local worst, loudest, biggestStep = 0, 0, 0
				for i, sample in rendered do
					worst = math.max(worst, math.abs(sample - committed[i]))
					loudest = math.max(loudest, math.abs(committed[i]))
					if i > 1 then
						biggestStep = math.max(biggestStep, math.abs(committed[i] - committed[i - 1]))
					end
				end
				expect(worst <= 1.5 / 32767).toBe(true)
				expect(loudest).toBeCloseTo(recipe.peak, 1e-3)
				local seam = math.abs(committed[#committed] - committed[1])
				if recipe.loop then
					expect(seam <= biggestStep).toBe(true) -- the end flows into the start
				else
					expect(math.abs(committed[1]) + math.abs(committed[#committed]) < 0.01).toBe(true)
				end
			end)
		end)
	end
end
