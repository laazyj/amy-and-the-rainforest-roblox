--[[
	Test bootstrap: where the repository is, and reading its files as text
	(docs, fixtures, and sources a spec checks without running them).
	See the comment at the top of runner.luau.
]]

local fs = require("@lune/fs")

local REPO_ROOT = assert(string.match(debug.info(1, "s"), "^(.*)[/\\]tests[/\\]lune[/\\]"), "cannot locate the repo")

local bootstrap = {}

bootstrap.REPO_ROOT = REPO_ROOT

-- Paths are relative to the repository root.
function bootstrap.readSource(path: string): string
	return fs.readFile(`{REPO_ROOT}/{path}`)
end

return bootstrap
