--!strict
-- Runs tests/engine/_prelude.luau under Lune, assembled by the same wrap()
-- tools/run-engine-tests uses, to prove finish() and storeName() behave before any engine time.
local H = require("./_harness")
local EngineTests = require("../../../tools/lib/engine-tests")
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local PRELUDE = fs.readFile(EngineTests.DEFAULT_PRELUDE)

-- Runs `body` wrapped exactly as tools/run-engine-tests submits it; returns
-- the printed lines and any error.
local function execute(body: string, runId: string?): ({ string }, string?)
	local printed = {}
	local env = setmetatable({
		print = function(...)
			table.insert(printed, table.concat({ ... }, " "))
		end,
	}, { __index = getfenv() })
	local source = EngineTests.wrap(runId or "", PRELUDE, { name = "test.luau", source = body })
	local chunk = luau.load(source, { debugName = "prelude", environment = env :: any })
	local ok, err = pcall(chunk)
	return printed, if ok then nil else tostring(err)
end

print("engine prelude")

H.test("finish prints ENGINE_TESTS_PASSED last when every test passes", function()
	local printed, err = execute([[
		describe("group", function()
			it("adds", function() expect(1 + 1).toBe(2) end)
			it("compares tables", function() expect({ a = { 1 } }).toEqual({ a = { 1 } }) end)
		end)
		finish()
	]])
	H.eq(err, nil, "error")
	H.eq(printed[#printed], "ENGINE_TESTS_PASSED", "last line")
	H.contains(table.concat(printed, "\n"), "ok   group > adds")
end)

H.test("finish lists failures, does not print the marker, and raises", function()
	local printed, err = execute([[
		it("passes", function() expect(true).toBeTruthy() end)
		it("fails", function() expect(1).toBe(2) end)
		it("throws", function() error("kaboom") end)
		finish()
	]])
	H.contains(err or "", "2 engine test(s) failed")
	local text = table.concat(printed, "\n")
	H.contains(text, "fails: ")
	H.contains(text, "expected 1 to be 2")
	H.contains(text, "kaboom")
	H.notContains(text, "ENGINE_TESTS_PASSED", "output with failures")
end)

H.test("finish raises when no tests ran", function()
	local _, err = execute("finish()")
	H.contains(err or "", "no tests ran")
end)

H.test("storeName prefixes with the run id", function()
	local printed, err = execute('print(storeName("Saves"))', "42-1")
	H.eq(err, nil, "error")
	H.eq(printed[1], "test-42-1-Saves", "store name")
end)

H.test("storeName refuses names over the 50-character DataStore limit", function()
	local _, err = execute(`storeName("{string.rep("x", 41)}")`, "42-1")
	H.contains(err or "", "over 50 characters")
end)

H.test("storeName refuses to run without RUN_ID", function()
	local _, err = execute('storeName("Saves")')
	H.contains(err or "", "RUN_ID is not set")
end)

return nil
