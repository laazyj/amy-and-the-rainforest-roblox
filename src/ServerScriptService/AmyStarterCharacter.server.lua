--[[
	AmyStarterCharacter
	===================
	The "full commitment" version of playing as Amy: every player
	spawns AS Amy from the hero drawing -- red jumper, blue skirt,
	long brown hair, brown shoes -- in the same cute blocky style as
	Dad, Mum, Sam and the animals. Profile avatars are never loaded.

	How it works:
	  * this script hand-builds a classic R6 rig (correct part names
	    and Motor6D joints), so Roblox recognises it, inserts the
	    default Animate script, and all the standard walk/jump/idle
	    animations just work
	  * Amy's hair, skirt and shoes are plain parts welded to the rig,
	    so they move with the animations -- no catalog assets needed
	  * the finished model is named "StarterCharacter" and parented to
	    StarterPlayer before anyone spawns, which is Roblox's built-in
	    mechanism for replacing every player's avatar

	To go back to normal avatars (or to the lighter "outfit only"
	approach), just delete this script.
]]

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

local SKIN = Color3.fromRGB(228, 194, 160)
local JUMPER_RED = Color3.fromRGB(198, 74, 56)
local SKIRT_BLUE = Color3.fromRGB(52, 108, 202)
local HAIR_BROWN = Color3.fromRGB(94, 64, 44)
local SHOE_BROWN = Color3.fromRGB(122, 82, 52)

----------------------------------------------------------------
-- R6 rig construction
----------------------------------------------------------------
local function makeBodyPart(model, name, size, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function makeMotor(parent, name, part0, part1, c0, c1)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = c0
	motor.C1 = c1
	motor.Parent = parent
	return motor
end

-- Decorative parts ride along on welds, so animations move them too
local function weldDecoration(limb, part, offset)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	local weld = Instance.new("Weld")
	weld.Part0 = limb
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = limb
	part.Parent = limb.Parent
end

local function buildAmyRig()
	local model = Instance.new("Model")
	model.Name = "StarterCharacter"
	model:SetAttribute("AmyRig", true)

	-- classic R6 proportions; the engine's default animations expect them
	local rootPart = makeBodyPart(model, "HumanoidRootPart", Vector3.new(2, 2, 1), SKIN)
	rootPart.Transparency = 1
	local torso = makeBodyPart(model, "Torso", Vector3.new(2, 2, 1), JUMPER_RED)
	local head = makeBodyPart(model, "Head", Vector3.new(2, 1, 1), SKIN)
	local leftArm = makeBodyPart(model, "Left Arm", Vector3.new(1, 2, 1), JUMPER_RED)
	local rightArm = makeBodyPart(model, "Right Arm", Vector3.new(1, 2, 1), JUMPER_RED)
	local leftLeg = makeBodyPart(model, "Left Leg", Vector3.new(1, 2, 1), SKIN)
	local rightLeg = makeBodyPart(model, "Right Leg", Vector3.new(1, 2, 1), SKIN)

	-- rough assembly positions (the Motor6Ds snap everything exact on spawn)
	rootPart.CFrame = CFrame.new(0, 3, 0)
	torso.CFrame = CFrame.new(0, 3, 0)
	head.CFrame = CFrame.new(0, 4.5, 0)
	leftArm.CFrame = CFrame.new(-1.5, 3, 0)
	rightArm.CFrame = CFrame.new(1.5, 3, 0)
	leftLeg.CFrame = CFrame.new(-0.5, 1, 0)
	rightLeg.CFrame = CFrame.new(0.5, 1, 0)

	-- the classic rounded head + the classic smiley (both ship with the
	-- engine, so no uploads are needed)
	local headMesh = Instance.new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Head
	headMesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	headMesh.Parent = head

	local face = Instance.new("Decal")
	face.Name = "face"
	face.Face = Enum.NormalId.Front
	face.Texture = "rbxasset://textures/face.png"
	face.Parent = head

	-- canonical R6 Motor6D joints (names and offsets matter: the default
	-- Animate script drives these exact motors)
	local halfPi = math.pi / 2
	makeMotor(rootPart, "RootJoint", rootPart, torso,
		CFrame.new(0, 0, 0) * CFrame.Angles(-halfPi, 0, math.pi),
		CFrame.new(0, 0, 0) * CFrame.Angles(-halfPi, 0, math.pi))
	makeMotor(torso, "Neck", torso, head,
		CFrame.new(0, 1, 0) * CFrame.Angles(-halfPi, 0, math.pi),
		CFrame.new(0, -0.5, 0) * CFrame.Angles(-halfPi, 0, math.pi))
	makeMotor(torso, "Left Shoulder", torso, leftArm,
		CFrame.new(-1, 0.5, 0) * CFrame.Angles(0, -halfPi, 0),
		CFrame.new(0.5, 0.5, 0) * CFrame.Angles(0, -halfPi, 0))
	makeMotor(torso, "Right Shoulder", torso, rightArm,
		CFrame.new(1, 0.5, 0) * CFrame.Angles(0, halfPi, 0),
		CFrame.new(-0.5, 0.5, 0) * CFrame.Angles(0, halfPi, 0))
	makeMotor(torso, "Left Hip", torso, leftLeg,
		CFrame.new(-1, -1, 0) * CFrame.Angles(0, -halfPi, 0),
		CFrame.new(-0.5, 1, 0) * CFrame.Angles(0, -halfPi, 0))
	makeMotor(torso, "Right Hip", torso, rightLeg,
		CFrame.new(1, -1, 0) * CFrame.Angles(0, halfPi, 0),
		CFrame.new(0.5, 1, 0) * CFrame.Angles(0, halfPi, 0))

	----------------------------------------------------------------
	-- Amy's look: hair, skirt, shoes (welded, so they animate)
	----------------------------------------------------------------
	-- hair dome over the top of the head
	local hairDome = Instance.new("Part")
	hairDome.Name = "AmyHairDome"
	hairDome.Shape = Enum.PartType.Ball
	hairDome.Size = Vector3.new(2.45, 2.1, 2.45)
	hairDome.Color = HAIR_BROWN
	hairDome.Material = Enum.Material.SmoothPlastic
	weldDecoration(head, hairDome, CFrame.new(0, 0.32, 0.12))

	-- long hair hanging down the back (character front is -Z)
	local hairBack = Instance.new("Part")
	hairBack.Name = "AmyHairBack"
	hairBack.Size = Vector3.new(1.9, 2.6, 0.65)
	hairBack.Color = HAIR_BROWN
	hairBack.Material = Enum.Material.SmoothPlastic
	weldDecoration(head, hairBack, CFrame.new(0, -0.75, 0.72))

	-- the blue skirt around the hips
	local skirt = Instance.new("Part")
	skirt.Name = "AmySkirt"
	skirt.Size = Vector3.new(2.5, 1.15, 1.7)
	skirt.Color = SKIRT_BLUE
	skirt.Material = Enum.Material.SmoothPlastic
	weldDecoration(torso, skirt, CFrame.new(0, -1.05, 0))

	-- skin-tone hands peeking out of the jumper sleeves
	for _, armInfo in ipairs({ { arm = leftArm }, { arm = rightArm } }) do
		local hand = Instance.new("Part")
		hand.Name = "AmyHand"
		hand.Size = Vector3.new(1.04, 0.4, 1.04)
		hand.Color = SKIN
		hand.Material = Enum.Material.SmoothPlastic
		weldDecoration(armInfo.arm, hand, CFrame.new(0, -0.82, 0))
	end

	-- little brown shoes
	for _, legInfo in ipairs({ { leg = leftLeg }, { leg = rightLeg } }) do
		local shoe = Instance.new("Part")
		shoe.Name = "AmyShoe"
		shoe.Size = Vector3.new(1.06, 0.4, 1.3)
		shoe.Color = SHOE_BROWN
		shoe.Material = Enum.Material.SmoothPlastic
		weldDecoration(legInfo.leg, shoe, CFrame.new(0, -0.85, -0.1))
	end

	----------------------------------------------------------------
	-- Humanoid
	----------------------------------------------------------------
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model

	model.PrimaryPart = rootPart
	return model
end

----------------------------------------------------------------
-- Install as everyone's character
----------------------------------------------------------------
local rig = buildAmyRig()
rig.Parent = StarterPlayer

-- If anyone somehow spawned with their profile avatar before the rig
-- was installed, respawn them as Amy.
local function ensureAmy(player)
	local character = player.Character
	if character and not character:GetAttribute("AmyRig") then
		player:LoadCharacter()
	end
end

Players.PlayerAdded:Connect(function(player)
	task.defer(ensureAmy, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.defer(ensureAmy, player)
end

print("[AmyStarterCharacter] Everyone plays as Amy herself.")
