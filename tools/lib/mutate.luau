--!strict
--[[
	The nightly mutation check (plan section 4): canned faults, each applied
	on its own to a copy of the repository, with tier 1 run against it. A
	fault the suite does not catch means the tests do not bite where they
	should. tools/mutate.luau runs it; .github/workflows/mutation.yml runs
	that nightly and writes the report to the job summary.

	Each fault is a list of exact edits to one file; every edit's `from`
	must occur exactly once, so a fault that no longer matches the code
	fails loudly instead of silently testing nothing.
]]

export type Edit = { from: string, to: string }
export type Fault = { name: string, file: string, edits: { Edit } }
export type Result = {
	fault: Fault,
	-- the tests that failed, "<spec>: <test>"; empty when the fault survived
	caught: { string },
	-- why the fault could not be applied, or its run read
	error: string?,
}

local Mutate = {}

-- Swaps two exact texts of a file, through a placeholder.
function Mutate.swap(a: string, b: string): { Edit }
	local placeholder = "\0MUTATE\0"
	return { { from = a, to = placeholder }, { from = b, to = a }, { from = placeholder, to = b } }
end

Mutate.FAULTS = {
	{
		name = "rename a Quest id (chapter3.meet_fox)",
		file = "src/content/chapters/3/data.luau",
		edits = { { from = 'id = "chapter3.meet_fox",', to = 'id = "chapter3.find_fox",' } },
	},
	{
		name = "drop a Hook (chapter2.enter_forest.onComplete plays no beat:paradise_reveal)",
		file = "src/content/chapters/2/data.luau",
		edits = { { from = 'hooks = { onComplete = { "paradise_reveal" } },', to = "" } },
	},
	{
		-- core/Save and its migrations arrive with brief 010; until then the
		-- Progress a save holds is rebuilt by Resume, so the fault breaks that.
		name = "break a Resume (Progress no longer replays the Beats of completed Quests)",
		file = "src/core/StoryEngine.luau",
		edits = {
			{
				from = "\t\t\tBeat.play(placed.chapter, hooks.onStart, events, commands)\n\t\t\tBeat.play(placed.chapter, hooks.onComplete, events, commands)\n",
				to = "\t\t\tBeat.play(placed.chapter, hooks.onStart, events, commands)\n",
			},
		},
	},
	{
		name = "blank a canon Line (It was a bautyfull paradise!)",
		file = "src/content/chapters/2/data.luau",
		edits = { { from = 'text = "It was a bautyfull paradise!"', to = 'text = ""' } },
	},
	{
		name = "swap two Objectives (chapter1.sneak_out_1 and chapter1.sneak_out_2)",
		file = "src/content/chapters/1/data.luau",
		edits = Mutate.swap(
			'objective = "Sneak out through the garden gate... quietly!"',
			'objective = "Wait for Sam to look away, then try the gate again"'
		),
	},
	{
		name = "remove a Zone (zone:HomeGarden)",
		file = "src/content/scenes/Garden.luau",
		edits = { { from = "\tHomeGarden = zone(at(0, 5, -26), at(26, 10, 16)),\n", to = "" } },
	},
	{
		name = "break a Beat's command order (beat:sam_catches teleports Amy before Sam reaches the gate)",
		file = "src/content/chapters/1/hooks.luau",
		edits = Mutate.swap(
			'{ kind = "MoveCharacter", character = "Sam", spot = "GateOutside" },',
			'{ kind = "TeleportPlayer", spot = "GardenInside" },'
		),
	},
	{
		name = "change a Speaker (Dad's canon Line said by Mum)",
		file = "src/content/chapters/1/data.luau",
		edits = {
			{
				from = '{ speaker = "Dad", text = "No, it to Dangerous',
				to = '{ speaker = "Mum", text = "No, it to Dangerous',
			},
		},
	},
	{
		name = "a reach Quest completes on any Zone",
		file = "src/core/quests/reach.luau",
		edits = { { from = "event.zone == quest.zone", to = "event.zone ~= nil" } },
	},
	{
		name = "rename a remote on the wire (ShowChapter sent as ShowChapterCard)",
		file = "src/core/Net.luau",
		edits = { { from = 'else "ShowChapter",', to = 'else "ShowChapterCard",' } },
	},
	{
		name = "the World state ignores SetLighting",
		file = "src/core/WorldState.luau",
		edits = { { from = "state.lighting = command.preset", to = "state.lighting = state.lighting" } },
	},
	{
		name = "the Objective tracker shows with no Objective",
		file = "src/core/ObjectiveText.luau",
		edits = { { from = 'visible = trimmed ~= ""', to = "visible = true" } },
	},
} :: { Fault }

-- Why each fault no longer applies to the files `read` returns; empty when
-- every one does. Run in tier 0 (`tools/guard faults`), so a stale fault
-- fails on the PR that makes it stale, not in the nightly job.
function Mutate.stale(faults: { Fault }, read: (path: string) -> string): { string }
	local stale = {}
	for _, fault in faults do
		local ok, err = pcall(Mutate.apply, read(fault.file), fault)
		if not ok then
			table.insert(stale, `tools/lib/mutate.luau: {err}`)
		end
	end
	return stale
end

-- `source` with `fault`'s edits applied in order; an error when an edit's
-- text is not in it exactly once.
function Mutate.apply(source: string, fault: Fault): string
	for i, edit in fault.edits do
		local first, last = string.find(source, edit.from, 1, true)
		if not first or not last then
			error(`edit {i} of "{fault.name}" no longer matches {fault.file}`, 0)
		elseif string.find(source, edit.from, last + 1, true) then
			error(`edit {i} of "{fault.name}" matches {fault.file} more than once`, 0)
		end
		source = string.sub(source, 1, first - 1) .. edit.to .. string.sub(source, last + 1)
	end
	return source
end

-- The tests a run of tests/lune/runner.luau reports failing, as
-- "<spec>: <test>", from its output.
function Mutate.failures(output: string): { string }
	local failures, spec = {}, "?"
	for line in string.gmatch(output, "[^\n]+") do
		local failed = string.match(line, "^  ✗ (.*)$")
		if failed then
			table.insert(failures, `{spec}: {failed}`)
		elseif string.match(line, "%.spec%.luau$") then
			spec = line
		end
	end
	return failures
end

export type Runner = {
	read: (path: string) -> string,
	write: (path: string, text: string) -> (),
	-- runs tier 1 on the copy; whether it passed, and its output
	test: () -> (boolean, string),
	-- progress, before each fault
	log: (string) -> (),
}

-- Applies each fault on its own, runs tier 1, and restores the file.
function Mutate.run(faults: { Fault }, runner: Runner): { Result }
	local results: { Result } = {}
	for i, fault in faults do
		runner.log(`[{i}/{#faults}] {fault.name}`)
		local original = runner.read(fault.file)
		local ok, mutated = pcall(Mutate.apply, original, fault)
		if not ok then
			table.insert(results, { fault = fault, caught = {}, error = tostring(mutated) })
			continue
		end
		runner.write(fault.file, mutated)
		local passed, output = runner.test()
		runner.write(fault.file, original)
		local caught: { string } = if passed then {} else Mutate.failures(output)
		local failed = if not passed and #caught == 0 then `tier 1 failed without naming a test:\n{output}` else nil
		table.insert(results, { fault = fault, caught = caught, error = failed })
	end
	return results
end

-- The faults the suite let through, or that could not be applied.
function Mutate.survivors(results: { Result }): { Result }
	local survivors = {}
	for _, result in results do
		if result.error or #result.caught == 0 then
			table.insert(survivors, result)
		end
	end
	return survivors
end

local SHOWN = 3

-- The report, as Markdown: one row per fault with the tests that caught it.
function Mutate.report(results: { Result }): string
	local lines = {
		"## Mutation check",
		"",
		`{#results - #Mutate.survivors(results)} of {#results} faults caught by tier 1.`,
		"",
		"| Fault | File | Caught by |",
		"|---|---|---|",
	}
	for _, result in results do
		local cell
		if result.error then
			cell = `**not applied**: {result.error}`
		elseif #result.caught == 0 then
			cell = "**survived**: no test failed"
		else
			local shown = table.move(result.caught, 1, math.min(SHOWN, #result.caught), 1, {})
			cell = table.concat(shown, "<br>")
			if #result.caught > SHOWN then
				cell ..= `<br>and {#result.caught - SHOWN} more`
			end
		end
		cell = string.gsub(cell, "|", "\\|")
		table.insert(lines, `| {result.fault.name} | \`{result.fault.file}\` | {cell} |`)
	end
	return table.concat(lines, "\n") .. "\n"
end

return Mutate
