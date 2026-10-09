--[[
	The Net contract: the remotes and their payloads, the World commands that
	reach the client, and the rejection of malformed payloads.
]]

local Net = require("../../../src/core/Net")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("Net.check", function()
		it("accepts each remote's payload", function()
			expect(Net.check("ShowDialogue", table.pack({ { speaker = "Narrator", text = "She rushed Home..." } }))).toBe(
				true
			)
			expect(Net.check("SetObjective", table.pack("Tell Mum"))).toBe(true)
			expect(Net.check("SetObjective", table.pack(nil))).toBe(true)
			expect(Net.check("ShowChapter", table.pack("Chapter One", "One Beautyfull Sunday"))).toBe(true)
			expect(Net.check("ShowEnding", table.pack("The end ♥", "a story by Clara"))).toBe(true)
			expect(Net.check("DialogueFinished", { n = 0 })).toBe(true)
			expect(Net.check("ClientReady", { n = 0 })).toBe(true)
		end)

		local malformed: { { any } } = {
			{ "Shout", { n = 0 }, "unknown remote Shout" },
			{ "ShowDialogue", table.pack({}), "argument 1 must be lines" },
			{ "ShowDialogue", table.pack("WOOF!"), "argument 1 must be lines" },
			{ "ShowDialogue", table.pack({ { speaker = "Sam the Dog", text = 1 } }), "argument 1 must be lines" },
			{ "SetObjective", table.pack(42), "argument 1 must be string?" },
			{ "ShowChapter", table.pack("Chapter One"), "argument 2 must be string" },
			{ "ShowEnding", table.pack("a", "b", "c"), "takes 2 argument(s), got 3" },
			{ "DialogueFinished", table.pack("done"), "takes 0 argument(s), got 1" },
			{ "ClientReady", table.pack(true), "takes 0 argument(s), got 1" },
		}
		for _, case in malformed do
			it(`rejects a malformed {case[1]} payload: {case[3]}`, function()
				local ok, reason = Net.check(case[1], case[2])
				expect(ok).toBe(false)
				expect(reason).toContain(case[3])
			end)
		end
	end)

	describe("Net.message", function()
		it("carries ShowDialogue, SetObjective and both cards to the client", function()
			local lines = { { speaker = "Amy", text = "Deal." } }
			local remote, args = Net.message({ kind = "ShowDialogue", lines = lines })
			expect(remote).toBe("ShowDialogue")
			expect(args).toEqual(table.pack(lines))
			remote, args = Net.message({ kind = "SetObjective", text = nil })
			expect(remote).toBe("SetObjective")
			expect(args and args.n).toBe(1)
			remote = Net.message({ kind = "ShowChapterCard", title = "a", subtitle = "b", ending = false })
			expect(remote).toBe("ShowChapter")
			remote, args =
				Net.message({ kind = "ShowChapterCard", title = "The end ♥", subtitle = "b", ending = true })
			expect(remote).toBe("ShowEnding")
			expect(args).toEqual(table.pack("The end ♥", "b"))
		end)

		it("keeps the other World commands on the server", function()
			expect(Net.message({ kind = "MoveCharacter", character = "Sam", spot = "Farm" })).toBeNil()
			expect(Net.message({ kind = "Wait", seconds = 3.2 })).toBeNil()
		end)

		it("only names remotes in the contract, sent to the client", function()
			for _, command in
				{
					{ kind = "ShowDialogue", lines = { { speaker = "Amy", text = "Hi" } } },
					{ kind = "SetObjective", text = "x" },
					{ kind = "ShowChapterCard", title = "a", subtitle = "b", ending = false },
					{ kind = "ShowChapterCard", title = "a", subtitle = "b", ending = true },
				} :: { any }
			do
				local remote, args = Net.message(command)
				assert(remote and args, command.kind)
				expect(Net.REMOTES[remote].direction).toBe("toClient")
				expect(Net.check(remote, args)).toBe(true)
			end
		end)
	end)
end
