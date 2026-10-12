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

	Shots (src/core/Shot, feel.md section 2): `frameShot` queues a Shot,
	which takes the camera from the one before it, easing in over 0.5 s,
	and frames its subject from behind Amy, who turns to face it. A held
	Shot lasts until `dialogueFinished`; any other at most 4 s. When the
	last Shot ends, the follow camera returns over 0.5 s. A Shot whose
	subject cannot be found is skipped. Every Shot's Rig goes through the
	same clamp as the follow camera.
]]

local Shot = require("./Shot")
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
-- way Amy faces, all in world space; and the Shot framed, if any.
export type Frame = { camera: Vec3, lookAt: Vec3, facing: Vec3, shot: string? }

-- A FrameShot: the Shot, and the Character it frames when it takes one.
export type Framing = { shot: string, character: string? }

-- Where a Shot's subject is now (a Character's head, the forest gap), or
-- nil when it cannot be found. The adapter answers from the world.
export type Subject = (framing: Framing) -> Vec3?

-- A Shot being played: since when, the Rig it eases in from, and the way
-- Amy turns to face its subject.
type Playing = { framing: Framing, started: number, from: Rig, heading: number }

export type Camera = {
	-- the follow camera's view: Amy's facing, and how high it looks down on her
	yaw: number,
	pitch: number,
	-- seconds since the camera was made
	clock: number,
	-- the Shot being played, the Shots framed after it, and the follow
	-- camera's return once the last ends
	playing: Playing?,
	queue: { Framing },
	handBack: { from: Rig, started: number }?,
	-- the Rig of the last Frame
	last: Rig?,
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

local function lerp(a: Vec3, b: Vec3, t: number): Vec3
	return v(math.lerp(a.x, b.x, t), math.lerp(a.y, b.y, t), math.lerp(a.z, b.z, t))
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
		lookAt = lerp(a.lookAt, b.lookAt, t),
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
	return {
		yaw = CameraModel.yawOf(facing) or 0,
		pitch = CameraModel.DEFAULT_PITCH,
		clock = 0,
		playing = nil,
		queue = {},
		handBack = nil,
		last = nil,
	}
end

-- Amy was put somewhere facing `facing` (a respawn, or TeleportPlayer):
-- the follow camera goes behind her there, and any Shot ends.
function CameraModel.place(camera: Camera, facing: Vec3)
	camera.yaw = CameraModel.yawOf(facing) or camera.yaw
	camera.pitch = CameraModel.DEFAULT_PITCH
	camera.playing = nil
	camera.handBack = nil
	table.clear(camera.queue)
	camera.last = nil
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
-- tilting back down answers at once. A Shot owns the view while it plays.
function CameraModel.turn(camera: Camera, yaw: number, pitch: number)
	if camera.playing then
		return
	end
	camera.yaw = wrap(camera.yaw + yaw)
	camera.pitch = math.clamp(camera.pitch + pitch, CameraModel.MIN_PITCH, CameraModel.MAX_PITCH)
end

--[[ The Shots ]]

-- 0 to 1 over 0 to 1, starting and ending gently.
local function smooth(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

-- What a Shot's path is given: Amy, its subject, the way she faces it,
-- and the Character it frames.
export type Scene = { amy: Vec3, subject: Vec3, heading: number, character: string? }

-- shot:MeetCharacter's rows (feel.md): the camera's azimuth from and to
-- (degrees), its elevation (degrees) and distance from and to.
type Meeting = { azimuth: { number }, elevation: number, distance: { number } }
CameraModel.MEETINGS = table.freeze({
	-- low behind Amy, the Squirrel among the roots ahead: an arc of about 15°
	Squirrel = { azimuth = { 10, 25 }, elevation = -9, distance = { 10, 10 } },
	-- bright orange against the paradise greens: an arc of about 15°
	Fox = { azimuth = { -20, -5 }, elevation = 10, distance = { 11, 11 } },
	-- low, looking up at him so he looks big: a slow push in
	Lion = { azimuth = { 15, 15 }, elevation = -10, distance = { 14, 9 } },
}) :: { [string]: Meeting }
-- an animal with no row yet: a still framing over her shoulder
local STILL_MEETING: Meeting = { azimuth = { 20, 20 }, elevation = 10, distance = { 10, 10 } }

-- shot:Dialogue: over Amy's right shoulder, at the speaker's eye height,
-- looking a little below the head so it sits in the upper part of the
-- frame (tan of the head's angle above the view's centre).
CameraModel.DIALOGUE_AZIMUTH = math.rad(30)
CameraModel.DIALOGUE_DISTANCE = 9
CameraModel.DIALOGUE_HEAD_RISE = 0.24
-- the steepest the two-shot looks up or down at a speaker
local DIALOGUE_STEEPEST = math.rad(35)

-- The Rig of each Shot `t` seconds in, before easing in and before the
-- clamp: every path keeps the cone by itself (a Shot that would show her
-- face is not a valid Shot), and tier 1 checks it.
CameraModel.PATHS = {
	Dialogue = function(scene)
		local distance = CameraModel.DIALOGUE_DISTANCE
		local rise = (scene.subject.y - scene.amy.y) / distance
		local rig: Rig = {
			yaw = scene.heading,
			azimuth = CameraModel.DIALOGUE_AZIMUTH,
			elevation = math.clamp(math.asin(math.clamp(rise, -1, 1)), -DIALOGUE_STEEPEST, DIALOGUE_STEEPEST),
			distance = distance,
			lookAt = scene.subject,
		}
		local camera = CameraModel.frame(rig, scene.amy).camera
		local dx, dz = scene.subject.x - camera.x, scene.subject.z - camera.z
		local across = math.sqrt(dx * dx + dz * dz)
		rig.lookAt = v(scene.subject.x, scene.subject.y - CameraModel.DIALOGUE_HEAD_RISE * across, scene.subject.z)
		return rig
	end,

	-- low behind Amy, tilting up from her to the wall of trunks and the
	-- canopies over about 3 s, the gap centred and still in view at the end
	ForestWallReveal = function(scene, t)
		local facing = CameraModel.facing(scene.heading)
		local from = add(add(scene.amy, UP, 2), facing, 6)
		local to = v(scene.subject.x, 18, scene.subject.z)
		local share = smooth((t - Shot.EASE_IN) / 3)
		return {
			yaw = scene.heading,
			azimuth = math.rad(12),
			elevation = math.rad(-7),
			distance = 8,
			lookAt = lerp(from, to, share),
		}
	end,

	MeetCharacter = function(scene, t)
		local row = CameraModel.MEETINGS[scene.character or ""] or STILL_MEETING
		local share = smooth(t / (Shot.SECONDS.MeetCharacter :: number))
		return {
			yaw = scene.heading,
			azimuth = math.rad(math.lerp(row.azimuth[1], row.azimuth[2], share)),
			elevation = math.rad(row.elevation),
			distance = math.lerp(row.distance[1], row.distance[2], share),
			lookAt = scene.subject,
		}
	end,

	-- wide, from behind Amy and the crowd, toward the machine and the
	-- trees; holds while the machine reverses, then tilts up to the treetops
	MachineFinale = function(scene, t)
		local share = smooth((t - 2.5) / 3)
		return {
			yaw = scene.heading,
			azimuth = math.rad(35),
			elevation = math.rad(22),
			distance = 40,
			lookAt = v(scene.subject.x, math.lerp(8, 50, share), scene.subject.z),
		}
	end,
} :: { [string]: (scene: Scene, t: number) -> Rig }
local PATHS = CameraModel.PATHS

-- Queues `shot` (with its Character); it plays once those before it end.
-- An unknown Shot is an error.
function CameraModel.frameShot(camera: Camera, shot: string, character: string?)
	if not PATHS[shot] then
		error(`no Shot {shot}`, 2)
	end
	table.insert(camera.queue, { shot = shot, character = character })
end

-- Ends the playing Shot: the next queued one starts at the next step, or
-- the follow camera returns, behind the way Amy now faces.
local function finish(camera: Camera)
	camera.playing = nil
	if #camera.queue == 0 and camera.last then
		camera.yaw = camera.last.yaw
		camera.pitch = CameraModel.DEFAULT_PITCH
		camera.handBack = { from = camera.last, started = camera.clock }
	end
end

-- The Dialogue was finished: a held Shot playing ends, and one queued
-- for it is dropped.
function CameraModel.dialogueFinished(camera: Camera)
	for i = #camera.queue, 1, -1 do
		if Shot.HELD[camera.queue[i].shot] then
			table.remove(camera.queue, i)
		end
	end
	if camera.playing and Shot.HELD[camera.playing.framing.shot] then
		finish(camera)
	end
end

-- Where the playing Shot's subject is now; when no Shot is playing, starts
-- the next queued one whose subject can be found, from `from`.
local function subjectNow(camera: Camera, amy: Vec3, subject: Subject, from: Rig): Vec3?
	if camera.playing then
		return subject(camera.playing.framing)
	end
	while #camera.queue > 0 do
		local framing = table.remove(camera.queue, 1) :: Framing
		local at = subject(framing)
		if at then
			local heading = CameraModel.yawOf(v(at.x - amy.x, 0, at.z - amy.z)) or from.yaw
			camera.playing = { framing = framing, started = camera.clock, from = from, heading = heading }
			camera.handBack = nil
			return at
		end
	end
	return nil
end

local function nowhere(): Vec3?
	return nil
end

-- This frame, `seconds` after the last, for Amy standing at `amy`.
function CameraModel.step(camera: Camera, seconds: number, amy: Vec3, subject: Subject?): Frame
	camera.clock += seconds
	local playing = camera.playing
	local limit = playing and Shot.SECONDS[playing.framing.shot]
	if limit and camera.clock - (playing :: Playing).started >= limit then
		finish(camera)
	end
	local follow = CameraModel.follow(camera, amy)
	local at = subjectNow(camera, amy, subject or nowhere, camera.last or follow)
	if camera.playing and not at then
		finish(camera) -- the subject left the world: the Shot ends here
	end

	local rig = follow
	playing = camera.playing
	if playing and at then
		local t = camera.clock - playing.started
		local scene = { amy = amy, subject = at, heading = playing.heading, character = playing.framing.character }
		rig = CameraModel.blend(playing.from, PATHS[playing.framing.shot](scene, t), smooth(t / Shot.EASE_IN))
	elseif camera.handBack then
		local t = camera.clock - camera.handBack.started
		if t >= Shot.HAND_BACK then
			camera.handBack = nil
		else
			rig = CameraModel.blend(camera.handBack.from, follow, smooth(t / Shot.HAND_BACK))
		end
	end

	rig = CameraModel.clamp(rig)
	camera.last = rig
	local frame = CameraModel.frame(rig, amy)
	frame.shot = if playing then playing.framing.shot else nil
	return frame
end

return CameraModel
