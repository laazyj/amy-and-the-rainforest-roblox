--!strict
-- A minimal MCP client over stdio: newline-delimited JSON-RPC 2.0, enough to
-- initialise a server and call its tools. Roblox Studio's built-in MCP server
-- is reached through the StudioMCP proxy in the app bundle (studio.luau).
-- The framing and result parsing are pure and unit-tested; `connect` spawns
-- the server and runs under Lune only.

local Mcp = {}

export type Client = {
	-- Calls a tool and returns its text result; raises on a tool error, a
	-- JSON-RPC error, a timeout or a server that has exited.
	callTool: (name: string, arguments: { [string]: any }) -> string,
	close: () -> (),
}

local PROTOCOL_VERSION = "2025-06-18"
local TOOL_TIMEOUT = 120

-- Splits what has been read so far into complete lines and the unfinished rest.
function Mcp.lines(pending: string): ({ string }, string)
	local lines = {}
	local from = 1
	while true do
		local newline = string.find(pending, "\n", from, true)
		if not newline then
			break
		end
		if newline > from then
			table.insert(lines, string.sub(pending, from, newline - 1))
		end
		from = newline + 1
	end
	return lines, string.sub(pending, from)
end

-- The text of a tools/call response, or an error naming the tool.
function Mcp.toolText(tool: string, response: any): string
	if type(response) ~= "table" then
		error(`{tool}: malformed response`, 0)
	end
	if response.error then
		error(`{tool}: {response.error.message or "JSON-RPC error"}`, 0)
	end
	local result = response.result
	if type(result) ~= "table" or type(result.content) ~= "table" then
		error(`{tool}: response has no content`, 0)
	end
	local texts = {}
	for _, part in result.content do
		if type(part) == "table" and part.type == "text" and type(part.text) == "string" then
			table.insert(texts, part.text)
		end
	end
	local text = table.concat(texts, "\n")
	if result.isError then
		error(`{tool}: {text}`, 0)
	end
	return text
end

-- Spawns `program` as an MCP server and performs the initialise handshake.
function Mcp.connect(program: string, clientName: string): Client
	local process = require("@lune/process")
	local serde = require("@lune/serde")
	local task = require("@lune/task")

	local child = process.create(program, {})
	local responses: { [number]: any } = {}
	local exited = false
	local nextId = 0

	task.spawn(function()
		local pending = ""
		while true do
			local chunk = child.stdout:read(65536)
			if chunk == nil then
				break
			end
			local lines
			lines, pending = Mcp.lines(pending .. chunk)
			for _, line in lines do
				local ok, message = pcall(serde.decode, "json" :: "json", line)
				-- Only responses: a request from the server (roots/list, say) has
				-- a method, and its id is the server's, not one of ours.
				if ok and type(message) == "table" and type(message.id) == "number" and message.method == nil then
					responses[message.id] = message
				end
			end
		end
		exited = true
	end)
	-- The proxy logs to stderr; an unread pipe would fill and block it.
	task.spawn(function()
		repeat
			local chunk = child.stderr:read(65536)
		until chunk == nil
	end)

	local function send(message: { [string]: any })
		message.jsonrpc = "2.0"
		child.stdin:write(serde.encode("json", message) .. "\n")
	end

	local function request(method: string, params: { [string]: any }, timeoutSeconds: number): any
		nextId += 1
		local id = nextId
		send({ id = id, method = method, params = params })
		local deadline = os.clock() + timeoutSeconds
		while responses[id] == nil do
			if exited then
				error(`{method}: the MCP server exited`, 0)
			end
			if os.clock() > deadline then
				error(`{method}: no response within {timeoutSeconds} seconds`, 0)
			end
			task.wait(0.02)
		end
		local response = responses[id]
		responses[id] = nil
		return response
	end

	local ok, err = pcall(function()
		local hello = request("initialize", {
			protocolVersion = PROTOCOL_VERSION,
			capabilities = {},
			clientInfo = { name = clientName, version = "1" },
		}, 30)
		if hello.error then
			error(`initialize: {hello.error.message}`, 0)
		end
		send({ method = "notifications/initialized" })
	end)
	if not ok then
		child:kill() -- no client is returned, so nobody else could
		error(err, 0)
	end

	return {
		callTool = function(name, arguments)
			-- An empty Luau table would encode as a JSON array, not an object.
			local params: { [string]: any } = { name = name }
			if next(arguments) ~= nil then
				params.arguments = arguments
			end
			return Mcp.toolText(name, request("tools/call", params, TOOL_TIMEOUT))
		end,
		close = function()
			child:kill()
		end,
	}
end

return Mcp
