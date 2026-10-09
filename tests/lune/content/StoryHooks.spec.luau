--[[
	StoryServer runs its Beats (Sam's catch, the paradise reveal, the machine)
	from tables keyed by bare quest id. Renaming a quest in StoryData would
	silently stop its Beat, so every key must name a quest that exists.
	StoryServer needs the engine, so its source is read as text.
]]

local bootstrap = require("../bootstrap")

local StoryData = bootstrap.loadSource("src/ReplicatedStorage/StoryData.lua")
local serverSource = bootstrap.readSource("src/ServerScriptService/StoryServer/Server.lua")

local HOOK_TABLES = { "questStartedHooks", "questCompletedHooks" }

local questIds = {}
for _, chapter in StoryData.Chapters do
	for _, quest in chapter.quests do
		questIds[quest.id] = true
	end
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	for _, tableName in HOOK_TABLES do
		describe(`StoryServer {tableName}`, function()
			local body = string.match(serverSource, `local {tableName} = (%b\{\})`)

			it("is found in StoryServer", function()
				expect(body).never.toBeNil()
			end)

			for questId in string.gmatch(body or "", "([%w_]+)%s*=") do
				it(`keys quest {questId}, which exists in StoryData`, function()
					expect(questIds[questId]).toBe(true)
				end)
			end
		end)
	end
end
