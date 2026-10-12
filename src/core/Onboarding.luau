--!strict
--[[
	Onboarding: the first minute, which teaches the three verbs (walk,
	talk, advance) inside Chapter One, as a view-model (docs/design/feel.md
	section 6). The client binder feeds it what it sees and renders what
	`view` returns; it never blocks play.

	The Onboarding steps, in order, and when each is done:

	  card       the chapter1 card (tap or click skips it)   the card is gone
	  advance    the first Narrator Line, its Hint large      DialogueFinished
	  objective  the first Objective; the tracker glows       it is shown
	  walk       Amy in the garden; walk and turn Hints       she has moved 4 studs
	  talk       Dad's talk prompt; the talk Hint             TalkedTo(Dad): his
	                                                          Dialogue arrives
	  listen     Dad's Dialogue, then the next Objective     the next Objective

	A step's Hint shows while it is the current step and is needed (the
	talk Hint once a prompt is shown), hides as soon as the player makes
	progress (Amy starts to walk), comes back after 10 seconds without
	progress, and is gone when the step is done. Talking to Dad also does
	the walk step. The Skip button ends the Onboarding.

	Shown once per Save, from what the client already receives: a Story
	that begins with its first Chapter card is a fresh Save (a new player,
	or "Start again"); one that begins with an Objective is a Resume, and
	never shows the Onboarding. No Save field and no new remote.

	  new(story)                  waiting for the Story's first message
	  chapterShown(vm, title)     ShowChapter
	  objectiveShown(vm, text)    SetObjective
	  cardGone(vm)                the Chapter card has faded
	  dialogueShown(vm)           ShowDialogue
	  dialogueFinished(vm)        the player advanced past a Dialogue's last Line
	  moved(vm, studs)            Amy walked this far
	  promptShown(vm, shown)      whether a talk prompt shows
	  tick(vm, seconds)           time passes
	  skip(vm)                    the Skip button
	  view(vm, hints, touch)      what shows now, the dialogue box's hint row
	                              included
]]

-- An Onboarding step's name: "card", "advance", "objective", "walk",
-- "talk" or "listen" (Onboarding.STEPS).
export type Step = string
export type State = "waiting" | "running" | "finished"

local Story = require("./Story")

-- A step's Hint for each input: on touch some steps show the control
-- instead of words (the talk step pulses the Talk-and-advance button).
export type Hint = { pc: string, touch: string? }
-- src/content/hints: each step's Hint, and the box's standing hint after
-- the Onboarding.
export type Hints = { steps: { [Step]: Hint }, continue: { pc: string, touch: string } }

export type Onboarding = {
	state: State,
	-- the Story's first Chapter's title, and its first Quest's Character
	firstChapter: string,
	character: string?,
	done: { [Step]: true },
	-- the current step, an index into Onboarding.STEPS
	step: number,
	-- whether the player has made progress on the current step, and the
	-- seconds since the step began or since that progress
	progressed: boolean,
	idle: number,
	moved: number,
	dialogues: number,
	objective: string?,
	prompt: boolean,
	-- seconds left of the Objective tracker's glow
	glow: number,
}

export type View = {
	step: Step?,
	-- the Hint's words, or nil when none shows
	hint: string?,
	-- touch: the glowing ring on the thumbstick, the pulsing Talk-and-advance button
	ring: boolean,
	pulse: boolean,
	-- the Character the marker is over: the first Quest's, from the first
	-- Objective until Amy talks to them
	marker: string?,
	-- the dialogue box's hint row, and whether it is the large Hint
	row: string,
	large: boolean,
	glow: boolean,
	-- the Skip button: with a Hint in free play
	skip: boolean,
}

local Onboarding = {}

Onboarding.STEPS = table.freeze({ "card", "advance", "objective", "walk", "talk", "listen" } :: { Step })
Onboarding.RETURN_SECONDS = 10
Onboarding.WALK_STUDS = 4
Onboarding.GLOW_SECONDS = 1.2

local OBJECTIVE = table.find(Onboarding.STEPS, "objective") :: number

function Onboarding.new(story: Story.Story): Onboarding
	local first = story.chapters[1]
	return {
		state = "waiting",
		firstChapter = first.title,
		character = first.quests[1].character,
		done = {},
		step = 1,
		progressed = false,
		idle = 0,
		moved = 0,
		dialogues = 0,
		objective = nil,
		prompt = false,
		glow = 0,
	}
end

local function running(vm: Onboarding): boolean
	return vm.state == "running"
end

-- Moves past every step that is done; the Onboarding ends after the last.
local function settle(vm: Onboarding)
	local from = vm.step
	while vm.step <= #Onboarding.STEPS and vm.done[Onboarding.STEPS[vm.step]] do
		vm.step += 1
	end
	if vm.step ~= from then
		vm.progressed, vm.idle = false, 0
		if from <= OBJECTIVE and vm.step > OBJECTIVE then
			vm.glow = Onboarding.GLOW_SECONDS
		end
	end
	if vm.step > #Onboarding.STEPS then
		vm.state = "finished"
	end
end

local function complete(vm: Onboarding, step: Step)
	if running(vm) then
		vm.done[step] = true
		settle(vm)
	end
end

-- The Story's first message decides: its first Chapter card starts the
-- Onboarding; anything else is a Resume.
local function begins(vm: Onboarding, fresh: boolean)
	if vm.state == "waiting" then
		vm.state = if fresh then "running" else "finished"
	end
end

function Onboarding.chapterShown(vm: Onboarding, title: string)
	begins(vm, title == vm.firstChapter)
end

function Onboarding.objectiveShown(vm: Onboarding, text: string?)
	begins(vm, false)
	if not running(vm) or not text or text == "" or text == vm.objective then
		return
	end
	if vm.objective then
		vm.state = "finished" -- the next Objective: the first Quest is complete
	else
		vm.objective = text
		complete(vm, "objective")
	end
end

function Onboarding.cardGone(vm: Onboarding)
	complete(vm, "card")
end

function Onboarding.dialogueShown(vm: Onboarding)
	if running(vm) then
		vm.dialogues += 1
		if vm.dialogues > 1 then -- the talk Quest's Dialogue follows TalkedTo
			vm.done.walk = true
			complete(vm, "talk")
		end
	end
end

function Onboarding.dialogueFinished(vm: Onboarding)
	if running(vm) and vm.dialogues == 1 then
		complete(vm, "advance")
	end
end

function Onboarding.moved(vm: Onboarding, studs: number)
	if not running(vm) or studs <= 0 then
		return
	end
	vm.moved += studs
	if Onboarding.STEPS[vm.step] == "walk" then
		vm.progressed, vm.idle = true, 0
	end
	if vm.moved >= Onboarding.WALK_STUDS then
		complete(vm, "walk")
	end
end

function Onboarding.promptShown(vm: Onboarding, shown: boolean)
	vm.prompt = shown
end

function Onboarding.tick(vm: Onboarding, seconds: number)
	vm.idle += seconds
	vm.glow = math.max(0, vm.glow - seconds)
end

function Onboarding.skip(vm: Onboarding)
	vm.state = "finished"
end

function Onboarding.view(vm: Onboarding, hints: Hints, touch: boolean): View
	local continue = if touch then hints.continue.touch else hints.continue.pc
	if not running(vm) then
		return {
			step = nil,
			hint = nil,
			ring = false,
			pulse = false,
			marker = nil,
			row = continue,
			large = false,
			glow = false,
			skip = false,
		}
	end
	local step = Onboarding.STEPS[vm.step]
	local needed = step ~= "talk" or vm.prompt
	local showing = needed and (not vm.progressed or vm.idle >= Onboarding.RETURN_SECONDS)
	local hint = hints.steps[step]
	local words = if hint and showing then (if touch then hint.touch else hint.pc) else nil
	local ring = touch and showing and step == "walk"
	local pulse = touch and showing and step == "talk"
	-- the advance step's Hint shows large, in the dialogue box's hint row
	local large = step == "advance" and words ~= nil
	return {
		step = step,
		hint = if large then nil else words,
		ring = ring,
		pulse = pulse,
		marker = if vm.objective ~= nil and not vm.done.talk then vm.character else nil,
		row = if large then words :: string else continue,
		large = large,
		glow = vm.glow > 0,
		-- free play only: the first Line's Hint is skipped by tapping
		skip = not large and (words ~= nil or ring or pulse),
	}
end

return Onboarding
