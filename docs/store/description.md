# The store page's words

What the owner pastes into the Release experience's store page. Written
in the [style guide](../story/style-guide.md)'s voice for the page, not
the game: short plain sentences, standard spelling, Clara's first name
only, no web address, nothing to buy. These are new words, not canon,
for the owner's and Clara's approval.

Where: the Creator Hub, the Release experience, **Configure**, then
**Basic Settings** (the name and the description). Paste each block's
text without the fence. The kit's art is in [art.md](art.md).

## Name

```text
Amy and the Rain Forest
```

23 characters; the Roblox limit is 50. Dev keeps its own name, "Amy and
the Rain Forest (Dev)", which `tests/engine/smoke.luau` checks begins
with the same words.

## Description

```text
A gentle story game for ages 7 to 12, from the story by Clara.

One beautiful Sunday, Amy wants to explore. Sam the dog has other ideas! Slip out through the garden gate, cross the field and find the gap in the wall of giant trees. Behind it is a hidden world full of colour.

Meet a maroon squirrel, an orange fox and a golden lion. Follow the glowing flowers. Then hurry home, because the forest needs Amy's help.

- Four short chapters, played on your own
- Read at your own pace: nothing moves on until you tap
- Bigger text, high contrast and easy-read letters in Settings
- Nothing to buy
- Your place in the story is saved

A story by Clara.
```

About 640 characters; the Roblox limit is 1,000.

Each claim and what backs it:

| Claim | Backed by |
|---|---|
| Four chapters | `src/content/Story.luau`; `tests/engine/smoke.luau` counts them |
| Played on your own | Max Players = 1: `tests/engine/maxplayers.luau` on Dev, the [release checklist](../RELEASE_CHECKLIST.md) on Release |
| Nothing moves on until you tap | The no-timed-reading test in `tests/lune/core/DialogueViewModel.spec.luau`, and the server waits for every `DialogueFinished` (`tests/lune/place/Wiring.spec.luau`) |
| Bigger text, high contrast, easy-read letters | `src/core/Settings.luau` and its spec |
| Nothing to buy | `tools/guard purchases-and-text` |
| Your place is saved | `src/server/Persist.luau`, `tests/engine/persist.luau` |
| By Clara | `tools/guard names`: no surname under `src/`, `assets/` or `docs/store/` |

The story facts (the gate, Sam, the wall of trees, the three animals, the
glowing flowers, hurrying home) are all in [canon](../story/canon.md);
the description adds none.
