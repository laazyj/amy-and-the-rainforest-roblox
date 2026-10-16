-- The paths whose change alters what is on screen: CI's prompt to label a
-- pull request `needs-playtest` (brief mac-003, Must A4).
local VisualPaths = require("../../../tools/lib/visual-paths")
local bootstrap = require("../bootstrap")
local fs = require("@lune/fs")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("visual-paths", function()
		it("lists exactly the brief's paths", function()
			expect(VisualPaths.PATHS).toEqual({
				"src/client/",
				"src/core/ScreenLayout.luau",
				"src/content/palette.luau",
				"src/content/title.luau",
				"src/content/hints.luau",
				"docs/design/feel.md",
				"assets/images/",
			})
		end)

		it("names only paths that exist, so a rename cannot drop one silently", function()
			for _, path in VisualPaths.PATHS do
				local full = `{bootstrap.REPO_ROOT}/{path}`
				local exists = if string.sub(path, -1) == "/" then fs.isDir(full) else fs.isFile(full)
				expect(`{path} {if exists then "exists" else "is missing"}`).toBe(`{path} exists`)
			end
		end)

		it("matches a listed file, and anything under a listed directory", function()
			expect(VisualPaths.matches({
				"src/client/StoryClient.client.luau",
				"src/core/ScreenLayout.luau",
				"assets/images/title/hero.png",
				"docs/design/feel.md",
			})).toEqual({
				"src/client/StoryClient.client.luau",
				"src/core/ScreenLayout.luau",
				"assets/images/title/hero.png",
				"docs/design/feel.md",
			})
		end)

		it("matches nothing else", function()
			expect(VisualPaths.matches({
				"",
				"src/core/Story.luau",
				"src/core/ScreenLayout.luau.bak",
				"src/clientele.luau",
				"src/content/chapters/chapter1.luau",
				"docs/design/feel.md.orig",
				"assets/images",
				"tests/lune/core/ScreenLayout.spec.luau",
			})).toEqual({})
		end)
	end)
end
