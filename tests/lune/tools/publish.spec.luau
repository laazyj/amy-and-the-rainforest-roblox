local F = require("../fixtures/opencloud")
local Release = require("../../../tools/lib/release")
local roblox = require("@lune/roblox") :: any
local OpenCloud = require("../../../tools/opencloud")
local Publish = require("../../../tools/lib/publish")

local function args(versionType: string, universe: string?, extra: { string }?): { string }
	local list =
		{ "--universe", universe or F.DEV, "--place", F.PLACE, "--file", "place.rbxl", "--version-type", versionType }
	for _, arg in (extra or {}) :: { string } do
		table.insert(list, arg)
	end
	return list
end

local function mock(options: {
	args: { string },
	env: { [string]: string }?,
	handler: ((OpenCloud.Request) -> OpenCloud.Response)?,
	place: string?,
}): F.Mock
	return F.mock({
		args = options.args,
		env = options.env,
		files = { ["place.rbxl"] = options.place or "<roblox!binary>" },
		handler = options.handler or function()
			return F.response(200, '{"versionNumber":7}')
		end,
	})
end

local BUSY =
	'{"code":"Conflict","message":"Save failed. Server is busy and unable to process your upload request. Please try again in a couple minutes."}'

-- A publish against a server that answers `busyCount` busy 409s first.
local function busyServer(busyCount: number, body: string?): (F.Mock, { number })
	local waited = {}
	local m = F.mock({
		args = args("Published"),
		files = { ["place.rbxl"] = "<roblox!binary>" },
		handler = function()
			if busyCount > 0 then
				busyCount -= 1
				return F.response(409, body or BUSY)
			end
			return F.response(200, '{"versionNumber":9}')
		end,
		sleep = function(seconds)
			table.insert(waited, seconds)
		end,
	})
	return m, waited
end

return function(t: any)
	local describe, it, expect, expectError = t.describe, t.it, t.expect, t.expectError

	describe("publish", function()
		for _, versionType in { "Saved", "Published" } do
			it(`{versionType}: builds the URL, headers and content type, prints the version`, function()
				local m = mock({ args = args(versionType) })
				Publish.main(m.ctx)
				expect(#m.calls).toBe(1)
				local request = m.calls[1]
				expect(request.method).toBe("POST")
				expect(request.url).toBe(
					`https://apis.roblox.com/universes/v1/{F.DEV}/places/{F.PLACE}/versions?versionType={versionType}`
				)
				expect(request.headers["x-api-key"]).toBe(F.KEY)
				expect(request.headers["content-type"]).toBe("application/octet-stream")
				expect(request.body).toBe("<roblox!binary>")
				expect(m.out[#m.out]).toBe("7")
			end)
		end

		it("rejects an unknown version type", function()
			local m = mock({ args = args("Draft") })
			expectError(function()
				Publish.main(m.ctx)
			end, "Saved or Published")
			expect(#m.calls).toBe(0)
		end)

		it("refuses the Release universe without RELEASE_JOB, sending nothing", function()
			local m = mock({ args = args("Published", F.RELEASE) })
			expectError(function()
				Publish.main(m.ctx)
			end, "refusing to target the Release universe")
			expect(#m.calls).toBe(0)
		end)

		it("publishes to the Release universe with RELEASE_JOB=1", function()
			-- the release job strips the Dev shortcuts, so it needs a place that
			-- has them (tests/lune/tools/release.spec.luau checks the real one)
			local place = roblox.Instance.new("DataModel")
			local dev = roblox.Instance.new("Folder")
			dev.Name = Release.DEV_ONLY
			dev.Parent = place:GetService("ServerScriptService")
			local m = mock({
				args = args("Published", F.RELEASE),
				env = F.env({ RELEASE_JOB = "1" }),
				place = roblox.serializePlace(place),
			})
			Publish.main(m.ctx)
			expect(m.calls[1].url).toContain(`/universes/v1/{F.RELEASE}/`)
		end)

		it("dry run makes no request and prints the request it would make", function()
			local m = mock({ args = args("Saved", nil, { "--dry-run" }) })
			Publish.main(m.ctx)
			expect(#m.calls).toBe(0)
			expect(m:stderr()).toContain(
				`POST https://apis.roblox.com/universes/v1/{F.DEV}/places/{F.PLACE}/versions?versionType=Saved`
			)
			expect(m:stderr()).toContain("x-api-key: <redacted>")
			expect(m:stderr()).never.toContain(F.KEY)
		end)

		it("retries a transport error once", function()
			local attempts = 0
			local m = mock({
				args = args("Saved"),
				handler = function()
					attempts += 1
					if attempts == 1 then
						error("connection reset")
					end
					return F.response(200, '{"versionNumber":8}')
				end,
			})
			Publish.main(m.ctx)
			expect(#m.calls).toBe(2)
			expect(m.out[#m.out]).toBe("8")
		end)

		it("gives up after a second transport error", function()
			local m = mock({
				args = args("Saved"),
				handler = function(): OpenCloud.Response
					error("connection reset")
				end,
			})
			expectError(function()
				Publish.main(m.ctx)
			end, "failed after one retry")
			expect(#m.calls).toBe(2)
		end)

		it("never retries a 5xx, as the publish may have been accepted", function()
			local m = mock({
				args = args("Saved"),
				handler = function()
					return F.response(502, "Bad gateway")
				end,
			})
			expectError(function()
				Publish.main(m.ctx)
			end, "HTTP 502")
			expect(#m.calls).toBe(1)
		end)

		it("retries Roblox's 'server busy' 409 with backoff", function()
			local m, waited = busyServer(2)
			Publish.main(m.ctx)
			expect(#m.calls).toBe(3)
			expect(waited).toEqual({ 30, 60 })
			expect(m.out[#m.out]).toBe("9")
		end)

		it("does not retry a 409 with any other message", function()
			local m = busyServer(1, '{"code":"Conflict","message":"Place not part of the universe."}')
			expectError(function()
				Publish.main(m.ctx)
			end, "HTTP 409")
			expect(#m.calls).toBe(1)
		end)

		it("gives up on 'server busy' after the last backoff", function()
			local m, waited = busyServer(99)
			expectError(function()
				Publish.main(m.ctx)
			end, "Server is busy")
			expect(#m.calls).toBe(#OpenCloud.BUSY_BACKOFF + 1)
			expect(waited).toEqual(OpenCloud.BUSY_BACKOFF)
		end)

		it("never retries a 4xx", function()
			local m = mock({
				args = args("Saved"),
				handler = function()
					return F.response(409, "Place not part of the universe.")
				end,
			})
			expectError(function()
				Publish.main(m.ctx)
			end, "HTTP 409")
			expect(#m.calls).toBe(1)
		end)
	end)
end
