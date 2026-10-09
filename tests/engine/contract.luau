--!strict
-- The remote contract (plan section 2.4, "tier 2 remote contract"): every
-- server -> client message in the golden file goes through the validator
-- the client wraps its remotes in (Net.guard, src/core/Net), as built into
-- the place, and must hold. The golden file is every message a whole
-- playthrough sends, so this covers every payload a player's client gets.
--
-- JSON loses a trailing nil (SetObjective's `[null]` decodes to an empty
-- list), so each message's argument count is taken from the contract, and
-- re-encoding the decoded message must give back the golden line: the
-- payload checked is exactly the one recorded.

local Golden = include("tests/engine/_golden.luau")
local GOLDEN = fixture("tests/fixtures/golden/walkthrough.json")

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = (require :: any)(ReplicatedStorage:WaitForChild("core"):WaitForChild("Net"))

describe("remote contract", function()
	local lines = Golden.lines(GOLDEN)

	it("has the golden file's messages to check", function()
		print(`  {#lines} messages in the golden file`)
		expect(#lines > 0).toBe(true)
	end)

	it("passes every server -> client payload in the golden file through the client's validator", function()
		local counts: { [string]: number } = {}
		for i, line in lines do
			local message = HttpService:JSONDecode(line)
			local contract = Net.REMOTES[message.remote]
			assert(contract, `message {i}: unknown remote {message.remote}`)
			assert(contract.direction == "toClient", `message {i}: {message.remote} does not go to the client`)
			local args: any = table.clone(message.args)
			args.n = #contract.args
			assert(Golden.messageLine(message.remote, message.quest, args) == line, `message {i} does not round-trip`)

			local rejected: string? = nil
			Net.guard(message.remote, function() end, function(reason)
				rejected = reason
			end)(table.unpack(args, 1, args.n))
			assert(rejected == nil, `message {i}: {rejected}`)
			counts[message.remote] = (counts[message.remote] or 0) + 1
		end
		for remote, contract in Net.REMOTES do
			if contract.direction == "toClient" then
				print(`  {remote}: {counts[remote] or 0} payloads hold`)
				expect((counts[remote] or 0) > 0).toBe(true)
			end
		end
	end)
end)

finish()
