--[[
	The mutation check (tools/lib/mutate.luau, run nightly by
	tools/mutate.luau): faults applied by exact edits, the failing tests
	read from the runner's output, and the report. That every canned fault
	still applies to the tree is checked in tier 0 (`tools/guard faults`).
]]

local Mutate = require("../../../tools/lib/mutate")

local FAULT: Mutate.Fault = {
	name = "say goodbye",
	file = "x.luau",
	edits = { { from = "hello", to = "goodbye" } },
}

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("Mutate.apply", function()
		it("applies each edit in order", function()
			expect(Mutate.apply("say hello", FAULT)).toBe("say goodbye")
		end)

		it("raises when an edit no longer matches, or matches more than once", function()
			t.expectError(function()
				Mutate.apply("say hi", FAULT)
			end, 'edit 1 of "say goodbye" no longer matches x.luau')
			t.expectError(function()
				Mutate.apply("hello hello", FAULT)
			end, 'edit 1 of "say goodbye" matches x.luau more than once')
		end)

		it("swaps two texts through a placeholder", function()
			local swapped = { name = "swap", file = "x.luau", edits = Mutate.swap("one", "two") }
			expect(Mutate.apply("one, two", swapped)).toBe("two, one")
		end)
	end)

	describe("the canned faults", function()
		it("are a dozen, each with a name", function()
			expect(#Mutate.FAULTS).toBe(12)
			for _, fault in Mutate.FAULTS do
				expect(fault.name ~= "").toBe(true)
			end
		end)

		it("are stale when an edit no longer matches its file", function()
			local stale: Mutate.Fault = { name = "stale", file = "x.luau", edits = { { from = "nope", to = "" } } }
			expect(Mutate.stale({ FAULT, stale }, function()
				return "say hello"
			end)).toEqual({ 'tools/lib/mutate.luau: edit 1 of "stale" no longer matches x.luau' })
		end)
	end)

	describe("Mutate.failures", function()
		it("reads the failing tests from the runner's output, with their spec", function()
			local output = table.concat({
				"core/Beat.spec.luau",
				"  ✓ plays a Beat",
				"content/Story.spec.luau",
				"  ✗ the Story from a fresh start reaches the Ending",
				"      expected false to be true",
				"  ✗ failed to load: boom",
				"",
				"1 passed, 2 failed, 2 spec files",
			}, "\n")
			expect(Mutate.failures(output)).toEqual({
				"content/Story.spec.luau: the Story from a fresh start reaches the Ending",
				"content/Story.spec.luau: failed to load: boom",
			})
		end)
	end)

	describe("Mutate.run", function()
		local function runner(files: { [string]: string }, failing: string)
			return {
				read = function(path)
					return files[path]
				end,
				write = function(path, text)
					files[path] = text
				end,
				test = function()
					local caught = string.find(files["x.luau"], failing, 1, true) ~= nil
					return not caught, if caught then "a.spec.luau\n  ✗ catches it" else "1 passed"
				end,
				log = function() end,
			}
		end

		it("names the tests that caught each fault, and restores the file", function()
			local files = { ["x.luau"] = "say hello" }
			local results = Mutate.run({ FAULT }, runner(files, "goodbye"))
			expect(results[1].caught).toEqual({ "a.spec.luau: catches it" })
			expect(Mutate.survivors(results)).toEqual({})
			expect(files["x.luau"]).toBe("say hello")
		end)

		it("records a run that fails without naming a test as an error", function()
			local results = Mutate.run({ FAULT }, {
				read = function()
					return "say hello"
				end,
				write = function() end,
				test = function()
					return false, "boom"
				end,
				log = function() end,
			})
			expect(results[1].error).toBe("tier 1 failed without naming a test:\nboom")
			expect(#Mutate.survivors(results)).toBe(1)
		end)

		it("counts a fault that leaves the suite green, or no longer applies, as a survivor", function()
			local stale: Mutate.Fault = { name = "stale", file = "x.luau", edits = { { from = "nope", to = "" } } }
			local results = Mutate.run({ FAULT, stale }, runner({ ["x.luau"] = "say hello" }, "never"))
			expect(#Mutate.survivors(results)).toBe(2)
			local report = Mutate.report(results)
			expect(report).toContain("0 of 2 faults caught by tier 1.")
			expect(report).toContain("| say goodbye | `x.luau` | **survived**: no test failed |")
			expect(report).toContain('**not applied**: edit 1 of "stale" no longer matches x.luau')
		end)
	end)

	describe("Mutate.report", function()
		it("shows the first three tests that caught a fault, and how many more", function()
			local report = Mutate.report({
				{ fault = FAULT, caught = { "a: 1", "a: 2", "a: 3", "a: 4", "a: 5" } },
			})
			expect(report).toContain("1 of 1 faults caught by tier 1.")
			expect(report).toContain("| say goodbye | `x.luau` | a: 1<br>a: 2<br>a: 3<br>and 2 more |")
		end)
	end)
end
