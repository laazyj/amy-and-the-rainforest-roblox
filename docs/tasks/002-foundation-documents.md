# 002 — Foundation documents (Checkpoint A, package A2)

**Kind:** documentation. No code changes except where stated. No secrets,
no Mac.

## Goal

The documents that every later build session and every PR review depend
on exist, are consistent with `docs/DEVELOPMENT_PLAN.md`, and are
specific enough to be checked against.

## Must

1. **`docs/GLOSSARY.md`.** The ubiquitous language from plan section 2.4,
   as the single source of truth: every noun and verb with its definition,
   lifecycle states, and the enumerations that the content schema will be
   derived from (Quest kinds, Speakers, Hook names, Player events, Story
   events, World commands). Add a short "how to propose a new term"
   section. Where the plan and the current code disagree on a name
   (`npc` versus Character), the glossary wins and notes the migration.
2. **`docs/story/canon.md`.** Every line in the current
   `src/ReplicatedStorage/StoryData.lua` that is quoted from Clara's story,
   byte for byte, including her spelling, in story order with the chapter
   and quest it appears in. Clara's lines are the `Narrator` lines that
   read as the book's text (for example "One beautyfull sunday, Amy asked
   to go outside." and "She tryed again but Sam brang her back."). Lines
   written for the game in Amy's, Dad's or others' voices are **not**
   canon; list them separately in the same file under "Game lines, not
   canon" so the distinction is explicit. State the rule that canon lines
   are locked and that a future tier 1 test checks them byte for byte.
3. **`docs/story/style-guide.md`.** How to write new lines in Clara's
   voice, drawn from the canon: sentence length, warmth, humour, the
   spellings that are kept on purpose and the rule that new text uses
   standard spelling unless Clara writes it; reading level for ages 7 to
   12; what is off limits (changing the ending, altering characters'
   personalities, anything outside an all-ages rating, purchases, external
   links, full names). Include three example lines that fit and three that
   do not, with reasons.
4. **`docs/DEFINITION_OF_DONE.md`.** The checklist every PR must satisfy,
   from the plan: tiers that must be green, the glossary rule, canon rule,
   no secrets, only CI publishes, `/simplify` before each commit, PR
   description contents (changelog, verification, how to play-test, what
   was left out), the Max Players = 1 invariant, budgets once they exist,
   and the perceptual-versus-logic-provable declaration for briefs.
5. **`docs/RELEASE_CHECKLIST.md`.** The human promotion checklist from
   Dev to Release, from plan sections 3, 6 (Phase 1 compliance list) and
   8: tier 3 ran on this build, real phone and real tablet playthrough,
   Experience Guidelines questionnaire current, no external URLs, credits
   say "Clara" only, Max Players = 1, Allow copying off, automatic
   translation off, key rotation dates, rollback limit of one schema
   version, baselines updated deliberately.
6. **`docs/design/feel.md`.** First version of the camera, input,
   readability and onboarding spec from the plan: the named Shots the
   current story needs (forest-wall reveal, meeting each animal, the
   machine finale, dialogue framing), the three device classes and their
   layout rules, minimum dialogue text size on a 6-inch phone and maximum
   line length on a 13-inch tablet (choose concrete numbers and justify
   them), touch target size, the first-minute onboarding steps, the
   per-scene visual rubric used by the agent when reviewing screenshots,
   and "automatic translation off" with the reason.
7. **README.** Add a "Documents" section linking all of the above.

## Must not

- Change any Lua file.
- Invent story facts not in the current data or the plan.

## Done when

- Every document above exists, cross-links correctly, and uses the
  glossary's terms consistently (search your own text for NPC, cutscene,
  trigger, region and replace them).
- The PR description lists each document in one line.

## Proof the coordinator checks

The coordinator will diff `canon.md` against the Narrator lines in
`StoryData.lua` by script and expect zero differences, and will read the
glossary's enumerations against plan section 2.4.
