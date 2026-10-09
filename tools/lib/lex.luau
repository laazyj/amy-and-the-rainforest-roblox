--!strict
--[[
	A small Luau lexer for the source guards (tools/lib/purity.luau): names,
	strings and symbols with their line, comments dropped. An interpolated
	string's text segments are strings and the code in its braces is lexed
	as code, so nothing can hide in a `{...}`. A string token keeps its
	escapes as written; `Lex.decode` gives the text they stand for. Numbers
	are skipped; the guards never look at them.
]]

export type Kind = "name" | "string" | "symbol"
-- `value` is as written; `text` is what it stands for: a quoted or
-- interpolated string's escapes decoded (Lex.decode), anything else as written.
export type Token = { kind: Kind, value: string, text: string, line: number }

local Lex = {}

local SYMBOLS2: { [string]: boolean } = {}
for _, symbol in { "..", "::", "==", "~=", "<=", ">=", "->", "//" } do
	SYMBOLS2[symbol] = true
end

local ESCAPES: { [string]: string } = {
	n = "\n",
	t = "\t",
	r = "\r",
	a = "\a",
	b = "\b",
	f = "\f",
	v = "\v",
}

-- Each escape after a backslash: its pattern (ending in the position after
-- it) and what it decodes to. Tried in order; the last matches any character.
local DECODERS: { { pattern: string, decode: (string) -> string } } = {
	{
		pattern = "^(%d%d?%d?)()",
		decode = function(digits)
			return string.char(math.min(tonumber(digits) :: number, 255))
		end,
	},
	{
		pattern = "^x(%x%x)()",
		decode = function(hex)
			return string.char(tonumber(hex, 16) :: number)
		end,
	},
	{
		pattern = "^u{(%x+)}()",
		decode = function(code)
			return utf8.char(math.min(tonumber(code, 16) :: number, 0x10FFFF))
		end,
	},
	{
		pattern = "^(z)%s*()",
		decode = function()
			return ""
		end,
	},
	{
		pattern = "^(.)()",
		decode = function(c)
			return ESCAPES[c] or c
		end,
	},
}

-- The text a quoted string's escapes stand for: `\65`, `\x41` and `\u{41}`
-- are all "A"; `\z` skips the whitespace after it.
function Lex.decode(raw: string): string
	local out, i = {}, 1
	while i <= #raw do
		local slash = string.find(raw, "\\", i, true)
		if not slash then
			table.insert(out, string.sub(raw, i))
			break
		end
		table.insert(out, string.sub(raw, i, slash - 1))
		i = slash + 1
		for _, decoder in DECODERS do
			local captured, after = string.match(raw, decoder.pattern, i)
			if captured then
				table.insert(out, decoder.decode(captured))
				i = after :: any
				break
			end
		end
	end
	return table.concat(out)
end

function Lex.tokens(source: string): { Token }
	local tokens: { Token } = {}
	local i, line, n = 1, 1, #source
	-- one entry per interpolated string we are inside: the brace depth of its code
	local interpolations: { number } = {}

	local function add(kind: Kind, value: string, at: number, text: string?)
		table.insert(tokens, { kind = kind, value = value, text = text or value, line = at })
	end

	-- Moves past `text`, counting its lines.
	local function consume(text: string)
		line += select(2, string.gsub(text, "\n", ""))
		i += #text
	end

	-- The `[==[ ... ]==]` long bracket at `i`: its whole text and its body.
	local function longBracket(): (string?, string)
		local equals = string.match(source, "^%[(=*)%[", i)
		if not equals then
			return nil, ""
		end
		local open = i + #equals + 2
		local close = string.find(source, `]{equals}]`, open, true)
		local stop = if close then close + #equals + 1 else n
		return string.sub(source, i, stop), string.sub(source, open, (close or n + 1) - 1)
	end

	-- A string token from `i` up to the first unescaped character of `stops`
	-- (a pattern set), leaving `i` on it; returns it, or nil at the end.
	local function scanString(stops: string): string?
		local start, text = line, {}
		while true do
			local found = string.find(source, `[\\{stops}]`, i) or n + 1
			local chunk = string.sub(source, i, found - 1)
			table.insert(text, chunk)
			consume(chunk)
			local stop = string.sub(source, found, found)
			if stop ~= "\\" then
				local raw = table.concat(text)
				add("string", raw, start, Lex.decode(raw))
				return if stop == "" then nil else stop
			end
			local escape = string.sub(source, found, found + 1)
			table.insert(text, escape)
			consume(escape)
		end
	end

	-- An interpolated string's text from `i` to its end or its next `{`.
	local function interpolated()
		local stop = scanString("`{")
		if stop then
			i += 1
			if stop == "{" then
				table.insert(interpolations, 0)
			end
		end
	end

	while i <= n do
		local c = string.sub(source, i, i)
		if string.match(c, "%s") then
			consume(c)
		elseif string.sub(source, i, i + 1) == "--" then
			i += 2
			local whole = longBracket()
			consume(whole or string.match(source, "^[^\n]*", i) :: string)
		elseif c == "[" and longBracket() then
			local whole, body = longBracket()
			add("string", (string.gsub(body, "^\n", "")), line)
			consume(whole :: string)
		elseif c == '"' or c == "'" then
			i += 1
			if scanString(c .. "\n") == c then
				i += 1
			end
		elseif c == "`" then
			i += 1
			interpolated()
		elseif #interpolations > 0 and c == "}" and interpolations[#interpolations] == 0 then
			table.remove(interpolations)
			i += 1
			interpolated()
		elseif string.match(c, "[%a_]") then
			local name = string.match(source, "^[%w_]+", i) :: string
			add("name", name, line)
			i += #name
		elseif string.match(c, "%d") or (c == "." and string.match(source, "^%.%d", i)) then
			i += #(string.match(source, "^%.?[%w_%.]*", i) :: string)
			-- an exponent's sign: 1e-5
			if string.match(string.sub(source, i - 1, i), "^[eE][%+%-]") then
				i += 1 + #(string.match(source, "^[%w_]*", i + 1) :: string)
			end
		else
			local symbol = if string.sub(source, i, i + 2) == "..."
				then "..."
				elseif SYMBOLS2[string.sub(source, i, i + 1)] then string.sub(source, i, i + 1)
				else c
			if #interpolations > 0 then
				if symbol == "{" then
					interpolations[#interpolations] += 1
				elseif symbol == "}" then
					interpolations[#interpolations] -= 1
				end
			end
			add("symbol", symbol, line)
			i += #symbol
		end
	end
	return tokens
end

return Lex
