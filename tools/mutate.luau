--!strict
--[[
	The mutation check (tools/lib/mutate.luau): applies each canned fault on
	its own to a copy of the repository, runs tier 1 there, and prints which
	tests caught it. Fails if any fault survives or no longer applies. The
	working tree is never touched.

	  lune run tools/mutate

	Prints the report as Markdown on stdout (the nightly
	.github/workflows/mutation.yml appends it to the job summary) and the
	progress on stderr. Needs the toolchain in build/bin, as tools/test.sh
	does.
]]

local Cli = require("./lib/cli")
local Files = require("./lib/files")
local Mutate = require("./lib/mutate")
local fs = require("@lune/fs")
local process = require("@lune/process")

local SKIP = { [".git"] = true, build = true }

Cli.main(function(ctx)
	local made = process.exec("mktemp", { "-d" })
	assert(made.ok, `mktemp failed: {made.stderr}`)
	local copy = string.gsub(made.stdout, "%s+$", "")
	for _, entry in fs.readDir(Files.ROOT) do
		if not SKIP[entry] then
			fs.copy(`{Files.ROOT}/{entry}`, `{copy}/{entry}`)
		end
	end

	local env = { PATH = `{Files.ROOT}/build/bin:{ctx.env.PATH or ""}` }
	local runner: Mutate.Runner = {
		read = function(path)
			return fs.readFile(`{copy}/{path}`)
		end,
		write = function(path, text)
			fs.writeFile(`{copy}/{path}`, text)
		end,
		test = function()
			local result = process.exec("lune", { "run", "tests/lune/runner.luau" }, { cwd = copy, env = env })
			return result.ok, result.stdout .. result.stderr
		end,
		log = ctx.log,
	}

	local ok, err = pcall(function()
		local passed, output = runner.test()
		if not passed then
			error(`tier 1 fails before any fault is applied:\n{output}`, 0)
		end
		local results = Mutate.run(Mutate.FAULTS, runner)
		ctx.out(Mutate.report(results))
		local survivors = Mutate.survivors(results)
		if #survivors > 0 then
			error(`{#survivors} of {#results} fault(s) survived or no longer apply`, 0)
		end
	end)
	fs.removeDir(copy)
	if not ok then
		error(err, 0)
	end
end)
