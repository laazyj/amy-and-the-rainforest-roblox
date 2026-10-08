# Definition of done

Every PR must satisfy this checklist before the owner reviews it. Copy
the checklist into the PR description and tick each item, or write
"n/a: <reason>" next to it. It comes from
[`DEVELOPMENT_PLAN.md`](DEVELOPMENT_PLAN.md) sections 2–5; when the plan
changes, this file changes in the same PR.

Terms are as defined in the [glossary](GLOSSARY.md). Promotion from Dev
to Release has its own [release checklist](RELEASE_CHECKLIST.md).

## Checklist

### Tests

Bring the branch up to date with `main` first, so the tiers run on what
will land.

- [ ] **Tier 0 (static) is green**: format, lint, strict types, core and
      content purity, content schema, no `http` strings in content or UI
      text.
- [ ] **Tier 1 (unit, Lune) is green**, including the canon test and a
      walkthrough of every Chapter from a fresh save, from every
      Checkpoint and from a Resume at every Quest.
- [ ] **Tier 2 (engine) is green** on the Saved Dev version built from
      this PR's head. Open Cloud outages are reported in the PR, never
      retried into green.
- [ ] **Tier 3 (Studio, Mac)**: result attached, or "skipped: runner
      offline" stated.
- [ ] New behaviour has new tests, named in the glossary's language
      ("plays beat sam_catches on EnteredZone(GardenGate)").
- [ ] **Budgets** (instance, part, triangle, texture, server Heartbeat,
      client frame time) are within limits, once tiers 2 and 3 measure
      them. Until then: n/a.

Tiers that do not exist yet are marked "n/a: not built yet" until the
Phase 0 PR that adds them; from then on they are required.

### Language and story

- [ ] **Glossary rule.** Every noun and verb in code names, content keys,
      tests and this PR's description is in [`GLOSSARY.md`](GLOSSARY.md);
      new terms follow
      [How to propose a new term](GLOSSARY.md#how-to-propose-a-new-term).
- [ ] **Canon rule.** No canon Line is changed
      ([the rule](story/canon.md#the-rule)); the tier 1 canon test
      enforces it.
- [ ] New Lines in Clara's voice follow the
      [style guide](story/style-guide.md) and are listed in the PR as
      "new Lines, not canon, for approval".
- [ ] No new story facts unless from an approved proposal in
      `docs/story/proposals/`.

### Safety and publishing

- [ ] **No secrets** in the diff, the PR description, logs or test
      fixtures: no API keys, tokens, cookies or `.env` files.
- [ ] **Only CI publishes.** Nothing in this PR was published from
      Studio or by hand to Dev or Release.
- [ ] **Max Players = 1** is unchanged and still asserted by tier 2.
- [ ] **Amy's face is never seen**: every camera and Shot obeys the
      [camera rule](design/feel.md#invariants), and no new art shows her
      face.
- [ ] No purchases or full names in anything a player can see (tier 0
      already rejects `http` strings).

### Process

- [ ] **`/simplify` was run on the changes before each commit**, and its
      fixes applied or the skips noted.
- [ ] The PR covers one brief, one Chapter or one feature set, and is
      under about 2,000 changed lines (otherwise stacked PRs).

### PR description

- [ ] **Changelog**: what changed, in the glossary's language.
- [ ] **Verification**: a link to the CI run for tiers 0–2, the tier 3
      result, and screenshots or the contact sheet for anything visible
      (or a note that none were possible).
- [ ] **How to play-test**: the Dev link, a save-state shortcut (for
      example `/chapter 3` or "jump to Quest `chapter3.meet_fox`"), and
      what to look for on PC, phone and tablet.
- [ ] **What was left out**: anything in the brief not done, with the
      reason and the proposed alternative.
- [ ] Open questions as a short list.
- [ ] If a baseline screenshot changed: before and after, with the
      [feel rubric](design/feel.md#7-visual-rubric) scores.

## Declaring the kind of work

Every brief and its PR declares whether its scope is **logic-provable**,
**perceptual**, or both, as defined in plan
[section 5.4](DEVELOPMENT_PLAN.md#54-logic-provable-versus-perceptual-work).
What "done" adds for each:

| Kind | Done when |
|---|---|
| Logic-provable | The checklist above is green |
| Perceptual | The above, plus tier 3 green, the [feel rubric](design/feel.md#7-visual-rubric) passed and new baselines proposed; the owner and Clara accept the result. If the Mac was off, the PR says which perceptual parts are unproven. |
