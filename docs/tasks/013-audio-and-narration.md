# 013 — Phase 1: audio and narration

**Kind:** mixed: cue plumbing is logic-provable; the mix is perceptual.
**Starts after** brief 009 merges (manifest and uploader) and 006 (Cues as
World commands). Needs the account ID-verified for audio upload limits.

## Goal

Every scene has ambience and music, every interaction has feedback, and
the canon Lines are narrated, as plan section 7 describes.

## Must

1. **AudioManager** (`src/client/Audio.luau`) resolving `cue:` and `music:`
   names through `AssetIds`; music per Scene with crossfades; SFX for
   prompts, pickups, footsteps, chapter cards. `PlayCue` World commands
   from Beats and Hooks; tier 1 asserts every Scene names an ambience and a
   music Cue and every Cue name resolves in the manifest.
2. **Sources.** Free-licence or synthesised SFX and music recorded in the
   manifest with licences. Clara's palette of feeling: gentle, warm.
3. **Narration.** Canon Lines recorded (ideally by Clara; the owner
   provides files) batched per chapter into single audio files with a
   timestamp table in content, played in sync with the dialogue
   view-model; a text-only fallback when a file is missing. Tier 1 asserts
   the timestamp table covers every canon Line.
4. **Golden.** `PlayCue` commands appear in the walkthrough; re-record the
   golden once in its own commit, diff shown as only added `PlayCue`
   messages.
5. **Tier 3** (when the Mac exists): `PlaybackLoudness` above zero when a
   Cue fires; each Scene has ambience and music playing.

## Must not

- Exceed the monthly audio upload limit; the PR plans uploads per chapter.

## Done when

- Tiers 1 and 2 green; cues audible on Dev; owner's audio review per
  `feel.md`.

## Owner inputs

Narration recordings (or a decision to defer narration to a later PR).
