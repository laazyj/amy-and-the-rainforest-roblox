--!strict
--[[
	StoryClient: the client binder. It renders the core view-model and
	forwards input; the logic is in the core, tested in tier 1:

	  ShowDialogue    -> DialogueViewModel: the dialogue box, typed out
	  SetObjective    -> ObjectiveText: the Objective tracker (top right)
	  ShowChapter /   -> ChapterCardTimeline: the Chapter card and the end card
	  ShowEnding
	  ShowTitle       -> TitleScreen: the Title screen's choices
	  FrameShot       -> Camera (src/client/Camera, over CameraModel): the
	                     Shot, framed from behind Amy

	Every remote it receives is held to the Net contract first (Net.guard);
	a malformed payload is dropped with a warning.

	Click, tap, or press E, Space or Enter to advance a Dialogue; when the
	view-model says it is finished, DialogueFinished goes to the server.
	The Title screen shows while the client loads; a returning player's
	Title choice goes to the server as TitleChoice.

	Every screen is laid out for the Device class (DeviceClass: PC, Phone
	or Tablet, from the last input and the viewport) by ScreenLayout, again
	whenever the viewport, the safe area or the last input kind changes
	(a rotation, a resize, a keyboard on a tablet). The safe area is
	measured by a probe ScreenGui that keeps out of the notch, the home
	bar and Roblox's top bar (ScreenInsets CoreUISafeInsets).
	What is left here is building the UI, turning plain colours into
	Color3, and connecting remotes, input and the frame loop.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- The camera first, before anything here yields: every frame is its own.
local Camera = require(script.Parent:WaitForChild("Camera"))
Camera.start()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Core = ReplicatedStorage:WaitForChild("core")
local ChapterCardTimeline = require(Core:WaitForChild("ChapterCardTimeline"))
local DeviceClass = require(Core:WaitForChild("DeviceClass"))
local DialogueViewModel = require(Core:WaitForChild("DialogueViewModel"))
local Events = require(Core:WaitForChild("Events"))
local ObjectiveText = require(Core:WaitForChild("ObjectiveText"))
local Story = require(Core:WaitForChild("Story"))
local Net = require(Core:WaitForChild("Net"))
local ScreenLayout = require(Core:WaitForChild("ScreenLayout"))
local TitleScreen = require(Core:WaitForChild("TitleScreen"))
local palette = require(ReplicatedStorage:WaitForChild("content"):WaitForChild("palette")).colours
local Shared = ReplicatedStorage:WaitForChild("shared")
local AssetIds = require(Shared:WaitForChild("AssetIds"))
local Remotes = require(Shared:WaitForChild("Net"))

local remotes = Remotes.waitForRemotes()
local ShowDialogue = remotes.ShowDialogue
local DialogueFinished = remotes.DialogueFinished
local SetObjective = remotes.SetObjective
local ShowChapter = remotes.ShowChapter
local ShowEnding = remotes.ShowEnding
local ClientReady = remotes.ClientReady
local ShowTitle = remotes.ShowTitle
local TitleChoice = remotes.TitleChoice
local FrameShot = remotes.FrameShot

-- The view-model's colours are a few frozen tables; each becomes a Color3 once.
local colours: { [Story.RGB]: Color3 } = {}
local function rgb(colour: Story.RGB): Color3
	local converted = colours[colour]
	if not converted then
		converted = Color3.fromRGB(colour.r, colour.g, colour.b)
		colours[colour] = converted
	end
	return converted
end

----------------------------------------------------------------
-- Build the UI
----------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StoryUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.Parent = playerGui

-- The whole screen, to measure the viewport by, and a probe kept inside the
-- safe area, to measure the insets by.
local root = Instance.new("Frame")
root.Name = "Screen"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = screenGui

local safeAreaGui = Instance.new("ScreenGui")
safeAreaGui.Name = "SafeArea"
safeAreaGui.ResetOnSpawn = false
safeAreaGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
safeAreaGui.Parent = playerGui
local safeArea = Instance.new("Frame")
safeArea.Size = UDim2.fromScale(1, 1)
safeArea.BackgroundTransparency = 1
safeArea.Parent = safeAreaGui

local function addPadding(guiObject: GuiObject, top: number, bottom: number, sides: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingBottom = UDim.new(0, bottom)
	padding.PaddingLeft = UDim.new(0, sides)
	padding.PaddingRight = UDim.new(0, sides)
	padding.Parent = guiObject
end

local function addCorner(guiObject: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = guiObject
end

-- Dialogue box -------------------------------------------------
-- A button, so a tap anywhere on it advances (feel.md section 4); it grows
-- upwards to fit its Line, up to the Screen layout's tallest.
local dialogueFrame = Instance.new("TextButton")
dialogueFrame.Name = "DialogueFrame"
dialogueFrame.AnchorPoint = Vector2.new(0, 1)
dialogueFrame.AutomaticSize = Enum.AutomaticSize.Y
dialogueFrame.AutoButtonColor = false
dialogueFrame.Text = ""
dialogueFrame.BackgroundColor3 = Color3.fromRGB(24, 44, 30)
dialogueFrame.BackgroundTransparency = 0.12
dialogueFrame.BorderSizePixel = 0
dialogueFrame.Visible = false
dialogueFrame.Parent = screenGui
addCorner(dialogueFrame, 16)

local dialogueLimit = Instance.new("UISizeConstraint")
dialogueLimit.Parent = dialogueFrame

addPadding(dialogueFrame, ScreenLayout.BOX.top, ScreenLayout.BOX.bottom, ScreenLayout.PADDING)

local dialogueStroke = Instance.new("UIStroke")
dialogueStroke.Color = Color3.fromRGB(140, 200, 120)
dialogueStroke.Thickness = 2.5
dialogueStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
dialogueStroke.Parent = dialogueFrame

-- the name tag sits over the box's top edge
local speakerLabel = Instance.new("TextLabel")
speakerLabel.Name = "Speaker"
speakerLabel.AnchorPoint = Vector2.new(0, 1)
speakerLabel.Position = UDim2.new(0, -4, 0, -12)
speakerLabel.BackgroundColor3 = Color3.fromRGB(94, 160, 80)
speakerLabel.BorderSizePixel = 0
speakerLabel.Font = Enum.Font.FredokaOne
speakerLabel.TextColor3 = Color3.fromRGB(255, 255, 245)
speakerLabel.Text = ""
speakerLabel.AutomaticSize = Enum.AutomaticSize.X
speakerLabel.Parent = dialogueFrame
addCorner(speakerLabel, 10)

local speakerPadding = Instance.new("UIPadding")
speakerPadding.PaddingLeft = UDim.new(0, 14)
speakerPadding.PaddingRight = UDim.new(0, 14)
speakerPadding.Parent = speakerLabel

-- the text column: the Line, then the hint row under it
local dialogueLines = Instance.new("Frame")
dialogueLines.Name = "Lines"
dialogueLines.Size = UDim2.fromScale(1, 0)
dialogueLines.AutomaticSize = Enum.AutomaticSize.Y
dialogueLines.BackgroundTransparency = 1
dialogueLines.Parent = dialogueFrame
local dialogueList = Instance.new("UIListLayout")
dialogueList.SortOrder = Enum.SortOrder.LayoutOrder
dialogueList.Padding = UDim.new(0, ScreenLayout.BOX.between)
dialogueList.Parent = dialogueLines

local bodyLabel = Instance.new("TextLabel")
bodyLabel.Name = "Body"
bodyLabel.LayoutOrder = 1
bodyLabel.Size = UDim2.fromScale(1, 0)
bodyLabel.AutomaticSize = Enum.AutomaticSize.Y
bodyLabel.BackgroundTransparency = 1
bodyLabel.Font = Enum.Font.GothamMedium
bodyLabel.TextColor3 = Color3.fromRGB(240, 248, 235)
bodyLabel.TextWrapped = true
bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
bodyLabel.Text = ""
bodyLabel.Parent = dialogueLines

local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "Hint"
hintLabel.LayoutOrder = 2
hintLabel.BackgroundTransparency = 1
hintLabel.Font = Enum.Font.Gotham
hintLabel.TextColor3 = Color3.fromRGB(190, 215, 180)
hintLabel.TextXAlignment = Enum.TextXAlignment.Right
hintLabel.TextWrapped = true
hintLabel.Text = "click / E / Space to continue  ▶"
hintLabel.Parent = dialogueLines

-- Invisible full-screen button that advances dialogue on a click (a PC's
-- only: on touch a tap outside the box turns the view)
local clickCatcher = Instance.new("TextButton")
clickCatcher.Name = "ClickCatcher"
clickCatcher.Size = UDim2.new(1, 0, 1, 0)
clickCatcher.BackgroundTransparency = 1
clickCatcher.Text = ""
clickCatcher.Visible = false
clickCatcher.ZIndex = 5
clickCatcher.Parent = screenGui

-- Objective tracker --------------------------------------------
-- It grows down to fit its Objective; on a Phone it collapses to an icon
-- while a Dialogue shows.
local objectiveFrame = Instance.new("Frame")
objectiveFrame.Name = "ObjectiveFrame"
objectiveFrame.AutomaticSize = Enum.AutomaticSize.Y
objectiveFrame.BackgroundColor3 = Color3.fromRGB(24, 44, 30)
objectiveFrame.BackgroundTransparency = 0.25
objectiveFrame.BorderSizePixel = 0
objectiveFrame.Visible = false
objectiveFrame.Parent = screenGui
addCorner(objectiveFrame, 12)

local tracker = ScreenLayout.TRACKER
addPadding(objectiveFrame, tracker.top, tracker.bottom, tracker.side)
local objectiveList = Instance.new("UIListLayout")
objectiveList.SortOrder = Enum.SortOrder.LayoutOrder
objectiveList.Padding = UDim.new(0, tracker.between)
objectiveList.Parent = objectiveFrame

local objectiveHeader = Instance.new("TextLabel")
objectiveHeader.LayoutOrder = 1
objectiveHeader.Size = UDim2.fromScale(1, 0)
objectiveHeader.AutomaticSize = Enum.AutomaticSize.Y
objectiveHeader.BackgroundTransparency = 1
objectiveHeader.Font = Enum.Font.FredokaOne
objectiveHeader.TextColor3 = Color3.fromRGB(255, 214, 120)
objectiveHeader.TextXAlignment = Enum.TextXAlignment.Left
objectiveHeader.Text = ObjectiveText.HEADER
objectiveHeader.Parent = objectiveFrame

local objectiveText = Instance.new("TextLabel")
objectiveText.LayoutOrder = 2
objectiveText.Size = UDim2.fromScale(1, 0)
objectiveText.AutomaticSize = Enum.AutomaticSize.Y
objectiveText.BackgroundTransparency = 1
objectiveText.Font = Enum.Font.GothamMedium
objectiveText.TextColor3 = Color3.fromRGB(240, 248, 235)
objectiveText.TextWrapped = true
objectiveText.TextXAlignment = Enum.TextXAlignment.Left
objectiveText.TextYAlignment = Enum.TextYAlignment.Top
objectiveText.Text = ""
objectiveText.Parent = objectiveFrame

local objectiveIcon = Instance.new("TextLabel")
objectiveIcon.Name = "ObjectiveIcon"
objectiveIcon.BackgroundColor3 = Color3.fromRGB(24, 44, 30)
objectiveIcon.BackgroundTransparency = ObjectiveText.RESTING_TRANSPARENCY
objectiveIcon.BorderSizePixel = 0
objectiveIcon.Font = Enum.Font.FredokaOne
objectiveIcon.TextColor3 = Color3.fromRGB(255, 214, 120)
objectiveIcon.Text = "✦"
objectiveIcon.Visible = false
objectiveIcon.Parent = screenGui
addCorner(objectiveIcon, 12)

-- Title / chapter card -----------------------------------------
local titleOverlay = Instance.new("Frame")
titleOverlay.Name = "TitleOverlay"
titleOverlay.Size = UDim2.new(1, 0, 1, 0)
titleOverlay.BackgroundColor3 = Color3.fromRGB(8, 18, 10)
titleOverlay.BackgroundTransparency = 1
titleOverlay.BorderSizePixel = 0
titleOverlay.Visible = false
titleOverlay.ZIndex = 20
titleOverlay.Parent = screenGui

local titleLabel = Instance.new("TextLabel")
titleLabel.AnchorPoint = Vector2.new(0.5, 1)
titleLabel.AutomaticSize = Enum.AutomaticSize.Y
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.FredokaOne
titleLabel.TextWrapped = true
titleLabel.TextColor3 = Color3.fromRGB(255, 240, 200)
titleLabel.TextTransparency = 1
titleLabel.Text = ""
titleLabel.ZIndex = 21
titleLabel.Parent = titleOverlay

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.AnchorPoint = Vector2.new(0.5, 0)
subtitleLabel.AutomaticSize = Enum.AutomaticSize.Y
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Font = Enum.Font.Gotham
subtitleLabel.TextWrapped = true
subtitleLabel.TextColor3 = Color3.fromRGB(200, 225, 190)
subtitleLabel.TextTransparency = 1
subtitleLabel.Text = ""
subtitleLabel.ZIndex = 21
subtitleLabel.Parent = titleOverlay

-- Title screen (docs/design/feel.md, "Title screen") ----------
-- Over Clara's forest wall (ui:title_screen), or plain deep green until it
-- is uploaded. Every word is game-rendered text.
local titleScreen = Instance.new("ImageLabel")
titleScreen.Name = "TitleScreen"
titleScreen.Size = UDim2.new(1, 0, 1, 0)
titleScreen.BackgroundColor3 = rgb(palette.deep)
titleScreen.BorderSizePixel = 0
titleScreen.Image = AssetIds["ui:title_screen"] or ""
titleScreen.ScaleType = Enum.ScaleType.Crop
titleScreen.ZIndex = 30
titleScreen.Parent = screenGui

-- A line of title text, white, with a soft dark shadow behind it; `rich`
-- is the line with its RichText colours, when it has any.
local function titleText(
	name: string,
	y: number,
	height: number,
	font: Enum.Font,
	text: string,
	rich: string?
): TextLabel
	local shadow = Instance.new("TextLabel")
	shadow.Name = name .. "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.new(0.5, 3, y, 4)
	shadow.Size = UDim2.new(0.92, 0, height, 0)
	shadow.BackgroundTransparency = 1
	shadow.Font = font
	shadow.TextScaled = true
	shadow.TextColor3 = rgb(palette.deep)
	shadow.TextTransparency = 0.45
	shadow.Text = text
	shadow.ZIndex = 31
	shadow.Parent = titleScreen
	local label = shadow:Clone()
	label.Name = name
	label.Position = UDim2.new(0.5, 0, y, 0)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextTransparency = 0
	label.RichText = rich ~= nil
	label.Text = rich or text
	label.ZIndex = 32
	label.Parent = titleScreen
	return label
end

local words = TitleScreen.WORDS
local pill = Instance.new("TextLabel")
pill.Name = "Pill"
pill.AnchorPoint = Vector2.new(0.5, 0.5)
pill.Position = UDim2.new(0.5, 0, 0.16, 0)
pill.Size = UDim2.new(0.5, 0, 0.07, 0)
pill.BackgroundColor3 = rgb(palette.cream)
pill.BackgroundTransparency = 0.25
pill.Font = Enum.Font.Kalam
pill.TextScaled = true
pill.TextColor3 = rgb(palette.deep)
pill.Text = words.pill
pill.ZIndex = 32
pill.Parent = titleScreen
addCorner(pill, 999)
local pillPadding = Instance.new("UIPadding")
pillPadding.PaddingLeft = UDim.new(0.06, 0)
pillPadding.PaddingRight = UDim.new(0.06, 0)
pillPadding.PaddingTop = UDim.new(0.12, 0)
pillPadding.PaddingBottom = UDim.new(0.12, 0)
pillPadding.Parent = pill

titleText("Amy", 0.29, 0.15, Enum.Font.Fondamento, words.name)
local gold = palette.gold
titleText(
	"RainForest",
	0.43,
	0.13,
	Enum.Font.Fondamento,
	words.the .. words.gold,
	string.format('%s<font color="#%02x%02x%02x">%s</font>', words.the, gold.r, gold.g, gold.b, words.gold)
)

-- The choices sit at the bottom, above the safe area, and grow upwards:
-- the note (the Chapter, or the confirmation's question), then the buttons
-- in a row that wraps, so they fit a phone in landscape or portrait.
local function list(parent: Instance, direction: Enum.FillDirection, padding: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, padding)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

local titleChoices = Instance.new("Frame")
titleChoices.Name = "Choices"
titleChoices.AnchorPoint = Vector2.new(0.5, 1)
titleChoices.AutomaticSize = Enum.AutomaticSize.Y
titleChoices.BackgroundTransparency = 1
titleChoices.ZIndex = 32
titleChoices.Parent = titleScreen
list(titleChoices, Enum.FillDirection.Vertical, 10)

local titleNote = Instance.new("TextLabel")
titleNote.Name = "Note"
titleNote.LayoutOrder = 1
titleNote.Size = UDim2.new(1, 0, 0, 0)
titleNote.AutomaticSize = Enum.AutomaticSize.Y
titleNote.BackgroundTransparency = 1
titleNote.Font = Enum.Font.GothamMedium
titleNote.TextWrapped = true
titleNote.TextColor3 = Color3.new(1, 1, 1)
titleNote.TextStrokeColor3 = rgb(palette.deep)
titleNote.TextStrokeTransparency = 0.4
titleNote.Text = ""
titleNote.ZIndex = 33
titleNote.Parent = titleChoices

local titleButtons = Instance.new("Frame")
titleButtons.Name = "Buttons"
titleButtons.LayoutOrder = 2
titleButtons.Size = UDim2.new(1, 0, 0, 0)
titleButtons.AutomaticSize = Enum.AutomaticSize.Y
titleButtons.BackgroundTransparency = 1
titleButtons.ZIndex = 32
titleButtons.Parent = titleChoices
local titleButtonList = list(titleButtons, Enum.FillDirection.Horizontal, 0)
titleButtonList.Wraps = true

----------------------------------------------------------------
-- Dialogue
----------------------------------------------------------------
local dialogue = DialogueViewModel.new()
-- the Screen layout, set by applyLayout once the UI is built
local layout: ScreenLayout.Layout
local objectiveView = ObjectiveText.view(nil)

-- The Objective tracker, or its icon on a Phone while a Dialogue shows.
local function renderObjective()
	local collapsed = layout.objective.collapses and dialogue.lines ~= nil
	objectiveFrame.Visible = objectiveView.visible and not collapsed
	objectiveIcon.Visible = objectiveView.visible and collapsed
	objectiveText.Text = objectiveView.text
end

-- the Line the box shows, to set its text and colours only when it changes
local shownLines, shownIndex = nil, 0

local function renderDialogue()
	local view = DialogueViewModel.view(dialogue)
	if dialogueFrame.Visible ~= view.open then
		dialogueFrame.Visible = view.open
		renderObjective()
	end
	clickCatcher.Visible = view.open and not layout.touch
	if dialogue.lines ~= shownLines or dialogue.index ~= shownIndex then
		shownLines, shownIndex = dialogue.lines, dialogue.index
		speakerLabel.Text = view.speaker
		speakerLabel.Visible = view.speaker ~= ""
		speakerLabel.BackgroundColor3 = rgb(view.style.tag)
		bodyLabel.TextColor3 = rgb(view.style.text)
		bodyLabel.Text = view.text
	end
	bodyLabel.MaxVisibleGraphemes = view.visibleGraphemes
end

local function advance()
	if DialogueViewModel.advance(dialogue) then
		Camera.dialogueFinished()
		DialogueFinished:FireServer()
	end
	renderDialogue()
end

clickCatcher.Activated:Connect(advance)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if
		input.KeyCode == Enum.KeyCode.E
		or input.KeyCode == Enum.KeyCode.Space
		or input.KeyCode == Enum.KeyCode.Return
	then
		advance()
	end
end)

ShowDialogue.OnClientEvent:Connect(Net.guard("ShowDialogue", function(lines: { Events.ShownLine })
	DialogueViewModel.enqueue(dialogue, lines)
	renderDialogue()
end, warn))

----------------------------------------------------------------
-- Objective tracker
----------------------------------------------------------------
SetObjective.OnClientEvent:Connect(Net.guard("SetObjective", function(text: string?)
	-- The server never moves on while a Dialogue shows, but for a Resume (a
	-- Dev shortcut's jump): the camera leaves that Dialogue's Shot.
	if DialogueViewModel.view(dialogue).open then
		Camera.resumed()
	end
	local view = ObjectiveText.view(text)
	objectiveView = view
	renderObjective()
	if view.visible then
		objectiveFrame.BackgroundTransparency = 0
		TweenService:Create(objectiveFrame, TweenInfo.new(ObjectiveText.POP_SECONDS), {
			BackgroundTransparency = ObjectiveText.RESTING_TRANSPARENCY,
		}):Play()
	end
end, warn))

----------------------------------------------------------------
-- Chapter cards and the end card
----------------------------------------------------------------
local card: ChapterCardTimeline.Card? = nil
local cardStarted = 0

local function renderCard()
	local frame = ChapterCardTimeline.at(card :: ChapterCardTimeline.Card, os.clock() - cardStarted)
	titleOverlay.Visible = frame ~= nil
	if not frame then
		card = nil
		return
	end
	titleOverlay.BackgroundTransparency = frame.overlayTransparency
	titleLabel.TextTransparency = frame.textTransparency
	subtitleLabel.TextTransparency = frame.textTransparency
end

local function showCard(ending: boolean): (title: string, subtitle: string) -> ()
	return function(title, subtitle)
		titleLabel.Text = title
		subtitleLabel.Text = subtitle
		card, cardStarted = ChapterCardTimeline.new(ending), os.clock()
		renderCard()
	end
end

ShowChapter.OnClientEvent:Connect(Net.guard("ShowChapter", showCard(false), warn))
ShowEnding.OnClientEvent:Connect(Net.guard("ShowEnding", showCard(true), warn))

----------------------------------------------------------------
-- The Shots the camera frames
----------------------------------------------------------------
FrameShot.OnClientEvent:Connect(Net.guard("FrameShot", Camera.frameShot, warn))

----------------------------------------------------------------
-- The Title screen
----------------------------------------------------------------
local title = TitleScreen.new()

local function renderTitle()
	local view = TitleScreen.view(title)
	titleScreen.Visible = view.visible
	titleNote.Text = view.note or ""
	titleNote.Visible = view.note ~= nil
	for _, child in titleButtons:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for order, button in view.buttons do
		local choice = Instance.new("TextButton")
		choice.Name = button.id
		choice.LayoutOrder = order
		local size = layout.title.button
		choice.Size = UDim2.fromOffset(size.width, size.height) -- feel.md: at least 48 x 48
		choice.AutomaticSize = Enum.AutomaticSize.Y
		choice.TextWrapped = true
		choice.BackgroundColor3 = rgb(if button.primary then palette.gold else palette.cream)
		choice.Font = Enum.Font.FredokaOne
		choice.TextSize = size.text
		choice.TextColor3 = rgb(palette.deep)
		choice.Text = button.label
		choice.ZIndex = 33
		choice.Parent = titleButtons
		addCorner(choice, 16)
		addPadding(choice, 0, 0, ScreenLayout.BUTTON_PADDING)
		choice.Activated:Connect(function()
			local made = TitleScreen.press(title, button.id)
			if made then
				Camera.resumed()
				TitleChoice:FireServer(made)
			end
			renderTitle()
		end)
	end
end

-- The Story has begun, with its first Chapter card or, for a Resume, the
-- Objective: the Title screen goes.
local begun: { RBXScriptConnection } = {}
local function storyBegins()
	TitleScreen.close(title)
	renderTitle()
	for _, connection in begun do
		connection:Disconnect()
	end
end
begun = { ShowChapter.OnClientEvent:Connect(storyBegins), SetObjective.OnClientEvent:Connect(storyBegins) }

ShowTitle.OnClientEvent:Connect(Net.guard("ShowTitle", function(chapter: string, canContinue: boolean)
	TitleScreen.show(title, { chapter = chapter, canContinue = canContinue })
	renderTitle()
end, warn))

----------------------------------------------------------------
-- The Screen layout: for the Device class, the viewport and the safe area
----------------------------------------------------------------
local TEXT_SCALE = 1 -- brief 015 adds the setting, from 1 to 1.5

local preferred = nil
pcall(function() -- PreferredInput is newer than some clients
	preferred = UserInputService.PreferredInput.Name
end)
local inputKind: DeviceClass.InputKind =
	DeviceClass.starting(preferred, UserInputService.TouchEnabled, UserInputService.KeyboardEnabled)

local function absolute(gui: GuiObject): ScreenLayout.Rect
	local at, size = gui.AbsolutePosition, gui.AbsoluteSize
	return { x = at.X, y = at.Y, width = size.X, height = size.Y }
end

local function applyLayout()
	local screen = absolute(root)
	layout = ScreenLayout.new({
		class = DeviceClass.pick(inputKind, screen.width, screen.height),
		width = screen.width,
		height = screen.height,
		insets = ScreenLayout.insets(screen, absolute(safeArea)),
		textScale = TEXT_SCALE,
	})
	local text = layout.text
	Camera.setZones(layout.zones)

	local box = layout.dialogue
	dialogueFrame.Position = UDim2.fromOffset(box.x, box.bottom)
	dialogueFrame.Size = UDim2.fromOffset(box.width, 0)
	dialogueLimit.MaxSize = Vector2.new(box.width, box.maxHeight)
	speakerLabel.TextSize = text.speaker
	speakerLabel.Size = UDim2.fromOffset(0, box.speaker)
	bodyLabel.TextSize = text.body
	hintLabel.TextSize = text.hint
	hintLabel.Size = UDim2.new(1, 0, 0, box.hintRow)

	local objective = layout.objective
	objectiveFrame.Position = UDim2.fromOffset(objective.x, objective.y)
	objectiveFrame.Size = UDim2.fromOffset(objective.width, 0)
	objectiveHeader.TextSize = text.objective
	objectiveText.TextSize = text.objective
	objectiveIcon.Position = UDim2.fromOffset(objective.icon.x, objective.icon.y)
	objectiveIcon.Size = UDim2.fromOffset(objective.icon.width, objective.icon.height)
	objectiveIcon.TextSize = text.objective

	local cardLayout = layout.card
	local cardMiddle = cardLayout.x + cardLayout.width / 2
	titleLabel.TextSize = cardLayout.title
	titleLabel.Position = UDim2.fromOffset(cardMiddle, cardLayout.centre)
	titleLabel.Size = UDim2.fromOffset(cardLayout.width, 0)
	subtitleLabel.TextSize = cardLayout.subtitle
	subtitleLabel.Position = UDim2.fromOffset(cardMiddle, cardLayout.centre + cardLayout.gap)
	subtitleLabel.Size = UDim2.fromOffset(cardLayout.width, 0)

	local choices = layout.title
	titleChoices.Position = UDim2.fromOffset(choices.x + choices.width / 2, choices.bottom)
	titleChoices.Size = UDim2.fromOffset(choices.width, 0)
	titleNote.TextSize = choices.note
	titleButtonList.Padding = UDim.new(0, choices.gap)

	renderObjective()
	renderDialogue()
	if titleScreen.Visible then
		renderTitle() -- its buttons are built at the layout's size
	end
end

UserInputService.LastInputTypeChanged:Connect(function(input: Enum.UserInputType)
	local kind = DeviceClass.inputKind(input.Name)
	if kind and kind ~= inputKind then
		inputKind = kind :: DeviceClass.InputKind
		applyLayout()
	end
end)
-- A rotation changes the screen and the safe area at once: lay out once,
-- after them all.
local relayout = false
for _, changed in
	{
		root:GetPropertyChangedSignal("AbsoluteSize"),
		safeArea:GetPropertyChangedSignal("AbsoluteSize"),
		safeArea:GetPropertyChangedSignal("AbsolutePosition"),
	}
do
	changed:Connect(function()
		if not relayout then
			relayout = true
			task.defer(function()
				relayout = false
				applyLayout()
			end)
		end
	end)
end
applyLayout()

----------------------------------------------------------------
-- Every frame: time passes for the Dialogue and the card
----------------------------------------------------------------
RunService.RenderStepped:Connect(function(seconds)
	if dialogue.lines then
		DialogueViewModel.tick(dialogue, seconds)
		renderDialogue()
	end
	if card then
		renderCard()
	end
end)

----------------------------------------------------------------
-- Tell the server we're ready for the story to begin
----------------------------------------------------------------
task.wait(1) -- give the world a moment to stream in
ClientReady:FireServer()
