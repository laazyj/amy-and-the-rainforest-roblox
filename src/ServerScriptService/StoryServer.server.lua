--[[
	StoryServer
	===========
	The story engine. Reads StoryData and runs the game:
	  * builds the NPCs (and the Rain Flower) with talk prompts
	  * creates trigger zones and collectible pickups
	  * walks each player through chapters and quests
	  * repairs the bridge, starts the rain, and plays the ending

	This is a solo, story-driven experience: each player runs through
	the story at their own pace with their own state.
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

----------------------------------------------------------------
-- NPC construction
----------------------------------------------------------------
local NPC_LOOKS = {
	monkey = {
		body = Color3.fromRGB(124, 87, 56),
		belly = Color3.fromRGB(214, 186, 150),
		size = 1.0,
	},
	sloth = {
		body = Color3.fromRGB(140, 126, 100),
		belly = Color3.fromRGB(186, 172, 144),
		size = 1.15,
	},
	toucan = {
		body = Color3.fromRGB(40, 40, 46),
		belly = Color3.fromRGB(240, 235, 220),
		size = 0.85,
	},
}

local npcModels = {} -- id -> Model
local npcPrompts = {} -- id -> ProximityPrompt

local npcFolder = Instance.new("Folder")
npcFolder.Name = "StoryNPCs"
npcFolder.Parent = Workspace

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

local function addNameTag(rootPart, displayName)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTag"
	billboard.Size = UDim2.new(0, 160, 0, 32)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4.4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 60
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = displayName
	label.TextColor3 = Color3.fromRGB(255, 255, 240)
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromRGB(30, 50, 30)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = billboard
	billboard.Parent = rootPart
end

-- A cute blocky animal: body, belly, head, eyes + one signature feature
local function buildAnimal(def)
	local look = NPC_LOOKS[def.kind]
	local s = look.size
	local model = Instance.new("Model")
	model.Name = def.id

	local baseCFrame = CFrame.lookAt(
		Vector3.new(def.position.X, Map.GroundY + 1.6 * s, def.position.Z),
		Vector3.new(def.position.X, Map.GroundY + 1.6 * s, def.position.Z + (def.faceZ or 1) * 10)
	)

	local body = makeNPCPart({
		Name = "Body",
		Size = Vector3.new(2.6, 3.2, 2) * s,
		CFrame = baseCFrame,
		Color = look.body,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
	}, model)

	makeNPCPart({
		Name = "Belly",
		Size = Vector3.new(1.8, 2.2, 0.4) * s,
		CFrame = baseCFrame * CFrame.new(0, -0.2 * s, -0.9 * s),
		Color = look.belly,
	}, model)

	local head = makeNPCPart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.4, 2.4, 2.4) * s,
		CFrame = baseCFrame * CFrame.new(0, 2.4 * s, 0),
		Color = look.body,
	}, model)

	for side = -1, 1, 2 do
		makeNPCPart({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.5, 0.5, 0.5) * s,
			CFrame = baseCFrame * CFrame.new(0.5 * s * side, 2.6 * s, -1.05 * s),
			Color = Color3.fromRGB(25, 25, 25),
		}, model)
	end

	if def.kind == "monkey" then
		-- curly tail
		makeNPCPart({
			Name = "Tail",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3.4, 0.6, 0.6) * s,
			CFrame = baseCFrame * CFrame.new(0, 0.4 * s, 1.6 * s) * CFrame.Angles(0, 0, math.rad(50)),
			Color = look.body,
		}, model)
		-- tan face patch
		makeNPCPart({
			Name = "FacePatch",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.5, 1.2, 0.8) * s,
			CFrame = baseCFrame * CFrame.new(0, 2.25 * s, -0.8 * s),
			Color = look.belly,
		}, model)
	elseif def.kind == "sloth" then
		-- sleepy eye patches
		for side = -1, 1, 2 do
			makeNPCPart({
				Name = "EyePatch",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.9, 0.7, 0.4) * s,
				CFrame = baseCFrame * CFrame.new(0.5 * s * side, 2.6 * s, -0.95 * s),
				Color = Color3.fromRGB(96, 82, 62),
			}, model)
		end
		-- long arms
		for side = -1, 1, 2 do
			makeNPCPart({
				Name = "Arm",
				Size = Vector3.new(0.7, 3.4, 0.7) * s,
				CFrame = baseCFrame * CFrame.new(1.6 * s * side, -0.2 * s, 0),
				Color = look.body,
			}, model)
		end
	elseif def.kind == "toucan" then
		-- the big orange beak
		makeNPCPart({
			Name = "Beak",
			Size = Vector3.new(0.9, 0.8, 2.4) * s,
			CFrame = baseCFrame * CFrame.new(0, 2.3 * s, -2.1 * s) * CFrame.Angles(math.rad(-8), 0, 0),
			Color = Color3.fromRGB(255, 150, 40),
			Material = Enum.Material.SmoothPlastic,
		}, model)
		-- little wings
		for side = -1, 1, 2 do
			makeNPCPart({
				Name = "Wing",
				Size = Vector3.new(0.5, 2.2, 1.6) * s,
				CFrame = baseCFrame * CFrame.new(1.55 * s * side, 0.2 * s, 0.2 * s) * CFrame.Angles(0, 0, math.rad(12 * side)),
				Color = Color3.fromRGB(60, 60, 66),
			}, model)
		end
	end

	addNameTag(head, def.display)
	model.PrimaryPart = body
	model.Parent = npcFolder
	return model, body
end

-- The Rain Flower: a big sleeping flower on the tree-top platform
local flowerPetals = {}
local function buildRainFlower(def)
	local model = Instance.new("Model")
	model.Name = def.id
	local pos = def.position

	makeNPCPart({
		Name = "Stem",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3.2, 1.1, 1.1),
		CFrame = CFrame.new(pos.X, pos.Y + 1.6, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(80, 140, 80),
		Material = Enum.Material.Grass,
	}, model)

	local core = makeNPCPart({
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.4, 2.4, 2.4),
		CFrame = CFrame.new(pos.X, pos.Y + 3.4, pos.Z),
		Color = Color3.fromRGB(255, 214, 120),
		Material = Enum.Material.SmoothPlastic,
	}, model)

	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2
		local petal = makeNPCPart({
			Name = "Petal",
			Size = Vector3.new(2.2, 0.5, 3.4),
			CFrame = CFrame.new(pos.X + math.cos(a) * 2.4, pos.Y + 3.4, pos.Z + math.sin(a) * 2.4)
				* CFrame.Angles(math.rad(18), -a + math.pi / 2, 0),
			Color = Color3.fromRGB(190, 130, 160), -- dim, sleeping pink
			Material = Enum.Material.SmoothPlastic,
		}, model)
		table.insert(flowerPetals, petal)
	end

	addNameTag(core, def.display)
	model.PrimaryPart = core
	model.Parent = npcFolder
	return model, core
end

for _, def in ipairs(StoryData.NPCs) do
	local model, promptPart
	if def.kind == "flower" then
		model, promptPart = buildRainFlower(def)
	else
		model, promptPart = buildAnimal(def)
	end
	npcModels[def.id] = model

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TalkPrompt"
	prompt.ActionText = "Talk"
	prompt.ObjectText = def.display
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
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
	ShowDialogue:FireClient(player, lines)
	local waited = 0
	while playerStates[player] and not state.dialogueDone and waited < 300 do
		waited = waited + task.wait(0.1)
	end
end

DialogueFinished.OnServerEvent:Connect(function(player)
	local state = getState(player)
	if state then
		state.dialogueDone = true
	end
end)

----------------------------------------------------------------
-- Pickups (collect quests)
----------------------------------------------------------------
local activePickups = {} -- part -> {player=..., quest=...}

local pickupFolder = Instance.new("Folder")
pickupFolder.Name = "StoryPickups"
pickupFolder.Parent = Workspace

local function makePickup(quest, position, player)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false

	if quest.pickupStyle == "plank" then
		part.Name = "PlankPickup"
		part.Size = Vector3.new(4, 0.6, 1.6)
		part.Color = Color3.fromRGB(160, 118, 74)
		part.Material = Enum.Material.WoodPlanks
	else
		part.Name = "PetalPickup"
		part.Size = Vector3.new(2.6, 0.6, 2.6)
		part.Color = Color3.fromRGB(255, 130, 190)
		part.Material = Enum.Material.Neon
	end

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

	local light = Instance.new("PointLight")
	light.Color = part.Color
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = part

	activePickups[part] = { player = player, quest = quest }
	part.Parent = pickupFolder
	return part
end

-- Gentle spin + bob so pickups catch the eye
task.spawn(function()
	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t = t + dt
		for part in pairs(activePickups) do
			if part.Parent then
				local base = part:GetAttribute("BaseY")
				if not base then
					base = part.Position.Y
					part:SetAttribute("BaseY", base)
				end
				part.CFrame = CFrame.new(part.Position.X, base + math.sin(t * 2) * 0.5, part.Position.Z)
					* CFrame.Angles(0, t * 1.2, 0)
			end
		end
	end)
end)

----------------------------------------------------------------
-- World reactions to story progress
----------------------------------------------------------------
local function fixBridge()
	local mapFolder = Workspace:FindFirstChild("RainforestMap")
	if not mapFolder then
		return
	end
	local bridge = mapFolder:FindFirstChild("Bridge")
	if bridge then
		local broken = bridge:FindFirstChild("Broken")
		if broken then
			broken:Destroy()
		end
		local fixed = bridge:FindFirstChild("Fixed")
		if fixed then
			for _, part in ipairs(fixed:GetDescendants()) do
				if part:IsA("BasePart") then
					TweenService:Create(part, TweenInfo.new(1), { Transparency = 0 }):Play()
					part.CanCollide = not (part.Name == "BridgeRail" or part.Name == "BridgeRailPost")
				end
			end
			-- rails shouldn't block, but the deck must
			local deck = fixed:FindFirstChild("BridgeDeck")
			if deck then
				deck.CanCollide = true
			end
		end
	end
	local barrier = mapFolder:FindFirstChild("RiverBarrier")
	if barrier then
		barrier:Destroy()
	end
end

-- After Amy meets Milo, he "races ahead" to wait at the village
local function moveMiloToVillage()
	local milo = npcModels["Milo"]
	if milo and milo.PrimaryPart then
		local target = CFrame.lookAt(Vector3.new(-8, Map.GroundY + 1.6, 158), Vector3.new(-8, Map.GroundY + 1.6, 148))
		milo:PivotTo(target)
	end
end

local function startTheRain()
	-- glowing flower
	for _, petal in ipairs(flowerPetals) do
		petal.Material = Enum.Material.Neon
		petal.Color = Color3.fromRGB(255, 150, 210)
	end
	local flower = npcModels["RainFlower"]
	if flower and flower.PrimaryPart then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 180, 220)
		light.Range = 40
		light.Brightness = 2
		light.Parent = flower.PrimaryPart
	end

	-- rain across the whole map
	local rainPart = Instance.new("Part")
	rainPart.Name = "RainCloudLayer"
	rainPart.Size = Vector3.new(190, 1, 550)
	rainPart.CFrame = CFrame.new(0, 150, 205)
	rainPart.Anchored = true
	rainPart.CanCollide = false
	rainPart.Transparency = 1

	local rain = Instance.new("ParticleEmitter")
	rain.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	rain.Color = ColorSequence.new(Color3.fromRGB(170, 210, 255))
	rain.Size = NumberSequence.new(0.4)
	rain.Transparency = NumberSequence.new(0.3)
	rain.Lifetime = NumberRange.new(3, 4)
	rain.Rate = 800
	rain.Speed = NumberRange.new(40, 55)
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.LightEmission = 0.4
	rain.Parent = rainPart
	rainPart.Parent = Workspace

	-- the sky freshens up
	TweenService:Create(Lighting, TweenInfo.new(4), {
		FogColor = Color3.fromRGB(150, 190, 210),
		OutdoorAmbient = Color3.fromRGB(135, 155, 150),
		Brightness = 2.8,
	}):Play()
end

local questCompletedHooks = {
	meet_milo = moveMiloToVillage,
	find_planks = fixBridge,
	wake_flower = startTheRain,
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
	SetObjective:FireClient(player, questObjectiveText(state, quest))

	if quest.intro then
		playDialogue(player, quest.intro)
	end

	if quest.type == "talk" then
		local prompt = npcPrompts[quest.npc]
		if prompt then
			if quest.promptText then
				prompt.ActionText = quest.promptText
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
		hook()
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
			ShowChapter:FireClient(player, chapter.title, chapter.subtitle)
			task.wait(3.2) -- let the title card breathe
		end
	end

	local quest = currentQuest(state)
	if quest then
		startQuest(player, quest)
	else
		-- Story complete!
		SetObjective:FireClient(player, nil)
		playDialogue(player, StoryData.Ending.lines)
		ShowEnding:FireClient(player, StoryData.Ending.title, StoryData.Ending.subtitle)
	end
end

----------------------------------------------------------------
-- Interactions
----------------------------------------------------------------
for npcId, prompt in pairs(npcPrompts) do
	prompt.Triggered:Connect(function(player)
		local state = getState(player)
		if not state or state.busy then
			return
		end
		local quest = currentQuest(state)
		if quest and quest.type == "talk" and quest.npc == npcId then
			state.busy = true
			prompt.Enabled = false
			playDialogue(player, quest.dialogue)
			completeQuest(player)
			state.busy = false
		end
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
		SetObjective:FireClient(player, questObjectiveText(state, quest))

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
						if math.abs(offset.X) <= half.X
							and math.abs(offset.Y) <= half.Y + 3
							and math.abs(offset.Z) <= half.Z then
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
	ShowChapter:FireClient(player, firstChapter.title, firstChapter.subtitle)
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
for _, player in ipairs(Players:GetPlayers()) do
	initPlayer(player)
end

ClientReady.OnServerEvent:Connect(function(player)
	initPlayer(player)
	task.spawn(beginStory, player)
end)

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
