--!strict
-- Smoke test: the published place loads in Luau Execution and is this game.
-- Runs after _prelude.luau (see tools/run-engine-tests).

describe("place", function()
	it("has a Workspace", function()
		expect(game:GetService("Workspace")).toBeTruthy()
	end)

	it("is named after the game", function()
		-- The name set on the Creator Dashboard (plan section 10): "Amy and the
		-- Rain Forest" for Release, "Amy and the Rain Forest (Dev)" for Dev.
		local prefix = "Amy and the Rain Forest"
		local info = game:GetService("MarketplaceService"):GetProductInfoAsync(game.PlaceId)
		print("  place name: " .. tostring(info.Name))
		expect(string.sub(info.Name, 1, #prefix)).toBe(prefix)
	end)

	it("contains the story scripts built from src/", function()
		expect(game:GetService("ServerScriptService"):FindFirstChild("StoryServer")).toBeTruthy()
		expect(game:GetService("ReplicatedStorage"):FindFirstChild("StoryData")).toBeTruthy()
	end)
end)

finish()
