--!strict
--[[
	Config: settings the server adapters read when they start.

	  storePrefix  goes before the name of every DataStore Persist opens
	               ("" in a real server, so the Save store is "Progress").
	               The engine harness (tests/engine/_world.luau) sets it to
	               "test-<RUN_ID>-<test>-" before anything starts, so engine
	               tests never touch a player's Save (docs/OPEN_CLOUD.md).
]]

return {
	storePrefix = "",
}
