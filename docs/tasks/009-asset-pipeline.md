# 009 — Phase 1: asset pipeline (manifest, uploads, Clara's illustrations)

**Kind:** logic-provable. No Mac. **Independent of Checkpoint B**; may run
in parallel with 006.

## Goal

Assets reach Roblox only through CI, every asset the game references is
recorded with its licence, and Clara's illustrations are available to the
chapter cards and store page.

## Must

1. **Manifest.** `assets/manifest.json`: for each asset, its local path,
   kind (`image`, `audio`, `model`), Roblox asset id once uploaded, creator,
   licence, moderation status and the `cue:`/`card:`/`prop:` name the
   game uses for it. A tier 0 check validates the file and fails on any
   `rbxassetid://` in `src/` that is not in the manifest.
2. **Uploader.** `tools/upload-assets.luau` through `tools/opencloud.luau`
   (the only place URLs live): uploads every manifest entry without an id
   via the Assets API, polls the operation, writes the id back, and
   regenerates `src/shared/AssetIds.luau`. Idempotent; dry-run mode;
   unit-tested against the mock HTTP context. The Release guard applies.
3. **Workflow.** `.github/workflows/upload-assets.yml` on
   `workflow_dispatch` only, with the Dev key, running the uploader and
   opening a PR with the updated manifest and `AssetIds.luau`
   (SHA-pinned actions, minimal permissions, the composite action). The
   agent never holds a key; it changes the manifest and triggers the job.
4. **Illustrations: assess, reuse where right, placeholder otherwise.**
   The website's illustrations at
   `https://github.com/laazyj/jasonduffett.net/tree/main/packages/clara/assets-src`
   were drawn for the one-page story, not for the game. The build session
   attaches that repository read-only (or asks the owner to copy the
   files), reviews each image against the GitHub issue "Illustrations
   needed for the game" (the list of cards, store art, UI pieces and
   character references, with sizes and the face rule), and records in
   the PR which pieces the existing art can serve as-is, which it can
   serve after cropping, and which must be drawn. Reused pieces go under
   `assets/images/` with manifest entries, origin paths and the owner's
   rights noted; every piece still needed gets a plain placeholder
   (palette-coloured card with no text) under the same name so the game
   and the store page can be built now and swapped later. No image
   showing Amy's face is used anywhere.

5. **Docs.** `docs/ASSETS.md`: how to add an asset, the licence rules
   (free Creator Store, Clara's work, free-licence or synthesised audio),
   the audio upload limits, and the moderation-status workflow.

## Must not

- Upload anything to the Release universe or outside the owner's creator
  account. Include any key or real id in the repo.

## Done when

- A dry run lists every pending upload; one real `workflow_dispatch` run on
  Dev uploads the illustrations and opens the id PR; CI green.

Confirmation the account is ID-verified (audio limits) is needed before
brief 013, not this one.
