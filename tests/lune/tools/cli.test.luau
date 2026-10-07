--!strict
-- The setup every tool shares: the Release refusal and the API key.
local H = require("./_harness")
local Cli = require("../../../tools/lib/cli")

local function target(universe: string, env: { [string]: string }, extra: { string }?): (Cli.Target?, string?)
	local args = { "--universe", universe, "--place", H.PLACE }
	for _, arg in extra or {} do
		table.insert(args, arg)
	end
	local mock = H.mock({ args = args, env = env })
	local ok, result = pcall(Cli.target, mock.ctx, "usage", {})
	return if ok then result else nil, if ok then nil else tostring(result)
end

print("cli")

H.test("refuses the Release universe without RELEASE_JOB", function()
	local _, err = target(H.RELEASE, H.env())
	H.contains(err or "", "refusing to target the Release universe")
end)

H.test("refuses the Release universe in a dry run too, however the id is written", function()
	local _, err = target("0" .. H.RELEASE, H.env(), { "--dry-run" })
	H.contains(err or "", "refusing to target the Release universe")
end)

H.test("refuses the Release universe when RELEASE_JOB is anything but 1", function()
	local _, err = target(H.RELEASE, H.env({ RELEASE_JOB = "true" }))
	H.contains(err or "", "refusing to target the Release universe")
end)

H.test("allows the Release universe with RELEASE_JOB=1", function()
	local result, err = target(H.RELEASE, H.env({ RELEASE_JOB = "1" }))
	H.eq(err, nil, "error")
	H.eq(result and result.universeId, H.RELEASE, "universe")
end)

H.test("refuses a real run when RELEASE_UNIVERSE_ID is unset", function()
	local _, err = target(H.DEV, { ROBLOX_DEV_API_KEY = H.KEY })
	H.contains(err or "", "RELEASE_UNIVERSE_ID is not set")
end)

H.test("allows a dry run with RELEASE_UNIVERSE_ID unset, and no key", function()
	local result, err = target(H.DEV, {}, { "--dry-run" })
	H.eq(err, nil, "error")
	H.eq(result and result.dryRun, true, "dry run")
end)

H.test("reads the key from the variable named by --key-env", function()
	local result = target(H.DEV, H.env({ OTHER_KEY = "other" }), { "--key-env", "OTHER_KEY" })
	H.eq(result and result.apiKey, "other", "api key")
end)

H.test("fails without a key", function()
	local _, err = target(H.DEV, { RELEASE_UNIVERSE_ID = H.RELEASE })
	H.contains(err or "", "ROBLOX_DEV_API_KEY is not set")
end)

H.test("rejects unknown options", function()
	local _, err = target(H.DEV, H.env(), { "--universe-id", "1" })
	H.contains(err or "", "unknown option --universe-id")
end)

return nil
