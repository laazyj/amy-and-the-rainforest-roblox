--!strict
--[[
	CameraModel: the locked-behind camera as plain data (docs/design/feel.md,
	"Invariants"). Given where Amy stands, the player's turn input and the
	time passing, it says where the camera is, what it looks at and which
	way Amy faces. src/client/Camera.luau is the adapter that turns a Frame
	into a CFrame and Amy's root.

	The camera rule: unit(camera − Amy) · (−facing) ≥ 0.5, the camera within
	60° of directly behind her, so her face is never seen. The model keeps
	every Frame inside a tighter cone (CLAMP_DEGREES), so the rule holds with
	a margin at every frame.

	A camera placement is a Rig, relative to Amy: the way she faces (yaw),
	and the camera's azimuth and elevation away from directly behind her,
	its distance, and the point it looks at. In a Rig the rule reads
	cos(azimuth) · cos(elevation) ≥ 0.5, and the set of placements that keep
	it is convex in (azimuth, elevation), so blending two Rigs that keep it
	keeps it too; `clamp` pulls any Rig back inside the cone, never across.

	The follow camera: Amy faces the way the view faces, as with Roblox's
	shift-lock; the player turns the view (`turn`) and Amy turns with it.
	There is no free look round to her front.
]]

local Story = require("./Story")

type Vec3 = Story.Vec3

export type Rig = {
	-- the way Amy faces: facing = (sin yaw, 0, cos yaw)
	yaw: number,
	-- the camera's angle round from directly behind her, positive over her right shoulder
	azimuth: number,
	-- the camera's angle above (positive) or below her
	elevation: number,
	distance: number,
	lookAt: Vec3,
}

-- What the adapter renders: the camera, the point it looks at, and the
-- way Amy faces, all in world space.
export type Frame = { camera: Vec3, lookAt: Vec3, facing: Vec3 }

export type Camera = {
	-- the follow camera's view: Amy's facing, and how high it looks down on her
	yaw: number,
	pitch: number,
}

local CameraModel = {}

-- The camera rule: the least unit(camera − Amy) · (−facing).
CameraModel.RULE_COSINE = 0.5
-- The cone the model keeps the camera in: 5° inside the rule's 60°.
CameraModel.CLAMP_DEGREES = 55
CameraModel.CLAMP_COSINE = math.cos(math.rad(CameraModel.CLAMP_DEGREES))

-- The follow camera: how far behind Amy, how high it starts and how low it
-- may go, and where it looks (above her root, ahead of her).
CameraModel.FOLLOW_DISTANCE = 13
CameraModel.DEFAULT_PITCH = math.rad(18)
CameraModel.MIN_PITCH = math.rad(-15)
CameraModel.MAX_PITCH = math.rad(CameraModel.CLAMP_DEGREES)
CameraModel.LOOK_HEIGHT = 2
CameraModel.LOOK_AHEAD = 4

local UP: Vec3 = table.freeze({ x = 0, y = 1, z = 0 })

local function v(x: number, y: number, z: number): Vec3
	return { x = x, y = y, z = z }
end

local function add(a: Vec3, b: Vec3, scale: number?): Vec3
	local s = scale or 1
	return v(a.x + b.x * s, a.y + b.y * s, a.z + b.z * s)
end

-- The angle in (−π, π] equal to `angle`.
local function wrap(angle: number): number
	return angle - 2 * math.pi * math.floor((angle + math.pi) / (2 * math.pi))
end

-- The yaw of a direction on the ground; nil for one with no ground part.
function CameraModel.yawOf(direction: Vec3): number?
	if math.abs(direction.x) + math.abs(direction.z) < 1e-6 then
		return nil
	end
	return math.atan2(direction.x, direction.z)
end

function CameraModel.facing(yaw: number): Vec3
	return v(math.sin(yaw), 0, math.cos(yaw))
end

-- unit(camera − Amy) · (−facing): 1 directly behind her, 0.5 at the edge
-- of the camera rule, below 0 in front of her.
function CameraModel.cosine(frame: Frame, amy: Vec3): number
	local d = v(frame.camera.x - amy.x, frame.camera.y - amy.y, frame.camera.z - amy.z)
	local length = math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
	if length < 1e-9 then
		return -1 -- a camera inside Amy shows her from no side at all
	end
	return -(d.x * frame.facing.x + d.y * frame.facing.y + d.z * frame.facing.z) / length
end

-- `rig` pulled back inside the cone the model keeps (CLAMP_DEGREES) along
-- the straight line towards directly behind Amy; unchanged when inside.
function CameraModel.clamp(rig: Rig): Rig
	local azimuth = wrap(rig.azimuth)
	local elevation = math.clamp(rig.elevation, -math.pi / 2, math.pi / 2)
	local cosine = math.cos(azimuth) * math.cos(elevation)
	if cosine >= CameraModel.CLAMP_COSINE then
		return rig
	end
	-- the largest share of the way out that is still inside, by bisection
	local inside, outside = 0, 1
	for _ = 1, 30 do
		local share = (inside + outside) / 2
		if math.cos(azimuth * share) * math.cos(elevation * share) >= CameraModel.CLAMP_COSINE then
			inside = share
		else
			outside = share
		end
	end
	local clamped = table.clone(rig)
	clamped.azimuth = azimuth * inside
	clamped.elevation = elevation * inside
	return clamped
end

-- `a` blended towards `b` by `t` (0 to 1): the shorter way round for yaw.
function CameraModel.blend(a: Rig, b: Rig, t: number): Rig
	return {
		yaw = a.yaw + wrap(b.yaw - a.yaw) * t,
		azimuth = math.lerp(a.azimuth, b.azimuth, t),
		elevation = math.lerp(a.elevation, b.elevation, t),
		distance = math.lerp(a.distance, b.distance, t),
		lookAt = v(
			math.lerp(a.lookAt.x, b.lookAt.x, t),
			math.lerp(a.lookAt.y, b.lookAt.y, t),
			math.lerp(a.lookAt.z, b.lookAt.z, t)
		),
	}
end

-- Where `rig` puts the camera, round Amy standing at `amy`.
function CameraModel.frame(rig: Rig, amy: Vec3): Frame
	local facing = CameraModel.facing(rig.yaw)
	-- her right: facing × up
	local right = v(-facing.z, 0, facing.x)
	local ground = math.cos(rig.elevation) * rig.distance
	local offset = v(
		ground * (-math.cos(rig.azimuth) * facing.x + math.sin(rig.azimuth) * right.x),
		math.sin(rig.elevation) * rig.distance,
		ground * (-math.cos(rig.azimuth) * facing.z + math.sin(rig.azimuth) * right.z)
	)
	return { camera = add(amy, offset), lookAt = rig.lookAt, facing = facing }
end

-- A follow camera behind Amy facing `facing`, as at spawn: inside the
-- cone from its first frame.
function CameraModel.new(facing: Vec3): Camera
	return { yaw = CameraModel.yawOf(facing) or 0, pitch = CameraModel.DEFAULT_PITCH }
end

-- Amy was put somewhere facing `facing` (a respawn, or TeleportPlayer):
-- the follow camera goes behind her there.
function CameraModel.place(camera: Camera, facing: Vec3)
	camera.yaw = CameraModel.yawOf(facing) or camera.yaw
	camera.pitch = CameraModel.DEFAULT_PITCH
end

-- The follow camera's Rig for Amy standing at `amy`.
function CameraModel.follow(camera: Camera, amy: Vec3): Rig
	local lookAt = add(add(amy, UP, CameraModel.LOOK_HEIGHT), CameraModel.facing(camera.yaw), CameraModel.LOOK_AHEAD)
	return {
		yaw = camera.yaw,
		azimuth = 0,
		elevation = camera.pitch,
		distance = CameraModel.FOLLOW_DISTANCE,
		lookAt = lookAt,
	}
end

-- The player turns the view by `yaw` and tilts it by `pitch` (radians);
-- Amy turns with the view. The tilt stops at the edge of the cone, so
-- tilting back down answers at once.
function CameraModel.turn(camera: Camera, yaw: number, pitch: number)
	camera.yaw = wrap(camera.yaw + yaw)
	camera.pitch = math.clamp(camera.pitch + pitch, CameraModel.MIN_PITCH, CameraModel.MAX_PITCH)
end

-- This frame, for Amy standing at `amy`.
function CameraModel.step(camera: Camera, _seconds: number, amy: Vec3): Frame
	return CameraModel.frame(CameraModel.clamp(CameraModel.follow(camera, amy)), amy)
end

return CameraModel
