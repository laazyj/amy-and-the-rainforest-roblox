# Release checklist — promoting Dev to Release

The owner works through this list before approving the `release`
environment for a tag. Every box is ticked, or the promotion waits. It
comes from [`DEVELOPMENT_PLAN.md`](DEVELOPMENT_PLAN.md) sections 3, 6
(Phase 1 compliance) and 8.

Copy it into the GitHub Release draft for the tag and tick it there.

Terms are as defined in the [glossary](GLOSSARY.md). Every PR in the
release has already met the [definition of done](DEFINITION_OF_DONE.md).

Each item is one of two kinds:

- **Check**: an automated check, named. Tick it when that check is green
  on the tagged commit (its CI run, or the job named).
- **Human**: a step only a person can do, with where to do it. In the
  Creator Hub, "the experience" means the **Release** experience unless
  the item says Dev. The Creator Hub's menus move from time to time: if a
  page is not where this says, look for the same name nearby and correct
  this file.

The cheap checks come first, so a blocker is found before the
playthroughs.

## The build

- [ ] **Check: the release workflow's gates passed**: the tag `vX.Y.Z` is
      on `main` with tiers 0–2 green (`.github/workflows/ci.yml`,
      `engine-tests.yml`), the artifact built at that tag is used by SHA
      with its checksum verified, and **tier 3 ran on this exact build**
      and is green (plan [section 4](DEVELOPMENT_PLAN.md#4-the-test-harness)).
- [ ] **Check: Dev shortcuts are gone from the Release build**: the
      publish job, with `RELEASE_JOB=1`, strips `ServerScriptService.Dev`
      and refuses a place without it (`tools/lib/release.luau`,
      `tests/lune/tools/release.spec.luau`).
- [ ] **Human: baselines were updated deliberately**: every changed
      baseline in `docs/screens/` since the last release came from a PR
      that showed before and after and was accepted. Where: the PRs
      merged since the last tag, on GitHub.

## Keys, saves and rollback

- [ ] **Human: key rotation dates checked**: neither
      `ROBLOX_DEV_API_KEY` nor `ROBLOX_RELEASE_API_KEY` expires within 30
      days; if one does, rotate it before promoting. Where: the Creator
      Hub, **Open Cloud**, **API Keys** (each key's expiry), then the
      repository's or the `release` environment's secrets on GitHub.
- [ ] **Human: rollback limit**: this release changes the Save's schema
      version by at most **one** from the current Release, so the
      previous tag can still read its Saves. Where: `Save.VERSION` in
      `src/core/Save.luau` at this tag and at the previous one. If it
      changes by more, plan the rollback before promoting. (Check: the
      tolerance test in `tests/lune/core/Save.spec.luau` proves code reads
      a Save one version newer.)
- [ ] **Human: the rollback target** is the previous release tag:
      `v_____`. Rollback is re-running the release workflow with that
      tag, never reverting in the Roblox dashboard.

## Compliance and settings

The settings are on the **Release** experience, not Dev. The words, the
art and the questionnaire are in the [store page kit](store/README.md),
in the order to do them in one sitting.

- [ ] **Human: the Experience Guidelines questionnaire is current**:
      completed with an all-ages result, and redone if this release adds
      material content (a new Chapter with new themes). Where: the
      Creator Hub, the experience, **Audience**, **Maturity &
      Compliance**; the answers are drafted in
      [store/questionnaire.md](store/questionnaire.md).
- [ ] **Check: no external URLs** in content, dialogue, Hints, the
      ending card or any UI text: `tools/guard links` (every text under
      `src/`), and in the store page kit: `tools/guard store-links`.
- [ ] **Human: no external URLs on the store page itself**: the
      description, icon and thumbnails as set. Where: the Creator Hub,
      the experience, **Configure**, **Basic Settings**.
- [ ] **Check: credits say "Clara" only**: `tools/guard names` (no
      surname under `src/`, `assets/` or `docs/store/`; the owner adds a
      name to `Compliance.SURNAMES` in `tools/lib/compliance.luau`).
- [ ] **Check and Human: Max Players = 1**: tier 2 asserts it on Dev
      (`tests/engine/maxplayers.luau`). On Release, where: the Creator
      Hub, the experience, **Places**, the start place, its settings
      (server size, **Max Players**), set to 1.
- [ ] **Human: "Allow copying" is off.** Where: the Creator Hub, the
      experience, **Places**, the start place, its settings
      (**Permissions** or **Access**, "Allow Copying"); also in Studio's
      Game Settings, **Security** for the place. Off on Dev too.
- [ ] **Human: automatic translation is off**, because it would
      "correct" Clara's deliberate spellings (see
      [canon](story/canon.md#the-rule) and
      [feel.md](design/feel.md#8-automatic-translation-is-off)). Where:
      the Creator Hub, the experience, **Localization**, **Settings**:
      automatic translation (and automatic text capture, which feeds it)
      off. Off on Dev too.
- [ ] **Check: no text chat on Release**: the server turns Roblox's chat
      window and input bar off unless the build has the Dev folder, which
      the release job strips (`Config.chat`;
      `tests/lune/place/Config.spec.luau`, the Wiring spec,
      `tests/engine/chat.luau` for Dev), which works only with the place's
      chat on `TextChatService` (`tests/lune/place/chat.spec.luau`). **Human**: after publishing, join
      Release once and see no chat window.
- [ ] **Human: voice chat is off.** Where: the Creator Hub, the
      experience, **Communication** (or **Audience**, voice chat).
- [ ] **Check: no in-game purchases, paid items or Robux prompts**:
      `tools/guard purchases-and-text` (nothing under `src/` reaches
      MarketplaceService or prompts a purchase). **Human**: no passes or
      developer products exist. Where: the Creator Hub, the experience,
      **Monetization** (Passes, Developer Products): both empty.
- [ ] **Human: icon, thumbnails and description pass a moderation
      pre-check**: [store/art.md](store/art.md)'s rules and
      [store/description.md](store/description.md), before setting them
      in **Basic Settings**.
- [ ] **Check and Human: every Asset the game shows is approved**:
      `upload: true` entries in `assets/manifest.json` have Moderation
      status `approved` (the upload workflow records it; `tools/check.sh`
      checks the Manifest), and no `placeholder: true` entry ships unless
      the owner accepted it ([`ASSETS.md`](ASSETS.md#moderation)).
- [ ] **Human: Amy's face is never shown** in any image: the by-eye
      checklist in [store/art.md](store/art.md) is ticked. (Check: tier
      3's camera rule for the game itself.)

## Settings and accessibility

- [ ] **Check: no timed reading**: no Dialogue moves on without the
      player (`tests/lune/core/DialogueViewModel.spec.luau`, "no timed
      reading"; the mutation check's timed-reading fault is caught).
- [ ] **Check: every feel.md rule holds at every Setting**: text sizes,
      the 60-character column, touch targets, the Pause screen and
      contrast at 4.5:1 and 7:1 in high contrast, at each Text scale
      (`tests/lune/core/ScreenLayout.spec.luau`,
      `DialogueViewModel.spec.luau`, `PauseScreen.spec.luau`).
- [ ] **Human: the Settings work on a real phone and tablet**: in the
      playthroughs below, open the Pause screen, try each Setting, and
      check the volume, the Largest text size (and the note when the
      screen caps it), high contrast and easy-read letters, then rejoin
      and see they are kept.

## Play it (tier 4)

On the Dev experience, from a fresh Save and from a Save made on the
current Release:

- [ ] **Human: PC** playthrough of every Chapter to the Ending.
- [ ] **Human: real phone** playthrough: touch controls, dialogue
      readable, nothing under the notch or home bar, smooth enough.
- [ ] **Human: real tablet** playthrough, landscape: controls at the
      corners, dialogue centred and readable, smooth enough.
- [ ] **Human: quit mid-Chapter and rejoin**: Resume puts Amy at the
      same Quest with the world as it was. (Check: `tests/engine/resume.luau`.)
- [ ] **Human: Clara has played the new content**, or the release has no
      new story.

## Publish

- [ ] **Human: only CI publishes**: approve the `release` environment on
      GitHub; do not publish from Studio.
- [ ] **Human: after publish, join the Release experience once** and reach
      the first Objective.
- [ ] **Human: the analytics arrive**: a day later, the Release
      experience's custom events show your visit
      ([ANALYTICS.md](ANALYTICS.md)). Where: the Creator Hub, the
      experience, **Analytics**, **Custom events**.
- [ ] **Human: the GitHub Release** has a changelog in the glossary's
      language and the `.rbxl` attached.
