local F = require("../fixtures/opencloud")
local M = require("../fixtures/manifest")
local Manifest = require("../../../tools/lib/manifest")
local OpenCloud = require("../../../tools/opencloud")
local UploadAssets = require("../../../tools/lib/upload-assets")
local bootstrap = require("../bootstrap")
local serde = require("@lune/serde")

local CREATOR = "5005"
local ASSETS_URL = "https://apis.roblox.com/assets/v1/assets"

local LEAF_PATH = "assets/images/leaf.png"
local LEAF = "\137PNG leaf"

-- Two images to upload and one reference that is never uploaded.
local function startingManifest(): Manifest.Manifest
	return M.manifest(
		M.entry(),
		M.entry({ name = "ui:leaf", path = LEAF_PATH, amy = "absent" }),
		M.entry({ name = "ref:sam", upload = false, amy = "absent" })
	)
end

local function args(extra: { string }?, universe: string?): { string }
	local list = { "--universe", universe or F.DEV, "--place", F.PLACE, "--creator-user", CREATOR }
	for _, arg in (extra or {}) :: { string } do
		table.insert(list, arg)
	end
	return list
end

-- Roblox's Assets API: each upload is operation `op<n>`, done on its first
-- poll, giving asset `900<n>` in review; a get of an asset says `moderation`.
type ServerOptions = { moderation: string?, failOperation: number? }

local function server(options: ServerOptions?)
	local opts: ServerOptions = options or {}
	local uploads = 0
	return function(request: OpenCloud.Request): OpenCloud.Response
		if request.method == "POST" and request.url == ASSETS_URL then
			uploads += 1
			return F.response(200, `\{"path":"operations/op{uploads}","done":false}`)
		end
		local op = string.match(request.url, "/assets/v1/operations/op(%d+)$")
		if request.method == "GET" and op then
			if tonumber(op) == opts.failOperation then
				return F.response(
					200,
					`\{"path":"operations/op{op}","done":true,"error":\{"code":3,"message":"Rejected"}}`
				)
			end
			return F.response(
				200,
				`\{"path":"operations/op{op}","done":true,"response":\{"assetId":"900{op}","moderationResult":\{"moderationState":"MODERATION_STATE_REVIEWING"}}}`
			)
		end
		if
			request.method == "GET" and string.match(request.url, "/assets/v1/assets/%d+%?readMask=moderationResult$")
		then
			return F.response(200, `\{"moderationResult":\{"moderationState":"{opts.moderation or "Reviewing"}"}}`)
		end
		error(`unexpected request: {request.method} {request.url}`)
	end
end

local function repo(options: {
	args: { string }?,
	manifest: Manifest.Manifest?,
	env: { [string]: string }?,
	handler: ((OpenCloud.Request) -> OpenCloud.Response)?,
	files: { [string]: string }?,
}): F.Mock
	local m = options.manifest or startingManifest()
	local files = options.files or M.files(m, { [LEAF_PATH] = LEAF })
	return F.mock({
		args = options.args or args(),
		env = options.env,
		files = files,
		handler = options.handler or server(),
	})
end

local function uploads(mock: F.Mock): { OpenCloud.Request }
	local list = {}
	for _, request in mock.calls do
		if request.method == "POST" then
			table.insert(list, request)
		end
	end
	return list
end

local function written(mock: F.Mock): Manifest.Manifest
	return Manifest.decode(mock.files[Manifest.PATH])
end

return function(t: any)
	local describe, it, expect, expectError = t.describe, t.it, t.expect, t.expectError

	describe("upload-assets", function()
		it("uploads each pending image as a multipart Create Asset request", function()
			local mock = repo({})
			UploadAssets.main(mock.ctx)
			local sent = uploads(mock)
			expect(#sent).toBe(2)
			local request = sent[1]
			expect(request.url).toBe(ASSETS_URL)
			expect(request.headers["x-api-key"]).toBe(F.KEY)
			local boundary = string.match(request.headers["content-type"], "^multipart/form%-data; boundary=(.+)$")
			expect(boundary).never.toBeNil()
			local body = request.body :: string
			expect(body).toContain(`--{boundary}\r\nContent-Disposition: form-data; name="request"\r\n`)
			expect(body).toContain(
				`Content-Disposition: form-data; name="fileContent"; filename="card-chapter2.png"\r\nContent-Type: image/png\r\n\r\n{M.PNG}\r\n--{boundary}--\r\n`
			)
			local json = string.match(body, "Content%-Type: application/json\r\n\r\n(.-)\r\n")
			expect(serde.decode("json", json :: string)).toEqual({
				assetType = "Image",
				displayName = "Amy and the Rain Forest card:chapter2",
				description = "card:chapter2, for the game Amy and the Rain Forest.",
				creationContext = { creator = { userId = CREATOR } },
			})
		end)

		it("polls each operation, writes the ids back and regenerates AssetIds", function()
			local mock = repo({})
			UploadAssets.main(mock.ctx)
			expect(mock.calls[2].url).toBe("https://apis.roblox.com/assets/v1/operations/op1")
			local m = written(mock)
			expect(m.assets[1].assetId).toBe("9001")
			expect(m.assets[1].sha256).toBe(M.HASH)
			expect(m.assets[1].moderation).toBe("reviewing")
			expect(m.assets[2].assetId).toBe("9002")
			expect(m.assets[3].assetId).toBeNil()
			expect(mock.files[Manifest.ASSET_IDS_PATH]).toBe(Manifest.generateAssetIds(m))
			expect(mock.files[Manifest.ASSET_IDS_PATH]).toContain('["card:chapter2"] = "rbxassetid://9001"')
			expect(mock:stdout()).toBe(
				"- uploaded `card:chapter2` (assets/images/card-chapter2.png) as 9001: reviewing\n"
					.. "- uploaded `ui:leaf` (assets/images/leaf.png) as 9002: reviewing"
			)
			-- What it wrote passes the tier 0 check.
			mock.files["src/client/Card.luau"] = 'local image = "rbxassetid://9001"'
			expect(Manifest.check(mock.ctx)).toEqual({})
		end)

		it("is idempotent: a second run uploads nothing", function()
			local first = repo({})
			UploadAssets.main(first.ctx)
			local second = repo({ files = first.files })
			UploadAssets.main(second.ctx)
			expect(#uploads(second)).toBe(0)
			expect(second.files[Manifest.PATH]).toBe(first.files[Manifest.PATH])
		end)

		it("uploads a changed file again, as a new asset", function()
			local m = M.manifest(M.entry(M.UPLOADED, { moderation = "approved" }))
			local mock = repo({ manifest = m })
			mock.files[M.PNG_PATH] = "\137PNG Clara's new drawing"
			UploadAssets.main(mock.ctx)
			expect(#uploads(mock)).toBe(1)
			expect(written(mock).assets[1].assetId).toBe("9001")
			expect(mock:stdout()).toContain("as 9001, replacing 4242: reviewing")
		end)

		it("dry run lists every pending upload and sends and writes nothing", function()
			local mock = repo({ args = args({ "--dry-run" }) })
			local before = mock.files[Manifest.PATH]
			UploadAssets.main(mock.ctx)
			expect(#mock.calls).toBe(0)
			expect(mock.files[Manifest.PATH]).toBe(before)
			local log = mock:stderr()
			expect(log).toContain("2 pending upload(s)")
			expect(log).toContain("would upload card:chapter2 (assets/images/card-chapter2.png)")
			expect(log).toContain("would upload ui:leaf (assets/images/leaf.png)")
			expect(log).never.toContain("ref:sam")
			expect(log).toContain(`POST {ASSETS_URL}`)
			expect(log).toContain("x-api-key: <redacted>")
			expect(log).never.toContain(F.KEY)
		end)

		it("refuses the Release universe without RELEASE_JOB, sending nothing, even in a dry run", function()
			for _, extra in { {}, { "--dry-run" } } do
				local mock = repo({ args = args(extra, F.RELEASE) })
				expectError(function()
					UploadAssets.main(mock.ctx)
				end, "refusing to target the Release universe")
				expect(#mock.calls).toBe(0)
			end
		end)

		it("refuses a real run when the Release guard is not armed", function()
			local mock = repo({ env = { ROBLOX_DEV_API_KEY = F.KEY } })
			expectError(function()
				UploadAssets.main(mock.ctx)
			end, "RELEASE_UNIVERSE_ID is not set")
			expect(#mock.calls).toBe(0)
		end)

		it("needs the creator's user id", function()
			local mock = repo({ args = { "--universe", F.DEV, "--place", F.PLACE } })
			expectError(function()
				UploadAssets.main(mock.ctx)
			end, "--creator-user is required")
		end)

		it("refuses an invalid manifest before sending anything", function()
			local mock = repo({ manifest = M.manifest(M.entry({ amy = "front" })) })
			expectError(function()
				UploadAssets.main(mock.ctx)
			end, "no image shows Amy's face")
			expect(#mock.calls).toBe(0)
		end)

		it("fails on a failed operation, keeping the ids it already got", function()
			local mock = repo({ handler = server({ failOperation = 2 }) })
			local err = expectError(function()
				UploadAssets.main(mock.ctx)
			end, "operations/op2 failed: 3 Rejected")
			expect(err).never.toContain(F.KEY)
			local m = written(mock)
			expect(m.assets[1].assetId).toBe("9001")
			expect(m.assets[2].assetId).toBeNil()
		end)

		it("gives up on an operation that is never done", function()
			local mock = repo({
				handler = function()
					return F.response(200, '{"path":"operations/slow","done":false}')
				end,
			})
			expectError(function()
				UploadAssets.main(mock.ctx)
			end, `not done after {UploadAssets.MAX_POLLS} polls`)
			expect(#mock.calls).toBe(UploadAssets.MAX_POLLS + 1)
		end)

		it("never retries a Create Asset that failed with a 5xx", function()
			local mock = repo({
				handler = function()
					return F.response(503, "unavailable")
				end,
			})
			expectError(function()
				UploadAssets.main(mock.ctx)
			end, "HTTP 503")
			expect(#mock.calls).toBe(1)
		end)

		it("never retries a Create Asset that failed with a transport error", function()
			local mock = repo({
				handler = function(): OpenCloud.Response
					error("connection reset")
				end,
			})
			expectError(function()
				UploadAssets.main(mock.ctx)
			end, "failed, not retried (transport error")
			expect(#mock.calls).toBe(1)
			expect(written(mock).assets[1].assetId).toBeNil()
		end)

		it("retries a poll that failed with a transport error once", function()
			local polls = 0
			local upstream = server()
			local mock = repo({
				handler = function(request)
					if request.method == "GET" then
						polls += 1
						if polls == 1 then
							error("connection reset")
						end
					end
					return upstream(request)
				end,
			})
			UploadAssets.main(mock.ctx)
			expect(written(mock).assets[1].assetId).toBe("9001")
		end)

		it("updates the moderation status of assets in review", function()
			local m = M.manifest(M.entry(M.UPLOADED))
			local mock = repo({ manifest = m, handler = server({ moderation = "Approved" }) })
			UploadAssets.main(mock.ctx)
			expect(#uploads(mock)).toBe(0)
			expect(mock.calls[1].url).toBe("https://apis.roblox.com/assets/v1/assets/4242?readMask=moderationResult")
			expect(written(mock).assets[1].moderation).toBe("approved")
			expect(mock:stdout()).toBe("- `card:chapter2` (4242) is now approved")
		end)

		it("builds no Open Cloud URL itself: no tool but tools/opencloud.luau names apis.roblox.com", function()
			local fs = require("@lune/fs")
			for _, dir in { "tools", "tools/lib" } do
				for _, name in fs.readDir(`{bootstrap.REPO_ROOT}/{dir}`) do
					local path = `{dir}/{name}`
					if string.match(name, "%.luau$") and path ~= "tools/opencloud.luau" then
						expect(string.find(bootstrap.readSource(path), "apis.roblox.com", 1, true)).toBeNil()
					end
				end
			end
		end)
	end)

	describe("Open Cloud assets", function()
		it("reads an operation's asset id as a number or a string", function()
			local operation = OpenCloud.parseOperation(
				F.response(200, '{"path":"operations/a-1","done":true,"response":{"assetId":12345678901}}')
			)
			expect(operation.assetId).toBe("12345678901")
		end)

		it("refuses an operation path it would not build a URL from", function()
			expectError(function()
				OpenCloud.parseOperation(F.response(200, '{"path":"../universes/1","done":false}'))
			end, "unexpected operation path")
		end)

		it("refuses a file the Assets API would refuse", function()
			expectError(function()
				OpenCloud.createAssetRequest(F.KEY, {
					kind = "image",
					displayName = "x",
					description = "x",
					creatorUserId = CREATOR,
					fileName = "card.gif",
					file = "GIF89a",
				})
			end, "takes no image file named card.gif")
		end)
	end)
end
