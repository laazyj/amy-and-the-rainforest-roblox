--[[
	Tier 1 test runner (Lune)
	=========================
	Run all tests with `tools/test.sh`, or only the tests whose full name
	contains some text with `tools/test.sh <text>`.

	Discovers every tests/lune/**/*.spec.luau, runs it, prints one line per
	test and exits non-zero if any test fails, if no tests are found, or
	(without a filter) if a spec registers no tests.
	No dependencies.

	A spec module returns a function that receives the test API:

		return function(t: any) -- untyped: specs cannot require the runner
			t.describe("chapter1", function()
				t.it("has quests", function()
					t.expect(#chapter.quests > 0).toBe(true)
				end)
			end)
		end

	Matchers: toBe, toEqual (deep), toBeNil, toContain, toBeA (typeof),
	toThrow; prefix with `never.` to negate, e.g. expect(x).never.toBeNil().

	Requiring modules from src/ under Lune
	--------------------------------------
	Lune resolves a require path relative to the file that requires it, so
	a pure module (no Roblox globals, no services) is required directly
	from a spec, and Lune finds `Thing.luau` or `Thing.lua`:

		local Thing = require("../../src/core/Thing")

	A module that uses Roblox datatypes as globals (Vector3, Color3, ...),
	like today's StoryData, cannot be required directly because Lune has
	no such globals. Load it through the bootstrap, which runs the file
	with those datatypes injected from @lune/roblox:

		local bootstrap = require("./bootstrap")
		local StoryData = bootstrap.loadSource("src/ReplicatedStorage/StoryData.lua")

	Modules that touch `game`, Instances or services do not run under Lune
	at all; they belong to the engine tests (tier 2).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local HERE = assert(string.match(debug.info(1, "s"), "^(.*)[/\\]"), "cannot locate the runner")
local filter = process.args[1]
-- Spec paths are only known at runtime, which the type checker cannot follow.
local dynamicRequire: any = require

type Test = { name: string, fn: () -> ...any }

local function format(value: any): string
	return if type(value) == "string" then string.format("%q", value) else stdio.format(value)
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function contains(container: any, item: any): boolean
	if type(container) == "string" then
		return string.find(container, item, 1, true) ~= nil
	end
	for _, value in container do
		if value == item then
			return true
		end
	end
	return false
end

local function expect(actual: any)
	local function matchers(negated: boolean)
		-- Level 3 points the error at the spec line that called the matcher.
		local function check(pass: boolean, description: string)
			if pass == negated then
				error(`expected {format(actual)} {if negated then "not " else ""}{description}`, 3)
			end
		end
		return {
			toBe = function(expected: any)
				check(actual == expected, `to be {format(expected)}`)
			end,
			toEqual = function(expected: any)
				check(deepEqual(actual, expected), `to deep-equal {format(expected)}`)
			end,
			toBeNil = function()
				check(actual == nil, "to be nil")
			end,
			toContain = function(item: any)
				check(contains(actual, item), `to contain {format(item)}`)
			end,
			toBeA = function(typeName: string)
				check(typeof(actual) == typeName, `to be a {typeName}`)
			end,
			toThrow = function()
				check(type(actual) == "function" and not pcall(actual), "to be a function that throws")
			end,
		}
	end
	local expectation: any = matchers(false)
	expectation.never = matchers(true)
	return expectation
end

-- Collects the tests declared by one spec, with describe names prefixed.
local function collect(spec: (any) -> ()): { Test }
	local tests: { Test } = {}
	local scope: { string } = {}
	local api = {
		expect = expect,
		describe = function(name: string, body: () -> ())
			table.insert(scope, name)
			body()
			table.remove(scope)
		end,
		it = function(name: string, fn: () -> ())
			table.insert(scope, name)
			local fullName = table.concat(scope, " ")
			table.remove(scope)
			if not filter or string.find(fullName, filter, 1, true) then
				table.insert(tests, { name = fullName, fn = fn })
			end
		end,
	}
	spec(api)
	return tests
end

local function findSpecs(dir: string, prefix: string, found: { string })
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			findSpecs(path, `{prefix}{entry}/`, found)
		elseif string.match(entry, "%.spec%.luau$") then
			table.insert(found, prefix .. entry)
		end
	end
end

local specs: { string } = {}
findSpecs(HERE, "", specs)

local passed, failed = 0, 0
for _, specPath in specs do
	print(specPath)
	local ok, testsOrError = pcall(function()
		return collect(dynamicRequire(`./{string.gsub(specPath, "%.luau$", "")}`))
	end)
	if not ok then
		failed += 1
		print(`  ✗ failed to load: {testsOrError}`)
		continue
	end
	-- Without a filter, an empty spec means its data loops found nothing to test.
	if not filter and #testsOrError == 0 then
		failed += 1
		print("  ✗ no tests registered")
	end
	for _, test in testsOrError do
		local testOk, message = pcall(test.fn)
		if testOk then
			passed += 1
			print(`  ✓ {test.name}`)
		else
			failed += 1
			print(`  ✗ {test.name}\n      {message}`)
		end
	end
end

print(`\n{passed} passed, {failed} failed, {#specs} spec files`)
if failed > 0 or passed == 0 then
	process.exit(1)
end
