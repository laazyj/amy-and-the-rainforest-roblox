--!strict
-- Uploads every manifest entry still to upload through the Assets API, polls
-- each operation, writes the asset id back to assets/manifest.json and
-- regenerates src/shared/AssetIds.luau. Then asks Roblox for the moderation
-- state of every asset still in review. Entry point: tools/upload-assets.luau,
-- run only by .github/workflows/upload-assets.yml. See docs/ASSETS.md.
--
-- Idempotent: an entry with an id and an unchanged file is never sent again.
-- The manifest is written after each upload, so a run that fails part way
-- keeps the ids it got. stdout is the PR body's list of what changed.

local Cli = require("./cli")
local Manifest = require("./manifest")
local OpenCloud = require("../opencloud")

local USAGE = "usage: lune run tools/upload-assets --creator-user <id>"

local UploadAssets = {}

-- Seconds between polls of an upload's operation, and how many polls before giving up.
UploadAssets.POLL_INTERVAL = 2
UploadAssets.MAX_POLLS = 90

local function save(ctx: Cli.Context, manifest: Manifest.Manifest)
	ctx.writeFile(Manifest.PATH, Manifest.encode(manifest))
	ctx.writeFile(Manifest.ASSET_IDS_PATH, Manifest.generateAssetIds(manifest))
end

-- A moderation state the manifest records, or nil.
local function known(state: string?): string?
	return if state and Manifest.MODERATION[state] then state else nil
end

-- What Roblox sees: no names of people, only the game and the asset name.
local function uploadFor(entry: Manifest.Entry, contents: string, creatorUserId: string): OpenCloud.AssetUpload
	return {
		kind = entry.kind,
		displayName = `Amy and the Rain Forest {entry.name}`,
		description = `{entry.name}, for the game Amy and the Rain Forest.`,
		creatorUserId = creatorUserId,
		fileName = string.match(entry.path, "[^/]+$") :: string,
		file = contents,
	}
end

-- Sends the upload and polls its operation until it is done; returns the result.
local function upload(ctx: Cli.Context, apiKey: string, request: OpenCloud.Request): OpenCloud.Operation
	-- Not retried on a transport error: a second create could duplicate the
	-- asset. The next run uploads the entry again.
	local operation = OpenCloud.parseOperation(OpenCloud.call(ctx.http, ctx.sleep, request, { retryTransport = false }))
	local polls = 0
	while not operation.done do
		if polls >= UploadAssets.MAX_POLLS then
			error(`{operation.path} was not done after {polls} polls`, 0)
		end
		polls += 1
		ctx.sleep(UploadAssets.POLL_INTERVAL)
		local poll = OpenCloud.getOperationRequest(apiKey, operation.path)
		operation = OpenCloud.parseOperation(OpenCloud.call(ctx.http, ctx.sleep, poll))
	end
	if operation.error or not operation.assetId then
		error(`{operation.path} failed: {operation.error or "no asset id in the response"}`, 0)
	end
	return operation
end

function UploadAssets.main(ctx: Cli.Context)
	local target = Cli.target(ctx, USAGE, { "creator-user" })
	local creatorUserId = Cli.numericId(target.values, "creator-user")

	local manifest, problems, readAsset = Manifest.load(ctx)
	if #problems > 0 then
		error(`{Manifest.PATH} is not valid:\n{table.concat(problems, "\n")}`, 0)
	end

	type Pending = { entry: Manifest.Entry, request: OpenCloud.Request, sha256: string }
	local pending: { Pending } = {}
	local reviewing: { Manifest.Entry } = {}
	for _, entry in manifest.assets do
		if not entry.upload then
			continue
		end
		local contents = readAsset(entry.path) :: string
		local sha256 = Manifest.hash(contents)
		if Manifest.isPending(entry, sha256) then
			local request = OpenCloud.createAssetRequest(target.apiKey, uploadFor(entry, contents, creatorUserId))
			table.insert(pending, { entry = entry, request = request, sha256 = sha256 })
		elseif entry.moderation == "reviewing" then
			table.insert(reviewing, entry)
		end
	end
	ctx.log(`{#pending} pending upload(s), {#reviewing} asset(s) in moderation review`)

	if target.dryRun then
		for _, item in pending do
			ctx.log(`dry run: would upload {item.entry.name} ({item.entry.path})`)
			ctx.log(OpenCloud.describe(item.request))
			ctx.log(OpenCloud.describeOperationPolling())
		end
		for _, entry in reviewing do
			ctx.log(`dry run: would check the moderation of {entry.name}`)
			ctx.log(OpenCloud.describe(OpenCloud.getAssetRequest(target.apiKey, entry.assetId :: string)))
		end
		return
	end

	for _, item in pending do
		local entry = item.entry
		local operation = upload(ctx, target.apiKey, item.request)
		local replaced = entry.assetId
		entry.assetId = operation.assetId
		entry.sha256 = item.sha256
		entry.moderation = known(operation.moderation) or "reviewing"
		save(ctx, manifest)
		local was = if replaced then `, replacing {replaced}` else ""
		ctx.out(`- uploaded \`{entry.name}\` ({entry.path}) as {entry.assetId}{was}: {entry.moderation}`)
	end

	for _, entry in reviewing do
		local request = OpenCloud.getAssetRequest(target.apiKey, entry.assetId :: string)
		local state = known(OpenCloud.parseAssetModeration(OpenCloud.call(ctx.http, ctx.sleep, request)))
		if state and state ~= entry.moderation then
			entry.moderation = state
			save(ctx, manifest)
			ctx.out(`- \`{entry.name}\` ({entry.assetId}) is now {state}`)
		end
	end
	ctx.log("done")
end

return UploadAssets
