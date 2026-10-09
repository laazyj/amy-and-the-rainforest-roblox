# 010 — Phase 1: saves and resume

**Kind:** logic-provable. No Mac. **Starts after** brief 006 merges
(Progress and `resume` exist in core).

## Goal

A child who closes the app mid-chapter comes back to the same Quest with
the world as they left it, on any device, as plan 2.3 and 2.4 specify.

## Must

1. **Persist adapter** (`src/server/Persist.luau`) using ProfileStore
   (add to `wally.toml`, pinned). Store name prefix from config; the engine
   harness sets it to `test-<RUN_ID>` so engine tests never touch tester
   data. Progress is written on every Story event and on leave.
2. **Save schema** in `src/core/Save.luau`: versioned, a migration per
   version with a tier 1 test each, and a tolerance test that version N
   code reads a version N+1 save (rollback by one version).
3. **Resume.** On join, `StoryEngine.resume(progress)` rebuilds the world;
   the "Continue" and "Start again" (behind a confirmation) title-screen
   flow; a Checkpoint per Chapter for "play this chapter again".
4. **Tests.** Tier 1: for every Quest, walk-to state equals resume state.
   Tier 2: save at every Quest, resume in a fresh engine instance, assert
   Characters, Props and lighting preset match; ProfileStore session lock
   released on `BindToClose`; a test-store cleanup step deletes
   `test-<RUN_ID>-*` keys through the Open Cloud DataStore API (the Dev key
   has list, read and delete).
5. **Studio DataStore access** on the Dev experience documented for later
   Mac playtests.

## Must not

- Change the golden walkthrough (a fresh player with no save must behave
  exactly as today). Add a second save slot.

## Done when

- All tiers green; a real resume demonstrated in the engine test log;
  cleanup verified by listing the test store after the run.
