--!strict
--[[
	Tier 3 (Studio, Mac): Amy's face is never seen (docs/design/feel.md,
	"Invariants" and section 2). Ready to run until the Mac runner exists
	(brief mac-001); docs/MAINTENANCE.md, "The camera rule in Studio", says
	how the owner runs it by hand.

	A LocalScript: copy it into StarterPlayer.StarterPlayerScripts, press
	Play, and play (or jump with /chapter N). It checks, on the real
	camera and Amy's real character:

	  at the first frames after CharacterAdded (spawn and respawn), at
	  every Shot keyframe (the frame a Shot starts, the frame it has
	  eased in, the frame it ends) and every 0.25 s of play (feel.md asks
	  for at least every 0.5 s):
	    the camera rule      unit(camera − Amy's root) · (−facing) ≥ 0.5
	    her head from behind the camera is behind the plane of her face
	                         (unit(camera − head) · head's look ≤ 0)
	  while shot:Dialogue frames a speaker, once it has eased in:
	    the head's place     the speaker's head point inside x 0.33-0.67,
	                         y 0.15-0.5 of the viewport
	    no name tag shown    every Character's name tag (BillboardGui) is
	                         hidden while the Shot plays
	    nothing covers it    no visible UI element overlaps the projected
	                         bounding box of the speaker's head

	Every failure prints a [CameraRule] FAIL line; a summary prints every
	30 s and when the Story ends (the end card). Remove the script before
	publishing: only CI publishes, from the repository, which never has it
	in the place.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerScripts = player:WaitForChild("PlayerScripts")
local playerGui = player:WaitForChild("PlayerGui")
local Camera = (require :: any)(playerScripts:WaitForChild("Camera"))
local Core = ReplicatedStorage:WaitForChild("core")
-- the script is not in the place's tree, so the type checker cannot follow these
local CameraModel = (require :: any)(Core:WaitForChild("CameraModel"))

local SAMPLE_SECONDS = 0.25
local SUMMARY_SECONDS = 30
local HEAD_WINDOW = { left = 0.33, right = 0.67, top = 0.15, bottom = 0.5 }

local checks, failures = 0, 0

local function fail(what: string, detail: string)
	failures += 1
	warn(`[CameraRule] FAIL {what}: {detail}`)
end

local function unit(v: Vector3): Vector3
	return if v.Magnitude > 1e-9 then v.Unit else Vector3.zero
end

-- The projected bounding box of `part` in viewport pixels, or nil when any
-- corner is behind the camera.
local function screenBox(camera: Camera, part: BasePart): Rect?
	local half = part.Size / 2
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local corner = part.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
				local point, inFront = camera:WorldToViewportPoint(corner)
				if not inFront then
					return nil
				end
				minX, minY = math.min(minX, point.X), math.min(minY, point.Y)
				maxX, maxY = math.max(maxX, point.X), math.max(maxY, point.Y)
			end
		end
	end
	return Rect.new(minX, minY, maxX, maxY)
end

-- Whether `gui` draws anything: a full-screen transparent button (the
-- dialogue's click catcher) covers nothing.
local function draws(gui: GuiObject): boolean
	if gui.BackgroundTransparency < 1 then
		return true
	elseif gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
		return gui.Text ~= "" and gui.TextTransparency < 1
	elseif gui:IsA("ImageLabel") or gui:IsA("ImageButton") then
		return gui.Image ~= "" and gui.ImageTransparency < 1
	end
	return false
end

-- The visible UI elements over the 3D view that overlap `box`.
local function covering(box: Rect): { string }
	local found = {}
	for _, screen in playerGui:GetChildren() do
		if screen:IsA("ScreenGui") and screen.Enabled then
			-- AbsolutePosition is below the top bar unless the ScreenGui ignores it
			local inset = if screen.IgnoreGuiInset then Vector2.zero else GuiService:GetGuiInset()
			for _, gui in screen:GetDescendants() do
				if gui:IsA("GuiObject") and gui.Visible and draws(gui) then
					local at, size = gui.AbsolutePosition, gui.AbsoluteSize
					local left, top = at.X + inset.X, at.Y + inset.Y
					if
						left < box.Max.X
						and left + size.X > box.Min.X
						and top < box.Max.Y
						and top + size.Y > box.Min.Y
					then
						table.insert(found, gui:GetFullName())
					end
				end
			end
		end
	end
	return found
end

-- `settled`: the Shot has eased in, so it frames its subject.
local function check(why: string, settled: boolean)
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not camera or not root or not head then
		return
	end
	checks += 1
	local at = camera.CFrame.Position
	local facing = unit(root.CFrame.LookVector * Vector3.new(1, 0, 1))
	local cosine = unit(at - root.Position):Dot(-facing)
	if cosine < CameraModel.RULE_COSINE then
		fail("the camera rule", `{why}: unit(camera − Amy) · (−facing) = {string.format("%.3f", cosine)}`)
	end
	local fromFront = unit(at - head.Position):Dot(head.CFrame.LookVector)
	if fromFront > 0 then
		fail("her head from behind", `{why}: the camera is in front of her face ({string.format("%.3f", fromFront)})`)
	end

	local frame = Camera.last()
	if not settled or not frame or frame.shot ~= "Dialogue" or not frame.character then
		return
	end
	local characters = Workspace:FindFirstChild("StoryCharacters")
	local speaker = characters and characters:FindFirstChild(frame.character)
	local speakerHead = speaker and speaker:FindFirstChild("Head") :: BasePart?
	if not speakerHead then
		return
	end
	local viewport = camera.ViewportSize
	local point = camera:WorldToViewportPoint(speakerHead.Position)
	local x, y = point.X / viewport.X, point.Y / viewport.Y
	if x < HEAD_WINDOW.left or x > HEAD_WINDOW.right or y < HEAD_WINDOW.top or y > HEAD_WINDOW.bottom then
		fail("the speaker's head", `{why}: {frame.character}'s head at ({string.format("%.2f, %.2f", x, y)})`)
	end
	for _, tag in (characters :: Instance):GetDescendants() do
		if tag:IsA("BillboardGui") and tag.Name == "NameTag" and tag.Enabled then
			fail("no name tag shown", `{why}: {tag:GetFullName()} shows during shot:Dialogue`)
		end
	end
	local box = screenBox(camera, speakerHead)
	local over = if box then covering(box) else {}
	if #over > 0 then
		fail("nothing covers the subject", `{why}: {table.concat(over, ", ")} over {frame.character}'s head`)
	end
end

local function summary()
	print(`[CameraRule] {checks} checks, {failures} failures`)
end

-- Every Shot keyframe, and a sample every 0.25 s.
-- the first frames after CharacterAdded (spawn, respawn) are each checked
local FIRST_FRAMES = 3
local fresh = 0
player.CharacterAdded:Connect(function()
	fresh = FIRST_FRAMES
end)
if player.Character then
	fresh = FIRST_FRAMES
end

local shot: string? = nil
local eased = false
local sinceSample, sinceSummary = 0, 0
RunService:BindToRenderStep("CameraRuleCheck", Enum.RenderPriority.Last.Value, function(seconds)
	local frame = Camera.last()
	local framed = frame and frame.shot
	if fresh > 0 and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		fresh -= 1
		check(`frame {FIRST_FRAMES - fresh} after CharacterAdded`, false)
	end
	if framed ~= shot then
		check(if framed then `{framed} starts` else `{shot} ends`, false)
		shot, eased = framed, false
	end
	-- the model says when a Shot has eased in: at least 0.5 s, longer after a long swing
	local settled = frame ~= nil and frame.settled == true
	if settled and not eased then
		eased = true
		check(`{framed} eased in`, true)
	end
	sinceSample += seconds
	if sinceSample >= SAMPLE_SECONDS then
		sinceSample = 0
		check(if framed then `during {framed}` else "free play", settled)
	end
	sinceSummary += seconds
	if sinceSummary >= SUMMARY_SECONDS then
		sinceSummary = 0
		summary()
	end
end)

-- The end card: the playthrough is over.
local showEnding = ReplicatedStorage:WaitForChild("StoryRemotes"):WaitForChild("ShowEnding") :: RemoteEvent
showEnding.OnClientEvent:Connect(summary)
print("[CameraRule] checking the camera rule every 0.25 s and at every Shot keyframe")
