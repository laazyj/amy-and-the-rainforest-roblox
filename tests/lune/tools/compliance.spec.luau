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

		it("does not match a surname inside a longer word", function()
			expect(Compliance.names("assets/manifest.json", "Smithson and blacksmith", { "Smith" })).toEqual({})
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
