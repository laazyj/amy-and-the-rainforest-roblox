--!strict
-- Tier 0 asset check: assets/manifest.json is valid, every asset id in src/
-- is in it, and src/shared/AssetIds.luau matches it. See docs/ASSETS.md.
-- lune run tools/check-assets
local Cli = require("./lib/cli")
local Manifest = require("./lib/manifest")

Cli.main(function(ctx)
	local problems = Manifest.check(ctx)
	for _, problem in problems do
		ctx.log(problem)
	end
	if #problems > 0 then
		error(`{#problems} asset problem(s)`, 0)
	end
	ctx.log(`{Manifest.PATH}: ok`)
end)
