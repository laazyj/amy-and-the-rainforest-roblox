--!strict
-- Publishes a place file to a universe through Open Cloud and prints the new
-- version number on stdout. Entry point: tools/publish.luau.

local Cli = require("./cli")
local OpenCloud = require("../opencloud")

local USAGE = "usage: lune run tools/publish --file <path.rbxl> --version-type Saved|Published"

local function main(ctx: Cli.Context)
	local target = Cli.target(ctx, USAGE, { "file", "version-type" })
	local path = Cli.required(target.values, "file")
	local versionType = Cli.required(target.values, "version-type")
	if versionType ~= "Saved" and versionType ~= "Published" then
		error(`--version-type must be Saved or Published, not '{versionType}'`, 0)
	end

	local placeFile = ctx.readFile(path)
	if not placeFile then
		if not target.dryRun then
			error(`place file not found: {path}`, 0)
		end
		ctx.log(`warning: place file not found: {path}`)
	end

	local request = OpenCloud.publishRequest(
		target.apiKey,
		target.universeId,
		target.placeId,
		versionType :: OpenCloud.VersionType,
		placeFile or ""
	)
	if target.dryRun then
		ctx.log("dry run: would send")
		ctx.log(OpenCloud.describe(request))
		return
	end

	local version = OpenCloud.parsePublishResponse(OpenCloud.call(ctx.http, ctx.sleep, request))
	ctx.log(
		`published {path} to universe {target.universeId} place {target.placeId} as {versionType} version {version}`
	)
	ctx.out(tostring(version))
end

return { main = main }
