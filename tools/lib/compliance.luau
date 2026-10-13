--!strict
--[[
	The Roblox compliance guards of plan section 6 (Phase 1, "Roblox
	compliance") that read text rather than Luau source:

	No surname: the author is "Clara" only, in credits and everywhere else
	(docs/story/style-guide.md section 4), so no surname of the family
	appears in the game's source, its assets' text or the store page kit.
	SURNAMES lists them; the owner adds one by adding a line. A surname
	matches as a whole word, in any case: "Smith" and "SMITH" match,
	"Smithson" does not.

	No external links in the store page kit: the description, the art
	specifications and the questionnaire draft are pasted into Roblox, so
	none of them holds a web address. (Links in Luau text are
	tools/lib/purity.luau's check.)

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

-- What reads as a web address: a scheme, or a www. host.
local LINK_PATTERNS = { "https?://", "%f[%w]www%." }

-- Whether `text` holds a web address, in any case; tools/lib/purity.luau
-- asks the same of Luau's strings.
function Compliance.isLink(text: string): boolean
	local lower = string.lower(text)
	for _, pattern in LINK_PATTERNS do
		if string.find(lower, pattern) then
			return true
		end
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

-- The lines of `text` (the file at `path`) that name one of `surnames`.
function Compliance.names(path: string, text: string, surnames: { string }?): { string }
	local patterns = {}
	for _, surname in (surnames or Compliance.SURNAMES) :: { string } do
		local escaped = string.gsub(string.lower(surname), "%p", "%%%0")
		table.insert(patterns, `%f[%a]{escaped}%f[%A]`)
	end
	local function named(line: string): boolean
		local lower = string.lower(line)
		for _, pattern in patterns do
			if string.find(lower, pattern) then
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
