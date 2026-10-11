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
-- The listing lags a delete: a key deleted a moment ago can still be listed.
-- So the stores are listed again until empty, LIST_ATTEMPTS times
-- LIST_WAIT seconds apart, and any key still listed then is read on its
-- own: it must read as deleted (204) or not found. A key that still has a
-- value fails the run.
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

	-- the stores listed again, until the listing catches up with the deletes
	local listed: { [string]: { OpenCloud.EntryKey } } = {}
	for attempt = 1, CleanTestStores.LIST_ATTEMPTS do
		local still = 0
		for _, store in stores do
			local before = listed[store]
			listed[store] = if deleted[store] > 0 and (not before or #before > 0) then entries(store) else {}
			still += #listed[store]
		end
		if still == 0 or attempt == CleanTestStores.LIST_ATTEMPTS then
			break
		end
		ctx.sleep(CleanTestStores.LIST_WAIT)
	end

	local left = 0
	for _, store in stores do
		local values = 0
		for _, entry in listed[store] do
			local read = OpenCloud.getEntryRequest(key, universe, store, entry)
			local response = OpenCloud.send(ctx.http, ctx.sleep, read)
			if not OpenCloud.isDeletedEntry(response) then
				OpenCloud.expectOk(read, response)
				values += 1
			end
		end
		left += values
		local note = if #listed[store] > values
			then ` ({#listed[store] - values} still listed, each read as deleted)`
			else ""
		ctx.out(
			`{store}: deleted {deleted[store]} entries; listed after: {#listed[store]} entries{note}; {values} with a value`
		)
	end
	ctx.out(`test stores {prefix}*: {#stores} store(s), {total} entries deleted, {left} left with a value`)
	if left > 0 then
		error(`{left} entries in the test stores still have a value`, 0)
	end
end

return CleanTestStores
