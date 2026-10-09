--!strict
--[[
	Brief 008's coverage spike (docs/MAINTENANCE.md): a stand-in for the
	tier 1 runner's test API, small enough for the plain Luau CLI, which has
	no @lune libraries. It runs the specs named as program arguments (paths
	from the repository root) so `luau --coverage` can count the lines they
	reach. Only specs that require nothing from Lune can run here: today,
	those under tests/lune/core. Run it with tools/coverage-spike.sh; it is
	not part of CI. It mirrors tests/lune/runner.luau's test API: keep the
	two in step, and share them once the Luau CLI joins the toolchain.
]]

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
		return type(item) == "string" and string.find(container, item, 1, true) ~= nil
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
		local function check(pass: boolean, description: string)
			if pass == negated then
				error(`expected {tostring(actual)} {if negated then "not " else ""}{description}`, 3)
			end
		end
		return {
			toBe = function(expected: any)
				check(actual == expected, `to be {tostring(expected)}`)
			end,
			toEqual = function(expected: any)
				check(deepEqual(actual, expected), "to deep-equal")
			end,
			toBeNil = function()
				check(actual == nil, "to be nil")
			end,
			toContain = function(item: any)
				check(contains(actual, item), `to contain {tostring(item)}`)
			end,
			toBeA = function(typeName: string)
				check(typeof(actual) == typeName, `to be a {typeName}`)
			end,
			toThrow = function()
				check(type(actual) == "function" and not pcall(actual), "to throw")
			end,
		}
	end
	local expectation: any = matchers(false)
	expectation.never = matchers(true)
	return expectation
end

local function expectError(fn: () -> ...any, needle: string): string
	local ok, err = pcall(fn)
	if ok or not string.find(tostring(err), needle, 1, true) then
		error(`expected an error containing {needle}`, 2)
	end
	return tostring(err)
end

-- Spec paths are only known at runtime, which the type checker cannot follow.
local dynamicRequire: any = require
local specs: { string } = { ... }
local passed, failed, scope = 0, 0, {}
for _, path in specs do
	dynamicRequire(`../{string.gsub(path, "%.luau$", "")}`)({
		expect = expect,
		expectError = expectError,
		describe = function(name: string, body: () -> ())
			table.insert(scope, name)
			body()
			table.remove(scope)
		end,
		it = function(name: string, fn: () -> ...any)
			local ok, err = pcall(fn)
			if ok then
				passed += 1
			else
				failed += 1
				print(`✗ {table.concat(scope, " ")} {name}: {err}`)
			end
		end,
	})
end
print(`{passed} passed, {failed} failed, {#specs} spec files`)
-- Coverage from failing specs would mislead.
if failed > 0 then
	error(`{failed} failed`, 0)
end
