--[[
	Fault: every Fault the server can report is named in the glossary's
	Faults table and nowhere else, and reads as one warning line.
]]

local Fault = require("../../../src/core/Fault")
local glossary = require("../content/glossary")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("Fault", function()
		it("names exactly the glossary's Faults", function()
			local names = {}
			for name in Fault.NAMES do
				names[name] = true
			end
			expect(names).toEqual(glossary.names("Faults"))
		end)

		it("gives each Fault a name that reads as an analytics event name", function()
			for name in Fault.NAMES do
				expect(string.match(name, "^[a-z]+_[a-z_]+$") ~= nil).toBe(true)
			end
		end)

		it("writes a player's Fault as one line: prefix, name, player, why", function()
			expect(Fault.line("save_unreadable", 123, "progress: quest must be a string")).toBe(
				"[Fault] save_unreadable player 123: progress: quest must be a string"
			)
		end)

		it("leaves the player out of a Fault of the whole server", function()
			expect(Fault.line("save_unavailable", nil, "no package")).toBe("[Fault] save_unavailable: no package")
		end)

		it("refuses a Fault with no name in the glossary", function()
			expect(function()
				Fault.line("save_lost" :: any, 1, "?")
			end).toThrow()
		end)
	end)
end
