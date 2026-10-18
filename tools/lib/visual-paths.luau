--!strict
--[[
	The paths whose change alters what is on screen (brief mac-003, Must
	A4). A pull request that changes one gets CI's prompt: "This pull
	request changes what is on screen. The owner's `needs-playtest` label
	brings screenshots here." (ci.yml, the screen-prompt job; the paths
	come from tools/visual-paths.luau, which reads CHANGED_FILES as
	tools/guard test-change does.)

	A path ending in "/" is a directory and everything under it; any other
	is one file.
]]

local VisualPaths = {}

VisualPaths.PATHS = table.freeze({
	"src/client/",
	"src/core/ScreenLayout.luau",
	"src/content/palette.luau",
	"src/content/title.luau",
	"src/content/hints.luau",
	"docs/design/feel.md",
	"assets/images/",
})

local function visual(path: string): boolean
	for _, each in VisualPaths.PATHS do
		if path == each or (string.sub(each, -1) == "/" and string.sub(path, 1, #each) == each) then
			return true
		end
	end
	return false
end

-- The changed paths that alter what is on screen, in the order given.
function VisualPaths.matches(changed: { string }): { string }
	local found = {}
	for _, path in changed do
		if visual(path) then
			table.insert(found, path)
		end
	end
	return found
end

return VisualPaths
