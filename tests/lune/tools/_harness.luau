--!strict
-- Minimal test harness for the Open Cloud tool tests, plus mocks for the
-- tool context. Temporary: to be ported to tests/lune/runner.luau (brief 001).

local OpenCloud = require("../../../tools/opencloud")
local Cli = require("../../../tools/lib/cli")

local H = {}

-- Made-up ids and key used by every test. Never real ones.
H.DEV = "1001"
H.RELEASE = "2002"
H.PLACE = "3003"
H.KEY = "dev-key-not-real"

H.passed = 0
H.failures = {} :: { string }

function H.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		H.passed += 1
		print(`  ok   {name}`)
	else
		table.insert(H.failures, `{name}: {err}`)
		print(`  FAIL {name}: {err}`)
	end
end

function H.eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(`{label or "value"}: expected {expected}, got {actual}`, 2)
	end
end

function H.contains(haystack: string, needle: string, label: string?)
	if not string.find(haystack, needle, 1, true) then
		error(`{label or "text"}: expected to contain '{needle}' in:\n{haystack}`, 2)
	end
end

function H.notContains(haystack: string, needle: string, label: string?)
	if string.find(haystack, needle, 1, true) then
		error(`{label or "text"}: expected not to contain '{needle}' in:\n{haystack}`, 2)
	end
end

function H.response(statusCode: number, body: string?, headers: { [string]: string }?): OpenCloud.Response
	return {
		ok = statusCode >= 200 and statusCode < 300,
		statusCode = statusCode,
		headers = headers or {},
		body = body or "",
	}
end

-- The environment a Dev job has: a Dev key and the Release guard armed.
function H.env(overrides: { [string]: string }?): { [string]: string }
	local env = { ROBLOX_DEV_API_KEY = H.KEY, RELEASE_UNIVERSE_ID = H.RELEASE }
	for name, value in overrides or {} do
		env[name] = value
	end
	return env
end

export type Mock = {
	calls: { OpenCloud.Request },
	out: { string },
	log: { string },
	ctx: Cli.Context,
	-- Runs a tool's main against this mock; returns the error message or nil.
	run: (self: Mock, main: (Cli.Context) -> ()) -> string?,
	stdout: (self: Mock) -> string,
	stderr: (self: Mock) -> string,
}

local Mock = {}
Mock.__index = Mock

function Mock.run(self: Mock, main: (Cli.Context) -> ()): string?
	local ok, err = pcall(main, self.ctx)
	return if ok then nil else tostring(err)
end

function Mock.stdout(self: Mock): string
	return table.concat(self.out, "\n")
end

function Mock.stderr(self: Mock): string
	return table.concat(self.log, "\n")
end

-- A context whose HTTP is `handler` (records every request), whose sleep does
-- not wait (unless `sleep` is given), and whose filesystem is `files`.
function H.mock(options: {
	args: { string },
	env: { [string]: string }?,
	files: { [string]: string }?,
	handler: ((OpenCloud.Request) -> OpenCloud.Response)?,
	sleep: OpenCloud.Sleep?,
}): Mock
	local files = options.files or {}
	local mock = setmetatable({ calls = {}, out = {}, log = {} }, Mock) :: any
	mock.ctx = {
		args = options.args,
		env = options.env or H.env(),
		http = function(request)
			table.insert(mock.calls, request)
			assert(options.handler, `unexpected request: {request.method} {request.url}`)
			return options.handler(request)
		end,
		sleep = options.sleep or function() end,
		out = function(line)
			table.insert(mock.out, line)
		end,
		log = function(line)
			table.insert(mock.log, line)
		end,
		readFile = function(path)
			return files[path]
		end,
		listDir = function(path)
			local entries = nil
			for name in files do
				local entry = string.match(name, `^{path}/([^/]+)$`)
				if entry then
					entries = entries or {}
					table.insert(entries, entry)
				end
			end
			return entries
		end,
	}
	return mock
end

-- Asserts `main` succeeds against `mock`.
function H.passes(mock: Mock, main: (Cli.Context) -> ())
	local err = mock:run(main)
	if err then
		error(`expected success, got error: {err}`, 2)
	end
end

-- Asserts `main` fails against `mock` with an error containing `needle`.
function H.fails(mock: Mock, main: (Cli.Context) -> (), needle: string)
	local err = mock:run(main)
	if not err then
		error(`expected an error containing '{needle}', got success`, 2)
	elseif not string.find(err, needle, 1, true) then
		error(`expected an error containing '{needle}', got: {err}`, 2)
	end
end

return H
