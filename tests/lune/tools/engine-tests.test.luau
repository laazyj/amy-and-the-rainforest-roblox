--!strict
local H = require("./_harness")
local EngineTests = require("../../../tools/lib/engine-tests")
local OpenCloud = require("../../../tools/opencloud")
local serde = require("@lune/serde")
local task = require("@lune/task")

local PRELUDE = "-- prelude\n"
local PASSING = { "  ok   a test", "1 passed", "ENGINE_TESTS_PASSED" }

type Behaviour = { polls: number?, state: string?, logs: { string }?, logPages: number? }

-- A fake Luau Execution service. Each script's behaviour is looked up by its
-- file name, which tools/run-engine-tests puts on the first line of the task.
-- `polls` counts GETs of each task, by file name.
local function fakeServer(behaviours: { [string]: Behaviour })
	local server = { created = {} :: { any }, polls = {} :: { [string]: number }, inFlight = 0, maxInFlight = 0 }
	local nameByPath: { [string]: string } = {}
	local base = "https://apis.roblox.com/cloud/v2/"
	function server.handler(request: OpenCloud.Request): OpenCloud.Response
		if request.method == "POST" then
			local body = serde.decode("json", request.body :: string)
			table.insert(server.created, { url = request.url, body = body })
			local name = string.match(body.script, "^%-%- %S-([^/%s]+) ") :: string
			-- Real task ids are UUIDs; derive a stable one from the file name.
			local id = string.gsub(name, "[^%w]", "-")
			local path = `universes/{H.DEV}/places/{H.PLACE}/versions/5/luau-execution-sessions/s/tasks/{id}`
			nameByPath[path] = name
			server.polls[name] = 0
			server.inFlight += 1
			server.maxInFlight = math.max(server.maxInFlight, server.inFlight)
			return H.response(200, serde.encode("json", { path = path, state = "QUEUED" }))
		end
		local path, isLogs = string.match(request.url, `^{base}(.-)(/logs)%?`)
		if isLogs then
			local behaviour = behaviours[nameByPath[path :: string]]
			local messages = behaviour.logs or {}
			local page = tonumber(string.match(request.url, "pageToken=(%d+)")) or 1
			local pages = behaviour.logPages or 1
			-- Split the messages over `pages` pages to exercise pagination.
			local per = math.ceil(#messages / pages)
			local chunk = table.move(messages, (page - 1) * per + 1, math.min(page * per, #messages), 1, {})
			return H.response(
				200,
				serde.encode("json", {
					luauExecutionSessionTaskLogs = { { messages = chunk } },
					nextPageToken = if page < pages then tostring(page + 1) else nil,
				})
			)
		end
		local taskPath = string.sub(request.url, #base + 1)
		local name = nameByPath[taskPath]
		local behaviour = behaviours[name]
		server.polls[name] += 1
		local done = server.polls[name] >= (behaviour.polls or 1)
		if done then
			server.inFlight -= 1
		end
		local state = if done then behaviour.state or "COMPLETE" else "PROCESSING"
		local resource: any = { path = taskPath, state = state }
		if state == "FAILED" then
			resource.error = { code = "SCRIPT_ERROR", message = "boom" }
		end
		return H.response(200, serde.encode("json", resource))
	end
	return server
end

-- Runs the tool over engine/<name> for each behaviour (with --dir engine by
-- default). `intercept` can answer a request before the fake server does.
local function run(options: {
	behaviours: { [string]: Behaviour },
	args: { string }?,
	extra: { string }?,
	env: { [string]: string }?,
	files: { [string]: string }?,
	sleep: OpenCloud.Sleep?,
	intercept: ((OpenCloud.Request) -> OpenCloud.Response?)?,
})
	local files = options.files or {}
	files["engine/_prelude.luau"] = PRELUDE
	for name in options.behaviours do
		files[`engine/{name}`] = files[`engine/{name}`] or `print("{name}")\nfinish()\n`
	end
	local args = options.args
		or {
			"--universe",
			H.DEV,
			"--place",
			H.PLACE,
			"--version",
			"5",
			"--dir",
			"engine",
			"--prelude",
			"engine/_prelude.luau",
		}
	for _, arg in (options.extra or {}) :: { string } do
		table.insert(args, arg)
	end
	local server = fakeServer(options.behaviours)
	local m = H.mock({
		args = args,
		env = options.env or H.env({ GITHUB_RUN_ID = "42" }),
		files = files,
		handler = function(request)
			local intercepted = options.intercept and options.intercept(request)
			return intercepted or server.handler(request)
		end,
		sleep = options.sleep,
	})
	return m:run(EngineTests.main), m, server
end

local SINGLE_LATEST =
	{ "--universe", H.DEV, "--place", H.PLACE, "--script", "engine/a.luau", "--prelude", "engine/_prelude.luau" }

print("run-engine-tests")

H.test("submits each script to the versioned task endpoint with key and timeout", function()
	local err, m, server = run({ behaviours = { ["a.luau"] = { logs = PASSING } }, extra = { "--timeout", "120" } })
	H.eq(err, nil, "error")
	H.eq(#server.created, 1, "tasks created")
	H.eq(
		server.created[1].url,
		`https://apis.roblox.com/cloud/v2/universes/{H.DEV}/places/{H.PLACE}/versions/5/luau-execution-session-tasks`,
		"create url"
	)
	H.eq(server.created[1].body.timeout, "120s", "timeout")
	H.eq(m.calls[1].headers["x-api-key"], H.KEY, "api key header")
	H.eq(m.calls[1].headers["content-type"], "application/json", "content type")
end)

H.test("uses the latest-version endpoint when --version is omitted", function()
	local err, _, server = run({ behaviours = { ["a.luau"] = { logs = PASSING } }, args = table.clone(SINGLE_LATEST) })
	H.eq(err, nil, "error")
	H.eq(
		server.created[1].url,
		`https://apis.roblox.com/cloud/v2/universes/{H.DEV}/places/{H.PLACE}/luau-execution-session-tasks`,
		"create url"
	)
end)

H.test("injects RUN_ID before the prelude and the script", function()
	local err, _, server = run({ behaviours = { ["a.luau"] = { logs = PASSING } }, extra = { "--run-id", "pr-7" } })
	H.eq(err, nil, "error")
	local script = server.created[1].body.script
	local runIdAt = string.find(script, 'RUN_ID = "pr-7"', 1, true)
	local preludeAt = string.find(script, PRELUDE, 1, true)
	local sourceAt = string.find(script, 'print("a.luau")', 1, true)
	assert(runIdAt and preludeAt and sourceAt, `missing part in:\n{script}`)
	assert(runIdAt < preludeAt and preludeAt < sourceAt, "parts out of order")
end)

H.test("derives RUN_ID from the GitHub run when not given", function()
	local _, _, server = run({ behaviours = { ["a.luau"] = { logs = PASSING } } })
	H.contains(server.created[1].body.script, 'RUN_ID = "42-1"')
end)

H.test("rejects a RUN_ID that is unsafe in a DataStore name", function()
	local err = run({ behaviours = { ["a.luau"] = { logs = PASSING } }, extra = { "--run-id", 'x"; os' } })
	H.contains(err or "", "run id")
end)

H.test("polls until the task is done", function()
	local sleeps = 0
	local err, _, server = run({
		behaviours = { ["a.luau"] = { polls = 4, logs = PASSING } },
		sleep = function()
			sleeps += 1
		end,
	})
	H.eq(err, nil, "error")
	H.eq(server.polls["a.luau"], 4, "polls")
	H.eq(sleeps, 4, "waits between polls")
end)

H.test("reads every page of logs and prints them", function()
	local logs = { "one", "two", "three", "four", "ENGINE_TESTS_PASSED" }
	local err, m = run({ behaviours = { ["a.luau"] = { logs = logs, logPages = 3 } } })
	H.eq(err, nil, "error")
	H.contains(m:stdout(), "one\ntwo\nthree\nfour\nENGINE_TESTS_PASSED")
	H.contains(m:stdout(), "PASS engine/a.luau")
end)

H.test("fails when the output does not end with ENGINE_TESTS_PASSED", function()
	local err, m = run({
		behaviours = {
			["a.luau"] = { logs = PASSING },
			["b.luau"] = { logs = { "ENGINE_TESTS_PASSED", "something after" } },
			["c.luau"] = { logs = {} },
		},
	})
	H.contains(err or "", "2 engine test script(s) failed")
	H.contains(m:stdout(), "PASS engine/a.luau")
	H.contains(m:stdout(), "FAIL engine/b.luau: output does not end with ENGINE_TESTS_PASSED")
	H.contains(m:stdout(), "FAIL engine/c.luau")
end)

H.test("fails when the task errored, even if it printed the marker", function()
	local err, m = run({ behaviours = { ["a.luau"] = { state = "FAILED", logs = PASSING } } })
	H.contains(err or "", "1 engine test script(s) failed")
	H.contains(m:stdout(), "FAIL engine/a.luau: task FAILED: SCRIPT_ERROR boom")
end)

H.test("skips helper files that start with an underscore", function()
	local _, _, server = run({
		behaviours = { ["a.luau"] = { logs = PASSING } },
		files = { ["engine/_helper.luau"] = "-- helper" },
	})
	H.eq(#server.created, 1, "tasks created")
	H.notContains(server.created[1].body.script, "-- helper")
end)

H.test("skips .d.luau type declaration files", function()
	local _, _, server = run({
		behaviours = { ["a.luau"] = { logs = PASSING } },
		files = { ["engine/globals.d.luau"] = "declare RUN_ID: string" },
	})
	H.eq(#server.created, 1, "tasks created")
	H.notContains(server.created[1].body.script, "declare RUN_ID")
end)

H.test(`runs at most {EngineTests.CONCURRENCY} tasks at once`, function()
	local behaviours = {}
	for i = 1, EngineTests.CONCURRENCY + 3 do
		behaviours[`t{i}.luau`] = { polls = 3, logs = PASSING }
	end
	local err, _, server = run({
		behaviours = behaviours,
		sleep = function()
			task.wait()
		end,
	})
	H.eq(err, nil, "error")
	H.eq(#server.created, EngineTests.CONCURRENCY + 3, "tasks created")
	H.eq(server.maxInFlight, EngineTests.CONCURRENCY, "max tasks in flight")
end)

-- Answers the first `count` requests with `method` with a 429.
local function rateLimit(method: string, count: number, headers: { [string]: string }?)
	local limited = 0
	return function(request: OpenCloud.Request): OpenCloud.Response?
		if request.method == method and limited < count then
			limited += 1
			return H.response(429, "Too many requests", headers)
		end
		return nil
	end
end

H.test("waits out a 429 when creating a task, honouring Retry-After", function()
	local waited = {}
	local err, _, server = run({
		behaviours = { ["a.luau"] = { logs = PASSING } },
		args = table.clone(SINGLE_LATEST),
		intercept = rateLimit("POST", 2, { ["retry-after"] = "7" }),
		sleep = function(seconds)
			table.insert(waited, seconds)
		end,
	})
	H.eq(err, nil, "error")
	H.eq(waited[1], 7, "honours retry-after")
	H.eq(#server.created, 1, "tasks created")
end)

H.test("retries Roblox's 'server busy' 409 when creating a task", function()
	local waited = {}
	local err, _, server = run({
		behaviours = { ["a.luau"] = { logs = PASSING } },
		args = table.clone(SINGLE_LATEST),
		intercept = (function()
			local busy = true
			return function(request: OpenCloud.Request): OpenCloud.Response?
				if request.method == "POST" and busy then
					busy = false
					return H.response(409, '{"code":"Conflict","message":"Server is busy. Please try again later."}')
				end
				return nil
			end
		end)(),
		sleep = function(seconds)
			table.insert(waited, seconds)
		end,
	})
	H.eq(err, nil, "error")
	H.eq(waited[1], OpenCloud.BUSY_BACKOFF[1], "backoff")
	H.eq(#server.created, 1, "tasks created")
end)

H.test("waits out a 429 while polling", function()
	local waited = {}
	local err = run({
		behaviours = { ["a.luau"] = { polls = 2, logs = PASSING } },
		args = table.clone(SINGLE_LATEST),
		intercept = rateLimit("GET", 1),
		sleep = function(seconds)
			table.insert(waited, seconds)
		end,
	})
	H.eq(err, nil, "error")
	H.eq(table.find(waited, EngineTests.RATE_LIMIT_WAIT) ~= nil, true, "waited the rate-limit interval")
end)

H.test("refuses the Release universe without RELEASE_JOB, sending nothing", function()
	local args = table.clone(SINGLE_LATEST)
	args[2] = H.RELEASE
	local err, m = run({ behaviours = { ["a.luau"] = { logs = PASSING } }, args = args })
	H.contains(err or "", "refusing to target the Release universe")
	H.eq(#m.calls, 0, "requests")
end)

H.test("dry run makes no request and prints the request it would make", function()
	local err, m = run({ behaviours = { ["a.luau"] = { logs = PASSING } }, extra = { "--dry-run" } })
	H.eq(err, nil, "error")
	H.eq(#m.calls, 0, "requests")
	H.contains(
		m:stderr(),
		`POST https://apis.roblox.com/cloud/v2/universes/{H.DEV}/places/{H.PLACE}/versions/5/luau-execution-session-tasks`
	)
	H.contains(m:stderr(), "x-api-key: <redacted>")
	H.notContains(m:stderr(), H.KEY, "dry run output")
end)

print("run-engine-tests: DataStore lint")

local function lint(source: string): string?
	local ok, err = pcall(EngineTests.checkDataStoreUse :: any, "t.luau", source)
	return if ok then nil else tostring(err)
end

local LINT_REFUSES: { [string]: string } = {
	["a plain name"] = 'D:GetDataStore("PlayerData")',
	["string-call syntax"] = 'D:GetDataStore"PlayerData"',
	["single-quoted string-call syntax"] = "D:GetDataStore'PlayerData'",
	["long-string call syntax"] = "D:GetDataStore[[PlayerData]]",
	["table-call syntax"] = "D:GetDataStore{}",
	["indexing by name"] = 'D["GetDataStore"](D, "PlayerData")',
	["indexing by a long-string name"] = "D[ [[GetOrderedDataStore]] ](D, 'x')",
	["the method taken as a value"] = 'local f = D.GetDataStore; f(D, "PlayerData")',
	["an expression around storeName"] = 'D:GetDataStore(storeName("x") and "PlayerData")',
	["GetGlobalDataStore"] = "D:GetGlobalDataStore()",
	["a call inside an interpolated string"] = '`{D:GetDataStore("PlayerData")}`',
	["GetOrderedDataStore with a plain name"] = 'D:GetOrderedDataStore( "Scores" )',
}
for label, source in LINT_REFUSES do
	H.test(`refuses {label}`, function()
		H.contains(lint(source) or "", "t.luau:1:", "error")
	end)
end

local LINT_ALLOWS: { [string]: string } = {
	["a line comment"] = '-- never call GetGlobalDataStore or D:GetDataStore("x") here',
	["a block comment"] = '--[==[ D:GetDataStore("x") ]==]',
	["a string mentioning a call"] = 'local s = "GetDataStore(x)"',
	["a string mentioning GetGlobalDataStore"] = 'print("use GetGlobalDataStore")',
	["a storeName call"] = 'D:GetDataStore( storeName("PlayerData") )',
	["a storeName call with a scope"] = 'D:GetOrderedDataStore(storeName("Scores"), "scope")',
	["a storeName call with an interpolated base"] = "D:GetDataStore(storeName(`run-{i}`))",
	["a longer identifier"] = "local MyGetDataStoreHelper = 1",
}
for label, source in LINT_ALLOWS do
	H.test(`allows {label}`, function()
		H.eq(lint(source), nil, "error")
	end)
end

H.test("reports the source line, counting lines inside comments and strings", function()
	local source = '--[[ one\ntwo ]]\nlocal s = [[a\nb]]\nD:GetDataStore("x")'
	H.contains(lint(source) or "", "t.luau:5:", "error")
end)

H.test("refuses to submit a script that opens an unprefixed DataStore", function()
	local err, m = run({
		behaviours = { ["a.luau"] = { logs = PASSING } },
		files = { ["engine/a.luau"] = 'game:GetService("DataStoreService"):GetDataStore("Saves")' },
	})
	H.contains(err or "", "engine/a.luau:1: GetDataStore must be called as :GetDataStore(storeName(...), ...)")
	H.eq(#m.calls, 0, "requests")
end)

print("run-engine-tests: pool and transport")

H.test("a worker that raises counts as failed and the pool still finishes", function()
	local reported = {}
	local results = EngineTests.runPool({ "a", "b", "c" }, 2, function(item: string): boolean
		if item == "b" then
			error("worker blew up")
		end
		return true
	end, function(item: string, err: string)
		table.insert(reported, `{item}: {err}`)
	end, os.clock, math.huge)
	H.eq(results[1], true, "a")
	H.eq(results[2], false, "b")
	H.eq(results[3], true, "c")
	H.eq(#reported, 1, "errors reported")
	H.contains(reported[1], "worker blew up")
end)

H.test("gives up when the run passes its wall-clock deadline", function()
	local now = 0
	local ok, err = pcall(EngineTests.runPool, { "hangs" }, 1, function(): boolean
		coroutine.yield() -- a request that never returns
		return true
	end, function() end, function()
		now += 100
		return now
	end, 1000)
	H.eq(ok, false, "raised")
	H.contains(tostring(err), "run deadline")
end)

H.test("retries a 5xx on GET once", function()
	local failedOnce = false
	local err = run({
		behaviours = { ["a.luau"] = { polls = 2, logs = PASSING } },
		intercept = function(request)
			if request.method == "GET" and not failedOnce then
				failedOnce = true
				return H.response(503, "unavailable")
			end
			return nil
		end,
	})
	H.eq(failedOnce, true, "a 503 was returned")
	H.eq(err, nil, "error")
end)

H.test("never retries a 5xx when creating a task", function()
	local err, m = run({
		behaviours = { ["a.luau"] = { logs = PASSING } },
		intercept = function(request)
			return if request.method == "POST" then H.response(500, "oops") else nil
		end,
	})
	H.contains(err or "", "1 engine test script(s) failed")
	H.contains(m:stdout(), "HTTP 500")
	H.eq(#m.calls, 1, "requests")
end)

H.test("URL-encodes the logs page token", function()
	local urls = {}
	local err = run({
		behaviours = { ["a.luau"] = { logs = PASSING } },
		intercept = function(request)
			if string.find(request.url, "/logs?", 1, true) then
				table.insert(urls, request.url)
				if #urls == 1 then
					return H.response(
						200,
						'{"luauExecutionSessionTaskLogs":[{"messages":[]}],"nextPageToken":"a+b/c="}'
					)
				end
			end
			return nil
		end,
	})
	H.eq(err, nil, "error")
	H.contains(urls[2] or "", "pageToken=a%2Bb%2Fc%3D", "second page url")
end)

return nil
