--!strict
-- Fixtures for the asset manifest specs: a made-up image and manifest
-- entries built from one valid entry.

local Manifest = require("../../../tools/lib/manifest")

local Fixtures = {}

Fixtures.PNG_PATH = "assets/images/card-chapter2.png"
Fixtures.PNG = "\137PNG card"
Fixtures.HASH = Manifest.hash(Fixtures.PNG)

-- In `entry` overrides, removes the field.
Fixtures.REMOVE = table.freeze({})

-- The fields that mark an entry as uploaded (as asset 4242, in review).
Fixtures.UPLOADED = table.freeze({ assetId = "4242", sha256 = Fixtures.HASH, moderation = "reviewing" })

-- A valid image entry, not yet uploaded, with each `overrides` table applied in turn.
function Fixtures.entry(...: { [string]: any }): Manifest.Entry
	local e: { [string]: any } = {
		name = "card:chapter2",
		kind = "image",
		path = Fixtures.PNG_PATH,
		moderation = "pending",
		upload = true,
		placeholder = false,
		amy = "from-behind",
		creator = "Clara",
		licence = "owner",
		origin = "the website's hero drawing",
	}
	for _, overrides in { ... } do
		for key, value in overrides do
			e[key] = if value == Fixtures.REMOVE then nil else value
		end
	end
	return e :: any
end

function Fixtures.manifest(...: Manifest.Entry): Manifest.Manifest
	return { version = 1, assets = { ... } }
end

-- A repository holding `m`, the AssetIds it generates, the image, and `extra` files.
function Fixtures.files(m: Manifest.Manifest, extra: { [string]: string }?): { [string]: string }
	local files = {
		[Manifest.PATH] = Manifest.encode(m),
		[Manifest.ASSET_IDS_PATH] = Manifest.generateAssetIds(m),
		[Fixtures.PNG_PATH] = Fixtures.PNG,
	}
	for path, text in (extra or {}) :: { [string]: string } do
		files[path] = text
	end
	return files
end

return Fixtures
