--!strict
-- Budgets (plan section 4: "Budgets are tests, measured where they can
-- be"). With the world built as the place's Scripts build it (_world.luau),
-- the instance count, the part count and the mean server Heartbeat time
-- over a 5-second sample (the worst frame is printed, not gated: one slow
-- frame on a shared server is noise) must stay within budget: the value
-- MEASURED when the budget was set, plus 20% HEADROOM, or its FLOOR where a
-- shared server's noise needs more. A change that needs more raises
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

-- Measured on Saved Dev version 27 (PR #25, 2026-10-09): Workspace
-- descendants, BaseParts among them, and the mean Stats.HeartbeatTime of an
-- idle server (worst frame 0.27 ms). Budgets round up to 0.01, and never
-- go below their FLOOR.
local MEASURED = {
	instances = 1593,
	parts = 1533,
	heartbeatMs = 0.08,
}

-- A shared server's idle frame time varies from run to run, so the Heartbeat
-- budget is at least 0.25 ms; that still catches a regression of three times
-- the measured 0.08 ms, well before the plan's 8 ms (section 8).
local FLOOR = { heartbeatMs = 0.25 }

include("tests/engine/_world.luau").build(true)
local descendants = Workspace:GetDescendants()

-- Reports `value` against its budget, then holds it to the budget.
local function within(name: string, value: number)
	local budget = math.max(math.ceil(MEASURED[name] * HEADROOM * 100) / 100, FLOOR[name] or 0)
	print(string.format("  %-12s %10.2f  budget %.2f (%.0f%% used)", name, value, budget, 100 * value / budget))
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
