local Playthrough = require("../../../tools/studio-playtest/playthrough")

local serde = require("@lune/serde")

local CARD = { title = "Chapter One", settled = true }

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
			return 0.4
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

local function play(bridge: any, clock: () -> number, sleep: (number) -> (), devices: { any }?): Playthrough.Report
	return Playthrough.run(bridge, {
		placeFile = "build/Place.rbxl",
		outDir = "out",
		devices = devices or { Playthrough.DEVICES[1] },
		pinnedStudioVersion = "0.742.0.7421053",
		clock = clock,
		sleep = sleep,
		log = function() end,
	})
end

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
			})
		end)

		t.it("captures a Shot only once it has eased in", function()
			local captured: number? = nil
			local bridge, _, clock, sleep
			bridge, _, clock, sleep = fakeStudio(
				{ { dialogue = true, shots = { { name = "MeetCharacter", at = 0.1 } } }, THE_END },
				{
					capture = function()
						captured = captured or clock()
						return 0.4
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

		t.it("fails a stuck Story, stops Play, and plays the next device", function()
			local bridge, calls, clock, sleep = fakeStudio({ { objective = "Wait forever" } })
			local report = play(bridge, clock, sleep, { Playthrough.DEVICES[1], Playthrough.DEVICES[2] })
			t.expect(report.result).toBe("fail")
			t.expect(string.find(report.failure :: string, "pc: the Story is stuck", 1, true)).toBe(1)
			t.expect(#report.devices).toBe(2)
			t.expect(report.devices[1].result).toBe("fail")
			t.expect(only(calls, "stopPlay")).toEqual({ "stopPlay", "stopPlay" })
			t.expect(only(calls, "device")).toEqual({ "device none", "device iphone_16 Landscape" })
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
						return luminance
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

		t.it("lists PC, then a phone and a tablet in both orientations", function()
			local names = {}
			for _, run in Playthrough.DEVICES do
				table.insert(names, `{run.class}:{run.name}`)
			end
			t.expect(names).toEqual({
				"PC:pc",
				"Phone:phone-landscape",
				"Phone:phone-portrait",
				"Tablet:tablet-landscape",
				"Tablet:tablet-portrait",
			})
		end)
	end)
end
