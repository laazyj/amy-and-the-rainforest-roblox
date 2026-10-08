-- The setup every tool shares: the Release refusal and the API key.
local F = require("../fixtures/opencloud")
local Cli = require("../../../tools/lib/cli")

local function target(universe: string, env: { [string]: string }, extra: { string }?): (Cli.Target?, string?)
	local args = { "--universe", universe, "--place", F.PLACE }
	for _, arg in (extra or {}) :: { string } do
		table.insert(args, arg)
	end
	local mock = F.mock({ args = args, env = env })
	local ok, result = pcall(Cli.target, mock.ctx, "usage", {})
	return if ok then result else nil, if ok then nil else tostring(result)
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("cli", function()
		it("refuses the Release universe without RELEASE_JOB", function()
			local _, err = target(F.RELEASE, F.env())
			expect(err).toContain("refusing to target the Release universe")
		end)

		it("refuses the Release universe in a dry run too, however the id is written", function()
			local _, err = target("0" .. F.RELEASE, F.env(), { "--dry-run" })
			expect(err).toContain("refusing to target the Release universe")
		end)

		it("refuses the Release universe when RELEASE_JOB is anything but 1", function()
			local _, err = target(F.RELEASE, F.env({ RELEASE_JOB = "true" }))
			expect(err).toContain("refusing to target the Release universe")
		end)

		it("allows the Release universe with RELEASE_JOB=1", function()
			local result, err = target(F.RELEASE, F.env({ RELEASE_JOB = "1" }))
			expect(err).toBeNil()
			expect(result and result.universeId).toBe(F.RELEASE)
		end)

		it("refuses the Release place when RELEASE_PLACE_ID is set", function()
			local _, err = target(F.DEV, F.env({ RELEASE_PLACE_ID = F.PLACE }))
			expect(err).toContain(`refusing to target the Release place ({F.PLACE})`)
		end)

		it("allows the Release place with RELEASE_JOB=1", function()
			local _, err = target(F.DEV, F.env({ RELEASE_PLACE_ID = F.PLACE, RELEASE_JOB = "1" }))
			expect(err).toBeNil()
		end)

		it("refuses a non-numeric RELEASE_PLACE_ID", function()
			local _, err = target(F.DEV, F.env({ RELEASE_PLACE_ID = "release" }))
			expect(err).toContain("RELEASE_PLACE_ID is set but is not a numeric id")
		end)

		it("refuses a real run when RELEASE_UNIVERSE_ID is unset", function()
			local _, err = target(F.DEV, { ROBLOX_DEV_API_KEY = F.KEY })
			expect(err).toContain("RELEASE_UNIVERSE_ID is not set")
		end)

		it("allows a dry run with RELEASE_UNIVERSE_ID unset, and no key", function()
			local result, err = target(F.DEV, {}, { "--dry-run" })
			expect(err).toBeNil()
			expect(result and result.dryRun).toBe(true)
		end)

		it("reads the key from the variable named by --key-env", function()
			local result = target(F.DEV, F.env({ OTHER_KEY = "other" }), { "--key-env", "OTHER_KEY" })
			expect(result and result.apiKey).toBe("other")
		end)

		it("fails without a key", function()
			local _, err = target(F.DEV, { RELEASE_UNIVERSE_ID = F.RELEASE })
			expect(err).toContain("ROBLOX_DEV_API_KEY is not set")
		end)

		it("rejects unknown options", function()
			local _, err = target(F.DEV, F.env(), { "--universe-id", "1" })
			expect(err).toContain("unknown option --universe-id")
		end)
	end)
end
