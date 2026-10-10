# 012 — Phase 1: device classes, touch controls and onboarding

**Kind:** perceptual (Mac device emulation and real devices for the final
pass; layout logic first). **Starts after** brief 007 merges.

## Goal

The game plays well on PC, phone and tablet as three first-class device
classes (plan 2.3, `feel.md`), and a child's first minute teaches them to
move and talk.

## Must

1. **Device class detection** in a pure `src/core/DeviceClass.luau` from
   viewport size and last input type, per `feel.md`; tier 1 tests for the
   boundaries and orientation changes.
2. **Layouts** per class for every screen: dialogue box (60-character
   cap, minimum text size on a 6-inch phone), Objective tracker, touch
   control zones, chapter cards, title screen. Safe-area insets respected.
3. **Touch input** with `ContextActionService`: a talk-and-advance button in
   the right zone, thumbstick in the left; prompts remain the universal
   "talk" affordance. PC keyboard unchanged.
4. **Onboarding** for the first minute: where the thumbstick is, how to
   talk, in Clara's voice where text is shown (new Lines, not canon, for
   approval), skippable, shown once per save.
5. **Tests.** Tier 1 for layout maths (text column width ≤ 30 × text size,
   touch targets ≥ 44 points). Tier 3 scripts under `tests/studio/` for a
   phone and a tablet preset in both orientations, with the on-screen
   assertions from plan section 4 (text fits, safe areas, contrast ≥ 4.5:1,
   no overlapping interactive elements).

## Must not

- Change gameplay or canon Lines. Add gamepad support (later).

## Done when

- Tier 1 green; on the Mac, device-emulation screenshots for both classes
  and orientations pass the assertions; the owner plays on a real phone and
  tablet per the release checklist.
