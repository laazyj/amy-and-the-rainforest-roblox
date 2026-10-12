--!strict
--[[
	Tier 3 (Studio, Mac): the Screen layout on a real client, per Device
	class (docs/design/feel.md sections 1, 3, 4 and 6). Ready to run until
	the Mac runner exists (brief mac-001); docs/MAINTENANCE.md, "Device
	classes and the Onboarding in Studio", says how the owner runs it by
	hand under device emulation: a phone and a tablet preset, each in both
	orientations.

	A LocalScript: copy it into StarterPlayer.StarterPlayerScripts, press
	Play, and play the first minute of a fresh Save. Every 0.5 s, and each
	time the viewport changes, it checks the StoryUI:

	  text fits          every visible text shows in full (TextFits)
	  the column         the dialogue box's text column is at most
	                     30 x its TextSize (60 characters)
	  a Line never       the Line's bottom is no lower than the box's
	  scrolls            bottom less its padding (the box clips its text,
	                     so TextFits alone would not show a spill)
	  nothing covers     while shot:Dialogue frames a speaker, once eased
	  the head           in, the box and its name tag stay below the head
	                     window (y 0.5 of the viewport, feel.md section 2)
	  the safe area      every visible element is inside the safe area
	                     (but the full-screen backdrops: the Title screen's
	                     image, the card's overlay and the click catcher)
	  contrast           text against its background is at least 4.5:1,
	                     with the background's transparency composited
	                     over the 3D world, taken at its worst (black or
	                     white) because a LocalScript cannot read pixels;
	                     text over an image is skipped and counted
	  no overlaps        no two visible interactive elements overlap: the
	                     StoryUI's buttons, the Talk-and-advance button
	  touch targets      on touch, each of those, and each talk prompt's
	                     button, is at least 44 x 44 (we design at 48),
	                     and the interactive elements are 8 apart

	And it follows the Onboarding of a fresh Save (feel.md section 6),
	from the first Chapter card: the advance Hint shows large on the first
	Line and clears when it is advanced; the walk Hint (or on touch the
	ring on the thumbstick) shows, and clears once Amy has walked 4 studs;
	the talk Hint (or the pulse round the Talk-and-advance button) shows
	once Dad's prompt does, and clears when his Dialogue arrives; nothing
	of the Onboarding shows after the next Objective. A Resume shows none.

	Every failure prints a [DeviceLayout] FAIL line; a summary prints
	every 30 s, with the viewport and the class. Remove the script before
	publishing: only CI publishes, from the repository, which never has it
	in the place.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local ui = playerGui:WaitForChild("StoryUI") :: ScreenGui
local safeArea = (playerGui:WaitForChild("SafeArea") :: ScreenGui):WaitForChild("Frame") :: Frame
local screen = ui:WaitForChild("Screen") :: Frame
-- the script is not in the place's tree, so the type checker cannot follow these
local Content = ReplicatedStorage:WaitForChild("content")
local hints = (require :: any)(Content:WaitForChild("hints"))
local story = (require :: any)(Content:WaitForChild("Story")).story
local remotes = ReplicatedStorage:WaitForChild("StoryRemotes")
local ScreenLayout = (require :: any)(ReplicatedStorage:WaitForChild("core"):WaitForChild("ScreenLayout"))
local Camera = (require :: any)(player:WaitForChild("PlayerScripts"):WaitForChild("Camera"))
local Contrast = (require :: any)(ReplicatedStorage:WaitForChild("core"):WaitForChild("Contrast"))

local SAMPLE_SECONDS = 0.5
local SUMMARY_SECONDS = 30
local MIN_TARGET = 44
-- how long a Hint may take to show or clear after what calls for it
local WITHIN = 1
-- full-screen backdrops and catchers, outside the safe area on purpose
local FULL_SCREEN = { Screen = true, ClickCatcher = true, TitleOverlay = true, TitleScreen = true }

local checks, failures, skippedContrast = 0, 0, 0
local reported: { [string]: boolean } = {}

-- Each distinct failure prints once, so a held layout does not flood the Output.
local function fail(what: string, detail: string)
	failures += 1
	local line = `[DeviceLayout] FAIL {what}: {detail}`
	if not reported[line] then
		reported[line] = true
		warn(line)
	end
end

local function rectOf(gui: GuiObject): Rect
	local at, size = gui.AbsolutePosition, gui.AbsoluteSize
	return Rect.new(at.X, at.Y, at.X + size.X, at.Y + size.Y)
end

-- The space between two rects that do not overlap.
local function spacing(a: Rect, b: Rect): number
	return math.max(b.Min.X - a.Max.X, a.Min.X - b.Max.X, b.Min.Y - a.Max.Y, a.Min.Y - b.Max.Y)
end

local function overlap(a: Rect, b: Rect): boolean
	return a.Min.X < b.Max.X and b.Min.X < a.Max.X and a.Min.Y < b.Max.Y and b.Min.Y < a.Max.Y
end

-- Whether `gui` and every ancestor up to its ScreenGui are visible.
local function shown(gui: GuiObject): boolean
	local at: Instance? = gui
	while at and at:IsA("GuiObject") do
		if not at.Visible then
			return false
		end
		at = at.Parent
	end
	return true
end

local function isText(gui: Instance): boolean
	return gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox")
end

-- Whether `gui` draws anything: a transparent button covers nothing.
local function draws(gui: GuiObject): boolean
	if gui.BackgroundTransparency < 1 then
		return true
	elseif isText(gui) then
		local text = gui :: TextLabel
		return text.Text ~= "" and text.TextTransparency < 1
	end
	return false
end

-- Whether `gui` is, or is inside, a full-screen backdrop; the Title
-- screen's words and choices are not, and keep to the safe area.
local function backdropOnly(gui: Instance): boolean
	local at: Instance? = gui
	while at and at ~= ui do
		if at.Name == "Words" or at.Name == "Choices" then
			return false
		elseif FULL_SCREEN[at.Name] then
			return true
		end
		at = at.Parent
	end
	return false
end

--[[ Contrast (WCAG 2), feel.md section 3: src/core/Contrast ]]

local function ratio(a: Color3, b: Color3): number
	local function plain(colour: Color3)
		return { r = colour.R * 255, g = colour.G * 255, b = colour.B * 255 }
	end
	return Contrast.ratio(plain(a), plain(b))
end

-- The backgrounds behind `gui`, composited from the nearest up, over the
-- 3D world `world`; nil when an image is behind it.
local function backdrop(gui: GuiObject, world: Color3): Color3?
	local layers: { GuiObject } = {}
	local at: Instance? = gui
	while at and at:IsA("GuiObject") do
		if (at:IsA("ImageLabel") or at:IsA("ImageButton")) and at.Image ~= "" then
			return nil
		end
		table.insert(layers, at)
		at = at.Parent
	end
	local colour = world
	for i = #layers, 1, -1 do
		local layer = layers[i]
		colour = colour:Lerp(layer.BackgroundColor3, 1 - layer.BackgroundTransparency)
	end
	return colour
end

local function checkContrast(text: TextLabel)
	if text.TextStrokeTransparency < 0.5 then
		-- outlined text: its stroke is its background
		if ratio(text.TextColor3, text.TextStrokeColor3) < Contrast.MINIMUM then
			fail("contrast", `{text:GetFullName()} against its outline`)
		end
		return
	end
	local worst = math.huge
	for _, world in { Color3.new(0, 0, 0), Color3.new(1, 1, 1) } do
		local behind = backdrop(text, world)
		if not behind then
			skippedContrast += 1
			return
		end
		worst = math.min(worst, ratio(text.TextColor3, behind))
	end
	if worst < Contrast.MINIMUM then
		fail("contrast", `{text:GetFullName()} is {string.format("%.2f", worst)}:1 at worst`)
	end
end

--[[ The layout checks ]]

local function touch(): boolean
	return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
		or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
end

-- The interactive elements on screen: the StoryUI's buttons, the
-- Talk-and-advance button, and on touch each talk prompt's button.
local function interactive(): { GuiObject }
	local found: { GuiObject } = {}
	for _, gui in ui:GetDescendants() do
		if gui:IsA("GuiButton") and gui.Active and shown(gui) and draws(gui) and not FULL_SCREEN[gui.Name] then
			table.insert(found, gui)
		end
	end
	local talk = ContextActionService:GetButton("TalkAndAdvance")
	if talk and shown(talk) then
		table.insert(found, talk)
	end
	return found
end

local function promptButtons(): { GuiObject }
	local found: { GuiObject } = {}
	for _, gui in playerGui:GetDescendants() do
		if gui:IsA("GuiButton") and shown(gui) and string.find(gui:GetFullName(), "Prompt", 1, true) then
			table.insert(found, gui)
		end
	end
	return found
end

local function checkLayout()
	checks += 1
	local safe = rectOf(safeArea)
	for _, gui in ui:GetDescendants() do
		if not gui:IsA("GuiObject") or not shown(gui) then
			continue
		end
		local box = rectOf(gui)
		if
			not backdropOnly(gui)
			and draws(gui)
			and (
				box.Min.X < safe.Min.X - 1
				or box.Min.Y < safe.Min.Y - 1
				or box.Max.X > safe.Max.X + 1
				or box.Max.Y > safe.Max.Y + 1
			)
		then
			fail("the safe area", `{gui:GetFullName()} at {box.Min} to {box.Max}, safe {safe.Min} to {safe.Max}`)
		end
		if isText(gui) and (gui :: TextLabel).Text ~= "" then
			local text = gui :: TextLabel
			if not text.TextFits then
				fail("text fits", `{text:GetFullName()} ({text.Text})`)
			end
			if text.TextTransparency < 1 then
				checkContrast(text)
			end
		end
	end
	local box = ui:FindFirstChild("DialogueFrame") :: GuiObject?
	local body = ui:FindFirstChild("Body", true) :: TextLabel?
	if box and body and shown(body) then
		if body.AbsoluteSize.X > ScreenLayout.COLUMN_EMS * body.TextSize + 1 then
			fail(
				"the column",
				`{body.AbsoluteSize.X} wide at TextSize {body.TextSize}, over {ScreenLayout.COLUMN_EMS * body.TextSize}`
			)
		end
		-- the box clips its text: a Line that spills past it is cut off unseen
		local floor = box.AbsolutePosition.Y + box.AbsoluteSize.Y - ScreenLayout.BOX.bottom
		if body.AbsolutePosition.Y + body.AbsoluteSize.Y > floor + 1 then
			fail("a Line never scrolls", `{body.Text} reaches below the box's padding`)
		end
		-- nothing covers the speaker's head: during shot:Dialogue the box, its
		-- name tag included, stays below the head window
		local frame = Camera.last()
		local camera = Workspace.CurrentCamera
		local tag = box:FindFirstChild("Speaker") :: GuiObject?
		local top = if tag and shown(tag)
			then math.min(tag.AbsolutePosition.Y, box.AbsolutePosition.Y)
			else box.AbsolutePosition.Y
		local window = if camera then ScreenLayout.HEAD_WINDOW.bottom * camera.ViewportSize.Y else 0
		if frame and frame.shot == "Dialogue" and frame.settled and top - rectOf(screen).Min.Y < window - 1 then
			fail("nothing covers the head", `the box's top at {top}, inside the head window (down to {window})`)
		end
	end
	local buttons = interactive()
	for i, a in buttons do
		for j = i + 1, #buttons do
			local first, second = rectOf(a), rectOf(buttons[j])
			if overlap(first, second) then
				fail("no overlaps", `{a:GetFullName()} and {buttons[j]:GetFullName()}`)
			elseif touch() and spacing(first, second) < ScreenLayout.TARGET_GAP then
				fail(
					"touch targets",
					`{a:GetFullName()} and {buttons[j]:GetFullName()} under {ScreenLayout.TARGET_GAP} apart`
				)
			end
		end
	end
	if touch() then
		for _, list in { buttons, promptButtons() } do
			for _, button in list do
				local size = button.AbsoluteSize
				if size.X < MIN_TARGET or size.Y < MIN_TARGET then
					fail("touch targets", `{button:GetFullName()} is {size.X} x {size.Y}`)
				end
			end
		end
	end
end

--[[ The Onboarding ]]

-- An expectation: `check` must hold within WITHIN seconds of `since`.
type Expect = { what: string, since: number, check: () -> boolean }
local expecting: { Expect } = {}

local function expect(what: string, check: () -> boolean)
	table.insert(expecting, { what = what, since = os.clock(), check = check })
end

local function visible(name: string): boolean
	local gui = ui:FindFirstChild(name, true)
	return gui ~= nil and gui:IsA("GuiObject") and shown(gui)
end

local function largeHint(): boolean
	local hint = ui:FindFirstChild("Lines", true)
	local label = hint and hint:FindFirstChild("Hint") :: TextLabel?
	local text = if touch() then hints.steps.advance.touch else hints.steps.advance.pc
	return label ~= nil and shown(label) and label.Text == text
end

local function walkHint(): boolean
	return if touch() then visible("ThumbstickRing") else visible("OnboardingHint")
end

local function talkHint(): boolean
	return if touch() then visible("TalkRing") else visible("OnboardingHint")
end

local function anyHint(): boolean
	return largeHint() or visible("OnboardingHint") or visible("ThumbstickRing") or visible("TalkRing")
end

local fresh: boolean? = nil -- nil until the Story's first message
local dialogues, objectives = 0, 0
local walkFrom: Vector3? = nil

local function amyAt(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position * Vector3.new(1, 0, 1) else nil
end

local showChapter = remotes:WaitForChild("ShowChapter") :: RemoteEvent
local setObjective = remotes:WaitForChild("SetObjective") :: RemoteEvent
local showDialogue = remotes:WaitForChild("ShowDialogue") :: RemoteEvent

showChapter.OnClientEvent:Connect(function(title: string)
	if fresh == nil then
		fresh = title == story.chapters[1].title
		print(`[DeviceLayout] a {if fresh then "fresh Save: following the Onboarding" else "Resume"}`)
	end
end)
setObjective.OnClientEvent:Connect(function(text: string?)
	if fresh == nil then
		fresh = false
		print("[DeviceLayout] a Resume: no Onboarding")
		expect("no Hint on a Resume", function()
			return not anyHint()
		end)
	end
	if text and text ~= "" then
		objectives += 1
		if objectives == 2 then
			expect("nothing of the Onboarding after the next Objective", function()
				return not anyHint() and not visible("Skip")
			end)
		end
	end
end)
showDialogue.OnClientEvent:Connect(function()
	dialogues += 1
	if fresh and dialogues == 2 then
		expect("the talk Hint clears when Dad's Dialogue arrives", function()
			return not talkHint()
		end)
	end
end)

-- The first Line's Hint: shown large once the card has gone, cleared
-- when the Line is advanced; then the walk Hint.
local stage = "card"
local function followOnboarding()
	if not fresh then
		return
	end
	local boxShown = visible("DialogueFrame")
	if stage == "card" and boxShown and not visible("TitleOverlay") then
		stage = "advance"
		expect("the advance Hint shows large on the first Line", largeHint)
	elseif stage == "advance" and not boxShown then
		stage = "walk"
		walkFrom = amyAt()
		expect("the walk Hint shows after the first Line", walkHint)
	elseif stage == "walk" then
		local at = amyAt()
		if at and walkFrom and (at - walkFrom).Magnitude >= 4 then
			stage = "talk"
			expect("the walk Hint clears once Amy has walked 4 studs", function()
				return not walkHint()
			end)
		end
	end
end

game:GetService("ProximityPromptService").PromptShown:Connect(function()
	if fresh and stage == "talk" and dialogues == 1 then
		expect("the talk Hint shows with Dad's prompt", talkHint)
	end
end)

local function settle()
	local now = os.clock()
	for i = #expecting, 1, -1 do
		local each = expecting[i]
		if each.check() then
			checks += 1
			print(`[DeviceLayout] ok: {each.what}`)
			table.remove(expecting, i)
		elseif now - each.since > WITHIN then
			fail("the Onboarding", `{each.what}: not within {WITHIN} s`)
			table.remove(expecting, i)
		end
	end
end

--[[ When ]]

local function summary()
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.zero
	print(
		`[DeviceLayout] {checks} checks, {failures} failures, {skippedContrast} texts over images not measured; `
			.. `viewport {size.X} x {size.Y}, {if touch() then "touch" else "pointer"}`
	)
end

screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	task.defer(checkLayout) -- after the binder has laid out again
end)

local sinceSample, sinceSummary = 0, 0
RunService.Heartbeat:Connect(function(seconds)
	followOnboarding()
	settle()
	sinceSample += seconds
	if sinceSample >= SAMPLE_SECONDS then
		sinceSample = 0
		checkLayout()
	end
	sinceSummary += seconds
	if sinceSummary >= SUMMARY_SECONDS then
		sinceSummary = 0
		summary()
	end
end)

print("[DeviceLayout] checking the Screen layout every 0.5 s and on every viewport change")
