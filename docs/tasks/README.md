# Task briefs

Each file is a brief for one build session. A brief is the whole contract
for that session: goal, scope, constraints, definition of done, and the
proof the coordinator will check. Briefs are written in the language of
`docs/DEVELOPMENT_PLAN.md` section 2.4.

Rules every build session follows, regardless of brief:

- Work on your own branch, open a PR to `main`, and **never merge**. The
  owner reviews and merges every PR personally.
- Read `docs/DEVELOPMENT_PLAN.md` before starting. The plan is the source
  of truth; a brief narrows it, never contradicts it.
- Before **each** commit, run the `/simplify` skill on your changes and
  apply its fixes.
- Keep PRs reviewable: a clear description with what changed, how it was
  verified (commands and their output), and anything left out and why.
- Never publish to Roblox from anywhere but CI. Never commit a secret.
- If something in the brief turns out to be impossible or wrong, finish
  everything else, say so in the PR, and propose the alternative.

| Brief | Checkpoint | Status |
|---|---|---|
| 001 Toolchain and CI | A | done |
| 002 Foundation documents | A | done |
| 003 Open Cloud tooling | A | done |
| 004 Golden walkthrough on Dev | A | done |
| 005 Integrate toolchain and Open Cloud tooling | A | done |
| 006 Core and content (the refactor) | B | done (#20) |
| 007 Client view-model and engine suite | B | running (B2) |
| 008 Content schema, purity and coverage guards | B | after 007 |
| 009 Asset pipeline | Phase 1 | in review (#26) |
| 010 Saves and resume | Phase 1 | after 006 |
| 011 Locked-behind camera and Shots | Phase 1 | after 007; Mac for the visual pass |
| 012 Device classes, touch and onboarding | Phase 1 | after 007; Mac for emulation |
| 013 Audio and narration | Phase 1 | after 009 and 006; owner's recordings |
| 014 Characters and Sam's chase | Phase 1 | after 006; Mac for the look |
| 015 Settings, accessibility, store page, compliance | Phase 1 | after 011 and 012 |
| 016 Visual pass | Phase 1 | after 011, 012, 014; Mac required |
| 017 Agent bootstrap and Selene standard library | tooling | in review (#24) |
| mac-001 Runner bootstrap | Phase 1 | on the MacBook, any time |
| mac-002 Studio bridge, emulation and asset spikes | Phase 1 | after mac-001 |
