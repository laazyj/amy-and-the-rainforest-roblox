# 007 — Checkpoint B, package B2: client view-model and the engine suite

**Kind:** logic-provable. No Mac. **Starts after** brief 006 merges.

## Goal

Client logic becomes a pure, tested view-model, and tier 2 grows into the
suite plan section 4 describes, so the harness can catch the bug classes
the golden walkthrough cannot.

## Must

1. **Client view-model in core** (`src/core/DialogueViewModel.luau`,
   `ObjectiveText.luau`, `ChapterCardTimeline.luau`): the dialogue queue,
   line index, visible-grapheme count (emoji and `♥` tested), speaker
   style, objective formatting and chapter-card timing, all pure. The
   client binder (`src/client/`) renders the view-model and forwards
   input; it holds no logic. Tier 1 specs for each.
2. **Remote contract.** `src/core/Events.luau` payload schemas are
   validated on both sides: the server validates what it sends, the client
   what it receives, and a tier 2 test sends every server→client payload
   from the golden file through the validator.
3. **Engine suite additions** under `tests/engine/`, each a separate
   script:
   - `maxplayers.luau`: `Players.MaxPlayers == 1` (if the property cannot
     be read in Luau Execution, record that and move the check to a tier 1
     spec that reads it from the built place, as brief 005 did for Lighting).
   - `isolation.luau`: two fake players at different chapters; assert no
     cross-talk in objectives, dialogue or world commands addressed to each.
   - `reachability.luau`: `PathfindingService:ComputeAsync` from spawn to
     every Zone centre and every Character's prompt position with R15
     agent parameters; assert `Status == Success` for each; print path
     lengths.
   - `budgets.luau`: instance count, part count and server Heartbeat time
     over a 5-second sample, each under a budget stored in
     `tests/engine/budgets.luau` with the current values plus 20% headroom.
   - `resume.luau`: for every Quest, save Progress, resume in a fresh
     engine instance, and assert the same Characters, Props and lighting
     preset are in place as when walked to.
4. **Physics spike, decided.** Record in `docs/OPEN_CLOUD.md` whether
   `Heartbeat` and physics step in Luau Execution (brief 004 found no
   `Touched`), and therefore whether real traversal is tier 2 or tier 3
   only. Update plan section 4's "Reachability is tested, traversal may
   be" note to the decided wording.
5. **Debug shortcuts** for Dev builds only (plan 5.3): a `/chapter N`
   chat command and a jump-to-quest entry point on the server, compiled
   out of Release builds via a config flag set by the publish job
   (`RELEASE_JOB=1` → off). Tier 1 asserts the flag gates them.

## Must not

- Change the golden file (the view-model extraction must not alter any
  payload).
- Touch the Release universe.

## Done when

- All new engine scripts pass on the PR's Saved version; tier 1 covers
  every new core module; CI green; golden unchanged.
- The PR states the measured budget values and the physics decision.
