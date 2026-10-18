# Assets

How an image, sound or model gets into the game: the manifest, the
licence rules, the upload limits, and how moderation is tracked. Plan
background: [`DEVELOPMENT_PLAN.md`](DEVELOPMENT_PLAN.md) sections 2.2,
3, 5.5 and 7. Terms are as in the [glossary](GLOSSARY.md).

**Only CI uploads.** Assets reach Roblox only through the
`upload-assets` workflow, with the Dev key, on the owner's account. The
agent never holds a key: it changes the manifest, and the workflow does
the rest.

## The pieces

| File | What it is |
|---|---|
| `assets/manifest.json` | Every asset the game references: name, kind, file, Roblox asset id, the SHA-256 of the file uploaded, moderation status, creator, licence and origin. |
| `assets/images/`, `assets/audio/`, `assets/meshes/` | The files. Clara's illustrations, placeholders, sounds, models. |
| `src/shared/AssetIds.luau` | Generated from the manifest: asset name → `rbxassetid://` content id, for every entry with an id that the game shows: uploaded, or a [font](#fonts). Never edited by hand. |
| `tools/check-assets.luau` | Tier 0 (run by `tools/check.sh`): the manifest is valid, every asset id the scan finds is in it (see [What the tier 0 scan catches](#what-the-tier-0-scan-catches)), and `AssetIds.luau` matches it. |
| `tools/upload-assets.luau` | The uploader. Run only by CI; `--dry-run` anywhere. |
| `.github/workflows/upload-assets.yml` | Runs the uploader on demand and opens the "Asset ids" PR. |

## The manifest

```json
{
  "name": "card:chapter2",
  "kind": "image",
  "path": "assets/images/card-chapter2.png",
  "assetId": null,
  "moderation": "pending",
  "upload": true,
  "placeholder": false,
  "amy": "from-behind",
  "creator": "Clara (drawing); coloured for the story website",
  "licence": "owner",
  "origin": "laazyj/jasonduffett.net@4940d10 packages/clara/assets-src/hero.png, cropped to 16:9 ..."
}
```

| Field | Meaning |
|---|---|
| `name` | The Asset name the game uses; see [Asset names](#asset-names). Unique. |
| `kind` | `image`, `audio` or `model`. The file's extension must be one the Assets API takes for that kind (`tools/opencloud.luau`, `ASSET_CONTENT_TYPES`). Or, with no file, `font`, a Creator Store family (see [Fonts](#fonts)), or `library-audio`, a track from Roblox's audio library (see [Cues](#cues-the-placeholders-and-the-shopping-list)). |
| `path` | The file, under `assets/`. Two entries may share a file (a thumbnail that is a Chapter card). None for a font. |
| `assetId` | The Roblox asset id as a string of digits, or `null` until uploaded. Written by the uploader only, except a font's, which is its Creator Store id and is required. |
| `sha256` | The SHA-256 of the file that was uploaded. Written by the uploader only. None for a font. |
| `moderation` | The Moderation status; see [Moderation](#moderation). |
| `upload` | `false` for files the game never shows: store art (set on the Creator Dashboard by the owner) and Character references; and `false` for a font, which is referenced, never uploaded. |
| `placeholder` | `true` for a stand-in until the real piece is drawn. |
| `amy` | Images only. `absent` or `from-behind`. There is no third value, because **no image shows Amy's face**. Whoever adds an image states which it is; the reviewer checks it. |
| `creator` | Who made it. |
| `licence` | See [Licences](#licences). |
| `attribution` | Required for `cc-by`: the credit line. |
| `origin` | Where the file came from and what was done to it (crop, resize), so it can be traced and redone. |

### Asset names

An Asset name is a prefix saying what the Asset is for, then a name, in
the forms of the [glossary's Ids](GLOSSARY.md#6-ids): `card:` (Chapter
cards and the end card), `ui:` (frames, motifs, screens), `store:`
(store page art), `ref:` (references, never shown), `cue:` and `music:`
(Cues), `narration:` (a Chapter's narration file), `prop:` (Prop models),
`character:` ([Character models](#character-models)), `font:` (Creator
Store font families), `catalog:` ([Catalog items](#catalog-items)). The game looks an Asset up by its name in
`AssetIds.luau`; a name with no id yet is absent, and the game is to fall
back to plain UI (or silence, for a Cue). The client binder reads
`AssetIds.luau` for the Chapter cards, the UI frames, the Title screen and
its font, and `src/client/Audio.luau` for the Cues and narration.

## How to add an asset

1. Put the file under `assets/images/`, `assets/audio/` or
   `assets/meshes/`. A free Creator Store model is fetched on the Mac with
   `lune run tools/studio-playtest/fetch-model --asset <id> --name prop:<name> --out assets/meshes/<name>.rbxm`
   (plan section 5.5, [`MAC_RUNNER.md`](MAC_RUNNER.md#fetching-creator-store-models-studio-wins-spike-mac-002)),
   which refuses a model with scripts and prints the manifest entry. For an image, check the rules in the GitHub issue
   "Illustrations needed for the game": no words in the picture, the
   important part inside the middle 80%, nothing that identifies anyone,
   and **never Amy's face**.
2. Add an entry to `assets/manifest.json` with `"assetId": null` and
   `"moderation": "pending"`. Fill in `creator`, `licence` and `origin`.
3. Run `tools/check.sh` (or just `lune run tools/check-assets`). It notes
   the entry as waiting for upload.
4. To see what would be sent:
   `lune run tools/upload-assets --universe <dev id> --place <dev id> --creator-user 1 --dry-run`
   (any ids will do; nothing is sent).
5. Open the PR. After it merges, the owner (or the coordinator) runs
   **Actions → Upload assets → Run workflow** on `main`.
6. The workflow uploads every pending entry, then opens or updates the
   PR **Asset ids**, which changes only `assets/manifest.json` and
   `src/shared/AssetIds.luau`. Merging it is what makes the ids reach
   the game.
7. **Merge the Asset ids PR before running the workflow again.** Until it
   merges, `main` still lists every Asset as pending, so another run
   would upload them all again as new assets. The workflow refuses to
   start while that PR is open. This holds after a run that failed part
   way too: merge the PR with the ids it did get, then run again for the
   rest.

**To replace a file** (a placeholder swapped for Clara's drawing), just
replace the file under the same path and open a PR. Its SHA-256 no
longer matches the one recorded, so the next upload run sends it again.
Roblox cannot update an image or a sound in place, so it becomes a new
asset with a new id; the "Asset ids" PR shows the old id being replaced.

### Fonts

A font is a Creator Store font family the game references by its id, such
as `font:dancing_script` for the Title screen's lettering. To find one: in
Studio, **Toolbox → Creator Store → Fonts**. Only families Roblox has
published exist there, and Studio's Properties picker for `FontFace` shows
the built-in families only, so a Creator Store family is chosen by its id.
Its entry has kind `font`, no `path` and no `sha256`, `upload` false,
its Creator Store `assetId`, `moderation` `approved` (Roblox published
it), no `amy`, and licence `creator-store-free`; `creator` names the
designer and the publisher, and `origin` the listing and the font's
licence. Tier 0 holds all of that. `tools/upload-assets` skips it, and
`AssetIds.luau` lists it, so code names the Asset (`font:dancing_script`)
and looks its id up there, as for any other Asset.

### Character models

The animals (Sam, the Squirrel, the Fox, the Lion) are to be built from
free Creator Store models that ship with animations (plan sections 2.3 and
5.5). Until a Character has one it is drawn as its Placeholder, the
figure of parts whose colours, size and tail are in
`src/content/characters.luau`; the humans need none, being Roblox's R15
body made from their Description. The game picks which with `Story.build`:
`server/CharacterHost` looks for `ServerStorage.CharacterModels.<id>`, and
the place file holds that folder from `assets/meshes/characters/`
(`default.project.json`), so **committing the file is what brings a
Character model into the game**; nothing is uploaded.

What the Mac agent does for each animal:

1. Find a free model in Studio's Toolbox (Creator Store, Models) that
   reads as Clara's animal: the white dog, the maroon squirrel with a
   giant tail, the orangest fox, the golden lion, gentle and never
   menacing (`design/feel.md`). It must have a `Humanoid`, a part named
   `HumanoidRootPart` whose front faces the model's front (the root's
   look vector), and no scripts.
2. Fetch it:
   `lune run tools/studio-playtest/fetch-model --asset <id> --name character:Sam --out assets/meshes/characters/Sam.rbxm`.
   The tool refuses a model with scripts, so a model whose animations
   live in an `Animate` script is refused; take one whose animations are
   `Animation` objects.
3. The model's animations are to be `Animation` objects in a folder
   named `Animations` under the model, named `idle`, `walk` and `run` (any
   may be missing; the Character then stands still for it). If the model
   does not come that way, arrange it so in Studio and save it over the
   file the same way (`SerializationService`); `fetch-model` cannot yet do
   that step itself. CharacterHost loads these and plays `idle`, and
   `run` while the Character runs (`MoveCharacter` with `run`, as in
   `beat:sam_catches`).
4. Check each animation plays in the game on Dev. Roblox plays an
   animation in an experience only if the experience's owner (or Roblox)
   owns it, so another creator's animation ids may load and not play;
   then the owner uploads the model's animation (its KeyframeSequence) to
   their account and the folder's `Animation` takes that id. Record what
   was done in `origin`.
5. Add the entry the tool prints: kind `model`, the path above, `upload`
   false, licence `creator-store-free`, `creator` and `origin` as
   printed. Tier 0 holds a `character:` entry to that path and to
   `upload` false. Its mesh and animation ids stay inside the `.rbxm`,
   where the tier 0 scan cannot see them; review checks them.
6. Run the tier 2 suite (`tests/engine/characters.luau` loads each
   animation) and the tier 3 playtest: animation tracks playing, no
   T-pose, the speaker facing Amy, and screenshots of each Character
   against `design/feel.md`. Then the Placeholder can stay in content as
   the fallback, or go with the owner's say-so.

### Catalog items

The humans are Roblox's R15 body in the colours of their Description.
What colours cannot do (hair, sleeves, a skirt, shoes) is a Catalog item:
a free avatar item from the Marketplace that a Description wears in a
named slot. Amy's Description (`src/content/characters.luau`), from Clara's
`ref:Amy`, names five, each by its Asset name:

| Slot | Asset | Search the Marketplace (Avatar Shop) for, free only | Look |
|---|---|---|---|
| `hair` | `catalog:amy_hair` | Hair: "long brown hair", "long straight hair" | Long, dark brown, past the shoulders, covering the back of the head: what the camera sees most |
| `shirt` | `catalog:amy_shirt` | Clothing, Shirts (layered): "red sweater", "red long sleeve" | A red long-sleeved top, close to `#c2402f` |
| `skirt` | `catalog:amy_skirt` | Clothing, Dresses & Skirts (layered): "blue skirt" | A mid-blue skirt, about `#2f6fb5` |
| `leftShoe`, `rightShoe` | `catalog:amy_left_shoe`, `catalog:amy_right_shoe` | Clothing, Shoes (layered; a pair is two items): "brown shoes" | Plain brown shoes, about `#7a4a2a` |

Until a slot's Asset has an id, Amy is built without it: her light skin
(`#dba97e`) on head, arms and legs, and her red jumper on the torso.

**Recording one is one Manifest entry**, as for a [font](#fonts): kind
`catalog`, the name above, no `path` and no `sha256`, `upload` false, the
item's `assetId` from its Marketplace page, `moderation` `approved`,
`placeholder` false, licence `creator-store-free`, `creator` the item's
creator and `origin` its title and page. Then run
`lune run tools/check-assets --write-ids`, which writes the id into
`src/shared/AssetIds.luau`. `server/CharacterHost` reads the slot's id
there and Amy wears the item from her next spawn. Tier 0 holds the entry
to these rules. Pick items with no face and nothing on the face, and check
on Dev that the hair covers the back of her head (the camera never sees her
face, so nothing in front matters). Only the Player Character wears
Catalog items so far: Dad, Mum and the villagers are copies of one R15
body in their colours, and giving them slots means applying their
HumanoidDescription in `CharacterHost.buildHuman` too.

### Cues: the placeholders and the shopping list

Every Cue in the [glossary](GLOSSARY.md#cues) starts as a synthesised
placeholder, so the game is never silent where it should not be: gentle,
quiet, a few seconds each, the music and ambience looping seamlessly.
`lune run tools/synth-cues` writes them under `assets/audio/` from
`tools/lib/synth.luau`, and tier 1 checks each committed file is what its
recipe renders. They are clearly placeholders: plain tones and filtered
noise, no instruments, no voice.

The real Cues come from **Roblox's own audio library** on the Creator
Store: free, already approved, and never uploaded, so they cost none of
the monthly audio uploads. The library is the owner's to browse (a cloud
session cannot reach roblox.com). To find one: in Studio, **Toolbox →
Creator Store → Audio** (or create.roblox.com, Creator Store, Audio),
choose **Music** or **Sound Effects**, set the length, search, and listen.
Copy the asset id from the listing.

**Replacing a placeholder is one manifest change.** Its entry becomes a
`library-audio` entry, as a [font](#fonts) is: kind `library-audio`, no
`path` and no `sha256`, `upload` false, the library `assetId`,
`moderation` `approved`, `placeholder` false, licence
`creator-store-free`, `creator` the listing's artist and publisher and
`origin` its title and id. Then delete the WAV and run
`lune run tools/check-assets --write-ids`, which writes the id into
`src/shared/AssetIds.luau`. Tier 0 holds all of that; the uploader skips
the entry.

The shopping list, in Clara's palette of feeling: gentle and warm,
nothing scary, nothing loud. Music sits under the Lines, so pick tracks
without vocals and without big drums.

| Cue | Search for | Length | Loop |
|---|---|---|---|
| `music:theme` | Gentle, hopeful, whimsical; piano or music box with soft strings; "children's story", "fairy tale", "lullaby" | 1–3 min | yes. The original theme tune (GitHub issue "Original theme tune for the game") replaces it if delivered |
| `music:home` | Calm, cosy, pastoral; acoustic guitar or light piano; "sunday morning", "countryside", "cosy home" | 1–3 min | yes |
| `music:field` | Curious, airy, open; flute or light woodwinds; "adventure begins", "meadow", "exploration" (light) | 1–3 min | yes |
| `music:paradise` | Magical, wondrous, shimmering; harp, celesta, soft pads; "enchanted forest", "fantasy", "magic garden" | 1–3 min | yes |
| `cue:ambience_home` | A garden on a sunny day: birdsong, a light breeze, no traffic or people; "garden ambience", "birds daytime" | 30 s or more | yes |
| `cue:ambience_field` | An open field: wind through grass, distant birds; "meadow ambience", "field wind" | 30 s or more | yes |
| `cue:ambience_paradise` | A gentle rainforest: soft insects, far birds, leaves, no thunder or heavy rain; "jungle ambience calm", "rainforest day" | 30 s or more | yes |
| `cue:chapter_card` | A soft chime or harp flourish; "magic chime", "harp glissando short" | 1–3 s | no |
| `cue:prompt` | A soft, friendly UI click or pop; "UI select soft", "bubble pop" | under 0.5 s | no |
| `cue:pickup` | A small sparkle or twinkle; "collect sparkle", "magic twinkle" | under 1 s | no |
| `cue:footstep` | One soft step on grass; "footstep grass" (one step, not a walk loop) | under 0.3 s | no |
| `cue:sam_bark` | A friendly medium dog's bark, not aggressive; "dog bark friendly", "small dog woof" | under 1 s | no |
| `cue:paradise_shimmer` | A rising magical shimmer; "magic reveal", "sparkle swell" | 1–3 s | no |
| `cue:machine_rumble` | A big machine's engine rumbling closer, not menacing; "tractor engine", "bulldozer idle" | 2–5 s | no |
| `cue:machine_stop` | An engine winding down and switching off; "engine shut off", "machine power down" | 1–3 s | no |

A Cue with no asset id is silent, never an error, so a placeholder can
be replaced one at a time. If the library has nothing suitable for a Cue,
the alternatives are, in order: a free-licence (`cc0` or `cc-by`) file
uploaded as `audio`, then keeping the synthesised one.

**Narration** (plan section 7) is the owner's recording, uploaded: one
file per Chapter, `narration:<chapter id>` (the last Chapter's also reads
the Ending), with each canon Line's start and end in the Narration table,
`src/content/narration.luau`. Tier 1 holds the table to the canon Lines.

**Uploads, planned.** This brief's placeholders are 15 audio uploads in
one run; narration is 4 more, one a Chapter, run when the recordings
arrive. Both fit the 100 a month an ID-verified account has; without
verification (10 a month) the run stops part way, keeping the ids it got,
and the next month's run does the rest. Every Cue replaced by a library
pick needs no upload at all.

### What the tier 0 scan catches

`tools/check-assets` reads every file under `src/`, whatever its
extension, and `default.project.json`, matching case-insensitively. It
fails on:

- an asset id in `rbxassetid://<id>`, `…/asset/?id=<id>`, `…/asset?id=<id>`
  (the old and the asset delivery URLs) or `rbxthumb://…id=<id>` that is
  not in the manifest;
- any of those schemes not followed by the id written out as digits, such
  as `"rbxassetid://" .. id`, `` `rbxassetid://{id}` `` or
  `string.format("rbxassetid://%d", id)`;
- `Content.fromAssetId(` anywhere but `src/shared/AssetIds.luau`.

So code reaches an Asset only through `AssetIds`. The scan does not catch
an id with no scheme at all (a bare number passed to an engine API such
as `InsertService:LoadAsset`), or a scheme split across strings
(`"rbxasset" .. "id://"`), or an id inside a binary `.rbxm` model, which
is compressed. Review catches those. A thumbnail of a user
(`rbxthumb://type=AvatarHeadShot&id=…`) is flagged too; the game shows
none.

Tier 0 also cannot tell an `assetId` or `sha256` the uploader wrote from
one typed in, so **review is the gate**: a change to either belongs only
in the "Asset ids" PR the workflow opens.

## Licences

| `licence` | Use for | Rules |
|---|---|---|
| `owner` | Clara's illustrations (the owner's family's work, used with the owner's permission), and placeholders generated in this repository | Record in `origin` which original it came from. |
| `creator-store-free` | Free models, sounds and fonts from the Creator Store | Fetched as the plan's section 5.5 says. Record the Creator Store asset id and creator in `origin`. Only items marked free. |
| `cc0` | Public-domain sounds or images | Record the source URL in `origin`. |
| `cc-by` | Free-licence sounds or images that need credit | `attribution` is required and goes in the credits. |
| `synthesised` | Audio generated for this game | Record the tool and settings in `origin`. |

Nothing else: no paid assets, nothing "found online" without a licence,
and no audio from commercial music.

## Upload limits

From the Roblox Assets API guide, as checked in
[`OPEN_CLOUD.md`](OPEN_CLOUD.md#what-was-verified-against-robloxs-documentation):

| Kind | Formats | Limits |
|---|---|---|
| Image | `.png`, `.jpg`, `.jpeg`, `.bmp`, `.tga` | Under 8000 × 8000 pixels. |
| Audio | `.mp3`, `.ogg`, `.wav`, `.flac` | Up to 7 minutes. **10 uploads a month without Roblox ID verification, 100 with it.** Private to the uploading account's experiences. |
| Model | `.fbx`, `.gltf`, `.glb`, `.rbxm`, `.rbxmx` | Uploaded as a package. `.rbxm` edited outside Studio may not work. |

Every file is at most 20 MB (tier 0 checks it). Because of the audio
cap, narration is batched one file per Chapter (plan section 7), and
the account must be ID-verified before brief 013. The Cues come from
Roblox's audio library where it can, which needs no upload; see
[the upload plan](#cues-the-placeholders-and-the-shopping-list).

## Moderation

Every uploaded asset is moderated by Roblox. The manifest records where
it is:

1. `pending`: in the manifest, not uploaded yet.
2. `reviewing`: uploaded; Roblox has not decided. The game can already
   use the id on Dev, but the asset may show as blank until approved.
3. `approved`: safe to ship.
4. `rejected`: Roblox refused it. Replace the file (or fall back to the
   plain placeholder) and run the upload again.

Each upload run also asks Roblox about every asset still `reviewing` and
records any change in the "Asset ids" PR, so running the workflow again
a day later updates the statuses. **Before a Release**, every asset the
game shows must be `approved` (the release checklist). Store art
(`upload: false`) is moderated when the owner sets it on the Creator
Dashboard.

## Safety

The [safety rules](OPEN_CLOUD.md#safety-rules) of the Open Cloud tools
apply, the Release refusal included: `--universe` and `--place` name the
experience the Dev key is scoped to. On top of them, display names and
descriptions sent to Roblox name only the game and the Asset, never a
person.

## Clara's illustrations: what the website art covers

This is the assessment as of brief 009 (October 2026); the manifest's
`placeholder` field is the live status. Brief 009 assessed the story website's illustrations
(`laazyj/jasonduffett.net`, `packages/clara/assets-src` at commit
`4940d10`) against the GitHub issue "Illustrations needed for the game"
(#21). The website has one scene, drawn by Clara and coloured for the
site: Amy from behind on the scribbly-grass field, facing the wall of
giant trunks, with the cream sky, little black birds and the nests in
the canopies.

| Source file | What it is | Verdict |
|---|---|---|
| `hero.png` (2000 × 1320) | The coloured scene, Amy from behind | **Reused after cropping** to 16:9 as `card:chapter2` and `store:thumbnail_1` |
| `figure-colourisation.png` (3880 × 2560) | The colour layer of Amy over the line art | **Reused after cropping** as the reference `ref:Amy` (from behind only) |
| `background.png` (2000 × 1320) | The scene with Amy painted out | **Reused after retouching and cropping** as `ui:title_screen` (the owner's decision): the painted-out trunk and grass are patched from the same drawing, then cropped low to 16:9 |
| `hero-original.png` (2000 × 1320) | An earlier colouring whose layers do not line up | Not used; `hero.png` replaces it |
| `sketch-lines.png`, `sketch-tightened.png` (3880 × 2560) | Clara's pencil drawing, scanned and cleaned up | Not used in the game; the originals behind `hero.png` |
| `figure-lines.png` (460 × 770) | The line art of Amy alone | Not used; `ref:Amy` has the colours too |
| `scene.svg` | A vector redrawing of the scene with digital "crayon" filters | Not used: not Clara's hand |

Against each piece the issue lists:

| Piece (issue #21) | Asset name | Status | Notes |
|---|---|---|---|
| A `card-chapter1.png` | `card:chapter1` | Placeholder | Needs drawing: the garden, Amy from behind at the gate, Sam watching |
| A `card-chapter2.png` | `card:chapter2` | **Reused after cropping** | `hero.png`, rows 150 to 1275 (16:9). Amy from behind, inside the middle 80%. The wall shows several gaps rather than "the one narrow gap"; good enough for the card |
| A `card-chapter3.png` | `card:chapter3` | Placeholder | Needs drawing: the three animals in the paradise |
| A `card-chapter4.png` | `card:chapter4` | Placeholder | Needs drawing: the machine, the village people, Amy small from behind |
| A `card-end.png` | `card:end` | Placeholder | Needs drawing: the animals on the treetops, the machine leaving |
| B `icon.png` | `store:icon` | **Stop-gap crop** | A square crop of `title.png`, until Clara draws the icon; no crop of the website art with Amy in it reads at thumbnail size. See [store/art.md](store/art.md) |
| B `thumbnail-1.png` | `store:thumbnail_1` | **Reused after cropping** | Shares `card:chapter2`'s file |
| B `thumbnail-2.png`, `thumbnail-3.png` | `store:thumbnail_2`, `_3` | Placeholder | Share `card:chapter3`'s and `card:chapter4`'s files |
| C `title.png` | `ui:title_screen` | **Reused after retouching** | `background.png`, retouched and cropped; the title text is game-rendered over it (see `design/feel.md`, "Title screen") |
| C `dialogue-frame.png`, `objective-frame.png` | `ui:dialogue_frame`, `ui:objective_frame` | Placeholder | Needs drawing. The placeholder is a bark-coloured rounded border with a transparent middle |
| C `bird.png`, `leaf.png`, `flower.png` | `ui:bird`, `ui:leaf`, `ui:flower` | Placeholder | Needs drawing. The birds in `hero.png` are too small and thin to cut out at 256 px |
| D `ref-amy.png` | `ref:Amy` | **Reused after cropping** (partly) | From behind only; the side view is still needed |
| D `ref-sam.png` … `ref-machine.png` | `ref:Sam`, `ref:Squirrel`, `ref:Fox`, `ref:Lion`, `ref:Dad`, `ref:Mum`, `ref:Machine` | Placeholder | One shared placeholder file until each is drawn; then each gets its own file and entry path |

Nothing in the website art shows Amy's face; `hero.png` and the
crops show her from behind. Priority, as the issue says: the four
remaining cards and the icon first.
