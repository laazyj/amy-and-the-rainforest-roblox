-- Screens: a Studio playtest's screenshots, put where they are reviewed
-- (brief mac-003, Must A2 and A3). The pure half on hand-written reports,
-- then tools/screens end to end through ImageMagick, when it is installed
-- (it is on GitHub's ubuntu-latest, where CI runs this).
local Playthrough = require("../../../tools/studio-playtest/playthrough")
local Screens = require("../../../tools/lib/screens")
local bootstrap = require("../bootstrap")

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local function always(_: string): boolean
	return true
end

local function report(devices: { any }, extra: { [string]: any }?): any
	local made: { [string]: any } = {
		finished = true,
		result = "pass",
		studioVersion = "0.743.0.7431133",
		pinnedStudioVersion = "0.743.0.7431133",
		studioVersionDrift = false,
		durationSeconds = 412,
		devices = devices,
	}
	for key, value in (extra or {}) :: { [string]: any } do
		made[key] = value
	end
	return made
end

local function device(name: string, files: { string }, extra: { [string]: any }?): any
	local captures = {}
	for _, file in files do
		table.insert(captures, { file = file })
	end
	local made: { [string]: any } = { name = name, result = "pass", captures = captures, warnings = {} }
	for key, value in (extra or {}) :: { [string]: any } do
		made[key] = value
	end
	return made
end

local function capture(file: string): Screens.Capture
	return Screens.parse(file) :: Screens.Capture
end

local function page(devices: { Screens.Device }, extra: { [string]: any }?): Screens.Page
	local made: { [string]: any } = {
		report = report({ device("pc", {}) }),
		devices = devices,
		rejected = {},
		title = false,
		baseUrl = "https://raw.example/run-1",
		runUrl = "https://run.example/1",
		artifactUrl = "https://run.example/1/artifact",
	}
	for key, value in (extra or {}) :: { [string]: any } do
		made[key] = value
	end
	return made :: any
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("Screens.parse", function()
		it("reads <device>/<nn>-<kind>-<name>.png", function()
			expect(Screens.parse("phone-portrait/03-shot-amy-at-the-gate.png")).toEqual({
				device = "phone-portrait",
				file = "phone-portrait/03-shot-amy-at-the-gate.png",
				kind = "shot",
				name = "amy-at-the-gate",
			})
			expect(capture("pc/12-title-title.png").kind).toBe(Screens.TITLE_KIND)
			-- the playthrough numbers with %02d, so the 100th capture has three digits
			expect(capture("pc/100-shot-late.png").name).toBe("late")
		end)

		for _, file in
			{
				"pc/../../etc/passwd.png",
				"../pc/01-shot-a.png",
				"pc/1-shot-a.png",
				"pc/01-shot-A.png",
				"pc/01-shot-a b.png",
				"pc/01-shot-a.png.sh",
				"PC/01-shot-a.png",
				"pc/sub/01-shot-a.png",
				"01-shot-a.png",
			}
		do
			it(`refuses "{file}"`, function()
				expect(Screens.parse(file)).toBeNil()
			end)
		end
	end)

	describe("Screens.code", function()
		it("makes any text one inert code span", function()
			expect(Screens.code("a `b`\n| @owner <img src=x>")).toBe("`a  b / @owner <img src=x>`")
			expect(Screens.code(nil)).toBe("`nil`")
			expect(Screens.code(string.rep("x", 30), 10)).toBe("`xxxxxxxxxx...`")
		end)
	end)

	describe("Screens.captures", function()
		it("takes each device's captures, in order, and leaves out what is not one", function()
			local played, rejected = Screens.captures(
				report({
					device("pc", { "pc/01-card-one.png", "pc/../x.png", "phone/02-shot-a.png", "pc/03-shot-gone.png" }),
					device("../evil", { "pc/01-card-one.png" }),
					device("pc", {}),
					{ name = "phone", result = "fail", captures = "none" },
				}),
				function(file)
					return file ~= "pc/03-shot-gone.png"
				end
			)
			expect(played).toEqual({
				{ name = "pc", result = "pass", captures = { capture("pc/01-card-one.png") } },
				{ name = "phone", result = "fail", captures = {} },
			})
			expect(rejected).toEqual({
				"`pc/../x.png`",
				"`phone/02-shot-a.png`",
				"`pc/03-shot-gone.png`",
				"device `../evil`",
				"device `pc`",
			})
		end)

		it("takes nothing from a missing or broken report", function()
			expect(Screens.captures(nil, always)).toEqual({})
			expect(Screens.captures({ devices = "x" }, always)).toEqual({})
		end)
	end)

	describe("Screens.pair", function()
		it("pairs by device, kind and name, whatever the number, in order of occurrence", function()
			local compared, gone = Screens.pair({
				capture("pc/01-card-one.png"),
				capture("pc/02-shot-new.png"),
				capture("pc/03-shot-gate.png"),
				capture("pc/04-shot-gate.png"),
			}, {
				"pc/02-shot-gate.png",
				"pc/01-card-one.png",
				"pc/03-shot-gate.png",
				"pc/04-scene-gone.png",
				"pc/README",
			})
			local paired = {}
			for _, each in compared do
				table.insert(paired, `{each.capture.file} {each.baseline or "new"} {each.status}`)
			end
			expect(paired).toEqual({
				"pc/01-card-one.png pc/01-card-one.png new",
				"pc/02-shot-new.png new new",
				"pc/03-shot-gate.png pc/02-shot-gate.png new",
				"pc/04-shot-gate.png pc/03-shot-gate.png new",
			})
			expect(gone).toEqual({ "pc/04-scene-gone.png" })
		end)
	end)

	describe("Screens.changed", function()
		it("counts a capture as changed over the level 2 tolerance, or when its size changed", function()
			expect(Screens.changed(Screens.SHARE, false)).toBe(false)
			expect(Screens.changed(Screens.SHARE * 1.01, false)).toBe(true)
			expect(Screens.changed(0, true)).toBe(true)
		end)
	end)

	describe("Screens.comment", function()
		local function changed(file: string, baseline: string, share: number): Screens.Compared
			return { capture = capture(file), baseline = baseline, status = "changed", share = share }
		end

		it("starts with the marker it is found by, and links the run and the artifact", function()
			local text = Screens.comment(page({}))
			expect(string.sub(text, 1, #Screens.MARKER + 1)).toBe(Screens.MARKER .. "\n")
			expect(text).toContain("[The run](https://run.example/1) · [the artifact](https://run.example/1/artifact)")
		end)

		it("shows each device's counts, contact sheet and changed captures' before, after and difference", function()
			local text = Screens.comment(page({
				{
					name = "pc",
					result = "pass",
					compared = {
						changed("pc/02-shot-gate.png", "pc/01-shot-gate.png", 0.0234),
						{ capture = capture("pc/03-card-two.png"), baseline = "pc/02-card-two.png", status = "same" },
						{ capture = capture("pc/04-scene-new.png"), status = "new" },
					},
					gone = { "pc/09-scene-old.png" },
					baselines = 3,
				},
			}, { title = true }))
			expect(text).toContain("| pc | `pass` | 3 | 1 | 1 | 1 |")
			expect(text).toContain("![The title screen on every device](https://raw.example/run-1/sheets/title.png)")
			expect(text).toContain("![Contact sheet, pc](https://raw.example/run-1/sheets/pc.png)")
			expect(text).toContain(
				'| `pc/02-shot-gate.png`<br>2.3% of pixels | <img src="https://raw.example/run-1/before/pc/01-shot-gate.png" alt="before" width="240"> | <img src="https://raw.example/run-1/captures/pc/02-shot-gate.png" alt="after" width="240"> | <img src="https://raw.example/run-1/diff/pc/02-shot-gate.png" alt="difference" width="240"> |'
			)
			expect(text).toContain("New, no baseline: `pc/04-scene-new.png`")
			expect(text).toContain("Baselines no capture matched: `pc/09-scene-old.png`")
		end)

		it("says when a device has no baselines yet, instead of listing every capture as new", function()
			local text = Screens.comment(page({
				{
					name = "pc",
					result = "pass",
					compared = { { capture = capture("pc/01-card-one.png"), status = "new" } },
					gone = {},
					baselines = 0,
				},
			}))
			expect(text).toContain("No baselines in `docs/screens/pc/` yet: every capture is new.")
			expect(text).never.toContain("New, no baseline")
		end)

		it("shows the Studio version against the pin, warnings and failures, all as code", function()
			local text = Screens.comment(page({}, {
				report = report({
					device("phone-portrait", {}, {
						warnings = { "asked for portrait, played landscape @owner" },
						result = "fail",
						failure = "stuck at <b>",
					}),
				}, {
					studioVersion = "0.744",
					pinnedStudioVersion = "0.743",
					studioVersionDrift = true,
					finished = false,
				}),
			}))
			expect(text).toContain(
				"**Playtest: stopped before the end** in 412 s. Studio `0.744`, not the pinned `0.743`."
			)
			expect(text).toContain("> Warning, `phone-portrait`: `asked for portrait, played landscape @owner`")
			expect(text).toContain("> Failure, `phone-portrait`: `stuck at <b>`")
		end)

		it("says when there is no report", function()
			expect(Screens.comment(page({}, { report = false }))).toContain("**No report.json**")
		end)

		it(`shows at most {Screens.MAX_ROWS} changed captures, and says how many more`, function()
			local compared = {}
			for i = 1, Screens.MAX_ROWS + 3 do
				local file = string.format("pc/%02d-shot-s%d.png", i, i)
				table.insert(compared, changed(file, file, 0.5))
			end
			local text = Screens.comment(page({
				{ name = "pc", result = "pass", compared = compared, gone = {}, baselines = #compared },
			}))
			local _, rows = string.gsub(text, 'alt="difference"', "")
			expect(rows).toBe(Screens.MAX_ROWS)
			expect(text).toContain("3 more changed captures are not shown here")
		end)
	end)

	describe("Screens.status", function()
		local function played(name: string, result: string, statuses: { Screens.Status }): Screens.Device
			local compared: { Screens.Compared } = {}
			for i, status in statuses do
				local each: Screens.Compared =
					{ capture = capture(string.format("%s/%02d-shot-s.png", name, i)), status = status :: any }
				table.insert(compared, each)
			end
			return { name = name, result = result, compared = compared, gone = {}, baselines = 1 }
		end

		it("passes with the devices, the screenshots and how many changed", function()
			expect({
				Screens.status(report({}), {
					played("pc", "pass", { "same", "changed", "new" }),
					played("phone", "pass", { "changed" }),
				}),
			}).toEqual({ "success", "2 devices, 4 screenshots, 2 changed" })
		end)

		it("fails naming the first device that failed", function()
			expect({
				Screens.status(report({}, { result = "fail" }), {
					played("pc", "pass", {}),
					played("phone-portrait", "fail", {}),
				}),
			}).toEqual({ "failure", "playthrough failed on phone-portrait" })
		end)

		it("fails a run cut short, a failed run and a run with no report", function()
			expect({ Screens.status(report({}, { finished = false }), {}) }).toEqual({
				"failure",
				"playthrough stopped before the end",
			})
			expect({ Screens.status(report({}, { result = "fail" }), {}) }).toEqual({ "failure", "playthrough failed" })
			expect({ Screens.status(nil, {}) }).toEqual({ "failure", "no report: the playthrough did not start" })
		end)
	end)

	describe("Screens.baselines", function()
		local files = { "pc/01-card-one.png", "pc/02-title-title.png" }

		it("takes every capture of a finished, passing run of main", function()
			local captures = Screens.baselines(
				report({ device("pc", files), device("phone", { "phone/01-card-one.png" }) }),
				always,
				{ "pc", "phone" }
			)
			expect(captures).toEqual({ capture(files[1]), capture(files[2]), capture("phone/01-card-one.png") })
		end)

		local refused: { { any } } = {
			{ "a failed run", report({ device("pc", files) }, { result = "fail" }), "did not pass to the end" },
			{ "a run cut short", report({ device("pc", files) }, { finished = false }), "did not pass to the end" },
			{ "a stray file", report({ device("pc", { "pc/x.png" }) }), "not a capture's file name: `pc/x.png`" },
			{ "no captures", report({ device("pc", {}) }), "made no captures" },
			{ "no report", false, "there is no report.json" },
		}
		for _, case in refused do
			it(`refuses {case[1]}`, function()
				local captures, reason = Screens.baselines(case[2], always, { "pc", "phone" })
				expect(captures).toBeNil()
				expect(reason).toContain(case[3])
			end)
		end
	end)

	describe("the Baselines workflow", function()
		it("finds runs of main by the name studio-playtest.yml gives them", function()
			local playtest = bootstrap.readSource(".github/workflows/studio-playtest.yml")
			local baselines = bootstrap.readSource(".github/workflows/baselines.yml")
			expect(playtest).toContain(
				"run-name: Studio playtest of ${{ inputs.pr && format('#{0}', inputs.pr) || 'main' }}"
			)
			expect(baselines).toContain('select(.displayTitle == "Studio playtest of main")')
			expect(baselines).toContain('"Studio playtest / main / Studio playtest of main / success"')
		end)
	end)

	local magick = process.exec(
		"sh",
		{ "-c", "command -v montage && command -v compare && command -v convert && command -v identify" }
	).ok
	-- Skipped on a machine without ImageMagick, never in CI, which installs it.
	if not magick and process.env.CI then
		error("ImageMagick is not installed: CI installs it so tools/screens is proven end to end", 0)
	end
	describe(
		`tools/screens end to end {if magick then "through ImageMagick" else "(skipped: no ImageMagick here)"}`,
		function()
			if not magick then
				return
			end
			local dir = process.exec("mktemp", { "-d" }).stdout:gsub("%s+$", "")
			local function image(path: string, gradient: string, box: string)
				fs.writeDir(string.match(path, "^(.*)/") :: string)
				local made = process.exec(
					"convert",
					{ "-size", "320x200", `gradient:{gradient}`, "-fill", "gold", "-draw", `rectangle {box}`, path }
				)
				assert(made.ok, made.stderr)
			end
			local function screens(args: { string }): process.ExecResult
				local all = { "run", `{bootstrap.REPO_ROOT}/tools/screens` }
				table.move(args, 1, #args, #all + 1, all)
				return process.exec("lune", all)
			end

			image(`{dir}/artifact/pc/01-card-one.png`, "khaki-wheat", "10,10 40,40")
			image(`{dir}/artifact/pc/02-title-title.png`, "navy-green", "100,60 220,80")
			image(`{dir}/artifact/phone/01-title-title.png`, "navy-green", "100,60 220,80")
			image(`{dir}/screens/pc/01-card-one.png`, "khaki-wheat", "10,10 40,40")
			-- the title moved down by 20 pixels
			image(`{dir}/screens/pc/02-title-title.png`, "navy-green", "100,80 220,100")
			fs.writeFile(
				`{dir}/artifact/report.json`,
				serde.encode(
					"json",
					report({
						device("pc", { "pc/01-card-one.png", "pc/02-title-title.png" }),
						device("phone", { "phone/01-title-title.png" }),
					})
				)
			)

			it("writes the contact sheets, the title index, and the changed capture's before and difference", function()
				local result = screens({
					"sheets",
					"--artifact",
					`{dir}/artifact`,
					"--baselines",
					`{dir}/screens`,
					"--files",
					`{dir}/out/files`,
					"--comment",
					`{dir}/out/comment.md`,
					"--status",
					`{dir}/out/status.json`,
					"--base-url",
					"https://raw.example/run-1",
					"--run-url",
					"https://run.example/1",
				})
				expect(result.stderr).toBe("")
				for _, file in
					{
						"sheets/pc.png",
						"sheets/phone.png",
						"sheets/title.png",
						"captures/pc/01-card-one.png",
						"captures/pc/02-title-title.png",
						"captures/phone/01-title-title.png",
						"before/pc/02-title-title.png",
						"diff/pc/02-title-title.png",
					}
				do
					expect(`{file} {fs.isFile(`{dir}/out/files/{file}`)}`).toBe(`{file} true`)
				end
				-- the unchanged capture has no difference image
				expect(fs.isFile(`{dir}/out/files/diff/pc/01-card-one.png`)).toBe(false)
				local comment = fs.readFile(`{dir}/out/comment.md`)
				expect(comment).toContain("| pc | `pass` | 2 | 1 | 0 | 0 |")
				expect(comment).toContain("| phone | `pass` | 1 | 0 | 1 | 0 |")
				expect(comment).toContain("`pc/02-title-title.png`<br>")
				expect(serde.decode("json", fs.readFile(`{dir}/out/status.json`))).toEqual({
					state = "success",
					description = "2 devices, 3 screenshots, 1 changed",
				})
			end)

			it("copies a passing run's captures of every device for a Baselines pull request", function()
				local devices = {}
				for _, each in Playthrough.DEVICES do
					local file = `{each.name}/01-title-title.png`
					image(`{dir}/artifact/{file}`, "navy-green", "100,60 220,80")
					table.insert(devices, device(each.name, { file }))
				end
				fs.writeFile(`{dir}/artifact/report.json`, serde.encode("json", report(devices)))
				local result = screens({ "baselines", "--artifact", `{dir}/artifact`, "--out", `{dir}/baselines` })
				expect(result.stderr).toBe("")
				for _, each in Playthrough.DEVICES do
					local file = `{each.name}/01-title-title.png`
					expect(fs.readFile(`{dir}/baselines/{file}`)).toBe(fs.readFile(`{dir}/artifact/{file}`))
				end
			end)

			it("refuses, copying nothing, a run that did not pass", function()
				fs.writeFile(
					`{dir}/artifact/report.json`,
					serde.encode("json", report({ device("pc", { "pc/01-card-one.png" }) }, { result = "fail" }))
				)
				local result = screens({ "baselines", "--artifact", `{dir}/artifact`, "--out", `{dir}/refused` })
				expect(result.ok).toBe(false)
				expect(result.stderr).toContain("no baselines: the playtest did not pass to the end")
				expect(fs.isDir(`{dir}/refused`)).toBe(false)
			end)
		end
	)
end
