# Feel — camera, input, readability and onboarding

Version 1. How the game should look, read and respond on every device
class, written so each rule can be checked: by a tier 3 on-screen
assertion where the engine can measure it, by the agent's
[visual rubric](#7-visual-rubric) where it cannot, and by the owner on a
real phone and tablet ([release checklist](../RELEASE_CHECKLIST.md)).

Terms are as defined in the [glossary](../GLOSSARY.md). Text rules for
what Lines say are in the [style guide](../story/style-guide.md); this
file covers how they are shown.

**Units.** Sizes are in Roblox UI units (the offset units of `UDim2` and
`TextSize`, before `UIScale`). One unit is about 1/160 inch on a phone,
about 1/132 inch on a tablet (tablet points are physically larger), and
one pixel, about 1/96 inch, on a PC at 100% scaling. Tier 3 converts with
the emulated device's scale factor; a Phase 1 check on the real phone and
tablet confirms these ratios, and this file is corrected if they are off.

## Invariants

**Amy's face is never seen.** This is a quirk of Clara's story: we always
see Amy from behind. It holds from the first release onwards, on every
device class, in free play, at spawn and respawn, during Dialogue and in
every Shot. Future chapters may play with it (a mirror that still does
not show her face) but never break it.

- **The camera rule.** The camera stays within **60° of directly
  behind Amy**: unit(camera − Amy) · (−facing) ≥ 0.5. This is 30° inside
  her rear hemisphere, so her profile is not shown either. Tier 3 asserts
  it at every Shot keyframe and at least every 0.5 s of play.
- **The follow camera.** In free play the camera follows from behind on
  every device class. The player may turn the view, and Amy turns with
  it, as with Roblox's shift-lock, under touch as well as mouse and
  keyboard. No free-look orbits round to her front.
- **Art.** No chapter card, illustration, icon, thumbnail or reflective
  surface shows her face.

## 1. Device classes

The client binder picks the class when it starts and again whenever the
viewport size changes (rotation, window resize):

| Class | Detected when | Designed for | Viewing distance | Orientations |
|---|---|---|---|---|
| **PC** | Keyboard or mouse is the last input used | 1280 × 720 to 2560 × 1440 window | 60 cm | landscape |
| **Phone** | Touch, and the viewport's shorter side is under 600 units | 6-inch phone, about 844 × 390 units | 30 cm | landscape and portrait |
| **Tablet** | Touch, and the shorter side is 600 units or more | 11- to 13-inch tablet, up to about 1376 × 1032 units | 40 cm | landscape first; portrait works |

Gamepad is later; when it arrives it uses the PC layout with on-screen
button glyphs.

### Layout rules

The same rules apply to every class; only the numbers differ.

- **Safe area.** All UI sits inside the `GuiService` safe-area insets
  (notch, home bar, rounded corners).
- **Dialogue box** at the bottom centre. Its text column is as wide as
  the safe area allows, minus 24 units of padding each side, but never
  wider than **60 characters** at the current text size (see
  [§3](#3-text-and-readability)).
- **Objective panel** at the top right; on phone it collapses to an icon
  while a Dialogue is shown.
- **Touch control zones** are the bottom-left and bottom-right corners:
  35% of the width by 40% of the height on phone, 25% by 35% on tablet.
  The Roblox thumbstick sits in the left zone; a talk-and-advance button
  sits in the right zone, reachable by the right thumb. Thumbs reach from
  the edges, so no control sits anywhere else.
- **Nothing covers the subject.** No UI element overlaps the projected
  bounding box of the speaker's head during `shot:Dialogue`, the
  Objective target during free play, or a touch control zone. Tier 3
  asserts this by projecting the head's bounds with
  `WorldToViewportPoint` and intersecting them with every visible UI
  element's `AbsolutePosition` and `AbsoluteSize`.

## 2. Shots

A Shot takes the camera from the follow camera, frames something, and
hands it back over 0.5 seconds. Every Shot is framed from behind Amy or
over her shoulder and obeys the [camera rule](#invariants) at every
frame of its move; a Shot that would show her face is not a valid Shot.
Shots move slowly (no cuts faster than
0.5 s, no shake, no roll) because sudden motion is uncomfortable for many
children. A Shot that accompanies a Dialogue holds until
`DialogueFinished`; any other Shot lasts at most 4 seconds. The player
can always advance; a Shot never adds waiting. The Shot names are listed
in the [glossary](../GLOSSARY.md#shots).

| Shot | Used by | Subject and framing | Moves |
|---|---|---|---|
| `shot:Dialogue` | Every Dialogue whose Speaker is a Character in the world | Two-shot over Amy's shoulder, camera at the speaker's eye height, the projected head point inside x 0.33–0.67 and y 0.15–0.5 of the viewport. Narrator-only Dialogue keeps the current camera. | Eases in over 0.5 s, then still |
| `shot:ForestWallReveal` | `chapter2.walk_to_forest.onComplete`, with canon Line 6 | Low behind Amy, looking up: the wall of trunks fills the width, the gap is centred, the cream sky and canopies above. Ends with the gap clearly visible, so the next Objective is obvious. | Slow tilt up from Amy to the canopy over about 3 s |
| `shot:MeetCharacter` | The first `TalkedTo` of each animal in `chapter3`, before its `shot:Dialogue` | The animal in full, facing Amy, as the table below sets | As the table below sets |
| `shot:MachineFinale` | `chapter4.explain.onComplete` (`beat:machine_stops`) and the Ending | Wide, from behind Amy and the crowd, looking toward the machine and the trees: Amy small between the stopped blade and the giant trees | Holds while the machine reverses, then tilts up to the treetops for the Ending's Lines |

`shot:MeetCharacter` takes the Character as its argument
(`FrameShot(MeetCharacter, Fox)`), so a new animal adds a row here, not a
new Shot:

| Character | Framing | Move |
|---|---|---|
| `character:Squirrel` | Low behind Amy, the Squirrel among the roots ahead of her | Arc of about 15° |
| `character:Fox` | Bright orange against the paradise greens | Arc of about 15° |
| `character:Lion` | Low behind Amy, looking up at him so he looks big, but in warm light and calm: he is gentle, never menacing | Slow push in |

Tier 3 captures a screenshot at every Shot for every device class and
checks that a ray from the camera reaches the subject's head without
occlusion, and asserts the [camera rule](#invariants) at every Shot and
at sampled frames.

## 3. Text and readability

### One rule for text size

**The lower-case letters of essential text subtend at least 0.3° at the
device class's viewing distance.** About 0.2° is where reading starts to
slow even for fluent adults; our readers are 7 to 12 and many are not yet
fluent, so we sit half as high again above it. Taking lower-case height
as half the text size:

| Class | Unit size | Distance | Dialogue body | Angle | Speaker, Objective | Hints, optional |
|---|---|---|---|---|---|---|
| Phone (6-inch) | 1/160 in | 30 cm | **20** | 0.30° | 18 | 14 |
| Tablet | 1/132 in | 40 cm | **24** | 0.33° | 20 | 16 |
| PC | 1/96 in | 60 cm | **24** | 0.30° | 20 | 16 |

So the **minimum dialogue text size on a 6-inch phone is 20 units**: an
em of about 3.2 mm and a lower-case height of about 1.6 mm at 30 cm. For
comparison, Apple's default body text for adults is 17 points, and
today's client uses 21 for the body, 16 for the Objective and 14 for the
hint.

### One rule for line length

**At most 60 characters per line of dialogue, on every class and at
every text size.** Comfortable reading for adults is roughly 45 to 75
characters per line; children's books set shorter lines because the
return sweep to the next line is where young readers lose their place.
60 is the middle of the adult range.

Average character width is about half the text size, so tier 3 asserts
the text column's `AbsoluteSize.X` is at most **30 × `TextSize`**. On a
13-inch tablet at 24 units that is a **720-unit** column in a 768-unit
box, centred. Today's box at 62% of a 1376-unit-wide tablet holds about
77 characters per line, so the cap matters.

### Other text rules

- A Line never scrolls: the dialogue box grows to fit (at most 40% of
  the screen height in phone portrait) and `TextFits` must be true. The
  [style guide](../story/style-guide.md#3-reading-level-ages-7-to-12)
  keeps Lines short and untimed so this holds.
- Contrast between text and its background is at least 4.5:1, and 7:1 in
  the high-contrast setting. Tier 3 computes it from `TextColor3`,
  `BackgroundColor3` and transparency over the backdrop, sampling pixels
  only where the backdrop is the 3D world.
- Typewriter reveal is allowed, and a tap completes it instantly before
  a second tap advances.
- A text size setting scales all text up by up to 1.5×; every rule here
  must still pass at the largest setting.

### Title screen

The title screen emulates the story website's title overlay (reference:
[`reference/website-title-overlay.png`](reference/website-title-overlay.png),
a phone screenshot of the website). Over the `ui:title_screen` image, Clara's
scene of the forest wall:

- a rounded pill label, "a little tale of the wild";
- then "Amy", and below it "& the Rain Forest", in a hand-written script;
- the words are white, except "Rain Forest", which is gold; each has a soft
  dark shadow, so it reads over the canopy.

The words are game-rendered text, never part of the image.

## 4. Touch targets

- Every touch target is at least **48 × 48 units**, with 8 units between
  targets. Tier 3 fails anything under the plan's hard floor of 44.
  Children's fingers are less precise than adults', so we design above
  the floor.
- Proximity prompts are the universal "talk" affordance on every class;
  on touch their button meets the same size rule.
- Tapping anywhere on the dialogue box advances it, as well as the
  talk-and-advance button.

## 5. Input

- One action per verb: move, talk (use a prompt), advance dialogue. No
  jump requirement anywhere in the Story.
- PC: WASD or arrows to move, E to talk, click, E or Space to advance.
  Touch: the controls in [§1](#layout-rules).
- Every input gets feedback within 100 ms: the client logs a Cue played
  or a named UI tween started, with a timestamp, and tier 3 asserts the
  gap from input to that event.

## 6. Onboarding: the first minute

The first minute teaches the three verbs in the order the Story needs
them, inside Chapter One, with no separate tutorial. Each hint appears
when it is needed, disappears as soon as the player succeeds, and comes
back if the player has made no progress for 10 seconds. Hints never
block play.

| Step | What the player sees | Hint (PC / touch) | Done when |
|---|---|---|---|
| 1 | The `chapter1` card, about 3 s, tap or click to skip | none | Card fades |
| 2 | The first Narrator Line ([canon Line 1](../story/canon.md#canon-lines)) | "Click or press Space to continue" / "Tap to continue", shown large on this first Line only | `DialogueFinished` |
| 3 | Objective "Ask Dad if you can go outside" appears with a marker over Dad | none; the panel briefly glows | Objective shown |
| 4 | Amy in the garden, Dad nearby | "Use WASD or the arrow keys to walk" / a glowing ring on the thumbstick and "Drag here to walk" | Amy has moved 4 studs |
| 5 | Dad's talk prompt | "Press E to talk" / the prompt button pulses | `TalkedTo(Dad)` |
| 6 | Dad's Dialogue, then the next Objective | none: the advance hint is now learned | `QuestCompleted(chapter1.ask_dad)` |

By the end of step 6 the player has walked, talked, advanced dialogue and
read an Objective, on every device class, in about a minute.

## 7. Visual rubric

The agent scores every new or changed screenshot against these
criteria, by looking at it, before proposing a baseline. First, a gate:
**Amy's face is not visible** in the frame, and no chapter card or
illustration in it shows her face. A frame that fails the gate fails,
whatever its scores. Then each criterion scores 0 (fails),
1 (acceptable) or 2 (good).

| Criterion | 2 means |
|---|---|
| Composition | The subject of the Shot or Scene is in the middle third and not cut off; the eye goes to it first |
| Readability | Any dialogue or Objective is legible at the device's size and does not cover the subject |
| Style | Looks hand-drawn: scribbly grass, round two-tone canopies, trunks shoulder to shoulder, as in Clara's hero illustration |
| Palette | Dominant colours from Clara's palette (below); no stray default grey parts |
| Lighting | Neither too dark to read on a phone in daylight nor blown out; the paradise is visibly brighter and more saturated than the ordinary world |
| Clutter | Nothing distracting behind the speaker or the Objective target |
| Characters | Animated (no T-pose), standing on the ground, the speaker facing Amy |

**Pass:** no criterion at 0 and a total of at least 11 out of 14. The
PR lists the scores for every changed baseline.

**Clara's palette** (`src/content/palette.luau`): deep green
`#23401d`, moss `#5a8a44`, bark `#6b4426`, gold `#e7b53a`, red
`#c2402f`, grape `#7c4dff`, bubblegum `#ff5da2`, cream sky, and the grass
and canopy greens.

### What each Scene must show

| Scene | Must show |
|---|---|
| `scene:Garden` | Amy's red house with its gold roof, the fence and the gate opening; Sam by the gate |
| `scene:Village` | A few small houses behind Amy's |
| `scene:Field` | Wide scribbly-grass field, little gold and red flowers, black "v" birds in a cream sky |
| `scene:ForestWall` | Giant trunks standing shoulder to shoulder, round two-tone canopies, one narrow gap just Amy's size |
| `scene:Paradise` | Moss, gold, bubblegum and grape; shafts of light; drifting sparkles; a trail of glowing flowers |
| `scene:HeartGlade` | The ring of big glowing flowers, open space around it |

## 8. Automatic translation is off

Roblox can translate an experience's text automatically. It stays
**off** on both Dev and Release. Automatic translation treats Clara's
deliberate spellings ("beautyfull", "tryed", "brang", "thier") as
mistakes and would "correct" or mistranslate them, which breaks the
[canon rule](../story/canon.md#the-rule) for every player who sees the
game in another language. Translations, if they ever come, are written
by people and approved like any other new text.
