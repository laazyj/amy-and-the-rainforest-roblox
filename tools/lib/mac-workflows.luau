--!strict
--[[
	The rule that keeps pull request code off the Mac runner (brief mac-001a,
	Must 3 and 7; docs/MAC_RUNNER.md): a workflow with a job on a self-hosted
	runner starts only from the triggers in ALLOWED, and every such job uses
	the `studio` environment, which only `main` may deploy to, so a branch
	cannot run its own copy of a Mac workflow. The repository is
	public, so this fails closed: a `runs-on` this file cannot prove is a
	GitHub-hosted runner counts as the Mac, and a trigger that is not listed
	is refused, `pull_request`, `pull_request_target` and `workflow_call`
	(which inherits its caller's trigger) among them.
]]

local MacWorkflows = {}

-- `push` only to main.
MacWorkflows.ALLOWED = { "workflow_dispatch", "schedule", "push" }
MacWorkflows.ENVIRONMENT = "studio"

local HOSTED = { "^ubuntu%-", "^macos%-", "^windows%-" }

local function hosted(label: any): boolean
	if type(label) == "string" then
		for _, pattern in HOSTED do
			if string.match(label, pattern) then
				return true
			end
		end
	end
	return false -- an expression, a runner group, or a label of our own
end

-- Whether a job's `runs-on` is anything but a GitHub-hosted runner.
local function selfHosted(runsOn: any): boolean
	if type(runsOn) == "table" and #runsOn > 0 then
		for _, label in runsOn do
			if not hosted(label) then
				return true
			end
		end
		return false
	end
	return not hosted(runsOn)
end

-- The workflow's triggers by name, whichever of the three ways `on` is written.
local function triggers(on: any): { [string]: any }
	if type(on) == "string" then
		return { [on] = {} }
	end
	local found: { [string]: any } = {}
	if type(on) == "table" then
		for key, value in on do
			if type(key) == "number" then
				found[tostring(value)] = {}
			else
				found[tostring(key)] = if type(value) == "table" then value else {}
			end
		end
	end
	return found
end

-- Lune's YAML decoder gives a key with no value (`workflow_dispatch:`) the
-- value nil, which a Luau table cannot hold, so the trigger would vanish.
-- Returns the text with `{}` written after every such key.
function MacWorkflows.explicit(yaml: string): string
	local lines = string.split(yaml, "\n")
	local function indent(line: string): number
		return #(string.match(line, "^ *") :: string)
	end
	for i, line in lines do
		if string.match(line, "^ *[%w_-]+: *$") or string.match(line, "^ *[%w_-]+: +#") then
			-- Has no value unless the next line with anything on it is nested.
			local nested = false
			for j = i + 1, #lines do
				if not string.match(lines[j], "^%s*$") and not string.match(lines[j], "^%s*#") then
					nested = indent(lines[j]) > indent(line) or string.match(lines[j], "^ *%- ") ~= nil
					break
				end
			end
			if not nested then
				lines[i] = (string.gsub(line, ":.*$", ": {}"))
			end
		end
	end
	return table.concat(lines, "\n")
end

-- What is wrong with a parsed workflow file, as sentences starting with
-- `path`. Empty when it has no job on the Mac or follows the rule.
function MacWorkflows.check(path: string, workflow: any): { string }
	if type(workflow) ~= "table" or type(workflow.jobs) ~= "table" then
		return { `{path}: is not a workflow (no jobs)` }
	end
	local problems = {}
	local onMac = false
	for name, job in workflow.jobs do
		-- A job that calls a reusable workflow has no runs-on; the workflow it
		-- calls is checked as its own file.
		if type(job) == "table" and job.uses == nil and selfHosted(job["runs-on"]) then
			onMac = true
			local environment = job.environment
			if type(environment) == "table" then
				environment = environment.name
			end
			if environment ~= MacWorkflows.ENVIRONMENT then
				table.insert(
					problems,
					`{path}: job '{name}' runs on the Mac without 'environment: {MacWorkflows.ENVIRONMENT}'`
				)
			end
		end
	end
	if not onMac then
		return {}
	end

	-- YAML 1.1 parsers read the key `on` as the boolean true.
	local found = triggers(workflow.on or workflow[true])
	if next(found) == nil then
		table.insert(problems, `{path}: runs on the Mac and its triggers cannot be read`)
	end
	for name, filters in found do
		if not table.find(MacWorkflows.ALLOWED, name) then
			table.insert(
				problems,
				`{path}: runs on the Mac and starts on '{name}'; only {table.concat(MacWorkflows.ALLOWED, ", ")} may start a Mac job`
			)
		elseif
			name == "push"
			and not (type(filters.branches) == "table" and #filters.branches == 1 and filters.branches[1] == "main")
		then
			table.insert(problems, `{path}: runs on the Mac and starts on a push; only 'branches: [main]' may`)
		end
	end
	table.sort(problems)
	return problems
end

return MacWorkflows
