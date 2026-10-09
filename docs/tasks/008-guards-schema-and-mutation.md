# 008 — Checkpoint B, package B3: content schema, purity and coverage guards

**Kind:** logic-provable. No Mac. **Starts after** brief 007 merges.

## Goal

The rules the plan states become checks the build enforces, so a future
agent cannot drift from them.

## Must

1. **Content schema from the glossary.** A tier 0 step validates every
   file under `src/content` against a schema whose enumerations (Quest
   kinds, Speakers, Hook names, Zone, Scene, Prop, Beat, Cue and Shot
   names) are derived from `docs/GLOSSARY.md`'s tables, so adding a term
   to code without the glossary fails the build. Positions and colours
   must be plain tables.
2. **Purity lint.** Tier 0 fails if `src/core/**` or `src/content/**`
   references `game`, `Instance`, `GetService`, `script` or `require` of
   anything outside `src/core` and `src/content`.
3. **No external links.** Tier 0 fails on `http://` or `https://` in any
   content string or UI text (comments excluded), per the Roblox
   compliance list.
4. **Coverage guards** (plan section 4): every module under `src/core` has
   a matching spec; every Quest kind, Hook, World command and Player event
   in the glossary appears by name in at least one spec; every chapter in
   content has a walkthrough spec; a PR that changes `src/core` without
   changing `tests/` fails unless it carries the label `no-test-change`
   and the PR body states why (a workflow check reads both).
5. **Nightly mutation check.** `.github/workflows/mutation.yml` on a
   nightly schedule and `workflow_dispatch`: `tools/mutate.luau` applies a
   dozen canned faults one at a time (rename a quest id, drop a hook,
   break a save migration, blank a canon Line, swap two objectives,
   remove a zone, break a Beat's command order, change a Speaker, etc.),
   runs tier 1 for each, and fails if any fault leaves the suite green.
   Report which test caught each fault in the job summary.
6. **Luau coverage spike** (non-blocking): try exposing Luau VM coverage
   for the pure core tests through Lune or the Luau CLI; record the result
   in `docs/MAINTENANCE.md`. Do not gate on it.
7. **Definition of done** updated to point at these checks instead of
   instructions where a check now exists.

## Must not

- Weaken any existing test to satisfy a guard; fix the code or add the
  test instead.

## Done when

- CI green with every guard active; the mutation workflow has one
  successful manual run linked in the PR, with every fault caught.
