# Drive-and-Hunt — CP-B report (12 Nov 2026)

Scope: Part C, auto-lock aiming. Flag `DriveAndHuntV1Enabled` is still **false**. Nothing published. Waiting for owner approval before CP-C.

## 1. Route decision: Route 1, no server change

The server already has a validated locked-shot mode. `BrainrotSleepSystem.resolveShotAim` accepts `ShotMode = "ASSIST_LOCK"` with a target id and, on the server:

- looks the target up by id and refuses it if it is not a wild brainrot (or is camouflaged);
- checks the distance from the **muzzle** against the weapon's range;
- checks line of sight (`FindCentredHuntTarget`);
- runs the unchanged firing-context, fire-rate and camera-origin checks.

If any of those fail it falls back to an ordinary unassisted shot along the submitted line, which then hits whatever is really there.

The auto-lock therefore sends the **real camera origin** and the unit direction through the locked brainrot, in that existing mode. `BrainrotSleepSystem.lua`, the spawner, roaming, `ThirdPersonAimController`, `MountedAimState` and `Weapons.lua` are byte-identical to the CP-A snapshot.

Evidence from Play (server decision trace):

| Shot | Server decision |
|---|---|
| Mounted, brainrot 90° to the right at 26 studs | `accepted=true reason=hit context=mounted shotMode=ASSIST_LOCK fallback=nil` |
| On foot, aim view not active | `accepted=true reason=hit context=handheld shotMode=ASSIST_LOCK fallback=nil` |

One server limit shapes the lock: a shot is refused when the camera line and the muzzle line diverge by more than 60°. The client skips such candidates (very close, beside the cart), which are inside scoop reach anyway.

**The ±160° mounted arc is client-side only.** The server has never limited mounted yaw (the mounted aim camera turns freely), so no new server arc check was added.

## 2. What was built

| Piece | File |
|---|---|
| Pure selector: scoring, stickiness, exclusions, tap and pointer pickers | `src/shared/Utility/HuntTargetSelector.lua` |
| Client lock: 10 Hz scan, one reticle, tap to switch, lock snapshot | `src/client/Controllers/AutoLockController.lua` |
| Launcher hook: FIRE shoots the lock; touch Aim toggle hidden; on-foot firing without the aim view | `SleepLauncherController.client.lua` (7 small edits, all inert when the flag is off) |
| HOP OUT passes the locked brainrot so the player lands on its side | `DriveAndHuntController.lua` |
| Values | `Config/DriveAndHunt.lua` → `Lock` |

Behaviour:
- Candidates: awake wild brainrots only, visible, not camouflaged, within weapon range of the muzzle, with line of sight. The 12 nearest are scored. Sleeping ones are never locked.
- Score = distance^1.0 × facing^1.2 × alreadyHit^1.5 × rarity^0.3. Current target ×1.6. Held while FIRE is down and for 1.2 s after a shot. Dropped when it sleeps, leaves range, or loses sight for more than 0.5 s.
- A deliberate PvP crosshair target still takes priority over the lock (existing rule, unchanged).
- FIRE is a press. Gun still holds to fire; Bow and Crossbow still tap.
- On touch, FIRE is 88 × 88 and dims when nothing is locked.

## 3. Check results

Two Play starts, test profile `dah20261112`.

| ID | Result | Evidence |
|---|---|---|
| L1 | **Pass (spec)**, one scene also seen in Play | 6 scripted scenes in `HuntTargetSelector.spec`. In Play the lock chose the brainrot placed beside the cart on its own. |
| L2 | **Pass (spec)** | Closer brainrot does not take the lock while FIRE is held or inside the 1.2 s hold. Not staged in Play. |
| L3 | **Pass (spec only)** | Tap picker and "manual choice beats stickiness" are tested. **Touch cannot be simulated in Studio**, so a real tap and a real camera drag were not exercised. |
| L4 | **Pass** | Locked for 2 s with no press: target HP unchanged. Shots only followed a key press. |
| L5 | **Pass** | Mounted shot at 90° to the side slept the brainrot (HP 1 → 0). |
| L6 | **Pass, 3 of 4 cases run** | Forged requests sent straight to the remote: behind a wall → refused; out of range (343 studs) → fell back to a miss; at a sleeping brainrot → no change. None hit. "Wrong cart" cannot be forged: the cart and muzzle are resolved on the server from the player's own seat, never from the request. |
| L7 | **Code only for touch; PC pass** | With the lock on, the Aim button is never shown and its handler returns early. Not seen on a touch device. PC firing (G) works mounted and on foot. |

Tests: `./scripts/run-drive-and-hunt-tests.sh` — **202 of 206 pass**. The 18 new selector tests, 13 rule tests, 49 `ThirdPersonAimController` tests and the input specs all pass. **4 failures** are in `BrainrotSleepSystem.spec`, group "B1 enlarged bounds without hidden aim padding". Those test hunt-bounds code that is unchanged from the snapshot; I did not re-run them against the pre-change tree, so "already failing before" is my inference, not a measurement.

Selene is clean on every new and touched file.

## 4. Not done or not verified

- **Turret swivel (C4) is not built.** Carts have no launcher art: `HarpoonOrigin` is an invisible marker part. Shots already leave it toward the target, so side shots work; there is nothing visible to turn.
- **Reticle not captured.** Studio captures do not draw always-on-top billboards. I confirmed by reading the GUI that exactly one reticle exists and is attached to the locked brainrot's body.
- **One G press produced two accepted shots on foot** in the last Play (requests 1 and 2, both hits). Mounted, one press gave one shot. Held fire for the Gun family is existing behaviour and I did not isolate whether the synthetic key press was simply held long enough to repeat. Worth a hands-on check.
- An open menu (Daily Gift) blocks firing through the existing input-suspended rule. That is unchanged, but it means FIRE does nothing until the window is closed.
- "Already hit" is tracked locally per player (the lock they fired at, remembered 12 s). The server does not publish who hit what.
- A forged request can still name a camera origin anywhere inside the existing permitted camera distance. That is existing behaviour and unchanged.
- The B6 "get out here" pulse still uses the nearest awake brainrot, not the lock.
- No physical phone test.

## 5. Owner decisions

1. **Turret:** add launcher art to carts so it can swivel, show a simple aim line from the cart instead, or drop C4?
2. **Auto-lock and weapon assist cones:** the lock reaches the whole firing arc, so each weapon's assist-cone stat no longer limits which wild brainrot gets locked while the lock is on. The stats themselves are untouched. Confirm this is what you want.
3. The five CP-A decisions are still open (keys, boost, bystander puff, menus vs gate launch, hop animation).

## 6. Before you continue

Test attributes are removed. No place changes from me are pending. **Save the place yourself** when you are happy with your own Studio work.
