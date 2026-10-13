--!strict
--[[
	The Roblox compliance guards of plan section 6 (Phase 1, "Roblox
	compliance") that read text rather than Luau source:

	No surname: the author is "Clara" only, in credits and everywhere else
	(docs/story/style-guide.md section 4), so no surname of the family
	appears in the game's source, its assets' text or the store page kit.
	SURNAMES lists them; the owner adds one by adding a line. A surname
	matches anywhere, in any case, joined to other words or not: "Smith",
	"ClaraSmith" and "SMITHS" all match. ALLOWED lists the exact strings a
	file may hold that contain one: the Manifest's provenance, the owner's
	own repository, which is never built into the place.

	No web address: a scheme (`https://`), a `www.` host, a bare domain
	ending in a common top-level domain (`roblox.com/games/1`,
	`discord.gg/x`, `amyforest.co.uk`), an email address or handle (`@`),
	or a dot written out (`example[.]com`, `(dot)`). A bare domain needs a
	top-level domain from a short list, so ids such as `chapter3.meet_fox` and
	file names such as `Story.luau` are not addresses. The store page kit
	is held to it here; Luau text is tools/lib/purity.luau's check, which
	asks `isLink` too.

	Nothing to buy and nothing to write: no Luau under src/ reaches
	MarketplaceService or prompts a purchase, and none makes a TextBox, so
	a player can neither spend nor type anything another could see. The
	Experience Guidelines answers in docs/store/questionnaire.md rest on
	these.

	`tools/guard names`, `tools/guard store-links` and `tools/guard
	purchases-and-text` run them in tier 0.
]]

local Compliance = {}

-- The family's surnames, as they would be written. Extend this list to
-- guard another name.
Compliance.SURNAMES = { "Dineen", "Duffett" }

-- Where no surname may appear: the game's source, its assets' text (the
-- Manifest) and the store page kit.
Compliance.NAMED = { "src", "assets", "docs/store" }

-- Where no web address may appear, in any text.
Compliance.UNLINKED = { "docs/store" }

-- The text files the guards read; images and models are not text.
local TEXT = { "%.luau$", "%.json$", "%.md$", "%.txt$", "%.csv$" }

-- Exact strings a file may hold although they contain a surname: the
-- Manifest's provenance names the owner's own repository.
Compliance.ALLOWED = {
	["assets/manifest.json"] = { "laazyj/jasonduffett.net" },
} :: { [string]: { string } }

-- The top-level domains a bare domain is recognised by.
local DOMAINS: { [string]: true } = {}
for _, domain in
	string.split(
		"com net org gg io co uk tv me ly app dev xyz info biz us ca au ie nz gl link site online edu gov",
		" "
	)
do
	DOMAINS[domain] = true
end

-- What reads as a web address, in lowercased text: a scheme, a www. host,
-- an `@` before a name, or a dot written out; and (in isLink) a word, a
-- dot and one of DOMAINS, as a whole word.
local LINK_PATTERNS = { "https?://", "%f[%w]www%.", "@%w", "%[%.%]", "[%(%[]dot[%)%]]" }

-- Whether `text` holds a web address, in any case; tools/lib/purity.luau
-- asks the same of Luau's strings.
function Compliance.isLink(text: string): boolean
	local lower = string.lower(text)
	for _, pattern in LINK_PATTERNS do
		if string.find(lower, pattern) then
			return true
		end
	end
	-- each word, a dot and a name after it, overlapping ("a.b.com")
	local from = 1
	while true do
		local at, _, domain = string.find(lower, "%w%.(%a+)%f[^%w_]", from)
		if not at then
			break
		elseif DOMAINS[domain :: string] then
			return true
		end
		from = at + 1
	end
	return false
end

function Compliance.isText(path: string): boolean
	for _, pattern in TEXT do
		if string.find(path, pattern) then
			return true
		end
	end
	return false
end

-- Every line of `text` that `matches`, as "<path>:<line>: <what> (<the
-- line>)".
local function scan(path: string, text: string, matches: (line: string) -> boolean, what: string): { string }
	local found = {}
	local number = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		number += 1
		if matches(line) then
			local shown = string.gsub(line, "^%s+", "")
			table.insert(found, `{path}:{number}: {what} ({string.sub(shown, 1, 120)})`)
		end
	end
	return found
end

-- The lines of `text` (the file at `path`) that name one of `surnames`,
-- leaving out the strings ALLOWED in that file.
function Compliance.names(path: string, text: string, surnames: { string }?): { string }
	local lowered = {}
	for _, surname in (surnames or Compliance.SURNAMES) :: { string } do
		table.insert(lowered, string.lower(surname))
	end
	local allowed: { string } = Compliance.ALLOWED[path] or {}
	local function named(line: string): boolean
		for _, exact in allowed do
			line = table.concat(string.split(line, exact), "")
		end
		local lower = string.lower(line)
		for _, surname in lowered do
			if string.find(lower, surname, 1, true) then
				return true
			end
		end
		return false
	end
	return scan(path, text, named, `a surname; credits say "Clara" only`)
end

-- What a purchase or free text needs, in Luau.
local SHOP_PATTERNS = { "marketplaceservice", "prompt%a*purchase", "%f[%a]textbox%f[%A]" }

local function sellsOrTakesText(line: string): boolean
	local lower = string.lower(line)
	for _, pattern in SHOP_PATTERNS do
		if string.find(lower, pattern) then
			return true
		end
	end
	return false
end

-- The lines of `source` (Luau, the file at `path`) that reach a purchase
-- or make a TextBox; comments count too, which is simpler and stricter.
function Compliance.purchasesAndText(path: string, source: string): { string }
	return scan(path, source, sellsOrTakesText, "a purchase or free text; the game sells nothing and takes no writing")
end

-- The lines of `text` (the file at `path`) that hold a web address.
function Compliance.links(path: string, text: string): { string }
	return scan(path, text, Compliance.isLink, "a web address; the store page links to nothing")
end

return Compliance
