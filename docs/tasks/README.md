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
| 001 Toolchain and CI | A | open |
| 002 Foundation documents | A | open |
| 003 Open Cloud tooling | A | open |
| 004 Golden walkthrough on Dev | A | waiting on Roblox setup |
