--!strict
--[[
	FaultLog: where the server reports a Fault (src/core/Fault). It writes
	the warning line, keeps the last few reports, which the engine tests
	read, and logs each to Roblox Analytics as a custom event named after
	the Fault (src/server/Analytics).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fault = require(ReplicatedStorage:WaitForChild("core"):WaitForChild("Fault"))
local Analytics = require(script.Parent.Analytics)

export type Report = { name: Fault.Name, playerId: number?, why: string }

local KEPT = 50

local FaultLog = {}

-- The last KEPT reports, oldest first.
FaultLog.reported = {} :: { Report }

function FaultLog.report(name: Fault.Name, player: any?, why: string)
	local playerId = if player then player.UserId else nil
	warn(Fault.line(name, playerId, why))
	Analytics.fault(name, player)
	table.insert(FaultLog.reported, { name = name, playerId = playerId, why = why })
	if #FaultLog.reported > KEPT then
		table.remove(FaultLog.reported, 1)
	end
end

return FaultLog
