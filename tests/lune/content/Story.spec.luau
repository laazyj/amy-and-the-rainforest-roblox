--[[
	The Story walked through the core, as tier 1 (plan section 4): every
	Chapter completable from a fresh start and from a Resume at every Quest,
	the World a Resume rebuilds equal to the World the walk had there, no
	dead ends, the Beats' World commands, and every message the client gets,
	in order, equal to the golden file the engine walkthrough records
	(tests/fixtures/golden/walkthrough.json).
]]

local Net = require("../../../src/core/Net")
local StoryEngine = require("../../../src/core/StoryEngine")
local StoryModule = require("../../../src/core/Story")
local Story = require("../../../src/content/Story")
local Golden = require("../../engine/_golden")
local Walker = require("../core/walker")
local bootstrap = require("../bootstrap")

local story = Story.story

local walk = Walker.walk(story)

-- The golden file's lines, rebuilt from the walk: each command that reaches
-- the client, with the Quest active after the step that sent it.
local sent: { string } = {}
for _, step in walk.steps do
	for _, command in step.commands do
		local remote, args = Net.message(command)
		if remote and args then
			assert(Net.check(remote, args))
			table.insert(sent, Golden.messageLine(remote, step.quest, args))
		end
	end
end

local golden = Golden.lines(bootstrap.readSource("tests/fixtures/golden/walkthrough.json"))

-- The commands of the step that played `beat`.
local function stepPlaying(beat: string): Walker.Step?
	for _, step in walk.steps do
		for _, event in step.events do
			if event.kind == "BeatPlayed" and (event :: any).beat == beat then
				return step
			end
		end
	end
	return nil
end

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("the Story from a fresh start", function()
		it("reaches the Ending", function()
			expect(walk.progress.ended).toBe(true)
		end)

		it("completes every Quest, in story order", function()
			local ids = {}
			for _, placed in StoryModule.quests(story) do
				table.insert(ids, placed.quest.id)
			end
			expect(walk.progress.completed).toEqual(ids)
		end)

		it("leaves no Pickups and no talk affordance behind", function()
			local all = {}
			for _, step in walk.steps do
				table.move(step.commands, 1, #step.commands, #all + 1, all)
			end
			local world = Walker.rebuild(story, all)
			expect(world.pickups).toEqual({})
			expect(world.talk).toEqual({})
			expect(world.objective).toBeNil()
		end)

		it(`sends the client the {#golden} messages of the golden file, in order`, function()
			for i = 1, math.max(#golden, #sent) do
				if golden[i] ~= sent[i] then
					error(`message {i}:\n  golden: {golden[i]}\n  sent:   {sent[i]}`)
				end
			end
		end)
	end)

	for _, placed in StoryModule.quests(story) do
		local quest = placed.quest
		local playable = walk.playable[quest.id]

		describe(`a Resume at {quest.id}`, function()
			local resumed = Walker.rebuild(story, StoryEngine.resume(story, playable.progress))

			it("rebuilds the World the walk had there", function()
				expect(resumed).toEqual(Walker.withoutPlayer(playable.world))
			end)

			it("completes the Story from there", function()
				expect(Walker.walk(story, playable.progress, Walker.deepCopy(resumed)).progress.ended).toBe(true)
			end)
		end)
	end

	describe("the Beats", function()
		it("plays beat sam_catches and teleports Amy to spot GardenInside on EnteredZone(GardenGate)", function()
			local step = assert(stepPlaying("sam_catches"), "sam_catches never played")
			expect(step.event).toEqual({ kind = "DialogueFinished" })
			expect(table.find(step.commands, story.chapters[1].beats.sam_catches[1])).never.toBeNil()
			expect(Walker.kinds(step.commands)).toContain("TeleportPlayer")
			local world = Walker.rebuild(story, step.commands)
			expect(world.player).toBe("GardenInside")
			expect(world.characters.Sam).toBe("SamGuardPost")
		end)

		it("plays beat sam_catches after both sneak-outs, waiting 0.5 s and 0.4 s each time", function()
			local waits = {}
			for _, step in walk.steps do
				for _, command in step.commands do
					if command.kind == "Wait" then
						table.insert(waits, command.seconds)
					end
				end
			end
			-- a Chapter card's 3.2 s for each Chapter, Sam's catch twice in Chapter One
			expect(waits).toEqual({ 3.2, 0.5, 0.4, 0.5, 0.4, 3.2, 3.2, 3.2 })
		end)

		it("plays beat sam_goes_to_farm when chapter2.walk_to_forest starts, before its Objective", function()
			local step = assert(stepPlaying("sam_goes_to_farm"), "never played")
			local kinds = Walker.kinds(step.commands)
			local moved = table.find(kinds, "MoveCharacter")
			local objective = table.find(kinds, "SetObjective")
			expect(moved and objective and moved < objective).toBe(true)
			expect(Walker.rebuild(story, step.commands).characters.Sam).toBe("Farm")
		end)

		it("plays beat paradise_reveal and beat ordinary_world as Lighting presets", function()
			expect(Walker.rebuild(story, assert(stepPlaying("paradise_reveal"), "never played").commands).lighting).toBe(
				"paradise"
			)
			expect(Walker.rebuild(story, assert(stepPlaying("ordinary_world"), "never played").commands).lighting).toBe(
				"ordinary"
			)
		end)

		it("plays beat machine_arrives: the machine and villagers arrive, Dad, Mum and Sam go to the field", function()
			local world = Walker.rebuild(story, assert(stepPlaying("machine_arrives"), "never played").commands)
			expect(world.props).toEqual({ Machine = "advancing", Villagers = "gathered" })
			expect(world.characters.Dad).toBe("DadAtMachine")
			expect(world.characters.Mum).toBe("MumAtMachine")
		end)

		it("plays beat machine_stops: the blade stops, the crowd cheers, the machine reverses away", function()
			local step = assert(stepPlaying("machine_stops"), "never played")
			local states = {}
			for _, command in step.commands do
				if command.kind == "SetPropState" then
					table.insert(states, `{command.prop}:{command.state}`)
				end
			end
			expect(states).toEqual({ "Machine:stopped", "Villagers:cheering", "Machine:retreating" })
		end)
	end)
end
