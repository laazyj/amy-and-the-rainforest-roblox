-- The runner's own matchers, where using them in a spec proves too little:
-- toBeCloseTo's failing cases, whose message names the value and the tolerance.

return function(t: any)
	local describe, it, expect, expectError = t.describe, t.it, t.expect, t.expectError

	describe("expect().toBeCloseTo", function()
		it("passes a number an ulp away, as a computed angle is on another platform", function()
			expect(0.7853981633974482).toBeCloseTo(0.7853981633974483)
		end)

		it("fails beyond 1e-9 unless given a wider tolerance, naming the tolerance", function()
			expect(1).toBeCloseTo(1 + 1e-8, 1e-6)
			expectError(function()
				expect(1).toBeCloseTo(1 + 1e-8)
			end, "expected 1 to be within 1e-09 of 1.00000001")
			expectError(function()
				expect(1).toBeCloseTo(2, 0.5)
			end, "to be within 0.5 of 2")
		end)

		it("never passes a value that is not a number, nor NaN", function()
			expectError(function()
				expect("1").toBeCloseTo(1)
			end, 'expected "1" to be within')
			expectError(function()
				expect(0 / 0).toBeCloseTo(0 / 0)
			end, "to be within")
		end)
	end)
end
