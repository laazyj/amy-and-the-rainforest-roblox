--!strict
-- Runs engine test scripts inside a place through Open Cloud Luau Execution.
-- Entry point: tools/run-engine-tests.luau.
--
-- Each script is submitted as one task: the RUN_ID and PASS_MARKER globals,
-- then tests/engine/_prelude.luau, then the script. A script passes only if
-- its task completes and the last thing it printed is the pass marker.

local Cli = require("./cli")
local OpenCloud = require("../opencloud")

local USAGE = [=[
usage: lune run tools/run-engine-tests (--script <path> | --dir <path>) [--version <n>]
         [--timeout <seconds>] [--run-id <id>] [--prelude <path>]]=]

local EngineTests = {}

EngineTests.PASS_MARKER = "ENGINE_TESTS_PASSED"
EngineTests.CONCURRENCY = 4
EngineTests.POLL_INTERVAL = 3
-- Extra seconds, beyond the script timeout, a script may spend queued or rate limited.
EngineTests.QUEUE_ALLOWANCE = 300
-- Creating tasks is rate limited (5 per minute per key owner) and capped at
-- 10 incomplete tasks per place; both answer 429, which is waited out.
EngineTests.RATE_LIMIT_WAIT = 15
EngineTests.DEFAULT_PRELUDE = "tests/engine/_prelude.luau"

-- Embedded files: for each of EngineTests.EMBED_FUNCTIONS, repository path ->
-- the file's text (see collectEmbeds).
type Embedded = { [string]: { [string]: string } }
type Script = { name: string, source: string, embedded: Embedded? }

-- RUN_ID ends up inside DataStore names (limit 50 characters), so keep it short and plain.
function EngineTests.resolveRunId(explicit: string?, env: { [string]: string? }): string
	local runId = explicit
		or if env.GITHUB_RUN_ID
			then `{env.GITHUB_RUN_ID}-{env.GITHUB_RUN_ATTEMPT or "1"}`
			else nil or `local-{os.time()}-{math.random(1000, 9999)}`
	if not string.match(runId, "^[%w%-]+$") or #runId > 32 then
		error(`run id '{runId}' must be at most 32 letters, digits or hyphens`, 0)
	end
	return runId
end

-- Methods that open a named store: any Get...DataStore on DataStoreService,
-- and these on MemoryStoreService. Keep in step with _GUARDED in
-- tests/engine/_prelude.luau, the run-time guard for the same methods.
local MEMORYSTORE_METHODS = table.freeze({ GetQueue = true, GetSortedMap = true, GetHashMap = true })

local function isStoreMethod(name: string): boolean
	return MEMORYSTORE_METHODS[name] == true or string.match(name, "^Get%a*DataStore$") ~= nil
end

local function blankLines(text: string): string
	local _, count = string.gsub(text, "\n", "")
	return string.rep("\n", count)
end

-- Replaces comments with spaces and string literals with "", so the lint
-- below sees only code. A string that is exactly a store method name is
-- kept, so indexing by name (D["GetDataStore"]) stays visible. Interpolated
-- strings keep their {expressions}, which are code.
local function stripCommentsAndStrings(source: string): string
	local out = {}
	local i = 1
	local function longBracketEnd(at: number): number?
		local equals = string.match(source, "^%[(=*)%[", at)
		if not equals then
			return nil
		end
		local _, close = string.find(source, `]{equals}]`, at, true)
		return close or #source
	end
	local function keepOrBlank(content: string)
		local kept = if isStoreMethod(content) then `"{content}"` else '""'
		table.insert(out, kept .. blankLines(content))
	end
	while i <= #source do
		local char = string.sub(source, i, i)
		local bracketClose = if char == "[" then longBracketEnd(i) else nil
		if string.sub(source, i, i + 1) == "--" then
			local close = longBracketEnd(i + 2)
			local after = if close then close + 1 else (string.find(source, "\n", i, true) or #source + 1)
			-- Keep the comment's newlines, so line numbers still match.
			table.insert(out, " " .. blankLines(string.sub(source, i, after - 1)))
			i = after
		elseif bracketClose then
			keepOrBlank(string.match(string.sub(source, i, bracketClose), "^%[=*%[(.-)%]=*%]$") or "")
			i = bracketClose + 1
		elseif char == '"' or char == "'" or char == "`" then
			local content = {}
			local j = i + 1
			while j <= #source do
				local c = string.sub(source, j, j)
				if c == "\\" then
					j += 2
				elseif c == char or (c == "\n" and char ~= "`") then
					break
				elseif char == "`" and c == "{" then
					local _, found = string.find(source, "^%b{}", j)
					local close = found or #source
					table.insert(out, " " .. string.sub(source, j + 1, close - 1) .. " ")
					j = close + 1
				else
					table.insert(content, c)
					j += 1
				end
			end
			keepOrBlank(table.concat(content))
			i = if string.sub(source, j, j) == char then j + 1 else j
		else
			table.insert(out, char)
			i += 1
		end
	end
	return table.concat(out)
end

-- Engine tests touch live DataStores and MemoryStores, so every store a
-- script opens must be named by storeName(), which prefixes it with the run
-- id. Every mention of a store method must be a call of the form
-- :GetDataStore(storeName(...), ...) (or :GetQueue, :GetSortedMap, ...);
-- anything else (indexing by name, taking the method as a value, string or
-- table call syntax, an expression around storeName) is refused, and
-- GetGlobalDataStore always is. The prelude's `game` proxy is the runtime
-- check behind this lint (see docs/OPEN_CLOUD.md for what neither covers).
function EngineTests.checkDataStoreUse(name: string, source: string)
	local code = stripCommentsAndStrings(source)
	local at = 1
	while true do
		local first, last, method = string.find(code, "%f[%w_](Get[%w_]*)%f[^%w_]", at)
		if not (first and last and method) then
			return
		end
		if not isStoreMethod(method) then
			at = last + 1
			continue
		end
		local where = `{name}:{#blankLines(string.sub(code, 1, first)) + 1}`
		if method == "GetGlobalDataStore" then
			error(`{where}: GetGlobalDataStore is not allowed in engine tests; use GetDataStore(storeName(...))`, 0)
		end
		local called = string.match(string.sub(code, 1, first - 1), ":%s*$")
			and string.match(code, "^%s*%(%s*storeName%s*%b()%s*[,%)]", last + 1)
		if not called then
			error(`{where}: {method} must be called as :{method}(storeName(...), ...)`, 0)
		end
		at = last + 1
	end
end

-- What tests/engine/_prelude.luau returns, bound as locals for the script.
EngineTests.PRELUDE_EXPORTS = table.freeze({ "describe", "it", "expect", "storeName", "finish", "game" })

-- Locals the runner itself binds, after the prelude's. A task cannot read the
-- repository, so a script names the files it needs and the runner embeds them:
--   include("tests/engine/_helper.luau")  runs that helper once, returns its value
--   fixture("tests/fixtures/x.json")      returns that file's text
EngineTests.EMBED_FUNCTIONS = table.freeze({ "include", "fixture" })

-- The paths `source` passes to `call` ("include" or "fixture"). Only a
-- string literal can be embedded, so any other argument is refused here,
-- before a task is spent.
local function embedPaths(name: string, source: string, call: string): { string }
	local paths = {}
	for path in string.gmatch(source, `%f[%w_]{call}%s*%(%s*"([^"]+)"%s*%)`) do
		table.insert(paths, path)
	end
	-- In code with comments removed and strings emptied, a literal call reads call("").
	local code = stripCommentsAndStrings(source)
	local _, calls = string.gsub(code, `%f[%w_]{call}%s*%(`, "")
	local _, literals = string.gsub(code, `%f[%w_]{call}%s*%(%s*""%s*%)`, "")
	if calls ~= literals then
		error(`{name}: {call}() takes a path in double quotes, which the runner embeds`, 0)
	end
	return paths
end

-- Every file `source` names with include() or fixture(), and every file those
-- helpers name in turn. A helper is code in the task, so it is linted too.
local function collectEmbeds(ctx: Cli.Context, name: string, source: string): Embedded
	local embedded: Embedded = {}
	for _, call in EngineTests.EMBED_FUNCTIONS do
		embedded[call] = {}
	end
	local queue = { { name = name, source = source } }
	while #queue > 0 do
		local item = table.remove(queue) :: { name: string, source: string }
		for _, call in EngineTests.EMBED_FUNCTIONS do
			for _, file in embedPaths(item.name, item.source, call) do
				if embedded[call][file] == nil then
					local text = ctx.readFile(file) or error(`{item.name}: {call}("{file}"): file not found`, 0)
					embedded[call][file] = text
					if call == "include" then
						EngineTests.checkDataStoreUse(file, text)
						table.insert(queue, { name = file, source = text })
					end
				end
			end
		end
	end
	return embedded
end

local function sortedKeys(map: { [string]: string }): { string }
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- The include() and fixture() locals, over the embedded files. A helper is
-- inlined as a function body, so it sees the prelude's locals (its `game` is
-- the guarded one); a fixture is a string literal.
local function embedSource(embedded: Embedded): string
	local includes, fixtures = embedded.include or {}, embedded.fixture or {}
	local lines = { "local include, fixture", "do", "\tlocal helpers, texts, loaded = {}, {}, {}" }
	for _, path in sortedKeys(includes) do
		table.insert(lines, `helpers[{string.format("%q", path)}] = function()`)
		table.insert(lines, includes[path])
		table.insert(lines, "end")
	end
	for _, path in sortedKeys(fixtures) do
		table.insert(lines, `texts[{string.format("%q", path)}] = {string.format("%q", fixtures[path])}`)
	end
	table.insert(
		lines,
		[[
	function include(path)
		if loaded[path] == nil then
			loaded[path] = { (assert(helpers[path], "not embedded: " .. path))() }
		end
		return table.unpack(loaded[path])
	end
	function fixture(path)
		return (assert(texts[path], "not embedded: " .. path))
	end
end]]
	)
	return table.concat(lines, "\n")
end

-- The task script: the injected globals, the prelude run as a function whose
-- exports become locals, the embedded files, then the test script.
function EngineTests.wrap(runId: string, prelude: string, script: Script): string
	local values = {}
	for i, name in EngineTests.PRELUDE_EXPORTS do
		values[i] = `__prelude.{name}`
	end
	return table.concat({
		`-- {script.name} (submitted by tools/run-engine-tests)`,
		`RUN_ID = "{runId}"`,
		`PASS_MARKER = "{EngineTests.PASS_MARKER}"`,
		"local __prelude = (function()",
		prelude,
		"end)()",
		`local {table.concat(EngineTests.PRELUDE_EXPORTS, ", ")} = {table.concat(values, ", ")}`,
		embedSource(script.embedded or {}),
		`-- {script.name} begins here`,
		script.source,
	}, "\n")
end

-- The verdict for a finished task and its log messages.
function EngineTests.verdict(taskResource: OpenCloud.Task, logs: { string }): (boolean, string?)
	if taskResource.state ~= "COMPLETE" then
		local err = taskResource.error
		return false, `task {taskResource.state or "?"}: {err and err.code or "?"} {err and err.message or ""}`
	end
	for i = #logs, 1, -1 do
		local line = string.match(logs[i], "^%s*(.-)%s*$") :: string
		if line ~= "" then
			if line == EngineTests.PASS_MARKER then
				return true, nil
			end
			break
		end
	end
	return false, `output does not end with {EngineTests.PASS_MARKER}`
end

local function runOne(ctx: Cli.Context, target: Cli.Target, createRequest: OpenCloud.Request, timeout: number)
	local waited = 0
	local deadline = timeout + EngineTests.QUEUE_ALLOWANCE
	local function wait(seconds: number)
		if waited >= deadline then
			error(`gave up after waiting {waited}s`, 0)
		end
		ctx.sleep(seconds)
		waited += seconds
	end
	-- Every Luau Execution call can be rate limited; a 429 is waited out
	-- within the deadline rather than failing the script.
	local function call(request: OpenCloud.Request): OpenCloud.Response
		local response = OpenCloud.send(ctx.http, ctx.sleep, request)
		while response.statusCode == 429 do
			wait(tonumber(response.headers["retry-after"]) or EngineTests.RATE_LIMIT_WAIT)
			response = OpenCloud.send(ctx.http, ctx.sleep, request)
		end
		return OpenCloud.expectOk(request, response)
	end

	local taskResource = OpenCloud.parseTaskResponse(call(createRequest), target.universeId)
	local pollRequest = OpenCloud.getTaskRequest(target.apiKey, taskResource.path)
	while not OpenCloud.TERMINAL_STATES[taskResource.state or ""] do
		wait(EngineTests.POLL_INTERVAL)
		taskResource = OpenCloud.parseTaskResponse(call(pollRequest), target.universeId)
	end

	local logs = {}
	local pageToken: string? = nil
	repeat
		local request = OpenCloud.listLogsRequest(target.apiKey, taskResource.path, pageToken)
		local messages
		messages, pageToken = OpenCloud.parseLogsPage(call(request))
		table.move(messages, 1, #messages, #logs + 1, logs)
	until pageToken == nil
	return taskResource, logs
end

-- Wall-clock seconds the whole run may take: each wave of CONCURRENCY scripts
-- gets its timeout, the queue allowance and the longest "server busy" wait,
-- plus a minute of slack. Guards
-- against a request that never returns (net.request has no timeout).
function EngineTests.runBudget(scripts: number, timeout: number): number
	local waves = math.ceil(scripts / EngineTests.CONCURRENCY)
	return waves * (timeout + EngineTests.QUEUE_ALLOWANCE + OpenCloud.BUSY_WAIT_TOTAL) + 60
end

-- Runs `worker` over `items` with at most `limit` running at once and returns
-- each verdict. A worker that raises counts as failed and is reported through
-- `onError`. Raises if the run is still going when `clock()` passes `deadline`.
function EngineTests.runPool<T>(
	items: { T },
	limit: number,
	worker: (T) -> boolean,
	onError: (T, string) -> (),
	clock: () -> number,
	deadline: number
): { boolean }
	local task = require("@lune/task")
	local results: { boolean } = table.create(#items, false)
	local nextIndex = 1
	local finished = 0
	local workers = math.min(limit, #items)
	for _ = 1, workers do
		task.spawn(function()
			while nextIndex <= #items do
				local index = nextIndex
				nextIndex += 1
				local ok, passed = pcall(worker, items[index])
				if not ok then
					pcall(onError, items[index], tostring(passed))
				end
				results[index] = ok and passed == true
			end
			finished += 1
		end)
	end
	while finished < workers do
		if clock() > deadline then
			error(`engine tests still running after the run deadline; giving up`, 0)
		end
		task.wait(0.1)
	end
	return results
end

local function loadScripts(ctx: Cli.Context, values: { [string]: string }): { Script }
	local single, dir = values.script, values.dir
	if (single == nil) == (dir == nil) then
		error("give exactly one of --script or --dir", 0)
	end
	local paths = {}
	if single then
		table.insert(paths, single)
	else
		local entries = ctx.listDir(dir) or error(`not a directory: {dir}`, 0)
		table.sort(entries)
		for _, entry in entries do
			-- Files starting with "_" are helpers (the prelude), and ".d.luau"
			-- files are type declarations for the linters; neither is a test.
			if
				string.match(entry, "%.luau$")
				and not string.match(entry, "%.d%.luau$")
				and string.sub(entry, 1, 1) ~= "_"
			then
				table.insert(paths, `{dir}/{entry}`)
			end
		end
	end
	if #paths == 0 then
		error("no engine test scripts found", 0)
	end
	local scripts = {}
	for _, path in paths do
		local source = ctx.readFile(path) or error(`script not found: {path}`, 0)
		EngineTests.checkDataStoreUse(path, source)
		table.insert(scripts, { name = path, source = source, embedded = collectEmbeds(ctx, path, source) })
	end
	return scripts
end

function EngineTests.main(ctx: Cli.Context)
	local target = Cli.target(ctx, USAGE, { "version", "script", "dir", "timeout", "run-id", "prelude" })
	local values = target.values
	local versionId = if values.version then Cli.numericId(values, "version") else nil
	local timeout = tonumber(values.timeout or OpenCloud.MAX_TASK_TIMEOUT)
	if not timeout or timeout < 1 or timeout > OpenCloud.MAX_TASK_TIMEOUT or timeout % 1 ~= 0 then
		error(`--timeout must be a whole number of seconds from 1 to {OpenCloud.MAX_TASK_TIMEOUT}`, 0)
	end

	local runId = EngineTests.resolveRunId(values["run-id"], ctx.env)
	local preludePath = values.prelude or EngineTests.DEFAULT_PRELUDE
	local prelude = ctx.readFile(preludePath) or error(`prelude not found: {preludePath}`, 0)
	local scripts = loadScripts(ctx, values)

	local function createRequest(script: Script): OpenCloud.Request
		local source = EngineTests.wrap(runId, prelude, script)
		return OpenCloud.createTaskRequest(target.apiKey, target.universeId, target.placeId, versionId, source, timeout)
	end

	ctx.log(`engine tests: {#scripts} script(s), RUN_ID {runId}`)
	if target.dryRun then
		for _, script in scripts do
			ctx.log(`dry run: {script.name} would send`)
			ctx.log(OpenCloud.describe(createRequest(script)))
		end
		ctx.log(OpenCloud.describeTaskPolling())
		return
	end

	local results = EngineTests.runPool(scripts, EngineTests.CONCURRENCY, function(script: Script): boolean
		local ok, taskResource, logs = pcall(function()
			return runOne(ctx, target, createRequest(script), timeout)
		end)
		local passed: boolean, reason: string? = false, tostring(taskResource)
		if ok then
			passed, reason = EngineTests.verdict(taskResource, logs)
		end
		-- Printed as each script finishes; no yield inside, so blocks never interleave.
		ctx.out(`--- {script.name}`)
		for _, line in (if ok then logs else {}) :: { string } do
			ctx.out(line)
		end
		ctx.out(if passed then `PASS {script.name}` else `FAIL {script.name}: {reason}`)
		return passed
	end, function(script: Script, err: string)
		ctx.out(`FAIL {script.name}: {err}`)
	end, ctx.clock, ctx.clock() + EngineTests.runBudget(#scripts, timeout))

	local failed = 0
	for _, passed in results do
		if not passed then
			failed += 1
		end
	end
	ctx.out(`{#results - failed} passed, {failed} failed`)
	if failed > 0 then
		error(`{failed} engine test script(s) failed`, 0)
	end
end

return EngineTests
