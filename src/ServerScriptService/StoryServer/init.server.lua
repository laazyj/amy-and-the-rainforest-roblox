--!strict
-- Starts the story engine. Its code is the Server module beside this Script,
-- so that the golden walkthrough (tests/engine/walkthrough.luau) can require
-- it in a Luau Execution task, where Scripts do not run.
require(script.Server)
