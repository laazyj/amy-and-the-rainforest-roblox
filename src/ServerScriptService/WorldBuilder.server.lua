--[[
	WorldBuilder
	============
	Builds the whole world out of parts when the server starts, styled
	after the hand-drawn hero illustration on clara.jasonduffett.net:

	  * a cream sky with little black birds and outline clouds
	  * a wide field of scribbly green grass
	  * Amy's house and garden (with the gate Sam guards) and a village
	  * the rain forest as a LOOMING WALL of giant brown trunks standing
	    shoulder to shoulder, topped with big round two-tone canopies,
	    bird nests and eggs -- with one narrow gap, just Amy's size
	  * beyond the wall: the parallel-world paradise, in the site's
	    palette (moss, gold, bubblegum pink, grape purple)

	All the key coordinates come from StoryData.Map so the story
	scripts and the map always agree about where things are.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local StoryData = require(ReplicatedStorage:WaitForChild("StoryData"))
local Map = StoryData.Map

local rng = Random.new(20260702) -- deterministic layout

local mapFolder = Instance.new("Folder")
mapFolder.Name = "RainforestMap"

----------------------------------------------------------------
-- Palette (from the website's story page)
----------------------------------------------------------------
local DEEP = Color3.fromRGB(35, 64, 29) -- #23401d
local MOSS = Color3.fromRGB(90, 138, 68) -- #5a8a44
local BARK = Color3.fromRGB(107, 68, 38) -- #6b4426
local GOLD = Color3.fromRGB(231, 181, 58) -- #e7b53a
local RED = Color3.fromRGB(194, 64, 47) -- #c2402f
local GRAPE = Color3.fromRGB(124, 77, 255) -- #7c4dff
local BUBBLEGUM = Color3.fromRGB(255, 93, 162) -- #ff5da2
local CREAM = Color3.fromRGB(240, 237, 217)
local GRASS_GREEN = Color3.fromRGB(74, 122, 56)
local GRASS_LIGHT = Color3.fromRGB(96, 148, 70)
local CANOPY_DARK = Color3.fromRGB(56, 108, 45)
local CANOPY_LIGHT = Color3.fromRGB(104, 158, 72)

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function makePart(props, parent)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = parent or mapFolder
	return part
end

local function makeWedge(props, parent)
	local wedge = Instance.new("WedgePart")
	wedge.Anchored = true
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		wedge[key] = value
	end
	wedge.Parent = parent or mapFolder
	return wedge
end

local function makeFireflies(position, color)
	local holder = makePart({
		Name = "FireflyHolder",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(position),
		Transparency = 1,
		CanCollide = false,
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color or Color3.fromRGB(255, 240, 150))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.35)
	emitter.Lifetime = NumberRange.new(2, 4)
	emitter.Rate = 3
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = holder
end

----------------------------------------------------------------
-- Lighting: a warm cream-sky afternoon
----------------------------------------------------------------
Lighting.ClockTime = 13.5
Lighting.Brightness = 2.2
Lighting.Ambient = Color3.fromRGB(118, 118, 100)
Lighting.OutdoorAmbient = Color3.fromRGB(150, 148, 126)
Lighting.FogColor = CREAM
Lighting.FogEnd = 700

local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = 0.3
atmosphere.Color = Color3.fromRGB(227, 233, 191) -- the drawing's pale ground-sky tint
atmosphere.Haze = 1.6
atmosphere.Parent = Lighting

----------------------------------------------------------------
-- Ground
----------------------------------------------------------------
local WORLD_START_Z = -75
local WORLD_END_Z = Map.ForestEndZ
local WIDTH = Map.MapHalfWidth * 2

-- Home-and-field side: the drawing's flat green grass
local fieldLength = Map.ForestWallZ - WORLD_START_Z
makePart({
	Name = "GroundField",
	Size = Vector3.new(WIDTH, 4, fieldLength),
	CFrame = CFrame.new(0, Map.GroundY - 2, WORLD_START_Z + fieldLength / 2),
	Color = GRASS_GREEN,
	Material = Enum.Material.Grass,
})

-- Paradise side: a touch lighter and springier
local paradiseLength = WORLD_END_Z - Map.ForestWallZ
makePart({
	Name = "GroundParadise",
	Size = Vector3.new(WIDTH, 4, paradiseLength),
	CFrame = CFrame.new(0, Map.GroundY - 2, Map.ForestWallZ + paradiseLength / 2),
	Color = GRASS_LIGHT,
	Material = Enum.Material.Grass,
})

-- Invisible walls around the whole map
local function makeWall(cframe, size)
	makePart({ Name = "BoundaryWall", Size = size, CFrame = cframe, Transparency = 1 })
end
local midZ = (WORLD_START_Z + WORLD_END_Z) / 2
local totalLength = WORLD_END_Z - WORLD_START_Z
makeWall(CFrame.new(-Map.MapHalfWidth, 40, midZ), Vector3.new(4, 100, totalLength))
makeWall(CFrame.new(Map.MapHalfWidth, 40, midZ), Vector3.new(4, 100, totalLength))
makeWall(CFrame.new(0, 40, WORLD_START_Z), Vector3.new(WIDTH, 100, 4))
makeWall(CFrame.new(0, 40, WORLD_END_Z), Vector3.new(WIDTH, 100, 4))

----------------------------------------------------------------
-- Scribbly grass + field flowers (the drawing's pen strokes)
----------------------------------------------------------------
local function makeGrassTuft(x, z, side)
	local shade
	if side == "field" then
		shade = Color3.fromRGB(52, 92, 40)
	else
		shade = Color3.fromRGB(70, 120, 52)
	end
	local blades = rng:NextInteger(2, 3)
	for _ = 1, blades do
		local height = rng:NextNumber(1, 2.4)
		makePart({
			Name = "GrassBlade",
			Size = Vector3.new(0.25, height, 0.9),
			CFrame = CFrame.new(x + rng:NextNumber(-0.8, 0.8), Map.GroundY + height / 2, z + rng:NextNumber(-0.8, 0.8))
				* CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(0, math.pi), rng:NextNumber(-0.25, 0.25)),
			Color = shade,
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end
end

for _ = 1, 160 do
	makeGrassTuft(rng:NextNumber(-90, 90), rng:NextNumber(-60, Map.ForestWallZ - 8), "field")
end
for _ = 1, 120 do
	makeGrassTuft(rng:NextNumber(-90, 90), rng:NextNumber(Map.ForestWallZ + 10, WORLD_END_Z - 10), "paradise")
end

-- A few little gold and red flowers dotting the field (site accents)
for _ = 1, 26 do
	local x = rng:NextNumber(-85, 85)
	local z = rng:NextNumber(-55, Map.ForestWallZ - 12)
	local color
	if rng:NextNumber() < 0.5 then
		color = GOLD
	else
		color = RED
	end
	makePart({
		Name = "FieldFlower",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.9, 0.7, 0.9),
		CFrame = CFrame.new(x, Map.GroundY + 1.1, z),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	makePart({
		Name = "FieldFlowerStem",
		Size = Vector3.new(0.2, 1, 0.2),
		CFrame = CFrame.new(x, Map.GroundY + 0.5, z),
		Color = MOSS,
		Material = Enum.Material.Grass,
		CanCollide = false,
	})
end

----------------------------------------------------------------
-- Birds and clouds in the cream sky (like the drawing)
----------------------------------------------------------------
local function makeBird(position, scale)
	-- a little "v" of two angled black strokes
	for side = -1, 1, 2 do
		makePart({
			Name = "BirdWing",
			Size = Vector3.new(2.2 * scale, 0.3 * scale, 0.4 * scale),
			CFrame = CFrame.new(position + Vector3.new(side * 0.9 * scale, 0, 0))
				* CFrame.Angles(0, 0, math.rad(24 * side)),
			Color = Color3.fromRGB(30, 30, 30),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
	end
end

makeBird(Vector3.new(-40, 72, 100), 1.2)
makeBird(Vector3.new(-28, 66, 112), 0.9)
makeBird(Vector3.new(52, 78, 90), 1.1)
makeBird(Vector3.new(38, 70, 60), 0.8)
makeBird(Vector3.new(10, 82, 130), 1.0)

local function makeCloud(position, scale)
	for i = 1, 3 do
		makePart({
			Name = "Cloud",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(10, 6, 8) * scale * rng:NextNumber(0.7, 1.1),
			CFrame = CFrame.new(position + Vector3.new((i - 2) * 6 * scale, rng:NextNumber(-1, 1), 0)),
			Color = Color3.fromRGB(250, 248, 240),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
	end
end

makeCloud(Vector3.new(-60, 85, 40), 1.2)
makeCloud(Vector3.new(65, 92, 110), 1.0)
makeCloud(Vector3.new(-20, 95, 170), 1.4)

----------------------------------------------------------------
-- Amy's house and garden
----------------------------------------------------------------
local housePos = Map.HousePosition

local function makeHouse(x, z, wallColor, roofColor, scale, parent)
	local w = 20 * scale
	local d = 14 * scale
	local h = 10 * scale
	-- walls
	makePart({
		Name = "HouseWalls",
		Size = Vector3.new(w, h, d),
		CFrame = CFrame.new(x, Map.GroundY + h / 2, z),
		Color = wallColor,
		Material = Enum.Material.SmoothPlastic,
	}, parent)
	-- pitched roof from two wedges
	for side = -1, 1, 2 do
		makeWedge({
			Name = "HouseRoof",
			Size = Vector3.new(w + 2 * scale, 5 * scale, (d + 2 * scale) / 2),
			CFrame = CFrame.new(x, Map.GroundY + h + 2.5 * scale, z + side * (d + 2 * scale) / 4)
				* CFrame.Angles(0, side == 1 and math.pi or 0, 0),
			Color = roofColor,
			Material = Enum.Material.Wood,
		}, parent)
	end
	-- door (facing +Z, toward the field)
	makePart({
		Name = "HouseDoor",
		Size = Vector3.new(3.4 * scale, 6 * scale, 0.6),
		CFrame = CFrame.new(x, Map.GroundY + 3 * scale, z + d / 2 + 0.2),
		Color = BARK,
		Material = Enum.Material.Wood,
		CanCollide = false,
	}, parent)
	-- windows
	for side = -1, 1, 2 do
		makePart({
			Name = "HouseWindow",
			Size = Vector3.new(3 * scale, 3 * scale, 0.6),
			CFrame = CFrame.new(x + side * w / 3.2, Map.GroundY + 5.5 * scale, z + d / 2 + 0.2),
			Color = Color3.fromRGB(200, 226, 235),
			Material = Enum.Material.Glass,
			CanCollide = false,
		}, parent)
	end
end

-- Amy's house: red like her jumper in the drawing, gold roof
makeHouse(housePos.X, housePos.Z, Color3.fromRGB(206, 92, 74), BARK, 1, mapFolder)

-- Garden fence with a gate opening at the front
local GATE_HALF = 3
local fenceY = Map.GroundY + 1.4
local function fenceRun(x1, z1, x2, z2)
	local a = Vector3.new(x1, fenceY, z1)
	local b = Vector3.new(x2, fenceY, z2)
	local length = (b - a).Magnitude
	local mid = (a + b) / 2
	makePart({
		Name = "FenceRail",
		Size = Vector3.new(0.5, 0.5, length),
		CFrame = CFrame.lookAt(mid + Vector3.new(0, 0.6, 0), b + Vector3.new(0, 0.6, 0)),
		Color = Color3.fromRGB(168, 132, 90),
		Material = Enum.Material.Wood,
	})
	makePart({
		Name = "FenceRail",
		Size = Vector3.new(0.5, 0.5, length),
		CFrame = CFrame.lookAt(mid + Vector3.new(0, -0.4, 0), b + Vector3.new(0, -0.4, 0)),
		Color = Color3.fromRGB(168, 132, 90),
		Material = Enum.Material.Wood,
	})
	local posts = math.max(2, math.floor(length / 6) + 1)
	for i = 0, posts - 1 do
		local t = i / (posts - 1)
		local p = a:Lerp(b, t)
		makePart({
			Name = "FencePost",
			Size = Vector3.new(0.8, 3.4, 0.8),
			CFrame = CFrame.new(p.X, Map.GroundY + 1.7, p.Z),
			Color = Color3.fromRGB(150, 116, 78),
			Material = Enum.Material.Wood,
		})
	end
end

local GARDEN_HALF_W = 15
local gardenBackZ = housePos.Z - 10
local gateZ = Map.GardenGateZ
-- front fence, split around the gate
fenceRun(-GARDEN_HALF_W, gateZ, -GATE_HALF, gateZ)
fenceRun(GATE_HALF, gateZ, GARDEN_HALF_W, gateZ)
-- sides and back
fenceRun(-GARDEN_HALF_W, gateZ, -GARDEN_HALF_W, gardenBackZ)
fenceRun(GARDEN_HALF_W, gateZ, GARDEN_HALF_W, gardenBackZ)
fenceRun(-GARDEN_HALF_W, gardenBackZ, GARDEN_HALF_W, gardenBackZ)

-- Spawn inside the garden
local spawnLocation = Instance.new("SpawnLocation")
spawnLocation.Name = "AmySpawn"
spawnLocation.Size = Vector3.new(8, 1, 8)
spawnLocation.CFrame = CFrame.new(Map.SpawnPosition.X, Map.GroundY + 0.5, Map.SpawnPosition.Z)
spawnLocation.Anchored = true
spawnLocation.Color = GRASS_LIGHT
spawnLocation.Material = Enum.Material.Grass
spawnLocation.Duration = 0
spawnLocation.Transparency = 1
spawnLocation.Parent = mapFolder

----------------------------------------------------------------
-- The village (a few more little houses behind Amy's)
----------------------------------------------------------------
makeHouse(-44, -50, Color3.fromRGB(222, 196, 150), DEEP, 0.9, mapFolder)
makeHouse(44, -44, Color3.fromRGB(196, 176, 208), BARK, 0.85, mapFolder)
makeHouse(-64, -20, Color3.fromRGB(176, 196, 160), BARK, 0.8, mapFolder)
makeHouse(62, -24, Color3.fromRGB(228, 180, 120), DEEP, 0.9, mapFolder)

----------------------------------------------------------------
-- The dirt path from the garden gate toward the forest gap
----------------------------------------------------------------
local pathPoints = {
	Vector3.new(0, 0, gateZ + 2),
	Vector3.new(6, 0, 20),
	Vector3.new(-8, 0, 60),
	Vector3.new(4, 0, 100),
	Vector3.new(0, 0, Map.ForestWallZ - 6),
}
for i = 1, #pathPoints - 1 do
	local a = pathPoints[i]
	local b = pathPoints[i + 1]
	local mid = (a + b) / 2
	local length = (b - a).Magnitude + 4
	makePart({
		Name = "Path",
		Size = Vector3.new(7, 0.3, length),
		CFrame = CFrame.lookAt(Vector3.new(mid.X, Map.GroundY + 0.1, mid.Z), Vector3.new(b.X, Map.GroundY + 0.1, b.Z)),
		Color = Color3.fromRGB(186, 160, 116),
		Material = Enum.Material.Ground,
		CanCollide = false,
	})
end

----------------------------------------------------------------
-- THE LOOMING FOREST WALL
-- Giant trunks standing shoulder to shoulder, exactly like the
-- drawing: a fence of trees with one gap, just Amy's size.
----------------------------------------------------------------
local wallZ = Map.ForestWallZ
local TRUNK_DIAMETER = 13
local TRUNK_HEIGHT = 42

local function makeNest(x, y, z)
	makePart({
		Name = "Nest",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.4, 4.6, 4.6),
		CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(122, 88, 48),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	for i = 1, 3 do
		makePart({
			Name = "NestEgg",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1, 1.3, 1),
			CFrame = CFrame.new(x + (i - 2) * 0.9, y + 1, z + rng:NextNumber(-0.4, 0.4)),
			Color = Color3.fromRGB(248, 244, 230),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
	end
end

local function makeWallTree(x, hasNest)
	local heightJitter = rng:NextNumber(-3, 4)
	local height = TRUNK_HEIGHT + heightJitter
	-- the giant trunk
	makePart({
		Name = "WallTrunk",
		Size = Vector3.new(TRUNK_DIAMETER, height, TRUNK_DIAMETER * 0.85),
		CFrame = CFrame.new(x, Map.GroundY + height / 2, wallZ),
		Color = Color3.fromRGB(139, 101, 64),
		Material = Enum.Material.Wood,
	})
	-- rounded edges illusion: a slightly darker core cylinder in front
	makePart({
		Name = "WallTrunkBark",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, TRUNK_DIAMETER * 0.55, TRUNK_DIAMETER * 0.55),
		CFrame = CFrame.new(x, Map.GroundY + height / 2, wallZ - TRUNK_DIAMETER * 0.28) * CFrame.Angles(0, 0, math.rad(90)),
		Color = BARK,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	-- a knot hole on some trunks (like the drawing's swirls)
	if rng:NextNumber() < 0.4 then
		makePart({
			Name = "TrunkKnot",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.6, 3.4, 1.5),
			CFrame = CFrame.new(x + rng:NextNumber(-3, 3), Map.GroundY + rng:NextNumber(10, 24), wallZ - TRUNK_DIAMETER * 0.52),
			Color = Color3.fromRGB(92, 62, 38),
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
	end
	-- big round two-tone canopy
	local canopyY = Map.GroundY + height + 6
	local canopyR = rng:NextNumber(17, 22)
	makePart({
		Name = "WallCanopy",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(canopyR * 2, canopyR * 1.4, canopyR * 1.8),
		CFrame = CFrame.new(x, canopyY, wallZ),
		Color = CANOPY_DARK,
		Material = Enum.Material.Grass,
		CanCollide = false,
	})
	makePart({
		Name = "WallCanopyHighlight",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(canopyR * 1.3, canopyR * 0.8, canopyR * 1.1),
		CFrame = CFrame.new(x - canopyR * 0.15, canopyY + canopyR * 0.28, wallZ - canopyR * 0.2),
		Color = CANOPY_LIGHT,
		Material = Enum.Material.Grass,
		CanCollide = false,
	})
	if hasNest then
		makeNest(x, canopyY + canopyR * 0.72 + 1, wallZ - 2)
	end
end

-- Trunks marching out from the central gap to both edges
local gap = Map.ForestGapHalfWidth
local firstX = gap + TRUNK_DIAMETER / 2 + 0.5
local nestSpots = { [2] = true, [5] = true } -- which trees (per side) carry nests
local i = 0
local x = firstX
while x < Map.MapHalfWidth + TRUNK_DIAMETER do
	i = i + 1
	makeWallTree(x, nestSpots[i] == true)
	makeWallTree(-x, nestSpots[i] == true and i ~= 2) -- vary the sides a little
	x = x + TRUNK_DIAMETER + rng:NextNumber(-0.5, 1)
end

-- Above the gap the canopies close over, so the way in feels like a doorway
makePart({
	Name = "GapArchCanopy",
	Shape = Enum.PartType.Ball,
	Size = Vector3.new(26, 18, 22),
	CFrame = CFrame.new(0, Map.GroundY + TRUNK_HEIGHT + 8, wallZ),
	Color = CANOPY_DARK,
	Material = Enum.Material.Grass,
	CanCollide = false,
})
-- Shadowy earth in the gap itself
makePart({
	Name = "GapFloor",
	Size = Vector3.new(gap * 2, 0.3, TRUNK_DIAMETER + 4),
	CFrame = CFrame.new(0, Map.GroundY + 0.12, wallZ),
	Color = Color3.fromRGB(70, 84, 52),
	Material = Enum.Material.Ground,
	CanCollide = false,
})

----------------------------------------------------------------
-- THE PARALLEL-WORLD PARADISE (beyond the wall)
----------------------------------------------------------------
local PARADISE_LEAF_COLORS = {
	MOSS,
	Color3.fromRGB(120, 190, 90),
	BUBBLEGUM,
	GRAPE,
	Color3.fromRGB(90, 200, 170), -- teal
	GOLD,
}

local function paradiseLeafColor()
	return PARADISE_LEAF_COLORS[rng:NextInteger(1, #PARADISE_LEAF_COLORS)]
end

local function makeParadiseTree(px, pz, scale)
	local trunkHeight = 14 * scale
	makePart({
		Name = "ParadiseTrunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(trunkHeight, 2.4 * scale, 2.4 * scale),
		CFrame = CFrame.new(px, Map.GroundY + trunkHeight / 2, pz) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(122, 84, 56),
		Material = Enum.Material.Wood,
	})
	for _ = 1, rng:NextInteger(2, 4) do
		local offset = Vector3.new(
			rng:NextNumber(-3.5, 3.5) * scale,
			rng:NextNumber(-1, 3.5) * scale,
			rng:NextNumber(-3.5, 3.5) * scale
		)
		makePart({
			Name = "ParadiseLeaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1, 1, 1) * rng:NextNumber(7, 12) * scale,
			CFrame = CFrame.new(Vector3.new(px, Map.GroundY + trunkHeight, pz) + offset),
			Color = paradiseLeafColor(),
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end
end

local function makeGlowFlower(px, pz, big)
	local scale
	if big then
		scale = rng:NextNumber(2.2, 3)
	else
		scale = rng:NextNumber(0.8, 1.3)
	end
	local stemH = 2.2 * scale
	makePart({
		Name = "GlowFlowerStem",
		Size = Vector3.new(0.3 * scale, stemH, 0.3 * scale),
		CFrame = CFrame.new(px, Map.GroundY + stemH / 2, pz),
		Color = MOSS,
		Material = Enum.Material.Grass,
		CanCollide = false,
	})
	local petalColor
	if rng:NextNumber() < 0.5 then
		petalColor = BUBBLEGUM
	else
		petalColor = GRAPE
	end
	local head = makePart({
		Name = "GlowFlowerHead",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 1.1, 1.6) * scale,
		CFrame = CFrame.new(px, Map.GroundY + stemH + 0.5 * scale, pz),
		Color = petalColor,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	local core = makePart({
		Name = "GlowFlowerCore",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.7, 0.7, 0.7) * scale,
		CFrame = CFrame.new(px, Map.GroundY + stemH + 0.9 * scale, pz),
		Color = GOLD,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	if big then
		local light = Instance.new("PointLight")
		light.Color = petalColor
		light.Range = 14
		light.Brightness = 1.2
		light.Parent = core
	end
	return head
end

local function inParadiseKeepClear(px, pz)
	-- keep the walking line from the gap to the glade, and the glade
	-- itself, free of trunks
	if math.abs(px) < 10 and pz < 265 then
		return true
	end
	if (Vector3.new(px, 0, pz) - Vector3.new(0, 0, 255)).Magnitude < 24 then
		return true
	end
	-- keep breathing room where the animals stand
	for _, npc in ipairs(StoryData.NPCs) do
		if (Vector3.new(px - npc.position.X, 0, pz - npc.position.Z)).Magnitude < 12 then
			return true
		end
	end
	return false
end

for _ = 1, 90 do
	local px = rng:NextNumber(-88, 88)
	local pz = rng:NextNumber(Map.ForestWallZ + 18, WORLD_END_Z - 12)
	if not inParadiseKeepClear(px, pz) then
		makeParadiseTree(px, pz, rng:NextNumber(0.7, 1.8))
	end
end

for _ = 1, 40 do
	local px = rng:NextNumber(-80, 80)
	local pz = rng:NextNumber(Map.ForestWallZ + 14, WORLD_END_Z - 14)
	if not inParadiseKeepClear(px, pz) then
		makeGlowFlower(px, pz, false)
	end
end

-- A trail of glowing flowers leads from the gap to the heart glade
local trailZ = Map.ForestWallZ + 14
while trailZ < 240 do
	makeGlowFlower(((trailZ % 20 < 10) and 5 or -5), trailZ, false)
	trailZ = trailZ + 12
end

-- The heart glade: a ring of big glowing flowers
for j = 1, 9 do
	local a = (j / 9) * math.pi * 2
	makeGlowFlower(math.cos(a) * 20, 255 + math.sin(a) * 20, true)
end

-- Shafts of golden light falling through the paradise canopy
for _ = 1, 8 do
	local px = rng:NextNumber(-70, 70)
	local pz = rng:NextNumber(Map.ForestWallZ + 25, WORLD_END_Z - 30)
	makePart({
		Name = "LightShaft",
		Size = Vector3.new(rng:NextNumber(3, 6), 60, rng:NextNumber(3, 6)),
		CFrame = CFrame.new(px, Map.GroundY + 30, pz) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-6, 6))),
		Color = GOLD,
		Material = Enum.Material.Neon,
		Transparency = 0.82,
		CanCollide = false,
	})
end

-- Drifting sparkles everywhere in the paradise
for _ = 1, 16 do
	local px = rng:NextNumber(-70, 70)
	local pz = rng:NextNumber(Map.ForestWallZ + 15, WORLD_END_Z - 15)
	local color
	local roll = rng:NextNumber()
	if roll < 0.34 then
		color = BUBBLEGUM
	elseif roll < 0.67 then
		color = GOLD
	else
		color = Color3.fromRGB(190, 240, 255)
	end
	makeFireflies(Vector3.new(px, Map.GroundY + rng:NextNumber(3, 9), pz), color)
end

----------------------------------------------------------------
-- Billboard crediting the original story website
----------------------------------------------------------------
-- The story comes from Clara's non-commercial site. This billboard
-- stands beside the path just before the forest wall and recreates
-- the site's hero header (deep green, gold "Rain Forest", the URL).
--
-- OPTIONAL: to show the site's real hand-drawn hero artwork on the
-- board, upload assets-src/site-hero.png from this repo to Roblox as
-- a Decal (Studio > Asset Manager, or create.roblox.com), then paste
-- its numeric asset id here:
local SITE_SNAPSHOT_DECAL_ID = 0
local SITE_URL = "clara.jasonduffett.net"

-- beside the path, angled to face players walking up from the village
local billboardCFrame = CFrame.new(17, Map.GroundY, 126) * CFrame.Angles(0, math.rad(15), 0)

for side = -1, 1, 2 do
	makePart({
		Name = "BillboardPost",
		Size = Vector3.new(0.9, 8.4, 0.9),
		CFrame = billboardCFrame * CFrame.new(5.6 * side, 4.2, 0.5),
		Color = Color3.fromRGB(122, 88, 55),
		Material = Enum.Material.Wood,
	})
end
makePart({
	Name = "BillboardBacking",
	Size = Vector3.new(14.6, 7.6, 0.5),
	CFrame = billboardCFrame * CFrame.new(0, 8.2, 0.45),
	Color = BARK,
	Material = Enum.Material.Wood,
})
local billboardPanel = makePart({
	Name = "BillboardPanel",
	Size = Vector3.new(14, 7, 0.4),
	CFrame = billboardCFrame * CFrame.new(0, 8.2, 0),
	Color = DEEP,
	Material = Enum.Material.SmoothPlastic,
})
-- gold trim, like the site's golden squiggle rule
for side = -1, 1, 2 do
	makePart({
		Name = "BillboardTrim",
		Size = Vector3.new(14.6, 0.35, 0.5),
		CFrame = billboardCFrame * CFrame.new(0, 8.2 + 3.68 * side, -0.02),
		Color = GOLD,
		Material = Enum.Material.SmoothPlastic,
	})
	makePart({
		Name = "BillboardTrim",
		Size = Vector3.new(0.35, 7.4, 0.5),
		CFrame = billboardCFrame * CFrame.new(7.15 * side, 8.2, -0.02),
		Color = GOLD,
		Material = Enum.Material.SmoothPlastic,
	})
end

local billboardGui = Instance.new("SurfaceGui")
billboardGui.Name = "SiteCredit"
billboardGui.Face = Enum.NormalId.Front
billboardGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
billboardGui.PixelsPerStud = 40
billboardGui.LightInfluence = 0
billboardGui.Parent = billboardPanel

local billboardRoot = Instance.new("Frame")
billboardRoot.Size = UDim2.new(1, 0, 1, 0)
billboardRoot.BackgroundColor3 = DEEP
billboardRoot.BorderSizePixel = 0
billboardRoot.Parent = billboardGui

-- upper area: either the recreated hero header, or the real artwork
local heroArea = Instance.new("Frame")
heroArea.Size = UDim2.new(1, 0, 1, -56)
heroArea.BackgroundTransparency = 1
heroArea.Parent = billboardRoot

local kicker = Instance.new("TextLabel")
kicker.AnchorPoint = Vector2.new(0.5, 0)
kicker.Position = UDim2.new(0.5, 0, 0, 12)
kicker.Size = UDim2.new(0, 250, 0, 34)
kicker.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
kicker.BackgroundTransparency = 0.12
kicker.Rotation = -2
kicker.Font = Enum.Font.PatrickHand
kicker.TextSize = 24
kicker.TextColor3 = DEEP
kicker.Text = "a little tale of the wild"
kicker.Parent = heroArea
local kickerCorner = Instance.new("UICorner")
kickerCorner.CornerRadius = UDim.new(0, 17)
kickerCorner.Parent = kicker

local siteTitle = Instance.new("TextLabel")
siteTitle.AnchorPoint = Vector2.new(0.5, 0)
siteTitle.Position = UDim2.new(0.5, 0, 0, 50)
siteTitle.Size = UDim2.new(1, -50, 0, 100)
siteTitle.BackgroundTransparency = 1
siteTitle.Font = Enum.Font.PatrickHand
siteTitle.TextScaled = true
siteTitle.RichText = true
siteTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
siteTitle.Text = 'Amy &amp; the <font color="#E7B53A">Rain Forest</font>'
siteTitle.Parent = heroArea

local byline = Instance.new("TextLabel")
byline.AnchorPoint = Vector2.new(0.5, 1)
byline.Position = UDim2.new(0.5, 0, 1, -8)
byline.Size = UDim2.new(1, -40, 0, 30)
byline.BackgroundTransparency = 1
byline.Font = Enum.Font.PatrickHand
byline.TextSize = 26
byline.TextColor3 = CREAM
byline.Text = "a story by Clara Dineen-Duffett"
byline.Parent = heroArea

if SITE_SNAPSHOT_DECAL_ID > 0 then
	kicker.Visible = false
	siteTitle.Visible = false
	byline.Visible = false
	local artwork = Instance.new("ImageLabel")
	artwork.Size = UDim2.new(1, 0, 1, 0)
	artwork.BackgroundTransparency = 1
	artwork.Image = "rbxassetid://" .. tostring(SITE_SNAPSHOT_DECAL_ID)
	artwork.ScaleType = Enum.ScaleType.Crop
	artwork.Parent = heroArea
end

-- the URL strip along the bottom, always visible
local urlStrip = Instance.new("Frame")
urlStrip.AnchorPoint = Vector2.new(0, 1)
urlStrip.Position = UDim2.new(0, 0, 1, 0)
urlStrip.Size = UDim2.new(1, 0, 0, 56)
urlStrip.BackgroundColor3 = CREAM
urlStrip.BorderSizePixel = 0
urlStrip.Parent = billboardRoot

local urlLabel = Instance.new("TextLabel")
urlLabel.Position = UDim2.new(0, 0, 0, 4)
urlLabel.Size = UDim2.new(1, 0, 0, 30)
urlLabel.BackgroundTransparency = 1
urlLabel.Font = Enum.Font.FredokaOne
urlLabel.TextSize = 27
urlLabel.TextColor3 = DEEP
urlLabel.Text = SITE_URL
urlLabel.Parent = urlStrip

local urlNote = Instance.new("TextLabel")
urlNote.AnchorPoint = Vector2.new(0, 1)
urlNote.Position = UDim2.new(0, 0, 1, -4)
urlNote.Size = UDim2.new(1, 0, 0, 18)
urlNote.BackgroundTransparency = 1
urlNote.Font = Enum.Font.PatrickHand
urlNote.TextSize = 17
urlNote.TextColor3 = Color3.fromRGB(107, 68, 38)
urlNote.Text = "come read the original story — a non-commercial site"
urlNote.Parent = urlStrip

mapFolder.Parent = Workspace
print("[WorldBuilder] World built: village, field, forest wall, paradise.")
