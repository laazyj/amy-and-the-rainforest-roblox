--!strict
-- Helpers content writes positions, colours, Spots and Zones with. The world runs
-- from Amy's garden (low z) to the paradise (high z), so a Spot faces
-- either the forest (+z) or home (-z).

local Story = require("../core/Story")

local layout = {}

layout.TOWARD_FOREST = table.freeze({ x = 0, y = 0, z = 1 }) :: Story.Vec3
layout.TOWARD_HOME = table.freeze({ x = 0, y = 0, z = -1 }) :: Story.Vec3

function layout.at(x: number, y: number, z: number): Story.Vec3
	return { x = x, y = y, z = z }
end

function layout.rgb(r: number, g: number, b: number): Story.RGB
	return { r = r, g = g, b = b }
end

-- A human's Description: `skin` on the head, `top` on the torso and arms,
-- `bottom` on the legs.
function layout.dressed(skin: Story.RGB, top: Story.RGB, bottom: Story.RGB): Story.Description
	return { head = skin, torso = top, arms = top, legs = bottom }
end

-- A Spot on the ground at (x, z).
function layout.spot(x: number, z: number, facing: Story.Vec3): Story.Spot
	return { at = layout.at(x, 0, z), facing = facing }
end

-- A Spot on the ground at (x, z) facing `toward` across the ground: a
-- Character's Spot faces where Amy talks with it from.
function layout.spotToward(x: number, z: number, toward: Story.Vec3): Story.Spot
	local dx, dz = toward.x - x, toward.z - z
	local length = math.sqrt(dx * dx + dz * dz)
	return layout.spot(x, z, { x = dx / length, y = 0, z = dz / length })
end

-- A Zone: its centre and size.
function layout.zone(centre: Story.Vec3, size: Story.Vec3): Story.Zone
	return { centre = centre, size = size }
end

return layout
