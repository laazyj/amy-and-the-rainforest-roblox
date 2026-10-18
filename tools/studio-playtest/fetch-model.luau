--!strict
-- Fetches a free Creator Store model through Roblox Studio on a Mac (plan
-- section 5.5's winning path, brief mac-002) and saves it as a binary .rbxm,
-- then prints its manifest entry for assets/manifest.json (docs/ASSETS.md).
-- Refuses a model that is not free or that carries scripts. Studio opens the
-- built place only to have a DataModel to insert into; nothing is saved to it.
-- lune run tools/studio-playtest/fetch-model --asset 12549617200 --name prop:low_poly_tree --out assets/meshes/low-poly-tree.rbxm
-- A Character model goes in assets/meshes/characters, named by its Character:
-- --name character:Sam --out assets/meshes/characters/Sam.rbxm (docs/ASSETS.md).
local serde = require("@lune/serde")

local Cli = require("../lib/cli")
local Manifest = require("../lib/manifest")
local Fetch = require("./fetch")
local Studio = require("./studio")

local USAGE =
	"usage: lune run tools/studio-playtest/fetch-model --asset <id> --name <prop:name | character:Id> --out <assets/meshes/file.rbxm | assets/meshes/characters/Id.rbxm> [--place <file.rbxl>]"

Cli.main(function(ctx)
	local values, dryRun = Cli.options(ctx.args, USAGE, { "asset", "name", "out", "place" })
	Studio.refuseDryRun(dryRun)
	local assetId = Cli.required(values, "asset")
	if not string.match(assetId, "^%d+$") then
		error("--asset must be a numeric asset id", 0)
	end
	local out = Cli.required(values, "out")
	local name = Cli.required(values, "name")
	local characterFile = Manifest.characterModelPath(name)
	if characterFile and out ~= characterFile then
		error(`--out must be {characterFile} for {name}`, 0)
	elseif not characterFile and not string.match(out, "^assets/meshes/[%w_-]+%.rbxm$") then
		error("--out must be assets/meshes/<name>.rbxm", 0)
	end

	local bridge = Studio.bridge({ ctx = ctx })
	local ok, err = pcall(function()
		bridge.open(values.place or "build/AmyAndTheRainforest.rbxl")
		local described, bytes = Fetch.fetch(bridge, assetId, Fetch.folderName(assetId, os.time()))
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
