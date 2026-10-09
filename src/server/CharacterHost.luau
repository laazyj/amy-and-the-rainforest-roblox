--!strict
--[[
	CharacterHost: builds the Characters out of parts at their home Spots,
	moves them between Spots, and offers or withdraws each one's talk
	affordance (a ProximityPrompt, Enabled while a talk Quest waits for it).

	Humans are friendly blocky villagers; the animals' kind decides their
	colours and features: the white dog, the maroon squirrel, the orangest
	fox, the golden lion with his mane.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Story = require(ReplicatedStorage:WaitForChild("core"):WaitForChild("Story"))
local Convert = require(script.Parent.Convert)
local Parts = require(script.Parent.Parts)

local SKIN = Color3.fromRGB(228, 194, 160)
local HAIR = Color3.fromRGB(94, 64, 44)
local DEFAULT_SHIRT = Color3.fromRGB(120, 120, 140)
local TALK = "Talk"

local CharacterHost = {}

local models: { [string]: Model } = {}
local prompts: { [string]: ProximityPrompt } = {}
-- how high above its Spot each Character's pivot stands, kept when it moves
local pivotHeights: { [string]: number } = {}
local spots: { [string]: Story.Spot } = {}

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

-- A friendly blocky human standing on `spot` (Dad, Mum, and the villagers
-- of prop:Villagers). Returns the model and its body, which holds the
-- talk affordance.
function CharacterHost.buildHuman(
	name: string,
	display: string,
	shirt: Color3?,
	spot: Story.Spot,
	parent: Instance
): (Model, Part)
	local model = Instance.new("Model")
	model.Name = name
	local base = Convert.standing(spot, 2.9)
	local shirtColour = shirt or DEFAULT_SHIRT

	-- legs
	for side = -1, 1, 2 do
		makePart({
			Name = "Leg",
			Size = Vector3.new(0.9, 2.4, 1),
			CFrame = base * CFrame.new(0.55 * side, -2.1, 0),
			Color = Color3.fromRGB(64, 74, 94),
		}, model)
	end
	-- torso
	local body = makePart({
		Name = "Body",
		Size = Vector3.new(2.6, 3, 1.5),
		CFrame = base * CFrame.new(0, 0.6, 0),
		Color = shirtColour,
		CanCollide = true,
	}, model)
	-- arms
	for side = -1, 1, 2 do
		makePart({
			Name = "Arm",
			Size = Vector3.new(0.8, 2.8, 1),
			CFrame = base * CFrame.new(1.75 * side, 0.5, 0),
			Color = shirtColour,
		}, model)
		makePart({
			Name = "Hand",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.8, 0.8, 0.8),
			CFrame = base * CFrame.new(1.75 * side, -1.1, 0),
			Color = SKIN,
		}, model)
	end
	-- head + hair + eyes
	local head = makePart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.1, 2.1, 2.1),
		CFrame = base * CFrame.new(0, 3, 0),
		Color = SKIN,
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
	model.PrimaryPart = body
	model.Parent = parent
	return model, body
end

type AnimalLook = { body: Color3, belly: Color3, scale: number, tail: "up" | "fluff" | "brush" | "tuft" }

local ANIMALS: { [string]: AnimalLook } = {
	dog = { body = Color3.fromRGB(238, 230, 214), belly = Color3.fromRGB(150, 110, 74), scale = 1.0, tail = "up" },
	-- maroon!
	squirrel = {
		body = Color3.fromRGB(128, 32, 48),
		belly = Color3.fromRGB(214, 168, 150),
		scale = 0.55,
		tail = "fluff",
	},
	-- the orangest orange
	fox = { body = Color3.fromRGB(240, 120, 32), belly = Color3.fromRGB(248, 240, 226), scale = 0.85, tail = "brush" },
	-- golden
	lion = { body = Color3.fromRGB(226, 178, 68), belly = Color3.fromRGB(240, 214, 150), scale = 1.5, tail = "tuft" },
}

-- A four-legged friend. Its kind decides colours and signature features;
-- any kind not listed is drawn as the lion.
local function buildAnimal(character: Story.Character, spot: Story.Spot, parent: Instance): (Model, Part)
	local model = Instance.new("Model")
	model.Name = character.id
	local kind = character.kind
	local look = ANIMALS[kind] or ANIMALS.lion
	local bodyColor, bellyColor, scale, tailStyle = look.body, look.belly, look.scale, look.tail

	local bodyLift = 1.6 * scale + 0.6
	local base = Convert.standing(spot, bodyLift)

	-- body (horizontal)
	local body = makePart({
		Name = "Body",
		Size = Vector3.new(2 * scale, 1.8 * scale, 3.6 * scale),
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
	model.PrimaryPart = body
	model.Parent = parent
	return model, body
end

-- Builds every Character but the Player Character at its home Spot, in the
-- StoryCharacters folder, each with its talk affordance withdrawn.
function CharacterHost.build(story: Story.Story)
	local folder = Instance.new("Folder")
	folder.Name = "StoryCharacters"
	folder.Parent = Workspace
	spots = story.spots

	for _, character in story.characters do
		if character.player then
			continue
		end
		local home = assert(spots[character.home], character.home)
		local model, promptPart
		if character.kind == "human" then
			model, promptPart = CharacterHost.buildHuman(
				character.id,
				character.display,
				if character.shirt then Convert.colour(character.shirt) else nil,
				home,
				folder
			)
		else
			model, promptPart = buildAnimal(character, home, folder)
		end
		models[character.id] = model
		pivotHeights[character.id] = model:GetPivot().Position.Y - home.at.y

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

-- Puts a Character at a Spot, at its own height, facing the Spot's way.
function CharacterHost.moveCharacter(id: string, spotId: string)
	local model = models[id]
	local spot = spots[spotId]
	if model and spot then
		model:PivotTo(Convert.standing(spot, pivotHeights[id]))
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

return CharacterHost
