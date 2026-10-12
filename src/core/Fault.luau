--!strict
--[[
	Fault: the things that can go wrong for a player and are worth counting,
	as plain data (docs/GLOSSARY.md, "Faults"). Each has a name that reads
	as an analytics event name; the server reports one through FaultLog
	(src/server/FaultLog.luau), which today writes a warning line and which
	brief 015 routes to AnalyticsService custom events.

	  NAMES                      every Fault (the glossary says what each means)
	  line(name, player, why)    the warning line FaultLog writes
]]

export type Name = "save_unreadable" | "save_too_new" | "save_load_timeout" | "save_unavailable" | "save_close_unbound"

local Fault = {}

local PREFIX = "[Fault]"

Fault.NAMES = table.freeze({
	save_unreadable = true,
	save_too_new = true,
	save_load_timeout = true,
	save_unavailable = true,
	save_close_unbound = true,
} :: { [Name]: true })

-- "[Fault] save_unreadable player 123: <why>"; a Fault of the whole server
-- (no player) leaves the player out.
function Fault.line(name: Name, playerId: number?, why: string): string
	assert(Fault.NAMES[name], `unknown Fault {name}`)
	local who = if playerId then ` player {playerId}` else ""
	return `{PREFIX} {name}{who}: {why}`
end

return Fault
