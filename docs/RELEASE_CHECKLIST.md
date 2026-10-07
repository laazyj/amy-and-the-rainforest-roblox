# Release checklist — promoting Dev to Release

The owner works through this list before approving the `release`
environment for a tag. Every box is ticked, or the promotion waits. It
comes from [`DEVELOPMENT_PLAN.md`](DEVELOPMENT_PLAN.md) sections 3, 6
(Phase 1 compliance) and 8.

Copy it into the GitHub Release draft for the tag and tick it there.

Terms are as defined in the [glossary](GLOSSARY.md). Every PR in the
release has already met the [definition of done](DEFINITION_OF_DONE.md).

The cheap checks come first, so a blocker is found before the
playthroughs.

## The build

- [ ] **The release workflow's gates passed**: the tag `vX.Y.Z` is on
      `main` with tiers 0–2 green, the artifact built at that tag is used
      by SHA with its checksum verified, and **tier 3 ran on this exact
      build** and is green (plan [section 4](DEVELOPMENT_PLAN.md#4-the-test-harness)).
- [ ] **Baselines were updated deliberately**: every changed baseline in
      `docs/screens/` since the last release came from a PR that showed
      before and after and was accepted.

## Keys, saves and rollback

- [ ] **Key rotation dates checked**: neither `ROBLOX_DEV_API_KEY` nor
      `ROBLOX_RELEASE_API_KEY` expires within 30 days; if one does,
      rotate it before promoting.
- [ ] **Rollback limit**: this release changes the save schema by at
      most **one version** from the current Release, so the previous tag
      can still read its saves. If it changes by more, plan the rollback
      before promoting.
- [ ] The previous release tag is noted here as the rollback target:
      `v_____`. Rollback is re-running the release workflow with that
      tag, never reverting in the Roblox dashboard.

## Compliance and settings

Check these on the **Release** experience's settings page, not on Dev.

- [ ] **Experience Guidelines questionnaire is current**: completed,
      all-ages result, and redone if this release adds material content
      (a new Chapter with new themes).
- [ ] **No external URLs** in the experience description, icon,
      thumbnails, credits, ending card, dialogue or any UI text.
- [ ] **Credits say "Clara" only**, never a full name.
- [ ] **Max Players = 1.**
- [ ] **"Allow copying" is off.**
- [ ] **Automatic translation is off**, because it would "correct"
      Clara's deliberate spellings (see [canon](story/canon.md#the-rule)).
- [ ] No in-game purchases, paid items or Robux prompts.
- [ ] Icon, thumbnails and description pass a moderation pre-check.

## Play it (tier 4)

On the Dev experience, from a fresh save and from a save made on the
current Release:

- [ ] **PC** playthrough of every Chapter to the Ending.
- [ ] **Real phone** playthrough: touch controls, dialogue readable,
      nothing under the notch or home bar, smooth enough.
- [ ] **Real tablet** playthrough, landscape: controls at the corners,
      dialogue centred and readable, smooth enough.
- [ ] Quit mid-Chapter and rejoin: Resume puts Amy at the same Quest
      with the world as it was.
- [ ] Clara has played the new content, or the release has no new story.

## Publish

- [ ] **Only CI publishes**: approve the `release` environment; do not
      publish from Studio.
- [ ] After publish, join the Release experience once and reach the first
      Objective.
- [ ] The GitHub Release has a changelog in the glossary's language and
      the `.rbxl` attached.
