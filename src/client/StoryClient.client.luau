--!strict
--[[
	StoryClient: the client binder. It renders the core view-model and
	forwards input; the logic is in the core, tested in tier 1:

	  ShowDialogue    -> DialogueViewModel: the dialogue box, typed out
	  SetObjective    -> ObjectiveText: the Objective tracker (top right)
	  ShowChapter /   -> ChapterCardTimeline: the Chapter card and the end card
	  ShowEnding
	  ShowTitle       -> TitleScreen: the Title screen's choices
	  the first minute -> Onboarding: the Hints that teach walk, talk and
	                     advance, in src/content/hints
	  FrameShot       -> Camera (src/client/Camera, over CameraModel): the
	                     Shot, framed from behind Amy
	  ApplySettings   -> Settings: the player's Settings, applied to the
	                     volume, the dialogue box, the fonts and the layout
	  the pause button -> PauseScreen: the Pause screen and its Settings
	  (or P)             page; each change goes to the server as
	                     ChangeSettings. While it is open the Story does not
	                     advance: no input reaches it, a Dialogue stops
	                     typing, a Chapter card holds, Amy cannot walk or
	                     talk

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
local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

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
local Onboarding = require(Core:WaitForChild("Onboarding"))
local PauseScreen = require(Core:WaitForChild("PauseScreen"))
local ScreenLayout = require(Core:WaitForChild("ScreenLayout"))
local Settings = require(Core:WaitForChild("Settings"))
local TalkAndAdvance = require(Core:WaitForChild("TalkAndAdvance"))
local TitleScreen = require(Core:WaitForChild("TitleScreen"))
local ContentFolder = ReplicatedStorage:WaitForChild("content")
local palette = require(ContentFolder:WaitForChild("palette")).colours
local hints = require(ContentFolder:WaitForChild("hints"))
local Content = require(ContentFolder:WaitForChild("Story"))
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
local ApplySettings = remotes.ApplySettings
local ChangeSettings = remotes.ChangeSettings

-- Every sound plays through this SoundGroup (default.project.json), whose
-- volume is the volume Setting; brief 013's Cues set their SoundGroup to it.
local masterVolume = SoundService:WaitForChild("Master") :: SoundGroup

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
-- upwards to fit its Line, up to the Screen layout's tallest, and clips its
-- text, so a Line that ever spills can never cover a button.
local dialogueFrame = Instance.new("TextButton")
dialogueFrame.Name = "DialogueFrame"
dialogueFrame.AnchorPoint = Vector2.new(0, 1)
dialogueFrame.AutoButtonColor = false
dialogueFrame.Text = ""
dialogueFrame.BorderSizePixel = 0 -- its colours are the Settings' (renderBox)
dialogueFrame.Visible = false
dialogueFrame.Parent = screenGui
addCorner(dialogueFrame, 16)

addPadding(dialogueFrame, ScreenLayout.BOX.top, ScreenLayout.BOX.bottom, ScreenLayout.PADDING)

local dialogueStroke = Instance.new("UIStroke")
dialogueStroke.Thickness = 2.5
dialogueStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
dialogueStroke.Parent = dialogueFrame

-- the name tag sits over the box's top edge
local speakerLabel = Instance.new("TextLabel")
speakerLabel.Name = "Speaker"
speakerLabel.AnchorPoint = Vector2.new(0, 1)
speakerLabel.Position = UDim2.new(0, -4, 0, ScreenLayout.BOX.tag - ScreenLayout.BOX.top) -- inside the padding
speakerLabel.BorderSizePixel = 0
speakerLabel.Font = Enum.Font.FredokaOne
speakerLabel.TextColor3 = rgb(DialogueViewModel.NAME_TEXT)
speakerLabel.Text = ""
speakerLabel.AutomaticSize = Enum.AutomaticSize.X
speakerLabel.Parent = dialogueFrame
addCorner(speakerLabel, 10)

local speakerPadding = Instance.new("UIPadding")
speakerPadding.PaddingLeft = UDim.new(0, 14)
speakerPadding.PaddingRight = UDim.new(0, 14)
speakerPadding.Parent = speakerLabel

-- the text column, clipped (the name tag above it is not): the Line, then
-- the hint row under it
local dialogueText = Instance.new("Frame")
dialogueText.Name = "Text"
dialogueText.Size = UDim2.fromScale(1, 1)
dialogueText.BackgroundTransparency = 1
dialogueText.ClipsDescendants = true
dialogueText.Parent = dialogueFrame
local dialogueLines = Instance.new("Frame")
dialogueLines.Name = "Lines"
dialogueLines.Size = UDim2.fromScale(1, 0)
dialogueLines.AutomaticSize = Enum.AutomaticSize.Y
dialogueLines.BackgroundTransparency = 1
dialogueLines.Parent = dialogueText
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
hintLabel.TextXAlignment = Enum.TextXAlignment.Right
hintLabel.TextWrapped = true
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
-- a button: a tap or a click skips a Chapter card
local titleOverlay = Instance.new("TextButton")
titleOverlay.Name = "TitleOverlay"
titleOverlay.AutoButtonColor = false
titleOverlay.Text = ""
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

-- The Onboarding (docs/design/feel.md section 6) --------------
-- A Hint in free play; the advance step's shows large in the dialogue box.
local onboardingHint = Instance.new("TextLabel")
onboardingHint.Name = "OnboardingHint"
onboardingHint.BackgroundColor3 = Color3.fromRGB(24, 44, 30)
onboardingHint.BackgroundTransparency = 0.12
onboardingHint.BorderSizePixel = 0
onboardingHint.Font = Enum.Font.GothamMedium
onboardingHint.TextColor3 = Color3.fromRGB(240, 248, 235)
onboardingHint.TextWrapped = true
onboardingHint.Visible = false
onboardingHint.Parent = screenGui
addCorner(onboardingHint, 12)

local skipButton = Instance.new("TextButton")
skipButton.Name = "Skip"
skipButton.BackgroundColor3 = rgb(palette.cream)
skipButton.Font = Enum.Font.FredokaOne
skipButton.TextColor3 = rgb(palette.deep)
skipButton.Text = hints.skip
skipButton.Visible = false
skipButton.ZIndex = 6 -- over the PC's click catcher
skipButton.Parent = screenGui
addCorner(skipButton, 12)

-- A glowing ring: on the thumbstick for the walk step, pulsing round the
-- Talk-and-advance button for the talk step. Neither takes input.
local function ring(name: string): (Frame, UIStroke)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = screenGui
	addCorner(frame, 999)
	local stroke = Instance.new("UIStroke")
	stroke.Color = rgb(palette.gold)
	stroke.Thickness = 4
	stroke.Transparency = 0.3
	stroke.Parent = frame
	return frame, stroke
end
local thumbRing = ring("ThumbstickRing")
local talkRing, talkStroke = ring("TalkRing")

-- The Objective tracker's glow, when the first Objective appears.
local objectiveGlow = Instance.new("UIStroke")
objectiveGlow.Color = rgb(palette.gold)
objectiveGlow.Thickness = 3
objectiveGlow.Transparency = 1
objectiveGlow.Parent = objectiveFrame

-- The marker over the first Quest's Character (Dad), until Amy talks to him.
local markerGui = Instance.new("BillboardGui")
markerGui.Name = "OnboardingMarker"
markerGui.Size = UDim2.fromOffset(40, 40)
markerGui.StudsOffset = Vector3.new(0, 2.5, 0)
markerGui.AlwaysOnTop = true
markerGui.Enabled = false
markerGui.Parent = playerGui
local markerLabel = Instance.new("TextLabel")
markerLabel.Size = UDim2.fromScale(1, 1)
markerLabel.BackgroundTransparency = 1
markerLabel.Font = Enum.Font.FredokaOne
markerLabel.TextScaled = true
markerLabel.TextColor3 = rgb(palette.gold)
markerLabel.TextStrokeColor3 = rgb(palette.deep)
markerLabel.TextStrokeTransparency = 0.3
markerLabel.Text = "▼"
markerLabel.Parent = markerGui

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

-- The title's words, laid out over the safe area.
local titleWords = Instance.new("Frame")
titleWords.Name = "Words"
titleWords.BackgroundTransparency = 1
titleWords.Parent = titleScreen

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
	shadow.Parent = titleWords
	local label = shadow:Clone()
	label.Name = name
	label.Position = UDim2.new(0.5, 0, y, 0)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextTransparency = 0
	label.RichText = rich ~= nil
	label.Text = rich or text
	label.ZIndex = 32
	label.Parent = titleWords
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
pill.Parent = titleWords
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

-- The Pause screen ------------------------------------------------
-- Its button at the top left; the panel over a dimmed screen, which takes
-- every click and tap while it is open. Its rows are built by renderPause.
local pauseColours = PauseScreen.COLOURS
local pauseButton = Instance.new("TextButton")
pauseButton.Name = "Pause"
pauseButton.BackgroundColor3 = rgb(pauseColours.button)
pauseButton.Font = Enum.Font.FredokaOne
pauseButton.TextColor3 = rgb(pauseColours.label)
pauseButton.Text = PauseScreen.GLYPH
pauseButton.ZIndex = 6 -- over the PC's click catcher
pauseButton.Parent = screenGui
addCorner(pauseButton, 12)

local pauseOverlay = Instance.new("TextButton")
pauseOverlay.Name = "PauseScreen"
pauseOverlay.AutoButtonColor = false
pauseOverlay.Text = ""
pauseOverlay.Size = UDim2.fromScale(1, 1)
pauseOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
pauseOverlay.BackgroundTransparency = 0.45
pauseOverlay.Modal = true -- the pointer stays free
pauseOverlay.Visible = false
pauseOverlay.ZIndex = 40
pauseOverlay.Parent = screenGui

local pausePanel = Instance.new("Frame")
pausePanel.Name = "Panel"
pausePanel.AnchorPoint = Vector2.new(0, 0.5)
pausePanel.AutomaticSize = Enum.AutomaticSize.Y
pausePanel.BackgroundColor3 = rgb(pauseColours.panel)
pausePanel.BorderSizePixel = 0
pausePanel.ZIndex = 41
pausePanel.Parent = pauseOverlay
addCorner(pausePanel, 16)
addPadding(pausePanel, ScreenLayout.TARGET_GAP, ScreenLayout.TARGET_GAP, ScreenLayout.TARGET_GAP)
local pauseList = list(pausePanel, Enum.FillDirection.Vertical, ScreenLayout.TARGET_GAP)
pauseList.HorizontalAlignment = Enum.HorizontalAlignment.Left

----------------------------------------------------------------
-- Dialogue
----------------------------------------------------------------
local dialogue = DialogueViewModel.new()
-- the Screen layout, set by applyLayout once the UI is built
local layout: ScreenLayout.Layout
local objectiveView = ObjectiveText.view(nil)
-- the touch controls, shown for the Dialogue (Touch controls, below)
local renderTouch: () -> ()
-- the Pause screen (The Pause screen and the Settings, below)
local renderPause: () -> ()
-- the Chapter card showing, and when it started
local card: ChapterCardTimeline.Card? = nil
local cardStarted = 0
local onboarding = Onboarding.new(Content.story)
-- the player's Settings (the defaults until ApplySettings says otherwise),
-- the Pause screen, and the device's largest Text scale (set by applyLayout)
local settings: Settings.Settings = table.clone(Settings.DEFAULTS)
local pause = PauseScreen.new()
local textCap: number? = nil

-- The Objective tracker, or its icon on a Phone while a Dialogue shows.
local function renderObjective()
	local collapsed = layout.objective.collapses and dialogue.lines ~= nil
	objectiveFrame.Visible = objectiveView.visible and not collapsed
	objectiveIcon.Visible = objectiveView.visible and collapsed
	objectiveText.Text = objectiveView.text
end

-- The box as tall as its Line and hint row, up to the layout's tallest.
local function fitDialogue()
	local height = dialogueLines.AbsoluteSize.Y + ScreenLayout.BOX.top + ScreenLayout.BOX.bottom
	dialogueFrame.Size = UDim2.fromOffset(layout.dialogue.width, math.min(height, layout.dialogue.maxHeight))
end
dialogueLines:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if layout then
		fitDialogue()
	end
end)

-- the Line the box shows, to set its text and colours only when it changes
local shownLines, shownIndex, shownContrast = nil, 0, false

local function renderDialogue()
	local view = DialogueViewModel.view(dialogue, settings.highContrast)
	if dialogueFrame.Visible ~= view.open then
		dialogueFrame.Visible = view.open
		renderObjective()
		renderTouch()
	end
	clickCatcher.Visible = view.open and not layout.touch
	if dialogue.lines ~= shownLines or dialogue.index ~= shownIndex or settings.highContrast ~= shownContrast then
		shownLines, shownIndex, shownContrast = dialogue.lines, dialogue.index, settings.highContrast
		speakerLabel.Text = view.speaker
		speakerLabel.Visible = view.speaker ~= ""
		speakerLabel.BackgroundColor3 = rgb(view.style.tag)
		bodyLabel.TextColor3 = rgb(view.style.text)
		bodyLabel.Text = view.text
	end
	bodyLabel.MaxVisibleGraphemes = view.visibleGraphemes
end

local function advance()
	if PauseScreen.paused(pause) then
		return -- the Story does not advance while the Pause screen is open
	end
	-- the first press skips a Chapter card, not the Line under it
	if card and ChapterCardTimeline.skip(card, os.clock() - cardStarted) then
		return
	end
	if DialogueViewModel.advance(dialogue) then
		Camera.dialogueFinished()
		DialogueFinished:FireServer()
		Onboarding.dialogueFinished(onboarding)
	end
	renderDialogue()
end

clickCatcher.Activated:Connect(advance)
dialogueFrame.Activated:Connect(advance)
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
	Onboarding.dialogueShown(onboarding)
	renderDialogue()
end, warn))

----------------------------------------------------------------
-- Touch controls (feel.md sections 1 and 4)
----------------------------------------------------------------
-- The Talk-and-advance button, a ContextActionService touch button in the
-- right zone: it advances a Dialogue, or else uses the nearest prompt
-- shown, which stays the universal talk affordance. Roblox's thumbstick
-- has the left zone; while a Dialogue shows the player's controls are
-- disabled (Amy listens; the box may cover the zone). The jump button
-- goes: the Story never asks for a jump, and the right zone is the talk
-- button's.
local TALK_ACTION = "TalkAndAdvance"
local TALK_LABELS: TalkAndAdvance.Labels = hints.button
local talkBound = false
local prompts: { [ProximityPrompt]: true } = {}

-- Each prompt shown, by its distance from Amy.
local function promptDistances(): { [ProximityPrompt]: number }
	local character = player.Character
	local amy = character and character:FindFirstChild("HumanoidRootPart")
	local distances = {}
	if not (amy and amy:IsA("BasePart")) then
		return distances
	end
	for prompt in prompts do
		local parent = prompt.Parent
		local at = if parent and parent:IsA("BasePart")
			then parent.Position
			elseif parent and parent:IsA("Attachment") then parent.WorldPosition
			else nil
		if at then
			distances[prompt] = (at - amy.Position).Magnitude
		end
	end
	return distances
end

local function talkOrAdvance(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin and not PauseScreen.paused(pause) then
		local action = TalkAndAdvance.press(dialogue.lines ~= nil, promptDistances())
		if action == "advance" then
			advance()
		elseif action then
			local prompt = action :: ProximityPrompt
			prompt:InputHoldBegin()
			prompt:InputHoldEnd()
		end
	end
	return Enum.ContextActionResult.Sink
end

-- Puts `gui` at `rect`, in the layout's units, whatever its parent.
local function place(gui: GuiObject, rect: ScreenLayout.Rect)
	local parent = gui.Parent
	local origin = if parent and parent:IsA("GuiObject")
		then parent.AbsolutePosition - root.AbsolutePosition
		else Vector2.zero
	gui.AnchorPoint = Vector2.zero
	gui.Position = UDim2.fromOffset(rect.x - origin.X, rect.y - origin.Y)
	gui.Size = UDim2.fromOffset(rect.width, rect.height)
end

-- Roblox's touch controls (PlayerGui.TouchGui), once the player module
-- has built them: the thumbstick (dynamic or classic) and the jump button.
local CONTROLS: { [string]: string } =
	{ DynamicThumbstickFrame = "thumbstick", ThumbstickFrame = "thumbstick", JumpButton = "jump" }
local hiddenJumps: { [GuiObject]: true } = setmetatable({}, { __mode = "k" }) :: any

local function eachControl(each: (control: GuiObject, kind: string) -> ())
	local touchGui = playerGui:FindFirstChild("TouchGui")
	local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	for _, child in if frame then frame:GetChildren() else {} do
		local kind = CONTROLS[child.Name]
		if kind and child:IsA("GuiObject") then
			each(child, kind)
		end
	end
end

-- The player module's controls (PlayerModule:GetControls), found once.
local controls: any = nil
local controlsDisabled = false
local function playerControls(): any
	if controls then
		return controls
	end
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if module and module:IsA("ModuleScript") then
		local ok, found = pcall(function()
			return (require :: any)(module):GetControls()
		end)
		controls = if ok then found else nil
	end
	return controls
end

renderTouch = function()
	local open = dialogue.lines ~= nil
	if talkBound then
		ContextActionService:SetTitle(TALK_ACTION, TalkAndAdvance.title(open, TALK_LABELS))
	end
	-- on touch Amy listens while a Dialogue shows, and on every class she
	-- waits while the Pause screen is open: the controls are disabled
	local listening = (open and layout.touch) or PauseScreen.paused(pause)
	local found = if listening ~= controlsDisabled then playerControls() else nil
	if found then
		if listening then
			found:Disable()
		else
			found:Enable()
		end
		controlsDisabled = listening
	end
end

-- Lays the touch controls out in the Screen layout's zones.
local function placeTouchControls()
	if layout.touch ~= talkBound then
		if layout.touch then
			ContextActionService:BindAction(TALK_ACTION, talkOrAdvance, true)
		else
			ContextActionService:UnbindAction(TALK_ACTION)
		end
		talkBound = layout.touch
	end
	local button = if talkBound then ContextActionService:GetButton(TALK_ACTION) else nil
	if button and layout.talk then
		place(button, layout.talk)
	end
	eachControl(function(control, kind)
		if kind == "thumbstick" and layout.touch then
			place(control, layout.zones[1])
		elseif kind == "jump" and not hiddenJumps[control] then
			-- the player module shows it again on its own; it stays hidden
			hiddenJumps[control] = true
			control.Visible = false
			control:GetPropertyChangedSignal("Visible"):Connect(function()
				control.Visible = false
			end)
		end
	end)
	renderTouch()
end

ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
	prompts[prompt] = true
	Onboarding.promptShown(onboarding, true)
end)
ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
	prompts[prompt] = nil
	Onboarding.promptShown(onboarding, next(prompts) ~= nil)
end)

----------------------------------------------------------------
-- Objective tracker
----------------------------------------------------------------
SetObjective.OnClientEvent:Connect(Net.guard("SetObjective", function(text: string?)
	-- The server never moves on while a Dialogue shows, but for a Resume (a
	-- Dev shortcut's jump): the camera leaves that Dialogue's Shot.
	if DialogueViewModel.view(dialogue).open then
		Camera.resumed()
	end
	Onboarding.objectiveShown(onboarding, text)
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
local function renderCard()
	local frame = ChapterCardTimeline.at(card :: ChapterCardTimeline.Card, os.clock() - cardStarted)
	titleOverlay.Visible = frame ~= nil
	if not frame then
		card = nil
		Onboarding.cardGone(onboarding)
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
		if not ending then
			Onboarding.chapterShown(onboarding, title)
		end
		renderCard()
	end
end

titleOverlay.Activated:Connect(advance)

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
	renderPause() -- its button shows once the Title screen has gone
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
-- The Onboarding: the first minute's Hints
----------------------------------------------------------------
local PULSE_SECONDS = 1.2
-- the dialogue box's hint row as last set: the large Hint, or the standing one
local shownHint: string? = nil
-- where Amy was last frame, to count how far she walks
local lastAt: Vector3? = nil
-- the head the marker is over, found once
local markedHead: Instance? = nil

local function renderOnboarding()
	local view = Onboarding.view(onboarding, hints, layout.touch)
	if view.row ~= shownHint then
		shownHint = view.row
		hintLabel.Text = view.row
		hintLabel.TextSize = if view.large then layout.text.body else layout.text.hint
		local row = if view.large then layout.dialogue.largeHintRow else layout.dialogue.hintRow
		hintLabel.Size = UDim2.new(1, 0, 0, row)
	end
	onboardingHint.Text = view.hint or ""
	onboardingHint.Visible = view.hint ~= nil
	skipButton.Visible = view.skip
	thumbRing.Visible = view.ring and layout.ring ~= nil
	talkRing.Visible = view.pulse and layout.pulse ~= nil
	if talkRing.Visible then -- the pulse: the ring's stroke fades in and out
		talkStroke.Transparency = 0.5 - 0.5 * math.cos(os.clock() * 2 * math.pi / PULSE_SECONDS)
	end
	objectiveGlow.Transparency = if view.glow then 0 else 1
	if view.marker and not (markedHead and markedHead.Parent) then
		local characters = Workspace:FindFirstChild("StoryCharacters")
		local marked = characters and characters:FindFirstChild(view.marker)
		markedHead = marked and marked:FindFirstChild("Head")
	end
	local head = if view.marker then markedHead else nil
	markerGui.Adornee = head :: any -- a Head is a BasePart, or nil
	markerGui.Enabled = head ~= nil
end

-- How far Amy walked since the last frame, across the ground.
local function walked(): number
	local character = player.Character
	local amy = character and character:FindFirstChild("HumanoidRootPart")
	if not (amy and amy:IsA("BasePart")) then
		lastAt = nil
		return 0
	end
	local at = amy.Position * Vector3.new(1, 0, 1)
	local studs = if lastAt then (at - lastAt).Magnitude else 0
	lastAt = at
	return if studs < 10 then studs else 0 -- a teleport is not a walk
end

skipButton.Activated:Connect(function()
	Onboarding.skip(onboarding)
	renderOnboarding()
end)

----------------------------------------------------------------
-- The Pause screen and the Settings
----------------------------------------------------------------
-- The fonts each body text has with the standard font Setting.
local OWN_FONTS: { [TextLabel]: Enum.Font } = {}
for _, label in { bodyLabel, objectiveText, hintLabel, onboardingHint } do
	OWN_FONTS[label] = label.Font
end
local DYSLEXIA_FONT = Enum.Font:FromName(Settings.DYSLEXIA_FACE) or Enum.Font.GothamMedium

-- The dialogue box's colours and the body texts' font, for the Settings.
local function renderBox()
	local box = DialogueViewModel.box(settings.highContrast)
	dialogueFrame.BackgroundColor3 = rgb(box.background)
	dialogueFrame.BackgroundTransparency = box.transparency
	dialogueStroke.Color = rgb(box.stroke)
	hintLabel.TextColor3 = rgb(box.hint)
	for label, own in OWN_FONTS do
		label.Font = if settings.font == "dyslexia" then DYSLEXIA_FONT else own
	end
end
renderBox()

local applySettings: (Settings.Settings) -> ()

-- A label of the panel, `width` wide (0: as wide as its text).
local function pauseLabel(parent: Instance, text: string, size: number, width: number, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(width, height)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = rgb(pauseColours.text)
	label.TextSize = size
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.ZIndex = 42
	label.Parent = parent
	return label
end

-- A button of the panel; one that cannot be pressed is faded and inert.
local function pauseControl(parent: Instance, text: string, width: number, height: number, onPress: (() -> ())?)
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(width, height)
	button.BackgroundColor3 = rgb(pauseColours.button)
	button.BackgroundTransparency = if onPress then 0 else 0.6
	button.AutoButtonColor = onPress ~= nil
	button.Active = onPress ~= nil
	button.Font = Enum.Font.FredokaOne
	button.TextColor3 = rgb(pauseColours.label)
	button.TextSize = layout.text.body
	button.Text = text
	button.ZIndex = 42
	button.Parent = parent
	addCorner(button, 12)
	if onPress then
		button.Activated:Connect(onPress)
	end
	return button
end

-- A frame of the panel that lays its children out in a row or a column.
local function pauseGroup(parent: Instance, order: number, direction: Enum.FillDirection): Frame
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.BackgroundTransparency = 1
	frame.ZIndex = 41
	frame.Parent = parent
	local layoutList = list(frame, direction, layout.pause.gap)
	layoutList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layoutList.VerticalAlignment = Enum.VerticalAlignment.Center
	return frame
end

-- The Pause screen as the view-model says, built again on every change.
renderPause = function()
	local view = PauseScreen.view(pause)
	pauseButton.Visible = not titleScreen.Visible and not view.visible
	pauseOverlay.Visible = view.visible
	ProximityPromptService.Enabled = not view.visible -- Amy cannot talk while paused
	for _, child in pausePanel:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if not view.visible then
		return
	end
	local panel = layout.pause
	local body = layout.text.body
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	if view.heading then
		pauseLabel(pausePanel, view.heading, body, panel.width - 2 * panel.gap, panel.heading).LayoutOrder = nextOrder()
	end
	local note: string? = nil
	if view.settings then
		local rows
		rows, note = Settings.rows(settings, textCap)
		local rowDirection = if panel.stacked then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
		local target = ScreenLayout.TARGET
		for _, row in rows do
			local function change(direction: number): () -> ()
				return function()
					applySettings(Settings.change(settings, row.id, direction))
					ChangeSettings:FireServer(Settings.known(settings))
				end
			end
			local group = pauseGroup(pausePanel, nextOrder(), rowDirection)
			pauseLabel(group, row.label, body, panel.label, panel.labelHeight).LayoutOrder = 1
			local stepper = pauseGroup(group, 2, Enum.FillDirection.Horizontal)
			if row.toggle then
				pauseControl(stepper, row.value, panel.controls, target, change(1))
			else
				pauseControl(stepper, "−", target, target, if row.lower then change(-1) else nil).LayoutOrder = 1
				local value = pauseLabel(stepper, row.value, body, panel.value, target)
				value.TextXAlignment = Enum.TextXAlignment.Center
				value.LayoutOrder = 2
				pauseControl(stepper, "+", target, target, if row.higher then change(1) else nil).LayoutOrder = 3
			end
		end
	end
	-- the buttons, after the note when the Text scale is capped
	local footer = pauseGroup(pausePanel, nextOrder(), Enum.FillDirection.Horizontal)
	if note then
		pauseLabel(footer, note, layout.text.hint, panel.note, panel.footer).LayoutOrder = 0
	end
	for i, button in view.buttons do
		local control = pauseControl(footer, button.label, panel.button.width, panel.button.height, function()
			PauseScreen.press(pause, button.id)
			renderPause()
			renderTouch()
		end)
		control.LayoutOrder = i
		if button.primary then
			control.BackgroundColor3 = rgb(palette.gold)
		end
	end
end

local function togglePause()
	if not titleScreen.Visible then
		PauseScreen.toggle(pause)
		renderPause()
		renderTouch()
	end
end
pauseButton.Activated:Connect(togglePause)

----------------------------------------------------------------
-- The Screen layout: for the Device class, the viewport and the safe area
----------------------------------------------------------------
-- Every Line of the Story: the Text scale is capped so that each fits.
local LINES = Story.lineTexts(Content.story)
-- the device textCap was worked out for
local cappedFor: string? = nil

local preferred = nil
pcall(function() -- PreferredInput is newer than some clients
	preferred = UserInputService.PreferredInput.Name
end)
local inputKind: DeviceClass.InputKind =
	DeviceClass.starting(preferred, UserInputService.TouchEnabled, UserInputService.KeyboardEnabled)

local function offsets(rect: ScreenLayout.Rect): (UDim2, UDim2)
	return UDim2.fromOffset(rect.x, rect.y), UDim2.fromOffset(rect.width, rect.height)
end

local function absolute(gui: GuiObject): ScreenLayout.Rect
	local at, size = gui.AbsolutePosition, gui.AbsoluteSize
	return { x = at.X, y = at.Y, width = size.X, height = size.Y }
end

local function applyLayout()
	local screen = absolute(root)
	local device: ScreenLayout.Screen = {
		class = DeviceClass.pick(inputKind, screen.width, screen.height),
		width = screen.width,
		height = screen.height,
		insets = ScreenLayout.insets(screen, absolute(safeArea)),
		textScale = ScreenLayout.MAX_SCALE,
	}
	-- the cap depends on the device alone: worked out again when it changes
	local insets = device.insets
	local key =
		`{device.class} {device.width}x{device.height} {insets.left},{insets.top},{insets.right},{insets.bottom}`
	if key ~= cappedFor then
		cappedFor = key
		textCap = ScreenLayout.largestScale(device, LINES, LINES[1])
	end
	device.textScale = Settings.textScale(settings, textCap)
	layout = ScreenLayout.new(device)
	local text = layout.text
	Camera.setZones(layout.zones)
	placeTouchControls()
	onboardingHint.Position, onboardingHint.Size = offsets(layout.hint)
	onboardingHint.TextSize = text.hint
	skipButton.Position, skipButton.Size = offsets(layout.skip)
	skipButton.TextSize = text.hint
	if layout.ring then
		thumbRing.Position, thumbRing.Size = offsets(layout.ring)
	end
	if layout.pulse then
		talkRing.Position, talkRing.Size = offsets(layout.pulse)
	end

	local box = layout.dialogue
	shownHint = nil -- the hint row is set again for this layout
	dialogueFrame.Position = UDim2.fromOffset(box.x, box.bottom)
	fitDialogue() -- and again when the Lines settle at the new width
	speakerLabel.TextSize = text.speaker
	speakerLabel.Size = UDim2.fromOffset(0, box.speaker)
	bodyLabel.TextSize = text.body

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

	titleWords.Position, titleWords.Size = offsets(layout.safe)

	local choices = layout.title
	titleChoices.Position = UDim2.fromOffset(choices.x + choices.width / 2, choices.bottom)
	titleChoices.Size = UDim2.fromOffset(choices.width, 0)
	titleNote.TextSize = choices.note
	titleButtonList.Padding = UDim.new(0, choices.gap)

	pauseButton.Position, pauseButton.Size = offsets(layout.pauseButton)
	pauseButton.TextSize = text.speaker
	pausePanel.Position = UDim2.fromOffset(layout.pause.x, layout.pause.centre)
	pausePanel.Size = UDim2.fromOffset(layout.pause.width, 0)

	renderObjective()
	renderDialogue()
	renderOnboarding()
	renderPause()
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

applySettings = function(new: Settings.Settings)
	local rescaled = new.textScale ~= settings.textScale
	settings = new
	masterVolume.Volume = settings.volume
	renderBox()
	renderDialogue()
	if rescaled then
		applyLayout()
	else
		renderPause()
	end
end
ApplySettings.OnClientEvent:Connect(Net.guard("ApplySettings", applySettings, warn))

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.P then
		togglePause()
	end
end)

-- The player module builds its touch controls when touch is first used.
local function watchTouchGui(touchGui: Instance)
	if touchGui.Name == "TouchGui" then
		touchGui.DescendantAdded:Connect(function(added: Instance)
			if CONTROLS[added.Name] then
				task.defer(placeTouchControls)
			end
		end)
		task.defer(placeTouchControls)
	end
end
playerGui.ChildAdded:Connect(watchTouchGui)
local touchGui = playerGui:FindFirstChild("TouchGui")
if touchGui then
	watchTouchGui(touchGui)
end

----------------------------------------------------------------
-- Every frame: time passes for the Dialogue and the card
----------------------------------------------------------------
local wasTeaching = false
RunService.RenderStepped:Connect(function(seconds)
	if PauseScreen.paused(pause) then
		cardStarted += seconds -- a Chapter card holds; nothing else moves on
		return
	end
	if dialogue.lines then
		DialogueViewModel.tick(dialogue, seconds)
		renderDialogue()
	end
	if card then
		renderCard()
	end
	local teaching = onboarding.state == "running"
	if teaching then
		Onboarding.tick(onboarding, seconds)
		Onboarding.moved(onboarding, walked())
	end
	if teaching or wasTeaching then -- and once more when it ends, to clear it
		renderOnboarding()
	end
	wasTeaching = teaching
end)

----------------------------------------------------------------
-- Tell the server we're ready for the story to begin
----------------------------------------------------------------
task.wait(1) -- give the world a moment to stream in
ClientReady:FireServer()
