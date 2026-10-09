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

	it("contains the Story built from src/", function()
		local scripts = game:GetService("ServerScriptService")
		for _, name in { "StoryServer", "SceneServer" } do
			local found = scripts:FindFirstChild(name)
			expect(found and found.ClassName).toBe("Script")
		end
		for _, name in { "StoryHost", "SceneBuilder", "WorldImpl", "PromptBridge", "CharacterHost" } do
			local found = scripts:FindFirstChild(name)
			expect(found and found.ClassName).toBe("ModuleScript")
		end
		local storage = game:GetService("ReplicatedStorage")
		for _, path in { { "core", "StoryEngine" }, { "content", "Story" }, { "shared", "Net" } } do
			local folder = storage:FindFirstChild(path[1])
			local found = folder and folder:FindFirstChild(path[2])
			expect(found and found.ClassName).toBe("ModuleScript")
		end
	end)

	it("requires the core and the content by string inside the engine", function()
		local storage = game:GetService("ReplicatedStorage")
		local content = (require :: any)(storage:WaitForChild("content"):WaitForChild("Story"))
		expect(content.story.title).toBe("Amy and the Rain Forest")
		expect(#content.story.chapters).toBe(4)
	end)

	-- Lighting.Technology is not readable here (Luau Execution lacks the
	-- RobloxScript capability); tests/lune/place/lighting.spec.luau checks it
	-- in the built place instead.
end)

finish()
