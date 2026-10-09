--[[
	Reads the enumeration tables of docs/GLOSSARY.md (section 4). Each row's
	first cell is a backticked id; every cell is kept by its column header.
]]

local bootstrap = require("../bootstrap")

local GLOSSARY = bootstrap.readSource("docs/GLOSSARY.md")

local glossary = {}

export type Entry = {
	-- as written ("beat:sam_catches") and without its prefix ("sam_catches")
	id: string,
	name: string,
	-- column header -> the cell's text, trimmed
	cells: { [string]: string },
}

local function cells(row: string): { string }
	local list = {}
	for cell in string.gmatch((string.match(row, "^|(.*|)%s*$") or ""), "([^|]*)|") do
		table.insert(list, (string.gsub(cell, "^%s*(.-)%s*$", "%1")))
	end
	return list
end

-- The rows of the table under the `### <heading>` heading.
function glossary.entries(heading: string): { Entry }
	local section = assert(string.match(GLOSSARY, `\n### {heading}\n(.-)\n#`), `no {heading} section in the glossary`)
	local headers: { string }?
	local entries = {}
	for row in string.gmatch(section, "\n(|[^\n]*)") do
		local id = string.match(row, "^|%s*`([^`]+)`")
		if not headers then
			headers = cells(row)
		elseif id then
			local entry: Entry = { id = id, name = string.match(id, "^%a+:(.+)$") or id, cells = {} }
			for i, cell in cells(row) do
				entry.cells[(headers :: { string })[i] or tostring(i)] = cell
			end
			table.insert(entries, entry)
		end
	end
	return entries
end

-- The names of a table's ids, as a set.
function glossary.names(heading: string): { [string]: boolean }
	local names = {}
	for _, entry in glossary.entries(heading) do
		names[entry.name] = true
	end
	return names
end

-- The backticked values in a cell, in order ("`a`, `b`" -> { "a", "b" }).
function glossary.values(cell: string?): { string }
	local values = {}
	for value in string.gmatch(cell or "", "`([^`]+)`") do
		table.insert(values, value)
	end
	return values
end

return glossary
