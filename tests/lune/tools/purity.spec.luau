--[[
	The source guards (tools/lib/purity.luau over tools/lib/lex.luau), run by
	`tools/guard purity` and `tools/guard links` in tier 0: the pure core and
	content touch no engine global and require only each other, and no text
	holds a link. Comments never count.
]]

local Files = require("../../../tools/lib/files")
local Lex = require("../../../tools/lib/lex")
local Purity = require("../../../tools/lib/purity")

-- The values of `source`'s tokens of `kind`, names with their line.
local function tokens(source: string, kind: string): { string }
	local found = {}
	for _, token in Lex.tokens(source) do
		if token.kind == kind then
			table.insert(found, if kind == "name" then `{token.value}@{token.line}` else token.value)
		end
	end
	return found
end

local function strings(source: string): { string }
	return tokens(source, "string")
end

local function names(source: string): { string }
	return tokens(source, "name")
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("the lexer", function()
		it("drops line and block comments, and counts their lines", function()
			expect(names("-- game\n--[[ game\n]] a --[==[ ]] game ]==] b\nc")).toEqual({ "a@3", "b@3", "c@4" })
		end)

		it("reads quoted, long and interpolated strings as strings", function()
			expect(strings([=[local s = "a\"b" .. 'c' .. [==[d]]e]==] ]=])).toEqual({ 'a\\"b', "c", "d]]e" })
			expect(strings("local s = `one {x} two`")).toEqual({ "one ", " two" })
		end)

		it("lexes the code inside an interpolation, nested braces too", function()
			expect(names("local s = `a {game:GetService({ x = 1 }).y} b`")).toEqual({
				"local@1",
				"s@1",
				"game@1",
				"GetService@1",
				"x@1",
				"y@1",
			})
		end)

		it("keeps counting lines after an escaped newline in any string", function()
			expect(names('local a = "x\\\ny" b `p\\\nq` c')).toEqual({ "local@1", "a@1", "b@2", "c@3" })
		end)

		it("skips numbers, exponents included", function()
			expect(names("local n = 1e-5 + 0x1F + .5 + 2.5")).toEqual({ "local@1", "n@1" })
		end)
	end)

	describe("the purity lint", function()
		local function check(source: string, path: string?): { string }
			return Purity.check(path or "src/core/Thing.luau", source)
		end

		it("fails on game, workspace, Instance, script and GetService", function()
			expect(check("local a = game\nlocal b = Instance.new('Part')\nlocal c = script.Parent")).toEqual({
				"src/core/Thing.luau:1: references game; the pure core and content never touch the engine",
				"src/core/Thing.luau:2: references Instance; the pure core and content never touch the engine",
				"src/core/Thing.luau:3: references script; the pure core and content never touch the engine",
			})
			expect(check("local w = workspace\nlocal s = x:GetService('Players')")).toEqual({
				"src/core/Thing.luau:1: references workspace; the pure core and content never touch the engine",
				"src/core/Thing.luau:2: references GetService; the pure core and content never touch the engine",
			})
		end)

		it("fails on getfenv, setfenv, _G, shared, loadstring and rawget, where an engine global can hide", function()
			local source = table.concat({
				"local a = (getfenv(0) :: any).workspace",
				'local b = (getfenv() :: any)["ga" .. "me"]',
				"local c = _G.game",
				"setfenv(1, {})",
				"local d = shared.Story",
				'local e = loadstring("return game")',
				'local f = rawget(_G, "game")',
			}, "\n")
			local why = "the pure core and content never reach the global environment"
			expect(check(source)).toEqual({
				`src/core/Thing.luau:1: references getfenv; {why}`,
				`src/core/Thing.luau:2: references getfenv; {why}`,
				`src/core/Thing.luau:3: references _G; {why}`,
				`src/core/Thing.luau:4: references setfenv; {why}`,
				`src/core/Thing.luau:5: references shared; {why}`,
				`src/core/Thing.luau:6: references loadstring; {why}`,
				`src/core/Thing.luau:7: references rawget; {why}`,
				`src/core/Thing.luau:7: references _G; {why}`,
			})
		end)

		it("fails on a require outside src/core and src/content, or of anything but a string path", function()
			expect(check('local a = require("../server/StoryHost")')).toEqual({
				'src/core/Thing.luau:1: requires "../server/StoryHost", outside src/core and src/content',
			})
			expect(check('local fs = require("@lune/fs")')).toEqual({
				'src/core/Thing.luau:1: requires "@lune/fs", outside src/core and src/content',
			})
			expect(check('local a = require("../../../../etc")', "src/content/chapters/1/data.luau")).toEqual({
				'src/content/chapters/1/data.luau:1: requires "../../../../etc", outside src/core and src/content',
			})
			expect(check("local a = require(path)")).toEqual({
				"src/core/Thing.luau:1: requires something other than a string path",
			})
		end)

		it("passes a require of the core or content, in either call form", function()
			expect(check('local a = require("./Events")\nlocal b = require "./quests/talk"')).toEqual({})
			expect(check('local a = require("../../../core/Story")', "src/content/chapters/1/data.luau")).toEqual({})
		end)

		it("fails on an engine datatype in content, and allows it in the core", function()
			local source = "local p = Vector3.new(1, 2, 3)\nlocal c = Color3.fromRGB(1, 2, 3)"
			expect(check(source, "src/content/scenes/Garden.luau")).toEqual({
				"src/content/scenes/Garden.luau:1: references Vector3; content stores positions and colours as plain tables",
				"src/content/scenes/Garden.luau:2: references Color3; content stores positions and colours as plain tables",
			})
			expect(check(source)).toEqual({})
		end)

		it("ignores comments, strings and fields of the same names", function()
			expect(check('-- game:GetService\nlocal s = "script" .. story.game .. x.Instance')).toEqual({})
		end)

		it("passes src/core and src/content as they are", function()
			expect(Files.each(Purity.PURE, Purity.check)).toEqual({})
		end)
	end)

	describe("the no-external-links check", function()
		it("fails on http:// or https:// in any string, interpolated ones included", function()
			local source = 'local a = "see https://example.com"\nlocal b = `go to HTTP://x/{y}`'
			expect(Purity.links("src/client/StoryClient.client.luau", source)).toEqual({
				"src/client/StoryClient.client.luau:1: a link in text (see https://example.com); the game links to nothing",
				"src/client/StoryClient.client.luau:2: a link in text (go to HTTP://x/); the game links to nothing",
			})
		end)

		it("ignores links in comments, and asset ids", function()
			expect(Purity.links("src/core/Thing.luau", '-- https://example.com\nlocal a = "rbxassetid://1"')).toEqual({})
		end)

		it("passes content, the core and the client binder as they are", function()
			expect(Files.each(Purity.LINKED, Purity.links)).toEqual({})
		end)
	end)
end
