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
4. **Clara's illustrations.** The sources live in the owner's website
   repository at
   `https://github.com/laazyj/jasonduffett.net/tree/main/packages/clara/assets-src`.
   The build session attaches that repository read-only (or asks the
   owner to copy the files) and places the illustrations under
   `assets/images/` with manifest entries and `card:` names for the four
   chapter cards and the ending card. Record each file's origin path and
   that the owner holds the rights. Apply the face rule: no image showing
   Amy's face is used in game or on the store page.

## Owner inputs

- Illustration sources: the website repository path above (provided).
- Narration: tracked in the GitHub issue "Narration recordings needed for
  Phase 1 (brief 013)"; not needed for this brief.
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
