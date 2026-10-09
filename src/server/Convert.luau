--!strict
-- Content's plain positions, colours and Spots as engine datatypes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Story = require(ReplicatedStorage:WaitForChild("core"):WaitForChild("Story"))

local Convert = {}

function Convert.vector(v: Story.Vec3): Vector3
	return Vector3.new(v.x, v.y, v.z)
end

function Convert.colour(c: Story.RGB): Color3
	return Color3.fromRGB(c.r, c.g, c.b)
end

-- Standing on `spot` with its pivot `height` above the Spot's ground, facing
-- the way the Spot faces.
function Convert.standing(spot: Story.Spot, height: number): CFrame
	local at = Vector3.new(spot.at.x, spot.at.y + height, spot.at.z)
	return CFrame.lookAt(at, at + Convert.vector(spot.facing) * 10)
end

return Convert
