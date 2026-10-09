--!strict
--[[
	Tier 0 guards: the rules of plan sections 2.1, 2.4 and 4 as checks.

	  lune run tools/guard schema   every file under src/content against the
	                                content schema derived from docs/GLOSSARY.md

	Prints each violation and fails when there is any. Run from
	tools/check.sh; the logic is in tools/lib and tested in tier 1.
]]

local Cli = require("./lib/cli")
local Schema = require("./lib/schema")

local ROOT = assert(string.match(debug.info(1, "s"), "^(.*)[/\\]tools[/\\]"), "cannot locate the repo")

local GUARDS: { [string]: (Cli.Context) -> { string } } = {
	schema = function(ctx)
		local schema = Schema.fromGlossary((assert(ctx.readFile(`{ROOT}/docs/GLOSSARY.md`), "no docs/GLOSSARY.md")))
		local violations = {}
		for _, file in Schema.content() do
			local found = if file.ok
				then Schema.check(schema, file.path, file.value)
				else { `src/content/{file.path}: does not load under Lune: {file.value}` }
			table.move(found, 1, #found, #violations + 1, violations)
		end
		return violations
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
	local violations = guard(ctx)
	for _, violation in violations do
		ctx.log(violation)
	end
	if #violations > 0 then
		error(`{name}: {#violations} violation(s)`, 0)
	end
	ctx.out(`{name}: ok`)
end)
