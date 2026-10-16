--[[
	The Title screen's lettering (src/content/title.luau): each family is a
	font in the asset manifest, which the binder finds in AssetIds, or one of
	Roblox's built-in families; each weight is a FontWeight name.
]]

local Manifest = require("../../../tools/lib/manifest")
local bootstrap = require("../bootstrap")
local title = require("../../../src/content/title")

-- Enum.FontWeight's names, which Lune has no Enum to read.
local WEIGHTS = table.freeze({
	Thin = true,
	ExtraLight = true,
	Light = true,
	Regular = true,
	Medium = true,
	SemiBold = true,
	Bold = true,
	ExtraBold = true,
	Heavy = true,
})

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("Title screen lettering", function()
		local manifest = Manifest.decode(bootstrap.readSource(Manifest.PATH))
		local fonts: { [string]: boolean } = {}
		for _, entry in manifest.assets do
			if entry.kind == Manifest.FONT then
				fonts[entry.name] = true
			end
		end

		for _, part in { "heading", "pill" } do
			local lettering = (title :: any)[part]
			it(`names the {part}'s family as a manifest font or a built-in family`, function()
				local family: string = lettering.family
				local builtIn = string.match(family, "^rbxasset://fonts/families/%w+%.json$") ~= nil
				expect(fonts[family] or builtIn).toBe(true)
			end)

			it(`gives the {part} a FontWeight`, function()
				expect(WEIGHTS[lettering.weight]).toBe(true)
			end)
		end

		it("is the website's Dancing Script, Bold over a SemiBold pill", function()
			expect(title.heading).toEqual({ family = "font:dancing_script", weight = "Bold" })
			expect(title.pill).toEqual({ family = "font:dancing_script", weight = "SemiBold" })
		end)
	end)
end
