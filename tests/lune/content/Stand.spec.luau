--[[
	Where the Characters stand, walked as a player would
	(tests/lune/core/walker.luau):

	  * every Character faces Amy as it speaks: its Spot's facing is within
	    60° of the way to her (the camera rule's cone, cosine ≥ 0.5). Amy is
	    in a `reach` Quest's Zone once she has entered it; talking to a
	    Character, she has walked up to it from where the Quest before left
	    her, so it faces that way; and she stays beside it until the next
	    Quest moves her on (a TeleportPlayer puts her at its Spot).
	  * a Beat gives every run its time: the Waits after it, before Amy is
	    teleported or the Beat ends, are at least Story.runSeconds of the
	    run, so the whole run is seen.
	  * a run through the garden gate keeps clear of its posts.
]]

local CameraModel = require("../../../src/core/CameraModel")
local Events = require("../../../src/core/Events")
local Garden = require("../../../src/content/scenes/Garden")
local Story = require("../../../src/content/Story")
local StoryTypes = require("../../../src/core/Story")
local Walker = require("../core/walker")
local WorldState = require("../../../src/core/WorldState")

local story = Story.story

-- half of Sam's width, his Placeholder's ears included (2.4 across), and
-- room to spare: a run through the gate keeps this far from a post
local HALF_WIDTH, SPARE = 1.2, 0.2

type Point = { x: number, z: number }

local function point(at: StoryTypes.Vec3): Point
	return { x = at.x, z = at.z }
end

local function spotAt(id: string): Point
	return point(assert(story.spots[id], id).at)
end

-- The way from `from` to `to` across the ground, and how far.
local function across(from: Point, to: Point): (number, number, number)
	local dx, dz = to.x - from.x, to.z - from.z
	return dx, dz, math.sqrt(dx * dx + dz * dz)
end

-- Every Line a Character speaks, with where it stands and where Amy is;
-- and every run in a Beat, with the Waits after it.
type Spoken = { where: string, speaker: string, spot: string, amy: Point }
type Run = { where: string, character: string, from: Point, to: Point, waited: number }

local spoken: { Spoken } = {}
-- the Characters by the name a shown Line gives its Speaker
local byDisplay: { [string]: string } = {}
for _, character in story.characters do
	byDisplay[character.display] = character.id
end
local runs: { Run } = {}

do
	local walk = Walker.walk(story)
	local state = WorldState.initial(story)
	local amy = spotAt("AmySpawn")
	-- the Character Amy talks with, and where she walked up to it from
	local talking: string?, cameFrom: Point = nil, amy
	-- the Quest active as each step is played, and each Character already
	-- held to the rule there
	local quest: string?, held: { [string]: true } = nil, {}

	for _, step in walk.steps do
		local event: any = step.event
		local kind = event and event.kind
		if kind == "EnteredZone" then
			amy, talking = point(story.zones[event.zone].centre), nil
		elseif kind == "TalkedTo" then
			talking, cameFrom = event.character, amy
			amy = spotAt(state.characters[event.character])
		elseif kind == "TouchedPickup" then
			amy, talking = spotAt(event.pickup), nil
		end
		local where = if quest then `in {quest}` else "in the Ending"
		local open: { Run } = {}
		for _, command in step.commands do
			if command.kind == "MoveCharacter" and command.run then
				local run = {
					where = where,
					character = command.character,
					from = spotAt(state.characters[command.character]),
					to = spotAt(command.spot),
					waited = 0,
				}
				table.insert(runs, run)
				table.insert(open, run)
			elseif command.kind == "Wait" then
				for _, run in open do
					run.waited += command.seconds
				end
			elseif command.kind == "TeleportPlayer" then
				open = {}
				amy, talking = spotAt(command.spot), nil
			end
			WorldState.apply(story, state, command)
			if command.kind == "ShowDialogue" then
				for _, line in (command :: any).lines :: { Events.ShownLine } do
					local speaker = byDisplay[line.speaker]
					local spot = speaker and state.characters[speaker]
					local key = `{where} {speaker}`
					if spot and not held[key] then
						held[key] = true
						table.insert(spoken, {
							where = where,
							speaker = speaker,
							spot = spot,
							amy = if speaker == talking then cameFrom else amy,
						})
					end
				end
			end
		end
		quest = step.quest
	end
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("where the Characters stand", function()
		it("has Characters speak, and a run, to hold to the rules", function()
			expect(#spoken > 0).toBe(true)
			expect(#runs > 0).toBe(true)
		end)

		for _, line in spoken do
			it(`has character:{line.speaker} at spot:{line.spot} face Amy as it speaks, {line.where}`, function()
				local spot = story.spots[line.spot]
				local dx, dz, length = across(point(spot.at), line.amy)
				local cosine = if length > 0 then (dx * spot.facing.x + dz * spot.facing.z) / length else 1
				-- the camera rule's cone: within 60° of the way to her
				if cosine < CameraModel.RULE_COSINE then
					error(
						`spot:{line.spot} faces ({spot.facing.x}, {spot.facing.z}); Amy is at ({line.amy.x}, {line.amy.z}): cosine {cosine}, needs ≥ {CameraModel.RULE_COSINE}`
					)
				end
			end)
		end

		for _, run in runs do
			it(`gives character:{run.character}'s run its time before Amy is teleported, {run.where}`, function()
				local _, _, distance = across(run.from, run.to)
				local needs = StoryTypes.runSeconds(distance)
				if run.waited < needs then
					error(`the run is given {needs} s; the Beat waits {run.waited} s`)
				end
				-- brief 014: the chase adds at most its own length to the Beat
				expect(run.waited <= StoryTypes.RUN.limit).toBe(true)
			end)

			it(`keeps character:{run.character}'s run clear of the garden gate's posts, {run.where}`, function()
				local fence = Garden.fence
				local inner = fence.gateHalfWidth - fence.post / 2
				-- the run's line, across the posts' depth
				for _, z in { fence.frontZ - fence.post / 2, fence.frontZ, fence.frontZ + fence.post / 2 } do
					local share = (z - run.from.z) / (run.to.z - run.from.z)
					if share >= 0 and share <= 1 then
						local x = run.from.x + share * (run.to.x - run.from.x)
						if math.abs(x) + HALF_WIDTH + SPARE > inner then
							error(`at z {z} the run is at x {x}; it must stay within {inner - HALF_WIDTH - SPARE}`)
						end
					end
				end
			end)
		end
	end)
end
