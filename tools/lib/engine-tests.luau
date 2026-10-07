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

type Script = { name: string, source: string }

-- RUN_ID ends up inside DataStore names (limit 50 characters), so keep it short and plain.
function EngineTests.resolveRunId(explicit: string?, env: { [string]: string? }): string
	local runId = explicit
		or if env.GITHUB_RUN_ID then `{env.GITHUB_RUN_ID}-{env.GITHUB_RUN_ATTEMPT or "1"}` else nil
		or `local-{os.time()}-{math.random(1000, 9999)}`
	if not string.match(runId, "^[%w%-]+$") or #runId > 32 then
		error(`run id '{runId}' must be at most 32 letters, digits or hyphens`, 0)
	end
	return runId
end

-- Engine tests touch live DataStores, so every store they open must go through
-- storeName(), which prefixes it with the run id. This is a lint, not a sandbox.
function EngineTests.checkDataStoreUse(name: string, source: string)
	if string.find(source, "GetGlobalDataStore", 1, true) then
		error(`{name}: GetGlobalDataStore is not allowed in engine tests; use GetDataStore(storeName(...))`, 0)
	end
	for method, rest in string.gmatch(source, "(Get%a*DataStore)%s*(%b())") do
		if not string.match(rest, "^%(%s*storeName%(") then
			error(`{name}: {method}{rest} must name its store with storeName(...)`, 0)
		end
	end
end

function EngineTests.wrap(runId: string, prelude: string, script: Script): string
	return table.concat({
		`-- {script.name} (submitted by tools/run-engine-tests)`,
		`RUN_ID = "{runId}"`,
		`PASS_MARKER = "{EngineTests.PASS_MARKER}"`,
		prelude,
		`-- {script.name} begins here`,
		script.source,
	}, "\n")
end

-- The verdict for a finished task and its log messages.
function EngineTests.verdict(taskResource: OpenCloud.Task, logs: { string }): (boolean, string?)
	if taskResource.state ~= "COMPLETE" then
		local err = taskResource.error or {}
		return false, `task {taskResource.state or "?"}: {err.code or "?"} {err.message or ""}`
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

-- Runs `worker` over `items` with at most `limit` running at once.
local function runPool<T, R>(items: { T }, limit: number, worker: (T) -> R): { R }
	local task = require("@lune/task")
	local results: { R } = {}
	local nextIndex = 1
	local finished = 0
	local workers = math.min(limit, #items)
	for _ = 1, workers do
		task.spawn(function()
			while nextIndex <= #items do
				local index = nextIndex
				nextIndex += 1
				results[index] = worker(items[index])
			end
			finished += 1
		end)
	end
	while finished < workers do
		task.wait()
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
			-- Files starting with "_" are helpers (the prelude), not tests.
			if string.match(entry, "%.luau$") and string.sub(entry, 1, 1) ~= "_" then
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
		table.insert(scripts, { name = path, source = source })
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

	local results = runPool(scripts, EngineTests.CONCURRENCY, function(script: Script): boolean
		local ok, taskResource, logs = pcall(runOne, ctx, target, createRequest(script), timeout)
		local passed, reason = false, tostring(taskResource)
		if ok then
			passed, reason = EngineTests.verdict(taskResource, logs)
		end
		-- Printed as each script finishes; no yield inside, so blocks never interleave.
		ctx.out(`--- {script.name}`)
		for _, line in (if ok then logs else {}) do
			ctx.out(line)
		end
		ctx.out(if passed then `PASS {script.name}` else `FAIL {script.name}: {reason}`)
		return passed
	end)

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
