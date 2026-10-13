--[[
	The compliance guards (tools/lib/compliance.luau), run by `tools/guard
	names` and `tools/guard store-links` in tier 0: no surname of the family
	under src/, assets/ or docs/store/, and no web address in the store page
	kit. The repository holds to both.
]]

local Compliance = require("../../../tools/lib/compliance")
local Files = require("../../../tools/lib/files")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("the surname guard", function()
		it("finds a surname as a whole word in any case, with its line", function()
			local found = Compliance.names("docs/store/x.md", "a story by Clara\nby Clara SMITH\nsmith.", { "Smith" })
			expect(found).toEqual({
				'docs/store/x.md:2: a surname; credits say "Clara" only (by Clara SMITH)',
				'docs/store/x.md:3: a surname; credits say "Clara" only (smith.)',
			})
		end)

		for _, joined in { "ClaraSmith", "clarasmith", "clara_smith", "SMITH's", "@smith", "Smithson" } do
			it(`finds a surname joined to other words: {joined}`, function()
				expect(#Compliance.names("src/content/x.luau", `by {joined}`, { "Smith" })).toBe(1)
			end)
		end

		it("allows only the exact provenance string, and only in the Manifest", function()
			local exact = Compliance.ALLOWED["assets/manifest.json"][1]
			local surname: string? = nil
			for _, name in Compliance.SURNAMES do
				if string.find(string.lower(exact), string.lower(name), 1, true) then
					surname = name
				end
			end
			assert(surname, "the allowed string holds a surname")
			expect(Compliance.names("assets/manifest.json", `"origin": "{exact}@4940d10"`)).toEqual({})
			-- the same string anywhere else, or the name on its own in the Manifest, is caught
			expect(#Compliance.names("docs/store/x.md", exact)).toBe(1)
			expect(#Compliance.names("assets/manifest.json", `"creator": "Clara {surname}"`)).toBe(1)
		end)

		it("guards the family's surnames by default, and a double-barrelled name by either half", function()
			expect(#Compliance.SURNAMES >= 2).toBe(true)
			local double = `Clara {Compliance.SURNAMES[1]}-{Compliance.SURNAMES[2]}`
			expect(#Compliance.names("src/content/x.luau", double)).toBe(1)
		end)

		it("reads text files only", function()
			expect(Compliance.isText("assets/manifest.json")).toBe(true)
			expect(Compliance.isText("docs/store/description.md")).toBe(true)
			expect(Compliance.isText("assets/images/title.png")).toBe(false)
		end)

		it("finds no surname under src/, assets/ or docs/store/", function()
			expect(Files.each(Compliance.NAMED, Compliance.names, Compliance.isText)).toEqual({})
		end)
	end)

	describe("the purchases-and-text guard", function()
		it("finds a purchase prompt, MarketplaceService and a TextBox", function()
			local source = 'local M = game:GetService("MarketplaceService")\nM:PromptProductPurchase(p, 1)\n'
				.. 'Instance.new("TextBox")\nlocal ok = 1'
			expect(#Compliance.purchasesAndText("src/client/x.luau", source)).toBe(3)
		end)

		it("finds nothing to buy or type under src/", function()
			expect(Files.each({ "src" }, Compliance.purchasesAndText)).toEqual({})
		end)
	end)

	describe("Compliance.isLink", function()
		-- the reviewer's table: each was missed before, or caught already
		for _, text in
			{
				"visit roblox.com/games/1",
				"discord.gg/abc",
				"amyforest.co.uk",
				"a@b.com",
				"follow @amyforest",
				"example[.]com",
				"example (dot) com",
				"x.y.com",
				"HTTPS://x",
				"WWW.example",
				"[[https://example]]",
			}
		do
			it(`finds a web address in "{text}"`, function()
				expect(Compliance.isLink(text)).toBe(true)
			end)
		end

		for _, text in
			{
				"chapter3.meet_fox",
				"zone:ForestGap",
				"src/core/Story.luau",
				"description.md",
				"Dr. Who and Mrs. Smith",
				"It was a bautyfull paradise!",
				"Dad... can I go?",
			}
		do
			it(`leaves "{text}" alone`, function()
				expect(Compliance.isLink(text)).toBe(false)
			end)
		end
	end)

	describe("the store page kit's links guard", function()
		it("finds a scheme or a www. host, in any case", function()
			expect(Compliance.links("docs/store/x.md", "see HTTPS://example.com\nwww.example.com\nfine")).toEqual({
				"docs/store/x.md:1: a web address; the store page links to nothing (see HTTPS://example.com)",
				"docs/store/x.md:2: a web address; the store page links to nothing (www.example.com)",
			})
		end)

		it("leaves a relative link between the kit's own files alone", function()
			expect(Compliance.links("docs/store/x.md", "[the art](art.md)")).toEqual({})
		end)

		it("finds no web address in docs/store/", function()
			expect(Files.each(Compliance.UNLINKED, Compliance.links, Compliance.isText)).toEqual({})
		end)
	end)
end
