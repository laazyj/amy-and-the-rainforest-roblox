-- Runs tests/engine/_prelude.luau under Lune, assembled by the same wrap()
-- tools/run-engine-tests uses, to prove finish(), storeName() and the `game`
-- proxy behave before any engine time.
local EngineTests = require("../../../tools/lib/engine-tests")
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local PRELUDE = fs.readFile(EngineTests.DEFAULT_PRELUDE)

-- A stand-in for the engine's `game`: services whose store methods record
-- what they opened, and assert they were called on the real service rather
-- than on the prelude's proxy.
local STORE_METHODS =
	{ "GetDataStore", "GetOrderedDataStore", "GetGlobalDataStore", "GetQueue", "GetSortedMap", "GetHashMap" }

local function fakeGame(opened: { string }): any
	local services = {}
	for _, serviceName in { "DataStoreService", "MemoryStoreService", "Workspace" } do
		local service = { Name = serviceName }
		for _, method in STORE_METHODS do
			service[method] = function(self, name)
				assert(rawequal(self, service), `{method} was called on the proxy, not the real service`)
				table.insert(opened, `{method}:{name}`)
				return { Name = name }
			end
		end
		services[serviceName] = service
	end
	local game
	game = {
		PlaceId = 7,
		GetService = function(self, serviceName)
			assert(rawequal(self, game), "GetService was called on the proxy, not the real game")
			return services[serviceName]
		end,
		FindService = function(self, serviceName)
			assert(rawequal(self, game), "FindService was called on the proxy, not the real game")
			return services[serviceName]
		end,
	}
	return game
end

-- Runs `body` wrapped exactly as tools/run-engine-tests submits it, against a
-- fake `game`; returns the printed lines, any error, and the stores opened.
local function execute(body: string, runId: string?): ({ string }, string?, { string })
	local printed, opened = {}, {}
	local env = setmetatable({
		game = fakeGame(opened),
		print = function(...)
			local parts = table.pack(...)
			for i = 1, parts.n do
				parts[i] = tostring(parts[i])
			end
			table.insert(printed, table.concat(parts, " "))
		end,
	}, { __index = getfenv() })
	local source = EngineTests.wrap(runId or "", PRELUDE, { name = "test.luau", source = body })
	local chunk = luau.load(source, { debugName = "prelude", environment = env :: any })
	local ok, err = pcall(chunk)
	return printed, if ok then nil else tostring(err), opened
end

local DS = 'local D = game:GetService("DataStoreService")\n'
local MS = 'local M = game:GetService("MemoryStoreService")\n'

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("engine prelude", function()
		it("finish prints ENGINE_TESTS_PASSED last when every test passes", function()
			local printed, err = execute([[
				describe("group", function()
					it("adds", function() expect(1 + 1).toBe(2) end)
					it("compares tables", function() expect({ a = { 1 } }).toEqual({ a = { 1 } }) end)
				end)
				finish()
			]])
			expect(err).toBeNil()
			expect(printed[#printed]).toBe("ENGINE_TESTS_PASSED")
			expect(table.concat(printed, "\n")).toContain("ok   group > adds")
		end)

		it("finish lists failures, does not print the marker, and raises", function()
			local printed, err = execute([[
				it("passes", function() expect(true).toBeTruthy() end)
				it("fails", function() expect(1).toBe(2) end)
				it("throws", function() error("kaboom") end)
				finish()
			]])
			expect(err).toContain("2 engine test(s) failed")
			local text = table.concat(printed, "\n")
			expect(text).toContain("fails: ")
			expect(text).toContain("expected 1 to be 2")
			expect(text).toContain("kaboom")
			expect(text).never.toContain("ENGINE_TESTS_PASSED")
		end)

		it("finish raises when no tests ran", function()
			local _, err = execute("finish()")
			expect(err).toContain("no tests ran")
		end)

		it("storeName prefixes with the run id", function()
			local printed, err = execute('print(storeName("Saves"))', "42-1")
			expect(err).toBeNil()
			expect(printed[1]).toBe("test-42-1-Saves")
		end)

		it("storeName refuses names over the 50-character DataStore limit", function()
			local _, err = execute(`storeName("{string.rep("x", 41)}")`, "42-1")
			expect(err).toContain("over 50 characters")
		end)

		it("storeName refuses to run without RUN_ID", function()
			local _, err = execute('storeName("Saves")', "")
			expect(err).toContain("RUN_ID is not set")
		end)

		it("returns exactly the helpers the runner binds", function()
			local env = setmetatable({ game = fakeGame({}) }, { __index = getfenv() })
			local exports = luau.load(PRELUDE, { debugName = "prelude", environment = env :: any })()
			local names = {}
			for name in exports do
				table.insert(names, name)
			end
			table.sort(names)
			local expected = table.clone(EngineTests.PRELUDE_EXPORTS)
			table.sort(expected)
			expect(names).toEqual(expected)
		end)

		it("the static-check declarations match the helpers the runner binds", function()
			local expected = {}
			for _, name in EngineTests.PRELUDE_EXPORTS do
				if name ~= "game" then -- declared by Roblox's own std and definitions
					table.insert(expected, name)
				end
			end
			table.sort(expected)
			local function declared(path: string, pattern: string): string
				local names = {}
				for name in string.gmatch(fs.readFile(path), pattern) do
					if name ~= "RUN_ID" and name ~= "PASS_MARKER" then
						table.insert(names, name)
					end
				end
				table.sort(names)
				return table.concat(names, ",")
			end
			local want = table.concat(expected, ",")
			expect(declared("tests/engine/engine.yml", "\n  (%w+):\n")).toBe(want)
			expect(declared("tests/engine/globals.d.luau", "declare function (%w+)")).toBe(want)
		end)
	end)

	describe("engine prelude: game proxy", function()
		it("opens stores named by storeName, on the real service", function()
			local _, err, opened = execute(DS .. MS .. [[
				D:GetDataStore(storeName("Saves"))
				D:GetOrderedDataStore(storeName("Scores"), "scope")
				M:GetQueue(storeName("Q"))
				M:GetSortedMap(storeName("Map"))
				M:GetHashMap(storeName("Hash"))
			]], "42-1")
			expect(err).toBeNil()
			expect(opened).toEqual({
				"GetDataStore:test-42-1-Saves",
				"GetOrderedDataStore:test-42-1-Scores",
				"GetQueue:test-42-1-Q",
				"GetSortedMap:test-42-1-Map",
				"GetHashMap:test-42-1-Hash",
			})
		end)

		-- Every way the lint can be dodged still reaches the proxy at run time.
		local REFUSED: { [string]: string } = {
			["a plain name"] = DS .. 'D:GetDataStore("PlayerData")',
			["string-call syntax"] = DS .. 'D:GetDataStore"PlayerData"',
			["indexing by name"] = DS .. 'D["GetDataStore"](D, "PlayerData")',
			["the method taken as a value"] = DS .. 'local f = D.GetDataStore; f(D, "PlayerData")',
			["an expression around storeName"] = DS .. 'D:GetDataStore(storeName("x") and "PlayerData")',
			["another run's prefix"] = DS .. 'D:GetDataStore("test-42-10-Saves")',
			["a non-string name"] = DS .. "D:GetDataStore(nil)",
			["GetOrderedDataStore"] = DS .. 'D:GetOrderedDataStore("Scores")',
			["GetGlobalDataStore"] = DS .. "D:GetGlobalDataStore()",
			["game.DataStoreService"] = 'game.DataStoreService:GetDataStore("PlayerData")',
			["game:FindService"] = 'game:FindService("DataStoreService"):GetDataStore("PlayerData")',
			["MemoryStore GetQueue"] = MS .. 'M:GetQueue("Q")',
			["MemoryStore GetSortedMap"] = MS .. 'M:GetSortedMap("Map")',
			["MemoryStore GetHashMap"] = MS .. 'M:GetHashMap("Hash")',
			["a function handed the proxied service"] = DS .. [[
				local function openSaves(service) return service:GetDataStore("PlayerData") end
				openSaves(D)
			]],
		}
		for label, body in REFUSED do
			it(`refuses {label}`, function()
				local _, err, opened = execute(body, "42-1")
				expect(err).toContain("engine tests")
				expect(#opened).toBe(0)
			end)
		end

		it("passes everything else through to the real game", function()
			local printed, err =
				execute('print(game.PlaceId, game:GetService("Workspace").Name, tostring(game) ~= nil)', "42-1")
			expect(err).toBeNil()
			expect(printed[1]).toBe("7 Workspace true")
		end)
	end)
end
