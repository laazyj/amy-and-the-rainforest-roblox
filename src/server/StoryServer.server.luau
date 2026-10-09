--!strict
-- Starts the Story. The work is in the StoryHost module, so that the engine
-- walkthrough can start it in a Luau Execution task, where Scripts do not run.
require(script.Parent.StoryHost).start()
