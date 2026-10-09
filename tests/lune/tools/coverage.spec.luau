--[[
	The coverage guards (tools/lib/coverage.luau), run by `tools/guard
	coverage` in tier 0, and the test-change rule that
	.github/workflows/test-change.yml runs on every PR.
]]

local Coverage = require("../../../tools/lib/coverage")

local GLOSSARY = [[
## 3. The verbs

### Player events

| Event | Payload | Sent when |
|---|---|---|
| `EnteredZone` | `zone` | The Player Character enters a Zone |
| `FoundCollectible` *later* | `collectible` | later |

### World commands

| Command | Arguments | Does |
|---|---|---|
| `SetLighting` | `preset` | Applies a Lighting preset |

### Quest kinds

| Kind | Completed when |
|---|---|
| `reach` | `EnteredZone(zone)` |

### Hook names

| Hook | Runs when |
|---|---|
| `onStart` | The Quest becomes active |

## 5.
]]

local function input(): Coverage.Input
	return {
		core = { "Beat.luau", "quests/reach.luau" },
		specs = {
			["core/Beat.spec.luau"] = 'it("plays a Beat at onStart: SetLighting")',
			["core/quests/reach.spec.luau"] = 'it("completes a reach Quest on EnteredZone")',
			["content/walkthrough/chapter1.spec.luau"] = 'local walk = Chapter.walk("chapter1")',
		},
		chapters = { "chapter1" },
		glossary = GLOSSARY,
	}
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("the coverage guards", function()
		it("pass when every core module has a spec, every name is used and every Chapter walked", function()
			expect(Coverage.check(input())).toEqual({})
		end)

		it("fail on a core module with no spec at the same path", function()
			local given = input()
			given.specs["core/quests/reach.spec.luau"] = nil
			given.specs["core/reach.spec.luau"] = 'it("reach on EnteredZone")'
			expect(Coverage.check(given)).toEqual({
				"src/core/quests/reach.luau has no spec: add tests/lune/core/quests/reach.spec.luau",
			})
		end)

		it("fail on a Quest kind, Hook, World command or Player event no spec names, as a whole word", function()
			local given = input()
			given.specs["core/Beat.spec.luau"] = 'it("plays a Beat at onStartup: SetLightingPreset")'
			expect(Coverage.check(given)).toEqual({
				"onStart (Hook names, docs/GLOSSARY.md) appears in no spec under tests/lune",
				"SetLighting (World commands, docs/GLOSSARY.md) appears in no spec under tests/lune",
			})
		end)

		it("leave *later* names out", function()
			expect(table.concat(Coverage.check(input()), "\n")).never.toContain("FoundCollectible")
		end)

		it("fail on a Chapter with no Walkthrough spec walking it", function()
			local given = input()
			table.insert(given.chapters, "chapter2")
			given.specs["content/walkthrough/chapter2.spec.luau"] = 'local walk = Chapter.walk("chapter1")'
			expect(Coverage.check(given)).toEqual({
				'chapter2 has no Walkthrough: add tests/lune/content/walkthrough/chapter2.spec.luau, walking Chapter.walk("chapter2")',
			})
		end)
	end)

	describe("the test-change rule", function()
		local FAILS = "this PR changes src/core but nothing under tests/"

		it("passes a PR that does not change src/core, or changes tests/ too", function()
			expect(Coverage.testChange({ "src/content/chapters/1/data.luau" }, {}, "")).toBeNil()
			expect(Coverage.testChange({ "src/core/Beat.luau", "tests/lune/core/Beat.spec.luau" }, {}, "")).toBeNil()
		end)

		it("fails a PR that changes src/core and not tests/, naming what is missing", function()
			expect(Coverage.testChange({ "src/core/Beat.luau", "docs/GLOSSARY.md" }, {}, "")).toBe(
				`{FAILS}; add or change a test, or give it the label no-test-change and a line "No test change: <why>" in the PR body`
			)
		end)

		it("fails with the label but no reason, or a reason but no label", function()
			expect(Coverage.testChange({ "src/core/Beat.luau" }, { "no-test-change" }, "No test change:   ")).toBe(
				`{FAILS}; add or change a test, or give it a line "No test change: <why>" in the PR body`
			)
			expect(Coverage.testChange({ "src/core/Beat.luau" }, { "bug" }, "No test change: a comment")).toBe(
				`{FAILS}; add or change a test, or give it the label no-test-change`
			)
		end)

		it("passes with the label and a line in the body saying why", function()
			local body = "## What changed\n\nA comment in Beat.\n\nNo test change: only a comment changes\n"
			expect(Coverage.testChange({ "src/core/Beat.luau" }, { "no-test-change" }, body)).toBeNil()
		end)
	end)
end
