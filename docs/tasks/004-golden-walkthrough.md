# 004 — Golden walkthrough on Dev (Checkpoint A, package A4)

**Kind:** logic-provable. **Blocked until** the Dev experience, Dev API
key, repository variables and secrets exist (plan section 10, items 1 to
3) and briefs 001 and 003 have merged.

## Goal

The pipeline is live against the Dev experience, and a characterization
test records exactly what the current game does, so that the Checkpoint B
refactor can be proven behaviour-preserving.

## Must

1. **Prove the pipeline.** Run the publish-dev workflow once by hand
   (`workflow_dispatch`) and confirm a Published version appears on Dev;
   run the engine-tests workflow on a PR and confirm `smoke.luau` passes
   against a Saved version. Record both run links in the PR.
2. **Fake player.** `tests/engine/_fakeplayer.luau`: an object with
   `UserId`, `Name`, a `Character` model with a `HumanoidRootPart` that
   can be moved, and whatever the current `StoryServer` reads from a
   player. Document each field it needed and why.
3. **Drive the current server.** Find how `StoryServer` receives player
   events today (zone touches, proximity prompts, the `DialogueFinished`
   remote, pickups) and drive them from the test with the fake player:
   move the character into each zone, trigger each prompt, fire
   `DialogueFinished` when a dialogue is shown, touch each pickup. Do not
   modify `StoryServer` to make this possible unless there is no other
   way; if you must, make the smallest change, keep behaviour identical,
   and explain it.
4. **Record the golden file.** Capture every `FireClient` payload the
   server sends (`ShowDialogue`, `SetObjective`, `ShowChapter` and any
   others) in order, with the quest id active at the time, for a full
   playthrough from spawn to the ending. Serialise deterministically
   (sorted keys, no timestamps or positions that drift) to
   `tests/fixtures/golden/walkthrough.json`. Commit it.
5. **Assert against it.** `tests/engine/walkthrough.luau` replays the
   drive and fails on the first divergence from the golden file, printing
   the expected and actual payloads and the quest id. It must pass on
   `main`.
6. **Canon in the golden.** A Lune unit test asserts that every line in
   `docs/story/canon.md` appears, byte for byte, in the golden file in
   story order.
7. **DataStore hygiene.** Confirm no engine test writes to a non-prefixed
   store (the current game has no saves, so this should be a grep and a
   note).

## Must not

- Change game behaviour.
- Run anything against the Release universe.

## Done when

- Both workflows are green against Dev and the Dev experience shows the
  published version.
- `walkthrough.luau` passes on the PR and the golden file contains every
  chapter card, objective and dialogue in order.
- The PR explains how the server was driven and any change it needed.

## Proof the coordinator checks

The coordinator will open the golden file and check it contains the four
chapter cards, every objective and every canon line in order; will
re-run the engine-tests workflow and read its log; and will look at the
Dev experience's version history.
