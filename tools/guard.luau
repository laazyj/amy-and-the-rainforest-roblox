--!strict
--[[
	Tier 0 guards: the rules of plan sections 2.1, 2.4 and 4 as checks.

	  lune run tools/guard schema   every file under src/content against the
	                                content schema derived from docs/GLOSSARY.md
	  lune run tools/guard purity   src/core and src/content touch no engine
	                                global and require only each other
	  lune run tools/guard links    no http:// or https:// in the text of
	                                content, the core or the client binder
	  lune run tools/guard coverage a spec per core module, every glossary
	                                name tests must use in a spec, and a
	                                Walkthrough spec per Chapter
	  lune run tools/guard test-change
	                                a PR changing src/core changes tests/
	                                (CHANGED_FILES, PR_LABELS as JSON,
	                                PR_BODY; .github/workflows/test-change.yml)

	Prints each violation and fails when there is any. Run from
	tools/check.sh; the logic is in tools/lib and tested in tier 1.
]]

local Cli = require("./lib/cli")
local Coverage = require("./lib/coverage")
local Files = require("./lib/files")
local Purity = require("./lib/purity")
local Schema = require("./lib/schema")
local Story = require("../src/content/Story")

local serde = require("@lune/serde")

local GUARDS: { [string]: (Cli.Context) -> { string } } = {
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
	coverage = function()
		local specs = {}
		for _, path in Files.luau("tests/lune") do
			if string.match(path, "%.spec%.luau$") then
				specs[path] = Files.read(`tests/lune/{path}`)
			end
		end
		local chapters = {}
		for _, chapter in Story.story.chapters do
			table.insert(chapters, chapter.id)
		end
		return Coverage.check({
			core = Files.luau("src/core"),
			specs = specs,
			chapters = chapters,
			glossary = Files.read("docs/GLOSSARY.md"),
		})
	end,
	["test-change"] = function(ctx)
		local changed = string.split(ctx.env.CHANGED_FILES or "", "\n")
		local labels = serde.decode("json", ctx.env.PR_LABELS or "[]")
		local failure = Coverage.testChange(changed, labels, ctx.env.PR_BODY or "")
		return if failure then { failure } else {}
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
