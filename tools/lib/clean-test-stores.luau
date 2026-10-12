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
-- The v1 listing keeps a deleted key listed for a while, so the check
-- after the deletes lists through Open Cloud v2, which leaves out entries
-- marked as deleted; it lists again, LIST_ATTEMPTS times LIST_WAIT seconds
-- apart, until the stores are empty, and fails if they never are.
--
-- stdout: one line per store, then the summary the job writes to its log.

local Cli = require("./cli")
local EngineTests = require("./engine-tests")
local OpenCloud = require("../opencloud")

local USAGE = "usage: lune run tools/clean-test-stores --run-id <id>"

local CleanTestStores = {}

CleanTestStores.LIST_ATTEMPTS = 6
CleanTestStores.LIST_WAIT = 10

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

	local deleted: { [string]: number } = {}
	local total = 0
	for _, store in stores do
		if string.sub(store, 1, #prefix) ~= prefix then
			error(`the listing for prefix {prefix} returned {store}; refusing to touch it`, 0)
		end
		local found = entries(store)
		for _, entry in found do
			OpenCloud.call(ctx.http, ctx.sleep, OpenCloud.deleteEntryRequest(key, universe, store, entry))
		end
		deleted[store] = #found
		total += #found
	end

	-- the stores listed again, without entries marked as deleted, until empty
	local left: { [string]: number } = {}
	for attempt = 1, CleanTestStores.LIST_ATTEMPTS do
		local still = 0
		for _, store in stores do
			if deleted[store] > 0 and (left[store] or 1) > 0 then
				left[store] = #pages(ctx, function(token)
					return OpenCloud.listLiveEntriesRequest(key, universe, store, token)
				end, OpenCloud.parseLiveEntriesPage)
			end
			still += left[store] or 0
		end
		if still == 0 or attempt == CleanTestStores.LIST_ATTEMPTS then
			break
		end
		ctx.sleep(CleanTestStores.LIST_WAIT)
	end

	local remaining = 0
	for _, store in stores do
		remaining += left[store] or 0
		ctx.out(`{store}: deleted {deleted[store]} entries; listed after: {left[store] or 0} entries`)
	end
	ctx.out(`test stores {prefix}*: {#stores} store(s), {total} entries deleted, {remaining} left`)
	if remaining > 0 then
		error(`{remaining} entries are still listed in the test stores`, 0)
	end
end

return CleanTestStores
