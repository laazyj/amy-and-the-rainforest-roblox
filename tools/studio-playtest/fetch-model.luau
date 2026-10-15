--!strict
-- Fetches a free Creator Store model through Roblox Studio on a Mac (plan
-- section 5.5's winning path, brief mac-002) and saves it as a binary .rbxm,
-- then prints its manifest entry for assets/manifest.json (docs/ASSETS.md).
-- Refuses a model that is not free or that carries scripts. Studio opens the
-- built place only to have a DataModel to insert into; nothing is saved to it.
-- lune run tools/studio-playtest/fetch-model --asset 12549617200 --name prop:low_poly_tree --out assets/meshes/low-poly-tree.rbxm
local serde = require("@lune/serde")

local Cli = require("../lib/cli")
local Fetch = require("./fetch")
local Studio = require("./studio")

local USAGE =
	"usage: lune run tools/studio-playtest/fetch-model --asset <id> --name <prop:name> --out <assets/meshes/file.rbxm> [--place <file.rbxl>]"

Cli.main(function(ctx)
	local values, dryRun = Cli.options(ctx.args, USAGE, { "asset", "name", "out", "place" })
	Studio.refuseDryRun(dryRun)
	local assetId = Cli.required(values, "asset")
	if not string.match(assetId, "^%d+$") then
		error("--asset must be a numeric asset id", 0)
	end
	local out = Cli.required(values, "out")
	if not string.match(out, "^assets/meshes/[%w_-]+%.rbxm$") then
		error("--out must be assets/meshes/<name>.rbxm", 0)
	end
	local name = Cli.required(values, "name")

	local bridge = Studio.bridge({ ctx = ctx })
	local ok, err = pcall(function()
		bridge.open(values.place or "build/AmyAndTheRainforest.rbxl")
		local path = bridge.insertAsset(assetId)
		-- A path with spaces in a name: index it as a string.
		local parent, leaf = string.match(path, "^(.*)%.([^%.]+)$")
		local expression = `{parent}[{string.format("%q", leaf :: string)}]`
		local described: Fetch.Described =
			serde.decode("json", bridge.run("Edit", Fetch.describeScript(expression, assetId)))
		local refusal = Fetch.refusal(described)
		if refusal then
			error(refusal, 0)
		end
		local bytes = Fetch.base64Decode(bridge.run("Edit", Fetch.serialiseScript(expression)))
		ctx.writeFile(out, bytes)
		ctx.log(`saved {out} ({#bytes} bytes): {described.name} by {described.creator}`)
		local entry = Fetch.entry(name, out, assetId, described, os.date("!%Y-%m-%d") :: string)
		ctx.out(serde.encode("json", entry, true))
	end)
	pcall(bridge.close)
	if not ok then
		error(err, 0)
	end
end)
