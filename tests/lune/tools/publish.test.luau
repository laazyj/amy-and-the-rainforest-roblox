--!strict
local H = require("./_harness")
local OpenCloud = require("../../../tools/opencloud")
local Publish = require("../../../tools/lib/publish")

local function args(versionType: string, universe: string?, extra: { string }?): { string }
	local list =
		{ "--universe", universe or H.DEV, "--place", H.PLACE, "--file", "place.rbxl", "--version-type", versionType }
	for _, arg in (extra or {}) :: { string } do
		table.insert(list, arg)
	end
	return list
end

local function mock(options: {
	args: { string },
	env: { [string]: string }?,
	handler: ((OpenCloud.Request) -> OpenCloud.Response)?,
}): H.Mock
	return H.mock({
		args = options.args,
		env = options.env,
		files = { ["place.rbxl"] = "<roblox!binary>" },
		handler = options.handler or function()
			return H.response(200, '{"versionNumber":7}')
		end,
	})
end

print("publish")

for _, versionType in { "Saved", "Published" } do
	H.test(`{versionType}: builds the URL, headers and content type, prints the version`, function()
		local m = mock({ args = args(versionType) })
		H.passes(m, Publish.main)
		H.eq(#m.calls, 1, "requests")
		local request = m.calls[1]
		H.eq(request.method, "POST", "method")
		H.eq(
			request.url,
			`https://apis.roblox.com/universes/v1/{H.DEV}/places/{H.PLACE}/versions?versionType={versionType}`,
			"url"
		)
		H.eq(request.headers["x-api-key"], H.KEY, "api key header")
		H.eq(request.headers["content-type"], "application/octet-stream", "content type")
		H.eq(request.body, "<roblox!binary>", "body")
		H.eq(m.out[#m.out], "7", "stdout")
	end)
end

H.test("rejects an unknown version type", function()
	local m = mock({ args = args("Draft") })
	H.fails(m, Publish.main, "Saved or Published")
	H.eq(#m.calls, 0, "requests")
end)

H.test("refuses the Release universe without RELEASE_JOB, sending nothing", function()
	local m = mock({ args = args("Published", H.RELEASE) })
	H.fails(m, Publish.main, "refusing to target the Release universe")
	H.eq(#m.calls, 0, "requests")
end)

H.test("publishes to the Release universe with RELEASE_JOB=1", function()
	local m = mock({ args = args("Published", H.RELEASE), env = H.env({ RELEASE_JOB = "1" }) })
	H.passes(m, Publish.main)
	H.contains(m.calls[1].url, `/universes/v1/{H.RELEASE}/`, "url")
end)

H.test("dry run makes no request and prints the request it would make", function()
	local m = mock({ args = args("Saved", nil, { "--dry-run" }) })
	H.passes(m, Publish.main)
	H.eq(#m.calls, 0, "requests")
	H.contains(
		m:stderr(),
		`POST https://apis.roblox.com/universes/v1/{H.DEV}/places/{H.PLACE}/versions?versionType=Saved`
	)
	H.contains(m:stderr(), "x-api-key: <redacted>")
	H.notContains(m:stderr(), H.KEY, "dry run output")
end)

H.test("retries a transport error once", function()
	local attempts = 0
	local m = mock({
		args = args("Saved"),
		handler = function()
			attempts += 1
			if attempts == 1 then
				error("connection reset")
			end
			return H.response(200, '{"versionNumber":8}')
		end,
	})
	H.passes(m, Publish.main)
	H.eq(#m.calls, 2, "requests")
	H.eq(m.out[#m.out], "8", "stdout")
end)

H.test("gives up after a second transport error", function()
	local m = mock({
		args = args("Saved"),
		handler = function(): OpenCloud.Response
			error("connection reset")
		end,
	})
	H.fails(m, Publish.main, "failed after one retry")
	H.eq(#m.calls, 2, "requests")
end)

H.test("never retries a 5xx, as the publish may have been accepted", function()
	local m = mock({
		args = args("Saved"),
		handler = function()
			return H.response(502, "Bad gateway")
		end,
	})
	H.fails(m, Publish.main, "HTTP 502")
	H.eq(#m.calls, 1, "requests")
end)

local BUSY =
	'{"code":"Conflict","message":"Save failed. Server is busy and unable to process your upload request. Please try again in a couple minutes."}'

-- A publish against a server that answers `busyCount` busy 409s first.
local function busyServer(busyCount: number, body: string?)
	local waited = {}
	local m = H.mock({
		args = args("Published"),
		files = { ["place.rbxl"] = "<roblox!binary>" },
		handler = function()
			if busyCount > 0 then
				busyCount -= 1
				return H.response(409, body or BUSY)
			end
			return H.response(200, '{"versionNumber":9}')
		end,
		sleep = function(seconds)
			table.insert(waited, seconds)
		end,
	})
	return m, waited
end

H.test("retries Roblox's 'server busy' 409 with backoff", function()
	local m, waited = busyServer(2)
	H.passes(m, Publish.main)
	H.eq(#m.calls, 3, "requests")
	H.eq(table.concat(waited, ","), "30,60", "waits")
	H.eq(m.out[#m.out], "9", "stdout")
end)

H.test("does not retry a 409 with any other message", function()
	local m = busyServer(1, '{"code":"Conflict","message":"Place not part of the universe."}')
	H.fails(m, Publish.main, "HTTP 409")
	H.eq(#m.calls, 1, "requests")
end)

H.test("gives up on 'server busy' after the last backoff", function()
	local m, waited = busyServer(99)
	H.fails(m, Publish.main, "Server is busy")
	H.eq(#m.calls, #OpenCloud.BUSY_BACKOFF + 1, "requests")
	H.eq(table.concat(waited, ","), table.concat(OpenCloud.BUSY_BACKOFF, ","), "waits")
end)

H.test("never retries a 4xx", function()
	local m = mock({
		args = args("Saved"),
		handler = function()
			return H.response(409, "Place not part of the universe.")
		end,
	})
	H.fails(m, Publish.main, "HTTP 409")
	H.eq(#m.calls, 1, "requests")
end)

return nil
