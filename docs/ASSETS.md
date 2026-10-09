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
| `src/shared/AssetIds.luau` | Generated from the manifest: asset name → `rbxassetid://` content id, for every uploaded asset the game shows. Never edited by hand. |
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
| `kind` | `image`, `audio` or `model`. The file's extension must be one the Assets API takes for that kind (`tools/opencloud.luau`, `ASSET_CONTENT_TYPES`). |
| `path` | The file, under `assets/`. Two entries may share a file (a thumbnail that is a Chapter card). |
| `assetId` | The Roblox asset id as a string of digits, or `null` until uploaded. Written by the uploader only. |
| `sha256` | The SHA-256 of the file that was uploaded. Written by the uploader only. |
| `moderation` | The Moderation status; see [Moderation](#moderation). |
| `upload` | `false` for files the game never shows: store art (set on the Creator Dashboard by the owner) and Character references. |
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
(Cues), `prop:` (Prop models). The game looks an Asset up by its name in
`AssetIds.luau`; a name with no id yet is absent, and the game is to fall
back to plain UI (or silence, for a Cue). Nothing in `src/` reads
`AssetIds.luau` yet; the briefs that show the cards and play the Cues
(013, 015, 016) do.

## How to add an asset

1. Put the file under `assets/images/`, `assets/audio/` or
   `assets/meshes/`. For an image, check the rules in the GitHub issue
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
| `creator-store-free` | Free models and sounds from the Creator Store | Fetched as the plan's section 5.5 says. Record the Creator Store asset id and creator in `origin`. Only items marked free. |
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
the account must be ID-verified before brief 013.

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
| B `icon.png` | `store:icon` | Placeholder | Needs drawing. No square crop of the website art reads at thumbnail size without Amy |
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
