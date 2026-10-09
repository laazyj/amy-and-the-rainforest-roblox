--!nonstrict
-- Legacy untyped code from the proof of concept. The project default is strict
-- (.luaurc); this file opts out until the Checkpoint B restructure gives it
-- types. Under strict mode luau-lsp reports only type-inference errors here,
-- no real bugs; non-strict mode reports nothing.
--[[
	StoryServer
	===========
	The story engine for "Amy and the Rain Forest" (a story by Clara).
	Reads StoryData and runs the game:
	  * builds the characters: Dad, Mum, Sam the dog, and the three
	    parallel-world animals (maroon squirrel, orange fox, golden lion)
	  * creates trigger zones and (if a quest needs them) pickups
	  * walks each player through chapters and quests
	  * Sam drags Amy back when she tries to sneak out
	  * the paradise lights up when she steps through the tree wall
	  * the giant tree-chopping machine arrives for the finale -- and
	    backs down when Amy stands in front of it and explains

	This is a solo, story-driven experience: each player runs through
	the story at their own pace with their own state.

	This is a ModuleScript that the StoryServer Script requires, so that
	the golden walkthrough (tests/engine/walkthrough.luau) can start it in
	a Luau Execution task, where Scripts do not run. It returns the
	handlers the walkthrough's fake player drives (see the end of this file).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local StoryData = require(ReplicatedStorage:WaitForChild("StoryData"))
local Map = StoryData.Map

----------------------------------------------------------------
-- Remotes
----------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "StoryRemotes"

local function makeRemote(name)
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local ShowDialogue = makeRemote("ShowDialogue") -- server -> client (lines)
local DialogueFinished = makeRemote("DialogueFinished") -- client -> server
local SetObjective = makeRemote("SetObjective") -- server -> client (text or nil)
local ShowChapter = makeRemote("ShowChapter") -- server -> client (title, subtitle)
local ShowEnding = makeRemote("ShowEnding") -- server -> client (title, subtitle)
local ClientReady = makeRemote("ClientReady") -- client -> server

remotes.Parent = ReplicatedStorage

-- Every server -> client message goes through send. A real player gets it
-- over the remote. The golden walkthrough replaces it (setSend, at the end of
-- this file), because its fake player is not a Player and FireClient needs one.
local send = function(player, remote, ...)
	remote:FireClient(player, ...)
end

----------------------------------------------------------------
-- Character construction
----------------------------------------------------------------
local npcModels = {} -- id -> Model
local npcPrompts = {} -- id -> ProximityPrompt
local npcHomePivots = {} -- id -> CFrame (so characters can be moved and restored)

local npcFolder = Instance.new("Folder")
npcFolder.Name = "StoryNPCs"
npcFolder.Parent = Workspace

local SKIN = Color3.fromRGB(228, 194, 160)
local HAIR = Color3.fromRGB(94, 64, 44)

local function makeNPCPart(props, model)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = model
	return part
end

local function addNameTag(rootPart, displayName, offsetY)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTag"
	billboard.Size = UDim2.new(0, 170, 0, 30)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, offsetY or 4.4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 60
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = displayName
	label.TextColor3 = Color3.fromRGB(255, 255, 240)
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromRGB(38, 51, 31)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = billboard
	billboard.Parent = rootPart
end

local function baseCFrameFor(def, heightAboveGround)
	local at = Vector3.new(def.position.X, Map.GroundY + heightAboveGround, def.position.Z)
	return CFrame.lookAt(at, at + Vector3.new(0, 0, (def.faceZ or 1) * 10))
end

-- A friendly blocky villager (Dad, Mum, and the crowd in the finale)
local function buildHuman(def)
	local model = Instance.new("Model")
	model.Name = def.id
	local base = baseCFrameFor(def, 2.9)
	local shirt = def.shirt or Color3.fromRGB(120, 120, 140)

	-- legs
	for side = -1, 1, 2 do
		makeNPCPart({
			Name = "Leg",
			Size = Vector3.new(0.9, 2.4, 1),
			CFrame = base * CFrame.new(0.55 * side, -2.1, 0),
			Color = Color3.fromRGB(64, 74, 94),
		}, model)
	end
	-- torso
	local body = makeNPCPart({
		Name = "Body",
		Size = Vector3.new(2.6, 3, 1.5),
		CFrame = base * CFrame.new(0, 0.6, 0),
		Color = shirt,
		CanCollide = true,
	}, model)
	-- arms
	for side = -1, 1, 2 do
		makeNPCPart({
			Name = "Arm",
			Size = Vector3.new(0.8, 2.8, 1),
			CFrame = base * CFrame.new(1.75 * side, 0.5, 0),
			Color = shirt,
		}, model)
		makeNPCPart({
			Name = "Hand",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.8, 0.8, 0.8),
			CFrame = base * CFrame.new(1.75 * side, -1.1, 0),
			Color = SKIN,
		}, model)
	end
	-- head + hair + eyes
	local head = makeNPCPart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.1, 2.1, 2.1),
		CFrame = base * CFrame.new(0, 3, 0),
		Color = SKIN,
	}, model)
	makeNPCPart({
		Name = "Hair",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.25, 1.5, 2.25),
		CFrame = base * CFrame.new(0, 3.55, 0.25),
		Color = HAIR,
	}, model)
	for side = -1, 1, 2 do
		makeNPCPart({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.34, 0.34, 0.34),
			CFrame = base * CFrame.new(0.42 * side, 3.15, -0.92),
			Color = Color3.fromRGB(25, 25, 25),
		}, model)
	end

	addNameTag(head, def.display, 2.6)
	model.PrimaryPart = body
	model.Parent = npcFolder
	return model, body
end

-- A four-legged friend. kind decides colours and signature features.
local function buildAnimal(def)
	local model = Instance.new("Model")
	model.Name = def.id

	local bodyColor, bellyColor, scale, tailStyle
	if def.kind == "dog" then
		bodyColor = Color3.fromRGB(238, 230, 214)
		bellyColor = Color3.fromRGB(150, 110, 74)
		scale = 1.0
		tailStyle = "up"
	elseif def.kind == "squirrel" then
		bodyColor = Color3.fromRGB(128, 32, 48) -- maroon!
		bellyColor = Color3.fromRGB(214, 168, 150)
		scale = 0.55
		tailStyle = "fluff"
	elseif def.kind == "fox" then
		bodyColor = Color3.fromRGB(240, 120, 32) -- the orangest orange
		bellyColor = Color3.fromRGB(248, 240, 226)
		scale = 0.85
		tailStyle = "brush"
	else -- lion
		bodyColor = Color3.fromRGB(226, 178, 68) -- golden
		bellyColor = Color3.fromRGB(240, 214, 150)
		scale = 1.5
		tailStyle = "tuft"
	end

	local bodyLift = 1.6 * scale + 0.6
	local base = baseCFrameFor(def, bodyLift)

	-- body (horizontal)
	local body = makeNPCPart({
		Name = "Body",
		Size = Vector3.new(2 * scale, 1.8 * scale, 3.6 * scale),
		CFrame = base,
		Color = bodyColor,
		CanCollide = true,
	}, model)
	-- belly / chest patch
	makeNPCPart({
		Name = "Chest",
		Size = Vector3.new(1.4 * scale, 1.2 * scale, 0.5 * scale),
		CFrame = base * CFrame.new(0, -0.2 * scale, -1.7 * scale),
		Color = bellyColor,
	}, model)
	-- legs
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			makeNPCPart({
				Name = "Leg",
				Size = Vector3.new(0.6 * scale, 1.5 * scale, 0.6 * scale),
				CFrame = base * CFrame.new(0.6 * sx * scale, -1.5 * scale, 1.2 * sz * scale),
				Color = bodyColor,
			}, model)
		end
	end
	-- head
	local head = makeNPCPart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.9, 1.9, 1.9) * scale,
		CFrame = base * CFrame.new(0, 1.3 * scale, -2 * scale),
		Color = bodyColor,
	}, model)
	-- eyes
	for side = -1, 1, 2 do
		makeNPCPart({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.32, 0.32, 0.32) * scale,
			CFrame = base * CFrame.new(0.4 * side * scale, 1.5 * scale, -2.8 * scale),
			Color = Color3.fromRGB(25, 25, 25),
		}, model)
	end
	-- snout
	makeNPCPart({
		Name = "Snout",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.8, 0.6, 0.9) * scale,
		CFrame = base * CFrame.new(0, 1.1 * scale, -2.85 * scale),
		Color = bellyColor,
	}, model)
	makeNPCPart({
		Name = "Nose",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.3, 0.3, 0.3) * scale,
		CFrame = base * CFrame.new(0, 1.15 * scale, -3.3 * scale),
		Color = Color3.fromRGB(30, 26, 26),
	}, model)
	-- ears
	local earShape
	if def.kind == "dog" then
		earShape = Vector3.new(0.5, 1.1, 0.3) -- floppy
	elseif def.kind == "lion" then
		earShape = Vector3.new(0.55, 0.55, 0.3) -- little and round
	else
		earShape = Vector3.new(0.45, 0.8, 0.3) -- pointy-ish
	end
	for side = -1, 1, 2 do
		makeNPCPart({
			Name = "Ear",
			Size = earShape * scale * 1.6,
			CFrame = base
				* CFrame.new(0.6 * side * scale, 2.1 * scale, -1.9 * scale)
				* CFrame.Angles(0, 0, math.rad(def.kind == "dog" and 35 * side or 10 * side)),
			Color = def.kind == "fox" and Color3.fromRGB(40, 36, 36) or bodyColor,
		}, model)
	end
	-- tails
	if tailStyle == "up" then
		makeNPCPart({
			Name = "Tail",
			Size = Vector3.new(0.4, 1.6, 0.4) * scale,
			CFrame = base * CFrame.new(0, 0.9 * scale, 2 * scale) * CFrame.Angles(math.rad(-30), 0, 0),
			Color = bodyColor,
		}, model)
	elseif tailStyle == "fluff" then
		-- the squirrel's giant question-mark tail
		makeNPCPart({
			Name = "Tail",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.4, 2.6, 1.4) * scale,
			CFrame = base * CFrame.new(0, 1.4 * scale, 2.2 * scale),
			Color = bodyColor,
		}, model)
		makeNPCPart({
			Name = "TailTip",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1, 1.2, 1) * scale,
			CFrame = base * CFrame.new(0, 2.8 * scale, 1.6 * scale),
			Color = bodyColor,
		}, model)
	elseif tailStyle == "brush" then
		makeNPCPart({
			Name = "Tail",
			Size = Vector3.new(0.8, 0.8, 2.4) * scale,
			CFrame = base * CFrame.new(0, 0.4 * scale, 2.8 * scale) * CFrame.Angles(math.rad(18), 0, 0),
			Color = bodyColor,
		}, model)
		makeNPCPart({
			Name = "TailTip",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.85, 0.85, 1) * scale,
			CFrame = base * CFrame.new(0, 0.75 * scale, 3.9 * scale),
			Color = Color3.fromRGB(248, 240, 226), -- white tip
		}, model)
	else -- tuft
		makeNPCPart({
			Name = "Tail",
			Size = Vector3.new(0.35, 0.35, 2.6) * scale,
			CFrame = base * CFrame.new(0, 0.5 * scale, 2.9 * scale) * CFrame.Angles(math.rad(12), 0, 0),
			Color = bodyColor,
		}, model)
		makeNPCPart({
			Name = "TailTuft",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.7, 0.7, 0.7) * scale,
			CFrame = base * CFrame.new(0, 0.8 * scale, 4.1 * scale),
			Color = Color3.fromRGB(150, 96, 40),
		}, model)
	end
	-- the lion's magnificent mane
	if def.kind == "lion" then
		makeNPCPart({
			Name = "Mane",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.9, 2.9, 2.2) * scale,
			CFrame = base * CFrame.new(0, 1.3 * scale, -1.55 * scale),
			Color = Color3.fromRGB(168, 108, 40),
			Material = Enum.Material.Grass,
		}, model)
	end

	addNameTag(head, def.display, def.kind == "lion" and 4.6 or 3.2)
	model.PrimaryPart = body
	model.Parent = npcFolder
	return model, body
end

for _, def in ipairs(StoryData.NPCs) do
	local model, promptPart
	if def.kind == "human" then
		model, promptPart = buildHuman(def)
	else
		model, promptPart = buildAnimal(def)
	end
	npcModels[def.id] = model
	npcHomePivots[def.id] = model:GetPivot()

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TalkPrompt"
	prompt.ActionText = "Talk"
	prompt.ObjectText = def.display
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = promptPart
	npcPrompts[def.id] = prompt
end

----------------------------------------------------------------
-- Trigger zones
----------------------------------------------------------------
local zoneParts = {} -- name -> Part
local zoneFolder = Instance.new("Folder")
zoneFolder.Name = "StoryZones"
zoneFolder.Parent = Workspace

for _, zoneDef in ipairs(StoryData.Zones) do
	local part = Instance.new("Part")
	part.Name = zoneDef.name
	part.Size = zoneDef.size
	part.CFrame = CFrame.new(zoneDef.position)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = zoneFolder
	zoneParts[zoneDef.name] = part
end

----------------------------------------------------------------
-- Per-player story state
----------------------------------------------------------------
local playerStates = {} -- player -> state table

local function getState(player)
	return playerStates[player]
end

local function currentQuest(state)
	local chapter = StoryData.Chapters[state.chapterIndex]
	if not chapter then
		return nil, nil
	end
	return chapter.quests[state.questIndex], chapter
end

-- Blocking dialogue: sends lines to the client, waits until the player
-- has clicked through them all.
local function playDialogue(player, lines)
	local state = getState(player)
	if not state or not lines or #lines == 0 then
		return
	end
	state.dialogueDone = false
	send(player, ShowDialogue, lines)
	local waited = 0
	while playerStates[player] and not state.dialogueDone and waited < 300 do
		waited = waited + task.wait(0.1)
	end
end

local function onDialogueFinished(player)
	local state = getState(player)
	if state then
		state.dialogueDone = true
	end
end

DialogueFinished.OnServerEvent:Connect(onDialogueFinished)

----------------------------------------------------------------
-- Pickups (collect quests -- none in the base story, but the
-- engine keeps supporting them so new chapters can use them)
----------------------------------------------------------------
local activePickups = {} -- part -> {player=..., quest=...}

local pickupFolder = Instance.new("Folder")
pickupFolder.Name = "StoryPickups"
pickupFolder.Parent = Workspace

local function makePickup(quest, position, player)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Name = "Pickup"
	part.Size = Vector3.new(2.4, 0.6, 2.4)
	part.Color = Color3.fromRGB(255, 130, 190)
	part.Material = Enum.Material.Neon
	part.CFrame = CFrame.new(position.X, Map.GroundY + 2.2, position.Z)

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 170, 220))
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new(0.5)
	sparkle.Lifetime = NumberRange.new(0.8, 1.6)
	sparkle.Rate = 6
	sparkle.Speed = NumberRange.new(0.5, 1)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Parent = part

	activePickups[part] = { player = player, quest = quest }
	part.Parent = pickupFolder
	return part
end

task.spawn(function()
	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t = t + dt
		for part in pairs(activePickups) do
			if part.Parent then
				local baseY = part:GetAttribute("BaseY")
				if not baseY then
					baseY = part.Position.Y
					part:SetAttribute("BaseY", baseY)
				end
				part.CFrame = CFrame.new(part.Position.X, baseY + math.sin(t * 2) * 0.5, part.Position.Z)
					* CFrame.Angles(0, t * 1.2, 0)
			end
		end
	end)
end)

----------------------------------------------------------------
-- The giant tree-chopping machine (built for the finale)
----------------------------------------------------------------
local machineModel = nil
local machineBladeModel = nil
local machineBladeBase = nil
local machineSpinning = false
local machineSmoke = nil
local villagerModels = {}

local function buildMachine()
	if machineModel then
		return
	end
	local pos = Map.MachinePosition
	local model = Instance.new("Model")
	model.Name = "TreeChoppingMachine"

	local METAL = Color3.fromRGB(74, 78, 84)
	local METAL_DARK = Color3.fromRGB(52, 54, 58)
	local WARN_GOLD = Color3.fromRGB(231, 181, 58)

	local function machinePart(props, parent)
		local part = Instance.new("Part")
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		for key, value in pairs(props) do
			part[key] = value
		end
		part.Parent = parent or model
		return part
	end

	-- hull (facing +Z, toward the forest)
	local hull = machinePart({
		Name = "Hull",
		Size = Vector3.new(12, 8, 16),
		CFrame = CFrame.new(pos.X, Map.GroundY + 6, pos.Z),
		Color = METAL,
		Material = Enum.Material.DiamondPlate,
	})
	-- cab on top
	machinePart({
		Name = "Cab",
		Size = Vector3.new(8, 5, 6),
		CFrame = CFrame.new(pos.X, Map.GroundY + 12.5, pos.Z - 3),
		Color = METAL_DARK,
		Material = Enum.Material.Metal,
	})
	machinePart({
		Name = "CabWindow",
		Size = Vector3.new(6.5, 3, 0.5),
		CFrame = CFrame.new(pos.X, Map.GroundY + 12.8, pos.Z + 0.2),
		Color = Color3.fromRGB(160, 200, 210),
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		CanCollide = false,
	})
	-- warning stripes across the front
	for k = 0, 3 do
		machinePart({
			Name = "WarnStripe",
			Size = Vector3.new(1.6, 1.2, 0.4),
			CFrame = CFrame.new(pos.X - 4.5 + k * 3, Map.GroundY + 3, pos.Z + 8.1),
			Color = k % 2 == 0 and WARN_GOLD or METAL_DARK,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
	end
	-- wheels
	for sx = -1, 1, 2 do
		for _, wz in ipairs({ -5, 5 }) do
			machinePart({
				Name = "Wheel",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(2.4, 5.5, 5.5),
				CFrame = CFrame.new(pos.X + sx * 7, Map.GroundY + 2.75, pos.Z + wz) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(30, 30, 32),
				Material = Enum.Material.SmoothPlastic,
			})
		end
	end
	-- chimney + smoke
	local chimney = machinePart({
		Name = "Chimney",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6, 1.8, 1.8),
		CFrame = CFrame.new(pos.X + 4, Map.GroundY + 13, pos.Z - 6) * CFrame.Angles(0, 0, math.rad(90)),
		Color = METAL_DARK,
		Material = Enum.Material.Metal,
	})
	machineSmoke = Instance.new("ParticleEmitter")
	machineSmoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	machineSmoke.Color = ColorSequence.new(Color3.fromRGB(90, 90, 90))
	machineSmoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, 6),
	})
	machineSmoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	machineSmoke.Lifetime = NumberRange.new(2, 3.5)
	machineSmoke.Rate = 12
	machineSmoke.Speed = NumberRange.new(6, 9)
	machineSmoke.EmissionDirection = Enum.NormalId.Right
	machineSmoke.Parent = chimney

	-- THE BLADE: a giant circular saw on the front
	local bladeModel = Instance.new("Model")
	bladeModel.Name = "Blade"
	local bladeCenter = CFrame.new(pos.X, Map.GroundY + 6.5, pos.Z + 9.5)
	local hub = machinePart({
		Name = "BladeHub",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.4, 3, 3),
		CFrame = bladeCenter * CFrame.Angles(0, math.rad(90), 0),
		Color = METAL_DARK,
		Material = Enum.Material.Metal,
		CanCollide = false,
	}, bladeModel)
	machinePart({
		Name = "BladeDisc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 11, 11),
		CFrame = bladeCenter * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(168, 172, 178),
		Material = Enum.Material.Metal,
		CanCollide = false,
	}, bladeModel)
	-- radial teeth marks so the spin reads clearly
	for k = 0, 5 do
		local a = (k / 6) * math.pi * 2
		machinePart({
			Name = "BladeTooth",
			Size = Vector3.new(1.1, 4.6, 0.5),
			CFrame = bladeCenter * CFrame.Angles(0, 0, a) * CFrame.new(0, 3.6, -0.5),
			Color = METAL_DARK,
			Material = Enum.Material.Metal,
			CanCollide = false,
		}, bladeModel)
	end
	bladeModel.PrimaryPart = hub
	bladeModel.Parent = model

	model.PrimaryPart = hull
	model.Parent = Workspace

	machineModel = model
	machineBladeModel = bladeModel
	machineBladeBase = bladeModel:GetPivot()
	machineSpinning = true

	-- spin the blade until the story stops it
	task.spawn(function()
		local angle = 0
		while machineModel do
			if machineSpinning then
				-- the hub cylinder's axis (its local X) points at the forest,
				-- so spinning about local X turns the disc in its own plane
				angle = angle + 0.18
				machineBladeModel:PivotTo(machineBladeBase * CFrame.Angles(angle, 0, 0))
			end
			task.wait(0.03)
		end
	end)
end

local VILLAGER_SHIRTS = {
	Color3.fromRGB(180, 120, 70),
	Color3.fromRGB(96, 130, 170),
	Color3.fromRGB(170, 96, 96),
	Color3.fromRGB(120, 150, 96),
}

local function buildVillagers()
	if #villagerModels > 0 then
		return
	end
	local spots = {
		{ x = -14, z = 84 },
		{ x = -5, z = 80 },
		{ x = 6, z = 81 },
		{ x = 15, z = 85 },
	}
	for k, spot in ipairs(spots) do
		local def = {
			id = "Villager" .. k,
			display = "Villager",
			kind = "human",
			shirt = VILLAGER_SHIRTS[k],
			position = Vector3.new(spot.x, 0, spot.z),
			faceZ = 1,
		}
		local model = buildHuman(def)
		table.insert(villagerModels, model)
	end
end

----------------------------------------------------------------
-- World reactions to story progress (hooks receive the player)
----------------------------------------------------------------
local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.Name = "StoryColorGrade"
colorCorrection.Saturation = 0
colorCorrection.Parent = Lighting

local function pivotNPC(id, position, faceZ)
	local model = npcModels[id]
	if model then
		local at = Vector3.new(position.X, position.Y, position.Z)
		model:PivotTo(CFrame.lookAt(at, at + Vector3.new(0, 0, (faceZ or 1) * 10)))
	end
end

-- Sam catches Amy at the gate and hauls her back to the garden
local function samCatches(player)
	local character = player.Character
	local samPivotY = npcHomePivots.Sam and npcHomePivots.Sam.Position.Y or 2
	-- Sam bounds over to the gate...
	pivotNPC("Sam", Vector3.new(2, samPivotY, Map.GardenGateZ + 2), -1)
	task.wait(0.5)
	-- ...and both of them end up back in the garden.
	if character then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			root.CFrame = CFrame.lookAt(
				Vector3.new(Map.SpawnPosition.X, Map.GroundY + 3.5, Map.SpawnPosition.Z - 2),
				Vector3.new(Map.SpawnPosition.X, Map.GroundY + 3.5, Map.ForestWallZ)
			)
		end
	end
	pivotNPC("Sam", Vector3.new(3, samPivotY, Map.SpawnPosition.Z + 4), -1)
	task.wait(0.4)
end

-- Sam is off at the farm for chapter 2
local function samGoesToFarm()
	local samPivotY = npcHomePivots.Sam and npcHomePivots.Sam.Position.Y or 2
	pivotNPC("Sam", Vector3.new(80, samPivotY, -58), 1)
end

-- Stepping through the gap: the parallel world turns the colour up
local function paradiseReveal()
	TweenService:Create(colorCorrection, TweenInfo.new(2.5), {
		Saturation = 0.35,
		Contrast = 0.06,
		TintColor = Color3.fromRGB(255, 250, 240),
	}):Play()
end

-- Back home: the ordinary world is a little greyer than she remembered
local function ordinaryWorld()
	TweenService:Create(colorCorrection, TweenInfo.new(2), {
		Saturation = 0,
		Contrast = 0,
		TintColor = Color3.fromRGB(255, 255, 255),
	}):Play()
end

-- The village arrives with the machine (and Dad, Mum and Sam relocate)
local function machineArrives()
	buildMachine()
	buildVillagers()
	local dadY = npcHomePivots.Dad and npcHomePivots.Dad.Position.Y or 3
	local mumY = npcHomePivots.Mum and npcHomePivots.Mum.Position.Y or 3
	local samY = npcHomePivots.Sam and npcHomePivots.Sam.Position.Y or 2
	pivotNPC("Dad", Vector3.new(9, dadY, 108), 1)
	pivotNPC("Mum", Vector3.new(-9, mumY, 106), 1)
	pivotNPC("Sam", Vector3.new(13, samY, 104), 1)
end

-- Amy wins: the blade stops, the smoke dies, the machine backs away
local function machineStops()
	machineSpinning = false
	if machineSmoke then
		machineSmoke.Enabled = false
	end
	-- celebration sparkles over the crowd
	local burstColors = { Color3.fromRGB(255, 93, 162), Color3.fromRGB(231, 181, 58), Color3.fromRGB(124, 77, 255) }
	for k, color in ipairs(burstColors) do
		local holder = Instance.new("Part")
		holder.Anchored = true
		holder.CanCollide = false
		holder.Transparency = 1
		holder.Size = Vector3.new(1, 1, 1)
		holder.CFrame = CFrame.new((k - 2) * 10, Map.GroundY + 12, 100)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(color)
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new(0.7)
		emitter.Lifetime = NumberRange.new(1.5, 2.5)
		emitter.Rate = 40
		emitter.Speed = NumberRange.new(8, 14)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Parent = holder
		holder.Parent = Workspace
		task.delay(6, function()
			holder:Destroy()
		end)
	end
	-- the machine slowly reverses away from the forest
	task.spawn(function()
		if not machineModel then
			return
		end
		local start = machineModel:GetPivot()
		local bladeStart = machineBladeModel and machineBladeModel:GetPivot()
		local distance = 34
		local duration = 6
		local elapsed = 0
		while elapsed < duration and machineModel do
			local dt = task.wait(0.05)
			elapsed = elapsed + dt
			local alpha = math.min(elapsed / duration, 1)
			local offset = Vector3.new(0, 0, -distance * alpha)
			machineModel:PivotTo(start + offset)
			if machineBladeModel and bladeStart then
				machineBladeModel:PivotTo(bladeStart + offset)
			end
		end
	end)
end

local questCompletedHooks = {
	sneak_out_1 = samCatches,
	sneak_out_2 = samCatches,
	enter_forest = paradiseReveal,
	rush_home = ordinaryWorld,
	tell_mum = machineArrives,
	explain = machineStops,
}

local questStartedHooks = {
	walk_to_forest = samGoesToFarm,
}

----------------------------------------------------------------
-- Quest engine
----------------------------------------------------------------
local advanceStory -- forward declaration

local function questObjectiveText(state, quest)
	if quest.type == "collect" then
		return quest.objective .. "  (" .. tostring(state.collected) .. "/" .. tostring(quest.count) .. ")"
	end
	return quest.objective
end

local function startQuest(player, quest)
	local state = getState(player)
	if not state then
		return
	end
	state.collected = 0

	local startHook = questStartedHooks[quest.id]
	if startHook then
		startHook(player)
	end

	send(player, SetObjective, questObjectiveText(state, quest))

	if quest.intro then
		playDialogue(player, quest.intro)
	end

	if quest.type == "talk" then
		local prompt = npcPrompts[quest.npc]
		if prompt then
			if quest.promptText then
				prompt.ActionText = quest.promptText
			else
				prompt.ActionText = "Talk"
			end
			prompt.Enabled = true
		end
	elseif quest.type == "collect" then
		for _, point in ipairs(quest.spawnPoints) do
			makePickup(quest, point, player)
		end
	end
	-- "reach" quests need no setup: the zones are always listening
end

local function completeQuest(player)
	local state = getState(player)
	if not state then
		return
	end
	local quest = currentQuest(state)
	if not quest then
		return
	end

	if quest.type == "talk" then
		local prompt = npcPrompts[quest.npc]
		if prompt then
			prompt.Enabled = false
		end
	end

	if quest.onComplete then
		playDialogue(player, quest.onComplete)
	end

	local hook = questCompletedHooks[quest.id]
	if hook then
		hook(player)
	end

	advanceStory(player)
end

advanceStory = function(player)
	local state = getState(player)
	if not state then
		return
	end

	local chapter = StoryData.Chapters[state.chapterIndex]
	state.questIndex = state.questIndex + 1

	if chapter and state.questIndex > #chapter.quests then
		state.chapterIndex = state.chapterIndex + 1
		state.questIndex = 1
		chapter = StoryData.Chapters[state.chapterIndex]
		if chapter then
			send(player, ShowChapter, chapter.title, chapter.subtitle)
			task.wait(3.2) -- let the title card breathe
		end
	end

	local quest = currentQuest(state)
	if quest then
		startQuest(player, quest)
	else
		-- Story complete!
		send(player, SetObjective, nil)
		playDialogue(player, StoryData.Ending.lines)
		send(player, ShowEnding, StoryData.Ending.title, StoryData.Ending.subtitle)
	end
end

----------------------------------------------------------------
-- Interactions
----------------------------------------------------------------
local function onTalkPromptTriggered(npcId, player)
	local state = getState(player)
	if not state or state.busy then
		return
	end
	local quest = currentQuest(state)
	if quest and quest.type == "talk" and quest.npc == npcId then
		state.busy = true
		npcPrompts[npcId].Enabled = false
		playDialogue(player, quest.dialogue)
		completeQuest(player)
		state.busy = false
	end
end

for npcId, prompt in pairs(npcPrompts) do
	prompt.Triggered:Connect(function(player)
		onTalkPromptTriggered(npcId, player)
	end)
end

-- Pickup touches
pickupFolder.ChildAdded:Connect(function(part)
	part.Touched:Connect(function(hit)
		local character = hit.Parent
		if not character then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		local info = activePickups[part]
		if not info or info.player ~= player then
			return
		end
		local state = getState(player)
		if not state then
			return
		end
		local quest = currentQuest(state)
		if quest ~= info.quest then
			return
		end

		activePickups[part] = nil
		part:Destroy()

		state.collected = state.collected + 1
		send(player, SetObjective, questObjectiveText(state, quest))

		if state.collected >= quest.count and not state.busy then
			state.busy = true
			completeQuest(player)
			state.busy = false
		end
	end)
end)

-- Zone entry
local function tryCompleteReach(player, zoneName)
	local state = getState(player)
	if not state or state.busy then
		return
	end
	local quest = currentQuest(state)
	if quest and quest.type == "reach" and quest.zone == zoneName then
		state.busy = true
		completeQuest(player)
		state.busy = false
	end
end

for zoneName, zonePart in pairs(zoneParts) do
	zonePart.Touched:Connect(function(hit)
		local character = hit.Parent
		if character then
			local player = Players:GetPlayerFromCharacter(character)
			if player then
				tryCompleteReach(player, zoneName)
			end
		end
	end)
end

-- Fallback poll: Touched doesn't fire for a player already standing
-- inside a zone when their "reach" quest begins, so check positions too.
task.spawn(function()
	while true do
		task.wait(0.5)
		for player, state in pairs(playerStates) do
			if not state.busy then
				local quest = currentQuest(state)
				if quest and quest.type == "reach" then
					local character = player.Character
					local root = character and character:FindFirstChild("HumanoidRootPart")
					local zonePart = zoneParts[quest.zone]
					if root and zonePart then
						local offset = zonePart.Position - root.Position
						local half = zonePart.Size / 2
						if
							math.abs(offset.X) <= half.X
							and math.abs(offset.Y) <= half.Y + 3
							and math.abs(offset.Z) <= half.Z
						then
							task.spawn(tryCompleteReach, player, quest.zone)
						end
					end
				end
			end
		end
	end
end)

----------------------------------------------------------------
-- Player lifecycle
----------------------------------------------------------------
local function beginStory(player)
	local state = getState(player)
	if not state or state.started then
		return
	end
	state.started = true

	local firstChapter = StoryData.Chapters[1]
	send(player, ShowChapter, firstChapter.title, firstChapter.subtitle)
	task.wait(3.2)

	startQuest(player, firstChapter.quests[1])
end

local function initPlayer(player)
	if playerStates[player] then
		return
	end
	playerStates[player] = {
		chapterIndex = 1,
		questIndex = 1,
		collected = 0,
		busy = false,
		started = false,
		dialogueDone = false,
	}
end

Players.PlayerAdded:Connect(initPlayer)
for _, existing in ipairs(Players:GetPlayers()) do
	initPlayer(existing)
end

local function onClientReady(player)
	initPlayer(player)
	task.spawn(beginStory, player)
end

ClientReady.OnServerEvent:Connect(onClientReady)

Players.PlayerRemoving:Connect(function(player)
	playerStates[player] = nil
	for part, info in pairs(activePickups) do
		if info.player == player then
			activePickups[part] = nil
			part:Destroy()
		end
	end
end)

print("[StoryServer] Story engine ready: " .. StoryData.GameTitle)

-- What the golden walkthrough's fake player drives: the handlers the remotes
-- and talk prompts call for a real player, a replacement for send, and the
-- active Quest with its id ("chapter1.ask_dad"; nothing once the Story is
-- complete) for the golden file. Zones need no handler: the fallback poll
-- above reads the fake Character's position.
return {
	onClientReady = onClientReady,
	onDialogueFinished = onDialogueFinished,
	onTalkPromptTriggered = onTalkPromptTriggered,
	setSend = function(replacement)
		send = replacement
	end,
	activeQuest = function(player)
		local state = getState(player)
		if not state then
			return nil
		end
		local quest, chapter = currentQuest(state)
		if quest then
			return chapter.id .. "." .. quest.id, quest
		end
		return nil
	end,
}
