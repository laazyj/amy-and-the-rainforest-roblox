--!strict
-- The repository's files, for the guards: where the repository is, and the
-- .luau files under a directory.

local fs = require("@lune/fs")

local Files = {}

Files.ROOT = assert(string.match(debug.info(1, "s"), "^(.*)[/\\]tools[/\\]"), "cannot locate the repo")

-- Every .luau file under `dir` (relative to the repository), as a path
-- relative to `dir`, sorted.
function Files.luau(dir: string): { string }
	local found = {}
	local function walk(sub: string)
		local entries = fs.readDir(`{Files.ROOT}/{dir}/{sub}`)
		table.sort(entries)
		for _, entry in entries do
			local path = sub .. entry
			if fs.isDir(`{Files.ROOT}/{dir}/{path}`) then
				walk(path .. "/")
			elseif string.match(entry, "%.luau$") then
				table.insert(found, path)
			end
		end
	end
	walk("")
	return found
end

-- The text of `path` (relative to the repository).
function Files.read(path: string): string
	return fs.readFile(`{Files.ROOT}/{path}`)
end

-- Runs `check(path, source)` over every .luau file under `trees`, and
-- returns everything it found, in order.
function Files.each(trees: { string }, check: (path: string, source: string) -> { string }): { string }
	local found = {}
	for _, tree in trees do
		for _, file in Files.luau(tree) do
			local path = `{tree}/{file}`
			local results = check(path, Files.read(path))
			table.move(results, 1, #results, #found + 1, found)
		end
	end
	return found
end

return Files
