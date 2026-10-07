--!strict
local H = require("./_harness")
local OpenCloud = require("../../../tools/opencloud")
local Publish = require("../../../tools/lib/publish")

local function args(versionType: string, universe: string?, extra: { string }?): { string }
	local list =
		{ "--universe", universe or H.DEV, "--place", H.PLACE, "--file", "place.rbxl", "--version-type", versionType }
	for _, arg in extra or {} do
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
