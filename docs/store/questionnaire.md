# Experience Guidelines questionnaire — a draft for the owner

The answers the owner gives on Roblox's maturity questionnaire for the
**Release** experience, each tied to a fact about the game and to the
test or the plan rule that backs it. The owner submits it; no agent does.
Without it the experience is treated as 13+ and is not shown to younger
players (plan section 6, Phase 1, "Roblox compliance").

Where: the Creator Hub, the Release experience, **Audience**, then
**Maturity & Compliance** (the questionnaire; Roblox has also called it
"Experience Guidelines"). The account must be at least 30 days old to
complete it. Roblox words and groups its questions in its own way and
changes them from time to time, so the answers below are by topic: find
each topic's question on the form and give the answer in the second
column. A question not listed here is answered from the same facts; if
one does not fit, stop and ask rather than guess.

The expected result is the lowest maturity label, suitable for all ages
("Minimal" at the time of writing). Redo the questionnaire whenever a
release adds material content, such as a Chapter with new themes (the
[release checklist](../RELEASE_CHECKLIST.md)).

| Topic on the form | Answer | The fact | Backed by |
|---|---|---|---|
| Violence (fighting, weapons, harm to people or animals) | **None** | Nobody fights or is hurt. The one threat is a tree-chopping machine that the village means to use on the forest; Amy stands in front of it and explains, and the village listens and stops. No weapon is used | The [canon](../story/canon.md) and the [style guide](../story/style-guide.md) section 4 (no violence beyond the threat of the machine to the trees, no injury); canon Lines are locked by `tests/lune/content/Canon.spec.luau` |
| Blood and gore | **None** | No blood, injury or death anywhere | Style guide section 4 |
| Fear, horror, frightening themes | **None** | A forest "loomed" in Clara's words; the lion is gentle and framed "never menacing"; no jump scares, no chases at the player | Style guide sections 1 and 4; [feel.md](../design/feel.md) section 2 (the Lion's Shot) |
| Crude humour | **None** | The humour is Sam bringing Amy back each time | Style guide section 1 |
| Romance and sexual content | **None** | None in the story | Style guide section 4 (no romance) |
| Alcohol, drugs, tobacco | **None** | None in the story or the world | Canon; the Scenes in `src/content/scenes` |
| Strong language | **None** | Every Line is Clara's words or written to the style guide, and approved in review | Style guide; the definition of done ("new Lines ... for approval") |
| Gambling, paid random items | **None** | The game sells nothing and has no random rewards | `tools/guard purchases-and-text` (nothing under `src/` reaches MarketplaceService or prompts a purchase) |
| In-experience purchases | **None** | No passes, no developer products, no Robux prompts | `tools/guard purchases-and-text`; the release checklist |
| Social hangout, meeting other players | **No** | Single player: one player per server, so a player never meets another | Max Players = 1, the invariant **Single player**: `tests/engine/maxplayers.luau` on Dev; the release checklist on Release |
| Voice chat | **No** | Not enabled; with one player per server there is no one to hear | The owner leaves voice chat off in the experience's settings (Communication); see Open questions |
| Text chat | Roblox's own chat window only; no in-game chat | The game adds no chat of its own and takes no typed text; with one player per server there is no one to chat with. Release has no chat commands (the Dev shortcuts are stripped when the release job publishes) | `tools/guard purchases-and-text` (no TextBox under `src/`); the glossary's **Dev shortcut** |
| Free-form user creation (building, drawing, writing others see) | **No** | Players walk, talk and read; they make nothing others can see | `tools/guard purchases-and-text` (no TextBox); there is no building in the Story |
| Political, religious or real-world sensitive themes | **None** | A child persuades her village to look after a forest. Care for nature is the theme, with no real place, group or event named | Canon; style guide section 4 |
| Real people's personal information | **None** | The author is credited as "Clara" only; no full name, no web address | `tools/guard names`, `tools/guard links` and `tools/guard store-links` |
| External links | **None** | Nothing in the game or on the store page links outside Roblox | `tools/guard links`, `tools/guard store-links` |
| Data collected | Progress and Settings only, in Roblox's DataStores; Roblox Analytics custom events with no personal data | The Save holds Progress, Checkpoints and Settings; analytics events carry Story ids only | `src/core/Save.luau`; `src/core/AnalyticsEvents.luau`; [ANALYTICS.md](../ANALYTICS.md) |

## Before submitting

- [ ] The answers above still hold for the build being released: no
      Chapter added since this draft with new themes. If one has, redo
      the topics it touches with the same care.
- [ ] Voice chat is off (the release checklist's step), and the owner
      has decided on Roblox's text chat window (see Open questions).
- [ ] The result shown after submitting is the all-ages label; if it is
      not, do not publish to Release until the answer that raised it is
      understood.

## Open questions for the owner

- **Roblox's text chat window.** The game has no chat of its own, but
  Roblox shows its chat window by default. With one player per server
  nobody else can read it. Hiding it (TextChatService's chat window off)
  is one line in a later PR; the Dev shortcuts use chat commands, so it
  would be hidden on Release only. Say if you want it.
