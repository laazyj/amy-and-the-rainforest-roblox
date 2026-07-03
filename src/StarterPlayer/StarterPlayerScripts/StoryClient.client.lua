--[[
	StoryClient
	===========
	Everything the player sees on screen:
	  * the dialogue box with a typewriter effect
	  * the objective tracker (top right)
	  * chapter title cards and the ending card

	Click, press E, Space or Enter to advance dialogue.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("StoryRemotes")
local ShowDialogue = remotes:WaitForChild("ShowDialogue")
local DialogueFinished = remotes:WaitForChild("DialogueFinished")
local SetObjective = remotes:WaitForChild("SetObjective")
local ShowChapter = remotes:WaitForChild("ShowChapter")
local ShowEnding = remotes:WaitForChild("ShowEnding")
local ClientReady = remotes:WaitForChild("ClientReady")

----------------------------------------------------------------
-- Build the UI
----------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StoryUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.Parent = playerGui

local function addCorner(guiObject, radius)
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
objectiveHeader.Text = "✦ Objective"
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
-- Dialogue playback
----------------------------------------------------------------
local dialogueQueue = {}
local dialogueActive = false
local advanceRequested = false

local function requestAdvance()
	advanceRequested = true
end

clickCatcher.Activated:Connect(requestAdvance)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if not dialogueActive then
		return
	end
	if input.KeyCode == Enum.KeyCode.E
		or input.KeyCode == Enum.KeyCode.Space
		or input.KeyCode == Enum.KeyCode.Return then
		requestAdvance()
	end
end)

local function waitForAdvance()
	advanceRequested = false
	while not advanceRequested do
		task.wait(0.05)
	end
end

local function typewrite(label, text)
	label.Text = text
	local total = utf8.len(text) or string.len(text)
	label.MaxVisibleGraphemes = 0
	advanceRequested = false
	local shown = 0
	while shown < total do
		if advanceRequested then
			break -- skip straight to the full line
		end
		shown = shown + 1
		label.MaxVisibleGraphemes = shown
		task.wait(0.022)
	end
	label.MaxVisibleGraphemes = -1
end

local function playLines(lines)
	dialogueActive = true
	dialogueFrame.Visible = true
	clickCatcher.Visible = true

	for _, line in ipairs(lines) do
		local speaker = line.speaker or ""
		speakerLabel.Text = speaker
		speakerLabel.Visible = speaker ~= ""

		if speaker == "Narrator" then
			speakerLabel.BackgroundColor3 = Color3.fromRGB(120, 110, 160)
			bodyLabel.TextColor3 = Color3.fromRGB(225, 225, 245)
		elseif speaker == "Amy" then
			speakerLabel.BackgroundColor3 = Color3.fromRGB(214, 120, 140)
			bodyLabel.TextColor3 = Color3.fromRGB(248, 240, 240)
		else
			speakerLabel.BackgroundColor3 = Color3.fromRGB(94, 160, 80)
			bodyLabel.TextColor3 = Color3.fromRGB(240, 248, 235)
		end

		typewrite(bodyLabel, line.text or "")
		waitForAdvance()
	end

	dialogueFrame.Visible = false
	clickCatcher.Visible = false
	dialogueActive = false
	DialogueFinished:FireServer()
end

ShowDialogue.OnClientEvent:Connect(function(lines)
	table.insert(dialogueQueue, lines)
end)

task.spawn(function()
	while true do
		if #dialogueQueue > 0 and not dialogueActive then
			local lines = table.remove(dialogueQueue, 1)
			playLines(lines)
		end
		task.wait(0.1)
	end
end)

----------------------------------------------------------------
-- Objective tracker
----------------------------------------------------------------
SetObjective.OnClientEvent:Connect(function(text)
	if text and text ~= "" then
		objectiveFrame.Visible = true
		objectiveText.Text = text
		-- little pop so updates are noticeable
		objectiveFrame.BackgroundTransparency = 0
		TweenService:Create(objectiveFrame, TweenInfo.new(0.6), { BackgroundTransparency = 0.25 }):Play()
	else
		objectiveFrame.Visible = false
	end
end)

----------------------------------------------------------------
-- Chapter cards / ending
----------------------------------------------------------------
local function showCard(title, subtitle, holdTime, keepDark)
	titleOverlay.Visible = true
	titleLabel.Text = title or ""
	subtitleLabel.Text = subtitle or ""

	local fadeIn = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(titleOverlay, fadeIn, { BackgroundTransparency = 0.25 }):Play()
	TweenService:Create(titleLabel, fadeIn, { TextTransparency = 0 }):Play()
	TweenService:Create(subtitleLabel, fadeIn, { TextTransparency = 0 }):Play()

	task.wait(holdTime or 2.6)

	local fadeOut = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if not keepDark then
		TweenService:Create(titleOverlay, fadeOut, { BackgroundTransparency = 1 }):Play()
	end
	TweenService:Create(titleLabel, fadeOut, { TextTransparency = 1 }):Play()
	TweenService:Create(subtitleLabel, fadeOut, { TextTransparency = 1 }):Play()
	task.wait(0.9)
	if not keepDark then
		titleOverlay.Visible = false
	end
end

ShowChapter.OnClientEvent:Connect(function(title, subtitle)
	task.spawn(showCard, title, subtitle, 2.4, false)
end)

ShowEnding.OnClientEvent:Connect(function(title, subtitle)
	task.spawn(function()
		showCard(title, subtitle, 6, false)
		-- after the card fades, the player is free to wander in the rain
	end)
end)

----------------------------------------------------------------
-- Tell the server we're ready for the story to begin
----------------------------------------------------------------
task.wait(1) -- give the world a moment to stream in
ClientReady:FireServer()
