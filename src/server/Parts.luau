--!strict
-- Parts: the one way the adapters make the parts they build from: anchored,
-- smooth top and bottom, then the given properties, then parented.

local Parts = {}

function Parts.make<T>(className: string, props: { [string]: any }, parent: Instance): T
	local part = Instance.new(className :: any) :: BasePart
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part :: any
end

return Parts
