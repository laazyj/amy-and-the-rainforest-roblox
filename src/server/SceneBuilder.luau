--!strict
--[[
	SceneBuilder: builds the Scenes out of parts from their data in
	src/content/scenes, styled after the hand-drawn hero illustration on
	Clara's story page:

	  * a cream sky with little black birds and outline clouds
	  * a wide field of scribbly green grass
	  * Amy's house and garden (with the gate Sam guards) and a village
	  * the rain forest as a LOOMING WALL of giant brown trunks standing
	    shoulder to shoulder, topped with big round two-tone canopies,
	    bird nests and eggs -- with one narrow gap, just Amy's size
	  * beyond the wall: the parallel-world paradise, in the site's
	    palette (moss, gold, bubblegum pink, grape purple)

	The layout is seeded, so every server builds the same world: the
	random calls below must stay in this order.

	`build` makes the map (SceneServer.server.luau runs it); `buildZones`
	makes the invisible Zone boxes the Story listens to (StoryHost runs it).
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Content = ReplicatedStorage:WaitForChild("content")
local Scenes = Content:WaitForChild("scenes")
local Story = require(ReplicatedStorage:WaitForChild("core"):WaitForChild("Story"))
local StoryContent = require(Content:WaitForChild("Story"))
local palette = require(Content:WaitForChild("palette"))
local Field = require(Scenes:WaitForChild("Field"))
local ForestWall = require(Scenes:WaitForChild("ForestWall"))
local Garden = require(Scenes:WaitForChild("Garden"))
local HeartGlade = require(Scenes:WaitForChild("HeartGlade"))
local Paradise = require(Scenes:WaitForChild("Paradise"))
local Village = require(Scenes:WaitForChild("Village"))
local Convert = require(script.Parent.Convert)
local Parts = require(script.Parent.Parts)

local colour = Convert.colour

local SceneBuilder = {}

local SEED = 20260702 -- deterministic layout
local TRUNK_DIAMETER = 13
local TRUNK_HEIGHT = 42

-- Builds the map in a RainforestMap folder in Workspace.
function SceneBuilder.build()
	local rng = Random.new(SEED)
	local story = StoryContent.story

	local mapFolder = Instance.new("Folder")
	mapFolder.Name = "RainforestMap"

	----------------------------------------------------------------
	-- Palette (from the website's story page)
	----------------------------------------------------------------
	local colours = palette.colours
	local MOSS = colour(colours.moss)
	local BARK = colour(colours.bark)
	local GOLD = colour(colours.gold)
	local BUBBLEGUM = colour(colours.bubblegum)
	local GRAPE = colour(colours.grape)
	local GRASS_GREEN = colour(colours.grassGreen)
	local GRASS_LIGHT = colour(colours.grassLight)
	local CANOPY_DARK = colour(colours.canopyDark)
	local CANOPY_LIGHT = colour(colours.canopyLight)

	local groundY = Field.ground.y
	local forestWallZ = ForestWall.z

	----------------------------------------------------------------
	-- Helpers
	----------------------------------------------------------------
	local function makePart(props: { [string]: any }, parent: Instance?): Part
		return Parts.make("Part", props, parent or mapFolder)
	end

	local function makeWedge(props: { [string]: any }, parent: Instance?): WedgePart
		return Parts.make("WedgePart", props, parent or mapFolder)
	end

	local function makeFireflies(position: Vector3, color: Color3)
		local holder = makePart({
			Name = "FireflyHolder",
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(position),
			Transparency = 1,
			CanCollide = false,
		})
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(color)
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
	local sky = palette.sky
	Lighting.ClockTime = sky.clockTime
	Lighting.Brightness = sky.brightness
	Lighting.Ambient = colour(sky.ambient)
	Lighting.OutdoorAmbient = colour(sky.outdoorAmbient)
	Lighting.FogColor = colour(sky.fog)
	Lighting.FogEnd = sky.fogEnd

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = sky.atmosphere.density
	atmosphere.Color = colour(sky.atmosphere.colour)
	atmosphere.Haze = sky.atmosphere.haze
	atmosphere.Parent = Lighting

	----------------------------------------------------------------
	-- Ground
	----------------------------------------------------------------
	local WORLD_START_Z = Field.ground.startZ
	local WORLD_END_Z = Paradise.endZ
	local HALF_WIDTH = Field.ground.halfWidth
	local WIDTH = HALF_WIDTH * 2

	-- Home-and-field side: the drawing's flat green grass
	local fieldLength = forestWallZ - WORLD_START_Z
	makePart({
		Name = "GroundField",
		Size = Vector3.new(WIDTH, 4, fieldLength),
		CFrame = CFrame.new(0, groundY - 2, WORLD_START_Z + fieldLength / 2),
		Color = GRASS_GREEN,
		Material = Enum.Material.Grass,
	})

	-- Paradise side: a touch lighter and springier
	local paradiseLength = WORLD_END_Z - forestWallZ
	makePart({
		Name = "GroundParadise",
		Size = Vector3.new(WIDTH, 4, paradiseLength),
		CFrame = CFrame.new(0, groundY - 2, forestWallZ + paradiseLength / 2),
		Color = GRASS_LIGHT,
		Material = Enum.Material.Grass,
	})

	-- Invisible walls around the whole map
	local function makeWall(cframe: CFrame, size: Vector3)
		makePart({ Name = "BoundaryWall", Size = size, CFrame = cframe, Transparency = 1 })
	end
	local midZ = (WORLD_START_Z + WORLD_END_Z) / 2
	local totalLength = WORLD_END_Z - WORLD_START_Z
	makeWall(CFrame.new(-HALF_WIDTH, 40, midZ), Vector3.new(4, 100, totalLength))
	makeWall(CFrame.new(HALF_WIDTH, 40, midZ), Vector3.new(4, 100, totalLength))
	makeWall(CFrame.new(0, 40, WORLD_START_Z), Vector3.new(WIDTH, 100, 4))
	makeWall(CFrame.new(0, 40, WORLD_END_Z), Vector3.new(WIDTH, 100, 4))

	----------------------------------------------------------------
	-- Scribbly grass + field flowers (the drawing's pen strokes)
	----------------------------------------------------------------
	local function makeGrassTuft(x: number, z: number, side: "field" | "paradise")
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
				CFrame = CFrame.new(x + rng:NextNumber(-0.8, 0.8), groundY + height / 2, z + rng:NextNumber(-0.8, 0.8))
					* CFrame.Angles(
						rng:NextNumber(-0.15, 0.15),
						rng:NextNumber(0, math.pi),
						rng:NextNumber(-0.25, 0.25)
					),
				Color = shade,
				Material = Enum.Material.Grass,
				CanCollide = false,
			})
		end
	end

	for _ = 1, Field.grassTufts do
		makeGrassTuft(rng:NextNumber(-90, 90), rng:NextNumber(-60, forestWallZ - 8), "field")
	end
	for _ = 1, Paradise.grassTufts do
		makeGrassTuft(rng:NextNumber(-90, 90), rng:NextNumber(forestWallZ + 10, WORLD_END_Z - 10), "paradise")
	end

	-- A few little gold and red flowers dotting the field (site accents)
	for _ = 1, Field.flowers.count do
		local x = rng:NextNumber(-85, 85)
		local z = rng:NextNumber(-55, forestWallZ - 12)
		local color
		if rng:NextNumber() < 0.5 then
			color = colour(Field.flowers.colours[1])
		else
			color = colour(Field.flowers.colours[2])
		end
		makePart({
			Name = "FieldFlower",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.9, 0.7, 0.9),
			CFrame = CFrame.new(x, groundY + 1.1, z),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
		makePart({
			Name = "FieldFlowerStem",
			Size = Vector3.new(0.2, 1, 0.2),
			CFrame = CFrame.new(x, groundY + 0.5, z),
			Color = MOSS,
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end

	----------------------------------------------------------------
	-- Birds and clouds in the cream sky (like the drawing)
	----------------------------------------------------------------
	local function makeBird(position: Vector3, scale: number)
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

	for _, bird in Field.birds do
		makeBird(Convert.vector(bird.at), bird.scale)
	end

	local function makeCloud(position: Vector3, scale: number)
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

	for _, cloud in Field.clouds do
		makeCloud(Convert.vector(cloud.at), cloud.scale)
	end

	----------------------------------------------------------------
	-- Amy's house and garden
	----------------------------------------------------------------
	type House = { at: Story.Vec3, walls: Story.RGB, roof: Story.RGB, scale: number }

	local function makeHouse(house: House, parent: Instance)
		local x, z, scale = house.at.x, house.at.z, house.scale
		local w = 20 * scale
		local d = 14 * scale
		local h = 10 * scale
		-- walls
		makePart({
			Name = "HouseWalls",
			Size = Vector3.new(w, h, d),
			CFrame = CFrame.new(x, groundY + h / 2, z),
			Color = colour(house.walls),
			Material = Enum.Material.SmoothPlastic,
		}, parent)
		-- pitched roof from two wedges
		for side = -1, 1, 2 do
			makeWedge({
				Name = "HouseRoof",
				Size = Vector3.new(w + 2 * scale, 5 * scale, (d + 2 * scale) / 2),
				CFrame = CFrame.new(x, groundY + h + 2.5 * scale, z + side * (d + 2 * scale) / 4)
					* CFrame.Angles(0, if side == 1 then math.pi else 0, 0),
				Color = colour(house.roof),
				Material = Enum.Material.Wood,
			}, parent)
		end
		-- door (facing +Z, toward the field)
		makePart({
			Name = "HouseDoor",
			Size = Vector3.new(3.4 * scale, 6 * scale, 0.6),
			CFrame = CFrame.new(x, groundY + 3 * scale, z + d / 2 + 0.2),
			Color = BARK,
			Material = Enum.Material.Wood,
			CanCollide = false,
		}, parent)
		-- windows
		for side = -1, 1, 2 do
			makePart({
				Name = "HouseWindow",
				Size = Vector3.new(3 * scale, 3 * scale, 0.6),
				CFrame = CFrame.new(x + side * w / 3.2, groundY + 5.5 * scale, z + d / 2 + 0.2),
				Color = Color3.fromRGB(200, 226, 235),
				Material = Enum.Material.Glass,
				CanCollide = false,
			}, parent)
		end
	end

	-- Amy's house: red like her jumper in the drawing
	makeHouse(Garden.house, mapFolder)

	-- Garden fence with a gate opening at the front
	local fence = Garden.fence
	local fenceY = groundY + 1.4
	local function fenceRun(x1: number, z1: number, x2: number, z2: number)
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
				CFrame = CFrame.new(p.X, groundY + 1.7, p.Z),
				Color = Color3.fromRGB(150, 116, 78),
				Material = Enum.Material.Wood,
			})
		end
	end

	local halfW, gateHalf, gateZ, backZ = fence.halfWidth, fence.gateHalfWidth, fence.frontZ, fence.backZ
	-- front fence, split around the gate
	fenceRun(-halfW, gateZ, -gateHalf, gateZ)
	fenceRun(gateHalf, gateZ, halfW, gateZ)
	-- sides and back
	fenceRun(-halfW, gateZ, -halfW, backZ)
	fenceRun(halfW, gateZ, halfW, backZ)
	fenceRun(-halfW, backZ, halfW, backZ)

	-- Spawn inside the garden
	local spawnAt = story.spots.AmySpawn.at
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "AmySpawn"
	spawnLocation.Size = Vector3.new(8, 1, 8)
	spawnLocation.CFrame = CFrame.new(spawnAt.x, groundY + 0.5, spawnAt.z)
	spawnLocation.Anchored = true
	spawnLocation.Color = GRASS_LIGHT
	spawnLocation.Material = Enum.Material.Grass
	spawnLocation.Duration = 0
	spawnLocation.Transparency = 1
	spawnLocation.Parent = mapFolder

	----------------------------------------------------------------
	-- The village (a few more little houses behind Amy's)
	----------------------------------------------------------------
	for _, house in Village.houses do
		makeHouse(house, mapFolder)
	end

	----------------------------------------------------------------
	-- The dirt path from the garden gate toward the forest gap
	----------------------------------------------------------------
	local path = Field.path
	for i = 1, #path - 1 do
		local a = Convert.vector(path[i])
		local b = Convert.vector(path[i + 1])
		local mid = (a + b) / 2
		local length = (b - a).Magnitude + 4
		makePart({
			Name = "Path",
			Size = Vector3.new(7, 0.3, length),
			CFrame = CFrame.lookAt(Vector3.new(mid.X, groundY + 0.1, mid.Z), Vector3.new(b.X, groundY + 0.1, b.Z)),
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
	local function makeNest(x: number, y: number, z: number)
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

	local function makeWallTree(x: number, hasNest: boolean)
		local heightJitter = rng:NextNumber(-3, 4)
		local height = TRUNK_HEIGHT + heightJitter
		-- the giant trunk
		makePart({
			Name = "WallTrunk",
			Size = Vector3.new(TRUNK_DIAMETER, height, TRUNK_DIAMETER * 0.85),
			CFrame = CFrame.new(x, groundY + height / 2, forestWallZ),
			Color = Color3.fromRGB(139, 101, 64),
			Material = Enum.Material.Wood,
		})
		-- rounded edges illusion: a slightly darker core cylinder in front
		makePart({
			Name = "WallTrunkBark",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, TRUNK_DIAMETER * 0.55, TRUNK_DIAMETER * 0.55),
			CFrame = CFrame.new(x, groundY + height / 2, forestWallZ - TRUNK_DIAMETER * 0.28)
				* CFrame.Angles(0, 0, math.rad(90)),
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
				CFrame = CFrame.new(
					x + rng:NextNumber(-3, 3),
					groundY + rng:NextNumber(10, 24),
					forestWallZ - TRUNK_DIAMETER * 0.52
				),
				Color = Color3.fromRGB(92, 62, 38),
				Material = Enum.Material.Wood,
				CanCollide = false,
			})
		end
		-- big round two-tone canopy
		local canopyY = groundY + height + 6
		local canopyR = rng:NextNumber(17, 22)
		makePart({
			Name = "WallCanopy",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(canopyR * 2, canopyR * 1.4, canopyR * 1.8),
			CFrame = CFrame.new(x, canopyY, forestWallZ),
			Color = CANOPY_DARK,
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
		makePart({
			Name = "WallCanopyHighlight",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(canopyR * 1.3, canopyR * 0.8, canopyR * 1.1),
			CFrame = CFrame.new(x - canopyR * 0.15, canopyY + canopyR * 0.28, forestWallZ - canopyR * 0.2),
			Color = CANOPY_LIGHT,
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
		if hasNest then
			makeNest(x, canopyY + canopyR * 0.72 + 1, forestWallZ - 2)
		end
	end

	-- Trunks marching out from the central gap to both edges
	local gap = ForestWall.gapHalfWidth
	local firstX = gap + TRUNK_DIAMETER / 2 + 0.5
	local i = 0
	local x = firstX
	while x < HALF_WIDTH + TRUNK_DIAMETER do
		i = i + 1
		makeWallTree(x, table.find(ForestWall.nests.right, i) ~= nil)
		makeWallTree(-x, table.find(ForestWall.nests.left, i) ~= nil)
		x = x + TRUNK_DIAMETER + rng:NextNumber(-0.5, 1)
	end

	-- Above the gap the canopies close over, so the way in feels like a doorway
	makePart({
		Name = "GapArchCanopy",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(26, 18, 22),
		CFrame = CFrame.new(0, groundY + TRUNK_HEIGHT + 8, forestWallZ),
		Color = CANOPY_DARK,
		Material = Enum.Material.Grass,
		CanCollide = false,
	})
	-- Shadowy earth in the gap itself
	makePart({
		Name = "GapFloor",
		Size = Vector3.new(gap * 2, 0.3, TRUNK_DIAMETER + 4),
		CFrame = CFrame.new(0, groundY + 0.12, forestWallZ),
		Color = Color3.fromRGB(70, 84, 52),
		Material = Enum.Material.Ground,
		CanCollide = false,
	})

	----------------------------------------------------------------
	-- THE PARALLEL-WORLD PARADISE (beyond the wall)
	----------------------------------------------------------------
	local leafColours = {}
	for k, leaf in Paradise.leafColours do
		leafColours[k] = colour(leaf)
	end

	local function paradiseLeafColor(): Color3
		return leafColours[rng:NextInteger(1, #leafColours)]
	end

	local function makeParadiseTree(px: number, pz: number, scale: number)
		local trunkHeight = 14 * scale
		makePart({
			Name = "ParadiseTrunk",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(trunkHeight, 2.4 * scale, 2.4 * scale),
			CFrame = CFrame.new(px, groundY + trunkHeight / 2, pz) * CFrame.Angles(0, 0, math.rad(90)),
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
				CFrame = CFrame.new(Vector3.new(px, groundY + trunkHeight, pz) + offset),
				Color = paradiseLeafColor(),
				Material = Enum.Material.Grass,
				CanCollide = false,
			})
		end
	end

	local function makeGlowFlower(px: number, pz: number, big: boolean)
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
			CFrame = CFrame.new(px, groundY + stemH / 2, pz),
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
		makePart({
			Name = "GlowFlowerHead",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.6, 1.1, 1.6) * scale,
			CFrame = CFrame.new(px, groundY + stemH + 0.5 * scale, pz),
			Color = petalColor,
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		local core = makePart({
			Name = "GlowFlowerCore",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.7, 0.7, 0.7) * scale,
			CFrame = CFrame.new(px, groundY + stemH + 0.9 * scale, pz),
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
	end

	local glade = Convert.vector(HeartGlade.centre)
	local homes: { Vector3 } = {}
	for _, character in story.characters do
		if not character.player then
			table.insert(homes, Convert.vector(story.spots[character.home].at))
		end
	end

	local function inParadiseKeepClear(px: number, pz: number): boolean
		-- keep the walking line from the gap to the glade, and the glade
		-- itself, free of trunks
		if math.abs(px) < Paradise.clearPath.halfWidth and pz < Paradise.clearPath.untilZ then
			return true
		end
		if (Vector3.new(px, 0, pz) - Vector3.new(glade.X, 0, glade.Z)).Magnitude < HeartGlade.clearRadius then
			return true
		end
		-- keep breathing room where the animals stand
		for _, home in homes do
			if (Vector3.new(px - home.X, 0, pz - home.Z)).Magnitude < Paradise.clearAroundCharacters then
				return true
			end
		end
		return false
	end

	for _ = 1, Paradise.trees do
		local px = rng:NextNumber(-88, 88)
		local pz = rng:NextNumber(forestWallZ + 18, WORLD_END_Z - 12)
		if not inParadiseKeepClear(px, pz) then
			makeParadiseTree(px, pz, rng:NextNumber(0.7, 1.8))
		end
	end

	for _ = 1, Paradise.glowFlowers do
		local px = rng:NextNumber(-80, 80)
		local pz = rng:NextNumber(forestWallZ + 14, WORLD_END_Z - 14)
		if not inParadiseKeepClear(px, pz) then
			makeGlowFlower(px, pz, false)
		end
	end

	-- A trail of glowing flowers leads from the gap to the heart glade
	local trail = Paradise.trail
	local trailZ = forestWallZ + 14
	while trailZ < trail.untilZ do
		makeGlowFlower(if trailZ % 20 < 10 then trail.offsetX else -trail.offsetX, trailZ, false)
		trailZ = trailZ + trail.stepZ
	end

	-- The heart glade: a ring of big glowing flowers
	for j = 1, HeartGlade.ring.flowers do
		local a = (j / HeartGlade.ring.flowers) * math.pi * 2
		makeGlowFlower(
			glade.X + math.cos(a) * HeartGlade.ring.radius,
			glade.Z + math.sin(a) * HeartGlade.ring.radius,
			true
		)
	end

	-- Shafts of golden light falling through the paradise canopy
	for _ = 1, Paradise.lightShafts do
		local px = rng:NextNumber(-70, 70)
		local pz = rng:NextNumber(forestWallZ + 25, WORLD_END_Z - 30)
		makePart({
			Name = "LightShaft",
			Size = Vector3.new(rng:NextNumber(3, 6), 60, rng:NextNumber(3, 6)),
			CFrame = CFrame.new(px, groundY + 30, pz) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-6, 6))),
			Color = GOLD,
			Material = Enum.Material.Neon,
			Transparency = 0.82,
			CanCollide = false,
		})
	end

	-- Drifting sparkles everywhere in the paradise
	local sparkles = Paradise.sparkles
	for _ = 1, sparkles.count do
		local px = rng:NextNumber(-70, 70)
		local pz = rng:NextNumber(forestWallZ + 15, WORLD_END_Z - 15)
		local roll = rng:NextNumber()
		local color
		if roll < 0.34 then
			color = sparkles.colours[1]
		elseif roll < 0.67 then
			color = sparkles.colours[2]
		else
			color = sparkles.colours[3]
		end
		makeFireflies(Vector3.new(px, groundY + rng:NextNumber(3, 9), pz), colour(color))
	end

	mapFolder.Parent = Workspace
	print("[SceneBuilder] Scenes built: garden, village, field, forest wall, paradise, heart glade.")
end

-- Builds every Zone as an invisible box in a StoryZones folder in
-- Workspace, and returns them by Zone id.
function SceneBuilder.buildZones(story: Story.Story): { [string]: BasePart }
	local folder = Instance.new("Folder")
	folder.Name = "StoryZones"
	folder.Parent = Workspace

	local parts: { [string]: BasePart } = {}
	for id, zone in story.zones do
		local part = Instance.new("Part")
		part.Name = id
		part.Size = Convert.vector(zone.size)
		part.CFrame = CFrame.new(Convert.vector(zone.centre))
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 1
		part.Parent = folder
		parts[id] = part
	end
	return parts
end

return SceneBuilder
