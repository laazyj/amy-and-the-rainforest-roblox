--[[
	CameraModel: Amy's face is never seen. Over many random input sequences
	and starting poses, every Frame keeps the camera rule
	(unit(camera − Amy) · (−facing) ≥ 0.5) with the model's margin; spawn
	and respawn start inside the cone on the first frame; the player turns
	the view and Amy turns with it.
]]

local CameraModel = require("../../../src/core/CameraModel")
local Shot = require("../../../src/core/Shot")
local Story = require("../../../src/core/Story")
local Walker = require("./walker")

type Vec3 = Story.Vec3

-- A deterministic stream of numbers in [0, 1), so a failure replays.
local function random(seed: number): () -> number
	local state = seed
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

local function between(rng: () -> number, low: number, high: number): number
	return low + (high - low) * rng()
end

local function direction(rng: () -> number): Vec3
	local yaw = between(rng, -math.pi, math.pi)
	return { x = math.sin(yaw), y = 0, z = math.cos(yaw) }
end

-- Fails with the step when a Frame breaks the rule or leaves the clamp's cone.
local function holds(frame: CameraModel.Frame, amy: Vec3, where: string)
	local cosine = CameraModel.cosine(frame, amy)
	-- CLAMP_COSINE is above the rule's RULE_COSINE (0.5): the margin
	if cosine < CameraModel.CLAMP_COSINE - 1e-9 then
		error(
			`{where}: unit(camera − Amy) · (−facing) is {cosine}, the rule needs ≥ {CameraModel.RULE_COSINE} with the margin`
		)
	end
end

-- Every Shot as a FrameShot frames it, with each shot:MeetCharacter row,
-- and one animal with no row yet (Sam).
local FRAMINGS: { CameraModel.Framing } = {
	{ shot = "Dialogue", character = "Dad" },
	{ shot = "ForestWallReveal" },
	{ shot = "MeetCharacter", character = "Squirrel" },
	{ shot = "MeetCharacter", character = "Fox" },
	{ shot = "MeetCharacter", character = "Lion" },
	{ shot = "MeetCharacter", character = "Sam" },
	{ shot = "MachineFinale" },
}

local named = Walker.shot

-- A subject `rng` places round Amy: ahead, beside or behind her, near or far.
local function placeSubject(rng: () -> number, amy: Vec3, framing: CameraModel.Framing): Vec3
	local away = direction(rng)
	local far = if framing.shot == "Dialogue" or framing.shot == "MeetCharacter"
		then between(rng, 3, 12)
		else between(rng, 10, 60)
	return { x = amy.x + away.x * far, y = amy.y + between(rng, -2.5, 3), z = amy.z + away.z * far }
end

local SAMPLE = 0.1

-- A subject that stays at `point`.
local function always(point: Vec3): CameraModel.Subject
	return function()
		return point
	end
end

local function apart(a: Vec3, b: Vec3): number
	return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z)
end

local function sub(a: Vec3, b: Vec3): Vec3
	return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

local function dot(a: Vec3, b: Vec3): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end

local function unit(a: Vec3): Vec3
	local length = math.sqrt(dot(a, a))
	return { x = a.x / length, y = a.y / length, z = a.z / length }
end

local function angleBetween(a: Vec3, b: Vec3): number
	return math.acos(math.clamp(dot(a, b), -1, 1))
end

-- Where `point` lands in a viewport (0 to 1 across and down) seen from
-- `frame`'s camera, with Roblox's default vertical field of view of 70°.
local FIELD_OF_VIEW = math.rad(70)
local function project(frame: CameraModel.Frame, point: Vec3, aspect: number): (number, number)
	local forward = unit(sub(frame.lookAt, frame.camera))
	local right = unit({ x = -forward.z, y = 0, z = forward.x })
	local up = { -- right × forward
		x = right.y * forward.z - right.z * forward.y,
		y = right.z * forward.x - right.x * forward.z,
		z = right.x * forward.y - right.y * forward.x,
	}
	local d = sub(point, frame.camera)
	local depth = dot(d, forward)
	local half = math.tan(FIELD_OF_VIEW / 2)
	return 0.5 + dot(d, right) / (depth * half * aspect) / 2, 0.5 - dot(d, up) / (depth * half) / 2
end
-- a step that adds up to whole seconds exactly
local TICK = 1 / 32

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("CameraModel's camera rule", function()
		it("starts inside the cone on the first frame at spawn, for any facing", function()
			local rng = random(11)
			for i = 1, 500 do
				local facing = direction(rng)
				local amy = { x = between(rng, -200, 200), y = between(rng, 0, 10), z = between(rng, -200, 400) }
				local frame = CameraModel.step(CameraModel.new(facing), 1 / 60, amy)
				holds(frame, amy, `spawn {i}`)
				expect(math.abs(frame.facing.x - facing.x) + math.abs(frame.facing.z - facing.z) < 1e-9).toBe(true)
			end
		end)

		it("starts inside the cone on the first frame after a respawn or a TeleportPlayer", function()
			local rng = random(12)
			local camera = CameraModel.new({ x = 0, y = 0, z = 1 })
			for i = 1, 500 do
				CameraModel.turn(camera, between(rng, -4, 4), between(rng, -2, 2))
				local facing = direction(rng)
				CameraModel.place(camera, facing)
				local amy = { x = between(rng, -200, 200), y = 3, z = between(rng, -200, 400) }
				local frame = CameraModel.step(camera, 1 / 60, amy)
				holds(frame, amy, `respawn {i}`)
				expect(math.abs(frame.facing.x - facing.x) + math.abs(frame.facing.z - facing.z) < 1e-9).toBe(true)
			end
		end)

		it("holds with the margin at every step of 300 random input sequences", function()
			local rng = random(2026)
			for sequence = 1, 300 do
				local camera = CameraModel.new(direction(rng))
				local amy = { x = between(rng, -100, 100), y = 3, z = between(rng, -100, 300) }
				for step = 1, 200 do
					local roll = rng()
					if roll < 0.6 then
						-- mouse look or a touch drag, up to a wild flick
						CameraModel.turn(camera, between(rng, -3, 3), between(rng, -1.5, 1.5))
					elseif roll < 0.62 then
						CameraModel.place(camera, direction(rng))
					end
					amy = { x = amy.x + between(rng, -1, 1), y = between(rng, 0, 8), z = amy.z + between(rng, -1, 1) }
					holds(
						CameraModel.step(camera, between(rng, 1 / 240, 1 / 15), amy),
						amy,
						`sequence {sequence} step {step}`
					)
				end
			end
		end)

		it("holds when the player tilts the view as far up or down as it goes", function()
			local amy = { x = 0, y = 3, z = 0 }
			local camera = CameraModel.new({ x = 0, y = 0, z = 1 })
			for _ = 1, 50 do
				CameraModel.turn(camera, 0, 0.5)
				holds(CameraModel.step(camera, 1 / 60, amy), amy, "tilted up")
			end
			for _ = 1, 100 do
				CameraModel.turn(camera, 0, -0.5)
				holds(CameraModel.step(camera, 1 / 60, amy), amy, "tilted down")
			end
			expect(camera.pitch).toBe(CameraModel.MIN_PITCH)
		end)
	end)

	describe("the follow camera", function()
		it("turns Amy with the view, as with shift-lock: no free look round to her front", function()
			local camera = CameraModel.new({ x = 0, y = 0, z = 1 })
			local amy = { x = 0, y = 3, z = 0 }
			for _ = 1, 8 do
				CameraModel.turn(camera, math.pi / 4, 0)
				local frame = CameraModel.step(camera, 1 / 60, amy)
				expect(CameraModel.yawOf(frame.facing)).toBe(camera.yaw)
				expect(CameraModel.cosine(frame, amy) > 0.9).toBe(true)
			end
		end)

		it("follows from behind and above, looking ahead of Amy", function()
			local amy = { x = 10, y = 3, z = 20 }
			local frame = CameraModel.step(CameraModel.new({ x = 0, y = 0, z = 1 }), 1 / 60, amy)
			expect(frame.camera.z < amy.z).toBe(true)
			expect(frame.camera.y > amy.y).toBe(true)
			expect(frame.lookAt.z > amy.z).toBe(true)
		end)
	end)

	describe("turning", function()
		it("turns Amy's facing by exactly the turn the player makes", function()
			for _, theta in { 0.3, -0.3, 1, -2, math.rad(170) } do
				local camera = CameraModel.new({ x = 0, y = 0, z = 1 })
				local amy = { x = 0, y = 3, z = 0 }
				local before = CameraModel.step(camera, 1 / 60, amy).facing
				CameraModel.turn(camera, theta, 0)
				local after = CameraModel.step(camera, 1 / 60, amy).facing
				expect(math.abs(angleBetween(before, after) - math.abs(theta)) < 1e-9).toBe(true)
				-- a positive turn is to her left: facing +z, left is +x
				expect(math.sign(after.x)).toBe(math.sign(theta))
			end
		end)

		it("turns Amy and the view with the turn keys: A or Left to her left, D or Right to her right", function()
			local speed = CameraModel.KEY_TURN_SPEED
			expect(CameraModel.keyTurn({ A = true }, 0.5)).toBe(speed * 0.5)
			expect(CameraModel.keyTurn({ Left = true }, 0.5)).toBe(speed * 0.5)
			expect(CameraModel.keyTurn({ D = true }, 0.25)).toBe(-speed * 0.25)
			expect(CameraModel.keyTurn({ Right = true, D = true }, 0.25)).toBe(-speed * 0.25)
			expect(CameraModel.keyTurn({ A = true, D = true }, 1)).toBe(0)
			expect(CameraModel.keyTurn({ W = true, S = true, Up = true, Down = true }, 1)).toBe(0)
		end)
	end)

	describe("CameraModel.observe", function()
		it("puts the camera behind Amy when the server turns her (TeleportPlayer), ending any Shot", function()
			local camera = CameraModel.new({ x = 0, y = 0, z = 1 })
			local amy = { x = 0, y = 3, z = 0 }
			CameraModel.frameShot(camera, "Dialogue", "Dad")
			CameraModel.step(camera, SAMPLE, amy, always({ x = 0, y = 5, z = 8 }))
			CameraModel.observe(camera, { x = 0, y = 0, z = -1 })
			local frame = CameraModel.step(camera, SAMPLE, amy, always({ x = 0, y = 5, z = 8 }))
			expect(frame.shot).toBeNil()
			expect(frame.facing.z).toBe(-1)
			holds(frame, amy, "after the teleport")
		end)

		it("leaves the camera alone while Amy faces the way the last Frame turned her", function()
			local camera = CameraModel.new({ x = 0, y = 0, z = 1 })
			local amy = { x = 0, y = 3, z = 0 }
			CameraModel.turn(camera, 0.5, 0)
			local frame = CameraModel.step(camera, SAMPLE, amy)
			CameraModel.observe(camera, frame.facing)
			expect(CameraModel.step(camera, SAMPLE, amy).facing).toEqual(frame.facing)
		end)
	end)

	describe("CameraModel.pullIn", function()
		it("pulls the camera in at once, and eases it back out over 0.3 s", function()
			expect(CameraModel.pullIn(1, 0.25, 1 / 60)).toBe(0.25)
			local reach = 0.25
			for _ = 1, 9 do
				reach = CameraModel.pullIn(reach, 1, 1 / 60)
			end
			expect(reach > 0.25 and reach < 1).toBe(true) -- 0.15 s out: on its way
			for _ = 1, 9 do
				reach = CameraModel.pullIn(reach, 1, 1 / 60)
			end
			expect(reach).toBe(1)
			expect(CameraModel.pullIn(0.5, 0.75, 1)).toBe(0.75) -- never past what is clear
		end)
	end)

	describe("CameraModel.turnsView", function()
		it("turns the view for a touch anywhere but the thumbstick's and the talk button's zones", function()
			local width, height = 844, 390
			expect(CameraModel.turnsView(422, 100, width, height)).toBe(true) -- the middle
			expect(CameraModel.turnsView(50, 50, width, height)).toBe(true) -- top left
			expect(CameraModel.turnsView(422, 380, width, height)).toBe(true) -- bottom middle
			expect(CameraModel.turnsView(100, 350, width, height)).toBe(false) -- the thumbstick
			expect(CameraModel.turnsView(800, 350, width, height)).toBe(false) -- the talk button
		end)
	end)

	describe("CameraModel.clamp", function()
		local function rig(azimuth: number, elevation: number): CameraModel.Rig
			return { yaw = 0, azimuth = azimuth, elevation = elevation, distance = 10, lookAt = { x = 0, y = 0, z = 0 } }
		end

		it("leaves a Rig inside the cone as it is", function()
			local inside = rig(math.rad(30), math.rad(20))
			expect(CameraModel.clamp(inside)).toBe(inside)
		end)

		it("pulls a Rig in front of Amy or above her back to the edge of the cone, never across", function()
			for _, outside in { rig(math.pi, 0), rig(math.rad(80), 0), rig(0, math.rad(85)), rig(-2, -1) } do
				local clamped = CameraModel.clamp(outside)
				local cosine = math.cos(clamped.azimuth) * math.cos(clamped.elevation)
				expect(math.abs(cosine - CameraModel.CLAMP_COSINE) < 1e-6).toBe(true)
				expect(clamped.distance).toBe(outside.distance)
			end
		end)
	end)

	describe("the Shots", function()
		it("has a path for every Shot, and none other", function()
			for _, name in Shot.NAMES do
				expect(CameraModel.PATHS[name]).never.toBeNil()
			end
			for name in CameraModel.PATHS do
				expect(table.find(Shot.NAMES, name)).never.toBeNil()
			end
		end)

		for _, framing in FRAMINGS do
			local name = named(framing)

			it(`frames {name} from behind Amy by its own path: inside the cone every {SAMPLE} s`, function()
				local rng = random(#name)
				local path = CameraModel.PATHS[framing.shot]
				for pose = 1, 100 do
					local amy = { x = between(rng, -50, 50), y = 3, z = between(rng, -50, 300) }
					local subject = placeSubject(rng, amy, framing)
					local heading = CameraModel.yawOf({ x = subject.x - amy.x, y = 0, z = subject.z - amy.z }) or 0
					local scene = { amy = amy, subject = subject, heading = heading, character = framing.character }
					for i = 0, 100 do
						local rig = path(scene, i * SAMPLE)
						local cosine = math.cos(rig.azimuth) * math.cos(rig.elevation)
						if cosine < CameraModel.CLAMP_COSINE then
							error(`pose {pose} at {i * SAMPLE} s: the path leaves the cone ({cosine})`)
						end
					end
				end
			end)

			it(`plays {name} from any follow camera with the camera rule at every {SAMPLE} s`, function()
				local rng = random(100 + #name)
				for pose = 1, 100 do
					local camera = CameraModel.new(direction(rng))
					CameraModel.turn(camera, 0, between(rng, -1, 1))
					local amy = { x = between(rng, -50, 50), y = 3, z = between(rng, -50, 300) }
					local subject = placeSubject(rng, amy, framing)
					local find = always(subject)
					CameraModel.frameShot(camera, framing.shot, framing.character)
					for i = 1, 100 do
						if i == 60 then
							CameraModel.dialogueFinished(camera)
						end
						holds(CameraModel.step(camera, SAMPLE, amy, find), amy, `pose {pose} at {i * SAMPLE} s`)
					end
				end
			end)
		end

		for name, hold in Shot.HOLD do
			local seconds = Shot.EASE_IN + hold
			it(`eases {name} in, holds it {hold} s, and hands back to the follow camera over 0.5 s`, function()
				local camera = CameraModel.new({ x = 0, y = 0, z = 1 })
				local amy = { x = 0, y = 3, z = 0 }
				local subject = { x = 0, y = 4, z = 20 } -- ahead of Amy: a short swing
				local find = always(subject)
				CameraModel.frameShot(camera, name, "Squirrel")
				-- how long the Shot is framed, from its first frame
				local framed, frame = 0, CameraModel.step(camera, TICK, amy, find)
				while frame.shot == name and framed < 10 do
					frame = CameraModel.step(camera, TICK, amy, find)
					framed += TICK
				end
				expect(framed).toBe(seconds)
				expect(frame.settled).toBeNil()
				-- Amy faces the subject, and the follow camera goes behind her there
				expect(math.abs(frame.facing.z - 1) < 1e-6).toBe(true)
				local behind = CameraModel.step(CameraModel.new({ x = 0, y = 0, z = 1 }), 0, amy)
				for _ = 1, Shot.HAND_BACK / TICK - 1 do
					frame = CameraModel.step(camera, TICK, amy, find)
				end
				expect(apart(frame.camera, behind.camera) > 1e-3).toBe(true) -- a tick short of 0.5 s: still returning
				frame = CameraModel.step(camera, TICK, amy, find)
				expect(apart(frame.camera, behind.camera) < 1e-6).toBe(true)
				expect(apart(frame.lookAt, behind.lookAt) < 1e-6).toBe(true)
			end)
		end

		it("reaches each timed Shot's framed hold even from behind Amy, and ends it within 4 s", function()
			local rng = random(44)
			for _, framing in FRAMINGS do
				if Shot.HOLD[framing.shot] then
					for pose = 1, 100 do
						local camera = CameraModel.new(direction(rng))
						CameraModel.turn(camera, 0, between(rng, -1, 1))
						local amy = { x = 0, y = 3, z = 0 }
						local find = always(placeSubject(rng, amy, framing))
						CameraModel.frameShot(camera, framing.shot, framing.character)
						local framed, held, frame = 0, 0, CameraModel.step(camera, TICK, amy, find)
						while frame.shot do
							if frame.settled then
								held += TICK
							end
							frame = CameraModel.step(camera, TICK, amy, find)
							framed += TICK
						end
						if held < 0.25 or framed > Shot.LONGEST then
							error(`{named(framing)} pose {pose}: framed {framed} s, held {held} s`)
						end
					end
				end
			end
		end)

		it("holds a held Shot until DialogueFinished, then hands back over 0.5 s", function()
			local camera = CameraModel.new({ x = 0, y = 0, z = 1 })
			local amy = { x = 0, y = 3, z = 0 }
			local find = always({ x = 5, y = 6, z = 8 })
			CameraModel.frameShot(camera, "Dialogue", "Dad")
			for _ = 1, 600 do
				expect(CameraModel.step(camera, SAMPLE, amy, find).shot).toBe("Dialogue")
			end
			CameraModel.dialogueFinished(camera)
			expect(CameraModel.step(camera, SAMPLE, amy, find).shot).toBeNil()
		end)

		it("plays shot:MeetCharacter, then the shot:Dialogue framed after it", function()
			local camera = CameraModel.new({ x = 0, y = 0, z = 1 })
			local amy = { x = 0, y = 3, z = 0 }
			local find = always({ x = 0, y = 2, z = 8 })
			CameraModel.frameShot(camera, "MeetCharacter", "Fox")
			CameraModel.frameShot(camera, "Dialogue", "Fox")
			local shots = {}
			for _ = 1, 60 do
				local shot = CameraModel.step(camera, SAMPLE, amy, find).shot
				if shot ~= shots[#shots] then
					table.insert(shots, shot)
				end
			end
			expect(shots).toEqual({ "MeetCharacter", "Dialogue" })
			expect(CameraModel.step(camera, 0, amy, find).character).toBe("Fox")
		end)

		it(
			"never makes the player wait: a Dialogue finished during shot:MeetCharacter drops its shot:Dialogue",
			function()
				local camera = CameraModel.new({ x = 0, y = 0, z = 1 })
				local amy = { x = 0, y = 3, z = 0 }
				local find = always({ x = 0, y = 2, z = 8 })
				CameraModel.frameShot(camera, "MeetCharacter", "Fox")
				CameraModel.frameShot(camera, "Dialogue", "Fox")
				CameraModel.step(camera, SAMPLE, amy, find)
				CameraModel.dialogueFinished(camera)
				for _ = 1, 50 do
					expect(CameraModel.step(camera, SAMPLE, amy, find).shot ~= "Dialogue").toBe(true)
				end
			end
		)

		it("skips a Shot whose subject cannot be found, and ends one whose subject leaves", function()
			local camera = CameraModel.new({ x = 0, y = 0, z = 1 })
			local amy = { x = 0, y = 3, z = 0 }
			CameraModel.frameShot(camera, "Dialogue", "Mum")
			expect(CameraModel.step(camera, SAMPLE, amy, function()
				return nil
			end).shot).toBeNil()
			local here: Vec3? = { x = 3, y = 5, z = 6 }
			local function find()
				return here
			end
			CameraModel.frameShot(camera, "Dialogue", "Mum")
			expect(CameraModel.step(camera, SAMPLE, amy, find).shot).toBe("Dialogue")
			here = nil
			expect(CameraModel.step(camera, SAMPLE, amy, find).shot).toBeNil()
		end)

		it("ends every Shot on a respawn or a TeleportPlayer", function()
			local camera = CameraModel.new({ x = 0, y = 0, z = 1 })
			local find = always({ x = 3, y = 5, z = 6 })
			CameraModel.frameShot(camera, "MachineFinale")
			CameraModel.frameShot(camera, "Dialogue", "Dad")
			CameraModel.step(camera, SAMPLE, { x = 0, y = 3, z = 0 }, find)
			CameraModel.place(camera, { x = -1, y = 0, z = 0 })
			local frame = CameraModel.step(camera, SAMPLE, { x = 0, y = 3, z = 0 }, find)
			expect(frame.shot).toBeNil()
			expect(frame.facing.x).toBe(-1)
		end)

		it("clamps a Shot path that would leave the cone, in the Frame step returns", function()
			local paths: any = CameraModel.PATHS
			paths.InFrontOfAmy = function(scene)
				return { yaw = scene.heading, azimuth = math.pi, elevation = 0, distance = 9, lookAt = scene.amy }
			end
			local ok, failure = pcall(function()
				local camera = CameraModel.new({ x = 0, y = 0, z = 1 })
				local amy = { x = 0, y = 3, z = 0 }
				CameraModel.frameShot(camera, "InFrontOfAmy")
				local frame
				for _ = 1, 30 do
					frame = CameraModel.step(camera, SAMPLE, amy, always({ x = 0, y = 3, z = 10 }))
					holds(frame, amy, "a path in front of Amy")
				end
				expect(math.abs(CameraModel.cosine(frame, amy) - CameraModel.CLAMP_COSINE) < 1e-6).toBe(true)
			end)
			paths.InFrontOfAmy = nil
			assert(ok, failure)
		end)

		it("never swings the camera or Amy round faster than Shot.TURN_SPEED while a Shot plays", function()
			local rng = random(120)
			local function towardCamera(frame: CameraModel.Frame, amy: Vec3): Vec3
				return unit(sub(frame.camera, amy))
			end
			local dt = 1 / 120
			local peak = 0
			for _, framing in FRAMINGS do
				for _ = 1, 40 do
					local camera = CameraModel.new(direction(rng))
					local amy = { x = 0, y = 3, z = 0 }
					local subject = placeSubject(rng, amy, framing) -- often behind her
					CameraModel.frameShot(camera, framing.shot, framing.character)
					local last = CameraModel.step(camera, 0, amy, always(subject))
					for _ = 1, 6 / dt do
						local frame = CameraModel.step(camera, dt, amy, always(subject))
						if not frame.shot then
							break
						end
						local speed = math.max(
							angleBetween(towardCamera(last, amy), towardCamera(frame, amy)),
							angleBetween(last.facing, frame.facing)
						) / dt
						peak = math.max(peak, speed)
						last = frame
					end
				end
			end
			print(`  peak Shot turn: {string.format("%.0f", math.deg(peak))}°/s`)
			expect(peak <= Shot.TURN_SPEED * 1.02).toBe(true)
		end)

		it("refuses a Shot the glossary does not name", function()
			t.expectError(function()
				CameraModel.frameShot(CameraModel.new({ x = 0, y = 0, z = 1 }), "Orbit")
			end, "no Shot Orbit")
		end)

		it("holds the camera rule with the margin through 300 random sequences of Shots, turns and respawns", function()
			local rng = random(7)
			for sequence = 1, 300 do
				local camera = CameraModel.new(direction(rng))
				local amy = { x = between(rng, -100, 100), y = 3, z = between(rng, -100, 300) }
				local subjects: { [string]: Vec3? } = {}
				local function find(framing: CameraModel.Framing): Vec3?
					return subjects[named(framing)]
				end
				for step = 1, 200 do
					local roll = rng()
					if roll < 0.05 then
						local framing = FRAMINGS[math.floor(rng() * #FRAMINGS) + 1]
						subjects[named(framing)] = if rng() < 0.9 then placeSubject(rng, amy, framing) else nil
						CameraModel.frameShot(camera, framing.shot, framing.character)
					elseif roll < 0.08 then
						CameraModel.dialogueFinished(camera)
					elseif roll < 0.09 then
						CameraModel.place(camera, direction(rng))
					elseif roll < 0.6 then
						CameraModel.turn(camera, between(rng, -3, 3), between(rng, -1.5, 1.5))
					end
					amy = { x = amy.x + between(rng, -1, 1), y = between(rng, 0, 8), z = amy.z + between(rng, -1, 1) }
					local frame = CameraModel.step(camera, between(rng, 1 / 240, 1 / 15), amy, find)
					holds(frame, amy, `sequence {sequence} step {step} ({frame.shot or "follow"})`)
				end
			end
		end)

		-- feel.md: the speaker's projected head point inside x 0.33-0.67 and
		-- y 0.15-0.5, so the Dialogue box (bottom) and the Objective tracker
		-- (top right) never cover it. Head heights above the ground are those
		-- src/server/CharacterHost builds; Amy's root stands 3.5 above it
		-- (src/server/WorldImpl) and talks within the prompt's 10 studs.
		local HEADS: { [string]: number } = { Dad = 5.9, Mum = 5.9, Sam = 3.5, Squirrel = 2.2, Fox = 3.1, Lion = 5 }
		local VIEWPORTS: { [string]: number } = {
			["phone landscape"] = 844 / 390,
			["phone portrait"] = 390 / 844,
			["tablet landscape"] = 1376 / 1032,
			["tablet portrait"] = 1032 / 1376,
			["PC"] = 1280 / 720,
		}
		it("puts the speaker's head inside x 0.33-0.67, y 0.15-0.5 in shot:Dialogue, on every device class", function()
			local rng = random(33)
			for character, height in HEADS do
				for _ = 1, 200 do
					local ground = { x = between(rng, -50, 50), y = 0, z = between(rng, -50, 300) }
					local head = { x = ground.x, y = height, z = ground.z }
					local away = direction(rng)
					local reach = between(rng, 3, 10)
					local amy = { x = ground.x + away.x * reach, y = 3.5, z = ground.z + away.z * reach }
					local camera = CameraModel.new(direction(rng))
					CameraModel.frameShot(camera, "Dialogue", character)
					local frame
					for _ = 1, 50 do -- eased in (at most 4.5 s when Amy turns round); then still
						frame = CameraModel.step(camera, SAMPLE, amy, always(head))
					end
					for device, aspect in VIEWPORTS do
						local x, y = project(frame, head, aspect)
						if x < 0.33 or x > 0.67 or y < 0.15 or y > 0.5 then
							error(`{character}, Amy {reach} studs away, {device}: head at ({x}, {y})`)
						end
					end
				end
			end
		end)
	end)
end
