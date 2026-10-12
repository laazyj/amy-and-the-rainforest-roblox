--!strict
--[[
	Camera: the adapter for the locked-behind camera. The logic is the pure
	src/core/CameraModel (tier 1); this module only converts:

	  every frame   Amy's root position in, a Frame out: the camera's CFrame
	                (Scriptable, so the model owns it) and Amy's root turned
	                to the model's facing (AutoRotate off: shift-lock feel)
	  FrameShot     CameraModel.frameShot; a Shot's subject is a Character's
	                Head in Workspace.StoryCharacters, or the forest gap
	  input         mouse look on PC while the right button is held; on
	                touch, a drag that starts outside the control zones
	                (feel.md section 1: thumbstick bottom-left, talk button
	                bottom-right) turns the view
	  spawn         the camera starts behind Amy as she faces; a respawn, or
	                the server putting her somewhere (TeleportPlayer), puts
	                it behind her again

	There is no free-orbit option: the camera never leaves the cone behind
	her, whatever the input.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CameraModel = require(ReplicatedStorage:WaitForChild("core"):WaitForChild("CameraModel"))
local Story = require(ReplicatedStorage:WaitForChild("core"):WaitForChild("Story"))
local Content = require(ReplicatedStorage:WaitForChild("content"):WaitForChild("Story"))

type Vec3 = Story.Vec3

-- How far the view turns per pixel the mouse or a finger moves.
local MOUSE_RADIANS = math.rad(0.35)
local TOUCH_RADIANS = math.rad(0.3)

-- what shot:ForestWallReveal and shot:MachineFinale look toward
local FOREST_GAP: Vec3 = Content.story.zones.ForestGap.centre

local player = Players.LocalPlayer

local Camera = {}

local model: CameraModel.Camera? = nil
local root: BasePart? = nil
-- the last Frame, and where Amy stood for it (tests/studio reads them)
local lastFrame: CameraModel.Frame? = nil
local lastAmy: Vec3? = nil
-- each Character's Head, found once
local heads: { [string]: BasePart? } = {}

local function plain(vector: Vector3): Vec3
	return { x = vector.X, y = vector.Y, z = vector.Z }
end

local function vector(v: Vec3): Vector3
	return Vector3.new(v.x, v.y, v.z)
end

-- Where a Shot's subject is now, or nil when it is not in the world.
local function subject(framing: CameraModel.Framing): Vec3?
	local id = framing.character
	if not id then
		return FOREST_GAP
	end
	local head = heads[id]
	if not head or not head.Parent then
		local characters = Workspace:FindFirstChild("StoryCharacters")
		local character = characters and characters:FindFirstChild(id)
		local found = character and character:FindFirstChild("Head")
		head = if found and found:IsA("BasePart") then found else nil
		heads[id] = head
	end
	return if head then plain(head.Position) else nil
end

local function render(seconds: number)
	local camera = Workspace.CurrentCamera
	local part = root
	if not part or not part.Parent or not model or not camera then
		return
	end
	CameraModel.observe(model, plain(part.CFrame.LookVector))
	local at = part.Position
	local amy = plain(at)
	local frame = CameraModel.step(model, seconds, amy, subject)
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	camera.CFrame = CFrame.lookAt(vector(frame.camera), vector(frame.lookAt))
	local facing = vector(frame.facing)
	if part.CFrame.LookVector:Dot(facing) < 1 - 1e-9 then
		part.CFrame = CFrame.lookAt(at, at + facing)
	end
	lastFrame, lastAmy = frame, amy
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.AutoRotate = false
	local part = character:WaitForChild("HumanoidRootPart") :: BasePart
	-- spawn and respawn: behind Amy as she faces, from the first frame
	model = CameraModel.new(plain(part.CFrame.LookVector))
	root = part
end

local function turn(dx: number, dy: number, radians: number)
	if model then
		-- moving right turns the view right; moving down looks down on her
		CameraModel.turn(model, -dx * radians, dy * radians)
	end
end

local function bindInput()
	local looking = false
	-- the touch turning the view, and where it was last
	local dragging: InputObject? = nil
	local dragAt = Vector3.zero

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			looking = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		elseif input.UserInputType == Enum.UserInputType.Touch and not dragging then
			local camera = Workspace.CurrentCamera
			local size = if camera then camera.ViewportSize else Vector2.zero
			if CameraModel.turnsView(input.Position.X, input.Position.Y, size.X, size.Y) then
				dragging, dragAt = input, input.Position
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if looking and input.UserInputType == Enum.UserInputType.MouseMovement then
			turn(input.Delta.X, input.Delta.Y, MOUSE_RADIANS)
		elseif input == dragging then
			local delta = input.Position - dragAt
			dragAt = input.Position
			turn(delta.X, delta.Y, TOUCH_RADIANS)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			looking = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		elseif input == dragging then
			dragging = nil
		end
	end)
end

-- A FrameShot from the server: the Shot plays once those before it end.
function Camera.frameShot(shot: string, character: string?)
	if model then
		CameraModel.frameShot(model, shot, character)
	end
end

-- The player advanced past the last Line: a held Shot ends.
function Camera.dialogueFinished()
	if model then
		CameraModel.dialogueFinished(model)
	end
end

-- The last Frame and where Amy stood for it, or nil before the first.
function Camera.last(): (CameraModel.Frame?, Vec3?)
	return lastFrame, lastAmy
end

function Camera.start()
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	bindInput()
	RunService:BindToRenderStep("AmyCamera", Enum.RenderPriority.Camera.Value + 1, render)
end

return Camera
