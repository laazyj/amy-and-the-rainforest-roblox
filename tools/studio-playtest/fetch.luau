--!strict
-- Fetching a free Creator Store model through Studio (brief mac-002, plan
-- section 5.5): what runs in Studio, the checks on what came back, and the
-- manifest entry. Pure; fetch-model.luau runs it against the live Studio.

local Fetch = {}

export type Described = {
	name: string,
	creator: string,
	free: boolean,
	classes: { [string]: number },
}

-- In Edit: what the inserted model at `path` holds and what the Creator
-- Store says about it, as JSON.
function Fetch.describeScript(path: string, assetId: string): string
	return "local model = "
		.. path
		.. "\n"
		.. [[
local classes = {}
for _, item in model:GetDescendants() do
	classes[item.ClassName] = (classes[item.ClassName] or 0) + 1
end
local info = game:GetService("MarketplaceService"):GetProductInfoAsync(]]
		.. assetId
		.. [[)
return game:GetService("HttpService"):JSONEncode({
	name = info.Name,
	creator = info.Creator and info.Creator.Name or "unknown",
	free = info.IsPublicDomain == true or (info.PriceInRobux or 0) == 0,
	classes = classes,
})]]
end

-- In Edit: the model at `path` as a binary .rbxm, base64-encoded.
function Fetch.serialiseScript(path: string): string
	return 'local bytes = game:GetService("SerializationService"):SerializeInstancesAsync({ '
		.. path
		.. ' })\nreturn buffer.tostring(game:GetService("EncodingService"):Base64Encode(bytes))'
end

-- Why the model must not be saved, or nil: it is not free, or it carries
-- code (a free model's scripts are the usual way malware reaches a game).
function Fetch.refusal(described: Described): string?
	if not described.free then
		return `'{described.name}' is not free on the Creator Store`
	end
	local code = {}
	for class, count in described.classes do
		if string.find(class, "Script$") then
			table.insert(code, `{count} {class}`)
		end
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
	if #clean % 4 ~= 0 or string.find(clean, "[^%w+/=]") then
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

return Fetch
