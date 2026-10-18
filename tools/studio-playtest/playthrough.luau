--!strict
-- The tier 3 playthrough (brief mac-002): plays the Story from a fresh Save
-- to the end card on a real client in Roblox Studio, once per device, as a
-- player would: E advances each Dialogue and presses each talk prompt, and
-- the Player Character walks to each Quest's Zone or Character. A screenshot
-- is taken at every Shot, Chapter card and Scene entry, and of the Title
-- screen, which the Dev shortcut /title shows after the first Chapter card.
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
-- The Title screen is captured this long after its buttons are built, so
-- its picture has loaded.
Playthrough.TITLE_SETTLE = 1
-- How long /title, and then Continue, have to open and close it.
Playthrough.TITLE_TIMEOUT = 15
-- No change on screen for this long means the Story is stuck.
Playthrough.STALL = 60
-- The whole Story, per device.
Playthrough.DEVICE_TIMEOUT = 600
-- The whole run, Studio's start included: well inside the job's 60 minutes,
-- leaving time to install the tools, stop and upload. A device is not
-- started with less than MIN_DEVICE of it left (one takes about 200 s).
Playthrough.BUDGET = 45 * 60
-- Kept back from each device's time for what follows its deadline: the
-- step in progress, Stop Play and stopping the simulator, each of which
-- can wait on Studio.
Playthrough.TEARDOWN_RESERVE = 180
Playthrough.MIN_DEVICE = Playthrough.TEARDOWN_RESERVE + 240
-- How far the client's viewport may differ from the simulated device's
-- size in points, as a fraction: its short side, and at most its long side
-- (a phone's long side loses its safe-area insets).
Playthrough.VIEWPORT_TOLERANCE = 0.02

-- Run on the client once Play has started: records every Shot the server
-- frames, and the end card's arrival (a Chapter card is read off the screen
-- instead, since the first one arrives before this can run).
Playthrough.INSTALL_SCRIPT = [[
local player = game:GetService("Players").LocalPlayer
if player:FindFirstChild("PlaytestLog") then
	return "already installed"
end
-- Roblox's player list would put the runner's account name in every frame.
game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
-- Roblox's chat is on in Dev only, for the Dev shortcuts: hidden here as on
-- Release, its input bar shown only while the playthrough types /title.
local chat = game:GetService("TextChatService")
chat:WaitForChild("ChatWindowConfiguration").Enabled = false
chat:WaitForChild("ChatInputBarConfiguration").Enabled = false
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
local dialogueFrame = gui:FindFirstChild("DialogueFrame", true)
out.dialogue = dialogueFrame.Visible
if out.dialogue then
	out.line = dialogueFrame:FindFirstChild("Body", true).Text
end
local titleScreen = gui:FindFirstChild("TitleScreen", true)
if titleScreen.Visible then
	-- The Title screen, its Continue button once the server's offer built it.
	local button = titleScreen:FindFirstChild("continue", true)
	out.title = {
		continue = button and (string.gsub(button:GetFullName(), "^Players%.[^.]+%.", "LocalPlayer.")),
	}
end
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
	line: string?, -- the Dialogue's text so far, while it shows
	ended: boolean?, -- the server has sent the end card
	card: { title: string, settled: boolean }?,
	-- The Title screen; `continue` is its Continue button's instance path,
	-- once the server's offer has built the buttons.
	title: { continue: string? }?,
	objective: string?,
	target: Target?,
	scene: string?, -- the Scene of the Zone Amy stands in, if any
	amy: Smoke.Vector?,
	-- The client's viewport and the orientation it actually plays in (the
	-- place's StarterGui.ScreenOrientation can hold it to landscape).
	screen: { viewport: string, orientation: string }?,
}

export type CaptureKind = "shot" | "card" | "scene" | "title"

export type Capture = {
	file: string,
	kind: CaptureKind,
	name: string,
	luminance: number,
	pixels: string,
}

export type DeviceReport = {
	name: string,
	class: string,
	result: "pass" | "fail" | "skipped",
	failure: string?, -- or why it was skipped
	seconds: number,
	-- What the device simulator reported after it was set; nil for a PC.
	simulation: Smoke.Simulation?,
	quests: { string }, -- each Quest as it became active
	screen: { viewport: string, orientation: string }?, -- as the client first saw it
	captures: { Capture },
	warnings: { string },
}

export type Report = {
	-- False while the run is going: report.json is written after every
	-- device, so a job cut short still leaves what it played.
	finished: boolean,
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
	budget: number?, -- seconds; Playthrough.BUDGET when nil
	progress: ((Report) -> ())?, -- called with the report after every device
	clock: () -> number,
	sleep: (seconds: number) -> (),
	log: (string) -> (),
}

local round = Smoke.round

-- Shows or hides Roblox's chat input bar on the client (INSTALL_SCRIPT
-- hides it).
function Playthrough.chatBarScript(enabled: boolean): string
	return `game:GetService("TextChatService").ChatInputBarConfiguration.Enabled = {enabled}`
end

-- Selects the GuiButton at `instancePath` ("LocalPlayer.PlayerGui...") on
-- the client, so Return activates it as it does for a keyboard player.
function Playthrough.selectScript(instancePath: string): string
	return string.format(
		[[
local object = game:GetService("Players").LocalPlayer
for name in string.gmatch((string.gsub(%q, "^LocalPlayer%%.", "")), "[^.]+") do
	object = object:FindFirstChild(name) or error(`no {name} in {object:GetFullName()}`)
end
game:GetService("GuiService").SelectedObject = object
return object:GetFullName()
]],
		instancePath
	)
end

-- The observing script, reporting only the Shots after the first `since`.
function Playthrough.observeScript(since: number): string
	return `local SINCE = {since}\n` .. OBSERVE_BODY
end

-- A file name part from a Shot, card or Scene name.
local function slug(text: string): string
	local lowered = string.lower((string.gsub(text, "[^%w]+", "-")))
	return (string.gsub(lowered, "^%-*(.-)%-*$", "%1"))
end

-- A failure of the Story itself, not of Studio or the runner: raised as a
-- table so the run can tell the two apart.
type StoryFailure = { story: string }

local function storyFailure(message: string): never
	error({ story = message } :: StoryFailure)
end

-- Why the client's viewport is not the simulated device's, or nil.
local function viewportMismatch(viewport: string, simulation: Smoke.Simulation): string?
	local width, height = string.match(viewport, "^(%d+)x(%d+)$")
	local w, h = tonumber(width) or 0, tonumber(height) or 0
	local short, long = math.min(w, h), math.max(w, h)
	local deviceShort, deviceLong =
		math.min(simulation.width, simulation.height), math.max(simulation.width, simulation.height)
	local tolerance = Playthrough.VIEWPORT_TOLERANCE
	if math.abs(short - deviceShort) > deviceShort * tolerance or long > deviceLong * (1 + tolerance) then
		return `the client's viewport is {viewport}, not the {simulation.device}'s {simulation.width}x{simulation.height}`
	end
	return nil
end

-- Plays the Story once on the device Studio simulates, until `deadline`;
-- fills `report`.
local function playDevice(
	bridge: Smoke.Bridge,
	options: Options,
	run: DeviceRun,
	report: DeviceReport,
	deadline: number
)
	local started = options.clock()
	local shotsTaken, cardsTaken, scenesTaken, titleTaken = 0, {}, {}, false
	local function observe(): Observation
		return serde.decode("json", bridge.run("Client", Playthrough.observeScript(shotsTaken)))
	end
	local function capture(kind: CaptureKind, name: string)
		local file = string.format("%s/%02d-%s-%s.png", run.name, #report.captures + 1, kind, slug(name))
		local shot = bridge.capture(`{options.outDir}/{file}`)
		table.insert(report.captures, {
			file = file,
			kind = kind,
			name = name,
			luminance = Smoke.roundLuminance(shot.luminance),
			pixels = shot.pixels,
		})
		options.log(`  {file}`)
		if shot.luminance < Smoke.LUMINANCE_FLOOR then
			error(`{file} is black where the viewport should be: Studio rendered nothing`, 0)
		elseif shot.luminance > Smoke.LUMINANCE_CEILING then
			error(`{file} is nearly white where the viewport should be: something covers the game`, 0)
		end
	end

	-- Looks at the client until `find` finds something in what it shows; a
	-- Story failure after TITLE_TIMEOUT. For the Title screen's two waits.
	local function lookForTitle<T>(find: (Observation) -> T?, failure: string): T
		local giveUp = options.clock() + Playthrough.TITLE_TIMEOUT
		while true do
			local found = find(observe())
			if found ~= nil then
				return found
			elseif options.clock() > giveUp then
				storyFailure(`{failure} within {Playthrough.TITLE_TIMEOUT} seconds`)
			end
			options.sleep(Playthrough.POLL)
		end
	end
	-- The Title screen, through the Dev shortcut /title as a person testing
	-- Dev types it; Continue carries on where the Story was. On PC it is
	-- clicked; in the device simulator, which takes no mouse input on the
	-- game's buttons, it is selected and Return pressed, as by a keyboard.
	local function captureTitle()
		bridge.run("Client", Playthrough.chatBarScript(true))
		bridge.chat("/title")
		bridge.run("Client", Playthrough.chatBarScript(false))
		local continue = lookForTitle(function(seen)
			return seen.title and seen.title.continue
		end, "/title did not show the Title screen with Continue")
		options.sleep(Playthrough.TITLE_SETTLE)
		capture("title", "title")
		if run.device then
			bridge.run("Client", Playthrough.selectScript(continue))
			bridge.press("Return")
		else
			bridge.click(continue)
		end
		lookForTitle(function(seen)
			return not seen.title or nil
		end, "Continue did not close the Title screen")
	end

	bridge.run("Client", Playthrough.INSTALL_SCRIPT)
	local lastChange, lastState = options.clock(), ""
	while true do
		local now = options.clock()
		if now > deadline then
			storyFailure(`the Story did not end within {round(deadline - started)} seconds`)
		end
		local seen = observe()
		local screen = seen.screen
		if not report.screen and screen then
			report.screen = screen
			options.log(`  {screen.viewport}, {screen.orientation}`)
			local mismatch = report.simulation and viewportMismatch(screen.viewport, report.simulation)
			if mismatch then
				error(mismatch, 0)
			end
			local device = run.device
			if device and device.orientation == "Portrait" and not string.find(screen.orientation, "Portrait") then
				local warning = `asked for portrait, the place plays {screen.orientation}`
				table.insert(report.warnings, warning)
				options.log(`  warning: {warning}`)
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
		-- Once, after the first Chapter card, while the Story waits on the player.
		if not titleTaken and next(cardsTaken) and seen.objective and not card and not seen.dialogue then
			titleTaken = true
			captureTitle()
			lastChange = options.clock()
			continue
		end

		local target = seen.target
		if target and report.quests[#report.quests] ~= target.quest then
			table.insert(report.quests, target.quest)
			options.log(`  Quest {target.quest}`)
			if target.kind ~= "reach" and target.kind ~= "talk" then
				storyFailure(`the playthrough cannot play a {target.kind} Quest yet ({target.quest})`)
			end
		end
		-- Amy walking, or a Line still being written, is a change too.
		local amy = seen.amy
		local state = table.concat({
			tostring(seen.objective),
			tostring(seen.dialogue),
			seen.line or "",
			card and card.title or "",
			tostring(#seen.shots),
			tostring(seen.scene),
			if amy then `{amy.x // 2},{amy.z // 2}` else "",
		}, "|")
		if state ~= lastState then
			lastState, lastChange = state, now
		elseif now - lastChange > Playthrough.STALL then
			storyFailure(`the Story is stuck: nothing changed for {Playthrough.STALL} seconds ({state})`)
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
		`**Studio playtest: {if report.finished then report.result else "stopped before the end"}** in {report.durationSeconds} s, Studio {report.studioVersion or "unknown"}`
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
	for _, device in report.devices do
		for _, warning in device.warnings do
			table.insert(lines, "")
			table.insert(lines, `Warning, {device.name}: {warning}`)
		end
	end
	if report.failure then
		table.insert(lines, "")
		table.insert(lines, `Failure: {report.failure}`)
	end
	return table.concat(lines, "\n")
end

function Playthrough.run(bridge: Smoke.Bridge, options: Options): Report
	local started = options.clock()
	local budget = options.budget or Playthrough.BUDGET
	local report: Report = {
		finished = false,
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
	local function progress()
		report.durationSeconds = round(options.clock() - started)
		-- A report that cannot be written is logged, and the run goes on.
		local write = options.progress
		if write then
			local written, err = pcall(function()
				write(report)
			end)
			if not written then
				options.log(`could not write the report: {err}`)
			end
		end
	end
	local function deviceReport(run: DeviceRun): DeviceReport
		local device: DeviceReport = {
			name = run.name,
			class = run.class,
			result = "pass",
			seconds = 0,
			quests = {},
			captures = {},
			warnings = {},
		}
		table.insert(report.devices, device)
		return device
	end
	-- The devices from `index` on are not played.
	local function skip(index: number, reason: string)
		for i = index, #options.devices do
			local device = deviceReport(options.devices[i])
			device.result = "skipped"
			device.failure = reason
		end
	end

	local ok, err = pcall(function()
		Smoke.readVersion(bridge, report, options.log)
		bridge.open(options.placeFile)
	end)
	if not ok then
		fail(`Open the place in Studio: {err}`)
	else
		-- Whatever goes wrong below, Studio is still quit after it.
		local ran, crash = pcall(function()
			local simulated, stopped = false, true
			for index, run in options.devices do
				local remaining = budget - (options.clock() - started)
				if remaining < Playthrough.MIN_DEVICE then
					fail(`the run's {budget}-second budget was spent before {run.name}`)
					skip(index, "the run's time budget was spent")
					break
				end
				options.log(`== {run.name}`)
				local device = deviceReport(run)
				local deviceStarted = options.clock()
				local deadline = deviceStarted
					+ math.min(Playthrough.DEVICE_TIMEOUT, remaining - Playthrough.TEARDOWN_RESERVE)
				local playing = false
				local played, failure = pcall(function()
					simulated = simulated or run.device ~= nil
					device.simulation = Smoke.checkSimulation(run.device, bridge.setDevice(run.device))
					playing = true
					bridge.startPlay()
					playDevice(bridge, options, run, device, deadline)
				end)
				local stopFailure = nil
				if playing then
					stopped, stopFailure = pcall(bridge.stopPlay)
				end
				device.seconds = round(options.clock() - deviceStarted)
				local story = type(failure) == "table"
				if not played then
					device.result = "fail"
					device.failure = if story then (failure :: StoryFailure).story else tostring(failure)
					fail(`{run.name}: {device.failure}`)
				end
				local skipRest = nil
				if not stopped then
					device.result = "fail"
					device.failure = device.failure or `Stop Play: {stopFailure}`
					fail(`{run.name}: Stop Play: {stopFailure}`)
					skipRest = "Studio did not stop Play" -- the next device would play in a session still in Play
				elseif story and run.class == "PC" then
					skipRest = "the Story did not end on PC" -- nor will it on a phone
				end
				if skipRest then
					skip(index + 1, skipRest)
					progress()
					break
				end
				progress()
			end
			-- Studio as it was found: no device simulated.
			if simulated and stopped then
				local restored, restoreFailure = pcall(function()
					Smoke.checkSimulation(nil, bridge.setDevice(nil))
				end)
				if not restored then
					fail(`Stop the device simulator: {restoreFailure}`)
				end
			end
		end)
		if not ran then
			fail(`the run stopped: {crash}`)
		end
	end
	pcall(bridge.close)
	report.finished = true
	progress()
	return report
end

return Playthrough
