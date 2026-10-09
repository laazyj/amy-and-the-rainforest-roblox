--!strict
-- Checks the toolchain pins in rokit.toml (and any Wally dependency) against
-- the latest releases and rewrites the pins that are behind, with their lines
-- in tools/toolchain-checksums.txt. Entry point:
-- tools/toolchain-check.luau, run weekly by .github/workflows/toolchain-check.yml,
-- which opens a "Toolchain updates" PR so CI proves each bump.
--
-- The parsing and rewriting here are pure; HTTP comes in through the context.

local Cli = require("./cli")
local OpenCloud = require("../opencloud")
local serde = require("@lune/serde")

export type Pin = { name: string, repo: string, version: string }
export type Update = { name: string, from: string, to: string }
-- A release as GitHub's API returns it; `digest` is "sha256:<hex>".
export type Release = { tag_name: string, assets: { { name: string, digest: string? } } }

local Toolchain = {}

Toolchain.GITHUB_API = "https://api.github.com"
Toolchain.WALLY_API = "https://api.wally.run"
Toolchain.CHECKSUMS = "tools/toolchain-checksums.txt"

-- Lines `name = "source@version"` in the sections `inSection` accepts.
local function parsePins(text: string, inSection: (header: string) -> boolean): { Pin }
	local pins = {}
	local accepted = false
	for line in string.gmatch(text, "[^\n]+") do
		local header = string.match(line, "^%s*%[([^%]]+)%]")
		if header then
			accepted = inSection(header)
		elseif accepted then
			local name, repo, version = string.match(line, '^%s*([%w_%-]+)%s*=%s*"([^"@]+)@([^"]+)"')
			if name and repo and version then
				table.insert(pins, { name = name, repo = repo, version = version })
			end
		end
	end
	return pins
end

-- rokit.toml's [tools]: `name = "owner/repo@version"`.
function Toolchain.parseRokit(text: string): { Pin }
	return parsePins(text, function(header)
		return header == "tools"
	end)
end

-- wally.toml's dependency sections: `Alias = "scope/name@<requirement>"`,
-- with the requirement as written in `version`.
function Toolchain.parseWally(text: string): { Pin }
	return parsePins(text, function(header)
		return string.match(header, "dependencies$") ~= nil
	end)
end

-- A release tag as Rokit pins it: "v7.7.1" and "7.7.1" are both "7.7.1".
function Toolchain.versionFromTag(tag: string): string
	return (string.gsub(tag, "^v", ""))
end

-- A Wally requirement moved to `latest`, keeping its operator ("^1.2.0" -> "^1.3.0").
function Toolchain.bumpRequirement(requirement: string, latest: string): string
	return (string.match(requirement, "^[%^~=<>]*") or "") .. latest
end

-- .luaurc's @lune alias points at the typedefs of one Lune version
-- (tools/check.sh enforces it), so it moves with the Lune pin.
function Toolchain.updateLuaurc(text: string, luneVersion: string): string
	local updated, count = string.gsub(text, 'typedefs/[^/"]+/', `typedefs/{luneVersion}/`)
	assert(count == 1, ".luaurc must have exactly one @lune typedefs alias")
	return updated
end

-- Rewrites the lines of tool `name` in the checksums file (columns: tool,
-- tag, platform, asset, sha256) for `release`. Each asset keeps its name with
-- the version replaced, and takes the SHA-256 GitHub records for it.
function Toolchain.updateChecksums(text: string, name: string, release: Release): string
	local digests: { [string]: string } = {}
	for _, asset in release.assets do
		digests[asset.name] = if asset.digest then string.match(asset.digest, "^sha256:(%x+)$") else nil
	end
	local newVersion = Toolchain.versionFromTag(release.tag_name)
	return (
		string.gsub(text, "[^\n]+", function(line): string?
			local tool, tag, platform, asset = string.match(line, "^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+%x+$")
			if tool ~= name or not (tag and platform and asset) then
				return nil -- keep the line
			end
			local old = Toolchain.versionFromTag(tag)
			local first, last = string.find(asset, old, 1, true)
			local newAsset = if first and last
				then string.sub(asset, 1, first - 1) .. newVersion .. string.sub(asset, last + 1)
				else asset
			local digest = digests[newAsset]
				or error(`{name} {release.tag_name} has no asset {newAsset} with a SHA-256 digest`, 0)
			return string.format("%-9s %-7s %-14s %-31s %s", name, release.tag_name, platform, newAsset, digest)
		end)
	)
end

-- The markdown body of the "Toolchain updates" PR.
function Toolchain.summary(updates: { Update }): string
	local lines = {
		"Weekly check of the toolchain pins against their latest releases",
		"(`.github/workflows/toolchain-check.yml`). CI on this PR runs the full",
		"check, test and build against the new versions. Review the release notes,",
		"then merge or close; nothing merges automatically.",
		"",
		"| Tool | From | To |",
		"|---|---|---|",
	}
	for _, update in updates do
		table.insert(lines, `| {update.name} | {update.from} | {update.to} |`)
	end
	return table.concat(lines, "\n")
end

-- A GET through OpenCloud.call, for its transport retry and error text.
local function getJson(ctx: Cli.Context, url: string, headers: { [string]: string }): any
	local response = OpenCloud.call(ctx.http, ctx.sleep, { method = "GET", url = url, headers = headers })
	return serde.decode("json", response.body)
end

local function latestRelease(ctx: Cli.Context, pin: Pin): Release
	local headers = { accept = "application/vnd.github+json", ["user-agent"] = "toolchain-check" }
	local token = ctx.env.GITHUB_TOKEN
	if token and token ~= "" then
		headers.authorization = `Bearer {token}`
	end
	return getJson(ctx, `{Toolchain.GITHUB_API}/repos/{pin.repo}/releases/latest`, headers)
end

local function wantedRequirement(ctx: Cli.Context, pin: Pin): string
	local headers = { ["wally-version"] = "0.3.2", ["user-agent"] = "toolchain-check" }
	local metadata = getJson(ctx, `{Toolchain.WALLY_API}/v1/package-metadata/{pin.repo}`, headers)
	return Toolchain.bumpRequirement(pin.version, metadata.versions[1].package.version)
end

-- Rewrites each pin in `text` to `wanted(pin)`; returns the new text (nil
-- when nothing changed) and the updates.
local function bumpPins(ctx: Cli.Context, text: string, pins: { Pin }, wanted: (Pin) -> string): (string?, { Update })
	local updates = {}
	for _, pin in pins do
		local to = wanted(pin)
		ctx.log(`{pin.name}: pinned {pin.version}, latest {to}`)
		if to ~= pin.version then
			local old = `"{pin.repo}@{pin.version}"`
			local first, last = string.find(text, old, 1, true)
			assert(first and last, `{old} not found`)
			text = string.sub(text, 1, first - 1) .. `"{pin.repo}@{to}"` .. string.sub(text, last + 1)
			table.insert(updates, { name = pin.name, from = pin.version, to = to })
		end
	end
	return if #updates > 0 then text else nil, updates
end

-- Reads rokit.toml, wally.toml and .luaurc through the context, and returns
-- the new text of each file that changed, and the updates made.
function Toolchain.check(ctx: Cli.Context): ({ [string]: string }, { Update })
	local changed: { [string]: string } = {}
	local updates: { Update } = {}
	local function bump(path: string, pins: { Pin }, text: string, wanted: (Cli.Context, Pin) -> string)
		local newText, fileUpdates = bumpPins(ctx, text, pins, function(pin)
			return wanted(ctx, pin)
		end)
		if newText then
			changed[path] = newText
		end
		table.move(fileUpdates, 1, #fileUpdates, #updates + 1, updates)
	end

	local rokit = ctx.readFile("rokit.toml") or error("rokit.toml not found", 0)
	local releases: { [string]: Release } = {}
	bump("rokit.toml", Toolchain.parseRokit(rokit), rokit, function(_, pin)
		local release = latestRelease(ctx, pin)
		releases[pin.name] = release
		return Toolchain.versionFromTag(release.tag_name)
	end)
	local wally = ctx.readFile("wally.toml")
	if wally then
		bump("wally.toml", Toolchain.parseWally(wally), wally, wantedRequirement)
	end

	local checksums = ctx.readFile(Toolchain.CHECKSUMS)
	for _, update in updates do
		local release = releases[update.name]
		if release and checksums then
			checksums = Toolchain.updateChecksums(checksums, update.name, release)
			changed[Toolchain.CHECKSUMS] = checksums
		end
		if update.name == "lune" then
			local luaurc = ctx.readFile(".luaurc") or error(".luaurc not found", 0)
			changed[".luaurc"] = Toolchain.updateLuaurc(luaurc, update.to)
		end
	end
	return changed, updates
end

return Toolchain
