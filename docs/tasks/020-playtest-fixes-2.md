# 020 — Playtest fixes, round 2 (after brief 014's Character models)

**Kind:** fixes and small content corrections. **Source:** the Mac agent's
tier 3 findings on PR #69 (brief 014's Character models for Sam, the Fox
and the Lion, on `main` at `463137a`). It reported them and did not fix
them, because they are code and content, not assets. The causes were read
from the code on `main` at `463137a`.

## Findings and fixes

1. **Sam clips the gate post on his run.** `beat:sam_catches`
   (`src/content/chapters/1/hooks.luau`) runs Sam from `spot:SamHome`
   (3, −20) to `spot:GateOutside` (2, −14). That line crosses the front
   fence at x 2.33, and the post at the gate's edge stands at x 3, 0.8
   studs square, so Sam (about 2.4 studs across with his ears) overlaps
   `RainforestMap.FencePost`. The Mac saw this in 2 to 3 of 30 samples,
   with the Placeholder as with the new model. Fix: move `spot:SamHome`,
   `spot:GateOutside` and `spot:SamGuardPost`, which is on the same line
   for the second catch, towards x 0. Then both runs cross the fence
   through the middle of the gate. Keep Sam beside the way Amy walks to
   the gate, so she does not walk into him. The post's size moves into
   content (`Garden.fence.post`), and SceneBuilder builds the posts from it.
   Tier 1 rule: every run that crosses the front fence keeps half Sam's
   width and 0.2 studs to spare from the posts across their depth. Every
   tier 1 rule on Spots and Zones, and the camera rule (brief 011,
   `tests/lune/core/CameraModel.spec.luau`), stays green.
2. **Sam stalls about 2.6 s before moving.** First, `CharacterHost.runTo`
   (`src/server/CharacterHost.luau`) unanchors the root, gives it to the
   server and calls `Humanoid:MoveTo`, all in one frame. Sam then stands
   still for about 2.6 s and covers the 6 studs in about 0.4 s. The cause,
   read from the code and Roblox's documented Humanoid behaviour:
   - **The state machine.** While a Humanoid's root is anchored, its state
     machine does not run. A just-unanchored assembly first settles. A
     four-legged rig, with its root a box and its welded parts' weight
     off-centre, can tip as it wakes and fall into `FallingDown` or
     `Ragdoll`. `GettingUp` then holds it before `Running`, and only then
     does a Humanoid walk to its `WalkToPoint`.
   - **The timing.** `MoveTo` is issued before the physics step that wakes
     the assembly.

   `AutoRotate` only turns a moving Humanoid, so it cannot hold one still.
   The welded parts' mass changes how far the rig tips, not whether the
   Humanoid walks.

   Fix, the smallest change in the adapter:
   - **In `ready`:** disable `FallingDown`, `Ragdoll` and `GettingUp` on
     every Character. Nothing in the Story knocks a Character over.
   - **The new `CharacterHost.setOff`:** unanchor, give the root to the
     server, set the state to `Running` with `ChangeState`, then issue
     `MoveTo` after one `Heartbeat`.

   The run is given `Story.runSeconds`, now in core (`Story.RUN`: 16 studs
   a second, 0.5 s slack, 3 s at most), which the adapter and tier 1 share.
   The Beat's `Wait` goes from 1 s to 1.2 s, at least the run's
   `Story.runSeconds` for both catches (1.02 s and 1.14 s). So the whole
   run is seen before `TeleportPlayer`: about 0.5 to 0.65 s of running,
   then a moment at her side. That is 0.2 s more, within brief 014's "at
   most the chase duration". Tier 1 rule: a run's Waits, before Amy is
   teleported, are at least its `Story.runSeconds` and at most
   `Story.RUN.limit`. The golden file records remotes only, and a Wait is
   not one, so it does not change.
3. **Sam and the Squirrel do not face Amy in Dialogue; the Fox and the Lion
   do.** This comes from the Spots' facing in content, not the models.
   - **Sam:** his Spots faced home (−z), and he speaks from them while Amy
     stands in `zone:GardenGate`, behind him.
   - **The Squirrel:** `spot:SquirrelHome` faced −z, but Amy walks up to
     it from the heart glade, at higher z.

   Fix: `layout.spotToward(x, z, toward)`, a Spot facing a point.
   - **Sam:** `spot:SamHome` and `spot:SamGuardPost` face the gate.
   - **The Squirrel:** faces the heart glade.
   - **The Fox:** faces the Squirrel's Spot, which Amy walks up from. It
     faced −z, 63° off that way, outside the rule's 60°.
   - **Dad:** the rule also catches him at `spot:DadHome`, side-on to Amy
     at her spawn, and at `spot:DadAtMachine`, 77° off her in
     `zone:MachineFront`. Both now face her.

   Tier 1 rule, stated from content alone
   (`tests/lune/content/Stand.spec.luau`), walking the Story as a player
   would: every Character faces Amy as it speaks, its Spot's facing within
   60° of the way to her (the camera rule's cone, cosine ≥ 0.5). Where Amy
   stands:
   - **In a Zone:** a `reach` Quest's Zone, once she has entered it.
   - **Talking to a Character:** she walked up from where the Quest before
     left her, and that is where it faces.
   - **Afterwards:** beside the Character she talked to, until a Zone, a
     Pickup or a `TeleportPlayer` moves her.

## What tier 3 must then prove (the Mac agent)

- **Sam's run:** in both catches, Sam runs visibly from his Spot through
  the middle of the gate to `spot:GateOutside`. He starts within a frame
  or two of the bark, never touches a `FencePost`, and arrives before Amy
  is teleported. Record when the root first moves, the Humanoid's
  `StateChanged` sequence, and whether `MoveToFinished` fired before the
  run's clock ran out. If he still stalls, those three name the cause.
- **Facing:** Sam (at the gate, both times) and the Squirrel face Amy in
  their Dialogue Shots. The Fox, the Lion, Dad (in the garden and at the
  machine) and Mum still do.

## Must not

- **Lines:** change any Line or the golden file.
- **The camera:** change the camera rule or any Shot's path.
- **The run:** change any Beat but `beat:sam_catches`'s Wait.
- **The Characters:** move any Character but Sam. Dad's, the Squirrel's
  and the Fox's Spots change their facing only.

## Done when

- Tier 0 and tier 1 green, and `lune run tools/mutate` catches every fault.
  CI and the engine tests are green, including the new tier 2 cases:
  every Character has `FallingDown`, `Ragdoll` and `GettingUp` disabled,
  and `setOff`'s sequence against a fake Humanoid.
- The Mac agent's tier 3 pass shows the two points above.
