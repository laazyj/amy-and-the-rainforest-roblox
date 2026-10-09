--!strict
-- Budgets (plan section 4: "Budgets are tests, measured where they can
-- be"). With the world built as the place's Scripts build it (_world.luau),
-- the instance count, the part count and the mean server Heartbeat time
-- over a 5-second sample (the worst frame is printed, not gated: one slow
-- frame on a shared server is noise) must stay within budget: the value
-- MEASURED when the budget was set, plus 20% HEADROOM. A change that needs more raises
-- MEASURED in its own PR, with the new measurement, rather than slipping
-- past.
--
-- Triangle counts come from the mesh manifest, and arrive with it (brief
-- 009). Client frame time and texture memory are tier 3's.

local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local HEADROOM = 1.2
local SAMPLE_SECONDS = 5

-- Provisional: replaced by the values the first engine-tests run measures.
local MEASURED = {
	instances = 20000,
	parts = 10000,
	heartbeatMs = 40,
}

include("tests/engine/_world.luau").build(true)
local descendants = Workspace:GetDescendants()

-- Reports `value` against its budget, then holds it to the budget.
local function within(name: string, value: number)
	local budget = math.ceil(MEASURED[name] * HEADROOM)
	print(string.format("  %-12s %10.2f  budget %d (%.0f%% used)", name, value, budget, 100 * value / budget))
	expect(value <= budget).toBe(true)
end

describe("budgets", function()
	it("keeps the world's instance count within budget", function()
		print(`  (the whole DataModel: Stats.InstanceCount {Stats.InstanceCount})`)
		within("instances", #descendants)
	end)

	it("keeps the world's part count within budget", function()
		local count = 0
		for _, instance in descendants do
			if instance:IsA("BasePart") then
				count += 1
			end
		end
		within("parts", count)
	end)

	it(`keeps the server Heartbeat time within budget over {SAMPLE_SECONDS} s`, function()
		local frames, total, worst = 0, 0, 0
		local connection = RunService.Heartbeat:Connect(function()
			local ms = Stats.HeartbeatTime * 1000
			frames += 1
			total += ms
			worst = math.max(worst, ms)
		end)
		task.wait(SAMPLE_SECONDS)
		connection:Disconnect()
		expect(frames > 0).toBe(true)
		print(string.format("  %d Heartbeats in %d s, the worst %.2f ms", frames, SAMPLE_SECONDS, worst))
		within("heartbeatMs", total / frames)
	end)
end)

finish()
