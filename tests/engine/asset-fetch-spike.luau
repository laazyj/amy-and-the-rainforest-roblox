--!strict
-- TEMPORARY spike (brief mac-002, plan 5.5 path (a)): can a Luau Execution
-- task load a free Creator Store model and serialise it for CI to save as
-- .rbxm? Prints what happens and always passes; removed once the result is
-- written into the plan.

local MODEL = 12549617200 -- "Low Poly Tree" by Remadex Development, free

describe("asset fetch spike", function()
	it("reports what InsertService:LoadAsset does in a task", function()
		local ok, result = pcall(function()
			return game:GetService("InsertService"):LoadAsset(MODEL)
		end)
		print(`  LoadAsset({MODEL}): ok={ok} {if ok then result:GetFullName() else tostring(result)}`)
		if ok then
			local serialised, bytes = pcall(function()
				return game:GetService("SerializationService"):SerializeInstancesAsync(result:GetChildren())
			end)
			print(
				`  SerializeInstancesAsync: ok={serialised} {if serialised
					then buffer.len(bytes) .. " bytes"
					else tostring(bytes)}`
			)
		end
		expect(true).toBe(true)
	end)
end)

finish()
