-- DevShortcut: the Dev-only chat commands that jump to a Quest or show the
-- Title screen.

local DevShortcut = require("../../../src/core/DevShortcut")
local fixture = require("./fixtureStory")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	local function parse(text: string): (DevShortcut.Shortcut?, string?)
		return DevShortcut.parse(fixture, text)
	end

	describe("DevShortcut.parse", function()
		it("jumps /chapter N to the first Quest of Chapter N", function()
			for n, chapter in fixture.chapters do
				expect(parse(`/chapter {n}`)).toEqual({ kind = "jump", quest = chapter.quests[1].id })
			end
		end)

		it("jumps /quest <id> to that Quest", function()
			local quest = fixture.chapters[#fixture.chapters].quests[1]
			expect(parse(`  /quest {quest.id} `)).toEqual({ kind = "jump", quest = quest.id })
		end)

		it("shows the Title screen on /title, with no argument", function()
			expect(parse("/title")).toEqual({ kind = "title" })
			expect(parse("  /title  ")).toEqual({ kind = "title" })
		end)

		it("lists /title among the chat commands", function()
			expect(DevShortcut.COMMANDS).toEqual({ "/chapter", "/quest", "/title" })
		end)

		for _, case in
			{
				{ "/chapter 0", "there is no Chapter 0" },
				{ "/chapter two", "there is no Chapter two" },
				{ "/quest chapter9.fly", "there is no Quest chapter9.fly" },
				{ "/chapter", "usage: /chapter <argument>, /quest <argument>, /title" },
				{ "/chapter2", "usage:" },
				{ "/chapter 2 3", "usage:" },
				{ "/title 2", "usage:" },
				{ "/titles", "usage:" },
				{ "/dance 3", "usage:" },
			}
		do
			it(`refuses "{case[1]}"`, function()
				local shortcut, reason = parse(case[1])
				expect(shortcut).toBeNil()
				expect(reason).toContain(case[2])
			end)
		end
	end)
end
