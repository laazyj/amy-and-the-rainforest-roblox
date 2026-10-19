--!strict
-- The asset manifest, assets/manifest.json: every asset the game references,
-- with where it came from, its licence, its Roblox asset id once uploaded and
-- its moderation status. See docs/ASSETS.md.
--
-- Pure: files come in through the context, so tests use the mock filesystem.
-- Used by tools/check-assets.luau (tier 0) and tools/upload-assets.luau.

local Cli = require("./cli")
local OpenCloud = require("../opencloud")
local serde = require("@lune/serde")

export type Entry = {
	name: string,
	kind: string,
	path: string?,
	assetId: string?,
	sha256: string?,
	moderation: string,
	upload: boolean,
	placeholder: boolean,
	amy: string?,
	creator: string,
	licence: string,
	attribution: string?,
	origin: string,
}

export type Manifest = { version: number, assets: { Entry } }

local Manifest = {}

Manifest.PATH = "assets/manifest.json"
Manifest.ASSET_IDS_PATH = "src/shared/AssetIds.luau"

-- The prefix of an asset name says what the game uses it as.
Manifest.NAME_PREFIXES = table.freeze({
	card = true, -- a Chapter card or the end card
	ui = true, -- a frame, motif or screen in the UI
	store = true, -- the icon or a thumbnail on the store page
	ref = true, -- a Character reference; not shown in the game
	cue = true, -- a Cue: a sound or effect
	music = true, -- a Cue: a music track
	narration = true, -- a Chapter's narration file
	prop = true, -- a Prop's model
	character = true, -- a Character model: a Character with its Humanoid and animations
	font = true, -- a Creator Store font family, referenced by id
	catalog = true, -- a Catalog item a Description wears, referenced by id
})

-- The kinds referenced by their Creator Store id, never uploaded, so with
-- no file: a font family, a track from Roblox's audio library, and an
-- avatar item from the Marketplace, free or paid (a Catalog item).
Manifest.FONT = "font"
Manifest.LIBRARY_AUDIO = "library-audio"
Manifest.CATALOG = "catalog"
Manifest.REFERENCED = table.freeze({
	[Manifest.FONT] = "a font",
	[Manifest.LIBRARY_AUDIO] = "a library-audio track",
	[Manifest.CATALOG] = "a Catalog item",
})
-- The kinds whose Asset names have a prefix of their own, and that prefix.
Manifest.KIND_PREFIXES = table.freeze({ [Manifest.FONT] = "font", [Manifest.CATALOG] = "catalog" })

Manifest.LICENCES = table.freeze({
	owner = true, -- made for this game by the owner's family (Clara's work), or generated here
	["creator-store-free"] = true, -- free on the Creator Store (or the Marketplace, for a Catalog item)
	marketplace = true, -- a paid Catalog item the game dresses Amy in; nothing is bought
	cc0 = true,
	["cc-by"] = true, -- needs `attribution`
	synthesised = true, -- audio generated for this game
})

-- Where a Character model's file is: the place file holds this folder
-- (ServerStorage.CharacterModels, default.project.json), one model per
-- Character, named by its id.
Manifest.CHARACTER_MODELS = "assets/meshes/characters"

-- The file of the Character model named `name` (`character:<id>`), or nil
-- for a name of another kind.
function Manifest.characterModelPath(name: string): string?
	local id = string.match(name, "^character:([%w_]+)$")
	return if id then `{Manifest.CHARACTER_MODELS}/{id}.rbxm` else nil
end

-- `pending` until uploaded; then what Roblox moderation says.
Manifest.MODERATION = table.freeze({ pending = true, reviewing = true, approved = true, rejected = true })

-- What an image shows of Amy. Her face is never seen, so there is no third value.
Manifest.AMY = table.freeze({ absent = true, ["from-behind"] = true })

-- Field order when the manifest is written back, so a hand-edited file and
-- one the uploader rewrote read the same.
local FIELDS = {
	"name",
	"kind",
	"path",
	"assetId",
	"sha256",
	"moderation",
	"upload",
	"placeholder",
	"amy",
	"creator",
	"licence",
	"attribution",
	"origin",
}

local IS_FIELD: { [string]: boolean } = {}
for _, field in FIELDS do
	IS_FIELD[field] = true
end

-- Where an asset id hides in source, matched against the lowercased line: the
-- content scheme, the old and the delivery URLs (`asset/?id=` and
-- `asset?id=`), and thumbnails. Each captures the digits after it, which are
-- empty when the id is not written out (`"rbxassetid://" .. id`).
local ID_PATTERNS = { "rbxassetid://(%d*)", "asset/?%?id=(%d*)", "rbxthumb://[%w=&]-id=(%d*)" }

-- Only AssetIds.luau may build a content id from a number.
local FROM_ASSET_ID = "content.fromassetid("

-- The project file Rojo builds from, scanned with src/.
local PROJECT_FILE = "default.project.json"

local USE_ASSET_IDS = "look the Asset up in AssetIds instead"

function Manifest.decode(text: string): Manifest
	local ok, decoded = pcall(serde.decode, "json" :: any, text)
	if not ok then
		error(`{Manifest.PATH} is not valid JSON: {decoded}`, 0)
	end
	return decoded :: Manifest
end

function Manifest.encode(manifest: Manifest): string
	local blocks = {}
	for _, entry in manifest.assets do
		local fields = {}
		for _, field in FIELDS do
			local value = (entry :: any)[field]
			if value ~= nil or field == "assetId" then
				table.insert(fields, `      "{field}": {serde.encode("json", value)}`)
			end
		end
		table.insert(blocks, `    \{\n{table.concat(fields, ",\n")}\n    }`)
	end
	local assets = if #blocks > 0 then `[\n{table.concat(blocks, ",\n")}\n  ]` else "[]"
	return `\{\n  "version": {manifest.version},\n  "assets": {assets}\n}\n`
end

-- The SHA-256 of a file, as lowercase hex.
function Manifest.hash(contents: string): string
	return serde.hash("sha256", contents)
end

-- Whether an entry needs uploading, given its file's hash: never uploaded, or
-- its file changed since.
-- Roblox cannot update an image or a sound in place, so a changed file is a new asset.
function Manifest.isPending(entry: Entry, sha256: string): boolean
	return entry.upload and (entry.assetId == nil or entry.sha256 ~= sha256)
end

-- A set's keys, sorted and listed, for messages.
local function keys(set: { [string]: any }): string
	local list = {}
	for key in set do
		table.insert(list, key)
	end
	table.sort(list)
	return table.concat(list, ", ")
end

local function nonEmpty(value: any): boolean
	return type(value) == "string" and string.match(value, "%S") ~= nil
end

-- A font, a library-audio track or a Catalog item is on the Creator Store
-- (or the Marketplace) and the game references it by its id: it has no
-- file, is never uploaded, and Roblox published it, so it is approved.
local function referencedProblems(entry: any, bad: (string) -> ())
	local a = Manifest.REFERENCED[entry.kind]
	if entry.path ~= nil or entry.sha256 ~= nil or entry.amy ~= nil then
		bad(`{a} has no path, sha256 or amy: it is referenced, not uploaded`)
	end
	-- A Catalog item's slot is listed before the owner picks the item: no id
	-- yet, and pending, until then.
	if entry.kind == Manifest.CATALOG and entry.assetId == nil then
		if entry.upload ~= false or entry.moderation ~= "pending" or not entry.placeholder then
			bad(`{a} not picked yet has upload false, moderation "pending" and placeholder true`)
		end
		return
	end
	if entry.upload ~= false or entry.moderation ~= "approved" then
		bad(`{a} has upload false and moderation "approved"`)
	end
	if type(entry.assetId) ~= "string" or not string.match(entry.assetId, "^%d+$") then
		bad(`{a} needs its Creator Store assetId, a string of digits`)
	end
end

-- Every problem with the manifest, each naming the entry. `readFile` reads
-- an asset's file by its repository path.
function Manifest.validate(manifest: any, readFile: (string) -> string?): { string }
	local problems = {}
	local function problem(message: string)
		table.insert(problems, message)
	end
	if type(manifest) ~= "table" or manifest.version ~= 1 or type(manifest.assets) ~= "table" then
		problem(`{Manifest.PATH} must be an object with "version": 1 and an "assets" array`)
		return problems
	end
	local seen: { [string]: boolean } = {}
	for i, entry in manifest.assets do
		local name = if type(entry) == "table" and type(entry.name) == "string" then entry.name else `#{i}`
		local function bad(message: string)
			problem(`{name}: {message}`)
		end
		if type(entry) ~= "table" then
			bad("is not an object")
			continue
		end
		for field in entry do
			if not IS_FIELD[field] then
				bad(`unknown field "{field}"`)
			end
		end
		local prefix = string.match(name, "^(%l+):[%w_]+$")
		if not prefix or not Manifest.NAME_PREFIXES[prefix] then
			bad(`name must be <prefix>:<name>, the prefix one of {keys(Manifest.NAME_PREFIXES)}`)
		elseif seen[name] then
			bad("is listed twice")
		end
		seen[name] = true

		if type(entry.upload) ~= "boolean" or type(entry.placeholder) ~= "boolean" then
			bad("upload and placeholder must be true or false")
		end
		if not nonEmpty(entry.creator) or not nonEmpty(entry.origin) then
			bad("creator and origin are required")
		end
		if not Manifest.LICENCES[entry.licence] then
			bad(`licence must be one of {keys(Manifest.LICENCES)}`)
		elseif entry.licence == "cc-by" and not nonEmpty(entry.attribution) then
			bad("a cc-by licence needs an attribution")
		elseif entry.licence == "marketplace" and entry.kind ~= Manifest.CATALOG then
			bad("only a Catalog item has the marketplace licence")
		end
		for kind, kindPrefix in Manifest.KIND_PREFIXES do
			if (prefix == kindPrefix) ~= (entry.kind == kind) then
				bad(`{Manifest.REFERENCED[kind]} is named {kindPrefix}:<name> and has kind "{kind}"`)
			end
		end
		if Manifest.REFERENCED[entry.kind] then
			referencedProblems(entry, bad)
			continue
		end

		local path = entry.path
		local contents = nil
		if type(path) ~= "string" or not string.match(path, "^assets/") or string.find(path, "..", 1, true) then
			bad("path must be a file under assets/")
		else
			contents = readFile(path)
			if not contents then
				bad(`file not found: {path}`)
			end
		end
		if not OpenCloud.ASSET_TYPES[entry.kind] then
			bad(`kind must be one of {keys(OpenCloud.ASSET_TYPES)}, or {keys(Manifest.REFERENCED)}`)
		elseif type(path) == "string" then
			local refused = OpenCloud.assetUploadProblem(entry.kind, path, if contents then #contents else 0)
			if refused then
				bad(refused)
			end
		end
		local file = Manifest.characterModelPath(name)
		if file then
			if entry.kind ~= "model" or path ~= file or entry.upload ~= false then
				bad(`a Character model is kind "model" at {file} with upload false: the place file holds it`)
			end
		end
		if entry.kind == "image" and not Manifest.AMY[entry.amy] then
			bad('amy must be "absent" or "from-behind": no image shows Amy\'s face')
		end

		if not Manifest.MODERATION[entry.moderation] then
			bad(`moderation must be one of {keys(Manifest.MODERATION)}`)
		elseif entry.assetId == nil then
			if entry.moderation ~= "pending" or entry.sha256 ~= nil then
				bad("an entry with no assetId is pending and has no sha256")
			end
		elseif type(entry.assetId) ~= "string" or not string.match(entry.assetId, "^%d+$") then
			bad("assetId must be a string of digits, or null")
		elseif entry.upload == false then
			bad("an entry with upload false has no assetId")
		elseif entry.moderation == "pending" then
			bad("an uploaded entry's moderation is reviewing, approved or rejected")
		elseif type(entry.sha256) ~= "string" or not string.match(entry.sha256, "^%x+$") or #entry.sha256 ~= 64 then
			bad("an uploaded entry records the sha256 of the file uploaded")
		end
	end
	return problems
end

-- Every asset id in `sources` (path -> text) that the manifest does not
-- have, every id that is not written out as digits, and every
-- Content.fromAssetId outside AssetIds.luau. Code reaches an Asset through
-- AssetIds, so a literal id from the manifest is the only id it may name.
function Manifest.scanSources(manifest: Manifest, sources: { [string]: string }): { string }
	local known: { [string]: boolean } = {}
	for _, entry in manifest.assets do
		if entry.assetId then
			known[entry.assetId] = true
		end
	end
	local problems = {}
	for path, text in sources do
		text = string.lower(text)
		-- Most files name no asset at all; only those are split into lines.
		if not (string.find(text, "rbx", 1, true) or string.find(text, "asset", 1, true)) then
			continue
		end
		local lineNumber = 0
		for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
			lineNumber += 1
			local where = `{path}:{lineNumber}`
			for _, pattern in ID_PATTERNS do
				for id in string.gmatch(line, pattern) do
					if id == "" then
						table.insert(
							problems,
							`{where}: an asset id must be written out as digits from {Manifest.PATH}; {USE_ASSET_IDS}`
						)
					elseif not known[id] then
						table.insert(problems, `{where}: asset id {id} is not in {Manifest.PATH}`)
					end
				end
			end
			if path ~= Manifest.ASSET_IDS_PATH and string.find(line, FROM_ASSET_ID, 1, true) then
				table.insert(
					problems,
					`{where}: Content.fromAssetId outside {Manifest.ASSET_IDS_PATH}; {USE_ASSET_IDS}`
				)
			end
		end
	end
	table.sort(problems)
	return problems
end

-- The source of src/shared/AssetIds.luau: asset name -> content id, for every
-- entry with an id that the game shows: uploaded, or referenced by its
-- Creator Store id (validation allows no other entry an id).
function Manifest.generateAssetIds(manifest: Manifest): string
	local rows = {}
	for _, entry in manifest.assets do
		if entry.assetId then
			table.insert(rows, `\t["{entry.name}"] = "rbxassetid://{entry.assetId}",`)
		end
	end
	table.sort(rows)
	local lines = {
		"--!strict",
		`-- Generated by tools/upload-assets from {Manifest.PATH}; do not edit.`,
		"-- Asset name -> content id for every entry with an id that the game shows:",
		"-- uploaded, or referenced by its Creator Store id (a font, a library track,",
		"-- a Catalog item). A name with no id yet is absent, so the game does",
		"-- without it: plain UI, silence, a Character without the item. Tier 0",
		"-- (tools/check-assets) fails when this file and the manifest disagree.",
		"",
		"local AssetIds: { [string]: string } = {",
	}
	table.move(rows, 1, #rows, #lines + 1, lines)
	table.insert(lines, "}")
	table.insert(lines, "")
	table.insert(lines, "return table.freeze(AssetIds)")
	return table.concat(lines, "\n") .. "\n"
end

-- Every file under `dir`, whatever its extension, path -> text. Each
-- directory is listed once.
local function readSources(ctx: Cli.Context, dir: string, names: { string }, into: { [string]: string })
	for _, name in names do
		local path = `{dir}/{name}`
		local children = ctx.listDir(path)
		if children then
			readSources(ctx, path, children, into)
		else
			into[path] = ctx.readFile(path) or ""
		end
	end
end

-- Reads and validates the manifest. Returns it, its problems, and a reader
-- for asset files that reads each file once.
function Manifest.load(ctx: Cli.Context): (Manifest, { string }, (string) -> string?)
	local text = ctx.readFile(Manifest.PATH) or error(`{Manifest.PATH} not found`, 0)
	local files: { [string]: string | false } = {}
	local function readAsset(path: string): string?
		if files[path] == nil then
			files[path] = ctx.readFile(path) or false
		end
		return files[path] or nil
	end
	local manifest = Manifest.decode(text)
	return manifest, Manifest.validate(manifest, readAsset), readAsset
end

-- The tier 0 asset check: the manifest is valid, every asset id in src/ and
-- default.project.json is in it, and src/shared/AssetIds.luau is what the
-- manifest generates. Returns the problems, and logs a note for each entry
-- still to upload. With `writeIds`, a valid manifest's AssetIds is written
-- first: for an entry referenced by its Creator Store id, which no upload
-- run writes (`lune run tools/check-assets --write-ids`).
function Manifest.check(ctx: Cli.Context, writeIds: boolean?): { string }
	local manifest, problems, readAsset = Manifest.load(ctx)
	if #problems > 0 then
		return problems
	end
	if writeIds then
		ctx.writeFile(Manifest.ASSET_IDS_PATH, Manifest.generateAssetIds(manifest))
	end
	local sources = {}
	readSources(ctx, "src", ctx.listDir("src") or {}, sources)
	sources[PROJECT_FILE] = ctx.readFile(PROJECT_FILE) or ""
	problems = Manifest.scanSources(manifest, sources)
	if ctx.readFile(Manifest.ASSET_IDS_PATH) ~= Manifest.generateAssetIds(manifest) then
		table.insert(
			problems,
			`{Manifest.ASSET_IDS_PATH} does not match {Manifest.PATH}; only tools/upload-assets, or tools/check-assets --write-ids, writes it`
		)
	end
	for _, entry in manifest.assets do
		if entry.upload and Manifest.isPending(entry, Manifest.hash(readAsset(entry.path :: string) :: string)) then
			ctx.log(`note: {entry.name} is waiting for upload ({entry.path})`)
		end
	end
	return problems
end

return Manifest
