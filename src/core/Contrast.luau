--!strict
--[[
	Contrast: how well text stands out from what is behind it, as WCAG 2's
	contrast ratio of two plain colours (1 to 21). docs/design/feel.md
	section 3 asks for at least 4.5:1, and 7:1 in the high-contrast
	setting. Tier 1 checks the view-model's colours with it; tier 3
	(tests/studio) the rendered UI.
]]

local Story = require("./Story")

local Contrast = {}

Contrast.MINIMUM = 4.5
-- the high-contrast Setting's
Contrast.HIGH = 7

local function channel(value: number): number
	local c = value / 255
	return if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
end

-- WCAG 2's relative luminance, 0 (black) to 1 (white).
function Contrast.luminance(colour: Story.RGB): number
	return 0.2126 * channel(colour.r) + 0.7152 * channel(colour.g) + 0.0722 * channel(colour.b)
end

-- What shows where `colour` is drawn with `transparency` (0 opaque to 1
-- clear) over `backdrop`.
function Contrast.over(colour: Story.RGB, transparency: number, backdrop: Story.RGB): Story.RGB
	return {
		r = math.lerp(colour.r, backdrop.r, transparency),
		g = math.lerp(colour.g, backdrop.g, transparency),
		b = math.lerp(colour.b, backdrop.b, transparency),
	}
end

function Contrast.ratio(a: Story.RGB, b: Story.RGB): number
	local la, lb = Contrast.luminance(a), Contrast.luminance(b)
	return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

return Contrast
