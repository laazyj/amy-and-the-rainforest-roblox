--[[
	CameraModel: Amy's face is never seen. Over many random input sequences
	and starting poses, every Frame keeps the camera rule
	(unit(camera − Amy) · (−facing) ≥ 0.5) with the model's margin; spawn
	and respawn start inside the cone on the first frame; the player turns
	the view and Amy turns with it.
]]

local CameraModel = require("../../../src/core/CameraModel")
local Story = require("../../../src/core/Story")

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
end
