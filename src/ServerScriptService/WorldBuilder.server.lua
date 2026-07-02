--[[
	WorldBuilder
	============
	Builds the whole rainforest out of parts when the server starts:
	spawn clearing, jungle path, animal village, river with a broken
	bridge, and the Great Kapok Tree with its spiral climb.

	Everything is procedural (no uploaded assets needed), and all the
	key coordinates come from StoryData.Map so the story scripts and
	the map always agree about where things are.
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

local GREENS = {
	Color3.fromRGB(58, 125, 68),
	Color3.fromRGB(44, 110, 58),
	Color3.fromRGB(76, 145, 65),
	Color3.fromRGB(38, 96, 72),
}

local function pickGreen()
	return GREENS[rng:NextInteger(1, #GREENS)]
end

-- A simple jungle tree: cylinder trunk + a cluster of leaf balls
local function makeTree(x, z, scale)
	local trunkHeight = 14 * scale
	local trunk = makePart({
		Name = "TreeTrunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(trunkHeight, 2.2 * scale, 2.2 * scale),
		CFrame = CFrame.new(x, Map.GroundY + trunkHeight / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(92, 62, 42),
		Material = Enum.Material.Wood,
	})
	local leafCount = rng:NextInteger(2, 4)
	for i = 1, leafCount do
		local offset = Vector3.new(
			rng:NextNumber(-3, 3) * scale,
			rng:NextNumber(-1, 3) * scale,
			rng:NextNumber(-3, 3) * scale
		)
		makePart({
			Name = "TreeLeaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1, 1, 1) * rng:NextNumber(7, 11) * scale,
			CFrame = CFrame.new(Vector3.new(x, Map.GroundY + trunkHeight, z) + offset),
			Color = pickGreen(),
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end
	return trunk
end

local function makeGlowMushroom(x, z)
	local stemHeight = rng:NextNumber(1.5, 3)
	makePart({
		Name = "MushroomStem",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(stemHeight, 0.8, 0.8),
		CFrame = CFrame.new(x, Map.GroundY + stemHeight / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(235, 225, 200),
		CanCollide = false,
	})
	makePart({
		Name = "MushroomCap",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.4, 1.4, 2.4),
		CFrame = CFrame.new(x, Map.GroundY + stemHeight + 0.4, z),
		Color = Color3.fromRGB(120, 220, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
end

local function makeFireflies(position)
	local holder = makePart({
		Name = "FireflyHolder",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(position),
		Transparency = 1,
		CanCollide = false,
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.35)
	emitter.Lifetime = NumberRange.new(2, 4)
	emitter.Rate = 3
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = holder
end

----------------------------------------------------------------
-- Lighting / atmosphere
----------------------------------------------------------------
Lighting.ClockTime = 14.5
Lighting.Brightness = 2.4
Lighting.Ambient = Color3.fromRGB(90, 110, 90)
Lighting.OutdoorAmbient = Color3.fromRGB(120, 140, 115)
Lighting.FogColor = Color3.fromRGB(170, 205, 170)
Lighting.FogEnd = 550

local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = 0.35
atmosphere.Color = Color3.fromRGB(199, 220, 199)
atmosphere.Haze = 1.4
atmosphere.Parent = Lighting

----------------------------------------------------------------
-- Ground: near bank, river, far bank
----------------------------------------------------------------
local MAP_WIDTH = 190
local NEAR_START_Z = -70
local FAR_END_Z = 480

-- Near bank (spawn, village)
local nearLength = Map.RiverNearZ - NEAR_START_Z
makePart({
	Name = "GroundNear",
	Size = Vector3.new(MAP_WIDTH, 4, nearLength),
	CFrame = CFrame.new(0, Map.GroundY - 2, NEAR_START_Z + nearLength / 2),
	Color = Color3.fromRGB(80, 128, 66),
	Material = Enum.Material.Grass,
})

-- Far bank (deep jungle, Great Tree)
local farLength = FAR_END_Z - Map.RiverFarZ
makePart({
	Name = "GroundFar",
	Size = Vector3.new(MAP_WIDTH, 4, farLength),
	CFrame = CFrame.new(0, Map.GroundY - 2, Map.RiverFarZ + farLength / 2),
	Color = Color3.fromRGB(72, 120, 62),
	Material = Enum.Material.Grass,
})

-- Riverbed + water
local riverLength = Map.RiverFarZ - Map.RiverNearZ
local riverMidZ = (Map.RiverNearZ + Map.RiverFarZ) / 2
makePart({
	Name = "Riverbed",
	Size = Vector3.new(MAP_WIDTH, 4, riverLength),
	CFrame = CFrame.new(0, Map.GroundY - 7, riverMidZ),
	Color = Color3.fromRGB(196, 178, 128),
	Material = Enum.Material.Sand,
})
makePart({
	Name = "RiverWater",
	Size = Vector3.new(MAP_WIDTH, 3.5, riverLength),
	CFrame = CFrame.new(0, Map.GroundY - 3, riverMidZ),
	Color = Color3.fromRGB(70, 140, 180),
	Material = Enum.Material.Glass,
	Transparency = 0.45,
	CanCollide = false,
})

-- Gentle ramps so anyone who falls in the river can walk back out (near side)
makePart({
	Name = "RiverRampNear",
	Size = Vector3.new(24, 1, 14),
	CFrame = CFrame.new(-30, Map.GroundY - 3, Map.RiverNearZ - 1) * CFrame.Angles(math.rad(-35), 0, 0),
	Color = Color3.fromRGB(196, 178, 128),
	Material = Enum.Material.Sand,
})
makePart({
	Name = "RiverRampFar",
	Size = Vector3.new(24, 1, 14),
	CFrame = CFrame.new(30, Map.GroundY - 3, Map.RiverFarZ + 1) * CFrame.Angles(math.rad(35), 0, 0),
	Color = Color3.fromRGB(196, 178, 128),
	Material = Enum.Material.Sand,
})

-- Invisible barrier over the river until the bridge is repaired.
-- StoryServer removes this when chapter 3 is complete.
makePart({
	Name = "RiverBarrier",
	Size = Vector3.new(MAP_WIDTH, 60, 4),
	CFrame = CFrame.new(0, Map.GroundY + 20, riverMidZ),
	Transparency = 1,
})

-- Invisible walls around the whole map so nobody falls off the edge
local function makeWall(cframe, size)
	makePart({ Name = "BoundaryWall", Size = size, CFrame = cframe, Transparency = 1 })
end
local midZ = (NEAR_START_Z + FAR_END_Z) / 2
local totalLength = FAR_END_Z - NEAR_START_Z
makeWall(CFrame.new(-MAP_WIDTH / 2, 30, midZ), Vector3.new(4, 80, totalLength))
makeWall(CFrame.new(MAP_WIDTH / 2, 30, midZ), Vector3.new(4, 80, totalLength))
makeWall(CFrame.new(0, 30, NEAR_START_Z), Vector3.new(MAP_WIDTH, 80, 4))
makeWall(CFrame.new(0, 30, FAR_END_Z), Vector3.new(MAP_WIDTH, 80, 4))

----------------------------------------------------------------
-- Spawn point
----------------------------------------------------------------
local spawnLocation = Instance.new("SpawnLocation")
spawnLocation.Name = "AmySpawn"
spawnLocation.Size = Vector3.new(10, 1, 10)
spawnLocation.CFrame = CFrame.new(Map.SpawnPosition.X, Map.GroundY + 0.5, Map.SpawnPosition.Z)
spawnLocation.Anchored = true
spawnLocation.Color = Color3.fromRGB(214, 190, 140)
spawnLocation.Material = Enum.Material.WoodPlanks
spawnLocation.Duration = 0
spawnLocation.Parent = mapFolder

-- A little wooden jetty behind the spawn (Amy arrived by riverboat)
makePart({
	Name = "Jetty",
	Size = Vector3.new(8, 1, 18),
	CFrame = CFrame.new(0, Map.GroundY + 0.4, -48),
	Color = Color3.fromRGB(150, 110, 70),
	Material = Enum.Material.WoodPlanks,
})

----------------------------------------------------------------
-- The winding path (spawn -> village -> river -> tree)
----------------------------------------------------------------
local pathPoints = {
	Vector3.new(0, 0, -38),
	Vector3.new(4, 0, 10),
	Vector3.new(-8, 0, 55),
	Vector3.new(2, 0, 95),
	Vector3.new(0, 0, 130),
	Vector3.new(0, 0, 175),
	Vector3.new(4, 0, 210),
	Vector3.new(0, 0, 234),
	-- (bridge crosses the river here)
	Vector3.new(0, 0, 268),
	Vector3.new(-6, 0, 310),
	Vector3.new(4, 0, 350),
	Vector3.new(0, 0, 382),
}
for i = 1, #pathPoints - 1 do
	local a = pathPoints[i]
	local b = pathPoints[i + 1]
	local crossesRiver = (a.Z < riverMidZ) ~= (b.Z < riverMidZ)
	if not crossesRiver then
		local mid = (a + b) / 2
		local length = (b - a).Magnitude + 4
		makePart({
			Name = "Path",
			Size = Vector3.new(9, 0.35, length),
			CFrame = CFrame.lookAt(Vector3.new(mid.X, Map.GroundY + 0.1, mid.Z), Vector3.new(b.X, Map.GroundY + 0.1, b.Z)),
			Color = Color3.fromRGB(178, 152, 110),
			Material = Enum.Material.Ground,
			CanCollide = false,
		})
	end
end

----------------------------------------------------------------
-- Jungle trees & undergrowth (kept away from the path corridor)
----------------------------------------------------------------
local function nearPath(x, z)
	for i = 1, #pathPoints - 1 do
		local a = pathPoints[i]
		local b = pathPoints[i + 1]
		local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local t = math.clamp(((x - a.X) * ab.X + (z - a.Z) * ab.Z) / math.max(ab.Magnitude ^ 2, 0.01), 0, 1)
		local px = a.X + ab.X * t
		local pz = a.Z + ab.Z * t
		if (Vector3.new(x - px, 0, z - pz)).Magnitude < 14 then
			return true
		end
	end
	return false
end

local function inRiver(z)
	return z > Map.RiverNearZ - 8 and z < Map.RiverFarZ + 8
end

local function inVillage(x, z)
	return math.abs(x) < 34 and z > 138 and z < 195
end

local function nearGreatTree(x, z)
	return (Vector3.new(x - Map.TreePosition.X, 0, z - Map.TreePosition.Z)).Magnitude < Map.ClimbRadius + 16
end

for _ = 1, 110 do
	local x = rng:NextNumber(-88, 88)
	local z = rng:NextNumber(-60, 470)
	if not nearPath(x, z) and not inRiver(z) and not inVillage(x, z) and not nearGreatTree(x, z) then
		makeTree(x, z, rng:NextNumber(0.7, 1.9))
	end
end

for _ = 1, 30 do
	local x = rng:NextNumber(-80, 80)
	local z = rng:NextNumber(-50, 460)
	if not nearPath(x, z) and not inRiver(z) and not inVillage(x, z) and not nearGreatTree(x, z) then
		makeGlowMushroom(x, z)
	end
end

for _ = 1, 14 do
	local x = rng:NextNumber(-70, 70)
	local z = rng:NextNumber(-40, 450)
	if not inRiver(z) then
		makeFireflies(Vector3.new(x, Map.GroundY + rng:NextNumber(3, 8), z))
	end
end

----------------------------------------------------------------
-- The animal village
----------------------------------------------------------------
local function makeHut(x, z, wallColor)
	local wall = makePart({
		Name = "HutWall",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(8, 12, 12),
		CFrame = CFrame.new(x, Map.GroundY + 4, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = wallColor,
		Material = Enum.Material.Wood,
	})
	makePart({
		Name = "HutRoof",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(15, 8, 15),
		CFrame = CFrame.new(x, Map.GroundY + 9.5, z),
		Color = Color3.fromRGB(120, 160, 70),
		Material = Enum.Material.Grass,
	})
	-- doorway
	makePart({
		Name = "HutDoor",
		Size = Vector3.new(3.4, 5.5, 1.2),
		CFrame = CFrame.new(x, Map.GroundY + 2.75, z - 5.8),
		Color = Color3.fromRGB(80, 55, 38),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	return wall
end

makeHut(-22, 152, Color3.fromRGB(190, 155, 105))
makeHut(24, 158, Color3.fromRGB(175, 140, 95))
makeHut(-18, 184, Color3.fromRGB(200, 165, 115))
makeHut(22, 186, Color3.fromRGB(185, 150, 100))

-- Village campfire (unlit -- everything is dry!)
makePart({
	Name = "CampfireStones",
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(0.8, 7, 7),
	CFrame = CFrame.new(0, Map.GroundY + 0.4, 170) * CFrame.Angles(0, 0, math.rad(90)),
	Color = Color3.fromRGB(120, 120, 120),
	Material = Enum.Material.Slate,
})

-- Lantern posts
local function makeLantern(x, z)
	makePart({
		Name = "LanternPost",
		Size = Vector3.new(0.8, 7, 0.8),
		CFrame = CFrame.new(x, Map.GroundY + 3.5, z),
		Color = Color3.fromRGB(110, 80, 50),
		Material = Enum.Material.Wood,
	})
	local bulb = makePart({
		Name = "LanternBulb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 1.6, 1.6),
		CFrame = CFrame.new(x, Map.GroundY + 7.3, z),
		Color = Color3.fromRGB(255, 214, 130),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 214, 130)
	light.Range = 16
	light.Brightness = 1.2
	light.Parent = bulb
end
makeLantern(-8, 146)
makeLantern(10, 178)
makeLantern(-12, 176)

----------------------------------------------------------------
-- The bridge (broken + fixed versions; StoryServer swaps them)
----------------------------------------------------------------
local bridgeFolder = Instance.new("Folder")
bridgeFolder.Name = "Bridge"
bridgeFolder.Parent = mapFolder

local brokenFolder = Instance.new("Folder")
brokenFolder.Name = "Broken"
brokenFolder.Parent = bridgeFolder

local fixedFolder = Instance.new("Folder")
fixedFolder.Name = "Fixed"
fixedFolder.Parent = bridgeFolder

-- Broken: a couple of sad, tilted planks poking out of each bank
makePart({
	Name = "BrokenPlankA",
	Size = Vector3.new(6, 0.8, 10),
	CFrame = CFrame.new(-2, Map.GroundY - 0.5, Map.RiverNearZ + 4) * CFrame.Angles(math.rad(-25), math.rad(8), 0),
	Color = Color3.fromRGB(150, 110, 70),
	Material = Enum.Material.WoodPlanks,
}, brokenFolder)
makePart({
	Name = "BrokenPlankB",
	Size = Vector3.new(6, 0.8, 8),
	CFrame = CFrame.new(3, Map.GroundY - 0.8, Map.RiverFarZ - 3) * CFrame.Angles(math.rad(30), math.rad(-10), 0),
	Color = Color3.fromRGB(150, 110, 70),
	Material = Enum.Material.WoodPlanks,
}, brokenFolder)
-- Broken support posts
makePart({
	Name = "BridgePostNear",
	Size = Vector3.new(1.2, 6, 1.2),
	CFrame = CFrame.new(-5, Map.GroundY + 2, Map.RiverNearZ - 1),
	Color = Color3.fromRGB(110, 80, 50),
	Material = Enum.Material.Wood,
}, brokenFolder)

-- Fixed: a proper plank bridge with rope rails (hidden until repaired)
local riverSpan = (Map.RiverFarZ - Map.RiverNearZ) + 10
makePart({
	Name = "BridgeDeck",
	Size = Vector3.new(8, 0.9, riverSpan),
	CFrame = CFrame.new(0, Map.GroundY + 0.6, riverMidZ),
	Color = Color3.fromRGB(160, 118, 74),
	Material = Enum.Material.WoodPlanks,
}, fixedFolder)
for side = -1, 1, 2 do
	makePart({
		Name = "BridgeRail",
		Size = Vector3.new(0.5, 0.5, riverSpan),
		CFrame = CFrame.new(3.8 * side, Map.GroundY + 3.4, riverMidZ),
		Color = Color3.fromRGB(190, 170, 120),
		Material = Enum.Material.Fabric,
		CanCollide = false,
	}, fixedFolder)
	for i = 0, 4 do
		makePart({
			Name = "BridgeRailPost",
			Size = Vector3.new(0.7, 3.4, 0.7),
			CFrame = CFrame.new(3.8 * side, Map.GroundY + 2.2, Map.RiverNearZ - 4 + i * (riverSpan - 2) / 4),
			Color = Color3.fromRGB(120, 88, 55),
			Material = Enum.Material.Wood,
			CanCollide = false,
		}, fixedFolder)
	end
end

-- Hide the fixed bridge until the story repairs it
for _, part in ipairs(fixedFolder:GetDescendants()) do
	if part:IsA("BasePart") then
		part.Transparency = 1
		part.CanCollide = false
	end
end

----------------------------------------------------------------
-- The Great Kapok Tree + spiral climb
----------------------------------------------------------------
local treePos = Map.TreePosition

-- Trunk
makePart({
	Name = "GreatTreeTrunk",
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(Map.TreeHeight + 14, Map.TreeRadius * 2, Map.TreeRadius * 2),
	CFrame = CFrame.new(treePos.X, Map.GroundY + (Map.TreeHeight + 14) / 2 - 4, treePos.Z) * CFrame.Angles(0, 0, math.rad(90)),
	Color = Color3.fromRGB(96, 66, 44),
	Material = Enum.Material.Wood,
})
-- Root flare
for i = 1, 7 do
	local angle = (i / 7) * math.pi * 2
	makePart({
		Name = "GreatTreeRoot",
		Size = Vector3.new(4, 5, 14),
		CFrame = CFrame.new(
			treePos.X + math.cos(angle) * (Map.TreeRadius + 4),
			Map.GroundY + 1.5,
			treePos.Z + math.sin(angle) * (Map.TreeRadius + 4)
		) * CFrame.Angles(0, -angle + math.pi / 2, math.rad(12)),
		Color = Color3.fromRGB(88, 60, 40),
		Material = Enum.Material.Wood,
	})
end
-- Canopy
for i = 1, 9 do
	local angle = rng:NextNumber(0, math.pi * 2)
	local dist = rng:NextNumber(0, 16)
	makePart({
		Name = "GreatTreeCanopy",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1, 1, 1) * rng:NextNumber(18, 30),
		CFrame = CFrame.new(
			treePos.X + math.cos(angle) * dist,
			Map.GroundY + Map.TreeHeight + 10 + rng:NextNumber(-4, 8),
			treePos.Z + math.sin(angle) * dist
		),
		Color = pickGreen(),
		Material = Enum.Material.Grass,
		CanCollide = false,
	})
end

-- Spiral of branch platforms up the trunk
local platformY = Map.GroundY + 7
local angle = math.pi -- start on the path side (facing -Z)
local step = 0
while platformY < Map.TopPlatformY - 4 do
	local px = treePos.X + math.cos(angle) * Map.ClimbRadius
	local pz = treePos.Z + math.sin(angle) * Map.ClimbRadius
	makePart({
		Name = "BranchPlatform" .. step,
		Size = Vector3.new(9, 1.4, 9),
		CFrame = CFrame.new(px, platformY, pz) * CFrame.Angles(0, -angle, 0),
		Color = Color3.fromRGB(104, 72, 48),
		Material = Enum.Material.Wood,
	})
	-- a leafy tuft on every other platform for charm
	if step % 2 == 0 then
		makePart({
			Name = "BranchLeaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(4, 2.5, 4),
			CFrame = CFrame.new(px + 3.2, platformY + 1.6, pz),
			Color = pickGreen(),
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end
	platformY = platformY + 5.5
	angle = angle + 0.5
	step = step + 1
end

-- First platform is reachable from a root ramp
makePart({
	Name = "TreeRamp",
	Size = Vector3.new(8, 1, 22),
	CFrame = CFrame.new(treePos.X + math.cos(math.pi) * Map.ClimbRadius, Map.GroundY + 3.5, treePos.Z + math.sin(math.pi) * Map.ClimbRadius - 9)
		* CFrame.Angles(math.rad(-18), 0, 0),
	Color = Color3.fromRGB(104, 72, 48),
	Material = Enum.Material.Wood,
})

-- Tree-top platform where the Rain Flower lives
makePart({
	Name = "TreeTopPlatform",
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(2, 26, 26),
	CFrame = CFrame.new(treePos.X, Map.TopPlatformY, treePos.Z) * CFrame.Angles(0, 0, math.rad(90)),
	Color = Color3.fromRGB(114, 82, 54),
	Material = Enum.Material.Wood,
})
-- Silver-leaf nest around the top
for i = 1, 8 do
	local a = (i / 8) * math.pi * 2
	makePart({
		Name = "SilverLeaf",
		Size = Vector3.new(5, 0.5, 8),
		CFrame = CFrame.new(
			treePos.X + math.cos(a) * 11,
			Map.TopPlatformY + 1.4,
			treePos.Z + math.sin(a) * 11
		) * CFrame.Angles(math.rad(-14), -a + math.pi / 2, 0),
		Color = Color3.fromRGB(196, 220, 200),
		Material = Enum.Material.Grass,
		CanCollide = false,
	})
end

mapFolder.Parent = Workspace
print("[WorldBuilder] Rainforest built.")
