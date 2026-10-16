--!strict
-- Fixtures for the Open Cloud tool specs (tests/lune/tools/): made-up ids, a
-- canned HTTP response, and a mock tool context whose HTTP, clock, output and
-- filesystem are in memory, so no spec reaches the network.

local OpenCloud = require("../../../tools/opencloud")
local Cli = require("../../../tools/lib/cli")

local Fixtures = {}

-- Made-up ids and key used by every spec. Never real ones.
Fixtures.DEV = "1001"
Fixtures.RELEASE = "2002"
Fixtures.PLACE = "3003"
Fixtures.KEY = "dev-key-not-real"

function Fixtures.response(statusCode: number, body: string?, headers: { [string]: string }?): OpenCloud.Response
	return {
		ok = statusCode >= 200 and statusCode < 300,
		statusCode = statusCode,
		headers = headers or {},
		body = body or "",
	}
end

-- The environment a Dev job has: a Dev key and the Release guard armed.
function Fixtures.env(overrides: { [string]: string }?): { [string]: string }
	local env = { ROBLOX_DEV_API_KEY = Fixtures.KEY, RELEASE_UNIVERSE_ID = Fixtures.RELEASE }
	for name, value in (overrides or {}) :: { [string]: string } do
		env[name] = value
	end
	return env
end

export type Mock = {
	calls: { OpenCloud.Request },
	files: { [string]: string }, -- the filesystem, after any writes
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
	local ok, err = pcall(main :: any, self.ctx)
	return if ok then nil else tostring(err)
end

function Mock.stdout(self: Mock): string
	return table.concat(self.out, "\n")
end

function Mock.stderr(self: Mock): string
	return table.concat(self.log, "\n")
end

-- A context whose HTTP is `handler` (records every request), whose sleep does
-- not wait (unless `sleep` is given), and whose filesystem is `files`
-- (path -> contents; directories are implied by the paths).
function Fixtures.mock(options: {
	args: { string },
	env: { [string]: string }?,
	files: { [string]: string }?,
	handler: ((OpenCloud.Request) -> OpenCloud.Response)?,
	sleep: OpenCloud.Sleep?,
}): Mock
	local files: { [string]: string } = options.files or {}
	local mock = setmetatable({ calls = {}, out = {}, log = {}, files = files }, Mock) :: any
	mock.ctx = {
		args = options.args,
		env = options.env or Fixtures.env(),
		http = function(request)
			table.insert(mock.calls, request)
			assert(options.handler, `unexpected request: {request.method} {request.url}`)
			return options.handler(request)
		end,
		sleep = options.sleep or function() end,
		clock = function()
			return 0
		end,
		out = function(line)
			table.insert(mock.out, line)
		end,
		log = function(line)
			table.insert(mock.log, line)
		end,
		readFile = function(path)
			return files[path]
		end,
		writeFile = function(path, contents)
			files[path] = contents
		end,
		-- The files and subdirectories directly in `path`.
		listDir = function(path)
			local entries, seen = nil, {}
			for name in files do
				local entry = string.match(name, `^{path}/([^/]+)`)
				if entry and not seen[entry] then
					seen[entry] = true
					entries = entries or {}
					table.insert(entries, entry)
				end
			end
			return entries
		end,
	}
	return mock
end

return Fixtures
