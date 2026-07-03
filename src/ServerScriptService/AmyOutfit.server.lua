--[[
	AmyOutfit
	=========
	Dresses every player as Amy from the hero drawing on
	clara.jasonduffett.net: red jumper, blue skirt, long brown hair.

	The player keeps their own head, face and skin tone -- so it still
	feels like THEM stepping into the story -- but their clothing and
	accessories are replaced with Amy's outfit. Everything here is
	built from parts, so no uploaded catalog assets are needed.

	How it works:
	  * a HumanoidDescription recolours the torso and arms red (the
	    jumper), strips shirts/pants/accessories, and matches the leg
	    colour to the player's own skin tone (bare legs, like the
	    drawing)
	  * a part-built hair Accessory (brown bob with long back) snaps to
	    the head's HairAttachment
	  * a part-built skirt Accessory hangs from the waist attachment
]]

local Players = game:GetService("Players")

local JUMPER_RED = Color3.fromRGB(198, 74, 56)
local SKIRT_BLUE = Color3.fromRGB(52, 108, 202)
local HAIR_BROWN = Color3.fromRGB(94, 64, 44)
local FALLBACK_SKIN = Color3.fromRGB(228, 194, 160)

----------------------------------------------------------------
-- Part-built accessories (no catalog assets required)
----------------------------------------------------------------
local function makeHairAccessory()
	local accessory = Instance.new("Accessory")
	accessory.Name = "AmyHair"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Shape = Enum.PartType.Ball
	handle.Size = Vector3.new(2.35, 2.2, 2.35)
	handle.Color = HAIR_BROWN
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Massless = true

	-- the accessory system lines this up with the head's HairAttachment;
	-- sinking it a little makes the dome sit on the scalp, not hover
	local attachment = Instance.new("Attachment")
	attachment.Name = "HairAttachment"
	attachment.Position = Vector3.new(0, -0.4, 0)
	attachment.Parent = handle

	-- Amy's long hair, hanging down the back (+Z is behind the head)
	local back = Instance.new("Part")
	back.Name = "HairBack"
	back.Size = Vector3.new(1.9, 2.7, 0.7)
	back.Color = HAIR_BROWN
	back.Material = Enum.Material.SmoothPlastic
	back.CanCollide = false
	back.Massless = true

	local weld = Instance.new("Weld")
	weld.Part0 = handle
	weld.Part1 = back
	weld.C0 = CFrame.new(0, -1.15, 0.85)
	weld.Parent = handle

	back.Parent = accessory
	handle.Parent = accessory
	return accessory
end

local function makeSkirtAccessory()
	local accessory = Instance.new("Accessory")
	accessory.Name = "AmySkirt"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(2.5, 1.3, 1.7)
	handle.Color = SKIRT_BLUE
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Massless = true

	-- placing the attachment near the TOP of the handle makes the
	-- skirt hang downward from the character's waist line
	local attachment = Instance.new("Attachment")
	attachment.Name = "WaistCenterAttachment"
	attachment.Position = Vector3.new(0, 0.6, 0)
	attachment.Parent = handle

	handle.Parent = accessory
	return accessory
end

----------------------------------------------------------------
-- Dressing
----------------------------------------------------------------
local function dressAsAmy(character)
	if character:GetAttribute("AmyDressed") then
		return
	end
	character:SetAttribute("AmyDressed", true)

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Recolour + strip clothing via HumanoidDescription where we can
	local ok, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)

	if ok and description then
		local skin = description.HeadColor
		if skin == Color3.new(0, 0, 0) then
			skin = FALLBACK_SKIN
		end

		description.TorsoColor = JUMPER_RED
		description.LeftArmColor = JUMPER_RED
		description.RightArmColor = JUMPER_RED
		-- bare legs in the player's own skin tone, like the drawing
		description.LeftLegColor = skin
		description.RightLegColor = skin

		-- no marketplace clothing or accessories over the outfit
		description.Shirt = 0
		description.Pants = 0
		description.GraphicTShirt = 0
		description.HatAccessory = ""
		description.HairAccessory = ""
		description.FaceAccessory = ""
		description.NeckAccessory = ""
		description.ShouldersAccessory = ""
		description.FrontAccessory = ""
		description.BackAccessory = ""
		description.WaistAccessory = ""

		pcall(function()
			humanoid:ApplyDescription(description)
		end)
	else
		-- Fallback (e.g. appearance never loaded): recolour directly
		humanoid:RemoveAccessories()
		local bodyColors = character:FindFirstChildOfClass("BodyColors")
		if bodyColors then
			bodyColors.TorsoColor3 = JUMPER_RED
			bodyColors.LeftArmColor3 = JUMPER_RED
			bodyColors.RightArmColor3 = JUMPER_RED
			bodyColors.LeftLegColor3 = FALLBACK_SKIN
			bodyColors.RightLegColor3 = FALLBACK_SKIN
		end
		for _, item in ipairs(character:GetChildren()) do
			if item:IsA("Shirt") or item:IsA("Pants") or item:IsA("ShirtGraphic") then
				item:Destroy()
			end
		end
	end

	-- Amy's hair and skirt
	humanoid:AddAccessory(makeHairAccessory())
	humanoid:AddAccessory(makeSkirtAccessory())
end

----------------------------------------------------------------
-- Wiring
----------------------------------------------------------------
local function watchPlayer(player)
	-- Preferred moment: the profile appearance has fully loaded, so the
	-- description we edit is their real one.
	player.CharacterAppearanceLoaded:Connect(dressAsAmy)

	-- Safety net: if appearance loading stalls (offline test rigs),
	-- dress whatever character we have after a short wait.
	player.CharacterAdded:Connect(function(character)
		task.delay(3, function()
			if character.Parent then
				dressAsAmy(character)
			end
		end)
	end)

	if player.Character then
		task.delay(1, function()
			if player.Character then
				dressAsAmy(player.Character)
			end
		end)
	end
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end

print("[AmyOutfit] Every explorer gets the red jumper and blue skirt.")
