--!strict
-- The repository's files, for the guards: where the repository is, and the
-- files under a directory (the .luau files, or those a filter accepts).

local fs = require("@lune/fs")

local Files = {}

Files.ROOT = assert(string.match(debug.info(1, "s"), "^(.*)[/\\]tools[/\\]"), "cannot locate the repo")

local function isLuau(path: string): boolean
	return string.match(path, "%.luau$") ~= nil
end

-- Every file under `dir` (relative to the repository) that `accept` takes
-- by its path, as a path relative to `dir`, sorted.
function Files.list(dir: string, accept: (path: string) -> boolean): { string }
	local found = {}
	local function walk(sub: string)
		local entries = fs.readDir(`{Files.ROOT}/{dir}/{sub}`)
		table.sort(entries)
		for _, entry in entries do
			local path = sub .. entry
			if fs.isDir(`{Files.ROOT}/{dir}/{path}`) then
				walk(path .. "/")
			elseif accept(path) then
				table.insert(found, path)
			end
		end
	end
	walk("")
	return found
end

-- Every .luau file under `dir`, as Files.list gives it.
function Files.luau(dir: string): { string }
	return Files.list(dir, isLuau)
end

-- The text of `path` (relative to the repository).
function Files.read(path: string): string
	return fs.readFile(`{Files.ROOT}/{path}`)
end

-- Runs `check(path, source)` over every .luau file under `trees`, or every
-- file `accept` takes, and returns everything it found, in order.
function Files.each(
	trees: { string },
	check: (path: string, source: string) -> { string },
	accept: ((path: string) -> boolean)?
): { string }
	local found = {}
	for _, tree in trees do
		for _, file in Files.list(tree, accept or isLuau) do
			local path = `{tree}/{file}`
			local results = check(path, Files.read(path))
			table.move(results, 1, #results, #found + 1, found)
		end
	end
	return found
end

return Files
