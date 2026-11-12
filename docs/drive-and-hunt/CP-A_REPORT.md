# Drive-and-Hunt — CP-A report (12 Nov 2026)

Scope: reconcile, launch lanes, Part A (gate launch) and Part B (switch button). Flag `DriveAndHuntV1Enabled` is **false**. Nothing published. Waiting for owner approval before CP-B.

## 1. Reconcile

| Item | Finding |
|---|---|
| Checkout | `/Users/noahodukoya/development/Roblox/BrainrotExpedition`, branch `feature/camp-rework`, HEAD `582f505`, 835 dirty/untracked paths (all owner work, untouched) |
| Build stamp | `Deployment.ReleaseId = P14_VILLAGER_OUTFITS_20261110_R1`, place 91958083796436 |
| Rojo mapping | `MapBlockout` is not mapped (as AGENTS.md requires). Rojo was live-connected during this work. |
| Studio vs `src/` | Compared a checksum of every script under `Shared`, `Server` and `Client` in Studio with the local files. Every system this task touches is byte-identical, including `HuntFlow`, `DriveByHaulSystem` and `BrainrotInteractionSystem` (`TryScoopIntoCargo`). **Nothing was Studio-only, so nothing had to be moved.** I checked the task's systems by eye, not all ~600 entries. |
| Recovery | Source: `.checkpoints/drive_and_hunt_cpA_20261112/` (full `src/`, project file, AGENTS.md, git status, tracked diff). Place: saved to Roblox as **version 1250** before any change. That save included the owner's unsaved Studio work at that moment. |

## 2. What exists and how it was extended

| Prompt assumption | What the code does | What I did |
|---|---|---|
| Existing enter/exit key | None. Entry is the `ContextDrive` prompt (E / gamepad X). Exit was Roblox's default jump. | New switch input. **F is Burst and gamepad Y is Manage Team / Drop**, so the prompt's fallbacks both clash. Used **C** and **D-pad Up**, registered as `Switch` in `CartInputRegistry`. |
| Cart spawn | `PlayerSpawnSystem` / `PlayerWorldLifecycle` spawn the selected cart at the base pad. One cart per player already holds. | Unchanged. Launch and call only move the cart. If the cart is missing at launch, the CART button pulses; nothing is spawned there. |
| Moving a cart | `CartResetExecutor` already moves carts safely (suspend stability/terrain, assembly mutation, clearance proof, ownership restore). | Added `CartResetExecutor.RelocateParked` and `CartService:RelocateParkedCart`, which reuse that transaction for an empty parked cart. No second placement system. |
| Seating | Only the prompt handler called `seat:Sit`. | Added `CartOccupantService:SeatOwner` / `UnseatOwner` with the same eligibility checks (owner, `CanEnterDriver`, so carrying still blocks driving). |
| Launch order (anchor, pivot, seat, unanchor, ownership) | The executor's order is anchor, pivot, unanchor, validate, resume; ownership follows the normal occupant-changed path after seating. | Followed the code. Same end state: driver owns physics (verified). |
| Boost (`ConfigureBurstState`) | Burst is a team capacity that feeds cart performance. | **Skipped.** Triggering it would spend the owner's burst or add speed on top of Training. `Fx.BoostSeconds = 0`. |
| `Phase13CinematicActive`, dialogs | Client-only attributes; the server cannot read them. | The client reports "busy" over the switch remote. It can only restrict that player. |
| Tag slow "on the player" | It is on the cart (`VillagerSlowUntil`). | CART / LOAD & GO are refused while it is active. |
| Launch sound | `S8_1/S8_2` (cart burst whoosh) fits. | Reused; no upload needed. |
| Camp exits | The camp edge is open terrain, not discrete gates. | Lanes are sampled every ~40 studs along all four edges. |

New files: `Config/DriveAndHunt.lua`, `Config/DriveAndHuntFlags.lua`, `Config/CampExits.lua`, `Utility/DriveAndHuntRules.lua` (pure), `Services/DriveAndHuntService.lua`, `Controllers/DriveAndHuntController.lua`, `Tests/DriveAndHuntRules.spec.lua`, `scripts/run-drive-and-hunt-tests.sh`. Remotes: `DriveAndHuntRequest`, `DriveAndHuntFx` (created only when the feature is on).

Studio preview is opt-in: set `ReplicatedStorage.DriveAndHuntV1Preview = true` before Play. Without it, Studio and live behave as before.

## 3. Launch lanes

Measured in Play with the starter cart (CRT_001): 3 positions per lane at 12 / 18 / 24 studs outside the edge, slope ≤ 20°, camp-level ground, full `ValidateAssignedSpawn` clearance.

| Edge | Region | Lanes kept | Dropped |
|---|---|---|---|
| North (z = −294) | Forest | 12 of 12 | — |
| South (z = 202) | Jungle | 12 of 12 | — |
| West (x = −267) | Forest | 3 of 12 (`West_01`, `02`, `08`) | 9: cliffs or slope |
| East (x = 229) | Volcano | 8 of 12 (`East_01–05`, `08`, `09`, `12`; `East_02` has 2 positions) | 4: rock or slope |

35 lanes, 104 positions, in `src/shared/Config/CampExits.lua`. The server re-checks each one at launch.

## 4. Check results

Two Play starts, test profile namespace `dah20261112` (key now exists in `dev_v2`).

| ID | Result | Evidence |
|---|---|---|
| G1 | **Pass** | Walked out north on foot: seated 0.46 s after crossing (client-observed, includes the 10 Hz sample); server launch call 24 ms; cart at `North_03`, facing out; driver owns physics |
| G2 | **Pass, partial coverage** | 400 scripted launches with dummies in lanes: 174 launched, 226 refused, **0 overlaps**. The fresh profile only has Forest, so every launch used the 15 Forest lanes; Jungle/Volcano lanes were refused as Storm-locked and never received a cart. Refusals were not split into locked vs dummy-blocked. |
| G3 | **Pass** | Re-exit 2.96 s after hopping out: no relaunch. Exit after 4.6 s: relaunched |
| G4 | **Pass** | Carried a brainrot out: no launch, carry intact, button read LOAD & GO |
| G5 | **Pass** | Seated in camp stays seated; cargo 1 → 0 by auto-bank at base; HOP OUT pulse fired once |
| S1 | **Pass on keyboard** | Three Space presses while driving: still seated. Mobile jump button is hidden and the Jumping state disabled, **not tested on a touch device** |
| S2 | **Pass** | One C press exits. A request 0 s after seating was refused (`JustSeated`), 0.5 s later accepted. Landed on the driver's side, body edge 4 studs from the cart's visual edge, launcher equipped. Target side and lock carry-over need the CP-B lock. |
| S3 | **Pass** | Cart appeared beside the player, 6 bounds queries. Second call inside 5 s refused (`Cooldown`). With everything blocked: `NoRoom`, cart did not move, no cooldown |
| S4 | **Pass (success path)** | In camp and outside: cart placed, brainrot loaded (cargo 1), then seated. The failure path (cargo full) is code-only, not run in Play. Chase start was not observed; the load goes through the unchanged `TryPlaceInCargo`, which emits `CargoPlaced`. |
| S5 | **Pass (ledge)** | Brainrot 15 studs above the driven cart: pulse fired. Indoor/roof case not run. |
| F1 | **Pass by construction** | With the flag off the service returns before creating remotes and the controller returns before building UI. Not separately played. |

Tests run: `./scripts/run-drive-and-hunt-tests.sh` — 42/42 (13 new rule tests plus ConfigValidator, MountedAimState, CartBurstInput, CartInputController). Selene clean on every new and touched file; StyLua applied to new files only (owner's compact files were not reformatted).

Captures: `docs/drive-and-hunt/captures/`.

## 5. Config values

Gate: 10 Hz, 60-stud edge band, 30-stud max crossing, 4 s seat-exit quiet, 3 s repeat quiet. Lanes: 12/18/24 studs, 40-stud spacing, 20° slope, 2-stud margin, 2 lanes tried. Call: 8 directions × 7/10/13 studs (from the cart's edge), 30-stud lane fallback, 5 s cooldown, ≤ 27 bounds queries. Hop out: 0.3 s grace, 4 studs from the cart edge. Unreachable pulse: 2 Hz, 60 studs, 6 studs up, 30-stud roof probe, every 10 s. FX: 0.25 s beat, 12 particles (6 on Low).

Scoop reach per cart is CP-C. For reference, the starter cart's collider half-width is 3.38 and its visual half-width 4.54.

## 6. Known gaps in CP-A

- **Not built:** the hop-into-seat animation and the 0.25 s camera ease. The player is welded to the seat on arrival and `CartCameraController` already switches the camera; I did not add a second camera path. The cart pop, smoke and sound are in.
- **Fixed after the last Play, so unverified in Play:** the button now hides while any menu is open (`MenusV2Open` holds a window name, not `true`). In Play 2 it still showed over the Daily Gift window.
- A gate launch can fire while the Daily Gift window is open (the prompt lists only cinematic, consent and compare).
- The cooldown ring is an approximate sweep with a countdown number.
- Captures are at the Studio viewport (1377 × 882), not 844 × 390. The button is built at ≥ 88 × 88 px by construction.
- Lanes were measured with the starter cart only. Larger carts rely on the launch-time check.
- No physical phone test.

## 7. Owner decisions

1. **Keys:** C and D-pad Up, or different ones?
2. **Boost:** leave the launch without a boost, or allow a free 1.5 s burst that ignores burst capacity?
3. **Bystanders:** the puff is sent to everyone within 120 studs. Keep, or driver only?
4. **Daily Gift / menus:** should an open menu block the gate launch?
5. **Hop animation and camera ease:** build them in CP-C, or drop them?
6. No audio upload is needed for CP-A.

## 8. Before you continue

The place has no unsaved changes from me (test attributes removed). **Save the place yourself** when you are happy with your own Studio work.
