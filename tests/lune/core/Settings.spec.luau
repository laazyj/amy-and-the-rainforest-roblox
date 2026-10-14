--[[
	Settings: the defaults, what the Net contract accepts, reading a Save's
	Settings, changing one a step at a time, the Text scale capped per
	device, and the Settings screen's rows.
]]

local Settings = require("../../../src/core/Settings")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	local function with(changes: { [string]: any }): Settings.Settings
		local settings = table.clone(Settings.DEFAULTS)
		for key, value in changes do
			settings[key] = value
		end
		return settings
	end

	describe("Settings.DEFAULTS", function()
		it("are full volume, Text scale 1, the usual dialogue box and the standard font", function()
			expect(Settings.DEFAULTS).toEqual({ volume = 1, textScale = 1, highContrast = false, font = "standard" })
			expect(Settings.isDefault(Settings.DEFAULTS)).toBe(true)
			expect(Settings.problem(Settings.DEFAULTS)).toBeNil()
		end)

		it("offer Text scales from 1 to 1.5, feel.md's range", function()
			expect(Settings.TEXT_SCALES[1]).toBe(1)
			expect(Settings.TEXT_SCALES[#Settings.TEXT_SCALES]).toBe(1.5)
		end)

		it("name the dyslexia-friendly font, a font Roblox has: Cartoon, Comic Neue Angular", function()
			expect(Settings.DYSLEXIA_FACE).toBe("Cartoon")
			expect(Settings.FONTS).toEqual({ "standard", "dyslexia" })
		end)
	end)

	describe("Settings.problem", function()
		it("accepts every allowed value of every Setting", function()
			for _, volume in Settings.VOLUMES do
				for _, textScale in Settings.TEXT_SCALES do
					for _, highContrast in { true, false } do
						for _, font in Settings.FONTS do
							local settings =
								{ volume = volume, textScale = textScale, highContrast = highContrast, font = font }
							expect(Settings.problem(settings)).toBeNil()
						end
					end
				end
			end
		end)

		local wrong: { { any } } = {
			{ "not a table", "loud", "a table" },
			{ "a volume between steps", with({ volume = 0.3 }), "volume" },
			{ "a volume above full", with({ volume = 2 }), "volume" },
			{ "a Text scale above 1.5", with({ textScale = 3 }), "textScale" },
			{ "a Text scale as a string", with({ textScale = "1" }), "textScale" },
			{ "high contrast as a string", with({ highContrast = "yes" }), "highContrast" },
			{ "an unknown font", with({ font = "Comic Sans" }), "font" },
			{ "a missing Setting", { volume = 1, textScale = 1, highContrast = false }, "font" },
			{ "a Setting there is not", with({ narration = true }), "no Setting narration" },
		}
		for _, case in wrong do
			it(`rejects {case[1]}`, function()
				expect(Settings.problem(case[2])).toContain(case[3])
			end)
		end
	end)

	describe("Settings.read", function()
		it("gives the defaults for no Settings at all, as a Save made before them", function()
			expect(Settings.read(nil)).toEqual(Settings.DEFAULTS)
			expect(Settings.read(42)).toEqual(Settings.DEFAULTS)
		end)

		it("keeps each valid Setting, the default for one that is not, and a newer version's", function()
			local read = Settings.read({ volume = 0.5, textScale = 9, font = "dyslexia", narration = "on" })
			expect(read).toEqual({
				volume = 0.5,
				textScale = 1,
				highContrast = false,
				font = "dyslexia",
				narration = "on",
			})
			expect(Settings.known(read)).toEqual(with({ volume = 0.5, font = "dyslexia" }))
			expect(Settings.problem(Settings.known(read))).toBeNil()
		end)

		it("returns Settings that share no table with the defaults", function()
			local read = Settings.read(nil)
			read.volume = 0
			expect(Settings.DEFAULTS.volume).toBe(1)
		end)
	end)

	describe("Settings.change", function()
		it("steps the volume down to Off and up to full, no further", function()
			local settings = Settings.DEFAULTS
			expect(Settings.change(settings, "volume", 1).volume).toBe(1)
			for _ = 1, 10 do
				settings = Settings.change(settings, "volume", -1)
			end
			expect(settings.volume).toBe(0)
			expect(Settings.change(settings, "volume", 1).volume).toBe(0.25)
		end)

		it("steps the Text scale from 1 to 1.5, no further", function()
			local settings = Settings.change(Settings.DEFAULTS, "textScale", 1)
			expect(settings.textScale).toBe(1.25)
			settings = Settings.change(Settings.change(settings, "textScale", 1), "textScale", 1)
			expect(settings.textScale).toBe(1.5)
			expect(Settings.change(Settings.DEFAULTS, "textScale", -1).textScale).toBe(1)
		end)

		it("flips high contrast and the font either way, and leaves the Settings given as they were", function()
			local settings = Settings.change(Settings.DEFAULTS, "highContrast", -1)
			expect(settings.highContrast).toBe(true)
			expect(Settings.change(settings, "highContrast", 1).highContrast).toBe(false)
			expect(Settings.change(settings, "font", 1).font).toBe("dyslexia")
			expect(Settings.change(Settings.change(settings, "font", 1), "font", 1).font).toBe("standard")
			expect(Settings.DEFAULTS.highContrast).toBe(false)
			expect(Settings.isDefault(settings)).toBe(false)
		end)

		it("are the same Settings only when every known Setting agrees", function()
			expect(Settings.same(Settings.read({ narration = "on" }), Settings.DEFAULTS)).toBe(true)
			expect(Settings.same(Settings.change(Settings.DEFAULTS, "volume", -1), Settings.DEFAULTS)).toBe(false)
		end)

		it("keeps a newer version's Setting", function()
			local settings = Settings.read({ narration = "on" })
			expect(Settings.change(settings, "volume", -1).narration).toBe("on")
		end)
	end)

	describe("Settings.textScale", function()
		it("is the chosen Text scale, at most the device's cap, and 1 where nothing larger fits", function()
			local largest = with({ textScale = 1.5 })
			expect(Settings.textScale(largest, 1.5)).toBe(1.5)
			expect(Settings.textScale(largest, 1.35)).toBe(1.35)
			expect(Settings.textScale(with({ textScale = 1.25 }), 1.35)).toBe(1.25)
			expect(Settings.textScale(largest, nil)).toBe(1)
		end)
	end)

	describe("the Settings screen", function()
		local function row(rows: { Settings.Row }, id: string): Settings.Row
			for _, each in rows do
				if each.id == id then
					return each
				end
			end
			error(`no row {id}`)
		end

		it("lists every Setting in order, with its label and value", function()
			local rows, note = Settings.rows(Settings.DEFAULTS, 1.5)
			local ids, labels = {}, {}
			for _, each in rows do
				table.insert(ids, each.id)
				table.insert(labels, each.label)
			end
			expect(ids).toEqual({ "volume", "textScale", "highContrast", "font" })
			expect(labels).toEqual({ "Volume", "Text size", "High contrast", "Easy-read letters" })
			expect(row(rows, "volume").value).toBe("100%")
			expect(row(rows, "textScale").value).toBe("Normal")
			expect(row(rows, "highContrast").value).toBe("Off")
			expect(note).toBeNil()
		end)

		it("offers a lower and a higher step only where there is one; a toggle has neither", function()
			local rows = Settings.rows(with({ volume = 0 }), 1.5)
			expect(row(rows, "volume").lower).toBe(false)
			expect(row(rows, "volume").higher).toBe(true)
			expect(row(rows, "volume").value).toBe("Off")
			expect(row(rows, "highContrast").toggle).toBe(true)
			expect(row(rows, "highContrast").lower or row(rows, "highContrast").higher).toBe(false)
			local full = Settings.rows(with({ textScale = 1.5 }), 1.5)
			expect(row(full, "textScale").higher).toBe(false)
			expect(row(full, "textScale").value).toBe("Largest")
		end)

		it("says so when the screen cannot fit the Text scale chosen, and offers no larger one", function()
			local rows, note = Settings.rows(with({ textScale = 1.5 }), 1.35)
			expect(note).toBe(Settings.CAPPED)
			expect(row(rows, "textScale").higher).toBe(false)
			expect(row(rows, "textScale").lower).toBe(true)
			-- below the cap a larger step is still offered, and no note
			local below, none = Settings.rows(with({ textScale = 1.25 }), 1.35)
			expect(row(below, "textScale").higher).toBe(true)
			expect(none).toBeNil()
			-- where only 1 fits, no larger step at all
			expect(row(Settings.rows(Settings.DEFAULTS, 1), "textScale").higher).toBe(false)
		end)

		it("shows each font and contrast as On or Off", function()
			local rows = Settings.rows(with({ font = "dyslexia", highContrast = true }), 1.5)
			expect(row(rows, "font").value).toBe("On")
			expect(row(rows, "highContrast").value).toBe("On")
		end)

		it("knows its longest label and value, for the Screen layout", function()
			expect(Settings.LONGEST_LABEL).toBe(utf8.len("Easy-read letters"))
			expect(Settings.LONGEST_VALUE).toBe(utf8.len("Largest"))
		end)
	end)
end
