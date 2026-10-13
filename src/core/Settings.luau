--!strict
--[[
	Settings: a player's Settings, as plain data, and the Settings screen's
	view-model (plan section 5.3, Phase 1 "Settings"; docs/design/feel.md
	section 3). The Save keeps them (src/core/Save, schema version 3), the
	server sends them at join (ApplySettings) and the client sends a change
	back (ChangeSettings), both held to `problem` by the Net contract.

	  volume        0 to 1 in quarters; the client sets the volume of every
	                sound through SoundService
	  textScale     the Text scale chosen: 1, 1.25 or 1.5. The client lays
	                out at it, capped by ScreenLayout.largestScale so a Line
	                never spills; the Settings screen says when the cap
	                applies
	  highContrast  the dialogue box at 7:1 (DialogueViewModel.box)
	  font          "standard", or "dyslexia": the dyslexia-friendly font,
	                for the Lines, the Objective and the Hints (FACES)

	  problem(value)     why `value` is not Settings for the wire: exactly
	                     the known fields, each an allowed value
	  read(value)        Settings from a Save: each known field that is
	                     valid kept, the default for the rest, and the
	                     fields a newer version added kept as they were
	  known(settings)    only the known fields: what goes on the wire
	  isDefault(settings)
	  change(settings, setting, direction)
	                     one Setting moved a step up (1) or down (-1); a
	                     toggle flips either way
	  textScale(settings, cap)
	                     the Text scale to lay out at: the chosen one, at
	                     most `cap`
	  rows(settings, cap) the Settings screen: one row per Setting, and the
	                     note it shows when the cap applies
]]

export type Font = "standard" | "dyslexia"
export type Setting = "volume" | "textScale" | "highContrast" | "font"

export type Settings = {
	volume: number,
	textScale: number,
	highContrast: boolean,
	font: Font,
	-- fields of a newer schema version, kept as they were read
	[string]: any,
}

-- A row of the Settings screen: a stepped Setting has a lower and a higher
-- button round its value; a toggle is one button showing its value.
export type Row = {
	id: Setting,
	label: string,
	value: string,
	toggle: boolean,
	lower: boolean,
	higher: boolean,
}

local Settings = {}

Settings.VOLUMES = table.freeze({ 0, 0.25, 0.5, 0.75, 1 })
Settings.TEXT_SCALES = table.freeze({ 1, 1.25, 1.5 })
Settings.FONTS = table.freeze({ "standard", "dyslexia" } :: { Font })

-- The Settings, in the order the Settings screen lists them.
Settings.ORDER = table.freeze({ "volume", "textScale", "highContrast", "font" } :: { Setting })

Settings.DEFAULTS = table.freeze({
	volume = 1,
	textScale = 1,
	highContrast = false,
	font = "standard",
} :: Settings)

-- Each font's Roblox Enum.Font name, which the client binder sets on the
-- Lines, the Objective and the Hints. Cartoon is Comic Neue Angular: its
-- b, d, p and q are not mirror images and its capital I has bars, so it
-- is not confused with l, which is what a dyslexia-friendly font needs.
Settings.FACES = table.freeze({
	standard = "GothamMedium",
	dyslexia = "Cartoon",
} :: { [Font]: string })

Settings.LABELS = table.freeze({
	volume = "Volume",
	textScale = "Text size",
	highContrast = "High contrast",
	font = "Easy-read letters",
} :: { [Setting]: string })

-- Each Setting's choices, in order, and what the Settings screen shows for
-- each. A Setting of two choices is a toggle, flipped either way; the
-- others step up and down, no further than their ends.
local CHOICES: { [Setting]: { any } } = {
	volume = Settings.VOLUMES,
	textScale = Settings.TEXT_SCALES,
	highContrast = { false, true },
	font = Settings.FONTS,
}
local SHOWN: { [Setting]: { string } } = {
	volume = { "Off", "25%", "50%", "75%", "100%" },
	textScale = { "Normal", "Large", "Largest" },
	highContrast = { "Off", "On" },
	font = { "Off", "On" },
}

-- Shown under the rows when the screen cannot fit text as large as chosen.
Settings.CAPPED = "This is the biggest text that fits this screen."

-- How many characters the longest of `texts` has.
local function longest(texts: { string }): number
	local most = 0
	for _, text in texts do
		most = math.max(most, utf8.len(text) or #text)
	end
	return most
end

-- The longest label and value, for the Screen layout.
local labels, values = {}, {}
for setting: Setting, label in Settings.LABELS do
	table.insert(labels, label)
	table.move(SHOWN[setting], 1, #SHOWN[setting], #values + 1, values)
end
Settings.LONGEST_LABEL = longest(labels)
Settings.LONGEST_VALUE = longest(values)

local function isToggle(setting: Setting): boolean
	return #CHOICES[setting] == 2
end

-- Why `value` is not an allowed value of `setting`, or nil when it is.
local function invalid(setting: Setting, value: any): string?
	local choices = CHOICES[setting]
	if table.find(choices, value) then
		return nil
	end
	local allowed = {}
	for _, choice in choices do
		table.insert(allowed, tostring(choice))
	end
	return `{setting} must be one of {table.concat(allowed, ", ")}, got {tostring(value)} ({typeof(value)})`
end

function Settings.problem(value: any): string?
	if type(value) ~= "table" then
		return `Settings are a table, not {typeof(value)}`
	end
	for _, setting: Setting in Settings.ORDER do
		local wrong = invalid(setting, value[setting])
		if wrong then
			return wrong
		end
	end
	for key in value do
		if Settings.DEFAULTS[key] == nil then
			return `there is no Setting {tostring(key)}`
		end
	end
	return nil
end

function Settings.read(value: any): Settings
	local settings = table.clone(Settings.DEFAULTS)
	if type(value) ~= "table" then
		return settings
	end
	for key, item in value do
		if Settings.DEFAULTS[key] == nil or not invalid(key :: Setting, item) then
			settings[key] = item
		end
	end
	return settings
end

function Settings.known(settings: Settings): Settings
	local known = {}
	for _, setting in Settings.ORDER do
		known[setting] = settings[setting]
	end
	return known :: Settings
end

function Settings.isDefault(settings: Settings): boolean
	for _, setting in Settings.ORDER do
		if settings[setting] ~= Settings.DEFAULTS[setting] then
			return false
		end
	end
	return true
end

function Settings.change(settings: Settings, setting: Setting, direction: number): Settings
	local choices = CHOICES[setting]
	local at = table.find(choices, settings[setting]) or 1
	local changed = table.clone(settings)
	changed[setting] = if isToggle(setting)
		then choices[3 - at]
		else choices[math.clamp(at + math.sign(direction), 1, #choices)]
	return changed
end

-- The cap on the Text scale: ScreenLayout.largestScale's for the device,
-- nil when nothing fits but the smallest.
local function capOf(cap: number?): number
	return cap or Settings.TEXT_SCALES[1]
end

function Settings.textScale(settings: Settings, cap: number?): number
	return math.min(settings.textScale, capOf(cap))
end

function Settings.rows(settings: Settings, cap: number?): ({ Row }, string?)
	local largest = capOf(cap)
	local rows: { Row } = {}
	for _, setting: Setting in Settings.ORDER do
		local choices = CHOICES[setting]
		local at = table.find(choices, settings[setting]) or 1
		local toggle = isToggle(setting)
		local higher = not toggle and at < #choices
		if setting == "textScale" then
			-- no larger step while the screen already shows its largest
			higher = higher and settings.textScale < largest
		end
		table.insert(rows, {
			id = setting,
			label = Settings.LABELS[setting],
			value = SHOWN[setting][at],
			toggle = toggle,
			lower = not toggle and at > 1,
			higher = higher,
		})
	end
	return rows, if largest < settings.textScale then Settings.CAPPED else nil
end

return Settings
