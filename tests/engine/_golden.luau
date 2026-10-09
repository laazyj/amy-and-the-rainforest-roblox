--!strict
-- The golden file's format, shared by the engine walkthrough
-- (include("tests/engine/_golden.luau")) and the tier 1 Story spec
-- (require). One message per line of a JSON array: the remote, its
-- arguments (nil kept as null) and the active Quest's id, keys sorted.

-- JSON with sorted keys. Strings keep their UTF-8 bytes; control characters,
-- quotes and backslashes are escaped.
local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encode(value: any): string
	local kind = type(value)
	if value == nil then
		return "null"
	elseif kind == "string" then
		local escaped = string.gsub(value, '[%c"\\]', function(char)
			return ESCAPES[char] or string.format("\\u%04x", string.byte(char))
		end)
		return `"{escaped}"`
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "number" then
		return if value % 1 == 0 then string.format("%d", value) else string.format("%.17g", value)
	elseif kind == "table" then
		local parts = {}
		if #value > 0 then
			for i, item in value do
				assert(type(i) == "number", "a table mixes array and object keys")
				parts[i] = encode(item)
			end
			return `[{table.concat(parts, ",")}]`
		end
		local keys = {}
		for key in value do
			assert(type(key) == "string", "object keys must be strings")
			table.insert(keys, key)
		end
		table.sort(keys)
		for i, key in keys do
			parts[i] = `{encode(key)}:{encode(value[key])}`
		end
		return `\{{table.concat(parts, ",")}}`
	end
	error(`cannot encode a {typeof(value)}`)
end

local Golden = {}

-- One message as one line of the golden file.
function Golden.messageLine(remote: string, questId: string?, args: { n: number, [number]: any }): string
	local parts = {}
	for i = 1, args.n do
		parts[i] = encode(args[i])
	end
	return `\{"args":[{table.concat(parts, ",")}],"quest":{encode(questId)},"remote":{encode(remote)}}`
end

-- The message lines of a golden file's text.
function Golden.lines(text: string): { string }
	local lines = {}
	for line in string.gmatch(text, "[^\n]+") do
		line = string.gsub(line, ",$", "")
		if line ~= "[" and line ~= "]" then
			table.insert(lines, line)
		end
	end
	return lines
end

return Golden
