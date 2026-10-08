--[[
	Test bootstrap: loads src/ modules that use Roblox datatypes as globals.

	Lune has no Vector3 or Color3 globals, so a module such as StoryData
	cannot be required directly. loadSource runs the file with those
	datatypes injected from @lune/roblox and returns what it returns.
	See the comment at the top of runner.luau.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
-- Lune's type definitions leave out the datatype constructors, which do exist at runtime.
local roblox = require("@lune/roblox") :: any

local REPO_ROOT = assert(string.match(debug.info(1, "s"), "^(.*)[/\\]tests[/\\]lune[/\\]"), "cannot locate the repo")

-- Only datatypes, listed one by one: src modules that need Instances or
-- services are engine-tested, so those must stay unavailable here.
local ROBLOX_GLOBALS = {
	Vector3 = roblox.Vector3,
	Color3 = roblox.Color3,
}

local bootstrap = {}

bootstrap.REPO_ROOT = REPO_ROOT

-- Paths are relative to the repository root.
function bootstrap.readSource(path: string): string
	return fs.readFile(`{REPO_ROOT}/{path}`)
end

function bootstrap.loadSource(path: string): any
	local chunk = luau.load(bootstrap.readSource(path), {
		debugName = path,
		environment = ROBLOX_GLOBALS,
	})
	return chunk()
end

return bootstrap
