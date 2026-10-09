--!strict
--[[
	Tier 0 guards: the rules of plan sections 2.1, 2.4 and 4 as checks.

	  lune run tools/guard schema   every file under src/content against the
	                                content schema derived from docs/GLOSSARY.md
	  lune run tools/guard purity   src/core and src/content touch no engine
	                                global and require only each other
	  lune run tools/guard links    no http:// or https:// in the text of
	                                content, the core or the client binder

	Prints each violation and fails when there is any. Run from
	tools/check.sh; the logic is in tools/lib and tested in tier 1.
]]

local Cli = require("./lib/cli")
local Files = require("./lib/files")
local Purity = require("./lib/purity")
local Schema = require("./lib/schema")

local GUARDS: { [string]: () -> { string } } = {
	schema = function()
		local schema = Schema.fromGlossary(Files.read("docs/GLOSSARY.md"))
		local violations = {}
		for _, file in Schema.content() do
			local found = if file.ok
				then Schema.check(schema, file.path, file.value)
				else { `src/content/{file.path}: does not load under Lune: {file.value}` }
			table.move(found, 1, #found, #violations + 1, violations)
		end
		return violations
	end,
	purity = function()
		return Files.each(Purity.PURE, Purity.check)
	end,
	links = function()
		return Files.each(Purity.LINKED, Purity.links)
	end,
}

Cli.main(function(ctx)
	local name = ctx.args[1]
	local guard = name and GUARDS[name]
	if not guard then
		local names = {}
		for known in GUARDS do
			table.insert(names, known)
		end
		table.sort(names)
		error(`usage: lune run tools/guard <{table.concat(names, "|")}>`, 0)
	end
	local violations = guard()
	for _, violation in violations do
		ctx.log(violation)
	end
	if #violations > 0 then
		error(`{name}: {#violations} violation(s)`, 0)
	end
	ctx.out(`{name}: ok`)
end)
