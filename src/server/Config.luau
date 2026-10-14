--!strict
--[[
	Config: settings the server adapters read when they start.

	  storePrefix  goes before the name of every DataStore Persist opens
	               ("" in a real server, so the Save store is "Progress").
	               The engine harness (tests/engine/_world.luau) sets it to
	               "test-<RUN_ID>-<test>-" before anything starts, so engine
	               tests never touch a player's Save (docs/OPEN_CLOUD.md).
	  chat         whether Roblox's text chat shows: on in Dev, where the
	               Dev shortcuts are chat commands, and off on Release. It
	               follows the Dev folder (ServerScriptService.Dev), which
	               the release job strips before it publishes
	               (tools/lib/release.luau), so a Release build has no chat
	               without a setting to forget. StoryHost applies it.
]]

return {
	storePrefix = "",
	chat = script.Parent:FindFirstChild("Dev") ~= nil,
}
