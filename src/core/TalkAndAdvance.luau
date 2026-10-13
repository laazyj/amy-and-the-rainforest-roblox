--!strict
--[[
	TalkAndAdvance: what the Talk-and-advance button does, as plain data
	(docs/design/feel.md sections 1 and 4). The client binder shows it on
	every class, in the button row at the bottom right, when `shown` says,
	and calls `press` when it is pressed.

	  shown(open, prompts)  whether the button shows: while a Dialogue
	                        shows, or while a prompt is within reach (shown);
	                        with neither it would do nothing, so it hides
	  press(open, prompts)  "advance" while a Dialogue shows (a Line still
	                        typing shows in full first, as DialogueViewModel
	                        has it); otherwise the nearest prompt shown, to
	                        use: prompts stay the universal talk affordance;
	                        nil when there is nothing to do
	  title(open, labels)   the button's word: the "next" label while a
	                        Dialogue shows, the "talk" label otherwise
]]

export type Labels = { talk: string, next: string }

local TalkAndAdvance = {}

-- `prompts` maps each prompt shown to its distance from Amy.
function TalkAndAdvance.press<Prompt>(open: boolean, prompts: { [Prompt]: number }): ("advance" | Prompt)?
	if open then
		return "advance"
	end
	local nearest, best = nil, math.huge
	for prompt, distance in prompts do
		if distance < best then
			nearest, best = prompt, distance
		end
	end
	return nearest
end

function TalkAndAdvance.shown<Prompt>(open: boolean, prompts: { [Prompt]: any }): boolean
	return open or next(prompts) ~= nil
end

function TalkAndAdvance.title(open: boolean, labels: Labels): string
	return if open then labels.next else labels.talk
end

return TalkAndAdvance
