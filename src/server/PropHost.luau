--!strict
--[[
	PropHost: the Props and their states.

	  prop:Machine    absent, advancing (built, blade spinning, smoke
	                  rising), stopped (blade still, smoke gone), retreating
	                  (stopped, and slowly reversing away from the forest)
	  prop:Villagers  absent, gathered (the crowd stands at its Spots),
	                  cheering (gathered, with sparkles over the crowd)

	Each state can be set from any other, so a Resume can go straight to it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Story = require(ReplicatedStorage:WaitForChild("core"):WaitForChild("Story"))
-- for the types of its Props' data only; the data comes from the Story
local Field = require(ReplicatedStorage:WaitForChild("content"):WaitForChild("scenes"):WaitForChild("Field"))
local CharacterHost = require(script.Parent.CharacterHost)
local Convert = require(script.Parent.Convert)

local PropHost = {}

local spots: { [string]: Story.Spot } = {}
-- each Prop's data from the Story: its states and how it is placed
local machineData: Field.Machine
local villagersData: Field.Villagers

----------------------------------------------------------------
-- The giant tree-chopping machine
----------------------------------------------------------------
local machineModel: Model? = nil
local machineBladeModel: Model? = nil
local machineBladeBase: CFrame? = nil
local machineSpinning = false
local machineSmoke: ParticleEmitter? = nil

local function buildMachine()
	local pos = Convert.vector(assert(spots[machineData.spot], machineData.spot).at)
	local groundY = pos.Y
	local model = Instance.new("Model")
	model.Name = "TreeChoppingMachine"

	local METAL = Color3.fromRGB(74, 78, 84)
	local METAL_DARK = Color3.fromRGB(52, 54, 58)
	local WARN_GOLD = Color3.fromRGB(231, 181, 58)

	local function machinePart(props: { [string]: any }, parent: Instance?): Part
		local part = Instance.new("Part")
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		for key, value in props do
			(part :: any)[key] = value
		end
		part.Parent = parent or model
		return part
	end

	-- hull (facing +Z, toward the forest)
	local hull = machinePart({
		Name = "Hull",
		Size = Vector3.new(12, 8, 16),
		CFrame = CFrame.new(pos.X, groundY + 6, pos.Z),
		Color = METAL,
		Material = Enum.Material.DiamondPlate,
	})
	-- cab on top
	machinePart({
		Name = "Cab",
		Size = Vector3.new(8, 5, 6),
		CFrame = CFrame.new(pos.X, groundY + 12.5, pos.Z - 3),
		Color = METAL_DARK,
		Material = Enum.Material.Metal,
	})
	machinePart({
		Name = "CabWindow",
		Size = Vector3.new(6.5, 3, 0.5),
		CFrame = CFrame.new(pos.X, groundY + 12.8, pos.Z + 0.2),
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
			CFrame = CFrame.new(pos.X - 4.5 + k * 3, groundY + 3, pos.Z + 8.1),
			Color = if k % 2 == 0 then WARN_GOLD else METAL_DARK,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
	end
	-- wheels
	for sx = -1, 1, 2 do
		for _, wz in { -5, 5 } do
			machinePart({
				Name = "Wheel",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(2.4, 5.5, 5.5),
				CFrame = CFrame.new(pos.X + sx * 7, groundY + 2.75, pos.Z + wz) * CFrame.Angles(0, 0, math.rad(90)),
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
		CFrame = CFrame.new(pos.X + 4, groundY + 13, pos.Z - 6) * CFrame.Angles(0, 0, math.rad(90)),
		Color = METAL_DARK,
		Material = Enum.Material.Metal,
	})
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 90, 90))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, 6),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(2, 3.5)
	smoke.Rate = 12
	smoke.Speed = NumberRange.new(6, 9)
	smoke.EmissionDirection = Enum.NormalId.Right
	smoke.Parent = chimney
	machineSmoke = smoke

	-- THE BLADE: a giant circular saw on the front
	local bladeModel = Instance.new("Model")
	bladeModel.Name = "Blade"
	local bladeCenter = CFrame.new(pos.X, groundY + 6.5, pos.Z + 9.5)
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
		while machineModel == model do
			if machineSpinning then
				-- the hub cylinder's axis (its local X) points at the forest,
				-- so spinning about local X turns the disc in its own plane
				angle = angle + 0.18
				bladeModel:PivotTo((machineBladeBase :: CFrame) * CFrame.Angles(angle, 0, 0))
			end
			task.wait(0.03)
		end
	end)
end

-- The machine slowly reverses away from the forest.
local function retreat(model: Model)
	local bladeModel = machineBladeModel
	task.spawn(function()
		local start = model:GetPivot()
		local bladeStart = bladeModel and bladeModel:GetPivot()
		local distance = machineData.retreatDistance
		local duration = machineData.retreatSeconds
		local elapsed = 0
		while elapsed < duration and machineModel == model do
			local dt = task.wait(0.05)
			elapsed = elapsed + dt
			local alpha = math.min(elapsed / duration, 1)
			local offset = Vector3.new(0, 0, -distance * alpha)
			model:PivotTo(start + offset)
			if bladeModel and bladeStart then
				bladeModel:PivotTo(bladeStart + offset)
			end
		end
	end)
end

local machineState = "absent"

local function setMachine(state: string)
	if state == machineState then
		return
	end
	-- A machine that has backed away is rebuilt at its Spot for any other
	-- state, so a Resume can go from retreating back to advancing.
	if machineModel and (state == "absent" or machineState == "retreating") then
		machineModel:Destroy()
		machineModel, machineBladeModel, machineSmoke = nil, nil, nil
	end
	machineState = state
	if state == "absent" then
		return
	end
	if not machineModel then
		buildMachine()
	end
	local model = machineModel :: Model
	machineSpinning = state == "advancing"
	if machineSmoke then
		machineSmoke.Enabled = state == "advancing"
	end
	if state == "retreating" then
		retreat(model)
	end
end

----------------------------------------------------------------
-- The villagers who come with the machine
----------------------------------------------------------------
local villagers: Model? = nil

local function gather()
	if villagers then
		return
	end
	local crowd = Instance.new("Model")
	crowd.Name = "Villagers"
	for k, spotId in villagersData.spots do
		CharacterHost.buildHuman(
			"Villager" .. k,
			"Villager",
			Convert.colour(villagersData.shirts[k]),
			(assert(spots[spotId], spotId)),
			crowd
		)
	end
	crowd.Parent = Workspace
	villagers = crowd
end

-- Celebration sparkles over the crowd, for a few seconds.
local function cheer()
	for _, burst in villagersData.sparkles do
		local holder = Instance.new("Part")
		holder.Anchored = true
		holder.CanCollide = false
		holder.Transparency = 1
		holder.Size = Vector3.new(1, 1, 1)
		holder.CFrame = CFrame.new(Convert.vector(burst.at))
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(Convert.colour(burst.colour))
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new(0.7)
		emitter.Lifetime = NumberRange.new(1.5, 2.5)
		emitter.Rate = 40
		emitter.Speed = NumberRange.new(8, 14)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Parent = holder
		holder.Parent = Workspace
		task.delay(villagersData.sparkleSeconds, function()
			holder:Destroy()
		end)
	end
end

local function setVillagers(state: string)
	if state == "absent" then
		if villagers then
			villagers:Destroy()
		end
		villagers = nil
		return
	end
	gather()
	if state == "cheering" then
		cheer()
	end
end

----------------------------------------------------------------

local SETTERS: { [string]: (state: string) -> () } = {
	Machine = setMachine,
	Villagers = setVillagers,
}

function PropHost.build(story: Story.Story)
	spots = story.spots
	for id in story.props do
		assert(SETTERS[id], `PropHost cannot set prop:{id}`)
	end
	machineData = story.props.Machine :: any
	villagersData = story.props.Villagers :: any
end

function PropHost.setState(prop: string, state: string)
	local setter = SETTERS[prop]
	if setter then
		setter(state)
	end
end

return PropHost
