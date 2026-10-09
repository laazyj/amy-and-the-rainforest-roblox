--!strict
--[[
	StoryClient: the client binder. It renders the core view-model and
	forwards input; the logic is in the core, tested in tier 1:

	  ShowDialogue    -> DialogueViewModel: the dialogue box, typed out
	  SetObjective    -> ObjectiveText: the Objective tracker (top right)
	  ShowChapter /   -> ChapterCardTimeline: the Chapter card and the end card
	  ShowEnding

	Every remote it receives is held to the Net contract first (Net.guard);
	a malformed payload is dropped with a warning.

	Click, tap, or press E, Space or Enter to advance a Dialogue; when the
	view-model says it is finished, DialogueFinished goes to the server.
	What is left here is building the UI, turning plain colours into
	Color3, and connecting remotes, input and the frame loop.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Core = ReplicatedStorage:WaitForChild("core")
local ChapterCardTimeline = require(Core:WaitForChild("ChapterCardTimeline"))
local DialogueViewModel = require(Core:WaitForChild("DialogueViewModel"))
local Events = require(Core:WaitForChild("Events"))
local ObjectiveText = require(Core:WaitForChild("ObjectiveText"))
local Story = require(Core:WaitForChild("Story"))
local Net = require(Core:WaitForChild("Net"))
local Remotes = require(ReplicatedStorage:WaitForChild("shared"):WaitForChild("Net"))

local remotes = Remotes.waitForRemotes()
local ShowDialogue = remotes.ShowDialogue
local DialogueFinished = remotes.DialogueFinished
local SetObjective = remotes.SetObjective
local ShowChapter = remotes.ShowChapter
local ShowEnding = remotes.ShowEnding
local ClientReady = remotes.ClientReady

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
