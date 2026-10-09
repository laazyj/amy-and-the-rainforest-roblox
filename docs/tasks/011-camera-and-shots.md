# 011 — Phase 1: the locked-behind camera and the Shots

**Kind:** perceptual (Mac required for the visual pass; logic parts first).
**Starts after** brief 007 merges (client binder and view-model exist).

## Goal

"Amy's face is never seen" becomes true in the client: a follow camera
that stays in her rear hemisphere on every device class, and every Shot
in `docs/design/feel.md` implemented from behind her.

## Must

1. **Camera module** (`src/client/Camera.luau`) driven by a pure
   `src/core/CameraModel.luau`: the player turns the view and Amy turns
   with it (shift-lock feel) on PC, phone and tablet; the camera never
   leaves the rear hemisphere, within the margin `feel.md` states; spawn,
   respawn and Dialogue keep the rule. Tier 1 tests on the model:
   for any input sequence, dot(facing, camera − Amy) < 0 with the margin.
2. **Shots** as named camera moves (`shot:Dialogue`, `ForestWallReveal`,
   `MeetCharacter(character)`, `MachineFinale`) executed from the
   `FrameShot` World command, each framed as `feel.md` specifies, with the
   per-animal rows for MeetCharacter. Tier 1 asserts each Shot's camera
   path stays behind Amy at every sampled point.
3. **Tier 3 assertion** (once the Mac runner exists): at every Shot and at
   sampled frames, the camera is behind Amy and her head is never framed
   from the front; otherwise record the assertion in `tests/studio/` ready
   to run.
4. **Golden.** `FrameShot` commands appear in the walkthrough; re-record
   the golden file once, in its own commit, with the PR showing the diff
   is only added `FrameShot` messages.

## Must not

- Touch gameplay, Lines or timings beyond adding Shots. Add a free-orbit
  camera option.

## Done when

- Tier 1 green for model and Shots; walkthrough green with the re-recorded
  golden; on the Mac, screenshots at each Shot show Amy from behind.
