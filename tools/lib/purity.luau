--!strict
--[[
	The source guards of plan section 2.1, over the lexed source (comments
	never count, strings are only text):

	Purity: src/core and src/content never reference `game`, `workspace`,
	`Instance`, `script`, `plugin` or `GetService`, never reach the global
	environment where those can hide (`getfenv`, `setfenv`, `_G`, `shared`,
	`loadstring`, `rawget`), and `require` only a string path that stays
	inside src/core and src/content. Content also holds no engine datatype
	(`Vector3`, `Color3`, `CFrame`, `Enum`...): positions and colours are
	plain tables.

	No external links: no string in content, the core or the client binder
	(the UI's text) holds `http://` or `https://` (the Roblox compliance
	list).
]]

local Lex = require("./lex")

local Purity = {}

-- Purity covers these trees; the links check covers them and the client binder.
Purity.PURE = { "src/core", "src/content" }
Purity.LINKED = { "src/core", "src/content", "src/client" }

-- Name -> why the pure core and content never reference it.
local FORBIDDEN: { [string]: string } = {}
for _, name in { "game", "workspace", "Instance", "script", "plugin" } do
	FORBIDDEN[name] = "never touch the engine"
end
for _, name in { "getfenv", "setfenv", "_G", "shared", "loadstring", "rawget" } do
	FORBIDDEN[name] = "never reach the global environment"
end
local DATATYPES = {
	Vector3 = true,
	Vector2 = true,
	Color3 = true,
	CFrame = true,
	UDim = true,
	UDim2 = true,
	BrickColor = true,
	Enum = true,
}

-- `relative` resolved against the directory of `from`; nil if it climbs out.
local function resolve(from: string, relative: string): string?
	local parts = string.split(from, "/")
	table.remove(parts) -- the file itself
	for _, part in string.split(relative, "/") do
		if part == ".." then
			if #parts == 0 then
				return nil
			end
			table.remove(parts)
		elseif part ~= "." and part ~= "" then
			table.insert(parts, part)
		end
	end
	return table.concat(parts, "/")
end

local function under(path: string, tree: string): boolean
	return string.sub(path, 1, #tree + 1) == `{tree}/`
end

local function inPureTree(path: string): boolean
	for _, tree in Purity.PURE do
		if under(path, tree) then
			return true
		end
	end
	return false
end

-- The purity violations in `source`, the file at `path` (from the
-- repository root), as "<path>:<line>: <message>" lines.
function Purity.check(path: string, source: string): { string }
	local violations = {}
	local function report(line: number, message: string)
		table.insert(violations, `{path}:{line}: {message}`)
	end
	local content = under(path, "src/content")
	local tokens = Lex.tokens(source)
	for i, token in tokens do
		if token.kind ~= "name" then
			continue
		end
		local before = tokens[i - 1]
		local member = before and before.kind == "symbol" and (before.value == "." or before.value == ":")
		local name = token.value
		local why = if name == "GetService" then "never touch the engine" elseif member then nil else FORBIDDEN[name]
		if why then
			report(token.line, `references {name}; the pure core and content {why}`)
		elseif content and DATATYPES[name] and not member then
			report(token.line, `references {name}; content stores positions and colours as plain tables`)
		elseif name == "require" and not member then
			-- require "path" or require("path"), nothing else
			local open, inner, close = tokens[i + 1], tokens[i + 2], tokens[i + 3]
			local argument: string? = nil
			if open and open.kind == "string" then
				argument = open.value
			elseif open and open.value == "(" and inner and inner.kind == "string" and close and close.value == ")" then
				argument = inner.value
			end
			if not argument then
				report(token.line, "requires something other than a string path")
			else
				local target = if string.match(argument, "^%.%.?/") then resolve(path, argument) else nil
				if not target or not inPureTree(target) then
					report(token.line, `requires "{argument}", outside {table.concat(Purity.PURE, " and ")}`)
				end
			end
		end
	end
	return violations
end

-- The strings in `source` (the file at `path`) that hold a link.
function Purity.links(path: string, source: string): { string }
	local violations = {}
	for _, token in Lex.tokens(source) do
		if token.kind == "string" and string.find(string.lower(token.value), "https?://") then
			table.insert(violations, `{path}:{token.line}: a link in text ({token.value}); the game links to nothing`)
		end
	end
	return violations
end

return Purity
