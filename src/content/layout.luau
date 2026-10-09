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

-- A Spot on the ground at (x, z).
function layout.spot(x: number, z: number, facing: Story.Vec3): Story.Spot
	return { at = layout.at(x, 0, z), facing = facing }
end

-- A Zone: its centre and size.
function layout.zone(centre: Story.Vec3, size: Story.Vec3): Story.Zone
	return { centre = centre, size = size }
end

return layout
