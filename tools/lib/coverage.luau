--!strict
--[[
	Coverage guards (plan section 4): coverage enforced structurally, not by
	a percentage.

	- every module under src/core has a spec at the same path under
	  tests/lune/core (src/core/quests/talk.luau ->
	  tests/lune/core/quests/talk.spec.luau);
	- every Quest kind, Hook, World command and Player event the glossary
	  lists (not *later*) appears by name in at least one spec;
	- every Chapter of the Story has a Walkthrough spec,
	  tests/lune/content/walkthrough/<chapter id>.spec.luau, that walks it.

	Names count in a spec's code and strings, never its comments. These are
	structural checks: a spec that is trivial on purpose still passes them.

	And the rule for a pull request: one that changes src/core changes
	tests/ too, unless it carries the `no-test-change` label and its body
	says why on a line "No test change: <reason>".
]]

local Glossary = require("./glossary")
local Lex = require("./lex")

export type Input = {
	-- paths under src/core
	core: { string },
	-- path under tests/lune -> its text, for every spec
	specs: { [string]: string },
	-- the Story's Chapter ids ("chapter1", ...)
	chapters: { string },
	glossary: string,
}

local Coverage = {}

-- The glossary tables whose names must each appear in a spec.
Coverage.NAMED = { "Quest kinds", "Hook names", "World commands", "Player events" }

Coverage.LABEL = "no-test-change"

-- A spec's code and strings without its comments: its tokens joined by
-- spaces, each string quoted ('Chapter . walk ( "chapter1" )').
local function code(source: string): string
	local parts = {}
	for _, token in Lex.tokens(source) do
		table.insert(parts, if token.kind == "string" then `"{token.text}"` else token.value)
	end
	return table.concat(parts, " ")
end

function Coverage.check(input: Input): { string }
	local violations = {}
	local specs: { [string]: string } = {}
	for path, source in input.specs do
		specs[path] = code(source)
	end
	for _, module in input.core do
		local spec = `core/{string.gsub(module, "%.luau$", ".spec.luau")}`
		if not input.specs[spec] then
			table.insert(violations, `src/core/{module} has no spec: add tests/lune/{spec}`)
		end
	end

	local glossary = Glossary.parse(input.glossary)
	for _, heading in Coverage.NAMED do
		for _, entry in glossary.inUse(heading) do
			local pattern = `%f[%w_]{entry.name}%f[^%w_]`
			local named = false
			for _, text in specs do
				if string.find(text, pattern) then
					named = true
					break
				end
			end
			if not named then
				table.insert(violations, `{entry.id} ({heading}, docs/GLOSSARY.md) appears in no spec under tests/lune`)
			end
		end
	end

	for _, id in input.chapters do
		local spec = `content/walkthrough/{id}.spec.luau`
		local text = specs[spec]
		if not text or not string.find(text, `Chapter . walk ( "{id}" )`, 1, true) then
			table.insert(violations, `{id} has no Walkthrough: add tests/lune/{spec}, walking Chapter.walk("{id}")`)
		end
	end
	return violations
end

-- Why a pull request fails the test-change rule, or nil when it passes.
-- `changed` are the paths it changes, `labels` its label names.
function Coverage.testChange(changed: { string }, labels: { string }, body: string): string?
	local core, tests = false, false
	for _, path in changed do
		core = core or string.sub(path, 1, 9) == "src/core/"
		tests = tests or string.sub(path, 1, 6) == "tests/"
	end
	if not core or tests then
		return nil
	end
	local labelled = table.find(labels, Coverage.LABEL) ~= nil
	local because = string.find("\n" .. body, "\n[ \t]*[Nn]o test change:[^\n]*%S") ~= nil
	if labelled and because then
		return nil
	end
	local missing = {}
	if not labelled then
		table.insert(missing, `the label {Coverage.LABEL}`)
	end
	if not because then
		table.insert(missing, 'a line "No test change: <why>" in the PR body')
	end
	return `this PR changes src/core but nothing under tests/; add or change a test, or give it {table.concat(
		missing,
		" and "
	)}`
end

return Coverage
