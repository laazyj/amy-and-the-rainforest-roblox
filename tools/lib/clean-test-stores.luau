--!strict
-- Deletes every entry an engine-test run left in the Dev experience's data
-- stores, then lists them again to prove they are empty. Entry point:
-- tools/clean-test-stores.luau, run by .github/workflows/engine-tests.yml
-- after the engine tests, with the Dev key. See docs/OPEN_CLOUD.md.
--
-- A run's stores are the ones its scripts named with storeName(), and
-- Persist under the engine harness: "test-<RUN_ID>-...". Only names with
-- that prefix are touched, whatever the API returns. Data stores themselves
-- cannot be deleted through this API; an empty one costs nothing.
--
-- stdout: one line per store, then the summary the job writes to its log.

local Cli = require("./cli")
local EngineTests = require("./engine-tests")
local OpenCloud = require("../opencloud")

local USAGE = "usage: lune run tools/clean-test-stores --run-id <id>"

local CleanTestStores = {}

-- Every page of a listing: `request(cursor)` and `parse(response)`.
local function pages<T>(
	ctx: Cli.Context,
	request: (cursor: string?) -> OpenCloud.Request,
	parse: (OpenCloud.Response) -> ({ T }, string?)
): { T }
	local all: { T } = {}
	local cursor: string? = nil
	repeat
		local items
		items, cursor = parse(OpenCloud.call(ctx.http, ctx.sleep, request(cursor)))
		table.move(items, 1, #items, #all + 1, all)
	until not cursor
	return all
end

function CleanTestStores.main(ctx: Cli.Context)
	local target = Cli.target(ctx, USAGE, { "run-id" })
	local runId = EngineTests.resolveRunId(Cli.required(target.values, "run-id"), {})
	local prefix = EngineTests.storePrefix(runId)
	local key, universe = target.apiKey, target.universeId

	if target.dryRun then
		ctx.log("dry run: would list the test stores, then delete each one's entries and list them again")
		ctx.log(OpenCloud.describe(OpenCloud.listDataStoresRequest(key, universe, prefix)))
		ctx.log(OpenCloud.describe(OpenCloud.listEntriesRequest(key, universe, `{prefix}<name>`)))
		ctx.log(
			OpenCloud.describe(
				OpenCloud.deleteEntryRequest(key, universe, `{prefix}<name>`, { scope = "global", key = "<key>" })
			)
		)
		return
	end

	local stores = pages(ctx, function(cursor)
		return OpenCloud.listDataStoresRequest(key, universe, prefix, cursor)
	end, OpenCloud.parseDataStoresPage)
	local function entries(store: string): { OpenCloud.EntryKey }
		return pages(ctx, function(cursor)
			return OpenCloud.listEntriesRequest(key, universe, store, cursor)
		end, OpenCloud.parseEntriesPage)
	end

	local deleted, left = 0, 0
	for _, store in stores do
		if string.sub(store, 1, #prefix) ~= prefix then
			error(`the listing for prefix {prefix} returned {store}; refusing to touch it`, 0)
		end
		local found = entries(store)
		for _, entry in found do
			OpenCloud.call(ctx.http, ctx.sleep, OpenCloud.deleteEntryRequest(key, universe, store, entry))
		end
		local after = if #found > 0 then #entries(store) else 0
		deleted += #found
		left += after
		ctx.out(`{store}: deleted {#found} entries; listed after: {after} entries`)
	end
	ctx.out(`test stores {prefix}*: {#stores} store(s), {deleted} entries deleted, {left} left`)
	if left > 0 then
		error(`{left} entries are still listed in the test stores`, 0)
	end
end

return CleanTestStores
