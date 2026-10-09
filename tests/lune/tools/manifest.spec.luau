local Cli = require("../../../tools/lib/cli")
local F = require("../fixtures/opencloud")
local Manifest = require("../../../tools/lib/manifest")
local M = require("../fixtures/manifest")
local bootstrap = require("../bootstrap")

local PNG, HASH, UPLOADED, REMOVE = M.PNG, M.HASH, M.UPLOADED, M.REMOVE
local entry, manifest = M.entry, M.manifest

local function readFile(path: string): string?
	return if path == M.PNG_PATH then PNG else nil
end

-- A repository with this manifest, its generated AssetIds, and `files`.
local function repo(m: Manifest.Manifest, files: { [string]: string }?): F.Mock
	local all = M.files(m, { ["src/client/Card.luau"] = "local x = 1" })
	for path, text in (files or {}) :: { [string]: string } do
		all[path] = text
	end
	return F.mock({ args = {}, files = all })
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("asset manifest", function()
		it("accepts a pending entry and an uploaded one", function()
			expect(Manifest.validate(manifest(entry()), readFile)).toEqual({})
			expect(Manifest.validate(manifest(entry(UPLOADED)), readFile)).toEqual({})
		end)

		-- Each: the fields that make an entry invalid, and the problem reported.
		local cases: { { any } } = {
			{ { name = "chapter2" }, "name must be <prefix>:<name>" },
			{ { name = "npc:Sam" }, "name must be <prefix>:<name>" },
			{ { kind = "texture" }, "kind must be one of audio, image, model" },
			{ { kind = "audio" }, "takes no audio file named" },
			{ { path = "assets/images/missing.png" }, "file not found" },
			{ { path = "assets/../secrets.png" }, "path must be a file under assets/" },
			{ { amy = "front" }, "no image shows Amy's face" },
			{ { amy = REMOVE }, "no image shows Amy's face" },
			{ { licence = "found-online" }, "licence must be one of" },
			{ { licence = "cc-by" }, "needs an attribution" },
			{ { creator = " " }, "creator and origin are required" },
			{ { assetId = "4242" }, "an uploaded entry's moderation is" },
			{ { assetId = "4242", moderation = "approved" }, "records the sha256" },
			{ { assetId = "rbxassetid://4242" }, "assetId must be a string of digits" },
			{ { moderation = "approved" }, "an entry with no assetId is pending" },
			{
				{ upload = false, assetId = "1", sha256 = HASH, moderation = "approved" },
				"upload false has no assetId",
			},
			{ { colour = "red" }, 'unknown field "colour"' },
		}
		for _, case in cases do
			local overrides: { [string]: any }, needle: string = case[1], case[2]
			it(`rejects an entry: {needle}`, function()
				local problems = Manifest.validate(manifest(entry(overrides)), readFile)
				expect(#problems).toBe(1)
				expect(problems[1]).toContain(needle)
			end)
		end

		it("rejects a name listed twice", function()
			local problems = Manifest.validate(manifest(entry(), entry()), readFile)
			expect(problems).toEqual({ "card:chapter2: is listed twice" })
		end)

		it("rejects a file that is not a manifest", function()
			expect(Manifest.validate({ assets = {} }, readFile)[1]).toContain('"version": 1')
		end)

		it("round-trips through encode and decode, keeping null assetIds", function()
			local m = manifest(entry(), entry({ name = "card:chapter3", assetId = "7", sha256 = HASH }))
			local text = Manifest.encode(m)
			expect(text).toContain('"assetId": null')
			expect(Manifest.decode(text)).toEqual(m)
			expect(Manifest.encode(Manifest.decode(text))).toBe(text)
		end)

		it("is pending until uploaded, and again when the file changes", function()
			expect(Manifest.isPending(entry(), HASH)).toBe(true)
			expect(Manifest.isPending(entry(UPLOADED), HASH)).toBe(false)
			expect(Manifest.isPending(entry(UPLOADED), Manifest.hash("a new drawing"))).toBe(true)
			expect(Manifest.isPending(entry({ upload = false }), HASH)).toBe(false)
		end)

		it("generates AssetIds for uploaded entries only, sorted", function()
			local m = manifest(
				entry({ name = "ui:leaf", assetId = "2", sha256 = HASH, moderation = "approved" }),
				entry(),
				entry({ name = "card:end", assetId = "1", sha256 = HASH, moderation = "approved" })
			)
			local source = Manifest.generateAssetIds(m)
			expect(source).toContain('\t["card:end"] = "rbxassetid://1",\n\t["ui:leaf"] = "rbxassetid://2",\n}')
			expect(source).never.toContain("card:chapter2")
			expect(source).toContain("return table.freeze(AssetIds)")
		end)
	end)

	describe("tier 0 asset check", function()
		it("passes a repository whose ids are all in the manifest", function()
			local m = manifest(entry(UPLOADED))
			local mock = repo(m, { ["src/client/Card.luau"] = 'image.Image = "rbxassetid://4242"' })
			expect(Manifest.check(mock.ctx)).toEqual({})
		end)

		it("fails on an rbxassetid:// in src/ that is not in the manifest, naming file and line", function()
			local mock = repo(manifest(entry()), {
				["src/content/scenes/Field.luau"] = 'local a = 1\nlocal decal = "rbxassetid://99"',
				["src/server/Old.luau"] = 'local s = "http://www.roblox.com/asset/?id=77"',
			})
			expect(Manifest.check(mock.ctx)).toEqual({
				"src/content/scenes/Field.luau:2: asset id 99 is not in assets/manifest.json",
				"src/server/Old.luau:1: asset id 77 is not in assets/manifest.json",
			})
		end)

		it("fails when AssetIds.luau was edited by hand", function()
			local mock = repo(manifest(entry()), { [Manifest.ASSET_IDS_PATH] = "return {}" })
			expect(Manifest.check(mock.ctx)[1]).toContain("does not match assets/manifest.json")
		end)

		it("fails on an invalid manifest before scanning", function()
			local mock = repo(manifest(entry({ licence = "?" })))
			expect(Manifest.check(mock.ctx)[1]).toContain("licence must be one of")
		end)

		it("notes each entry waiting for upload", function()
			local mock = repo(manifest(entry()))
			expect(Manifest.check(mock.ctx)).toEqual({})
			expect(mock:stderr()).toContain("note: card:chapter2 is waiting for upload")
		end)

		it("passes on this repository", function()
			-- The live filesystem tools/check-assets reads, rooted at the repository.
			local live = Cli.liveContext()
			local ctx = F.mock({ args = {} }).ctx
			ctx.readFile = function(path)
				return live.readFile(`{bootstrap.REPO_ROOT}/{path}`)
			end
			ctx.listDir = function(path)
				return live.listDir(`{bootstrap.REPO_ROOT}/{path}`)
			end
			expect(Manifest.check(ctx)).toEqual({})
		end)
	end)
end
