--!strict
-- The Hints: the UI Lines the game shows to teach its verbs, in Clara's
-- voice (docs/story/style-guide.md). New Lines, not canon, for approval:
-- the owner changes the words here without touching code.
--
--   steps     each Onboarding step's Hint (docs/design/feel.md section 6),
--             for PC and for touch; on touch the talk step pulses the
--             Talk-and-advance button instead of showing words
--   continue  the dialogue box's standing hint, after the Onboarding
--   skip      the Skip button, which ends the Onboarding (6 characters at
--             most: ScreenLayout.SKIP_CHARACTERS)
--   button    the Talk-and-advance button's word, with no Dialogue (talk)
--             and while one shows (next)

local Onboarding = require("../core/Onboarding")

local steps: { [string]: Onboarding.Hint } = {
	advance = { pc = "Click or press Space to continue", touch = "Tap to continue" },
	walk = { pc = "W and S walk, A and D turn (or the arrow keys)", touch = "Drag here to walk" },
	talk = { pc = "Press E to talk" },
}

return {
	steps = steps,
	continue = { pc = "click / E / Space to continue  ▶", touch = "tap to continue  ▶" },
	skip = "Skip",
	button = { talk = "Talk", next = "Next" },
}
