--!strict
-- Unit tests for the Open Cloud tools, against a mocked HTTP function.
-- Run from the repository root: lune run tests/lune/tools/run
-- Temporary entry point until these move onto tests/lune/runner.luau (brief 001).
local H = require("./_harness")
local process = require("@lune/process")

require("./cli.test")
require("./publish.test")
require("./engine-tests.test")
require("./prelude.test")

print(`\n{H.passed} passed, {#H.failures} failed`)
for _, failure in H.failures do
	print(`  {failure}`)
end
process.exit(if #H.failures == 0 then 0 else 1)
