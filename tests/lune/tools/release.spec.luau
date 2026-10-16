--[[
	The Release flag gates the Dev shortcuts (plan section 5.3, brief 007):
	a Dev build has them, and a publish by the release job (RELEASE_JOB=1)
	uploads the place without them; any other publish uploads it as built.
]]

local Built = require("../place/built")
local F = require("../fixtures/opencloud")
local Publish = require("../../../tools/lib/publish")
local Release = require("../../../tools/lib/release")
local roblox = require("@lune/roblox") :: any

-- What `publish` uploads for a place built from src/, with `env`.
local function uploaded(env: { [string]: string }): string
	local m = F.mock({
		args = { "--universe", F.DEV, "--place", F.PLACE, "--file", "place.rbxl", "--version-type", "Saved" },
		env = env,
		files = { ["place.rbxl"] = Built.bytes() },
		handler = function()
			return F.response(200, '{"versionNumber":7}')
		end,
	})
	Publish.main(m.ctx)
	return assert(m.calls[1].body, "publish sent no body")
end

local function devFolder(place: any): any
	return place:GetService("ServerScriptService"):FindFirstChild(Release.DEV_ONLY)
end

return function(t: any)
	local describe, it, expect, expectError = t.describe, t.it, t.expect, t.expectError

	describe("the Release flag", function()
		it("leaves the Dev shortcuts in a Dev build, in ServerScriptService.Dev", function()
			local dev = devFolder(Built.place())
			expect(dev and dev:FindFirstChild("DevShortcuts") ~= nil and dev:FindFirstChild("DevServer") ~= nil).toBe(
				true
			)
		end)

		it("publishes the place as built without RELEASE_JOB", function()
			expect(uploaded(F.env())).toBe(Built.bytes())
		end)

		it("strips the Dev shortcuts, and only them, when the release job publishes (RELEASE_JOB=1)", function()
			local stripped = roblox.deserializePlace(uploaded(F.env({ RELEASE_JOB = "1" })))
			expect(devFolder(stripped)).toBeNil()
			local built = Built.place()
			local removed = 1 + #devFolder(built):GetDescendants()
			expect(#stripped:GetDescendants()).toBe(#built:GetDescendants() - removed)
		end)

		it("refuses to strip a place that lacks a Dev-only module, rather than ship it unstripped", function()
			local place = Built.place()
			devFolder(place):Destroy()
			expectError(function()
				Release.strip(roblox.serializePlace(place))
			end, "no ServerScriptService.Dev to strip")
		end)
	end)
end
