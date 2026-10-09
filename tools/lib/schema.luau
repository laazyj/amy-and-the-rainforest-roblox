--!strict
--[[
	The content schema (plan section 2.4, rule 3: the glossary is the
	schema). Every file under src/content has a role by its path, and each
	role a closed shape: a field the shape does not name is an error, and
	every name a field refers to (Quest kind, Speaker, Character, Hook,
	Beat, Spot, Zone, Scene, Prop and its states, Lighting preset, World
	command and its arguments, Cue, Shot) must be in the glossary's tables,
	not marked *later*. The enumerations are read from docs/GLOSSARY.md
	each run (tools/lib/glossary.luau); nothing here lists them. A World
	command's argument types are the core's (src/core/Events.luau).

	Positions and colours are plain tables wherever they appear: no value
	is an engine datatype (userdata, vector), a table with an `x`, `y` and
	`z` is exactly { x, y, z } numbers and one with an `r`, `g` and `b`
	exactly { r, g, b } in 0..255; the fields the schema knows to be
	positions or colours (a Spot's `at`, a Zone's `size`, a `tint`) must be.
]]

local Events = require("../../src/core/Events")
local Glossary = require("./glossary")

type Set = { [string]: boolean }

export type Schema = {
	questKinds: Set,
	speakers: Set,
	-- Character -> its glossary row's Kind, Display name and Home Spot
	characters: { [string]: { kind: string, display: string, home: string } },
	hooks: Set,
	beats: Set,
	-- Spot or Zone -> its Scene
	spots: { [string]: string },
	zones: { [string]: string },
	scenes: Set,
	-- Prop -> its states in order
	props: { [string]: { string } },
	lighting: Set,
	cues: Set,
	shots: Set,
	-- World command -> the arguments the glossary gives it
	commands: { [string]: Set },
}

local Schema = {}

-- Reads the enumerations from the glossary's text.
function Schema.fromGlossary(text: string): Schema
	local glossary = Glossary.parse(text)

	-- the first backticked value of a cell, without its prefix
	local function first(cell: string?): string
		return Glossary.name(Glossary.values(cell)[1] or "")
	end

	-- name -> the first value of a column, for the rows in use
	local function column(heading: string, header: string): { [string]: string }
		local map = {}
		for _, entry in glossary.inUse(heading) do
			map[entry.name] = first(entry.cells[header])
		end
		return map
	end

	local schema: Schema = {
		questKinds = glossary.names("Quest kinds"),
		speakers = glossary.names("Characters and Speakers"),
		characters = {},
		hooks = glossary.names("Hook names"),
		beats = glossary.names("Beats"),
		spots = column("Spots", "Scene"),
		zones = column("Zones", "Scene"),
		scenes = glossary.names("Scenes"),
		props = {},
		lighting = glossary.names("Lighting presets"),
		cues = glossary.names("Cues"),
		shots = glossary.names("Shots"),
		commands = {},
	}
	for _, entry in glossary.inUse("Characters and Speakers") do
		if entry.id ~= entry.name then -- the Narrator is a Speaker, not a Character
			schema.characters[entry.name] = {
				kind = first(entry.cells.Kind),
				display = entry.cells["Display name"] or "",
				home = first(entry.cells["Home Spot"]),
			}
		end
	end
	for _, entry in glossary.inUse("Props") do
		schema.props[entry.name] = Glossary.values(entry.cells["States, in order"])
	end
	for _, entry in glossary.inUse("World commands") do
		local args = {}
		for _, arg in Glossary.values(entry.cells.Arguments) do
			args[arg] = true
		end
		schema.commands[entry.name] = args
	end
	return schema
end

-- Validation ------------------------------------------------------------

type Report = (where: string, message: string) -> ()
type Check = (value: any, where: string, report: Report) -> ()

local function show(value: any): string
	return if type(value) == "string" then string.format("%q", value) else tostring(value)
end

local function text(value: any, where: string, report: Report)
	if type(value) ~= "string" or value == "" then
		report(where, `must be non-empty text, got {show(value)}`)
	end
end

local function number(value: any, where: string, report: Report)
	if type(value) ~= "number" then
		report(where, `must be a number, got {show(value)}`)
	end
end

local function isTrue(value: any, where: string, report: Report)
	if value ~= true then
		report(where, `is true or absent, got {show(value)}`)
	end
end

local function channel(value: any, where: string, report: Report)
	if type(value) ~= "number" or value < 0 or value > 255 then
		report(where, `must be a colour channel, 0 to 255, got {show(value)}`)
	end
end

local function optional(check: Check): Check
	return function(value, where, report)
		if value ~= nil then
			check(value, where, report)
		end
	end
end

-- A value that must be one of `set`'s names (a glossary enumeration).
local function oneOf(set: { [string]: any }, what: string): Check
	return function(value, where, report)
		if type(value) ~= "string" or set[value] == nil then
			report(where, `{show(value)} is not a {what} in docs/GLOSSARY.md`)
		end
	end
end

local function list(item: Check): Check
	return function(value, where, report)
		if type(value) ~= "table" or #value == 0 then
			report(where, "must be a non-empty list")
			return
		end
		for key, entry in value do
			if type(key) ~= "number" then
				report(`{where}.{tostring(key)}`, "is not a list item")
			else
				item(entry, `{where}[{key}]`, report)
			end
		end
	end
end

-- A table keyed by `key`'s names, each value checked by `item`.
local function map(key: Check, item: Check): Check
	return function(value, where, report)
		if type(value) ~= "table" then
			report(where, "must be a table")
			return
		end
		for name, entry in value do
			local at = `{where}.{tostring(name)}`
			key(name, at, report)
			item(entry, at, report)
		end
	end
end

-- A closed record: every field in `fields` checked, any other field an error.
-- With `open`, other fields are allowed (and only the plain-value rule
-- applies to them).
local function record(fields: { [string]: Check }, open: boolean?): Check
	return function(value, where, report)
		if type(value) ~= "table" then
			report(where, "must be a table")
			return
		end
		for name, check in fields do
			check(value[name], `{where}.{name}`, report)
		end
		if not open then
			for name in value do
				if fields[name] == nil then
					report(`{where}.{tostring(name)}`, "is not a field the content schema knows")
				end
			end
		end
	end
end

local function ignore() end

local vec3 = record({ x = number, y = number, z = number })
local rgb = record({ r = channel, g = channel, b = channel })

-- Every value under `value` is plain: no engine datatypes, and positions and
-- colours shaped as Vec3 and RGB tables.
local function plain(value: any, where: string, report: Report, seen: { [any]: boolean })
	local kind = typeof(value)
	if kind == "userdata" or kind == "vector" or kind == "buffer" or kind == "thread" then
		report(where, `is a {kind}; positions and colours are plain tables ({"{x, y, z}"}, {"{r, g, b}"})`)
		return
	elseif kind ~= "table" or seen[value] then
		return
	end
	seen[value] = true
	if value.x ~= nil and value.y ~= nil and value.z ~= nil then
		vec3(value, where, report)
	elseif value.r ~= nil and value.g ~= nil and value.b ~= nil then
		rgb(value, where, report)
	end
	for key, item in value do
		plain(item, if type(key) == "number" then `{where}[{key}]` else `{where}.{tostring(key)}`, report, seen)
	end
end

-- The shapes ------------------------------------------------------------

local function lines(schema: Schema): Check
	return list(record({ speaker = oneOf(schema.speakers, "Speaker"), text = text, canon = optional(isTrue) }))
end

-- A World command in a Beat: a kind the glossary lists, exactly the
-- arguments it gives that kind, each of its type in Events and naming
-- something the glossary has.
local function command(schema: Schema): Check
	local names: { [string]: Check } = {
		character = oneOf(schema.characters, "Character"),
		spot = oneOf(schema.spots, "Spot"),
		pickup = oneOf(schema.spots, "Spot"),
		prop = oneOf(schema.props, "Prop"),
		preset = oneOf(schema.lighting, "Lighting preset"),
		cue = oneOf(schema.cues, "Cue"),
		shot = oneOf(schema.shots, "Shot"),
	}
	local byKind: { [string]: Check } = {}

	local function shape(kind: string): Check
		local fields: { [string]: Check } = { kind = ignore }
		local types: { [string]: Events.FieldType } = Events.WORLD_COMMANDS[kind] or {}
		for arg, fieldType in types do
			fields[arg] = function(value, where, report)
				if not schema.commands[kind][arg] then
					report(where, `is an argument docs/GLOSSARY.md does not give {kind}`)
				elseif not Events.matches(fieldType, value) then
					report(where, `must be {fieldType}, got {show(value)}`)
				elseif value ~= nil and names[arg] then
					names[arg](value, where, report)
				end
			end
		end
		for arg in schema.commands[kind] do
			if not fields[arg] then
				fields[arg] = function(_, where, report)
					report(where, `is an argument docs/GLOSSARY.md gives {kind} but src/core/Events.luau does not`)
				end
			end
		end
		return record(fields)
	end

	return function(value, where, report)
		if type(value) ~= "table" then
			report(where, "must be a World command table")
			return
		end
		local kind = value.kind
		if type(kind) ~= "string" or not schema.commands[kind] then
			report(`{where}.kind`, `{show(kind)} is not a World command in docs/GLOSSARY.md`)
			return
		end
		byKind[kind] = byKind[kind] or shape(kind)
		byKind[kind](value, where, report)
		local states = value.prop and schema.props[value.prop]
		if value.state ~= nil and states and not table.find(states, value.state) then
			report(`{where}.state`, `{show(value.state)} is not a state of prop:{value.prop} in docs/GLOSSARY.md`)
		end
	end
end

local function chapter(schema: Schema, n: string): Check
	local id = `chapter{n}`
	local dialogue = optional(lines(schema))
	local quest = record({
		id = function(value, where, report)
			if type(value) ~= "string" or not string.match(value, `^{id}%.[a-z0-9_]+$`) then
				report(where, `must read {id}.<snake_case>, got {show(value)}`)
			end
		end,
		kind = oneOf(schema.questKinds, "Quest kind"),
		objective = text,
		character = optional(oneOf(schema.characters, "Character")),
		talkLabel = optional(text),
		zone = optional(oneOf(schema.zones, "Zone")),
		count = optional(number),
		pickups = optional(list(oneOf(schema.spots, "Spot"))),
		intro = dialogue,
		dialogue = dialogue,
		outro = dialogue,
		hooks = optional(map(oneOf(schema.hooks, "Hook name"), list(oneOf(schema.beats, "Beat")))),
	})
	return record({
		id = function(value, where, report)
			if value ~= id then
				report(where, `must be {id}, the Chapter's folder, got {show(value)}`)
			end
		end,
		title = text,
		subtitle = text,
		quests = list(quest),
	})
end

local function beats(schema: Schema): Check
	return map(oneOf(schema.beats, "Beat"), list(command(schema)))
end

local function scene(schema: Schema, file: string): Check
	-- An id this Scene declares: in the glossary, and listed under this Scene.
	local function inScene(set: { [string]: string }, what: string): Check
		local known = oneOf(set, what)
		return function(value, where, report)
			known(value, where, report)
			local listed = set[value]
			if listed and listed ~= file then
				report(where, `{what} {value} is in scene:{listed} in docs/GLOSSARY.md, not scene:{file}`)
			end
		end
	end
	-- A Prop's own placement fields are the adapter's; its states are the glossary's.
	local function propStates(value: any, where: string, report: Report)
		local name = string.match(where, "([^.]+)$") or ""
		local expected = table.concat(schema.props[name] or {}, ", ")
		local states = type(value) == "table" and type(value.states) == "table" and table.concat(value.states, ", ")
		if states ~= expected then
			report(`{where}.states`, `must be prop:{name}'s states in order, {expected}`)
		end
	end
	return record({
		id = function(value, where, report)
			oneOf(schema.scenes, "Scene")(value, where, report)
			if value ~= file then
				report(where, `must be {file}, the Scene's file name, got {show(value)}`)
			end
		end,
		spots = map(inScene(schema.spots, "Spot"), record({ at = vec3, facing = vec3 })),
		zones = map(inScene(schema.zones, "Zone"), record({ centre = vec3, size = vec3 })),
		props = map(oneOf(schema.props, "Prop"), propStates),
	}, true) -- the rest is the layout SceneBuilder builds from
end

local function characters(schema: Schema): Check
	local character = record({
		id = oneOf(schema.characters, "Character"),
		display = text,
		kind = text,
		home = oneOf(schema.spots, "Spot"),
		shirt = optional(rgb),
		player = optional(isTrue),
	})
	return list(function(value, where, report)
		character(value, where, report)
		local listed = type(value) == "table" and schema.characters[value.id]
		if not listed then
			return
		end
		for field, expected in listed :: { [string]: string } do
			if value[field] ~= expected then
				report(
					`{where}.{field}`,
					`character:{value.id} has {field} {show(expected)} in docs/GLOSSARY.md, not {show(value[field])}`
				)
			end
		end
	end)
end

local function presets(schema: Schema): Check
	return map(
		oneOf(schema.lighting, "Lighting preset"),
		record({ saturation = number, contrast = number, tint = rgb, seconds = number })
	)
end

local function ending(schema: Schema): Check
	return record({ lines = lines(schema), title = text, subtitle = text })
end

local function story(schema: Schema): Check
	return record({
		story = record({
			title = text,
			author = text,
			initialLighting = oneOf(schema.lighting, "Lighting preset"),
		}, true),
	}, true)
end

local function helpers(): Check
	return ignore
end

-- Each file's role: its shape, and whether its values are walked for the
-- plain-value rule (Story.luau only assembles the other files, each walked
-- on its own). A pattern's capture (the Chapter number, the Scene) is
-- passed to the shape.
type Role = { shape: (Schema, string) -> Check, plain: boolean }

local ROLES: { [string]: Role } = {
	["Story.luau"] = { shape = story, plain = false },
	["characters.luau"] = { shape = characters, plain = true },
	["presets.luau"] = { shape = presets, plain = true },
	["ending.luau"] = { shape = ending, plain = true },
	-- what content writes positions, colours, Spots and Zones with
	["layout.luau"] = { shape = helpers, plain = true },
	["palette.luau"] = { shape = helpers, plain = true },
}
local PATTERNS: { { pattern: string, role: Role } } = {
	{ pattern = "^chapters/(%d+)/data%.luau$", role = { shape = chapter, plain = true } },
	{ pattern = "^chapters/%d+/(hooks)%.luau$", role = { shape = beats, plain = true } },
	{ pattern = "^scenes/([%w_]+)%.luau$", role = { shape = scene, plain = true } },
}

local function roleOf(path: string): (Role?, string)
	for _, entry in PATTERNS do
		local captured = string.match(path, entry.pattern)
		if captured then
			return entry.role, captured
		end
	end
	return ROLES[path], ""
end

-- The violations in the value a content file returns, as sorted "<path>:
-- <where> <message>" lines; none when it holds to the schema.
function Schema.check(schema: Schema, path: string, value: any): { string }
	local violations, seen = {}, {}
	local function report(where: string, message: string)
		local line = `src/content/{path}: {if where == "" then "the file" else string.gsub(where, "^%.", "")} {message}`
		if not seen[line] then
			seen[line] = true
			table.insert(violations, line)
		end
	end
	local role, captured = roleOf(path)
	if not role then
		report("", "has no shape in the content schema; give it a role in tools/lib/schema.luau")
		return violations
	end
	role.shape(schema, captured)(value, "", report)
	if role.plain then
		plain(value, "", report, {})
	end
	table.sort(violations)
	return violations
end

export type Loaded = { path: string, ok: boolean, value: any }

-- Every .luau file under src/content, by its path there, sorted, with what
-- requiring it returned (or the error, when it does not load under Lune).
function Schema.content(): { Loaded }
	local fs = require("@lune/fs")
	local root = assert(string.match(debug.info(1, "s"), "^(.*)[/\\]tools[/\\]"), "cannot locate the repo")
	-- Content paths are only known at runtime, which the type checker cannot follow.
	local dynamicRequire: any = require
	local loaded = {}
	local function walk(dir: string)
		local entries = fs.readDir(`{root}/src/content/{dir}`)
		table.sort(entries)
		for _, entry in entries do
			local path = dir .. entry
			if fs.isDir(`{root}/src/content/{path}`) then
				walk(path .. "/")
			elseif string.match(entry, "%.luau$") then
				local ok, value = pcall(dynamicRequire, `../../src/content/{string.gsub(path, "%.luau$", "")}`)
				table.insert(loaded, { path = path, ok = ok, value = value })
			end
		end
	end
	walk("")
	return loaded
end

return Schema
