--!strict
-- Shared plumbing for the Open Cloud command-line tools: argument parsing,
-- the Release refusal and the run context that tests replace with mocks.

local OpenCloud = require("../opencloud")

export type Context = {
	args: { string },
	env: { [string]: string? },
	http: OpenCloud.Http,
	sleep: OpenCloud.Sleep,
	clock: () -> number, -- wall-clock seconds
	out: (string) -> (), -- stdout: results
	log: (string) -> (), -- stderr: progress, warnings, dry-run output
	readFile: (path: string) -> string?,
	listDir: (path: string) -> { string }?,
}

-- What every tool targets: a place in a universe, with the Release guard
-- already checked. `values` holds the tool's own `--name value` options.
export type Target = {
	values: { [string]: string },
	dryRun: boolean,
	universeId: string,
	placeId: string,
	apiKey: string,
}

local Cli = {}

local COMMON_OPTIONS = "--universe <id> --place <id> [--key-env NAME] [--dry-run]"

-- Parses `--name value` options (those in `valued`) and the --dry-run flag.
-- Anything else is an error; no arguments at all raises the usage text.
local function parseArgs(argv: { string }, usage: string, valued: { string }): ({ [string]: string }, boolean)
	if #argv == 0 then
		error(usage, 0)
	end
	local accepts: { [string]: boolean } = {}
	for _, name in valued do
		accepts[name] = true
	end
	local values: { [string]: string } = {}
	local dryRun = false
	local i = 1
	while i <= #argv do
		local name = string.match(argv[i], "^%-%-(.+)$")
		if name == "dry-run" then
			dryRun = true
		elseif name and accepts[name] then
			local value = argv[i + 1]
			if value == nil or string.sub(value, 1, 2) == "--" then
				error(`--{name} needs a value`, 0)
			end
			values[name] = value
			i += 1
		elseif name then
			error(`unknown option --{name}`, 0)
		else
			error(`unexpected argument '{argv[i]}'`, 0)
		end
		i += 1
	end
	return values, dryRun
end

function Cli.required(values: { [string]: string }, name: string): string
	return values[name] or error(`--{name} is required`, 0)
end

local function normaliseId(value: string): string?
	local digits = string.match(value, "^%s*(%d+)%s*$")
	return if digits then string.match(digits, "^0*(%d-%d)$") else nil
end

function Cli.numericId(values: { [string]: string }, name: string): string
	return normaliseId(Cli.required(values, name)) or error(`--{name} must be a numeric id`, 0)
end

-- Reads a Release id from the environment: nil when unset or empty (GitHub
-- passes a missing variable as ""), an error when set but not numeric.
local function releaseIdFromEnv(ctx: Context, name: string): string?
	local raw = ctx.env[name]
	if raw == nil or raw == "" then
		return nil
	end
	return normaliseId(raw) or error(`{name} is set but is not a numeric id; refusing to run`, 0)
end

-- The Release refusal. Nothing except the release job may target the Release
-- universe or place, and outside --dry-run the guard must be armed
-- (RELEASE_UNIVERSE_ID set) so a misconfigured job cannot disable it by
-- omission. RELEASE_PLACE_ID is checked too when it is set.
local function assertNotRelease(ctx: Context, universeId: string, placeId: string, dryRun: boolean)
	local releaseUniverse = releaseIdFromEnv(ctx, "RELEASE_UNIVERSE_ID")
	local releasePlace = releaseIdFromEnv(ctx, "RELEASE_PLACE_ID")
	if not releaseUniverse then
		if not dryRun then
			error("RELEASE_UNIVERSE_ID is not set; refusing to run without the Release guard armed", 0)
		end
		ctx.log("warning: RELEASE_UNIVERSE_ID is not set; the Release guard is not armed")
	end
	if ctx.env.RELEASE_JOB == "1" then
		return
	end
	local target = if universeId == releaseUniverse
		then `universe ({universeId})`
		elseif placeId == releasePlace then `place ({placeId})`
		else nil
	if target then
		error(`refusing to target the Release {target}: only the release job may do that (it sets RELEASE_JOB=1)`, 0)
	end
end

-- Parses the arguments every tool shares plus `ownOptions`, runs the Release
-- refusal, then reads the API key from the variable named by --key-env
-- (default ROBLOX_DEV_API_KEY). A dry run needs no key, as it sends nothing.
-- `usage` is the tool's own part of the usage line.
function Cli.target(ctx: Context, usage: string, ownOptions: { string }): Target
	local valued = { "universe", "place", "key-env" }
	table.move(ownOptions, 1, #ownOptions, #valued + 1, valued)
	local values, dryRun = parseArgs(ctx.args, `{usage}\n         {COMMON_OPTIONS}`, valued)
	local universeId = Cli.numericId(values, "universe")
	local placeId = Cli.numericId(values, "place")

	assertNotRelease(ctx, universeId, placeId, dryRun)

	local keyEnv = values["key-env"] or "ROBLOX_DEV_API_KEY"
	local apiKey = ctx.env[keyEnv]
	if not apiKey or apiKey == "" then
		if not dryRun then
			error(`no API key: environment variable {keyEnv} is not set`, 0)
		end
		apiKey = "<unset>"
	end
	return { values = values, dryRun = dryRun, universeId = universeId, placeId = placeId, apiKey = apiKey :: string }
end

-- The real context: Lune's network, clock, stdio and filesystem.
function Cli.liveContext(): Context
	local fs = require("@lune/fs")
	local net = require("@lune/net")
	local process = require("@lune/process")
	local stdio = require("@lune/stdio")
	local task = require("@lune/task")
	return {
		args = process.args,
		env = process.env,
		http = net.request :: any,
		sleep = function(seconds)
			task.wait(seconds)
		end,
		clock = os.time,
		out = function(line)
			stdio.write(line .. "\n")
		end,
		log = function(line)
			stdio.ewrite(line .. "\n")
		end,
		readFile = function(path)
			return if fs.isFile(path) then fs.readFile(path) else nil
		end,
		listDir = function(path)
			return if fs.isDir(path) then fs.readDir(path) else nil
		end,
	}
end

-- Runs `main` with the live context and exits with its status, so every tool
-- reports failures the same way.
function Cli.main(main: (Context) -> ())
	local ctx = Cli.liveContext()
	local ok, err = pcall(main :: any, ctx)
	if not ok then
		ctx.log(`error: {err}`)
	end
	require("@lune/process").exit(if ok then 0 else 1)
end

return Cli
