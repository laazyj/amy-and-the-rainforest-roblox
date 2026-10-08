local F = require("../fixtures/opencloud")
local OpenCloud = require("../../../tools/opencloud")
local Toolchain = require("../../../tools/lib/toolchain")
local serde = require("@lune/serde")

local ROKIT = [[
# Toolchain pins
[tools]
rojo = "rojo-rbx/rojo@7.7.1"
lune = "lune-org/lune@0.10.5"
selene = "Kampfkarren/selene@0.32.0"
]]

local LUAURC = '{\n  "aliases": {\n    "lune": "~/.lune/.typedefs/0.10.5/"\n  }\n}\n'

local WALLY = [[
[package]
name = "laazyj/amy"
registry = "https://github.com/UpliftGames/wally-index"

[dependencies]
Promise = "evaera/promise@^4.0.0"

[server-dependencies]
ProfileStore = "lm-loleris/profilestore@1.0.3"
]]

-- A fake GitHub releases API and Wally registry with these latest versions.
local function server(latest: { [string]: string }): (OpenCloud.Request) -> OpenCloud.Response
	return function(request)
		local repo = string.match(request.url, "/repos/(.-)/releases/latest$")
		if repo then
			return F.response(200, serde.encode("json", { tag_name = latest[repo] }))
		end
		local package = string.match(request.url, "/v1/package%-metadata/(.+)$") :: string
		return F.response(200, serde.encode("json", { versions = { { package = { version = latest[package] } } } }))
	end
end

local function check(files: { [string]: string }, latest: { [string]: string })
	local m = F.mock({ args = {}, env = { GITHUB_TOKEN = "token-not-real" }, files = files, handler = server(latest) })
	local changed, updates = Toolchain.check(m.ctx)
	return changed, updates, m
end

local CURRENT = {
	["rojo-rbx/rojo"] = "v7.7.1",
	["lune-org/lune"] = "v0.10.5",
	["Kampfkarren/selene"] = "0.32.0",
}

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("toolchain-check", function()
		it("reads the pins under [tools] in rokit.toml", function()
			expect(Toolchain.parseRokit(ROKIT)).toEqual({
				{ name = "rojo", repo = "rojo-rbx/rojo", version = "7.7.1" },
				{ name = "lune", repo = "lune-org/lune", version = "0.10.5" },
				{ name = "selene", repo = "Kampfkarren/selene", version = "0.32.0" },
			})
		end)

		it("reads every Wally dependency section and ignores [package]", function()
			expect(Toolchain.parseWally(WALLY)).toEqual({
				{ name = "Promise", repo = "evaera/promise", version = "^4.0.0" },
				{ name = "ProfileStore", repo = "lm-loleris/profilestore", version = "1.0.3" },
			})
		end)

		it("reads the repository's own rokit.toml and wally.toml", function()
			local fs = require("@lune/fs")
			expect(#Toolchain.parseRokit(fs.readFile("rokit.toml"))).toBe(6)
			expect(#Toolchain.parseWally(fs.readFile("wally.toml"))).toBe(0)
		end)

		it("drops a leading v from release tags", function()
			expect(Toolchain.versionFromTag("v7.7.1")).toBe("7.7.1")
			expect(Toolchain.versionFromTag("0.32.0")).toBe("0.32.0")
		end)

		it("keeps a Wally requirement's operator when bumping it", function()
			expect(Toolchain.bumpRequirement("^4.0.0", "4.1.0")).toBe("^4.1.0")
			expect(Toolchain.bumpRequirement("1.0.3", "1.1.0")).toBe("1.1.0")
		end)

		it("changes nothing when every pin is current", function()
			local changed, updates, m = check({ ["rokit.toml"] = ROKIT, [".luaurc"] = LUAURC }, CURRENT)
			expect(next(changed)).toBeNil()
			expect(#updates).toBe(0)
			expect(#m.calls).toBe(3)
			expect(m.calls[1].url).toBe("https://api.github.com/repos/rojo-rbx/rojo/releases/latest")
			expect(m.calls[1].headers.authorization).toBe("Bearer token-not-real")
		end)

		it("rewrites only the pins that are behind", function()
			local latest = table.clone(CURRENT)
			latest["rojo-rbx/rojo"] = "v7.8.0"
			local changed, updates = check({ ["rokit.toml"] = ROKIT, [".luaurc"] = LUAURC }, latest)
			expect(updates).toEqual({ { name = "rojo", from = "7.7.1", to = "7.8.0" } })
			expect(changed["rokit.toml"]).toBe((string.gsub(ROKIT, "rojo@7%.7%.1", "rojo@7.8.0")))
			expect(changed[".luaurc"]).toBeNil()
		end)

		it("moves the .luaurc typedefs alias with the Lune pin", function()
			local latest = table.clone(CURRENT)
			latest["lune-org/lune"] = "v0.11.0"
			local changed = check({ ["rokit.toml"] = ROKIT, [".luaurc"] = LUAURC }, latest)
			expect(changed["rokit.toml"]).toContain('"lune-org/lune@0.11.0"')
			expect(changed[".luaurc"]).toContain('"~/.lune/.typedefs/0.11.0/"')
		end)

		it("bumps Wally dependencies against the registry", function()
			local latest = table.clone(CURRENT)
			latest["evaera/promise"] = "4.0.0"
			latest["lm-loleris/profilestore"] = "1.1.0"
			local changed, updates = check({ ["rokit.toml"] = ROKIT, ["wally.toml"] = WALLY }, latest)
			expect(updates).toEqual({ { name = "ProfileStore", from = "1.0.3", to = "1.1.0" } })
			expect(changed["wally.toml"]).toContain('"lm-loleris/profilestore@1.1.0"')
		end)

		it("fails on an API error rather than reporting the pins current", function()
			local m = F.mock({
				args = {},
				files = { ["rokit.toml"] = ROKIT },
				handler = function()
					return F.response(403, "rate limited")
				end,
			})
			t.expectError(function()
				Toolchain.check(m.ctx)
			end, "HTTP 403")
		end)

		it("lists the updates in the PR body", function()
			local body = Toolchain.summary({ { name = "rojo", from = "7.7.1", to = "7.8.0" } })
			expect(body).toContain("| rojo | 7.7.1 | 7.8.0 |")
		end)
	end)
end
