--[[
	PauseScreen: opening and closing it, its two pages and their buttons,
	that the Story is paused while it is open, and its colours at 7:1.
]]

local Contrast = require("../../../src/core/Contrast")
local PauseScreen = require("../../../src/core/PauseScreen")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	local function ids(view: PauseScreen.View): { string }
		local list = {}
		for _, button in view.buttons do
			table.insert(list, button.id)
		end
		return list
	end

	describe("PauseScreen", function()
		it("is closed, and the Story not paused, until the pause button is pressed", function()
			local vm = PauseScreen.new()
			expect(PauseScreen.paused(vm)).toBe(false)
			expect(PauseScreen.view(vm).visible).toBe(false)
		end)

		it("opens on its Pause page, with Resume first and Settings, and pauses the Story", function()
			local vm = PauseScreen.new()
			PauseScreen.toggle(vm)
			local view = PauseScreen.view(vm)
			expect(PauseScreen.paused(vm)).toBe(true)
			expect(view.heading).toBe("Paused")
			expect(ids(view)).toEqual({ "resume", "settings" })
			expect(view.buttons[1].primary).toBe(true)
			expect(view.settings).toBe(false)
		end)

		it("shows the Settings page, still paused, and goes back to the Pause page", function()
			local vm = PauseScreen.new()
			PauseScreen.toggle(vm)
			PauseScreen.press(vm, "settings")
			local view = PauseScreen.view(vm)
			expect(view.settings).toBe(true)
			expect(view.heading).toBeNil()
			expect(ids(view)).toEqual({ "back" })
			expect(PauseScreen.paused(vm)).toBe(true)
			PauseScreen.press(vm, "back")
			expect(PauseScreen.view(vm).settings).toBe(false)
		end)

		it("closes on Resume, and on the pause button from either page", function()
			local vm = PauseScreen.new()
			PauseScreen.toggle(vm)
			PauseScreen.press(vm, "resume")
			expect(PauseScreen.paused(vm)).toBe(false)
			PauseScreen.toggle(vm)
			PauseScreen.press(vm, "settings")
			PauseScreen.toggle(vm)
			expect(PauseScreen.paused(vm)).toBe(false)
		end)

		it("ignores a button its page does not show", function()
			local vm = PauseScreen.new()
			PauseScreen.press(vm, "settings")
			expect(PauseScreen.paused(vm)).toBe(false)
			PauseScreen.toggle(vm)
			PauseScreen.press(vm, "back")
			expect(PauseScreen.view(vm).heading).toBe("Paused")
		end)

		it("puts its text and its buttons' labels at 7:1, the high-contrast standard", function()
			local colours = PauseScreen.COLOURS
			expect(Contrast.ratio(colours.text, colours.panel) >= Contrast.HIGH).toBe(true)
			expect(Contrast.ratio(colours.label, colours.button) >= Contrast.HIGH).toBe(true)
		end)
	end)
end
