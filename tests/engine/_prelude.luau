--!nocheck
-- Engine test prelude. tools/run-engine-tests submits every script in
-- tests/engine/ as one Luau Execution task: the RUN_ID and PASS_MARKER
-- globals, then this file, then the script. Luau Execution has no require for repository files, so the
-- helpers below are plain locals visible to the script that follows.
--
--   describe(name, fn)  groups tests; nests
--   it(name, fn)        one test; an error inside fails it and the rest still run
--   expect(value)       .toBe(x) .toEqual(x) .toBeTruthy() .toBeNil() .toThrow()
--   storeName(base)     "test-<RUN_ID>-<base>": the only way to name a DataStore
--   finish()            last line of every script; prints PASS_MARKER,
--                       or the failures and then raises so the task fails

local _scope = {}
local _passed = 0
local _failures = {}

local function _show(value)
	return if type(value) == "string" then string.format("%q", value) else tostring(value)
end

local function _deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not _deepEqual(value, b[key]) then
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

local function describe(name, fn)
	table.insert(_scope, name)
	fn()
	table.remove(_scope)
end

local function it(name, fn)
	local path = table.clone(_scope)
	table.insert(path, name)
	local fullName = table.concat(path, " > ")
	local ok, err = pcall(fn)
	if ok then
		_passed += 1
		print("  ok   " .. fullName)
	else
		table.insert(_failures, fullName .. ": " .. tostring(err))
		print("  FAIL " .. fullName .. ": " .. tostring(err))
	end
end

local function expect(actual)
	local function check(pass, message)
		if not pass then
			error(message, 3)
		end
	end
	return {
		toBe = function(expected)
			check(actual == expected, "expected " .. _show(actual) .. " to be " .. _show(expected))
		end,
		toEqual = function(expected)
			check(_deepEqual(actual, expected), "expected " .. _show(actual) .. " to deep-equal " .. _show(expected))
		end,
		toBeTruthy = function()
			check(actual, "expected " .. _show(actual) .. " to be truthy")
		end,
		toBeNil = function()
			check(actual == nil, "expected " .. _show(actual) .. " to be nil")
		end,
		toThrow = function()
			check(not pcall(actual), "expected function to throw")
		end,
	}
end

local function storeName(base)
	assert(type(RUN_ID) == "string" and RUN_ID ~= "", "RUN_ID is not set; run engine tests through tools/run-engine-tests")
	local name = "test-" .. RUN_ID .. "-" .. base
	assert(#name <= 50, "DataStore name over 50 characters: " .. name)
	return name
end

local function finish()
	if _passed == 0 and #_failures == 0 then
		error("no tests ran")
	end
	if #_failures > 0 then
		print(#_failures .. " failed, " .. _passed .. " passed:")
		for _, failure in _failures do
			print("  " .. failure)
		end
		error(#_failures .. " engine test(s) failed", 0)
	end
	print(_passed .. " passed")
	print(PASS_MARKER)
end
