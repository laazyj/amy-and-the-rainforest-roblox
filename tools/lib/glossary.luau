--!strict
--[[
	Reads the tables of docs/GLOSSARY.md: the enumerations of section 4 that
	the content schema is derived from, and the Player events and World
	commands of section 3. Each row whose first cell is a backticked id is an
	entry; every cell is kept by its column header. A row marked *later* is
	a reserved name: it is an entry, flagged `later`, and `inUse` and
	`names` leave it out, so tier 0 rejects it in content until the mark is
	removed.
]]

export type Entry = {
	-- as written ("beat:sam_catches") and without its prefix ("sam_catches")
	id: string,
	name: string,
	later: boolean,
	-- column header -> the cell's text, trimmed
	cells: { [string]: string },
}

export type Glossary = {
	-- the rows of the table under the `### <heading>` heading
	entries: (heading: string) -> { Entry },
	-- those rows not marked *later*
	inUse: (heading: string) -> { Entry },
	-- the names of the rows in use, as a set
	names: (heading: string) -> { [string]: boolean },
	values: (cell: string?) -> { string },
}

local Glossary = {}

local function cells(row: string): { string }
	local list = {}
	for cell in string.gmatch((string.match(row, "^|(.*|)%s*$") or ""), "([^|]*)|") do
		table.insert(list, (string.gsub(cell, "^%s*(.-)%s*$", "%1")))
	end
	return list
end

-- An id without its prefix: "spot:Farm" -> "Farm"; "Narrator" as it is.
function Glossary.name(id: string): string
	return string.match(id, "^%a+:(.+)$") or id
end

-- The backticked values in a cell, in order ("`a`, `b`" -> { "a", "b" }).
function Glossary.values(cell: string?): { string }
	local values = {}
	for value in string.gmatch(cell or "", "`([^`]+)`") do
		table.insert(values, value)
	end
	return values
end

function Glossary.parse(text: string): Glossary
	local parsed: { [string]: { Entry } } = {}

	local function entries(heading: string): { Entry }
		if parsed[heading] then
			return parsed[heading]
		end
		local section = string.match(text, `\n### {heading}\n(.-)\n#`)
		if not section then
			error(`no "{heading}" section in the glossary`, 2)
		end
		local headers: { string }?
		local found = {}
		for row in string.gmatch(section, "\n(|[^\n]*)") do
			local list = cells(row)
			local id = string.match(list[1] or "", "^`([^`]+)`")
			if not headers then
				headers = list
			elseif id then
				local entry: Entry = {
					id = id,
					name = Glossary.name(id),
					later = string.find(list[1], "*later*", 1, true) ~= nil,
					cells = {},
				}
				for i, cell in list do
					entry.cells[(headers :: { string })[i] or tostring(i)] = cell
				end
				table.insert(found, entry)
			end
		end
		parsed[heading] = found
		return found
	end

	local function inUse(heading: string): { Entry }
		local found = {}
		for _, entry in entries(heading) do
			if not entry.later then
				table.insert(found, entry)
			end
		end
		return found
	end

	local function names(heading: string): { [string]: boolean }
		local set = {}
		for _, entry in inUse(heading) do
			set[entry.name] = true
		end
		return set
	end

	return { entries = entries, inUse = inUse, names = names, values = Glossary.values }
end

return Glossary
