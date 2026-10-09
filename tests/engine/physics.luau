--!strict
-- Pins the answer recorded in docs/OPEN_CLOUD.md, "Physics in a task":
-- Heartbeat fires in a Luau Execution task, physics does not step. If
-- Roblox starts stepping physics in tasks these fail, and the decision is
-- to be revisited (tier 2 could then walk a Humanoid through each Chapter).

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Parts = (require :: any)(game:GetService("ServerScriptService"):WaitForChild("Parts"))

local SECONDS = 2

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local heartbeats, stepped, touched = 0, 0, false
local fell, walked = 0, 0

describe("physics in a Luau Execution task", function()
	it(`watches the engine for {SECONDS} s`, function()
		local floor =
			Parts.make("Part", { Size = Vector3.new(40, 1, 40), Position = Vector3.new(0, 1000, 0) }, Workspace)
		local ball = Parts.make(
			"Part",
			{ Size = Vector3.new(2, 2, 2), Position = Vector3.new(0, 1020, 0), Anchored = false },
			Workspace
		)
		local dropFrom = ball.Position
		ball.Touched:Connect(function(hit)
			touched = touched or hit == floor
		end)

		-- an R15 rig from a default HumanoidDescription, told to walk 10 studs
		local rig = game:GetService("Players")
			:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		rig:PivotTo(CFrame.new(10, 1004, 0))
		rig.Parent = Workspace
		local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
		local root = rig.PrimaryPart :: BasePart
		local walkedFrom = root.Position

		local connections = {
			RunService.Heartbeat:Connect(function()
				heartbeats += 1
			end),
			RunService.Stepped:Connect(function()
				stepped += 1
			end),
		}
		humanoid:MoveTo(walkedFrom + Vector3.new(10, 0, 0))
		task.wait(SECONDS)
		for _, connection in connections do
			connection:Disconnect()
		end
		fell = dropFrom.Y - ball.Position.Y
		walked = (flat(root.Position) - flat(walkedFrom)).Magnitude

		print(`  Heartbeat fired {heartbeats} times, Stepped {stepped} times in {SECONDS} s`)
		print(string.format("  an unanchored part fell %.2f studs; Touched on landing: %s", fell, tostring(touched)))
		print(string.format("  an R15 Humanoid told to MoveTo 10 studs away moved %.2f studs", walked))
	end)

	it("fires Heartbeat, so waits, tweens and the Zone poll run", function()
		expect(heartbeats > 0).toBe(true)
	end)

	it("does not step physics: no Stepped, no falling, no Touched", function()
		expect(stepped).toBe(0)
		expect(math.abs(fell) < 0.01).toBe(true)
		expect(touched).toBe(false)
	end)

	it("does not move a Humanoid told to MoveTo", function()
		expect(walked < 0.01).toBe(true)
	end)
end)

finish()
