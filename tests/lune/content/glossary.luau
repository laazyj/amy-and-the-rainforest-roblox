--[[
	docs/GLOSSARY.md's tables, read by the same parser the tier 0 content
	schema uses (tools/lib/glossary.luau).
]]

local Glossary = require("../../../tools/lib/glossary")
local bootstrap = require("../bootstrap")

export type Entry = Glossary.Entry

return Glossary.parse(bootstrap.readSource("docs/GLOSSARY.md"))
