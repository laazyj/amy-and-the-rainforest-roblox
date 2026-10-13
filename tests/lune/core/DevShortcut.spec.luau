-- DevShortcut: the Dev-only chat commands that jump to a Quest.

local DevShortcut = require("../../../src/core/DevShortcut")
local fixture = require("./fixtureStory")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	local function parse(text: string): (string?, string?)
		return DevShortcut.parse(fixture, text)
	end

	describe("DevShortcut.parse", function()
		it("jumps /chapter N to the first Quest of Chapter N", function()
			for n, chapter in fixture.chapters do
				expect(parse(`/chapter {n}`)).toBe(chapter.quests[1].id)
			end
		end)

		it("jumps /quest <id> to that Quest", function()
			local quest = fixture.chapters[#fixture.chapters].quests[1]
			expect(parse(`  /quest {quest.id} `)).toBe(quest.id)
		end)

		for _, case in
			{
				{ "/chapter 0", "there is no Chapter 0" },
				{ "/chapter two", "there is no Chapter two" },
				{ "/quest chapter9.fly", "there is no Quest chapter9.fly" },
				{ "/chapter", "usage: /chapter <argument> or /quest <argument>" },
				{ "/dance 3", "usage:" },
			}
		do
			it(`refuses "{case[1]}"`, function()
				local questId, reason = parse(case[1])
				expect(questId).toBeNil()
				expect(reason).toContain(case[2])
			end)
		end
	end)
end
