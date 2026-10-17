--!strict
--[[
	Cues: the Cues the core and the client binder name themselves, rather
	than content. Each is an Asset name in assets/manifest.json, resolved
	to a sound by src/client/Audio through AssetIds; until it has an id it
	is silent. The Scenes name their music and ambience, and Beats their
	PlayCues, in content.
]]

local Story = require("./Story")

local Cues = {
	-- the title screen, the Chapter cards and the end card
	THEME = "music:theme",
	-- a Chapter card or the end card appears
	CHAPTER_CARD = "cue:chapter_card",
	-- the player uses a talk affordance
	PROMPT = "cue:prompt",
	-- Amy touches a Pickup (the collect Kind's PlayCue)
	PICKUP = "cue:pickup",
	-- each of Amy's steps on the ground
	FOOTSTEP = "cue:footstep",
}

local OWN = { "THEME", "CHAPTER_CARD", "PROMPT", "PICKUP", "FOOTSTEP" }

-- Every Cue the game names, with where: the ones above, each Scene's music
-- and ambience, and each Beat's PlayCue.
function Cues.named(story: Story.Story, scenes: { Story.Scene }): { [string]: string }
	local named = {}
	for _, key in OWN do
		named[(Cues :: any)[key]] = `src/core/Cues {key}`
	end
	for _, scene in scenes do
		named[scene.music] = `scene:{scene.id} music`
		named[scene.ambience] = `scene:{scene.id} ambience`
	end
	for _, chapter in story.chapters do
		for name, beat in chapter.beats do
			for _, command in beat do
				if command.kind == "PlayCue" then
					named[command.cue] = `beat:{name}`
				end
			end
		end
	end
	return named
end

return Cues
