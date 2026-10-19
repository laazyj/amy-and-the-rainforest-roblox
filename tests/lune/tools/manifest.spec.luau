local Cli = require("../../../tools/lib/cli")
local F = require("../fixtures/opencloud")
local Manifest = require("../../../tools/lib/manifest")
local M = require("../fixtures/manifest")
local bootstrap = require("../bootstrap")

local PNG, HASH, UPLOADED, REMOVE, FONT = M.PNG, M.HASH, M.UPLOADED, M.REMOVE, M.FONT
local entry, manifest = M.entry, M.manifest

-- The PNG fixture, and any model as a few bytes.
local function readFile(path: string): string?
	return if path == M.PNG_PATH then PNG elseif string.match(path, "%.rbxm$") then "<roblox!" else nil
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

		it("accepts a font: an id with no file, never uploaded", function()
			expect(Manifest.validate(manifest(entry(FONT)), readFile)).toEqual({})
		end)

		-- Each: what makes a font entry invalid, and the problem reported.
		local NO_FILE, REFERENCED, NEEDS_ID =
			"a font has no path, sha256 or amy",
			'a font has upload false and moderation "approved"',
			"a font needs its Creator Store assetId"
		local fontCases: { { any } } = {
			{ "a path", { path = M.PNG_PATH }, NO_FILE },
			{ "a sha256", { sha256 = HASH }, NO_FILE },
			{ "an amy", { amy = "absent" }, NO_FILE },
			{ "upload true", { upload = true }, REFERENCED },
			{ "moderation pending", { moderation = "pending" }, REFERENCED },
			{ "no assetId", { assetId = REMOVE }, NEEDS_ID },
			{ "a content id for an assetId", { assetId = "rbxassetid://8764312106" }, NEEDS_ID },
		}
		for _, case in fontCases do
			local how: string, overrides: { [string]: any }, needle: string = case[1], case[2], case[3]
			it(`rejects a font with {how}`, function()
				local problems = Manifest.validate(manifest(entry(FONT, overrides)), readFile)
				expect(#problems).toBe(1)
				expect(problems[1]).toContain(needle)
			end)
		end

		it("accepts a library-audio track: an id with no file, never uploaded", function()
			expect(Manifest.validate(manifest(entry(M.LIBRARY_AUDIO)), readFile)).toEqual({})
		end)

		it("accepts a Catalog item: an id with no file, never uploaded, as a font", function()
			local item = entry(FONT, { name = "catalog:amy_hair", kind = "catalog" })
			expect(Manifest.validate(manifest(item), readFile)).toEqual({})
		end)

		it("accepts a Catalog item not picked yet: no id, pending, a placeholder", function()
			local slot = entry(FONT, {
				name = "catalog:amy_hair",
				kind = "catalog",
				assetId = REMOVE,
				moderation = "pending",
				placeholder = true,
			})
			expect(Manifest.validate(manifest(slot), readFile)).toEqual({})
			slot.placeholder = false
			expect(Manifest.validate(manifest(slot), readFile)).toEqual({
				'catalog:amy_hair: a Catalog item not picked yet has upload false, moderation "pending" and placeholder true',
			})
		end)

		it("accepts a paid Catalog item under the marketplace licence, and nothing else under it", function()
			local item = entry(FONT, { name = "catalog:amy_shirt", kind = "catalog", licence = "marketplace" })
			expect(Manifest.validate(manifest(item), readFile)).toEqual({})
			expect(Manifest.validate(manifest(entry(FONT, { licence = "marketplace" })), readFile)).toEqual({
				`{FONT.name}: only a Catalog item has the marketplace licence`,
			})
		end)

		it("holds a Catalog item to its name and a font's rules", function()
			local problems = Manifest.validate(
				manifest(entry(FONT, { name = "catalog:amy_hair", kind = "catalog", upload = true })),
				readFile
			)
			expect(problems).toEqual({
				'catalog:amy_hair: a Catalog item has upload false and moderation "approved"',
			})
			local misnamed = Manifest.validate(manifest(entry(FONT, { kind = "catalog" })), readFile)
			expect(misnamed[1]).toContain('a Catalog item is named catalog:<name> and has kind "catalog"')
		end)

		it("holds a library-audio track to a font's rules", function()
			local problems =
				Manifest.validate(manifest(entry(M.LIBRARY_AUDIO, { path = M.PNG_PATH, upload = true })), readFile)
			expect(problems).toEqual({
				"music:paradise: a library-audio track has no path, sha256 or amy: it is referenced, not uploaded",
				'music:paradise: a library-audio track has upload false and moderation "approved"',
			})
		end)

		-- Sam's Character model, as the Mac agent records it.
		local SAM = {
			name = "character:Sam",
			kind = "model",
			path = "assets/meshes/characters/Sam.rbxm",
			upload = false,
			amy = REMOVE,
			licence = "creator-store-free",
		}

		it("accepts a Character model in the place's folder of them, never uploaded", function()
			expect(Manifest.validate(manifest(entry(SAM)), readFile)).toEqual({})
		end)

		for _, case in
			{
				{ "named for another Character", { path = "assets/meshes/characters/Fox.rbxm" } },
				{ "outside the folder", { path = "assets/meshes/Sam.rbxm" } },
				{ "to upload", { upload = true } },
			} :: { { any } }
		do
			it(`rejects a Character model {case[1]}`, function()
				local problems = Manifest.validate(manifest(entry(SAM, case[2])), readFile)
				expect(problems).toEqual({
					'character:Sam: a Character model is kind "model" at assets/meshes/characters/Sam.rbxm with upload false: the place file holds it',
				})
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

		it("generates AssetIds for uploaded entries and fonts only, sorted", function()
			local m = manifest(
				entry({ name = "ui:leaf", assetId = "2", sha256 = HASH, moderation = "approved" }),
				entry(),
				entry(FONT),
				entry({ name = "card:end", assetId = "1", sha256 = HASH, moderation = "approved" })
			)
			local source = Manifest.generateAssetIds(m)
			expect(source).toContain(
				'\t["card:end"] = "rbxassetid://1",\n\t["font:dancing_script"] = "rbxassetid://8764312106",\n\t["ui:leaf"] = "rbxassetid://2",\n}'
			)
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

		-- Each way to write an asset id (the review of PR #26), the file it is
		-- in, and the problem tier 0 reports for it.
		local NOT_LITERAL = "must be written out as digits"
		local NOT_LISTED = "asset id 123456789 is not in assets/manifest.json"
		local CARD = "src/client/Card.luau"
		type Attempt = { how: string, line: string, problem: string, path: string? }
		local ATTEMPTS: { Attempt } = {
			{ how = "a concatenation", line = '"rbxassetid://" .. "123456789"', problem = NOT_LITERAL },
			{ how = "an interpolated string", line = "`rbxassetid://{123456789}`", problem = NOT_LITERAL },
			{ how = "a string.format", line = 'string.format("rbxassetid://%d", 123456789)', problem = NOT_LITERAL },
			{
				how = "a Content.fromAssetId call",
				line = "Content.fromAssetId(123456789)",
				problem = "Content.fromAssetId outside",
			},
			{ how = "the scheme in capitals", line = '"RBXASSETID://123456789"', problem = NOT_LISTED },
			{
				how = "asset?id= with no slash",
				line = '"http://www.roblox.com/asset?id=123456789"',
				problem = NOT_LISTED,
			},
			{
				how = "an asset delivery URL",
				line = '"https://assetdelivery.roblox.com/v1/asset/?id=123456789"',
				problem = NOT_LISTED,
			},
			{ how = "a thumbnail", line = '"rbxthumb://type=Asset&id=123456789&w=150&h=150"', problem = NOT_LISTED },
			{
				how = "a .model.json file",
				path = "src/shared/x/Card.model.json",
				line = '{"Properties":{"Image":"rbxassetid://123456789"}}',
				problem = NOT_LISTED,
			},
			{
				how = "a .lua file",
				path = "src/shared/Old.lua",
				line = 'return "rbxassetid://123456789"',
				problem = NOT_LISTED,
			},
			{
				how = "default.project.json",
				path = "default.project.json",
				line = '{"Image": "rbxassetid://123456789"}',
				problem = NOT_LISTED,
			},
		}
		for _, attempt in ATTEMPTS do
			local path = attempt.path or CARD
			it(`fails on an asset id in {attempt.how}`, function()
				local mock = repo(manifest(entry()), { [path] = attempt.line })
				local problems = Manifest.check(mock.ctx)
				expect(#problems).toBe(1)
				expect(problems[1]).toContain(`{path}:1: `)
				expect(problems[1]).toContain(attempt.problem)
			end)
		end

		it("lets AssetIds.luau build content ids with Content.fromAssetId", function()
			local m = manifest(entry())
			local source = Manifest.generateAssetIds(m) .. "-- Content.fromAssetId(id)\n"
			expect(Manifest.scanSources(m, { [Manifest.ASSET_IDS_PATH] = source })).toEqual({})
		end)

		it("fails when AssetIds.luau was edited by hand", function()
			local mock = repo(manifest(entry()), { [Manifest.ASSET_IDS_PATH] = "return {}" })
			expect(Manifest.check(mock.ctx)[1]).toContain("does not match assets/manifest.json")
		end)

		it("writes AssetIds.luau from the manifest first when asked, for an id typed in", function()
			local mock =
				repo(manifest(entry(UPLOADED), entry(M.LIBRARY_AUDIO)), { [Manifest.ASSET_IDS_PATH] = "return {}" })
			expect(Manifest.check(mock.ctx, true)).toEqual({})
			expect(mock.files[Manifest.ASSET_IDS_PATH]).toContain('["music:paradise"] = "rbxassetid://1234567890"')
		end)

		it("fails on an invalid manifest before scanning", function()
			local mock = repo(manifest(entry({ licence = "?" })))
			expect(Manifest.check(mock.ctx)[1]).toContain("licence must be one of")
		end)

		it("passes a font, which has no file to read", function()
			local mock = repo(manifest(entry(UPLOADED), entry(FONT)))
			expect(Manifest.check(mock.ctx)).toEqual({})
			expect(mock:stderr()).never.toContain("font:dancing_script")
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
