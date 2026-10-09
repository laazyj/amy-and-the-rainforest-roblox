--!strict
-- What a Release build leaves out. The publish job sets RELEASE_JOB=1, and
-- tools/lib/publish.luau then strips ServerScriptService.Dev (src/server/Dev:
-- the Dev shortcuts, plan section 5.3) from the place before uploading it,
-- so they are compiled out of Release. A place without the folder is
-- refused, so moving it without updating DEV_ONLY fails the release
-- instead of shipping the shortcuts.

local roblox = require("@lune/roblox") :: any

local Release = {}

-- The folder of ServerScriptService that holds everything Dev-only.
Release.DEV_ONLY = "Dev"

-- The place file `bytes` without the Dev-only folder.
function Release.strip(bytes: string): string
	local place = roblox.deserializePlace(bytes)
	local found = place:GetService("ServerScriptService"):FindFirstChild(Release.DEV_ONLY)
	if not found then
		error(`the place has no ServerScriptService.{Release.DEV_ONLY} to strip; is Release.DEV_ONLY out of date?`, 0)
	end
	found:Destroy()
	return roblox.serializePlace(place)
end

return Release
