--!strict
-- Starts the Dev shortcuts (DevShortcuts). Dev builds only: the publish
-- job strips this folder, ServerScriptService.Dev, from the Release place.
require(script.Parent.DevShortcuts).start()
