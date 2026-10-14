# 019 — Title lettering: Dancing Script through the asset manifest

**Kind:** small, perceptual; the owner confirmed the look by eye on Dev
on 2026-10-14 (Studio command bar, Client, on the Dev place after #44).
**Source:** brief 018 finding 1 and `docs/design/feel.md`, "Title
screen", which holds the website's recipe (PR #45). **Depends on:** #42
and #45 merged first (both touch files this brief touches).

## The decision

The Creator Store carries **Dancing Script**, published by Roblox, asset
id `8764312106`, in Regular, Medium, SemiBold and Bold, under the SIL
Open Font License 1.1. On Dev it renders as the website's title. The
owner's choice, seen whole: every title label in Dancing Script, the two
heading lines ("Amy", "& the Rain Forest") in **Bold** and the pill in
**SemiBold**. Kalam goes.

## Tasks

1. **A `font` kind in the asset manifest** (`docs/ASSETS.md`,
   `tools/lib/manifest.luau`, `tools/check-assets.luau`, their specs).
   A font is a Creator Store family the game references by id. It is not
   uploaded and has no file, so an entry of kind `font` has no `path` and
   no `sha256`, `upload` is `false`, `assetId` is required, `moderation`
   is `approved`, and `amy` does not apply. Name prefix `font`
   (`Manifest.NAME_PREFIXES`): `font:dancing_script`. Licence
   `creator-store-free`; `creator` names the designer and the publisher
   ("Impallari Type; published on the Creator Store by Roblox");
   `origin` names the listing and the licence. `AssetIds.luau` lists it:
   the game shows it, so the generator's rule becomes "every entry with
   an id that the game shows" (uploaded, or a font), and the file's
   header says so. Tier 0's rule that only `AssetIds.luau` names an id
   stays. Put the recipe in `docs/ASSETS.md`'s field table and a "Fonts"
   paragraph: how to find one (Toolbox → Creator Store → Fonts), that
   only Roblox-published families exist, and that the Properties
   picker shows built-in families only.
2. **`src/content/title.luau`** names the Asset, not a path:
   `heading = { family = "font:dancing_script", weight = "Bold" }`,
   `pill = { family = "font:dancing_script", weight = "SemiBold" }`.
   The binder resolves a family that starts with `font:` through
   `AssetIds`, and a family that does not as a built-in path, as now.
   The module's comment says both forms. A tier 1 test holds the title's
   families to a manifest font or a built-in family, and its weights to
   `Enum.FontWeight` names (the names are plain strings; list them).
   Content stays pure: it never requires `AssetIds`.
3. **The pill and the shadows, to the website's recipe** (feel.md's
   table): the pill rotated **−2°** (not −4°), background white at 73%
   (`BackgroundTransparency 0.27`), text deep green; each heading line
   gets two shadows, a hard one at `(0, 3)` in deep green, opaque, under
   a soft one at `(4, 8)` at 60% transparency, in that order below the
   white text. No blur exists in Roblox; the two offsets are the
   approximation, and feel.md says so. `ScreenLayout`'s title and pill
   rules and their spec are unchanged unless the tilt lives there; if it
   does, change the constant and the spec's expectation together.
4. **Docs.** feel.md's title section says what shipped (the family by
   its Asset name, the weights, the tilt). `docs/GLOSSARY.md` gains
   nothing unless a new noun appears; "font" is the manifest's word
   already. The task table: 015 done (#42), 018 done (#44), 019 done.

## Must not

- Change a canon Line, the title's words, the golden file or any remote.
- Write a literal `rbxassetid://` anywhere but `AssetIds.luau`.
- Upload anything: a Creator Store font is referenced, never uploaded;
  `tools/upload-assets` skips kind `font` and its spec says so.
- Touch the pause screen, the button row or the camera.

## Done when

- `tools/check.sh`, `tools/test.sh`, `tools/build.sh` and
  `lune run tools/mutate` are green locally and in CI; the golden file is
  byte-identical to `main`.
- The PR body names the font id, the weights, the tilt and the shadow
  offsets, and asks the owner to confirm the look on Dev with a
  screenshot, phone included: the pill's lowercase at SemiBold is the one
  thing to watch (Bold is the fallback if it reads thin).
- Under 400 changed lines.
