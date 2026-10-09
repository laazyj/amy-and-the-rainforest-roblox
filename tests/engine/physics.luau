--!strict
-- Physics spike (brief 007, plan section 4 "Reachability is tested,
-- traversal may be"): does the engine step in a Luau Execution task?
-- Watches for two seconds: how often Heartbeat and Stepped fire, whether
-- an unanchored part falls, whether Touched fires when it lands, and
-- whether a Humanoid's MoveTo moves it. Prints what it saw.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Parts = (require :: any)(game:GetService("ServerScriptService"):WaitForChild("Parts"))

local SECONDS = 2

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

describe("physics spike", function()
	it(`watches the engine for {SECONDS} s`, function()
		local floor =
			Parts.make("Part", { Size = Vector3.new(40, 1, 40), Position = Vector3.new(0, 1000, 0) }, Workspace)
		local ball = Parts.make(
			"Part",
			{ Size = Vector3.new(2, 2, 2), Position = Vector3.new(0, 1020, 0), Anchored = false },
			Workspace
		)
		local dropFrom = ball.Position
		local touched = false
		ball.Touched:Connect(function(hit)
			touched = touched or hit == floor
		end)

		-- an R15 rig from a default HumanoidDescription, standing on the
		-- floor and told to walk 10 studs; a bare root and Humanoid if the
		-- task cannot build one
		local built, rig = pcall(function()
			return game:GetService("Players")
				:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		end)
		if not built then
			print(`  CreateHumanoidModelFromDescription failed ({rig}); using a bare rig`)
			rig = Instance.new("Model")
			local bare =
				Parts.make("Part", { Name = "HumanoidRootPart", Size = Vector3.new(2, 2, 1), Anchored = false }, rig)
			rig.PrimaryPart = bare
			Instance.new("Humanoid").Parent = rig
		end
		rig:PivotTo(CFrame.new(10, 1004, 0))
		rig.Parent = Workspace
		local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
		local root = rig.PrimaryPart :: BasePart
		local walkedFrom = root.Position

		local heartbeats, stepped = 0, 0
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

		print(`  Heartbeat fired {heartbeats} times, Stepped {stepped} times in {SECONDS} s`)
		print(string.format("  an unanchored part fell %.2f studs", dropFrom.Y - ball.Position.Y))
		print(`  Touched fired on landing: {touched}`)
		print(`  the Humanoid's state: {humanoid:GetState().Name}`)
		print(
			string.format(
				"  a Humanoid told to MoveTo 10 studs away moved %.2f studs",
				(flat(root.Position) - flat(walkedFrom)).Magnitude
			)
		)
	end)
end)

finish()
