--!strict
--[[
	PauseScreen: the Pause screen and its Settings page, as the view-model
	the client binder renders (plan section 2.3, "UI"). The pause button
	(or P on a PC) opens it; while it is open the Story does not advance:
	the binder takes no input to the Story, a Dialogue does not type on,
	a Chapter card holds, and Amy cannot walk or talk. Nothing the server
	waits on can then happen, since every step waits on the player.

	  new()              closed
	  toggle(vm)         the pause button or key: opens it, or closes it
	                     from either page
	  press(vm, button)  a button pressed: "resume" closes it, "settings"
	                     shows the Settings page, "back" the Pause page
	  paused(vm)         whether it is open
	  view(vm)           what it shows now; the Settings page's rows come
	                     from Settings.rows

	Its colours are here, as plain data, so tier 1 holds them to 7:1.
]]

local DialogueViewModel = require("./DialogueViewModel")
local Story = require("./Story")

export type Page = "closed" | "pause" | "settings"
export type Button = "resume" | "settings" | "back"
export type PauseScreen = { page: Page }

export type View = {
	visible: boolean,
	-- the Settings page shows the Settings' rows above its button
	settings: boolean,
	-- the Pause page's; the Settings page's rows say what it is
	heading: string?,
	-- in order; the first is the main one
	buttons: { { id: Button, label: string, primary: boolean } },
}

local PauseScreen = {}

PauseScreen.LABELS = table.freeze({
	resume = "Resume",
	settings = "Settings",
	back = "Back",
} :: { [Button]: string })

PauseScreen.HEADING = "Paused"

-- The pause button's glyph.
PauseScreen.GLYPH = "II"

-- The panel, as the dialogue box, and its text; a button and its label.
PauseScreen.COLOURS = table.freeze({
	panel = DialogueViewModel.BOX.background,
	text = table.freeze({ r = 240, g = 248, b = 235 }),
	button = table.freeze({ r = 255, g = 244, b = 214 }),
	label = table.freeze({ r = 35, g = 64, b = 29 }),
} :: { [string]: Story.RGB })

local PAGES: { [Page]: { Button } } = {
	pause = { "resume", "settings" },
	settings = { "back" },
}

function PauseScreen.new(): PauseScreen
	return { page = "closed" }
end

function PauseScreen.toggle(vm: PauseScreen)
	vm.page = if vm.page == "closed" then "pause" else "closed"
end

function PauseScreen.press(vm: PauseScreen, button: Button)
	if vm.page == "closed" or not table.find(PAGES[vm.page], button) then
		return
	end
	vm.page = if button == "resume" then "closed" elseif button == "settings" then "settings" else "pause"
end

function PauseScreen.paused(vm: PauseScreen): boolean
	return vm.page ~= "closed"
end

function PauseScreen.view(vm: PauseScreen): View
	if vm.page == "closed" then
		return { visible = false, settings = false, heading = nil, buttons = {} }
	end
	local buttons = {}
	for i, id: Button in PAGES[vm.page] do
		table.insert(buttons, { id = id, label = PauseScreen.LABELS[id], primary = i == 1 })
	end
	return {
		visible = true,
		settings = vm.page == "settings",
		heading = if vm.page == "pause" then PauseScreen.HEADING else nil,
		buttons = buttons,
	}
end

return PauseScreen
