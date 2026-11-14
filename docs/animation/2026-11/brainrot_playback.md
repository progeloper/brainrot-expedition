# Brainrot playback (Part D.1 + brainrot LOD) — 14 Nov 2026

Status: **approved by the owner on 14 Nov 2026 (round 1), verified in Studio Play with the previews on.**
`CreatureAnimationEnabled` stays `false`; nothing changes in game until it is on.

**Live needs two flags.** The animation rigs (Motor6D joints) live on the Voxel V4 templates.
With `VoxelCreaturesV4Enabled = false` (today) the server supplies the legacy 25-part sculptures,
which have no joints, so they keep rendering exactly as now even with `CreatureAnimationEnabled`
on. Turning brainrot animation on in the live game means turning on both flags. Studio preview:
set `ReplicatedStorage.VoxelCreaturesV4Preview` and `CreatureAnimationPreview` to `true` before Play.

## What was built

| Part | Where | What it does |
|---|---|---|
| Playback | `Client/Controllers/CreatureAnimationController.lua` | A view gets an Animator only when the flag is on, the species is approved with every id uploaded, and the model is rigged. State → clip: `Deposited` → IdleDisplay; `Carried`/`Cart` → Carried; `Sleeping` → Sleep; Awake by `Motion`: Idle → IdleWild (every third pause, seeded, plays IdleWild2), Walk, Run, Alert and Signature as one-shots over the idle loop. Hit plays on each new `Phase13LastDamageAt`. Celebrate opens a fresh catch (Cart/Carried) and a fresh bank (a row seen with `PendingBank = true` that becomes Deposited). One-shots are timed from `MotionAt`; loops start at a seeded offset; crossfades 0.2 s (0.12 s into Run/Alert/Hit). |
| Speed matching | same | Walk and Run cycles follow ground speed measured from the replicated poses (low-passed, decays to 0 when updates stop), `AdjustSpeed` clamped 0.6–1.6. |
| Smoothing | same | Wild rows use a critically damped spring and a turn rate of at most 360°/s instead of the linear lerp; teleports over 20 studs snap. |
| LOD (D.3) | `Anim.RefreshLod`, inside the existing 0.25 s refresh | Wild on screen ≤ 80 studs: full set; 80–150: Movement tracks only; beyond or off screen: stopped. Own base ≤ 100: IdleDisplay. Other bases: nearest 12 within 80. Your own catch in your cart always animates. Cap 24 animators; graphics quality ≤ 3 halves the caps and drops Action one-shots beyond 40 studs. |
| Hooks | `Client/Controllers/CreaturePresentationController.lua` | Attach/Detach with the view; Celebrate flags; LOD call; per-frame Smooth + Update for animated views. No new connections. With the flag off no view is ever animated and every line of the old path runs as before. |

## Verified in Play (DEV, test profile `anim20261113`, both previews on)

| Check | Result |
|---|---|
| Rigged views | Every V4 view got an Animator (BRT_004, 006, 008, 010, 011, 013, 019 seen). |
| Wild clips (25 s, overhead camera) | `Idle` → IdleWild, `Walk` → Walk, `Signature` → Signature over IdleWild. |
| Foot sliding (R8) | Walk/Run playback speed median 0.97x of real ground speed (p10 0.60, p90 1.36); server-side walkers within 80 studs move 4–8 studs/s against authored cycles of 6–7.3. |
| Catch and bank (real haul: `DriveByHaulQA SleepBesideCart`, then drive to base) | `Sleeping` [Sleep] → `Cart` [Carried + Celebrate] → `Cart` [Carried] → `Deposited` [IdleDisplay + Celebrate] → `Deposited` [IdleDisplay]. |
| Adjacent displays out of phase (R7) | Three neighbouring platforms at 0.23, 0.61 and 0.01 of their IdleDisplay cycle. |
| LOD | Off-screen views stopped; 80–150 studs played Walk only; views returned to full when back on screen. |
| Specs | `CreatureProtocol.spec` 11 of 11 pass (the receiver this hooks into). |

Captures: `review/brainrots_partD/wild_brt008_walk.jpg` (Lirili Larila mid-stride),
`review/brainrots_partD/base_idledisplay.jpg` (Ballerina Banana and Cavallo Virtuoso on their
platforms).

## Not verified

- **Hit** and **Alert → Run**: the QA haul sleeps a brainrot without damage, and no reactive
  brainrot locked on during the run. Both use the same one-shot and loop paths as Signature/Walk.
- Frame cost (R18), bandwidth (R20) and the bind-pose comparison (R2) were not measured in this pass.
- Only Forest species were seen live; the rest share the code path and their rigs were approved in
  the review pens.
