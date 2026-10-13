# The store page's icon and thumbnails

What each image must be, which of Clara's illustrations qualify, and what
the owner checks by eye before setting them. Every image follows the
invariant **Amy's face is never seen** ([glossary](../GLOSSARY.md#invariants),
[feel.md](../design/feel.md#invariants)): she is shown from behind or not
at all. The Manifest's `amy` field (`absent` or `from-behind`) records
which; there is no third value ([ASSETS.md](../ASSETS.md)).

Where: the Creator Hub, the Release experience, **Configure**, then
**Basic Settings** (the icon, and the thumbnails under it). Store art is
not uploaded by CI (`upload: false` in the Manifest); Roblox moderates it
when the owner sets it. The words are in [description.md](description.md).

## The rules for every image

- **No face.** Amy only from behind, or not shown; no other person's face
  either, since the family roles are drawn from Clara's book.
- **No text in the image** beyond what Clara drew: no title, no web
  address, no name. The game renders its own title in game.
- **Nothing that suggests buying**, no Robux, no "free" or "new" badges.
- **Clara's own colours** (feel.md, "Clara's palette"); no screenshots
  edited to look busier than the game.

## Icon (`store:icon`)

| | |
|---|---|
| Size | 512 × 512 PNG; Roblox rounds its corners, so nothing that matters within about 50 pixels of a corner |
| Status | Placeholder (`assets/images/icon.png`): a plain stand-in, not for Release |
| Must read at | 150 × 150, the size the Roblox home page shows it |

No square crop of the illustrations we have reads at that size with Amy
in it (brief 009's assessment, [ASSETS.md](../ASSETS.md)), so the icon is
the first piece to ask Clara for. Until she draws it, the best stop-gap
is a square crop of `ui:title_screen` (`assets/images/title.png`, 2000 ×
1125, `amy: absent`): the wall of trunks with the nests in the canopy,
x 500 to 1625, y 0 to 1125, scaled to 512 × 512. It has no Amy at all, so
the face rule holds without a check, but it reads as "trees", not as this
story; the owner decides whether to ship it or wait.

## Thumbnails (`store:thumbnail_1` to `_3`)

| | |
|---|---|
| Size | 1920 × 1080 PNG or JPG (16:9); Roblox takes up to 10 |
| Shown | Large on the experience page, small in search; the first one matters most |

| Thumbnail | File | `amy` | Qualifies? | Notes |
|---|---|---|---|---|
| `store:thumbnail_1` | `assets/images/card-chapter2.png` (2000 × 1125) | `from-behind` | **Yes** | Clara's coloured scene: Amy from behind on the field, facing the wall of trunks. Scale to 1920 × 1080 (same 16:9 shape, no crop). Her hair covers the back of her head; no part of her face shows |
| `store:thumbnail_2` | `assets/images/card-chapter3.png` | `absent` | **No, placeholder** | A plain stand-in until Clara draws the animals in the paradise |
| `store:thumbnail_3` | `assets/images/card-chapter4.png` | `absent` | **No, placeholder** | A plain stand-in until Clara draws the machine and the village |
| (optional) | `assets/images/title.png` (2000 × 1125) | `absent` | Yes | The wall of trunks with no one in front of it; without the game's title over it, it is quieter than `thumbnail_1`. Scale to 1920 × 1080 |

So Release 1.0 can ship with one or two thumbnails from Clara's art; more
come with her new drawings, or as in-game screenshots from the visual pass
(brief 016), which then go through the same rules and the
[feel rubric](../design/feel.md#7-visual-rubric).

## What the owner confirms by eye

The agent looked at `card-chapter2.png` and `title.png` and found no face;
a person confirms it before anything is set on the store page:

- [ ] `store:thumbnail_1` (`card-chapter2.png`): Amy is from behind, and
      no part of her face (no cheek, no profile) shows at full size.
- [ ] The icon, whatever it is: no face, and it reads at 150 × 150.
- [ ] No image has text, a web address, a name or a purchase badge.
- [ ] The Manifest's `amy` field says what each image shows, and
      `moderation` is updated once Roblox has reviewed the store art.
