local Bmp = require("../../../tools/studio-playtest/bmp")
local Mcp = require("../../../tools/studio-playtest/mcp")
local Smoke = require("../../../tools/studio-playtest/smoke")

local PRINTED = "studio-smoke place=Game isStudio=true"

-- A Studio that behaves, recording what was asked of it; `overrides`
-- replaces single Bridge functions to make one thing go wrong.
local function fakeStudio(overrides: { [string]: any }?): (Smoke.Bridge, { string })
	local calls: { string } = {}
	local bridge: any = {
		studioVersion = function()
			return "0.742.0.7421053"
		end,
		open = function(placeFile)
			table.insert(calls, `open {placeFile}`)
		end,
		startPlay = function()
			table.insert(calls, "startPlay")
		end,
		stopPlay = function()
			table.insert(calls, "stopPlay")
		end,
		run = function(dataModel, code)
			table.insert(calls, `run {dataModel}`)
			return if dataModel == "Edit"
				then "Place.rbxl"
				elseif code == Smoke.PLAY_SCRIPT then PRINTED .. "\n"
				else "1029x719 16.64"
		end,
		consoleOutput = function()
			return `[StoryServer] Story engine ready\n{PRINTED}`
		end,
		capture = function(path)
			table.insert(calls, `capture {path}`)
			return 0.4321
		end,
		close = function()
			table.insert(calls, "close")
		end,
		setDevice = function() end,
		press = function() end,
		walkTo = function() end,
		insertAsset = function()
			return ""
		end,
	}
	for name, fn in overrides or {} :: { [string]: any } do
		bridge[name] = fn
	end
	return bridge, calls
end

local function run(bridge: Smoke.Bridge, pinned: string?): Smoke.Report
	local now = 0
	return Smoke.run(bridge, {
		placeFile = "build/Place.rbxl",
		screenshotPath = "out/viewport.png",
		pinnedStudioVersion = pinned or "0.742.0.7421053",
		clock = function()
			now += 0.5
			return now
		end,
		log = function() end,
	})
end

return function(t: any)
	t.describe("studio-playtest smoke", function()
		t.it("opens, plays, runs the script, captures, stops and quits, in that order", function()
			local bridge, calls = fakeStudio()
			local report = run(bridge)
			t.expect(calls).toEqual({
				"open build/Place.rbxl",
				"run Edit",
				"startPlay",
				"run Server",
				"run Client",
				"capture out/viewport.png",
				"stopPlay",
				"close",
			})
			t.expect(report.result).toBe("pass")
			t.expect(report.failure).toBeNil()
			t.expect(report.placeName).toBe("Place.rbxl")
			t.expect(report.printed).toBe(PRINTED)
			t.expect(report.isStudio).toBe(true)
			t.expect(report.viewport).toBe("1029x719")
			t.expect(report.frameMilliseconds).toBe(16.6)
			t.expect(report.screenshotLuminance).toBe(0.432)
			t.expect(report.screenshot).toBe("out/viewport.png")
			t.expect(report.studioVersion).toBe("0.742.0.7421053")
			t.expect(report.studioVersionDrift).toBe(false)
			t.expect(report.durationSeconds > 0).toBe(true)
			t.expect(#report.steps).toBe(7)
		end)

		t.it("reports Studio version drift without failing", function()
			local report = run(fakeStudio(), "0.741.0.1")
			t.expect(report.result).toBe("pass")
			t.expect(report.studioVersionDrift).toBe(true)
			t.expect(report.pinnedStudioVersion).toBe("0.741.0.1")
		end)

		t.it("fails when Studio has another place open, and still quits Studio", function()
			local bridge, calls = fakeStudio({
				run = function()
					return "Other.rbxl"
				end,
			})
			local report = run(bridge)
			t.expect(report.result).toBe("fail")
			t.expect(report.failure).toContain("Open the place in Studio: Studio has 'Other.rbxl' open")
			t.expect(calls).toEqual({ "open build/Place.rbxl", "close" })
		end)

		t.it("stops Play and quits Studio when a step fails during Play", function()
			local bridge, calls = fakeStudio({
				capture = function()
					error("the screen is locked", 0)
				end,
			})
			local report = run(bridge)
			t.expect(report.result).toBe("fail")
			t.expect(report.failure).toBe("Capture the viewport: the screen is locked")
			t.expect(report.screenshot).toBeNil()
			t.expect(calls[#calls - 1]).toBe("stopPlay")
			t.expect(calls[#calls]).toBe("close")
		end)

		t.it("fails with what the client returned when it is not a viewport and a frame time", function()
			local report = run((fakeStudio({
				run = function(dataModel, code)
					return if dataModel == "Edit"
						then "Place.rbxl"
						elseif code == Smoke.PLAY_SCRIPT then PRINTED
						else "1029x719 soon"
				end,
			})))
			t.expect(report.failure).toBe("Capture the viewport: the client returned '1029x719 soon'")
		end)

		t.it("fails when the screenshot is black where the viewport should be", function()
			local bridge = fakeStudio({
				capture = function()
					return 0.001
				end,
			})
			local report = run(bridge)
			t.expect(report.result).toBe("fail")
			t.expect(report.failure)
				.toBe("Capture the viewport: the screenshot is black where the viewport should be: Studio rendered nothing")
		end)

		t.it("stops Play when starting it failed half way", function()
			local bridge, calls = fakeStudio({
				startPlay = function()
					error("Studio did not start Play", 0)
				end,
			})
			t.expect(run(bridge).failure).toBe("Start Play: Studio did not start Play")
			t.expect(calls).toEqual({ "open build/Place.rbxl", "run Edit", "stopPlay", "close" })
		end)

		t.it("fails when the console does not show the printed line", function()
			local report = run((fakeStudio({
				consoleOutput = function()
					return "nothing"
				end,
			})))
			t.expect(report.failure).toContain("the Studio console does not show")
		end)

		t.it("fails when IsStudio is false", function()
			local report = run((fakeStudio({
				run = function(dataModel)
					return if dataModel == "Edit" then "Place.rbxl" else "studio-smoke place=Game isStudio=false"
				end,
			})))
			t.expect(report.failure).toContain("RunService:IsStudio() is false")
			t.expect(report.isStudio).toBe(false)
		end)

		t.it("fails when stopping Play fails, keeping the first failure", function()
			local report = run((fakeStudio({
				stopPlay = function()
					error("Studio did not stop Play", 0)
				end,
			})))
			t.expect(report.result).toBe("fail")
			t.expect(report.failure).toBe("Stop Play: Studio did not stop Play")
		end)
	end)

	t.describe("studio-playtest mcp", function()
		t.it("splits what was read into complete lines and the rest", function()
			local lines, rest = Mcp.lines('{"id":1}\n\n{"id":2}\n{"id"')
			t.expect(lines).toEqual({ '{"id":1}', '{"id":2}' })
			t.expect(rest).toBe('{"id"')
		end)

		t.it("returns a tool's text", function()
			local response = { result = { content = { { type = "text", text = "Game Started" } }, isError = false } }
			t.expect(Mcp.toolText("start_stop_play", response)).toBe("Game Started")
		end)

		t.it("raises a tool error with the tool's name", function()
			local response =
				{ result = { content = { { type = "text", text = "Place is not open" } }, isError = true } }
			t.expectError(function()
				Mcp.toolText("get_studio_state", response)
			end, "get_studio_state: Place is not open")
		end)

		t.it("raises a JSON-RPC error", function()
			t.expectError(function()
				Mcp.toolText("execute_luau", { error = { code = -32602, message = "unknown tool" } })
			end, "execute_luau: unknown tool")
		end)
	end)

	t.describe("studio-playtest bmp", function()
		-- A BMP of `width` x `height` pixels, each the bytes of `pixel` (BGR or BGRA).
		local function bmp(width: number, height: number, pixel: { number }): string
			local stride = math.ceil(width * #pixel / 4) * 4
			local row = string.rep(string.char(table.unpack(pixel)), width)
			row ..= string.rep("\0", stride - #row)
			local header = buffer.create(54)
			buffer.writestring(header, 0, "BM")
			buffer.writeu32(header, 10, 54)
			buffer.writei32(header, 18, width)
			buffer.writei32(header, 22, -height)
			buffer.writeu16(header, 28, #pixel * 8)
			return buffer.tostring(header) .. string.rep(row, height)
		end

		local function rounded(luminance: number): number
			return math.round(luminance * 10000) / 10000
		end

		t.it("reads black as 0 and white as 1, with or without alpha", function()
			t.expect(Bmp.luminance(bmp(3, 2, { 0, 0, 0 }))).toBe(0)
			t.expect(Bmp.luminance(bmp(3, 2, { 0, 0, 0, 255 }))).toBe(0)
			t.expect(rounded(Bmp.luminance(bmp(3, 2, { 255, 255, 255 })))).toBe(1)
			t.expect(rounded(Bmp.luminance(bmp(2, 2, { 255, 255, 255, 255 })))).toBe(1)
		end)

		t.it("weighs green above red above blue", function()
			t.expect(rounded(Bmp.luminance(bmp(1, 1, { 255, 0, 0 })))).toBe(0.0722)
			t.expect(rounded(Bmp.luminance(bmp(1, 1, { 0, 255, 0 })))).toBe(0.7152)
			t.expect(rounded(Bmp.luminance(bmp(1, 1, { 0, 0, 255 })))).toBe(0.2126)
		end)

		t.it("rejects what is not a whole BMP", function()
			t.expectError(function()
				Bmp.luminance("PNG")
			end, "not a BMP image")
			t.expectError(function()
				Bmp.luminance(string.sub(bmp(4, 4, { 1, 2, 3 }), 1, 60))
			end, "truncated BMP image")
		end)
	end)
end
