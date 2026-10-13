# Analytics — what the game logs and what to watch

The server logs Roblox Analytics **custom events** (plan section 2.3,
"Analytics"). The names are the glossary's: each Story event is logged
under its own name, each Fault under its name, and the end of a visit as
`SessionEnded`. The mapping is plain data in
`src/core/AnalyticsEvents.luau`; tier 1 (`tests/lune/core/AnalyticsEvents.spec.luau`)
fails if a Story event or a Fault, in the code or in the
[glossary](GLOSSARY.md), has none. The adapter is
`src/server/Analytics.luau`, called by `StoryHost` and `FaultLog`; tier 2
(`tests/engine/analytics.luau`) plays a fake player on Dev and checks what
it logs.

Dev and Release are separate experiences, so each has its own analytics:
testers' play on Dev never mixes with players' on Release.

## The events

| Event | Value | Custom field 1 | Logged when |
|---|---|---|---|
| `ChapterStarted` | 1 | the Chapter id | A Chapter became `active` |
| `QuestStarted` | 1 | the Quest id | A Quest became `active` |
| `QuestCompleted` | 1 | the Quest id | A Quest became `completed` |
| `ChapterCompleted` | 1 | the Chapter id | A Chapter became `completed` |
| `BeatPlayed` | 1 | the Beat | A Beat ran at a Hook |
| `StoryEnded` | 1 | | The Ending finished |
| `SessionEnded` | seconds played | | The player left |
| a Fault's name, such as `save_load_timeout` | 1 | | A Fault was reported for the player; a Fault of the whole server is logged for each player who joins it |

`CollectibleFound` and `BondChanged` are logged the same way from the PR
that makes them Story events: the tier 1 test fails until they are mapped.

A Resume raises no Story events, so a returning player's first event is the
next Quest they start or complete, not a second `ChapterStarted`.

## What to watch

In the Creator Hub, open the experience (Release, or Dev while testing),
then **Analytics**, then **Custom events**, and pick an event; break it
down by its custom field to see each Chapter or Quest. Roblox's own
**Engagement** and **Retention** pages, in the same Analytics section, show
visits and returning players without any of our events.

- **Where players stop.** Compare `QuestStarted` with `QuestCompleted` for
  each Quest id, in story order. A Quest started far more often than it is
  completed is where players get stuck or give up: its Objective may be
  unclear, or its Zone or Character hard to find. The first two Quests of
  `chapter1` also show whether the Onboarding works.
- **How far players get.** `ChapterStarted` per Chapter, and `StoryEnded`,
  against `ChapterStarted` for `chapter1`.
- **How long a visit is.** The distribution of `SessionEnded`'s value. A
  visit is single player and short by design; very short visits with no
  `QuestCompleted` mean players leave before the Story starts.
- **Saves going wrong.** Any `save_unreadable`, `save_too_new`,
  `save_load_timeout`, `save_unavailable` or `save_close_unbound` is worth a
  look: what each means is in the glossary's
  [Faults](GLOSSARY.md#faults). A rise after a release is a reason to roll
  back (release checklist, "Keys, saves and rollback").

Custom events appear in the Creator Hub after a delay of up to a day, and
only for real players: engine tests log nothing to AnalyticsService.

## Follow-up

Roblox Analytics also has funnel and progression events
(`AnalyticsService:LogFunnelStepEvent`, `LogProgressionEvent`), which the
Creator Hub draws as a funnel without building one from custom events.
Logging each `QuestStarted` as a funnel step of the Story, in story order,
would show at a glance where players stop. It is a small change in
`src/server/Analytics.luau` with its own mapping in
`src/core/AnalyticsEvents.luau`; not done yet.
