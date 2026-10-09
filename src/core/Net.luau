--!strict
--[[
	Net: the contract between the server and the client binder. Each remote,
	which way it goes and the payload it carries, positionally; `check`
	rejects anything else, and `message` says which World commands reach the
	client and as what. The remotes themselves are made by src/shared/Net.

	The remote names predate the glossary and are kept on the wire, so the
	golden file (tests/fixtures/golden/walkthrough.json) still names them:
	ShowChapterCard travels as ShowChapter, or ShowEnding for the end card.
]]

local Events = require("./Events")

export type Direction = "toClient" | "toServer"
export type Remote = { direction: Direction, args: { Events.FieldType } }
export type Args = { n: number, [number]: any }

local Net = {}

Net.FOLDER = "StoryRemotes"

Net.REMOTES = table.freeze({
	ShowDialogue = { direction = "toClient", args = { "lines" } },
	SetObjective = { direction = "toClient", args = { "string?" } },
	ShowChapter = { direction = "toClient", args = { "string", "string" } },
	ShowEnding = { direction = "toClient", args = { "string", "string" } },
	DialogueFinished = { direction = "toServer", args = {} },
	ClientReady = { direction = "toServer", args = {} },
} :: { [string]: Remote })

-- Holds a remote's arguments (from table.pack) to its payload: the right
-- count, each of its type. Returns false and the reason when they do not hold.
function Net.check(remote: string, args: Args): (boolean, string?)
	local contract = Net.REMOTES[remote]
	if not contract then
		return false, `unknown remote {remote}`
	end
	if args.n > #contract.args then
		return false, `{remote} takes {#contract.args} argument(s), got {args.n}`
	end
	for i, fieldType in contract.args do
		if not Events.matches(fieldType, args[i]) then
			return false, `{remote} argument {i} must be {fieldType}, got {typeof(args[i])}`
		end
	end
	return true, nil
end

-- The remote and arguments that carry `command` to the client, or nil for a
-- command the server carries out itself.
function Net.message(command: Events.WorldCommand): (string?, Args?)
	if command.kind == "ShowDialogue" then
		return "ShowDialogue", table.pack(command.lines)
	elseif command.kind == "SetObjective" then
		return "SetObjective", table.pack(command.text)
	elseif command.kind == "ShowChapterCard" then
		return if command.ending then "ShowEnding" else "ShowChapter", table.pack(command.title, command.subtitle)
	end
	return nil, nil
end

return Net
