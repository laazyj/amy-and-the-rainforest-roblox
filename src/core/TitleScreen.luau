--!strict
--[[
	TitleScreen: the Title screen as plain data (plan sections 2.1 and 2.3,
	docs/design/feel.md "Title screen"). Two halves:

	The server's: what a returning player is offered, and what each Title
	choice does to their Save.

	  offer(story, save)           nil for a player who has not started:
	                               the Story starts at once, as it always has
	  choose(story, save, choice)  the Save and the Progress to play from

	  continue  a Resume at the current Quest
	  replay    "Play this chapter again": a Resume at the current
	            Chapter's Checkpoint
	  restart   "Start again", behind a confirmation: a new Save, and the
	            Story from its first Chapter card

	The client's: the view-model the client binder renders. The Title
	screen shows from the moment the client loads (it is the loading
	screen too); the choices appear when the server offers them, and it
	closes when a choice is made or the Story's first message arrives.

	  new()               the Title screen, loading: the words, no buttons
	  show(vm, offer)     the server's offer (ShowTitle): the buttons
	  press(vm, button)   a button pressed; the Title choice to send, if any
	  close(vm)           the Story has begun
	  view(vm)            what the Title screen shows now
]]

local Save = require("./Save")
local Story = require("./Story")
local StoryEngine = require("./StoryEngine")

export type Choice = "continue" | "replay" | "restart"
-- A button's id: a Choice, "confirm" or "cancel".
export type Button = string

-- What the server offers a returning player: the Chapter they are in, as
-- "<title> — <subtitle>", and whether there is a Quest to continue.
export type Offer = { chapter: string, canContinue: boolean }

export type State = "loading" | "choosing" | "confirming" | "closed"
export type TitleScreen = { state: State, offer: Offer? }

export type View = {
	visible: boolean,
	-- the line under the title: the Chapter, or the confirmation's question
	note: string?,
	-- in order; the first is the main one
	buttons: { { id: Button, label: string, primary: boolean } },
}

local TitleScreen = {}

-- The title, as feel.md sets it out: the pill label, then "Amy", then
-- "& the Rain Forest" with "Rain Forest" in gold.
TitleScreen.WORDS = table.freeze({
	pill = "a little tale of the wild",
	name = "Amy",
	the = "& the ",
	gold = "Rain Forest",
})

TitleScreen.LABELS = table.freeze({
	continue = "Continue",
	replay = "Play this chapter again",
	restart = "Start again",
	confirm = "Yes, start again",
	cancel = "No, go back",
} :: { [Button]: string })

TitleScreen.CONFIRM = "Start the whole story again from the very beginning? Your place in the story will be gone."

TitleScreen.CHOICES = table.freeze({ continue = true, replay = true, restart = true } :: { [string]: true })

-- The Chapter a Save is in: the active one, or the last once it has ended.
local function chapterOf(story: Story.Story, progress: StoryEngine.Progress): Story.Chapter
	local _, chapter = Story.quest(story, progress.quest)
	return chapter or story.chapters[#story.chapters]
end

function TitleScreen.offer(story: Story.Story, save: Save.Save): Offer?
	if not Save.started(save) then
		return nil
	end
	local progress = Save.restore(story, save.progress)
	local chapter = chapterOf(story, progress)
	return { chapter = `{chapter.title} — {chapter.subtitle}`, canContinue = not progress.ended }
end

function TitleScreen.choose(story: Story.Story, save: Save.Save, choice: Choice): (Save.Save, StoryEngine.Progress)
	if choice == "restart" then
		return Save.new(), StoryEngine.fresh()
	end
	local progress = Save.restore(story, save.progress)
	if choice == "continue" then
		return save, progress
	end
	-- the Save as it stands has a Checkpoint for every Chapter reached
	local current = Save.record(story, save, progress)
	local replay = Save.restore(story, current.checkpoints[chapterOf(story, progress).id])
	return Save.record(story, current, replay), replay
end

--[[ The client's view-model ]]

function TitleScreen.new(): TitleScreen
	return { state = "loading", offer = nil }
end

function TitleScreen.show(vm: TitleScreen, offer: Offer)
	if vm.state ~= "closed" then
		vm.state = "choosing"
		vm.offer = offer
	end
end

-- The Title choice `button` makes, if any. "Start again" asks first.
function TitleScreen.press(vm: TitleScreen, button: Button): Choice?
	local shown = false
	for _, each in TitleScreen.view(vm).buttons do
		shown = shown or each.id == button
	end
	if not shown then
		return nil
	elseif button == "restart" then
		vm.state = "confirming"
	elseif button == "cancel" then
		vm.state = "choosing"
	else
		vm.state = "closed"
		return if button == "confirm" then "restart" else button :: Choice
	end
	return nil
end

function TitleScreen.close(vm: TitleScreen)
	vm.state = "closed"
end

local function buttons(ids: { Button }): { { id: Button, label: string, primary: boolean } }
	local list = {}
	for i, id in ids do
		table.insert(list, { id = id, label = TitleScreen.LABELS[id], primary = i == 1 })
	end
	return list
end

function TitleScreen.view(vm: TitleScreen): View
	if vm.state == "choosing" then
		local offer = vm.offer :: Offer
		local ids: { Button } = if offer.canContinue
			then { "continue", "replay", "restart" }
			else { "replay", "restart" }
		return { visible = true, note = offer.chapter, buttons = buttons(ids) }
	elseif vm.state == "confirming" then
		return { visible = true, note = TitleScreen.CONFIRM, buttons = buttons({ "confirm", "cancel" }) }
	end
	return { visible = vm.state == "loading", note = nil, buttons = {} }
end

return TitleScreen
