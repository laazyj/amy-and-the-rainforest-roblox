--!strict
--[[
	Camera: the adapter for the locked-behind camera. The logic is the pure
	src/core/CameraModel (tier 1); this module only converts:

	  every frame   Amy's root position in, a Frame out: the camera's CFrame
	                (Scriptable from the moment `start` runs, so no frame is
	                Roblox's default camera's) and Amy's root turned to the
	                model's facing (AutoRotate off: shift-lock feel). The
	                camera is pulled in along its ray when something stands
	                between it and Amy (at once; it eases back out over
	                0.3 s); its direction, and so the camera rule, is
	                unchanged.
	  FrameShot     CameraModel.frameShot; a Shot's subject is a Character's
	                Head in Workspace.StoryCharacters, or the forest gap.
	                The Characters' name tags hide while shot:Dialogue plays
	                (feel.md: nothing covers the subject)
	  input         PC: the turn keys (CameraModel.TURN_KEYS: A/D and the
	                Left/Right arrows) turn Amy and the view, W/S and Up/Down
	                walk, and a right-mouse drag turns too; the pointer is
	                never locked. Touch: a drag that starts outside the
	                control zones (feel.md section 1) turns the view
	  spawn         each new character is found the frame it appears, and
	                the camera starts behind Amy as she faces; on death (her
	                joints kept, so she stays in one piece) the last Frame
	                holds until she respawns. The server putting
	                her somewhere (TeleportPlayer) or a Resume puts the
	                camera behind her again

	There is no free-orbit option: the camera never leaves the cone behind
	her, whatever the input.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
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
-- The closest an obstacle pulls the camera to Amy, and the gap it keeps
-- in front of the obstacle.
local NEAREST = 2
local CLEARANCE = 0.5

-- what shot:ForestWallReveal and shot:MachineFinale look toward
local FOREST_GAP: Vec3 = Content.story.zones.ForestGap.centre

local player = Players.LocalPlayer

local Camera = {}

local model: CameraModel.Camera? = nil
-- the character the model follows, its root, and whether it has died
local following: Model? = nil
local root: BasePart? = nil
local dead = false
-- how far out along its ray toward the Frame's camera the camera is, 0 to 1
local reach = 1
-- the last Frame, and where Amy stood for it (tests/studio reads them)
local lastFrame: CameraModel.Frame? = nil
local lastAmy: Vec3? = nil
-- each Character's Head, found once
local heads: { [string]: BasePart? } = {}
-- the turn keys held, by KeyCode name
local held: { [string]: boolean } = {}
-- whether the last Frame was shot:Dialogue's, to notice when it starts or ends
local inDialogue = false

local obstacles = RaycastParams.new()
obstacles.FilterType = Enum.RaycastFilterType.Exclude
obstacles.RespectCanCollide = true

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

-- The Characters' name tags show, or hide while shot:Dialogue plays.
local function showNameTags(shown: boolean)
	local characters = Workspace:FindFirstChild("StoryCharacters")
	for _, tag in if characters then characters:GetDescendants() else {} do
		if tag:IsA("BillboardGui") and tag.Name == "NameTag" then
			tag.Enabled = shown
		end
	end
end

-- The player's current character, followed from the frame it has a root:
-- a new one (spawn, respawn) gets a camera behind Amy as she faces.
local function follow(): BasePart?
	local current = player.Character
	if current ~= following then
		local part = current and current:FindFirstChild("HumanoidRootPart")
		local humanoid = current and current:FindFirstChildOfClass("Humanoid")
		if not (part and part:IsA("BasePart") and humanoid) then
			return nil -- not built yet: the camera holds where it is
		end
		following, root, dead, reach = current, part, false, 1
		model = CameraModel.new(plain(part.CFrame.LookVector))
		obstacles.FilterDescendantsInstances = { current }
		humanoid.AutoRotate = false
		-- she can fall out of the world: a death keeps her in one piece, so
		-- no loose head rolls round to face the held camera
		humanoid.BreakJointsOnDeath = false
		humanoid.Died:Once(function()
			dead = true
		end)
	end
	return root
end

-- `at` pulled in toward Amy's root `from` when something stands between,
-- at once, and eased back out when it has gone.
local function unoccluded(from: Vector3, at: Vector3, seconds: number): Vector3
	local ray = at - from
	local hit = if ray.Magnitude > NEAREST then Workspace:Raycast(from, ray, obstacles) else nil
	local clear = if hit then math.max(NEAREST, hit.Distance - CLEARANCE) / ray.Magnitude else 1
	reach = CameraModel.pullIn(reach, clear, seconds)
	return from + ray * reach
end

local function render(seconds: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local part = follow()
	if not part or not model or dead then
		return -- no Amy yet, or she has died: the last Frame holds
	end
	local yaw = CameraModel.keyTurn(held, seconds)
	if yaw ~= 0 then
		CameraModel.turn(model, yaw, 0)
	end
	CameraModel.observe(model, plain(part.CFrame.LookVector))
	local at = part.Position
	local amy = plain(at)
	local frame = CameraModel.step(model, seconds, amy, subject)
	camera.CFrame = CFrame.lookAt(unoccluded(at, vector(frame.camera), seconds), vector(frame.lookAt))
	local facing = vector(frame.facing)
	if part.CFrame.LookVector:Dot(facing) < 1 - 1e-9 then
		part.CFrame = CFrame.lookAt(at, at + facing)
	end
	local dialogue = frame.shot == "Dialogue"
	if dialogue ~= inDialogue then
		showNameTags(not dialogue)
		inDialogue = dialogue
	end
	lastFrame, lastAmy = frame, amy
end

local function turn(dx: number, dy: number, radians: number)
	if model then
		-- moving right turns the view right; moving down looks down on her
		CameraModel.turn(model, -dx * radians, dy * radians)
	end
end

local function bindInput()
	-- The turn keys turn instead of strafing: bound above the default
	-- controls, which then never see them.
	local keys = {}
	for name in CameraModel.TURN_KEYS do
		table.insert(keys, (Enum.KeyCode :: any)[name])
	end
	ContextActionService:BindActionAtPriority("AmyTurn", function(_, state: Enum.UserInputState, input: InputObject)
		held[input.KeyCode.Name] = state == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, table.unpack(keys))

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
			-- a touch's Position is below the top bar; the viewport includes it
			local size = if camera then camera.ViewportSize else Vector2.zero
			local at = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
			if CameraModel.turnsView(at.X, at.Y, size.X, size.Y) then
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

-- A Resume (Continue, or a Dev shortcut's jump) rebuilt the world: any
-- Shot ends and the camera goes behind Amy.
function Camera.resumed()
	if model and root then
		CameraModel.place(model, plain(root.CFrame.LookVector))
	end
end

-- The last Frame and where Amy stood for it, or nil before the first.
function Camera.last(): (CameraModel.Frame?, Vec3?)
	return lastFrame, lastAmy
end

-- Takes the camera at once, before anything yields: from here on every
-- frame is the model's.
function Camera.start()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	RunService:BindToRenderStep("AmyCamera", Enum.RenderPriority.Camera.Value + 1, render)
	bindInput()
end

return Camera
