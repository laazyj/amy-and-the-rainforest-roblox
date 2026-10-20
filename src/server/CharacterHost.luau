--!strict
--[[
	CharacterHost: builds the Characters at their home Spots, moves them
	between Spots (running there when a Beat says so), dresses the Player
	Character as Amy, and offers or withdraws each Character's talk
	affordance (a ProximityPrompt, Enabled while a talk Quest waits for it).

	How each Character is built is Story.build's answer. A human is Roblox's
	R15 body made from its Description; any other Character is its Character
	model, ServerStorage.CharacterModels.<id> (assets/meshes/characters),
	when the place has one, and else its Placeholder, built out of parts:
	the white dog, the maroon squirrel, the orangest fox, the golden lion
	with his mane. Every Character has a Humanoid and stands anchored at its
	root, playing its `idle` animation; it runs with its `run` one. Its
	animations are the Animation objects in its Animations folder: a human's
	come from the Animate script Roblox gives the body (which runs only for
	a player), a Character model's from the model.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Story = require(ReplicatedStorage:WaitForChild("core"):WaitForChild("Story"))
local AssetIds = require(ReplicatedStorage:WaitForChild("shared"):WaitForChild("AssetIds"))
local Convert = require(script.Parent.Convert)
local Parts = require(script.Parent.Parts)

local HAIR = Color3.fromRGB(94, 64, 44)
local TALK = "Talk"
-- the animations a Character may have, by name in its Animations folder
local ANIMATIONS = { "idle", "walk", "run" }

local CharacterHost = {}

-- the states a Character never takes: it never dies, and a just-unanchored
-- assembly that tips as it wakes would fall down and stand getting up
-- before it ran
CharacterHost.NEVER_STATES = table.freeze({
	Enum.HumanoidStateType.Dead,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.GettingUp,
})

local models: { [string]: Model } = {}
local prompts: { [string]: ProximityPrompt } = {}
-- how high above its Spot each Character's pivot stands, kept when it moves
local pivotHeights: { [string]: number } = {}
-- each Character's loaded animations, by name
local tracks: { [string]: { [string]: AnimationTrack } } = {}
local spots: { [string]: Story.Spot } = {}
local amy: Story.Description? = nil

-- A Character's parts do not collide, but for its body.
local function makePart(props: { [string]: any }, model: Model): Part
	if props.CanCollide == nil then
		props.CanCollide = false
	end
	return Parts.make("Part", props, model)
end

local function addNameTag(rootPart: BasePart, displayName: string, offsetY: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTag"
	billboard.Size = UDim2.new(0, 170, 0, 30)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
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

-- A Description as a HumanoidDescription: its colours, and each Catalog
-- item whose id the Manifest has (AssetIds); an empty slot is left off.
function CharacterHost.humanoidDescription(description: Story.Description): HumanoidDescription
	local made = Instance.new("HumanoidDescription")
	local arms, legs = Convert.colour(description.arms), Convert.colour(description.legs)
	made.HeadColor = Convert.colour(description.head)
	made.TorsoColor = Convert.colour(description.torso)
	made.LeftArmColor, made.RightArmColor = arms, arms
	made.LeftLegColor, made.RightLegColor = legs, legs
	local accessories = {}
	for slot, name in (description.catalog or {}) :: { [string]: string } do
		local id = tonumber(string.match(AssetIds[name] or "", "%d+$"))
		local kind = Story.CATALOG_SLOTS[slot]
		if id and kind then
			local accessory = (Enum.AccessoryType :: any)[kind.accessory]
			table.insert(
				accessories,
				{ AssetId = id, AccessoryType = accessory, IsLayered = kind.order ~= nil, Order = kind.order }
			)
		end
	end
	made:SetAccessories(accessories, true)
	return made
end

-- Readies a Character's Humanoid: it never dies and shows no name or
-- health of its own (the NameTag does), and its animations are loaded, the
-- `idle` one playing.
local function ready(model: Model, humanoid: Humanoid)
	local name = model.Name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	for _, state in CharacterHost.NEVER_STATES do
		humanoid:SetStateEnabled(state, false)
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid

	local folder: Instance = model:FindFirstChild("Animations") or Instance.new("Folder")
	folder.Name = "Animations"
	folder.Parent = model
	local animate = model:FindFirstChild("Animate")
	if animate then
		for _, animationName in ANIMATIONS do
			local holder = animate:FindFirstChild(animationName)
			local animation = holder and holder:FindFirstChildWhichIsA("Animation")
			if animation and not folder:FindFirstChild(animationName) then
				local copy = animation:Clone()
				copy.Name = animationName
				copy.Parent = folder
			end
		end
		animate:Destroy()
	end

	local loaded: { [string]: AnimationTrack } = {}
	for _, animationName in ANIMATIONS do
		local animation = folder:FindFirstChild(animationName)
		if animation and animation:IsA("Animation") then
			local ok, track = pcall(animator.LoadAnimation, animator, animation)
			if ok then
				track.Looped = true
				loaded[animationName] = track
			else
				warn(`[CharacterHost] {name}'s {animationName} animation did not load: {track}`)
			end
		end
	end
	tracks[name] = loaded
	if loaded.idle then
		loaded.idle:Play()
	end
end

-- Anchors `model` at its root and puts it in `parent`, ready: in the world
-- first, so its animations load.
local function place(model: Model, root: BasePart, humanoid: Humanoid, parent: Instance)
	root.Anchored = true
	model.PrimaryPart = root
	model.Parent = parent
	ready(model, humanoid)
end

-- Gives a Character built of parts its Humanoid: an invisible root where its
-- pivot stands, `height` above the ground, every part welded to it. Then
-- puts it in `parent`, ready.
local function withHumanoid(model: Model, base: CFrame, size: Vector3, height: number, parent: Instance): BasePart
	local root = makePart({ Name = "HumanoidRootPart", Size = size, CFrame = base, Transparency = 1 }, model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
			part.Anchored = false
		end
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = height - size.Y / 2
	humanoid.Parent = model
	place(model, root, humanoid, parent)
	return root
end

-- A Humanoid's model standing on `spot`, anchored at its root, with its
-- name tag; nil when it has no Humanoid or no root.
local function stand(model: Model, display: string, spot: Story.Spot, parent: Instance): BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return nil
	end
	-- the pivot is the root's, whatever pivot a Character model came with
	model.PrimaryPart = root
	model:PivotTo(Convert.standing(spot, humanoid.HipHeight + root.Size.Y / 2))
	local head = model:FindFirstChild("Head")
	addNameTag(if head and head:IsA("BasePart") then head else root, display, 2.2)
	place(model, root, humanoid, parent)
	return root
end

-- A friendly blocky human in the colours of `description`, for when Roblox
-- makes no R15 body.
local function buildBlockyHuman(
	name: string,
	display: string,
	description: Story.Description,
	spot: Story.Spot,
	parent: Instance
): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = name
	local height = 2.9
	local base = Convert.standing(spot, height)
	local skin, torso, arms =
		Convert.colour(description.head), Convert.colour(description.torso), Convert.colour(description.arms)

	-- legs
	for side = -1, 1, 2 do
		makePart({
			Name = "Leg",
			Size = Vector3.new(0.9, 2.4, 1),
			CFrame = base * CFrame.new(0.55 * side, -2.1, 0),
			Color = Convert.colour(description.legs),
		}, model)
	end
	-- torso
	makePart({
		Name = "Body",
		Size = Vector3.new(2.6, 3, 1.5),
		CFrame = base * CFrame.new(0, 0.6, 0),
		Color = torso,
		CanCollide = true,
	}, model)
	-- arms
	for side = -1, 1, 2 do
		makePart({
			Name = "Arm",
			Size = Vector3.new(0.8, 2.8, 1),
			CFrame = base * CFrame.new(1.75 * side, 0.5, 0),
			Color = arms,
		}, model)
		makePart({
			Name = "Hand",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.8, 0.8, 0.8),
			CFrame = base * CFrame.new(1.75 * side, -1.1, 0),
			Color = skin,
		}, model)
	end
	-- head + hair + eyes
	local head = makePart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.1, 2.1, 2.1),
		CFrame = base * CFrame.new(0, 3, 0),
		Color = skin,
	}, model)
	makePart({
		Name = "Hair",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.25, 1.5, 2.25),
		CFrame = base * CFrame.new(0, 3.55, 0.25),
		Color = HAIR,
	}, model)
	for side = -1, 1, 2 do
		makePart({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.34, 0.34, 0.34),
			CFrame = base * CFrame.new(0.42 * side, 3.15, -0.92),
			Color = Color3.fromRGB(25, 25, 25),
		}, model)
	end

	addNameTag(head, display, 2.6)
	return model, withHumanoid(model, base, Vector3.new(2, 2, 1), height, parent)
end

-- The parts of Roblox's R15 body each colour of a Description paints.
local BODY_PARTS: { [string]: { string } } = {
	head = { "Head" },
	torso = { "UpperTorso", "LowerTorso" },
	arms = { "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand" },
	legs = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" },
}

-- Roblox's R15 body, made once (a web call); each human is a copy of it in
-- its own colours. False when Roblox made none.
local r15Body: Model | false | nil = nil

local function r15(): Model?
	if r15Body == nil then
		local ok, made = pcall(
			Players.CreateHumanoidModelFromDescriptionAsync,
			Players,
			Instance.new("HumanoidDescription"),
			Enum.HumanoidRigType.R15
		)
		if ok then
			-- its BodyColors would paint over the Descriptions' colours
			for _, bodyColors in made:GetChildren() do
				if bodyColors:IsA("BodyColors") then
					bodyColors:Destroy()
				end
			end
		else
			warn(`[CharacterHost] the humans are blocky: Roblox made no R15 body ({made})`)
		end
		r15Body = if ok then made else false
	end
	return r15Body or nil
end

-- A human standing on `spot` (Dad, Mum, and the villagers of
-- prop:Villagers): Roblox's R15 body in the colours of `description`. Only
-- if Roblox makes no body is it the blocky one, which tier 2 refuses.
-- Returns the model and its root, which holds the talk affordance.
function CharacterHost.buildHuman(
	name: string,
	display: string,
	description: Story.Description,
	spot: Story.Spot,
	parent: Instance
): (Model, BasePart)
	local body = r15()
	if not body then
		return buildBlockyHuman(name, display, description, spot, parent)
	end
	local model = body:Clone()
	model.Name = name
	for colour, names in BODY_PARTS do
		for _, partName in names do
			local part = model:FindFirstChild(partName)
			if part and part:IsA("BasePart") then
				part.Color = Convert.colour((description :: any)[colour])
			end
		end
	end
	return model, assert(stand(model, display, spot, parent), "Roblox's R15 body has a Humanoid and a root")
end

-- A four-legged friend, as its Placeholder: colours, size and tail from
-- content, and its kind's ears, the fox's dark ones and the lion's mane.
local function buildPlaceholder(character: Story.Character, spot: Story.Spot, parent: Instance): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = character.id
	local kind = character.kind
	local look = assert(character.placeholder, `character:{character.id} has no Placeholder`)
	local bodyColor, bellyColor, scale, tailStyle =
		Convert.colour(look.body), Convert.colour(look.belly), look.scale, look.tail

	local bodyLift = 1.6 * scale + 0.6
	local base = Convert.standing(spot, bodyLift)

	-- body (horizontal)
	local bodySize = Vector3.new(2 * scale, 1.8 * scale, 3.6 * scale)
	makePart({
		Name = "Body",
		Size = bodySize,
		CFrame = base,
		Color = bodyColor,
		CanCollide = true,
	}, model)
	-- belly / chest patch
	makePart({
		Name = "Chest",
		Size = Vector3.new(1.4 * scale, 1.2 * scale, 0.5 * scale),
		CFrame = base * CFrame.new(0, -0.2 * scale, -1.7 * scale),
		Color = bellyColor,
	}, model)
	-- legs
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			makePart({
				Name = "Leg",
				Size = Vector3.new(0.6 * scale, 1.5 * scale, 0.6 * scale),
				CFrame = base * CFrame.new(0.6 * sx * scale, -1.5 * scale, 1.2 * sz * scale),
				Color = bodyColor,
			}, model)
		end
	end
	-- head
	local head = makePart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.9, 1.9, 1.9) * scale,
		CFrame = base * CFrame.new(0, 1.3 * scale, -2 * scale),
		Color = bodyColor,
	}, model)
	-- eyes
	for side = -1, 1, 2 do
		makePart({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.32, 0.32, 0.32) * scale,
			CFrame = base * CFrame.new(0.4 * side * scale, 1.5 * scale, -2.8 * scale),
			Color = Color3.fromRGB(25, 25, 25),
		}, model)
	end
	-- snout
	makePart({
		Name = "Snout",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.8, 0.6, 0.9) * scale,
		CFrame = base * CFrame.new(0, 1.1 * scale, -2.85 * scale),
		Color = bellyColor,
	}, model)
	makePart({
		Name = "Nose",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.3, 0.3, 0.3) * scale,
		CFrame = base * CFrame.new(0, 1.15 * scale, -3.3 * scale),
		Color = Color3.fromRGB(30, 26, 26),
	}, model)
	-- ears
	local earShape
	if kind == "dog" then
		earShape = Vector3.new(0.5, 1.1, 0.3) -- floppy
	elseif kind == "lion" then
		earShape = Vector3.new(0.55, 0.55, 0.3) -- little and round
	else
		earShape = Vector3.new(0.45, 0.8, 0.3) -- pointy-ish
	end
	for side = -1, 1, 2 do
		makePart({
			Name = "Ear",
			Size = earShape * scale * 1.6,
			CFrame = base
				* CFrame.new(0.6 * side * scale, 2.1 * scale, -1.9 * scale)
				* CFrame.Angles(0, 0, math.rad(if kind == "dog" then 35 * side else 10 * side)),
			Color = if kind == "fox" then Color3.fromRGB(40, 36, 36) else bodyColor,
		}, model)
	end
	-- tails
	if tailStyle == "up" then
		makePart({
			Name = "Tail",
			Size = Vector3.new(0.4, 1.6, 0.4) * scale,
			CFrame = base * CFrame.new(0, 0.9 * scale, 2 * scale) * CFrame.Angles(math.rad(-30), 0, 0),
			Color = bodyColor,
		}, model)
	elseif tailStyle == "fluff" then
		-- the squirrel's giant question-mark tail
		makePart({
			Name = "Tail",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.4, 2.6, 1.4) * scale,
			CFrame = base * CFrame.new(0, 1.4 * scale, 2.2 * scale),
			Color = bodyColor,
		}, model)
		makePart({
			Name = "TailTip",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1, 1.2, 1) * scale,
			CFrame = base * CFrame.new(0, 2.8 * scale, 1.6 * scale),
			Color = bodyColor,
		}, model)
	elseif tailStyle == "brush" then
		makePart({
			Name = "Tail",
			Size = Vector3.new(0.8, 0.8, 2.4) * scale,
			CFrame = base * CFrame.new(0, 0.4 * scale, 2.8 * scale) * CFrame.Angles(math.rad(18), 0, 0),
			Color = bodyColor,
		}, model)
		makePart({
			Name = "TailTip",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.85, 0.85, 1) * scale,
			CFrame = base * CFrame.new(0, 0.75 * scale, 3.9 * scale),
			Color = Color3.fromRGB(248, 240, 226), -- white tip
		}, model)
	else -- tuft
		makePart({
			Name = "Tail",
			Size = Vector3.new(0.35, 0.35, 2.6) * scale,
			CFrame = base * CFrame.new(0, 0.5 * scale, 2.9 * scale) * CFrame.Angles(math.rad(12), 0, 0),
			Color = bodyColor,
		}, model)
		makePart({
			Name = "TailTuft",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.7, 0.7, 0.7) * scale,
			CFrame = base * CFrame.new(0, 0.8 * scale, 4.1 * scale),
			Color = Color3.fromRGB(150, 96, 40),
		}, model)
	end
	-- the lion's magnificent mane
	if kind == "lion" then
		makePart({
			Name = "Mane",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.9, 2.9, 2.2) * scale,
			CFrame = base * CFrame.new(0, 1.3 * scale, -1.55 * scale),
			Color = Color3.fromRGB(168, 108, 40),
			Material = Enum.Material.Grass,
		}, model)
	end

	addNameTag(head, character.display, if kind == "lion" then 4.6 else 3.2)
	return model, withHumanoid(model, base, bodySize, bodyLift, parent)
end

-- A Character from its Character model, standing on `spot`; nil when the
-- model has no Humanoid or no root.
local function buildFromModel(
	character: Story.Character,
	template: Model,
	spot: Story.Spot,
	parent: Instance
): (Model?, BasePart?)
	local model = template:Clone()
	model.Name = character.id
	local root = stand(model, character.display, spot, parent)
	if not root then
		warn(
			`[CharacterHost] character:{character.id}'s Character model has no Humanoid or root; drawn as its Placeholder`
		)
		model:Destroy()
		return nil, nil
	end
	return model, root
end

-- Builds every Character but the Player Character at its home Spot, in the
-- StoryCharacters folder, each with its talk affordance withdrawn.
function CharacterHost.build(story: Story.Story)
	local folder = Instance.new("Folder")
	folder.Name = "StoryCharacters"
	folder.Parent = Workspace
	spots = story.spots
	local characterModels = ServerStorage:FindFirstChild("CharacterModels")

	for _, character in story.characters do
		if character.player then
			amy = character.description
			continue
		end
		local home = assert(spots[character.home], character.home)
		local template = characterModels and characterModels:FindFirstChild(character.id)
		local build = Story.build(character, template ~= nil and template:IsA("Model"))
		local model: Model?, promptPart: BasePart?
		if build == "description" then
			local description = assert(character.description, `character:{character.id} has no Description`)
			model, promptPart = CharacterHost.buildHuman(character.id, character.display, description, home, folder)
		elseif build == "model" then
			model, promptPart = buildFromModel(character, template :: Model, home, folder)
		end
		if not model or not promptPart then
			model, promptPart = buildPlaceholder(character, home, folder)
		end
		local built = model :: Model
		models[character.id] = built
		pivotHeights[character.id] = built:GetPivot().Position.Y - home.at.y

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TalkPrompt"
		prompt.ActionText = TALK
		prompt.ObjectText = character.display
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = promptPart
		prompts[character.id] = prompt
	end
end

-- Each Character's talk affordance, by Character id.
function CharacterHost.prompts(): { [string]: ProximityPrompt }
	return prompts
end

-- Each Character's loaded animations, by Character id and animation name.
function CharacterHost.animations(): { [string]: { [string]: AnimationTrack } }
	return tracks
end

-- The run each Character is on, so a later move ends it.
local runs: { [string]: {} } = {}

-- Swaps a Character's playing animation `from` for `to`.
local function swap(animations: { [string]: AnimationTrack }, from: string, to: string)
	if animations[from] then
		animations[from]:Stop(0.2)
	end
	if animations[to] then
		animations[to]:Play(0.2)
	end
end

-- Sets a Humanoid off running to `to`: its root unanchored and simulated
-- by the server, its state Running (an anchored Humanoid's state machine
-- has not run, so it would first settle), and, once physics has stepped the
-- woken assembly (`stepped`, which yields), told to move, unless a later
-- move has anchored it again.
function CharacterHost.setOff(humanoid: Humanoid, root: BasePart, to: Vector3, stepped: () -> ())
	humanoid.WalkSpeed = Story.RUN.speed
	root.Anchored = false
	pcall(root.SetNetworkOwner, root, nil)
	humanoid:ChangeState(Enum.HumanoidStateType.Running)
	stepped()
	if not root.Anchored then
		humanoid:MoveTo(to)
	end
end

-- Sets a Character running toward `at` with its run animation, and returns.
-- The run ends when it arrives, when a later move comes, or after
-- Story.runSeconds (physics may not step, as in a Luau Execution task);
-- then it stands at `at`. A Beat gives the run its time with a Wait.
local function runTo(id: string, model: Model, at: CFrame)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	if not humanoid or not root then
		model:PivotTo(at)
		return
	end
	local run = {}
	runs[id] = run
	local animations: { [string]: AnimationTrack } = tracks[id] or {}
	local seconds = Story.runSeconds((at.Position - root.Position).Magnitude)
	swap(animations, "idle", "run")
	-- set off before this returns; the step and the move follow in the run
	task.spawn(function()
		CharacterHost.setOff(humanoid, root, at.Position, function()
			RunService.Heartbeat:Wait()
		end)
		local arrived = false
		local connection = humanoid.MoveToFinished:Connect(function()
			arrived = true
		end)
		while not arrived and seconds > 0 and runs[id] == run do
			seconds -= task.wait()
		end
		connection:Disconnect()
		if runs[id] == run then
			runs[id] = nil
			root.Anchored = true
			model:PivotTo(at)
		end
		-- unless another run has taken over
		if runs[id] == nil then
			swap(animations, "run", "idle")
		end
	end)
end

-- Puts a Character at a Spot, at its own height, facing the Spot's way;
-- with `run`, sets it running there instead.
function CharacterHost.moveCharacter(id: string, spotId: string, run: boolean?)
	local model = models[id]
	local spot = spots[spotId]
	if model and spot then
		local at = Convert.standing(spot, pivotHeights[id])
		if run then
			runTo(id, model, at)
			return
		end
		local running = runs[id] and model.PrimaryPart
		runs[id] = nil
		if running then
			running.Anchored = true
		end
		model:PivotTo(at)
	end
end

function CharacterHost.offerTalk(id: string, label: string)
	local prompt = prompts[id]
	if prompt then
		prompt.ActionText = label
		prompt.Enabled = true
	end
end

function CharacterHost.withdrawTalk(id: string)
	local prompt = prompts[id]
	if prompt then
		prompt.Enabled = false
	end
end

-- Dresses a Player Character as Amy: her Description on Roblox's body.
-- Her face is never seen (the camera rule), so it is left as Roblox makes it.
function CharacterHost.dress(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not amy or not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	-- the description is built inside the pcall, so its errors are caught too
	local ok, problem = pcall(function()
		humanoid:ApplyDescriptionAsync(CharacterHost.humanoidDescription(amy))
	end)
	if not ok then
		warn(`[CharacterHost] could not dress {character.Name} as Amy: {problem}`)
	end
end

-- Dresses `player`'s Character as Amy each time it spawns.
function CharacterHost.dressPlayer(player: Player)
	player.CharacterAdded:Connect(CharacterHost.dress)
	if player.Character then
		task.spawn(CharacterHost.dress, player.Character)
	end
end

return CharacterHost
