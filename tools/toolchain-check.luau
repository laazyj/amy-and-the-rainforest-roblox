--!strict
-- Compares the toolchain pins with the latest releases and rewrites the ones
-- that are behind; prints the PR body. See docs/MAINTENANCE.md.
-- lune run tools/toolchain-check > body.md
local Cli = require("./lib/cli")
local Toolchain = require("./lib/toolchain")
local fs = require("@lune/fs")

Cli.main(function(ctx)
	local changed, updates = Toolchain.check(ctx)
	for path, text in changed do
		fs.writeFile(path, text)
	end
	ctx.log(`{#updates} pin(s) behind`)
	ctx.out(Toolchain.summary(updates))
end)
