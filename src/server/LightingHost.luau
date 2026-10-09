--!strict
-- LightingHost: the Story's colour grade, and the Lighting presets it
-- changes into.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Story = require(ReplicatedStorage:WaitForChild("core"):WaitForChild("Story"))
local Convert = require(script.Parent.Convert)

local LightingHost = {}

local story: Story.Story
local colorGrade: ColorCorrectionEffect
local current: string

function LightingHost.build(forStory: Story.Story)
	story = forStory
	current = forStory.initialLighting
	colorGrade = Instance.new("ColorCorrectionEffect")
	colorGrade.Name = "StoryColorGrade"
	colorGrade.Saturation = 0
	colorGrade.Parent = Lighting
end

-- Changes into the preset over its `seconds`.
function LightingHost.set(presetId: string)
	local preset = assert(story.lighting[presetId], presetId)
	current = presetId
	TweenService:Create(colorGrade, TweenInfo.new(preset.seconds), {
		Saturation = preset.saturation,
		Contrast = preset.contrast,
		TintColor = Convert.colour(preset.tint),
	}):Play()
end

-- The preset the Story is in (or changing into).
function LightingHost.preset(): string
	return current
end

return LightingHost
