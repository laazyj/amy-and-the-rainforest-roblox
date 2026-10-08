local F = require("../fixtures/opencloud")
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
			local path = `universes/{F.DEV}/places/{F.PLACE}/versions/5/luau-execution-sessions/s/tasks/{id}`
			nameByPath[path] = name
			server.polls[name] = 0
			server.inFlight += 1
			server.maxInFlight = math.max(server.maxInFlight, server.inFlight)
			return F.response(200, serde.encode("json", { path = path, state = "QUEUED" }))
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
			return F.response(
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
		return F.response(200, serde.encode("json", resource))
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
			F.DEV,
			"--place",
			F.PLACE,
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
	local m = F.mock({
		args = args,
		env = options.env or F.env({ GITHUB_RUN_ID = "42" }),
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
	{ "--universe", F.DEV, "--place", F.PLACE, "--script", "engine/a.luau", "--prelude", "engine/_prelude.luau" }

-- Answers the first `count` requests with `method` with a 429.
local function rateLimit(method: string, count: number, headers: { [string]: string }?)
	local limited = 0
	return function(request: OpenCloud.Request): OpenCloud.Response?
		if request.method == method and limited < count then
			limited += 1
			return F.response(429, "Too many requests", headers)
		end
		return nil
	end
end

local function lint(source: string): string?
	local ok, err = pcall(EngineTests.checkDataStoreUse :: any, "t.luau", source)
	return if ok then nil else tostring(err)
end

return function(t: any)
	local describe, it, expect, expectError = t.describe, t.it, t.expect, t.expectError

	describe("run-engine-tests", function()
		it("submits each script to the versioned task endpoint with key and timeout", function()
			local err, m, server =
				run({ behaviours = { ["a.luau"] = { logs = PASSING } }, extra = { "--timeout", "120" } })
			expect(err).toBeNil()
			expect(#server.created).toBe(1)
			expect(server.created[1].url).toBe(
				`https://apis.roblox.com/cloud/v2/universes/{F.DEV}/places/{F.PLACE}/versions/5/luau-execution-session-tasks`
			)
			expect(server.created[1].body.timeout).toBe("120s")
			expect(m.calls[1].headers["x-api-key"]).toBe(F.KEY)
			expect(m.calls[1].headers["content-type"]).toBe("application/json")
		end)

		it("uses the latest-version endpoint when --version is omitted", function()
			local err, _, server =
				run({ behaviours = { ["a.luau"] = { logs = PASSING } }, args = table.clone(SINGLE_LATEST) })
			expect(err).toBeNil()
			expect(server.created[1].url).toBe(
				`https://apis.roblox.com/cloud/v2/universes/{F.DEV}/places/{F.PLACE}/luau-execution-session-tasks`
			)
		end)

		it("injects RUN_ID before the prelude and the script", function()
			local err, _, server =
				run({ behaviours = { ["a.luau"] = { logs = PASSING } }, extra = { "--run-id", "pr-7" } })
			expect(err).toBeNil()
			local script = server.created[1].body.script
			local runIdAt = string.find(script, 'RUN_ID = "pr-7"', 1, true)
			local preludeAt = string.find(script, PRELUDE, 1, true)
			local sourceAt = string.find(script, 'print("a.luau")', 1, true)
			assert(runIdAt and preludeAt and sourceAt, `missing part in:\n{script}`)
			assert(runIdAt < preludeAt and preludeAt < sourceAt, "parts out of order")
		end)

		it("derives RUN_ID from the GitHub run when not given", function()
			local _, _, server = run({ behaviours = { ["a.luau"] = { logs = PASSING } } })
			expect(server.created[1].body.script).toContain('RUN_ID = "42-1"')
		end)

		it("rejects a RUN_ID that is unsafe in a DataStore name", function()
			local err = run({ behaviours = { ["a.luau"] = { logs = PASSING } }, extra = { "--run-id", 'x"; os' } })
			expect(err).toContain("run id")
		end)

		it("polls until the task is done", function()
			local sleeps = 0
			local err, _, server = run({
				behaviours = { ["a.luau"] = { polls = 4, logs = PASSING } },
				sleep = function()
					sleeps += 1
				end,
			})
			expect(err).toBeNil()
			expect(server.polls["a.luau"]).toBe(4)
			expect(sleeps).toBe(4)
		end)

		it("reads every page of logs and prints them", function()
			local logs = { "one", "two", "three", "four", "ENGINE_TESTS_PASSED" }
			local err, m = run({ behaviours = { ["a.luau"] = { logs = logs, logPages = 3 } } })
			expect(err).toBeNil()
			expect(m:stdout()).toContain("one\ntwo\nthree\nfour\nENGINE_TESTS_PASSED")
			expect(m:stdout()).toContain("PASS engine/a.luau")
		end)

		it("fails when the output does not end with ENGINE_TESTS_PASSED", function()
			local err, m = run({
				behaviours = {
					["a.luau"] = { logs = PASSING },
					["b.luau"] = { logs = { "ENGINE_TESTS_PASSED", "something after" } },
					["c.luau"] = { logs = {} },
				},
			})
			expect(err).toContain("2 engine test script(s) failed")
			expect(m:stdout()).toContain("PASS engine/a.luau")
			expect(m:stdout()).toContain("FAIL engine/b.luau: output does not end with ENGINE_TESTS_PASSED")
			expect(m:stdout()).toContain("FAIL engine/c.luau")
		end)

		it("fails when the task errored, even if it printed the marker", function()
			local err, m = run({ behaviours = { ["a.luau"] = { state = "FAILED", logs = PASSING } } })
			expect(err).toContain("1 engine test script(s) failed")
			expect(m:stdout()).toContain("FAIL engine/a.luau: task FAILED: SCRIPT_ERROR boom")
		end)

		it("skips helper files that start with an underscore", function()
			local _, _, server = run({
				behaviours = { ["a.luau"] = { logs = PASSING } },
				files = { ["engine/_helper.luau"] = "-- helper" },
			})
			expect(#server.created).toBe(1)
			expect(server.created[1].body.script).never.toContain("-- helper")
		end)

		it("skips .d.luau type declaration files", function()
			local _, _, server = run({
				behaviours = { ["a.luau"] = { logs = PASSING } },
				files = { ["engine/globals.d.luau"] = "declare RUN_ID: string" },
			})
			expect(#server.created).toBe(1)
			expect(server.created[1].body.script).never.toContain("declare RUN_ID")
		end)

		it("embeds the files a script names with include and fixture, once each", function()
			local err, _, server = run({
				behaviours = { ["a.luau"] = { logs = PASSING } },
				files = {
					["engine/a.luau"] = 'local h = include("engine/_h.luau")\n'
						.. 'local g, g2 = fixture("golden/a.json"), fixture( "golden/a.json" )\nfinish()\n',
					["engine/_h.luau"] = "return 'helper body'",
					["golden/a.json"] = '["golden text"]',
				},
			})
			expect(err).toBeNil()
			local script = server.created[1].body.script
			local _, helpers = string.gsub(script, "helper body", "")
			local _, texts = string.gsub(script, "golden text", "")
			expect(helpers).toBe(1)
			expect(texts).toBe(1)
			assert(
				(string.find(script, "helper body", 1, true) :: number)
					< string.find(script, "a.luau begins here", 1, true) :: number,
				"embedded files come before the script"
			)
		end)

		it("embeds the files an included helper names in turn", function()
			local err, _, server = run({
				behaviours = { ["a.luau"] = { logs = PASSING } },
				files = {
					["engine/a.luau"] = 'include("engine/_h.luau")',
					["engine/_h.luau"] = 'return fixture("golden/b.json")',
					["golden/b.json"] = "nested fixture text",
				},
			})
			expect(err).toBeNil()
			expect(server.created[1].body.script).toContain("nested fixture text")
		end)

		it("refuses an include or fixture path that is not a string literal, sending nothing", function()
			local err, m = run({
				behaviours = { ["a.luau"] = { logs = PASSING } },
				files = {
					["engine/a.luau"] = 'local p = "golden/a.json"\nfixture(p) -- fixture() in a comment is fine',
				},
			})
			expect(err).toContain("engine/a.luau: fixture() takes a path in double quotes")
			expect(#m.calls).toBe(0)
		end)

		it("refuses a script whose included or fixture file is missing, sending nothing", function()
			local err, m = run({
				behaviours = { ["a.luau"] = { logs = PASSING } },
				files = { ["engine/a.luau"] = 'fixture("golden/missing.json")' },
			})
			expect(err).toContain('engine/a.luau: fixture("golden/missing.json"): file not found')
			expect(#m.calls).toBe(0)
		end)

		it(`runs at most {EngineTests.CONCURRENCY} tasks at once`, function()
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
			expect(err).toBeNil()
			expect(#server.created).toBe(EngineTests.CONCURRENCY + 3)
			expect(server.maxInFlight).toBe(EngineTests.CONCURRENCY)
		end)

		it("waits out a 429 when creating a task, honouring Retry-After", function()
			local waited = {}
			local err, _, server = run({
				behaviours = { ["a.luau"] = { logs = PASSING } },
				args = table.clone(SINGLE_LATEST),
				intercept = rateLimit("POST", 2, { ["retry-after"] = "7" }),
				sleep = function(seconds)
					table.insert(waited, seconds)
				end,
			})
			expect(err).toBeNil()
			expect(waited[1]).toBe(7)
			expect(#server.created).toBe(1)
		end)

		it("retries Roblox's 'server busy' 409 when creating a task", function()
			local waited = {}
			local err, _, server = run({
				behaviours = { ["a.luau"] = { logs = PASSING } },
				args = table.clone(SINGLE_LATEST),
				intercept = (function()
					local busy = true
					return function(request: OpenCloud.Request): OpenCloud.Response?
						if request.method == "POST" and busy then
							busy = false
							return F.response(
								409,
								'{"code":"Conflict","message":"Server is busy. Please try again later."}'
							)
						end
						return nil
					end
				end)(),
				sleep = function(seconds)
					table.insert(waited, seconds)
				end,
			})
			expect(err).toBeNil()
			expect(waited[1]).toBe(OpenCloud.BUSY_BACKOFF[1])
			expect(#server.created).toBe(1)
		end)

		it("waits out a 429 while polling", function()
			local waited = {}
			local err = run({
				behaviours = { ["a.luau"] = { polls = 2, logs = PASSING } },
				args = table.clone(SINGLE_LATEST),
				intercept = rateLimit("GET", 1),
				sleep = function(seconds)
					table.insert(waited, seconds)
				end,
			})
			expect(err).toBeNil()
			expect(waited).toContain(EngineTests.RATE_LIMIT_WAIT)
		end)

		it("refuses the Release universe without RELEASE_JOB, sending nothing", function()
			local args = table.clone(SINGLE_LATEST)
			args[2] = F.RELEASE
			local err, m = run({ behaviours = { ["a.luau"] = { logs = PASSING } }, args = args })
			expect(err).toContain("refusing to target the Release universe")
			expect(#m.calls).toBe(0)
		end)

		it("dry run makes no request and prints the request it would make", function()
			local err, m = run({ behaviours = { ["a.luau"] = { logs = PASSING } }, extra = { "--dry-run" } })
			expect(err).toBeNil()
			expect(#m.calls).toBe(0)
			expect(m:stderr()).toContain(
				`POST https://apis.roblox.com/cloud/v2/universes/{F.DEV}/places/{F.PLACE}/versions/5/luau-execution-session-tasks`
			)
			expect(m:stderr()).toContain("x-api-key: <redacted>")
			expect(m:stderr()).never.toContain(F.KEY)
		end)

		describe("store lint", function()
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
				["MemoryStore GetQueue with a plain name"] = 'M:GetQueue("Q")',
				["MemoryStore GetSortedMap with a plain name"] = 'M:GetSortedMap("Map", 30)',
				["MemoryStore GetHashMap with a plain name"] = 'M:GetHashMap("Hash")',
				["a MemoryStore method indexed by name"] = 'M["GetQueue"](M, "Q")',
				["a MemoryStore method taken as a value"] = "local f = M.GetSortedMap",
			}
			for label, source in LINT_REFUSES do
				it(`refuses {label}`, function()
					expect(lint(source)).toContain("t.luau:1:")
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
				["a storeName call to a MemoryStore method"] = 'M:GetQueue(storeName("Q"), 30)',
				["other Get methods"] = 'game:GetService("Workspace"):GetChildren()',
				["a string mentioning GetHashMap"] = 'print("GetHashMap(x)")',
			}
			for label, source in LINT_ALLOWS do
				it(`allows {label}`, function()
					expect(lint(source)).toBeNil()
				end)
			end

			it("reports the source line, counting lines inside comments and strings", function()
				local source = '--[[ one\ntwo ]]\nlocal s = [[a\nb]]\nD:GetDataStore("x")'
				expect(lint(source)).toContain("t.luau:5:")
			end)

			it("refuses to submit a script that opens an unprefixed DataStore", function()
				local err, m = run({
					behaviours = { ["a.luau"] = { logs = PASSING } },
					files = { ["engine/a.luau"] = 'game:GetService("DataStoreService"):GetDataStore("Saves")' },
				})
				expect(err).toContain(
					"engine/a.luau:1: GetDataStore must be called as :GetDataStore(storeName(...), ...)"
				)
				expect(#m.calls).toBe(0)
			end)

			it("lints an included helper too", function()
				local err, m = run({
					behaviours = { ["a.luau"] = { logs = PASSING } },
					files = {
						["engine/a.luau"] = 'include("engine/_h.luau")',
						["engine/_h.luau"] = 'return game:GetService("DataStoreService"):GetDataStore("Saves")',
					},
				})
				expect(err).toContain("engine/_h.luau:1: GetDataStore must be called")
				expect(#m.calls).toBe(0)
			end)

			it("refuses to submit a script that opens an unprefixed MemoryStore", function()
				local err, m = run({
					behaviours = { ["a.luau"] = { logs = PASSING } },
					files = { ["engine/a.luau"] = 'game:GetService("MemoryStoreService"):GetSortedMap("Scores")' },
				})
				expect(err).toContain(
					"engine/a.luau:1: GetSortedMap must be called as :GetSortedMap(storeName(...), ...)"
				)
				expect(#m.calls).toBe(0)
			end)
		end)

		describe("pool and transport", function()
			it("a worker that raises counts as failed and the pool still finishes", function()
				local reported = {}
				local results = EngineTests.runPool({ "a", "b", "c" }, 2, function(item: string): boolean
					if item == "b" then
						error("worker blew up")
					end
					return true
				end, function(item: string, err: string)
					table.insert(reported, `{item}: {err}`)
				end, os.clock, math.huge)
				expect(results[1]).toBe(true)
				expect(results[2]).toBe(false)
				expect(results[3]).toBe(true)
				expect(#reported).toBe(1)
				expect(reported[1]).toContain("worker blew up")
			end)

			it("gives up when the run passes its wall-clock deadline", function()
				local now = 0
				expectError(function()
					EngineTests.runPool({ "hangs" }, 1, function(): boolean
						coroutine.yield() -- a request that never returns
						return true
					end, function() end, function()
						now += 100
						return now
					end, 1000)
				end, "run deadline")
			end)

			it("retries a 5xx on GET once", function()
				local failedOnce = false
				local err = run({
					behaviours = { ["a.luau"] = { polls = 2, logs = PASSING } },
					intercept = function(request)
						if request.method == "GET" and not failedOnce then
							failedOnce = true
							return F.response(503, "unavailable")
						end
						return nil
					end,
				})
				expect(failedOnce).toBe(true)
				expect(err).toBeNil()
			end)

			it("never retries a 5xx when creating a task", function()
				local err, m = run({
					behaviours = { ["a.luau"] = { logs = PASSING } },
					intercept = function(request)
						return if request.method == "POST" then F.response(500, "oops") else nil
					end,
				})
				expect(err).toContain("1 engine test script(s) failed")
				expect(m:stdout()).toContain("HTTP 500")
				expect(#m.calls).toBe(1)
			end)

			it("URL-encodes the logs page token", function()
				local urls = {}
				local err = run({
					behaviours = { ["a.luau"] = { logs = PASSING } },
					intercept = function(request)
						if string.find(request.url, "/logs?", 1, true) then
							table.insert(urls, request.url)
							if #urls == 1 then
								return F.response(
									200,
									'{"luauExecutionSessionTaskLogs":[{"messages":[]}],"nextPageToken":"a+b/c="}'
								)
							end
						end
						return nil
					end,
				})
				expect(err).toBeNil()
				expect(urls[2]).toContain("pageToken=a%2Bb%2Fc%3D")
			end)
		end)
	end)
end
