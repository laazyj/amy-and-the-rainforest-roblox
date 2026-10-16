--[[
	The place as tools/build.sh builds it, for specs that check the built
	file: built once per run with Rojo, as bytes and as a DataModel.
]]

local bootstrap = require("../bootstrap")
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any

local bytes: string? = nil

local Built = {}

function Built.bytes(): string
	if not bytes then
		local path = `{bootstrap.REPO_ROOT}/build/spec-place.rbxl`
		fs.writeDir(`{bootstrap.REPO_ROOT}/build`)
		local result = process.exec(
			"rojo",
			{ "build", "default.project.json", "-o", path },
			{ cwd = bootstrap.REPO_ROOT }
		)
		assert(result.ok, `rojo build failed: {result.stderr}`)
		bytes = fs.readFile(path)
		fs.removeFile(path)
	end
	return bytes :: string
end

function Built.place(): any
	return roblox.deserializePlace(Built.bytes())
end

return Built
