# 014 — Phase 1: characters via HumanoidDescription, and Sam's chase

**Kind:** mixed. **Starts after** brief 006 merges; the perceptual pass
needs the Mac.

## Goal

Amy, Dad, Mum, the villagers, Sam and the three animals become proper
Roblox characters with built-in animations, and Sam's catch becomes a short
chase, without custom rigs (plan 2.3, Phase 1).

## Must

1. **Player is Amy.** A forced `HumanoidDescription` built from free
   catalog items and Clara's palette; applied on spawn; never shows a face
   the camera can see (brief 011's rule).
2. **Characters** from `src/content/characters.luau`: humans as R15 with
   `HumanoidDescription`s and the built-in animation set; the animals from
   free Creator Store rigs that ship with animations, fetched through the
   path decided in the asset-fetch spike (plan 5.5) and recorded in the
   manifest.
3. **Sam's chase.** The `beat:sam_catches` Beat becomes `MoveCharacter`
   commands with the built-in run animation ending at Amy, then the
   existing teleport; timings may change by at most the chase duration,
   and the golden is re-recorded once with the diff limited to that Beat.
4. **Tests.** Tier 1: every Character has a description or rig entry;
   Companions' follow logic in core. Tier 2: every Character spawns with a
   Humanoid and its animations load. Tier 3: animation tracks playing, no
   T-pose, speaker faces Amy during Dialogue.

## Must not

- Author custom rigs or keyframed animations (Phase 2, human task).

## Done when

- All tiers green; screenshots of each Character on the Mac reviewed
  against `feel.md`.
