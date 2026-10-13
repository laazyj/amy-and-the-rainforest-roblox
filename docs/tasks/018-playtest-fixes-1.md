# 018 — Playtest fixes, round 1 (after briefs 011 and 012 on Dev)

**Kind:** fixes and small design corrections. **Source:** the owner's first
playtest of Dev on 2026-10-13, on PC and on a phone (no tablet yet), with
screenshots. The findings are the owner's words; the causes were read from
the code on `main` at `eb546cf`.

## Findings and fixes

### PC

1. **"The Amy & the Rain Forest font is too gothic and not script
   enough."** The title uses `Enum.Font.Fondamento`, a calligraphic
   blackletter. The website reference
   (`docs/design/reference/website-title-overlay.png`) is a flowing,
   rounded handwritten script. Fix: pick the closest family available to
   the client, in this order: a Creator Store font family referenced by
   id through the asset manifest (brief 009's pipeline; candidates like
   Pacifico, Caveat or Dancing Script if the library carries them), else
   the built-in `Kalam`. Put the family in one content constant so a swap
   is one line, and list the candidates in the PR for the owner to pick
   by eye on Dev.
2. **"The 'a little tale of the wild' box is too wide for the text and
   should be offset, not straight."** The pill is `Size = (0.5, 0.07)` of
   the screen, centred and level. Fix: size the pill to its words plus
   padding (`AutomaticSize` on X), place it as the reference does (left
   of centre, above "Amy") and tilt it by about −4°, left end lower, as
   in the reference. Keep the layout rules of brief 012 for every class.
3. **"The game itself has no title screen in the Roblox interface. It's a
   black box."** That is the experience icon in Roblox's own UI, not the
   game: none has been uploaded. Not a code fix: brief 015's store page
   kit specifies the icon and thumbnails from Clara's illustrations under
   the face rule, and the owner uploads them in the Creator Hub. Until
   then the owner may set any placeholder there.
4. **"The Skip button is inaccessible because the chat window appears
   above it."** Skip sits top left on PC, under Roblox's chat window. The
   chat stays on: the Dev shortcuts (`/chapter`, `/quest`) are chat
   commands, so development needs it (whether Release turns it off is a
   brief 015 Config question). Fix, the owner's: Skip becomes a sibling of
   the Talk-and-advance button ("Talk" / "Next"), a button row at the
   bottom right on every class, PC included, so the two are paired: Next
   during a Dialogue, Skip while a Hint shows in free play, both when both
   apply. PC therefore gets the clickable Talk-and-advance button too.
   Layout and overlap tests updated; the row keeps clear of the dialogue
   box and the Objective tracker.
5. **"Using Space to continue is weird as the character jumps every time
   you press Space."** Jumping stays: the owner wants it for future
   chapters. Fix: Space no longer advances a Dialogue on PC; click on the
   box, E, Enter and the Next button do. The first-Line Hint and feel.md
   section 5 change to match ("Click or press E to continue"). The touch
   jump button stays hidden for now (the Story has no jump yet) with a
   note that a future chapter brings it back in its own zone.
6. **"The tilt shot at the forest wall could be more dramatic, panning
   higher up the wall."** `CameraModel.PATHS.ForestWallReveal` ends its
   look-at at 18 studs up. Fix: start lower (Amy's shoulders) and end at
   the canopies above the wall, so the tilt travels the trunks' full
   height; the camera position stays where it is, so the camera rule
   holds unchanged; the Shot path tests still pass; the PR gives the new
   end height.

### Phone

7. **"The thumbstick appeared but then disappeared and never came back."**
   Brief 012 disables the player module's controls during a Dialogue and
   enables them after. Find the path where `Enable()` is not reached (a
   Dialogue ended by a Resume or a Dev jump, a Dialogue Shot queued, the
   first Dialogue after join) and the interaction with moving the
   `DynamicThumbstickFrame`, and fix it so the controls return after
   every Dialogue. Say in the PR what the cause was.
8. **"Thumbstick is at an odd location, far away from the bottom-left
   corner. It is also NOT the active area for the thumbstick, which is
   correctly located in the bottom left."** The Onboarding ring (and the
   code that moves the thumbstick frame into the left zone) draws at the
   zone's centre, while Roblox's dynamic thumbstick lives in the
   bottom-left corner. Fix: stop moving the thumbstick frame; draw the
   ring where the real control is (its frame's absolute position and
   size at runtime, falling back to the zone's bottom-left corner).
9. **"There is a Talk button that does nothing, often showing when there
   is nobody to talk to."** The Talk-and-advance button is always bound.
   Fix: show it only when a prompt is within reach or a Dialogue is
   showing, hidden otherwise; the rule lives in `TalkAndAdvance` with a
   tier 1 test.
10. **"Objective icon is just an empty grey box."** The collapsed Objective
    icon is the glyph "✦" in `FredokaOne`, which has no such glyph (the
    "✦ Objective" header renders as "Objective" for the same reason).
    Fix: a drawn marker (a gold rounded square or circle with "!" in a
    font that has it) for the collapsed icon, and drop "✦" from
    `ObjectiveText.HEADER`.

## Must not

- Change the golden file, any Line, gameplay, the camera rule or the
  Shots' positions (only ForestWallReveal's look-at moves).
- Add a settings screen or anything from brief 015.

## Done when

- Tier 0 and tier 1 green, `lune run tools/mutate` at all faults caught,
  CI and the engine tests green; the PR lists each finding and its commit.
- The owner replays Dev on PC and on a phone and the ten findings are
  gone, with the title font chosen by eye.
