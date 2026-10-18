--!strict
-- Audio (brief 013), on the Saved version: the remote contract carries
-- PlayCue, and every Cue the game names resolves through the built
-- AssetIds as src/client/Audio resolves it: a Sound with the Cue's id
-- through SoundService.Master, or silence while it has none (not uploaded
-- yet), never an error. A Cue with an id is an audio asset on Roblox.
-- Whether each plays and is heard is tier 3's (PlaybackLoudness, the Mac).

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterPlayer = game:GetService("StarterPlayer")

local Core = ReplicatedStorage:WaitForChild("core")
local Cues = (require :: any)(Core:WaitForChild("Cues"))
local Net = (require :: any)(Core:WaitForChild("Net"))
local Story = (require :: any)(ReplicatedStorage:WaitForChild("content"):WaitForChild("Story"))
local AssetIds = (require :: any)(ReplicatedStorage:WaitForChild("shared"):WaitForChild("AssetIds"))
local Audio = (require :: any)(StarterPlayer:WaitForChild("StarterPlayerScripts"):WaitForChild("Audio"))

-- The Audio asset type (Enum.AssetType.Audio).
local AUDIO_ASSET_TYPE = 3

-- Every Cue the game names, sorted.
local function namedCues(): { string }
	local list = {}
	for cue in Cues.named(Story.story, Story.scenes) do
		table.insert(list, cue)
	end
	table.sort(list)
	return list
end

describe("audio", function()
	it("carries PlayCue to the client, held to the contract", function()
		local contract = Net.REMOTES.PlayCue
		expect(contract and contract.direction).toBe("toClient")
		expect((Net.check("PlayCue", table.pack("cue:sam_bark")))).toBe(true)
		expect((Net.check("PlayCue", table.pack(7)))).toBe(false)
	end)

	it("resolves every Cue the game names, or leaves it silent while it has no id", function()
		local master = SoundService:WaitForChild("Master") :: SoundGroup
		local silent = 0
		for _, cue in namedCues() do
			local sound = Audio.sound(cue, master, 0, false)
			if AssetIds[cue] then
				assert(sound, `{cue} has an id but no Sound`)
				expect(sound.SoundId).toBe(AssetIds[cue])
				expect(sound.SoundGroup).toBe(master)
				local info =
					MarketplaceService:GetProductInfoAsync(tonumber(string.match(AssetIds[cue], "%d+")) :: number)
				assert(info.AssetTypeId == AUDIO_ASSET_TYPE, `{cue} is asset type {info.AssetTypeId}, not audio`)
				sound:Destroy()
			else
				expect(sound).toBeNil()
				silent += 1
			end
		end
		print(`  {silent} Cue(s) silent until uploaded`)
	end)
end)

finish()
