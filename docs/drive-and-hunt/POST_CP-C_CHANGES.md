# Drive-and-Hunt — changes after CP-C (12 Nov 2026)

Owner-approved values applied on top of CP-C. Flag `DriveAndHuntV1Enabled` is still **false**. Nothing committed, saved to Roblox or published.

## Applied

| Item | Change | Checked |
|---|---|---|
| Fire inputs | Space also fires while driving; R2 bound explicitly on foot (0.15 s double-fire guard) | Play: server-accepted shots for Space and R2 driving, R2 on foot. Simulated pad only. |
| Scoop reach | `Scoop.Reach` 7 → 10. Beside the cart 13.2–14.4 studs, ahead 14.4–15.7. No cart reaches less than the old 13. | Spec (every profile ≥ 13). Live edge not re-measured at 10. |
| Pickup sound | **No code needed.** `AudioController` already plays S6 (random take, volume 0.9) on every own cargo load, scoops included. The sound I added doubled it, so I removed it. | Play: sound instances logged. |
| Hints | A hint is skipped once the player has done the action this session (fired, hopped out, used LOAD & GO, scooped). Still session-only. | Lint only. |
| Aim line | One Beam from the cart muzzle to the lock (0.15 wide, 60% transparent, lock colour), driving only. 0.08 s muzzle flash per mounted shot. | Play: beam on; visible in capture `apply_02`. Flash not observed (too brief). |
| Key cap | "C" badge on the switch button when keyboard is the preferred input | Capture `apply_01`. |
| Bystander puff | Radius 120 → 80; other players' puffs use 6 particles and at most one per 0.5 s | Lint only (needs two players). |
| Menus vs gate launch | Any open menu counts as busy. A crossing made while busy is kept and launches when the menu closes, if still within 30 studs of the edge. | Spec + Play: no launch with Daily Gift open, launched on close. |
| Launch boost | No change (stays 0) | — |
| Lock vs assist cones | No change (all weapons carry the same cone) | — |

Specs: 207 of 211 (one new gate test). The 4 failures are the pre-existing aim-bounds group.

## Not applied

**Camera ease (0.25 s).** `CartCameraController` snaps on activation through its resync state, which has its own rules and specs. An ease means changing that state machine, not adding a tween. I left it for a separate, reviewable change.

## Corrections to the CP-C report

- "Loads are silent" was wrong. The legacy `SFX_LoadAccent` is uninstalled, but the newer audio system plays S6 on every load.
- Scoop reach table: add 3 to every figure.

## Blocked launch view — fixed in the lane data

Cause: forest and jungle trees in `Workspace.World` neither collide nor answer queries (18 of 1,744 parts near camp do). The cart camera avoids only colliding geometry, so it cannot see them. The lane measurement had the same blind spot.

Measured on the server against 7,658 non-colliding scenery parts: **28 of 104 launch positions** had scenery in the camera line (28 studs behind, 9 up) or inside the cart footprint. Seven lanes had no clear position at all, including `North_03`.

Fix, in `CampExits.lua` only:
- the 28 positions are removed;
- the seven fully blocked lanes (`North_03`, `South_01`, `South_05`, `East_01`, `East_02`, `East_04`, `East_08`) are moved 6–14 studs along the camp edge to the nearest clear spot.

All 35 lanes remain, with 76 positions. Checked: `North_03` now launches at the moved spot with a clear view (capture `apply_02`, which also shows the aim line). The other six moved lanes passed a ground-level and slope check but were **not launch-tested**: they are in Jungle and Volcano, which the test profile has not unlocked. The server still re-validates every position at launch and falls back to the next lane.

Not changed: the camera itself. While driving through the forest it can still pass through trees, as it did before this work. Nine lanes now have a single position, so a parked cart or villager there sends the launch to the neighbouring lane.

## Phone test before CP-D

Device: a 3–4 GB Android phone or an older iPhone, landscape. Set `ReplicatedStorage.DriveAndHuntV1Preview = true` in a private test build.

| # | Do | Pass |
|---|---|---|
| 1 | Walk out of camp 10 times, different edges, including Jungle and Volcano sides | Seated every time; cart on clear ground; view not blocked |
| 2 | Open a menu, walk out, close it | No launch while open; launch on close |
| 3 | Drive and press jump | Never leaves the seat; no jump button visible |
| 4 | 20 shots with FIRE while driving | One shot per tap (bow/crossbow); hold fires (gun); reticle always on the target hit |
| 5 | Tap a different brainrot 10 times | Lock switches at least 9 of 10; dragging the camera never switches |
| 6 | Shoot on foot without an Aim button | Fires at the locked target |
| 7 | HOP OUT, CART, LOAD & GO | Each works with one thumb; buttons at least 88 px; no mis-taps on FIRE |
| 8 | Sleep 6 brainrots near the cart | Rings and arrows readable; 30 fps or better |
| 9 | Drive over a sleeper | Pull, pop, "+1", one S6 sound |
| 10 | Fill cargo | Gold HOME arrow points home; beam visible |
| 11 | Play 5 minutes | No accidental hop-out; each hint at most once |
| 12 | Controller, if available | R2 fires once per pull driving and on foot; D-pad Up switches |

## Recovery

`.checkpoints/drive_and_hunt_cpA_20261112/` and Roblox place version 1250.
