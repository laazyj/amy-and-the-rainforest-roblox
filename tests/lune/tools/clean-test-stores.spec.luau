local F = require("../fixtures/opencloud")
local CleanTestStores = require("../../../tools/lib/clean-test-stores")
local EngineTests = require("../../../tools/lib/engine-tests")
local OpenCloud = require("../../../tools/opencloud")
local serde = require("@lune/serde")

local RUN = "pr33-77-1"
local PREFIX = `test-{RUN}-`

local function args(universe: string?, extra: { string }?): { string }
	local list = { "--universe", universe or F.DEV, "--place", F.PLACE, "--run-id", RUN }
	table.move(extra or {}, 1, #(extra or {}), #list + 1, list)
	return list
end

local function query(url: string, name: string): string?
	local value = string.match(url, `[?&]{name}=([^&]*)`)
	return value
		and (string.gsub(value, "%%(%x%x)", function(hex)
			return string.char(tonumber(hex, 16) :: number)
		end))
end

-- A Dev experience whose data stores are `stores` (name -> scope -> keys),
-- listed `perPage` at a time, as the DataStores v1 API answers. With
-- `lagging`, a deleted key stays listed, as Roblox's listing does for a
-- while, and reads as deleted (204).
local function server(stores: { [string]: { [string]: { string } } }, perPage: number?, lagging: boolean?)
	local size = perPage or 2
	local gone: { [string]: boolean } = {}
	local function slice<T>(list: { T }, url: string): ({ T }, string?)
		local from = tonumber(query(url, "cursor") or "1") :: number
		local items = table.move(list, from, math.min(from + size - 1, #list), 1, {})
		return items, if from + size <= #list then tostring(from + size) else nil
	end
	return function(request: OpenCloud.Request): OpenCloud.Response
		local url = request.url
		local entry = `{query(url, "datastoreName")}/{query(url, "scope")}/{query(url, "entryKey")}`
		if request.method == "DELETE" then
			local keys = stores[query(url, "datastoreName") :: string][query(url, "scope") :: string]
			local index = assert(table.find(keys, query(url, "entryKey") :: string))
			gone[entry] = true
			if not lagging then
				table.remove(keys, index)
			end
			return F.response(204)
		elseif string.find(url, "/datastore/entries/entry?", 1, true) then
			return if gone[entry] then F.response(204) else F.response(200, "{}")
		elseif string.find(url, "/datastore/entries?", 1, true) then
			local all = {}
			local store = stores[query(url, "datastoreName") :: string]
			local scopes = {}
			for scope in store do
				table.insert(scopes, scope)
			end
			table.sort(scopes)
			for _, scope in scopes do
				for _, key in store[scope] do
					table.insert(all, { scope = scope, key = key })
				end
			end
			local items, cursor = slice(all, url)
			return F.response(200, serde.encode("json", { keys = items, nextPageCursor = cursor or "" }))
		end
		local names = {}
		for name in stores do
			if string.sub(name, 1, #(query(url, "prefix") :: string)) == query(url, "prefix") then
				table.insert(names, { name = name })
			end
		end
		table.sort(names, function(a, b)
			return a.name < b.name
		end)
		local items, cursor = slice(names, url)
		return F.response(200, serde.encode("json", { datastores = items, nextPageCursor = cursor }))
	end
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("clean-test-stores", function()
		it("deletes every entry of every store of the run, every scope and page, and lists them empty after", function()
			local stores = {
				[`{PREFIX}persist-Progress`] = { global = { "Player_-1", "Player_-2", "Player_-3" } },
				[`{PREFIX}resume-Progress`] = { global = { "Player_-1" }, other = { "x" } },
				[`{PREFIX}walkthrough-Progress`] = { global = {} },
				["Progress"] = { global = { "Player_123" } },
				["test-pr33-77-10-resume-Progress"] = { global = { "Player_-1" } },
			}
			local m = F.mock({ args = args(), handler = server(stores) })
			expect(m:run(CleanTestStores.main)).toBeNil()
			expect(stores[`{PREFIX}persist-Progress`].global).toEqual({})
			expect(stores[`{PREFIX}resume-Progress`]).toEqual({ global = {}, other = {} })
			-- a player's Save, and another run's store, are never touched
			expect(stores.Progress.global).toEqual({ "Player_123" })
			expect(stores["test-pr33-77-10-resume-Progress"].global).toEqual({ "Player_-1" })
			expect(m:stdout()).toContain(
				`{PREFIX}persist-Progress: deleted 3 entries; listed after: 0 entries; 0 with a value`
			)
			expect(m:stdout()).toContain(`test stores {PREFIX}*: 3 store(s), 5 entries deleted, 0 left with a value`)
		end)

		it("waits for a lagging listing, then reads each key still listed as deleted", function()
			local waited = {}
			local m = F.mock({
				args = args(),
				handler = server({ [`{PREFIX}a`] = { global = { "k1", "k2" } } }, 2, true),
				sleep = function(seconds)
					table.insert(waited, seconds)
				end,
			})
			expect(m:run(CleanTestStores.main)).toBeNil()
			expect(#waited).toBe(CleanTestStores.LIST_ATTEMPTS - 1)
			expect(m:stdout()).toContain(
				`{PREFIX}a: deleted 2 entries; listed after: 2 entries (2 still listed, each read as deleted); 0 with a value`
			)
		end)

		it("sends the key and builds every request through OpenCloud", function()
			local m = F.mock({ args = args(), handler = server({ [`{PREFIX}a`] = { global = { "k" } } }) })
			expect(m:run(CleanTestStores.main)).toBeNil()
			for _, call in m.calls do
				expect(call.headers[OpenCloud.API_KEY_HEADER]).toBe(F.KEY)
				local base = `{OpenCloud.BASE_URL}/datastores/v1/universes/{F.DEV}/standard-datastores`
				expect(string.sub(call.url, 1, #base)).toBe(base)
			end
			expect(m.calls[1].url).toContain(`prefix=test-{RUN}-`)
			expect(m.calls[2].url).toContain("allScopes=true")
			expect(m.calls[3].method).toBe("DELETE")
		end)

		it("fails when a listed entry still has a value after deleting", function()
			local stubborn = server({ [`{PREFIX}a`] = { global = { "k" } } })
			local m = F.mock({
				args = args(),
				handler = function(request)
					return if request.method == "DELETE" then F.response(204) else stubborn(request)
				end,
			})
			expect(m:run(CleanTestStores.main)).toContain("1 entries in the test stores still have a value")
		end)

		it("refuses a listed store without the run's prefix, deleting nothing", function()
			local m = F.mock({
				args = args(),
				handler = function()
					return F.response(200, '{"datastores":[{"name":"Progress"}]}')
				end,
			})
			expect(m:run(CleanTestStores.main)).toContain("refusing to touch it")
			expect(#m.calls).toBe(1)
		end)

		it("cleans the prefix the prelude's storeName() names stores with", function()
			local prelude = require("@lune/fs").readFile("tests/engine/_prelude.luau")
			expect(prelude).toContain('local name = "test-" .. RUN_ID .. "-" .. base')
			expect(EngineTests.storePrefix(RUN)).toBe(PREFIX)
		end)

		it("reads the spec's other forms: `data` for stores and plain keys", function()
			local names = OpenCloud.parseDataStoresPage(F.response(200, '{"data":[{"name":"a"}],"nextPageCursor":""}'))
			expect(names).toEqual({ "a" })
			local keys, cursor = OpenCloud.parseEntriesPage(F.response(200, '{"keys":["k"]}'))
			expect(keys).toEqual({ { scope = "global", key = "k" } })
			expect(cursor).toBeNil()
		end)

		it("refuses the Release universe without RELEASE_JOB, sending nothing, even in a dry run", function()
			for _, extra in { {}, { "--dry-run" } } do
				local m = F.mock({ args = args(F.RELEASE, extra) })
				expect(m:run(CleanTestStores.main)).toContain("refusing to target the Release universe")
				expect(#m.calls).toBe(0)
			end
		end)

		it("refuses a real run when the Release guard is not armed", function()
			local m = F.mock({ args = args(), env = { ROBLOX_DEV_API_KEY = F.KEY } })
			expect(m:run(CleanTestStores.main)).toContain("RELEASE_UNIVERSE_ID is not set")
			expect(#m.calls).toBe(0)
		end)

		it("needs a plain run id", function()
			local m = F.mock({ args = { "--universe", F.DEV, "--place", F.PLACE, "--run-id", "a b" } })
			expect(m:run(CleanTestStores.main)).toContain("must be at most 32 letters, digits or hyphens")
			local none = F.mock({ args = { "--universe", F.DEV, "--place", F.PLACE } })
			expect(none:run(CleanTestStores.main)).toContain("--run-id is required")
		end)

		it("dry run describes the requests and sends nothing", function()
			local m = F.mock({ args = args(nil, { "--dry-run" }), env = { RELEASE_UNIVERSE_ID = F.RELEASE } })
			expect(m:run(CleanTestStores.main)).toBeNil()
			expect(#m.calls).toBe(0)
			expect(m:stderr()).toContain("DELETE")
			expect(m:stderr()).toContain("<redacted>")
		end)
	end)
end
