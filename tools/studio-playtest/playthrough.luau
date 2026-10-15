--!strict
-- The tier 3 playthrough (brief mac-002): plays the Story from a fresh Save
-- to the end card on a real client in Roblox Studio, once per device, as a
-- player would: E advances each Dialogue and presses each talk prompt, and
-- the Player Character walks to each Quest's Zone or Character. A screenshot
-- is taken at every Shot, Chapter card and Scene entry.
--
-- Pure: Studio is reached through the Bridge (studio.luau), and what the
-- client sees comes back from Playthrough.observeScript as JSON, so the spec drives the
-- whole sequence with a fake client.

local serde = require("@lune/serde")

local Smoke = require("./smoke")

local Playthrough = {}

export type DeviceRun = {
	name: string, -- "pc", "phone-landscape", ...: the screenshots' folder
	class: "PC" | "Phone" | "Tablet",
	device: Smoke.Device?, -- nil: no simulation
}

-- PC, then a phone and a tablet preset in both orientations (plan section 4).
-- The phone is the 6-inch phone of feel.md (about 844 x 390 units), the
-- tablet an 11-inch one (up to 1376 x 1032).
Playthrough.DEVICES = table.freeze({
	{ name = "pc", class = "PC" },
	{ name = "phone-landscape", class = "Phone", device = { simulator = "iphone_16", orientation = "Landscape" } },
	{ name = "phone-portrait", class = "Phone", device = { simulator = "iphone_16", orientation = "Portrait" } },
	{
		name = "tablet-landscape",
		class = "Tablet",
		device = { simulator = "ipad_10th_generation", orientation = "Landscape" },
	},
	{
		name = "tablet-portrait",
		class = "Tablet",
		device = { simulator = "ipad_10th_generation", orientation = "Portrait" },
	},
} :: { DeviceRun })

-- A Shot is captured once it has eased in (Shot.EASE_IN is 0.5 s).
Playthrough.SHOT_SETTLE = 0.8
-- Seconds between looks at the client when there is nothing to do.
Playthrough.POLL = 0.25
-- After a key press, time for the client to answer it.
Playthrough.AFTER_PRESS = 0.5
-- A talk prompt is pressed from this close to its Character, in studs.
Playthrough.TALK_RANGE = 8
-- No change on screen for this long means the Story is stuck.
Playthrough.STALL = 60
-- The whole Story, per device.
Playthrough.DEVICE_TIMEOUT = 600

-- Run on the client once Play has started: records every Shot the server
-- frames, and the end card's arrival (a Chapter card is read off the screen
-- instead, since the first one arrives before this can run).
Playthrough.INSTALL_SCRIPT = [[
local player = game:GetService("Players").LocalPlayer
if player:FindFirstChild("PlaytestLog") then
	return "already installed"
end
local http = game:GetService("HttpService")
local log = Instance.new("Folder")
log.Name = "PlaytestLog"
log:SetAttribute("shots", "[]")
log.Parent = player
local remotes = game:GetService("ReplicatedStorage"):WaitForChild("StoryRemotes")
remotes.FrameShot.OnClientEvent:Connect(function(shot)
	local shots = http:JSONDecode(log:GetAttribute("shots"))
	table.insert(shots, { name = shot, at = os.clock() })
	log:SetAttribute("shots", http:JSONEncode(shots))
end)
remotes.ShowEnding.OnClientEvent:Connect(function()
	log:SetAttribute("ended", true)
end)
return "installed"
]]

-- Run on the client at every step: what the player sees, as JSON. The
-- active Quest is the one whose Objective is on screen; its target comes
-- from the place's own content, so a pull request's Story is played as it
-- is in that pull request.
local OBSERVE_BODY = [[
local http = game:GetService("HttpService")
local storage = game:GetService("ReplicatedStorage")
local player = game:GetService("Players").LocalPlayer
local out = { now = os.clock(), shots = {}, dialogue = false }
local camera = workspace.CurrentCamera
out.screen = {
	viewport = string.format("%dx%d", camera.ViewportSize.X, camera.ViewportSize.Y),
	orientation = player.PlayerGui.CurrentScreenOrientation.Name,
}

local log = player:FindFirstChild("PlaytestLog")
if log then
	local shots = http:JSONDecode(log:GetAttribute("shots"))
	out.shots = { table.unpack(shots, SINCE + 1) }
	out.ended = log:GetAttribute("ended") == true
end

local function vector(v)
	return { x = v.X, y = v.Y, z = v.Z }
end
local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
if root then
	out.amy = vector(root.Position)
end

local gui = player.PlayerGui:FindFirstChild("StoryUI")
if not gui then
	return http:JSONEncode(out)
end
out.dialogue = gui:FindFirstChild("DialogueFrame", true).Visible
local overlay = gui:FindFirstChild("TitleOverlay", true)
if overlay.Visible then
	local title = overlay:FindFirstChildWhichIsA("TextLabel")
	out.card = {
		title = title.Text,
		-- Faded in: the overlay at its shown transparency, the text opaque.
		settled = overlay.BackgroundTransparency <= 0.3 and title.TextTransparency <= 0.05,
	}
end

-- The content's Quests, Zones and the Scene each Zone is in.
local Story = require(storage.content.Story).story
local sceneOf = {}
for _, module in storage.content.scenes:GetChildren() do
	local scene = require(module)
	for zone in scene.zones or {} do
		sceneOf[zone] = scene.id
	end
end
local shown = {}
for _, label in gui:FindFirstChild("ObjectiveFrame", true):GetChildren() do
	if label:IsA("TextLabel") and label.Visible then
		shown[label.Text] = true
	end
end
local function inside(zone)
	if not root then
		return false
	end
	local offset = root.Position - Vector3.new(zone.centre.x, zone.centre.y, zone.centre.z)
	return math.abs(offset.X) <= zone.size.x / 2 and math.abs(offset.Z) <= zone.size.z / 2
end
for name, zone in Story.zones do
	if inside(zone) then
		out.scene = sceneOf[name]
	end
end
for _, chapter in Story.chapters do
	for _, quest in chapter.quests do
		if shown[quest.objective] then
			out.objective = quest.objective
			local target = { quest = quest.id, kind = quest.kind }
			if quest.kind == "reach" then
				local zone = Story.zones[quest.zone]
				target.zone = quest.zone
				target.scene = sceneOf[quest.zone]
				target.position = zone.centre
			elseif quest.kind == "talk" then
				local model = workspace:FindFirstChild("StoryCharacters")
				model = model and model:FindFirstChild(quest.character)
				target.character = quest.character
				if model then
					local at = model:GetPivot().Position
					local prompt = model:FindFirstChild("TalkPrompt", true)
					target.promptEnabled = prompt ~= nil and prompt.Enabled
					-- Beside the Character, on Amy's side: on top of it the prompt hides.
					local away = root and (root.Position - at) * Vector3.new(1, 0, 1) or Vector3.new(0, 0, 1)
					away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
					target.position = vector(at + away * 4)
					target.distance = root and (root.Position - at).Magnitude or math.huge
				end
			end
			out.target = target
		end
	end
end
return http:JSONEncode(out)
]]

export type Shot = { name: string, at: number }

export type Target = {
	quest: string,
	kind: string,
	zone: string?,
	scene: string?,
	character: string?,
	position: Smoke.Vector?,
	promptEnabled: boolean?,
	distance: number?,
}

export type Observation = {
	now: number, -- the client's clock, as the Shots' `at`
	shots: { Shot }, -- the Shots framed since the first `since`, in order
	dialogue: boolean,
	ended: boolean?, -- the server has sent the end card
	card: { title: string, settled: boolean }?,
	objective: string?,
	target: Target?,
	scene: string?, -- the Scene of the Zone Amy stands in, if any
	amy: Smoke.Vector?,
	-- The client's viewport and the orientation it actually plays in (the
	-- place's StarterGui.ScreenOrientation can hold it to landscape).
	screen: { viewport: string, orientation: string }?,
}

export type Capture = { file: string, kind: "shot" | "card" | "scene", name: string, luminance: number }

export type DeviceReport = {
	name: string,
	class: string,
	result: "pass" | "fail",
	failure: string?,
	seconds: number,
	quests: { string }, -- each Quest as it became active
	screen: { viewport: string, orientation: string }?, -- as the client first saw it
	captures: { Capture },
}

export type Report = {
	result: "pass" | "fail",
	failure: string?,
	studioVersion: string?,
	pinnedStudioVersion: string,
	studioVersionDrift: boolean,
	durationSeconds: number,
	placeFile: string,
	devices: { DeviceReport },
}

export type Options = {
	placeFile: string,
	outDir: string,
	devices: { DeviceRun },
	pinnedStudioVersion: string,
	clock: () -> number,
	sleep: (seconds: number) -> (),
	log: (string) -> (),
}

local round = Smoke.round

-- The observing script, reporting only the Shots after the first `since`.
function Playthrough.observeScript(since: number): string
	return `local SINCE = {since}\n` .. OBSERVE_BODY
end

-- A file name part from a Shot, card or Scene name.
local function slug(text: string): string
	local lowered = string.lower((string.gsub(text, "[^%w]+", "-")))
	return (string.gsub(lowered, "^%-*(.-)%-*$", "%1"))
end

-- Plays the Story once on the device Studio simulates; fills `report`.
local function playDevice(bridge: Smoke.Bridge, options: Options, run: DeviceRun, report: DeviceReport)
	local started = options.clock()
	local shotsTaken, cardsTaken, scenesTaken = 0, {}, {}
	local function observe(): Observation
		return serde.decode("json", bridge.run("Client", Playthrough.observeScript(shotsTaken)))
	end
	local function capture(kind: "shot" | "card" | "scene", name: string)
		local file = string.format("%s/%02d-%s-%s.png", run.name, #report.captures + 1, kind, slug(name))
		local luminance = bridge.capture(`{options.outDir}/{file}`)
		table.insert(
			report.captures,
			{ file = file, kind = kind, name = name, luminance = math.round(luminance * 1000) / 1000 }
		)
		options.log(`  {file}`)
		if luminance < Smoke.LUMINANCE_FLOOR then
			error(`{file} is black where the viewport should be: Studio rendered nothing`, 0)
		elseif luminance > Smoke.LUMINANCE_CEILING then
			error(`{file} is nearly white where the viewport should be: something covers the game`, 0)
		end
	end

	bridge.run("Client", Playthrough.INSTALL_SCRIPT)
	local lastChange, lastState = options.clock(), ""
	while true do
		local now = options.clock()
		if now - started > Playthrough.DEVICE_TIMEOUT then
			error(`the Story did not end within {Playthrough.DEVICE_TIMEOUT} seconds`, 0)
		end
		local seen = observe()
		if not report.screen and seen.screen then
			report.screen = seen.screen
			options.log(`  {seen.screen.viewport}, {seen.screen.orientation}`)
			local device = run.device
			if device and device.orientation == "Portrait" and not string.find(seen.screen.orientation, "Portrait") then
				options.log(`  warning: asked for portrait, the place plays {seen.screen.orientation}`)
			end
		end
		-- The client's clock now: its clock when it looked, plus the time since.
		local function clientNow(): number
			return seen.now + options.clock() - now
		end

		-- Captures first, before anything moves on.
		for _, shot in seen.shots do
			local wait = shot.at + Playthrough.SHOT_SETTLE - clientNow()
			if wait > 0 then
				options.sleep(wait)
			end
			capture("shot", shot.name)
			shotsTaken += 1
		end
		local card = seen.card
		if card and card.settled and not cardsTaken[card.title] then
			cardsTaken[card.title] = true
			capture("card", card.title)
			-- The run ends on both signals: the recorder saw the server send
			-- the end card, and the card on screen has faded in and been captured.
			if seen.ended then
				break
			end
		end
		if seen.scene and not scenesTaken[seen.scene] and not seen.dialogue and not card then
			scenesTaken[seen.scene] = true
			capture("scene", seen.scene)
		end

		local target = seen.target
		if target and report.quests[#report.quests] ~= target.quest then
			table.insert(report.quests, target.quest)
			options.log(`  Quest {target.quest}`)
		end
		local state = table.concat({
			tostring(seen.objective),
			tostring(seen.dialogue),
			card and card.title or "",
			tostring(#seen.shots),
			tostring(seen.scene),
		}, "|")
		if state ~= lastState then
			lastState, lastChange = state, now
		elseif now - lastChange > Playthrough.STALL then
			error(`the Story is stuck: nothing changed for {Playthrough.STALL} seconds ({state})`, 0)
		end

		-- A card holds, then fades by itself; a talk prompt comes once a Beat
		-- has played; anything else on screen waits too.
		local position = target and target.position
		local action = "wait"
		if seen.dialogue and not card then
			action = "press"
		elseif target and position and not card then
			if target.kind ~= "talk" then
				action = "walk"
			elseif target.promptEnabled then
				action = if (target.distance or math.huge) <= Playthrough.TALK_RANGE then "press" else "walk"
			end
		end
		if action == "press" then
			bridge.press("E")
			options.sleep(Playthrough.AFTER_PRESS)
		elseif action == "walk" and position then
			bridge.walkTo(position)
		else
			options.sleep(Playthrough.POLL)
		end
	end
end

-- The report as Markdown for the job summary: a line per device.
function Playthrough.summary(report: Report): string
	local lines = {
		`**Studio playtest: {report.result}** in {report.durationSeconds} s, Studio {report.studioVersion or "unknown"}`
			.. if report.studioVersionDrift then ` (the bridge was proven on {report.pinnedStudioVersion})` else "",
		"",
		"| Device | Result | Seconds | Quests | Screenshots | Screen |",
		"|---|---|---|---|---|---|",
	}
	for _, device in report.devices do
		table.insert(
			lines,
			`| {device.name} | {device.result} | {device.seconds} | {#device.quests} | {#device.captures} | {if device.screen
				then device.screen.viewport .. " " .. device.screen.orientation
				else "-"} |`
		)
	end
	if report.failure then
		table.insert(lines, "")
		table.insert(lines, `Failure: {report.failure}`)
	end
	return table.concat(lines, "\n")
end

function Playthrough.run(bridge: Smoke.Bridge, options: Options): Report
	local started = options.clock()
	local report: Report = {
		result = "pass",
		pinnedStudioVersion = options.pinnedStudioVersion,
		studioVersionDrift = false,
		durationSeconds = 0,
		placeFile = options.placeFile,
		devices = {},
	}
	local function fail(message: string)
		options.log(`failed: {message}`)
		if report.result == "pass" then
			report.result = "fail"
			report.failure = message
		end
	end

	local ok, err = pcall(function()
		Smoke.readVersion(bridge, report, options.log)
		bridge.open(options.placeFile)
	end)
	if not ok then
		fail(`Open the place in Studio: {err}`)
	else
		for _, run in options.devices do
			options.log(`== {run.name}`)
			local device: DeviceReport =
				{ name = run.name, class = run.class, result = "pass", seconds = 0, quests = {}, captures = {} }
			table.insert(report.devices, device)
			local deviceStarted = options.clock()
			local playing = false
			local played, failure = pcall(function()
				bridge.setDevice(run.device)
				playing = true
				bridge.startPlay()
				playDevice(bridge, options, run, device)
			end)
			if playing then
				pcall(bridge.stopPlay)
			end
			device.seconds = round(options.clock() - deviceStarted)
			if not played then
				device.result = "fail"
				device.failure = tostring(failure)
				fail(`{run.name}: {failure}`)
			end
		end
	end
	pcall(bridge.close)
	report.durationSeconds = round(options.clock() - started)
	return report
end

return Playthrough
