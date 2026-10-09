-- Story: the lookups the core makes on content, on the fixture Story.

local Story = require("../../../src/core/Story")
local fixture = require("./fixtureStory")

return function(t: any)
	local describe, it, expect, expectError = t.describe, t.it, t.expect, t.expectError

	describe("Story.quest", function()
		it("finds a Quest and its Chapter by id", function()
			local quest, chapter = Story.quest(fixture, "chapter2.pick")
			expect(quest and quest.kind).toBe("collect")
			expect(chapter and chapter.id).toBe("chapter2")
		end)

		it("finds nothing for an unknown or missing id", function()
			expect(Story.quest(fixture, "chapter9.nothing")).toBeNil()
			expect(Story.quest(fixture, nil)).toBeNil()
		end)
	end)

	describe("Story.after", function()
		it("gives the next Quest in the same Chapter", function()
			local quest, chapter = Story.after(fixture, "chapter1.greet")
			expect(quest and quest.id).toBe("chapter1.go_out")
			expect(chapter and chapter.id).toBe("chapter1")
		end)

		it("crosses into the next Chapter", function()
			local quest, chapter = Story.after(fixture, "chapter1.go_out")
			expect(quest and quest.id).toBe("chapter2.pick")
			expect(chapter and chapter.id).toBe("chapter2")
		end)

		it("gives nothing after the last Quest", function()
			expect(Story.after(fixture, "chapter2.pick")).toBeNil()
		end)
	end)

	describe("Story.displayName", function()
		it("shows the Narrator as itself and a Character by its display name", function()
			expect(Story.displayName(fixture, "Narrator")).toBe("Narrator")
			expect(Story.displayName(fixture, "Guide")).toBe("the Guide")
			expect(Story.displayName(fixture, "Hero")).toBe("the Hero")
		end)

		it("rejects an unknown Speaker", function()
			expectError(function()
				Story.displayName(fixture, "Stranger")
			end, "unknown Speaker Stranger")
		end)
	end)

	describe("Story.shownLines", function()
		it("keeps only the display name and the text of each Line", function()
			expect(Story.shownLines(fixture, { { speaker = "Guide", text = "Pick two.", canon = true } })).toEqual({
				{ speaker = "the Guide", text = "Pick two." },
			})
		end)
	end)

	describe("Story.character", function()
		it("finds a Character by id", function()
			local guide = Story.character(fixture, "Guide")
			expect(guide and guide.home).toBe("GuideHome")
			expect(Story.character(fixture, "Nobody")).toBeNil()
		end)
	end)
end
