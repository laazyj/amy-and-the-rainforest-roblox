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
local DialogueViewModel = require(Core:WaitForChild("DialogueViewModel"))
local Events = require(Core:WaitForChild("Events"))
local ObjectiveText = require(Core:WaitForChild("ObjectiveText"))
local Story = require(Core:WaitForChild("Story"))
local Net = require(Core:WaitForChild("Net"))
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

local function addCorner(guiObject: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = guiObject
end

-- Dialogue box -------------------------------------------------
local dialogueFrame = Instance.new("Frame")
dialogueFrame.Name = "DialogueFrame"
dialogueFrame.AnchorPoint = Vector2.new(0.5, 1)
dialogueFrame.Position = UDim2.new(0.5, 0, 1, -28)
dialogueFrame.Size = UDim2.new(0.62, 0, 0, 150)
dialogueFrame.BackgroundColor3 = Color3.fromRGB(24, 44, 30)
dialogueFrame.BackgroundTransparency = 0.12
dialogueFrame.BorderSizePixel = 0
dialogueFrame.Visible = false
dialogueFrame.Parent = screenGui
addCorner(dialogueFrame, 16)

local dialogueStroke = Instance.new("UIStroke")
dialogueStroke.Color = Color3.fromRGB(140, 200, 120)
dialogueStroke.Thickness = 2.5
dialogueStroke.Parent = dialogueFrame

local speakerLabel = Instance.new("TextLabel")
speakerLabel.Name = "Speaker"
speakerLabel.AnchorPoint = Vector2.new(0, 1)
speakerLabel.Position = UDim2.new(0, 20, 0, 6)
speakerLabel.Size = UDim2.new(0, 300, 0, 34)
speakerLabel.BackgroundColor3 = Color3.fromRGB(94, 160, 80)
speakerLabel.BorderSizePixel = 0
speakerLabel.Font = Enum.Font.FredokaOne
speakerLabel.TextSize = 22
speakerLabel.TextColor3 = Color3.fromRGB(255, 255, 245)
speakerLabel.Text = ""
speakerLabel.AutomaticSize = Enum.AutomaticSize.X
speakerLabel.Size = UDim2.new(0, 0, 0, 34)
speakerLabel.Parent = dialogueFrame
addCorner(speakerLabel, 10)

local speakerPadding = Instance.new("UIPadding")
speakerPadding.PaddingLeft = UDim.new(0, 14)
speakerPadding.PaddingRight = UDim.new(0, 14)
speakerPadding.Parent = speakerLabel

local bodyLabel = Instance.new("TextLabel")
bodyLabel.Name = "Body"
bodyLabel.Position = UDim2.new(0, 24, 0, 18)
bodyLabel.Size = UDim2.new(1, -48, 1, -52)
bodyLabel.BackgroundTransparency = 1
bodyLabel.Font = Enum.Font.GothamMedium
bodyLabel.TextSize = 21
bodyLabel.TextColor3 = Color3.fromRGB(240, 248, 235)
bodyLabel.TextWrapped = true
bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
bodyLabel.Text = ""
bodyLabel.Parent = dialogueFrame

local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "Hint"
hintLabel.AnchorPoint = Vector2.new(1, 1)
hintLabel.Position = UDim2.new(1, -18, 1, -8)
hintLabel.Size = UDim2.new(0, 260, 0, 20)
hintLabel.BackgroundTransparency = 1
hintLabel.Font = Enum.Font.Gotham
hintLabel.TextSize = 14
hintLabel.TextColor3 = Color3.fromRGB(190, 215, 180)
hintLabel.TextXAlignment = Enum.TextXAlignment.Right
hintLabel.Text = "click / E / Space to continue  ▶"
hintLabel.Parent = dialogueFrame

-- Invisible full-screen button that advances dialogue on click/tap
local clickCatcher = Instance.new("TextButton")
clickCatcher.Name = "ClickCatcher"
clickCatcher.Size = UDim2.new(1, 0, 1, 0)
clickCatcher.BackgroundTransparency = 1
clickCatcher.Text = ""
clickCatcher.Visible = false
clickCatcher.ZIndex = 5
clickCatcher.Parent = screenGui

-- Objective tracker --------------------------------------------
local objectiveFrame = Instance.new("Frame")
objectiveFrame.Name = "ObjectiveFrame"
objectiveFrame.AnchorPoint = Vector2.new(1, 0)
objectiveFrame.Position = UDim2.new(1, -18, 0, 18)
objectiveFrame.Size = UDim2.new(0, 320, 0, 74)
objectiveFrame.BackgroundColor3 = Color3.fromRGB(24, 44, 30)
objectiveFrame.BackgroundTransparency = 0.25
objectiveFrame.BorderSizePixel = 0
objectiveFrame.Visible = false
objectiveFrame.Parent = screenGui
addCorner(objectiveFrame, 12)

local objectiveHeader = Instance.new("TextLabel")
objectiveHeader.Position = UDim2.new(0, 14, 0, 8)
objectiveHeader.Size = UDim2.new(1, -28, 0, 20)
objectiveHeader.BackgroundTransparency = 1
objectiveHeader.Font = Enum.Font.FredokaOne
objectiveHeader.TextSize = 16
objectiveHeader.TextColor3 = Color3.fromRGB(255, 214, 120)
objectiveHeader.TextXAlignment = Enum.TextXAlignment.Left
objectiveHeader.Text = ObjectiveText.HEADER
objectiveHeader.Parent = objectiveFrame

local objectiveText = Instance.new("TextLabel")
objectiveText.Position = UDim2.new(0, 14, 0, 30)
objectiveText.Size = UDim2.new(1, -28, 1, -38)
objectiveText.BackgroundTransparency = 1
objectiveText.Font = Enum.Font.GothamMedium
objectiveText.TextSize = 16
objectiveText.TextColor3 = Color3.fromRGB(240, 248, 235)
objectiveText.TextWrapped = true
objectiveText.TextXAlignment = Enum.TextXAlignment.Left
objectiveText.TextYAlignment = Enum.TextYAlignment.Top
objectiveText.Text = ""
objectiveText.Parent = objectiveFrame

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
titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
titleLabel.Position = UDim2.new(0.5, 0, 0.44, 0)
titleLabel.Size = UDim2.new(0.8, 0, 0, 70)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.FredokaOne
titleLabel.TextSize = 52
titleLabel.TextColor3 = Color3.fromRGB(255, 240, 200)
titleLabel.TextTransparency = 1
titleLabel.Text = ""
titleLabel.ZIndex = 21
titleLabel.Parent = titleOverlay

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
subtitleLabel.Position = UDim2.new(0.5, 0, 0.54, 0)
subtitleLabel.Size = UDim2.new(0.8, 0, 0, 40)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Font = Enum.Font.Gotham
subtitleLabel.TextSize = 26
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
titleChoices.Position = UDim2.new(0.5, 0, 1, -24)
titleChoices.Size = UDim2.new(0.94, 0, 0, 0)
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
titleNote.TextSize = 22
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
list(titleButtons, Enum.FillDirection.Horizontal, 10).Wraps = true -- feel.md: at least 8 between touch targets

----------------------------------------------------------------
-- Dialogue
----------------------------------------------------------------
local dialogue = DialogueViewModel.new()

local function renderDialogue()
	local view = DialogueViewModel.view(dialogue)
	dialogueFrame.Visible = view.open
	clickCatcher.Visible = view.open
	speakerLabel.Text = view.speaker
	speakerLabel.Visible = view.speaker ~= ""
	speakerLabel.BackgroundColor3 = rgb(view.style.tag)
	bodyLabel.TextColor3 = rgb(view.style.text)
	bodyLabel.Text = view.text
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
	objectiveFrame.Visible = view.visible
	objectiveText.Text = view.text
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
		choice.Size = UDim2.new(0, 240, 0, 52) -- feel.md: at least 48 x 48
		choice.BackgroundColor3 = rgb(if button.primary then palette.gold else palette.cream)
		choice.Font = Enum.Font.FredokaOne
		choice.TextSize = 24
		choice.TextColor3 = rgb(palette.deep)
		choice.Text = button.label
		choice.ZIndex = 33
		choice.Parent = titleButtons
		addCorner(choice, 16)
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
renderTitle()

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
