--!strict
--[[
	Companion: how a Companion goes about with Amy, as plain data (plan
	section 2.3): a small state machine the adapter steps with what it
	senses, which answers with where the Companion goes. Moving it there is
	the adapter's (src/server/CharacterHost).

	  idle    stands where it is; while following, sets off once Amy is
	          further than FOLLOW_FROM
	  follow  goes to Amy, walking, running while she is further than
	          RUN_FROM; stands again within STOP_AT of her
	  react   stands and reacts (a bark, a look) for a while, then goes
	          back to what it was doing
	  lead    goes ahead to a Spot, waiting while Amy is further behind
	          than WAIT_FOR; stands once it is within ARRIVE_AT of the Spot
]]

local Companion = {}

export type State = "idle" | "follow" | "react" | "lead"
export type Gait = "walk" | "run"

export type Companion = {
	state: State,
	-- whether it follows Amy when it has nothing else to do
	following: boolean,
	-- the Spot it leads Amy to
	spot: string?,
	-- seconds of its reaction left
	reacting: number,
	-- the state a reaction goes back to
	after: State,
}

-- What the adapter senses each step, in studs: how far the Companion is
-- from Amy, and from the Spot it leads to.
export type Sense = { toAmy: number, toSpot: number? }

-- Where the Companion goes this step.
export type Move = { kind: "stay" } | { kind: "toAmy", gait: Gait } | { kind: "toSpot", spot: string, gait: Gait }

Companion.FOLLOW_FROM = 10
Companion.STOP_AT = 5
Companion.RUN_FROM = 18
Companion.WAIT_FOR = 16
Companion.ARRIVE_AT = 2

local STAY: Move = table.freeze({ kind = "stay" }) :: any

function Companion.new(following: boolean?): Companion
	return { state = "idle", following = following == true, spot = nil, reacting = 0, after = "idle" }
end

-- Starts or stops following Amy. A Companion that stops stands where it is.
function Companion.follow(companion: Companion, on: boolean)
	companion.following = on
	if not on and companion.state == "follow" then
		companion.state = "idle"
	end
	if not on and companion.after == "follow" then
		companion.after = "idle"
	end
end

-- Reacts for `seconds`, then goes back to what it was doing.
function Companion.react(companion: Companion, seconds: number)
	if companion.state ~= "react" then
		companion.after = companion.state
	end
	companion.state = "react"
	companion.reacting = seconds
end

-- Leads Amy to `spot`.
function Companion.lead(companion: Companion, spot: string)
	companion.state = "lead"
	companion.spot = spot
end

-- Steps `companion` on by `seconds` with what the adapter senses, in place,
-- and says where it goes.
function Companion.step(companion: Companion, seconds: number, sense: Sense): Move
	if companion.state == "react" then
		companion.reacting = math.max(0, companion.reacting - seconds)
		if companion.reacting > 0 then
			return STAY
		end
		companion.state = companion.after
	end
	if companion.state == "lead" then
		local spot = assert(companion.spot, "a leading Companion has a Spot")
		if (sense.toSpot or math.huge) > Companion.ARRIVE_AT then
			return if sense.toAmy > Companion.WAIT_FOR then STAY else { kind = "toSpot", spot = spot, gait = "walk" }
		end
		companion.state = "idle"
		companion.spot = nil
	end
	if companion.state == "idle" then
		if not companion.following or sense.toAmy <= Companion.FOLLOW_FROM then
			return STAY
		end
		companion.state = "follow"
	end
	-- following
	if sense.toAmy <= Companion.STOP_AT then
		companion.state = "idle"
		return STAY
	end
	return { kind = "toAmy", gait = if sense.toAmy > Companion.RUN_FROM then "run" else "walk" }
end

return Companion
