--!strict
-- Fetching a free Creator Store model through Studio (brief mac-002, plan
-- section 5.5): what runs in Studio, the checks on what came back, and the
-- manifest entry. Pure: Studio is reached through the Bridge, and
-- fetch-model.luau passes the live one.

local serde = require("@lune/serde")

local Smoke = require("./smoke")

local Fetch = {}

export type Described = {
	name: string,
	creator: string,
	free: boolean,
	classes: { [string]: number }, -- every instance's class, the root's included
	code: { [string]: number }, -- the classes of those that are scripts (LuaSourceContainer)
}

-- The folder in ServerStorage the model is inserted into: named by the
-- tool, never by the model's creator, so no creator-chosen text is ever
-- part of the Luau sent to Studio. `stamp` makes it unique.
function Fetch.folderName(assetId: string, stamp: number): string
	return `StudioPlaytestFetch_{assetId}_{stamp}`
end

local function checked(folder: string): string
	assert(string.match(folder, "^[%w_]+$"), "a fetch folder's name is letters, digits and underscores")
	return folder
end

-- In Edit: creates the empty folder to insert into.
function Fetch.prepareScript(folder: string): string
	return `local name = "{checked(folder)}"\n`
		.. [[
local storage = game:GetService("ServerStorage")
if storage:FindFirstChild(name) then
	error("ServerStorage already has " .. name)
end
local folder = Instance.new("Folder")
folder.Name = name
folder.Parent = storage
return "ready"]]
end

-- Studio's path to the folder, for insert_asset's parentPath.
function Fetch.folderPath(folder: string): string
	return `game.ServerStorage.{checked(folder)}`
end

-- The start of both scripts below: `items` is the one model in the folder
-- and everything under it.
local function itemsIn(folder: string): string
	return `local folder = game:GetService("ServerStorage"):FindFirstChild("{checked(folder)}")\n`
		.. [[
local inserted = if folder then folder:GetChildren() else {}
if #inserted ~= 1 then
	error(string.format("expected one inserted instance, found %d", #inserted))
end
local model = inserted[1]
local items = model:GetDescendants()
table.insert(items, model)
]]
end

-- In Edit: what the inserted model holds and what the Creator Store says
-- about it, as JSON. Off sale (no price) is not free.
function Fetch.describeScript(folder: string, assetId: string): string
	assert(string.match(assetId, "^%d+$"), "an asset id is digits")
	return itemsIn(folder)
		.. [[
local classes, code = {}, {}
for _, item in items do
	classes[item.ClassName] = (classes[item.ClassName] or 0) + 1
	if item:IsA("LuaSourceContainer") then
		code[item.ClassName] = (code[item.ClassName] or 0) + 1
	end
end
local info = game:GetService("MarketplaceService"):GetProductInfoAsync(]]
		.. assetId
		.. [[)
return game:GetService("HttpService"):JSONEncode({
	name = info.Name,
	creator = info.Creator and info.Creator.Name or "unknown",
	free = info.IsPublicDomain == true or info.PriceInRobux == 0,
	classes = classes,
	code = code,
})]]
end

-- In Edit: the model as a binary .rbxm, base64-encoded; refuses again if
-- it holds a script now.
function Fetch.serialiseScript(folder: string): string
	return itemsIn(folder)
		.. [[
for _, item in items do
	if item:IsA("LuaSourceContainer") then
		error("the model carries code: " .. item.ClassName)
	end
end
local bytes = game:GetService("SerializationService"):SerializeInstancesAsync({ model })
return buffer.tostring(game:GetService("EncodingService"):Base64Encode(bytes))]]
end

-- Why the model must not be saved, or nil: it is not free, or it carries
-- code (a free model's scripts are the usual way malware reaches a game).
function Fetch.refusal(described: Described): string?
	if not described.free then
		return `'{described.name}' is not free on the Creator Store`
	end
	local code = {}
	for class, count in described.code do
		table.insert(code, `{count} {class}`)
	end
	if #code > 0 then
		table.sort(code)
		return `'{described.name}' carries code ({table.concat(code, ", ")}); only models without scripts are fetched`
	end
	return nil
end

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUES: { [string]: number } = {}
for i = 1, #ALPHABET do
	VALUES[string.sub(ALPHABET, i, i)] = i - 1
end

-- Standard base64 (with = padding) to bytes.
function Fetch.base64Decode(text: string): string
	local clean = string.gsub(text, "%s", "")
	if
		#clean % 4 ~= 0
		or string.find(clean, "[^%w+/=]")
		or string.find(clean, "=[^=]")
		or string.find(clean, "===")
	then
		error("not base64", 0)
	end
	local out = table.create(#clean // 4)
	for i = 1, #clean, 4 do
		local quad = string.sub(clean, i, i + 3)
		local a, b = VALUES[string.sub(quad, 1, 1)], VALUES[string.sub(quad, 2, 2)]
		local c, d = VALUES[string.sub(quad, 3, 3)], VALUES[string.sub(quad, 4, 4)]
		local n = bit32.lshift(a, 18) + bit32.lshift(b, 12) + bit32.lshift(c or 0, 6) + (d or 0)
		local bytes = string.char(bit32.extract(n, 16, 8), bit32.extract(n, 8, 8), bit32.extract(n, 0, 8))
		table.insert(out, string.sub(bytes, 1, if c == nil then 1 elseif d == nil then 2 else 3))
	end
	return table.concat(out)
end

-- The manifest entry for the saved model (docs/ASSETS.md): pending upload,
-- the Creator Store id and creator in `origin`.
function Fetch.entry(name: string, path: string, assetId: string, described: Described, date: string): { [string]: any }
	return {
		name = name,
		kind = "model",
		path = path,
		-- "assetId": null goes in by hand: a Luau table cannot hold a nil.
		moderation = "pending",
		upload = false,
		placeholder = false,
		creator = described.creator,
		licence = "creator-store-free",
		origin = `Creator Store asset {assetId}, "{described.name}" by {described.creator}, inserted through Studio's MCP server and saved with SerializationService on {date} (tools/studio-playtest/fetch-model.luau). Meshes stay on Roblox under the creator's ids.`,
	}
end

-- Inserts the asset into a fresh folder, describes it, refuses it if it
-- must not be saved, and returns it serialised as .rbxm bytes.
function Fetch.fetch(bridge: Smoke.Bridge, assetId: string, folder: string): (Described, string)
	bridge.run("Edit", Fetch.prepareScript(folder))
	bridge.insertAsset(assetId, Fetch.folderPath(folder))
	local described: Described = serde.decode("json", bridge.run("Edit", Fetch.describeScript(folder, assetId)))
	local refusal = Fetch.refusal(described)
	if refusal then
		error(refusal, 0)
	end
	return described, Fetch.base64Decode(bridge.run("Edit", Fetch.serialiseScript(folder)))
end

return Fetch
