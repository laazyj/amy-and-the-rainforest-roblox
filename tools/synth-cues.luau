--!strict
--[[
	Writes the placeholder Cues (tools/lib/synth.luau) under assets/audio/,
	one WAV each. Run it after changing a recipe; the changed files are
	uploaded again by the owner's upload run (docs/ASSETS.md).

	  lune run tools/synth-cues
]]

local Cli = require("./lib/cli")
local Synth = require("./lib/synth")

Cli.main(function(ctx)
	for _, recipe in Synth.RECIPES do
		local path = Synth.path(recipe.name)
		ctx.writeFile(path, Synth.wav(Synth.samples(recipe)))
		ctx.log(`{path}: {recipe.name}, {recipe.seconds} s{if recipe.loop then ", looping" else ""}`)
	end
end)
