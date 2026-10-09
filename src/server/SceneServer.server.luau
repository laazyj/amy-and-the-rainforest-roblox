--!strict
-- Builds the Scenes. The work is in the SceneBuilder module, so that engine
-- tests can build them in a Luau Execution task, where Scripts do not run.
require(script.Parent.SceneBuilder).build()
