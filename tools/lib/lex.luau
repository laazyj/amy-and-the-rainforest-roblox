--!strict
--[[
	A small Luau lexer for the source guards (tools/lib/purity.luau): names,
	strings and symbols with their line, comments dropped. An interpolated
	string's text segments are strings and the code in its braces is lexed
	as code, so nothing can hide in a `{...}`. Numbers are skipped; the
	guards never look at them.
]]

export type Kind = "name" | "string" | "symbol"
export type Token = { kind: Kind, value: string, line: number }

local Lex = {}

local SYMBOLS2: { [string]: boolean } = {}
for _, symbol in { "..", "::", "==", "~=", "<=", ">=", "->", "//" } do
	SYMBOLS2[symbol] = true
end

function Lex.tokens(source: string): { Token }
	local tokens: { Token } = {}
	local i, line, n = 1, 1, #source
	-- one entry per interpolated string we are inside: the brace depth of its code
	local interpolations: { number } = {}

	local function add(kind: Kind, value: string, at: number)
		table.insert(tokens, { kind = kind, value = value, line = at })
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
				add("string", table.concat(text), start)
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
