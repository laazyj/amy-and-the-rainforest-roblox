--!nocheck
-- Engine test prelude. tools/run-engine-tests submits every script in
-- tests/engine/ as one Luau Execution task: the RUN_ID and PASS_MARKER
-- globals, then this file, then the script. Luau Execution has no require for
-- repository files, so the helpers below are plain locals visible to the
-- script that follows.
--
--   describe(name, fn)  groups tests; nests
--   it(name, fn)        one test; an error inside fails it and the rest still run
--   expect(value)       .toBe(x) .toEqual(x) .toBeTruthy() .toBeNil() .toThrow()
--   storeName(base)     "test-<RUN_ID>-<base>": the only way to name a DataStore
--   finish()            last line of every script; prints PASS_MARKER,
--                       or the failures and then raises so the task fails
--
-- DataStores and MemoryStores are live in a task. The script's `game` is a
-- proxy whose DataStoreService and MemoryStoreService only open names that
-- start with storeName(""), and refuse GetGlobalDataStore. It covers this
-- script and anything that reaches those services through this `game`; a
-- required module uses the real `game` (see docs/OPEN_CLOUD.md).

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
	assert(
		type(RUN_ID) == "string" and RUN_ID ~= "",
		"RUN_ID is not set; run engine tests through tools/run-engine-tests"
	)
	local name = "test-" .. RUN_ID .. "-" .. base
	assert(#name <= 50, "DataStore name over 50 characters: " .. name)
	return name
end

-- Methods that open a named store: true means the name must come from
-- storeName(), false means never allowed in engine tests.
local _GUARDED = {
	DataStoreService = { GetDataStore = true, GetOrderedDataStore = true, GetGlobalDataStore = false },
	MemoryStoreService = { GetQueue = true, GetSortedMap = true, GetHashMap = true },
}

-- A proxy for an engine object: reads and writes go to `real`, methods run on
-- `real`, and keys in `overrides` are replaced.
local function _proxy(real, overrides)
	local proxy = {}
	local methods = {} -- one wrapper per method, so lookups are stable
	return setmetatable(proxy, {
		__index = function(_, key)
			local override = overrides[key]
			if override ~= nil then
				return override
			end
			local value = real[key]
			if type(value) ~= "function" then
				return value
			end
			if not methods[key] then
				methods[key] = function(self, ...)
					return value(if rawequal(self, proxy) then real else self, ...)
				end
			end
			return methods[key]
		end,
		__newindex = function(_, key, value)
			real[key] = value
		end,
		__tostring = function()
			return tostring(real)
		end,
	})
end

local function _guardService(serviceName, real)
	local overrides = {}
	for method, allowed in _GUARDED[serviceName] do
		overrides[method] = function(_, name, ...)
			local call = serviceName .. ":" .. method .. "(" .. tostring(name) .. ")"
			if not allowed then
				error(call .. " is not allowed in engine tests", 2)
			end
			local prefix = storeName("")
			if type(name) ~= "string" or string.sub(name, 1, #prefix) ~= prefix then
				error(call .. ": engine tests may only open names made by storeName()", 2)
			end
			return real[method](real, name, ...)
		end
	end
	return _proxy(real, overrides)
end

local game = (function(realGame)
	local overrides = {}
	for serviceName in _GUARDED do
		overrides[serviceName] = _guardService(serviceName, realGame:GetService(serviceName))
	end
	for _, method in { "GetService", "FindService" } do
		overrides[method] = function(_, serviceName)
			return _GUARDED[serviceName] and overrides[serviceName] or realGame[method](realGame, serviceName)
		end
	end
	return _proxy(realGame, overrides)
end)(game)
local Game = game

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
