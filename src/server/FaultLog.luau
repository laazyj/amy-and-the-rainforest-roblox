--!strict
--[[
	FaultLog: where the server reports a Fault (src/core/Fault). Today it
	writes the warning line and keeps the last few reports, which the
	engine tests read; brief 015 sends each to AnalyticsService as a custom
	event named after the Fault.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fault = require(ReplicatedStorage:WaitForChild("core"):WaitForChild("Fault"))

export type Report = { name: Fault.Name, playerId: number?, why: string }

local KEPT = 50

local FaultLog = {}

-- The last KEPT reports, oldest first.
FaultLog.reported = {} :: { Report }

function FaultLog.report(name: Fault.Name, player: any?, why: string)
	local playerId = if player then player.UserId else nil
	warn(Fault.line(name, playerId, why))
	table.insert(FaultLog.reported, { name = name, playerId = playerId, why = why })
	if #FaultLog.reported > KEPT then
		table.remove(FaultLog.reported, 1)
	end
end

return FaultLog
