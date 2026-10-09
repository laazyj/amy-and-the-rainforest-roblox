# 016 — Phase 1: the visual pass

**Kind:** perceptual. **Requires the Mac runner** (mac-001) and the Studio
bridge; **starts after** briefs 011, 012 and 014 merge.

## Goal

The world looks like Clara's illustration: terrain and foliage, lighting
and atmosphere in her palette, chapter cards from her art, the Shots
composed as `feel.md` describes, on PC, phone and tablet.

## Must

1. **Scenes** reworked as content: terrain instructions, foliage models
   (free Creator Store, manifest-recorded), the forest wall and paradise
   in the site's palette (moss, gold, bubblegum pink, grape purple), the
   cream sky and little black birds.
2. **Lighting presets** per Scene, `ShadowMap` versus `Future` decided
   against the client frame-time budget measured in tier 3; the choice set
   in the project file.
3. **Chapter cards** using Clara's illustrations (face rule applied).
4. **Baselines.** One screenshot per Scene, Shot and chapter card per
   device class committed under `docs/screens/`, with the tier 3 diff
   tolerance tuned per shot and the palette check enabled.
5. **Agent visual loop.** The session runs the Mac visual pass per batch,
   reviews the contact sheet against the `feel.md` rubric by looking at
   the frames, iterates, and presents the before-and-after in the PR.
6. **Budgets** recorded: instance, part and triangle counts, texture memory,
   client frame time on the Mac; all under the budgets with headroom.

## Must not

- Change gameplay, Lines or timings; the golden stays unchanged.

## Done when

- Tier 3 green with baselines; the owner and Clara accept the look on a
  real phone and tablet.
