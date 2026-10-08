--!strict
-- Roblox Open Cloud: the only module in this repository that builds an Open
-- Cloud URL, header or payload. Everything else goes through it, so when an
-- endpoint changes there is exactly one place to fix.
--
-- Verified against the OpenAPI specs in github.com/Roblox/creator-docs
-- (content/en-us/reference/cloud/openapi.json and universes-api/v1.json);
-- see docs/OPEN_CLOUD.md for what was and was not verified.
--
-- HTTP is injected: `send` takes a function with the shape of Lune's
-- `net.request`, so tests can pass a mock and never reach the network.

export type Request = {
	method: string,
	url: string,
	headers: { [string]: string },
	body: string?,
}

export type Response = {
	ok: boolean,
	statusCode: number,
	statusMessage: string?,
	headers: { [string]: string },
	body: string,
}

export type Http = (Request) -> Response
export type Sleep = (seconds: number) -> ()

export type VersionType = "Saved" | "Published"

export type Task = {
	path: string,
	state: string?,
	error: { code: string?, message: string? }?,
	output: { results: { any }? }?,
}

local serde = require("@lune/serde")

local OpenCloud = {}

OpenCloud.BASE_URL = "https://apis.roblox.com"
OpenCloud.API_KEY_HEADER = "x-api-key"
-- Seconds to wait before the single retry (see `send`).
OpenCloud.RETRY_DELAY = 2

-- Longest a Luau Execution task may run, and the server default.
OpenCloud.MAX_TASK_TIMEOUT = 300

-- Task states that mean the task will not change again.
OpenCloud.TERMINAL_STATES = table.freeze({
	COMPLETE = true,
	FAILED = true,
	CANCELLED = true,
})

local function cloudV2(path: string): string
	return `{OpenCloud.BASE_URL}/cloud/v2/{path}`
end

-- Percent-encodes everything but RFC 3986 unreserved characters.
local function urlEncode(value: string): string
	return (string.gsub(value, "[^%w%-%._~]", function(char)
		return string.format("%%%02X", string.byte(char))
	end))
end

local function headers(apiKey: string, contentType: string): { [string]: string }
	return {
		[OpenCloud.API_KEY_HEADER] = apiKey,
		["content-type"] = contentType,
	}
end

-- Place publishing. POST /universes/v1/{universeId}/places/{placeId}/versions
-- Scope: universe-places:write. Body limit 10 MiB. Response {"versionNumber": n}.
function OpenCloud.publishRequest(
	apiKey: string,
	universeId: string,
	placeId: string,
	versionType: VersionType,
	placeFile: string
): Request
	return {
		method = "POST",
		url = `{OpenCloud.BASE_URL}/universes/v1/{universeId}/places/{placeId}/versions?versionType={versionType}`,
		headers = headers(apiKey, "application/octet-stream"),
		body = placeFile,
	}
end

function OpenCloud.parsePublishResponse(response: Response): number
	-- Documented as text/plain containing JSON.
	local version = serde.decode("json", response.body).versionNumber
	assert(type(version) == "number", `publish response has no versionNumber: {response.body}`)
	return version
end

-- Luau Execution. POST /cloud/v2/universes/{u}/places/{p}[/versions/{v}]/luau-execution-session-tasks
-- Scope: universe.place.luau-execution-session:write. `timeoutSeconds` maps to
-- the task's `timeout` duration field.
function OpenCloud.createTaskRequest(
	apiKey: string,
	universeId: string,
	placeId: string,
	versionId: string?,
	script: string,
	timeoutSeconds: number
): Request
	local parent = `universes/{universeId}/places/{placeId}`
	if versionId then
		parent ..= `/versions/{versionId}`
	end
	return {
		method = "POST",
		url = cloudV2(`{parent}/luau-execution-session-tasks`),
		headers = headers(apiKey, "application/json"),
		body = serde.encode("json", { script = script, timeout = `{timeoutSeconds}s` }),
	}
end

-- GET the task by the `path` the create call returned.
-- Scope: universe.place.luau-execution-session:read (or :write).
function OpenCloud.getTaskRequest(apiKey: string, taskPath: string): Request
	return { method = "GET", url = cloudV2(taskPath), headers = headers(apiKey, "application/json") }
end

-- A task resource from a create or get response. The path is checked to belong
-- to `universeId`, because it is used to build the next URLs.
function OpenCloud.parseTaskResponse(response: Response, universeId: string): Task
	local decoded = serde.decode("json", response.body)
	local path = decoded.path
	if type(path) ~= "string" or not string.match(path, `^universes/{universeId}/places/%d+/[%w%-/]+$`) then
		error(`unexpected task path in response: {response.body}`, 0)
	end
	return decoded
end

-- GET {taskPath}/logs, FLAT view: one string per print() call. Paginated.
function OpenCloud.listLogsRequest(apiKey: string, taskPath: string, pageToken: string?): Request
	local url = cloudV2(`{taskPath}/logs?maxPageSize=10000`)
	if pageToken then
		url ..= `&pageToken={urlEncode(pageToken)}`
	end
	return { method = "GET", url = url, headers = headers(apiKey, "application/json") }
end

-- The messages on one page of logs, and the token for the next page if any.
function OpenCloud.parseLogsPage(response: Response): ({ string }, string?)
	local page = serde.decode("json", response.body)
	local messages = {}
	for _, chunk in page.luauExecutionSessionTaskLogs or {} do
		table.move(chunk.messages or {}, 1, #(chunk.messages or {}), #messages + 1, messages)
	end
	local token = page.nextPageToken
	return messages, if token and token ~= "" then token else nil
end

-- A request as it would be sent, with the key redacted. For --dry-run.
function OpenCloud.describe(request: Request): string
	local lines = { `{request.method} {request.url}` }
	local names = {}
	for name in request.headers do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local value = if name == OpenCloud.API_KEY_HEADER then "<redacted>" else request.headers[name]
		table.insert(lines, `  {name}: {value}`)
	end
	if request.body then
		table.insert(lines, `  body: {#request.body} bytes`)
	end
	return table.concat(lines, "\n")
end

-- What happens after a task is created, for --dry-run (the task path is not known yet).
function OpenCloud.describeTaskPolling(): string
	local states = {}
	for state in OpenCloud.TERMINAL_STATES do
		table.insert(states, state)
	end
	table.sort(states)
	local path = "{task.path}"
	return `then GET {cloudV2(path)} until state is one of {table.concat(states, ", ")}, then GET {cloudV2(path .. "/logs")}`
end

-- Sends a request with the retry policy from the plan: a transport error is
-- retried once; a 4xx never is. A 5xx is retried once only for GET, because a
-- POST that failed with a 5xx may still have been accepted (a second publish
-- or a duplicate task). Returns the response, or raises.
function OpenCloud.send(http: Http, sleep: Sleep, request: Request): Response
	local lastError = ""
	for attempt = 1, 2 do
		local ok, result = pcall(http, request)
		if ok then
			local response = result :: Response
			if response.statusCode < 500 or request.method ~= "GET" then
				return response
			end
			lastError = `HTTP {response.statusCode}: {response.body}`
		else
			lastError = `transport error: {result}`
		end
		if attempt == 1 then
			sleep(OpenCloud.RETRY_DELAY)
		end
	end
	error(`{request.method} {request.url} failed after one retry ({lastError})`, 0)
end

-- Raises a readable error for any non-2xx response.
function OpenCloud.expectOk(request: Request, response: Response): Response
	if not response.ok then
		error(`{request.method} {request.url} returned HTTP {response.statusCode}: {response.body}`, 0)
	end
	return response
end

-- `send`, then `expectOk`.
function OpenCloud.call(http: Http, sleep: Sleep, request: Request): Response
	return OpenCloud.expectOk(request, OpenCloud.send(http, sleep, request))
end

return OpenCloud
