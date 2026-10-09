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
-- Largest task script Luau Execution accepts ("up to 4 MB").
OpenCloud.MAX_TASK_SCRIPT_BYTES = 4_000_000

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
-- the task's `timeout` duration field. A script over MAX_TASK_SCRIPT_BYTES is
-- refused here, since the server would refuse it.
function OpenCloud.createTaskRequest(
	apiKey: string,
	universeId: string,
	placeId: string,
	versionId: string?,
	script: string,
	timeoutSeconds: number
): Request
	if #script > OpenCloud.MAX_TASK_SCRIPT_BYTES then
		error(`the task script is {#script} bytes; Luau Execution accepts {OpenCloud.MAX_TASK_SCRIPT_BYTES}`, 0)
	end
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

-- Assets API: upload an image, sound or model to the creator's account.
-- Verified against content/en-us/reference/cloud/assets/v1.json and
-- cloud/guides/usage-assets.md; see docs/OPEN_CLOUD.md.

-- The Roblox asset type for each manifest kind. Images go up as `Image`, whose
-- id an ImageLabel takes directly (a `Decal` id would need resolving first).
OpenCloud.ASSET_TYPES = table.freeze({
	image = "Image",
	audio = "Audio",
	model = "Model",
})

-- The file extensions the Assets API accepts for each kind, and the content
-- type each is sent with.
OpenCloud.ASSET_CONTENT_TYPES = table.freeze({
	image = table.freeze({
		png = "image/png",
		jpg = "image/jpeg",
		jpeg = "image/jpeg",
		bmp = "image/bmp",
		tga = "image/tga",
	}),
	audio = table.freeze({ mp3 = "audio/mpeg", ogg = "audio/ogg", wav = "audio/wav", flac = "audio/flac" }),
	model = table.freeze({
		fbx = "model/fbx",
		gltf = "model/gltf+json",
		glb = "model/gltf-binary",
		rbxm = "model/x-rbxm",
		rbxmx = "model/x-rbxm",
	}),
})

-- Largest file Create Asset accepts ("up to 20 MB").
OpenCloud.MAX_ASSET_BYTES = 20_000_000

-- The content type for `path` as an asset of `kind`, or nil if the API takes no such file.
function OpenCloud.assetContentType(kind: string, path: string): string?
	local types = OpenCloud.ASSET_CONTENT_TYPES[kind]
	local extension = string.match(path, "%.(%w+)$")
	return if types and extension then types[string.lower(extension)] else nil
end

-- Why the Assets API would refuse `bytes` bytes named `fileName` as a `kind`, or nil.
function OpenCloud.assetUploadProblem(kind: string, fileName: string, bytes: number): string?
	if not OpenCloud.ASSET_TYPES[kind] then
		return `{kind} is not an asset kind (image, audio, model)`
	elseif not OpenCloud.assetContentType(kind, fileName) then
		return `the Assets API takes no {kind} file named {fileName}`
	elseif bytes > OpenCloud.MAX_ASSET_BYTES then
		return `{fileName} is {bytes} bytes; the Assets API accepts {OpenCloud.MAX_ASSET_BYTES}`
	end
	return nil
end

export type AssetUpload = {
	kind: string,
	displayName: string,
	description: string,
	creatorUserId: string,
	fileName: string,
	file: string,
}

-- POST /assets/v1/assets, multipart/form-data with a JSON `request` part and
-- the file as `fileContent`. Scopes asset:read and asset:write. The response
-- is an Operation to poll.
function OpenCloud.createAssetRequest(apiKey: string, upload: AssetUpload): Request
	local problem = OpenCloud.assetUploadProblem(upload.kind, upload.fileName, #upload.file)
	if problem then
		error(problem, 0)
	end
	local contentType = OpenCloud.assetContentType(upload.kind, upload.fileName)
	local request = serde.encode("json", {
		assetType = OpenCloud.ASSET_TYPES[upload.kind],
		displayName = upload.displayName,
		description = upload.description,
		creationContext = { creator = { userId = upload.creatorUserId } },
	})
	-- A boundary that occurs nowhere in the parts.
	local boundary = "amy-asset-boundary"
	while string.find(upload.file, boundary, 1, true) or string.find(request, boundary, 1, true) do
		boundary ..= "-x"
	end
	local body = table.concat({
		`--{boundary}`,
		'Content-Disposition: form-data; name="request"',
		"Content-Type: application/json",
		"",
		request,
		`--{boundary}`,
		`Content-Disposition: form-data; name="fileContent"; filename="{upload.fileName}"`,
		`Content-Type: {contentType}`,
		"",
		upload.file,
		`--{boundary}--`,
		"",
	}, "\r\n")
	return {
		method = "POST",
		url = `{OpenCloud.BASE_URL}/assets/v1/assets`,
		headers = headers(apiKey, `multipart/form-data; boundary={boundary}`),
		body = body,
	}
end

export type Operation = {
	path: string,
	done: boolean,
	assetId: string?,
	moderation: string?,
	error: string?,
}

-- "Approved", "MODERATION_STATE_APPROVED" -> "approved". The spec and the
-- guide's example disagree on the form, so both are read.
local function moderationState(asset: any): string?
	local result = type(asset) == "table" and asset.moderationResult
	local state = type(result) == "table" and result.moderationState
	return if type(state) == "string" then string.lower((string.gsub(state, "^MODERATION_STATE_", ""))) else nil
end

-- The asset id as digits; the spec says integer, the guide's example a string.
local function assetIdOf(asset: any): string?
	local id = type(asset) == "table" and asset.assetId
	if type(id) == "number" then
		return string.format("%d", id)
	end
	return if type(id) == "string" and string.match(id, "^%d+$") then id else nil
end

-- An Operation from a create or get-operation response. Its path is checked,
-- because it is used to build the next URL.
function OpenCloud.parseOperation(response: Response): Operation
	local decoded = serde.decode("json", response.body)
	local path = decoded.path
	if type(path) ~= "string" or not string.match(path, "^operations/[%w%-]+$") then
		error(`unexpected operation path in response: {response.body}`, 0)
	end
	local failure = decoded.error
	return {
		path = path,
		done = decoded.done == true,
		assetId = assetIdOf(decoded.response),
		moderation = moderationState(decoded.response),
		error = if type(failure) == "table" then `{failure.code or "?"} {failure.message or ""}` else nil,
	}
end

-- GET /assets/v1/{operation.path}. Scope asset:read.
function OpenCloud.getOperationRequest(apiKey: string, operationPath: string): Request
	return {
		method = "GET",
		url = `{OpenCloud.BASE_URL}/assets/v1/{operationPath}`,
		headers = headers(apiKey, "application/json"),
	}
end

-- GET /assets/v1/assets/{assetId}, for its moderation state. Scope asset:read.
function OpenCloud.getAssetRequest(apiKey: string, assetId: string): Request
	assert(string.match(assetId, "^%d+$"), `not an asset id: {assetId}`)
	return {
		method = "GET",
		url = `{OpenCloud.BASE_URL}/assets/v1/assets/{assetId}?readMask=moderationResult`,
		headers = headers(apiKey, "application/json"),
	}
end

-- The moderation state in a get-asset response ("reviewing", "approved", "rejected").
function OpenCloud.parseAssetModeration(response: Response): string?
	return moderationState(serde.decode("json", response.body))
end

-- What happens after an asset is created, for --dry-run (the operation path is not known yet).
function OpenCloud.describeOperationPolling(): string
	return `then GET {OpenCloud.BASE_URL}/assets/v1/\{operation.path\} until done`
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
	return `then GET {cloudV2(path)} until state is one of {table.concat(states, ", ")}, then GET {cloudV2(
		path .. "/logs"
	)}`
end

-- Waits before each retry of a "server busy" 409 (see `isBusy`): about 7.5
-- minutes in all, then the 409 is returned.
OpenCloud.BUSY_BACKOFF = table.freeze({ 30, 60, 120, 240 })
OpenCloud.BUSY_WAIT_TOTAL = 0
for _, seconds in OpenCloud.BUSY_BACKOFF do
	OpenCloud.BUSY_WAIT_TOTAL += seconds
end

-- Roblox answers a busy save with 409 {"code":"Conflict","message":"... Please
-- try again in a couple minutes."}. That one 4xx is a request to retry.
local function isBusy(response: Response): boolean
	if response.statusCode ~= 409 then
		return false
	end
	local ok, body = pcall(function()
		return serde.decode("json", response.body)
	end)
	return ok
		and type(body) == "table"
		and body.code == "Conflict"
		and type(body.message) == "string"
		and string.find(string.lower(body.message), "try again", 1, true) ~= nil
end

-- Sends a request with the retry policy from the plan:
-- - a transport error is retried once;
-- - a 5xx is retried once only for GET, because a POST that failed with a 5xx
--   may still have been accepted (a second publish or a duplicate task);
-- - a "server busy" 409 is retried with BUSY_BACKOFF, then returned;
-- - any other 4xx is returned at once.
-- Returns the response, or raises.
function OpenCloud.send(http: Http, sleep: Sleep, request: Request): Response
	local retried = false
	local busyRetries = 0
	while true do
		local ok, result = pcall(http, request)
		local failure
		if not ok then
			failure = `transport error: {result}`
		else
			local response = result :: Response
			if isBusy(response) and busyRetries < #OpenCloud.BUSY_BACKOFF then
				busyRetries += 1
				sleep(OpenCloud.BUSY_BACKOFF[busyRetries])
				continue
			elseif response.statusCode < 500 or request.method ~= "GET" then
				return response
			end
			failure = `HTTP {response.statusCode}: {response.body}`
		end
		if retried then
			error(`{request.method} {request.url} failed after one retry ({failure})`, 0)
		end
		retried = true
		sleep(OpenCloud.RETRY_DELAY)
	end
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
