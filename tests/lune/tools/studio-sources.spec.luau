-- Every piece of Luau the Studio tools send Studio to run is a string, so
-- a syntax error in one would otherwise first show in the Mac's VM.
local Fetch = require("../../../tools/studio-playtest/fetch")
local Playthrough = require("../../../tools/studio-playtest/playthrough")
local Smoke = require("../../../tools/studio-playtest/smoke")
local Studio = require("../../../tools/studio-playtest/studio")

local luau = require("@lune/luau")

local FOLDER = Fetch.folderName("12549617200", 1760000000)

local SOURCES: { [string]: string } = {
	["Smoke.PLAY_SCRIPT"] = Smoke.PLAY_SCRIPT,
	["Smoke.CLIENT_READY_SCRIPT"] = Smoke.CLIENT_READY_SCRIPT,
	["Playthrough.INSTALL_SCRIPT"] = Playthrough.INSTALL_SCRIPT,
	["Playthrough.observeScript"] = Playthrough.observeScript(3),
	["Playthrough.chatBarScript"] = Playthrough.chatBarScript(true),
	["Playthrough.selectScript"] = Playthrough.selectScript("LocalPlayer.PlayerGui.StoryUI.TitleScreen"),
	["Studio.deviceScript, a device"] = Studio.deviceScript(Playthrough.DEVICES[3].device),
	["Studio.deviceScript, none"] = Studio.deviceScript(nil),
	["Fetch.prepareScript"] = Fetch.prepareScript(FOLDER),
	["Fetch.describeScript"] = Fetch.describeScript(FOLDER, "12549617200"),
	["Fetch.serialiseScript"] = Fetch.serialiseScript(FOLDER),
}

return function(t: any)
	t.describe("studio-playtest sources", function()
		for name, source in SOURCES do
			t.it(`compiles {name}`, function()
				local ok, err = pcall(luau.compile, source)
				t.expect(if ok then nil else tostring(err)).toBeNil()
			end)
		end
	end)
end
