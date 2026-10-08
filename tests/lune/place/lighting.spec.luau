--[[
	Lighting.Technology is place-level: only default.project.json can set it,
	and engine tests cannot check it, because Luau Execution scripts lack the
	capability to read it. So this spec builds the place with Rojo and reads the
	property back from the built file, which is what Studio and players load.
]]

local bootstrap = require("../bootstrap")
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any

local function buildPlace(): any
	local path = `{bootstrap.REPO_ROOT}/build/lighting-spec.rbxl`
	fs.writeDir(`{bootstrap.REPO_ROOT}/build`)
	local result = process.exec("rojo", { "build", "default.project.json", "-o", path }, { cwd = bootstrap.REPO_ROOT })
	assert(result.ok, `rojo build failed: {result.stderr}`)
	local ok, place = pcall(function()
		return roblox.deserializePlace(fs.readFile(path))
	end)
	fs.removeFile(path)
	assert(ok, place)
	return place
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("built place", function()
		it("uses the ShadowMap lighting technology set in default.project.json", function()
			local lighting = buildPlace():GetService("Lighting")
			expect(lighting.Technology).toBe(roblox.Enum.Technology.ShadowMap)
		end)
	end)
end
