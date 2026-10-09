--!strict
-- Single player is an invariant (plan section 2.1): the place admits one
-- player. Max Players is a setting of the place on the Creator Dashboard,
-- not part of a place version, so this asserts the Dev place's server
-- size as a task's server sees it; the Release place's is a line of
-- docs/RELEASE_CHECKLIST.md.

describe("single player", function()
	it("admits one player: Players.MaxPlayers is 1", function()
		local value = game:GetService("Players").MaxPlayers
		print(`  Players.MaxPlayers: {value}`)
		expect(value).toBe(1)
	end)
end)

finish()
