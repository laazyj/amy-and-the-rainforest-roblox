local Playthrough = require("../../../tools/studio-playtest/playthrough")

local serde = require("@lune/serde")

local CARD = { title = "Chapter One", settled = true }

-- The presets' sizes in points, as Studio's simulator reports them.
local SIZES = { iphone_16 = { 852, 393 }, ipad_10th_generation = { 1180, 820 } }

-- What a simulator that took the setting reports.
local function simulating(device: any): any
	if not device then
		return nil
	end
	local size = SIZES[device.simulator]
	return {
		device = device.simulator,
		orientation = "LandscapeRight",
		scaling = "FitToWindow",
		width = size[1],
		height = size[2],
	}
end

-- A Studio whose client shows `screens` one after another, one per look,
-- and keeps showing the last; records what was asked of it.
local function fakeStudio(screens: { { [string]: any } }, overrides: { [string]: any }?)
	local calls: { string } = {}
	local now = 0
	local shown = 0
	local bridge: any = {
		studioVersion = function()
			return "0.742.0.7421053"
		end,
		open = function(placeFile)
			table.insert(calls, `open {placeFile}`)
		end,
		setDevice = function(device: any)
			table.insert(calls, `device {if device then device.simulator .. " " .. device.orientation else "none"}`)
			return simulating(device)
		end,
		startPlay = function()
			table.insert(calls, "startPlay")
		end,
		stopPlay = function()
			table.insert(calls, "stopPlay")
		end,
		run = function(dataModel, code)
			assert(dataModel == "Client", "the playthrough only looks at the client")
			if code == Playthrough.INSTALL_SCRIPT then
				table.insert(calls, "install")
				return "installed"
			end
			shown = math.min(shown + 1, #screens)
			local screen = table.clone(screens[shown])
			screen.now = now
			-- The client sends only the Shots after the first `since`.
			local since = tonumber(string.match(code, "^local SINCE = (%d+)")) or 0
			screen.shots = { table.unpack(screen.shots or {}, since + 1) }
			screen.dialogue = screen.dialogue or false
			return serde.encode("json", screen)
		end,
		capture = function(path)
			table.insert(calls, `capture {path}`)
			return { luminance = 0.4, pixels = "1024x768" }
		end,
		press = function(key)
			table.insert(calls, `press {key}`)
		end,
		walkTo = function(position)
			table.insert(calls, `walk {position.x},{position.z}`)
		end,
		close = function()
			table.insert(calls, "close")
		end,
	}
	for name, fn in overrides or {} :: { [string]: any } do
		bridge[name] = fn
	end
	local function clock()
		now += 0.05
		return now
	end
	local function sleep(seconds)
		now += seconds
	end
	return bridge, calls, clock, sleep
end

local function play(
	bridge: any,
	clock: () -> number,
	sleep: (number) -> (),
	devices: { any }?,
	extra: { [string]: any }?
): Playthrough.Report
	local options: any = {
		placeFile = "build/Place.rbxl",
		outDir = "out",
		devices = devices or { Playthrough.DEVICES[1] },
		pinnedStudioVersion = "0.742.0.7421053",
		clock = clock,
		sleep = sleep,
		log = function() end,
	}
	for key, value in extra or {} :: { [string]: any } do
		options[key] = value
	end
	return Playthrough.run(bridge, options)
end

local PHONE, TABLET = Playthrough.DEVICES[2], Playthrough.DEVICES[3]

local function only(calls: { string }, prefix: string): { string }
	local found = {}
	for _, call in calls do
		if string.sub(call, 1, #prefix) == prefix then
			table.insert(found, call)
		end
	end
	return found
end

-- The first Quest, Dad `distance` studs away with his talk prompt offered.
local function talkToDad(distance: number)
	return {
		objective = "Ask Dad",
		target = {
			quest = "chapter1.ask_dad",
			kind = "talk",
			promptEnabled = true,
			distance = distance,
			position = { x = 4, y = 0, z = -26 },
		},
	}
end
local TALK_FAR, TALK_NEAR = talkToDad(20), talkToDad(3)
local SHOT = { name = "Dialogue", at = 0 }
local THE_END = { card = { title = "The End", settled = true }, ended = true, shots = { SHOT } }

return function(t: any)
	t.describe("studio-playtest playthrough", function()
		t.it("plays to the end card, capturing each card and Shot, walking and pressing E", function()
			local bridge, calls, clock, sleep = fakeStudio({
				{ card = { title = "Chapter One", settled = false } },
				{ card = CARD },
				{ dialogue = true },
				TALK_FAR,
				TALK_NEAR,
				{ dialogue = true, shots = { SHOT } },
				THE_END,
			})
			local report = play(bridge, clock, sleep)
			t.expect(report.result).toBe("pass")
			t.expect(report.failure).toBeNil()
			t.expect(only(calls, "capture")).toEqual({
				"capture out/pc/01-card-chapter-one.png",
				"capture out/pc/02-shot-dialogue.png",
				"capture out/pc/03-card-the-end.png",
			})
			t.expect(only(calls, "press")).toEqual({ "press E", "press E", "press E" })
			t.expect(only(calls, "walk")).toEqual({ "walk 4,-26" })
			t.expect(calls[1]).toBe("open build/Place.rbxl")
			t.expect(calls[2]).toBe("device none")
			t.expect(calls[#calls - 1]).toBe("stopPlay")
			t.expect(calls[#calls]).toBe("close")
			t.expect(report.devices[1].quests).toEqual({ "chapter1.ask_dad" })
			t.expect(report.devices[1].captures[2]).toEqual({
				file = "pc/02-shot-dialogue.png",
				kind = "shot",
				name = "Dialogue",
				luminance = 0.4,
				pixels = "1024x768",
			})
			t.expect(report.finished).toBe(true)
		end)

		t.it("captures a Shot only once it has eased in", function()
			local captured: number? = nil
			local bridge, _, clock, sleep
			bridge, _, clock, sleep = fakeStudio(
				{ { dialogue = true, shots = { { name = "MeetCharacter", at = 0.1 } } }, THE_END },
				{
					capture = function()
						captured = captured or clock()
						return { luminance = 0.4, pixels = "1024x768" }
					end,
				}
			)
			play(bridge, clock, sleep)
			t.expect((captured :: number) >= 0.1 + Playthrough.SHOT_SETTLE).toBe(true)
		end)

		t.it("captures a Scene entry once, and not while a Dialogue shows", function()
			local bridge, calls, clock, sleep = fakeStudio({
				{ dialogue = true, scene = "Garden" },
				{ scene = "Garden" },
				{ scene = "Garden" },
				{ scene = "Field" },
				THE_END,
			})
			play(bridge, clock, sleep)
			t.expect(only(calls, "capture")).toEqual({
				"capture out/pc/01-scene-garden.png",
				"capture out/pc/02-scene-field.png",
				"capture out/pc/03-shot-dialogue.png",
				"capture out/pc/04-card-the-end.png",
			})
		end)

		t.it("walks into a reach Quest's Zone", function()
			local reach = {
				objective = "Cross the field",
				target = {
					quest = "chapter2.walk_to_forest",
					kind = "reach",
					zone = "ForestEdge",
					position = { x = 0, y = 5, z = 60 },
				},
			}
			local bridge, calls, clock, sleep = fakeStudio({ reach, THE_END })
			play(bridge, clock, sleep)
			t.expect(only(calls, "walk")).toEqual({ "walk 0,60" })
		end)

		t.it("waits for a talk prompt that is not offered yet", function()
			local waiting = table.clone(TALK_NEAR)
			waiting.target = table.clone(TALK_NEAR.target)
			waiting.target.promptEnabled = false
			local bridge, calls, clock, sleep = fakeStudio({ waiting, waiting, THE_END })
			play(bridge, clock, sleep)
			t.expect(only(calls, "press")).toEqual({})
			t.expect(only(calls, "walk")).toEqual({})
		end)

		t.it("fails a stuck Story on a phone, stops Play, plays the next device and stops the simulator", function()
			local bridge, calls, clock, sleep = fakeStudio({ { objective = "Wait forever" } })
			local report = play(bridge, clock, sleep, { PHONE, TABLET })
			t.expect(report.result).toBe("fail")
			t.expect(string.find(report.failure :: string, "phone-landscape: the Story is stuck", 1, true)).toBe(1)
			t.expect(#report.devices).toBe(2)
			t.expect(report.devices[1].result).toBe("fail")
			t.expect(report.devices[2].result).toBe("fail")
			t.expect((report.devices[2].simulation :: any).device).toBe("ipad_10th_generation")
			t.expect(only(calls, "stopPlay")).toEqual({ "stopPlay", "stopPlay" })
			t.expect(only(calls, "device")).toEqual({
				"device iphone_16 Landscape",
				"device ipad_10th_generation Landscape",
				"device none",
			})
		end)

		t.it("skips the other devices when the Story does not end on PC", function()
			local bridge, calls, clock, sleep = fakeStudio({ { objective = "Wait forever" } })
			local report = play(bridge, clock, sleep, { Playthrough.DEVICES[1], PHONE })
			t.expect(string.find(report.failure :: string, "pc: the Story is stuck", 1, true)).toBe(1)
			t.expect(report.devices[2].result).toBe("skipped")
			t.expect(report.devices[2].failure).toBe("the Story did not end on PC")
			t.expect(only(calls, "startPlay")).toEqual({ "startPlay" })
		end)

		t.it("fails at once on a Quest kind it cannot play", function()
			local collect = { objective = "Gather seeds", target = { quest = "chapter9.gather", kind = "collect" } }
			local bridge, _, clock, sleep = fakeStudio({ collect })
			local report = play(bridge, clock, sleep)
			t.expect(report.failure).toBe("pc: the playthrough cannot play a collect Quest yet (chapter9.gather)")
			t.expect(report.devices[1].seconds < Playthrough.STALL).toBe(true)
		end)

		t.it("counts Amy walking and a Line being written as change, not a stall", function()
			local screens = {}
			for step = 1, 400 do
				table.insert(
					screens,
					{ dialogue = step % 2 == 0, line = string.rep("a", step), amy = { x = step * 3, y = 0, z = 0 } }
				)
			end
			table.insert(screens, THE_END)
			local bridge, _, clock, sleep = fakeStudio(screens, {
				press = function() end,
			})
			t.expect(play(bridge, clock, sleep).result).toBe("pass")
		end)

		t.it("fails a device whose simulator did not take the setting, and plays nothing on it", function()
			local bridge, calls, clock, sleep = fakeStudio({ THE_END }, {
				setDevice = function()
					return nil
				end,
			})
			local report = play(bridge, clock, sleep, { PHONE })
			t.expect(report.failure).toBe("phone-landscape: Studio simulates no device, not iphone_16")
			t.expect(only(calls, "startPlay")).toEqual({})
		end)

		t.it("fails a PC run while a device is still simulated", function()
			local bridge, _, clock, sleep = fakeStudio({ THE_END }, {
				setDevice = function()
					return simulating(TABLET.device)
				end,
			})
			local report = play(bridge, clock, sleep)
			t.expect(report.failure)
				.toBe("pc: Studio still simulates ipad_10th_generation after the simulator was stopped")
		end)

		t.it("fails when the client's viewport is not the simulated device's size", function()
			local wrong = table.clone(THE_END)
			wrong.screen = { viewport = "541x414", orientation = "LandscapeRight" }
			local bridge, _, clock, sleep = fakeStudio({ wrong })
			local report = play(bridge, clock, sleep, { PHONE })
			t.expect(report.failure)
				.toBe("phone-landscape: the client's viewport is 541x414, not the iphone_16's 852x393")
		end)

		t.it("stops playing devices when Stop Play fails, and leaves the simulator alone", function()
			local bridge, calls, clock, sleep = fakeStudio({ THE_END }, {
				stopPlay = function()
					error("Studio did not stop Play (waited 60 seconds)", 0)
				end,
			})
			local report = play(bridge, clock, sleep, { PHONE, TABLET })
			t.expect(report.failure).toBe("phone-landscape: Stop Play: Studio did not stop Play (waited 60 seconds)")
			t.expect(report.devices[2].result).toBe("skipped")
			t.expect(only(calls, "device")).toEqual({ "device iphone_16 Landscape" })
		end)

		t.it("starts no device without enough of the run's budget left, and says so", function()
			local bridge, calls, clock, sleep = fakeStudio({ THE_END })
			local budget = Playthrough.MIN_DEVICE + 10
			local report = play(bridge, clock, sleep, { PHONE, TABLET }, {
				budget = budget,
				-- Each device takes as long as the budget.
				sleep = function(seconds: number)
					sleep(seconds + budget)
				end,
			})
			t.expect(report.devices[1].result).toBe("pass")
			t.expect(report.devices[2].result).toBe("skipped")
			t.expect(report.failure).toBe(`the run's {budget}-second budget was spent before tablet-landscape`)
			t.expect(only(calls, "startPlay")).toEqual({ "startPlay" })
		end)

		t.it("ends a device early enough to leave the teardown reserve inside the budget", function()
			local walking = {}
			-- More looks than fit before the deadline (a look takes about 0.3 s).
			for step = 1, 2000 do
				table.insert(walking, { amy = { x = step * 3, y = 0, z = 0 } })
			end
			local bridge, _, clock, sleep = fakeStudio(walking)
			local budget = Playthrough.MIN_DEVICE + 100
			local report = play(bridge, clock, sleep, { PHONE }, { budget = budget })
			local seconds = tonumber(string.match(report.failure :: string, "did not end within ([%d.]+) seconds"))
			t.expect(seconds ~= nil).toBe(true)
			t.expect((seconds :: number) <= budget - Playthrough.TEARDOWN_RESERVE).toBe(true)
			t.expect(report.durationSeconds <= budget).toBe(true)
		end)

		t.it("still quits Studio when the report cannot be written", function()
			local bridge, calls, clock, sleep = fakeStudio({ THE_END })
			local report = play(bridge, clock, sleep, { PHONE }, {
				progress = function()
					error("disk full", 0)
				end,
			})
			t.expect(report.finished).toBe(true)
			t.expect(calls[#calls]).toBe("close")
		end)

		t.it("still quits Studio when the run itself breaks between devices", function()
			local bridge, calls, clock, sleep = fakeStudio({ THE_END })
			local report = play(bridge, clock, sleep, { PHONE }, {
				log = function(line)
					if line == "== phone-landscape" then
						error("the log broke", 0)
					end
				end,
			})
			t.expect(report.failure).toBe("the run stopped: the log broke")
			t.expect(calls[#calls]).toBe("close")
		end)

		t.it("hands over the report after every device, finished only at the end", function()
			local seen = {}
			local bridge, _, clock, sleep = fakeStudio({ THE_END })
			play(bridge, clock, sleep, { PHONE, TABLET }, {
				progress = function(report)
					table.insert(seen, `{#report.devices} {report.finished}`)
				end,
			})
			t.expect(seen).toEqual({ "1 false", "2 false", "2 true" })
		end)

		t.it("reports a place that does not open, plays nothing, and quits Studio", function()
			local bridge, calls, clock, sleep = fakeStudio({ THE_END }, {
				open = function()
					error("Studio's MCP server is not enabled", 0)
				end,
			})
			local report = play(bridge, clock, sleep)
			t.expect(report.failure).toBe("Open the place in Studio: Studio's MCP server is not enabled")
			t.expect(#report.devices).toBe(0)
			t.expect(calls).toEqual({ "close" })
		end)

		t.it("fails a screenshot that is black or nearly white where the game should be", function()
			for _, luminance in { 0.01, 0.95 } do
				local bridge, _, clock, sleep = fakeStudio({ { card = CARD }, THE_END }, {
					capture = function()
						return { luminance = luminance, pixels = "1024x768" }
					end,
				})
				local report = play(bridge, clock, sleep)
				t.expect(report.result).toBe("fail")
				t.expect(
					string.find(
						report.failure :: string,
						"01-card-chapter-one.png is " .. if luminance < 0.5 then "black" else "nearly white",
						1,
						true
					) ~= nil
				).toBe(true)
			end
		end)

		t.it("summarises the report as a line per device", function()
			local bridge, _, clock, sleep = fakeStudio({ { card = CARD }, TALK_NEAR, THE_END })
			local summary = Playthrough.summary(play(bridge, clock, sleep))
			t.expect(string.find(summary, "**Studio playtest: pass**", 1, true)).toBe(1)
			t.expect(string.find(summary, "| pc | pass |", 1, true) ~= nil).toBe(true)
			t.expect(string.find(summary, "| 1 | 3 |", 1, true) ~= nil).toBe(true)
		end)

		t.it("lists PC, then a phone and a tablet, landscape only", function()
			local names = {}
			for _, run in Playthrough.DEVICES do
				table.insert(names, `{run.class}:{run.name}`)
			end
			t.expect(names).toEqual({
				"PC:pc",
				"Phone:phone-landscape",
				"Tablet:tablet-landscape",
			})
		end)
	end)
end
