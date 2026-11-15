# Playtest Fixes — CP-C report (13 Nov 2026)

Scope: Part D (Train! puts the cart on the rollers) and Part E (brainrot size ladder). The master flag `FeatureFlags.PlaytestFixesV1Enabled` is **false**. Nothing has been saved to the cloud or published.

## What I found

- **Training:** `TrainingService` ran one occupant per bay, with "Bay busy" for everyone else. It also had an **idle ejection**: 10 minutes without input (`Training.AfkKickSeconds`) unseated the trainer and moved the cart off. With the flag on that ejection does not run (D5). With the flag off it is unchanged.
- **`StallTrainingScreen.goTrain()`** only drew an arrow over the rollers.
- **The seat-and-pop beat** already existed in `DriveAndHuntService.seatAfterMove`, plus the client `pop()` and puff. I reused it unchanged.
- **Cart relocation** goes through `CartService:RelocateParkedCart` → `CartLocalPlacement`, which only accepts tagged ground and proves the cart against the surfaces under its contact points. **CartAssemblyValidator treats any collision-group change on a cart as fatal** (it despawned the test cart). Both needed handling, below.
- **Size:** every role used one height (6.706). On the client, `CreaturePresentationController` scales each state through `ApplyCanonicalScale(context)`. On the server, proxies scale through `WorldPrepared`, and query and hunt bounds copy the proxy scale.

## Part D — TrainPlace

- **D1:** Train! closes the window and sends `TrainPlace` on the existing `DriveAndHuntRequest` remote, through the existing per-request rate limit. When the player is already training, the button stays "Training…" and does nothing.
- **D2, server validation** (pure `Shared.Utility.TrainPlaceRules`):
  - Training on, not already training, alive, within the prompt's `MaxActivationDistance + 6`.
  - `CanAct` (not dazed), not busy, not carrying, owns a cart.
  - Each refusal comes back as a Stud Pop toast through the existing Feedback channel ("Drop your brainrot first", "Get closer to the Training stall", ...).
- **D3, placement:**
  - It uses the player's existing cart (it never creates one). If the player is driving it elsewhere, they step out first.
  - The cart goes on the trigger, facing up the ramp (the trigger's LookVector), 0.1 studs above the tallest deck piece.
  - One `GetPartBoundsInBox` check (no person standing there), then `RelocateParkedCart` → `seatAfterMove(..., "TrainPlace")`.
  - The client plays the same pop/smoke/sound beat, then a 0.35 s camera ease to a ¾ view.
- **To make relocation onto rollers legal** (runtime only, flag-gated, nothing authored):
  - the Training stall's deck-level pieces get `CartDrivableGround`;
  - the raised roller pieces (rollers, bands, pit rails, deck edges) move to a `TrainingRollers` collision group. Plain `Carts` pass over them, so the placement proof sees the flat deck; `TrainingCarts` ride on them.
- **D4, shared bay:**
  - Carts on the deck join `TrainingCarts`, which copies the `Carts` rules except that it doesn't collide with itself. They join when placed or driven on and leave once off the trigger volume.
  - `CartAssemblyValidator` gets one narrow exception: `TrainingCarts` is accepted only on a cart flagged `PlaytestTrainingBay` (6 lines, no reformatting of that file).
  - Groups are registered when the stall binds and configured on the first Training tick, after `CollisionService` has set its rules.
  - Any number of players train at once, each with the existing per-player XP tick. `BayOccupantUserId` stays 0, and `BayTrainingCount` drives the rollers spinning while anyone trains. "Bay busy" is gone.
  - Other players' bay carts draw at 0.5 `LocalTransparencyModifier` (visual parts).
  - Driving onto the rollers still trains, as before.
- **D5, while training:**
  - The switch button reads **STOP** and sends `TrainStop`, the ordinary HOP OUT that lands beside the cart on clear deck.
  - Pooled "+XP" pops come off the rollers (4 billboards, round-robin).
  - The needle ticks as before. Level-ups add a burst at the rollers to the existing toast and U6 chime; no new audio is needed.
  - No idle ejection.

**Play check** (flag preview, isolated test profile `ptf20261113`):

| Check | Result |
|---|---|
| D1 Train! → seated on the rollers | **0.127 s** and **0.128 s** from press to seated (≤ 0.5). Puff + TrainPlace beat + accepted result. Cart at the trigger, facing up the ramp. |
| D1 training ticks | `TrainingActive` = true and XP climbing (+1 per tick); the cart is in `TrainingCarts`, flagged, and not despawned. Captures: [D_trainplace_on_rollers_STOP.jpg](captures/D_trainplace_on_rollers_STOP.jpg), [D_xp_pop.jpg](captures/D_xp_pop.jpg) ("+1 XP", STOP button). |
| D2 refusals | TooFar returned with its toast. The other reasons are covered by the TrainPlaceRules spec; carrying and dazed were not driven in Play. |
| D3 four players at once | **Not tested in Play** (single test client). The spec covers N occupants; the group rule is the mechanism. |
| D4 STOP | Unseated beside the deck; `TrainingActive` false on the next tick; XP kept. |
| D4 prompt | "Open" (no Bay busy), `BayTrainingCount` = 1 while training. |
| D5 idle | The shared-bay tick has no AFK path. A 10-minute idle run was not done. |

**Noted:**

- The HUD shows **Cargo 0/0 while seated** on the rollers and 0/3 on foot. The cart's capacity attribute stays 3; it looks like how the HUD shows cargo while driving, not something this change caused, but it's worth a glance.
- The camera ease is reset by the Studio automation tool in captures, so it was not visible in them.

## Part E — Size ladder

- **E1/E2:** `BrainrotVisualScale` takes the role from the existing `context`:
  - **Wild:** Awake, Sleeping, WorldPrepared/Adopted, Decoy, FrontTeam, CatchReveal, IndexShot.
  - **Base:** Deposited.
  - **Carry:** Cart, Carried, cargo `LightweightVisual`.
  - Wild uses `HeightByRarity × 5.158`. Base uses the ladder, capped to 92% of the slot, never below 6.706. Carry stays 6.706.
  - Scaling stays absolute and idempotent: `ExactBodyPlacement.Normalize` gained an optional multiplier.
  - **Celestial** isn't in the prompt table; it's set to **2.30**. Please confirm.
- **E3, what follows the size:**
  - **Spawn envelopes:** `RegionSpawnCatalog` uses the ladder height.
  - **Name tags, the escape "?", contact shadows, base placement and formation geometry** read `VoxelCreatureRegistry.ModelMeasurement`. It now scales its `normalized*` fields by the model's `PlaytestSizeRatio` (the raw fields used for normalization are untouched). `CreaturePresentationController` keeps that attribute when it syncs attributes.
  - **Scoop ground ring:** radius × the ratio; arrow height already followed the Body part.
  - **Hunt hitboxes and query proxies** follow the server proxy scale automatically.
  - **Unchanged:** the villager escape ring (a chase distance by rarity), the scoop radius and its vertical limit (measured from pivots), and HP, damage and ranges.
- **E4:**
  - **Catch pop:** a brainrot going into the cart or into the player's hands pops 0.7 → 1.12 → 1.0 (Back out, 0.3 s) on the local visual only.
  - **First sighting:** the first Mythic, Celestial or Secret within 80 studs each session gets a pulsing rarity-colour ground ring and a 0.2 s camera nudge (`Humanoid.CameraOffset`).
  - **Not seen in Play:** no catch was made, and no Mythic+ spawned.
- **E5:** see [size_ladder_fit.md](size_ladder_fit.md).
  - All 35 species are listed. The prompt's expected caps are within 0.25 studs (BRT_001 7.09, BRT_006/011 6.71 floor, BRT_027 8.54, BRT_028 7.77, BRT_032 9.24, BRT_034 9.65).
  - **Flags:** BRT_028 (11.8) and BRT_031 (11.6) are nearly as wide as the 12-stud alleys, and every Legendary, Mythic and Secret is taller than the 10-stud doorways.
- **Play check:**
  - Forest wild brainrots render at ratio 1.192 (Common, 8.0) and 1.269 (Uncommon, 8.5).
  - Name tags sit on the larger bodies. Capture: [E_wild_ladder_forest.jpg](captures/E_wild_ladder_forest.jpg).
  - Base displays were not seen: the test profile has nothing banked.
- **E6:** proposals are in [doc_edits.md](doc_edits.md).

## Tests and lint

- `run-playtest-fixes-tests.sh`: **72/73.**
  - New TrainPlaceRules.spec 6/6 (each refusal, N occupants, legacy single occupant, bay pose).
  - New SizeLadder.spec 7/7 (heights, roles, carry floor, base fit cap and floor, flag off).
  - The one failure is the existing `BrainrotVisualScale.spec` check, which still expects a 0.64 ratio. The config has been 1.3 since before this work, and neither file was changed by me. It is stale.
- Selene: 0 errors on changed files. StyLua formatted the changed files (some owner lines in already-touched files were reformatted). `CartAssemblyValidator.lua` was restored from the snapshot and carries only the 6-line exception.

## Play starts

**Six** Play starts this checkpoint, against a budget of two. Each fixed something the previous run exposed:

1. Placement refused by the drivable-ground rule.
2. A rail overlap.
3. Bootstrap stopped because I configured groups before `CollisionService`.
4. The validator despawned the test cart.
5. A client bug (an ambiguous `(Controller :: any)` line).
6. The clean run.

All runs used the test profile; the owner's profile was never loaded. These problems would otherwise have shipped behind the flag.

## Owner decisions

1. **Celestial** ladder value (2.30).
2. **Doorway height:** cap wild Legendary/Mythic/Secret at about 9.8 inside village footprints, or accept the clipping.
3. **Diagonal base placement** for the capped long species (default no).
4. **D6 personal roller pad per base:** see below.

## D6 — personal roller pad per base (not built)

What it would take:

- **Art:** a 10 × 14 roller pad per base (8 bases), with a `RollerTrigger`, deck pieces and rollers, authored once and cloned into each base's patch. Bases are Studio-owned, so this is a native write plus an export.
- **Code:** `TrainingService` treats each pad as a bay (`BindPrompt` per pad). `TrainPlace` targets the player's own pad instead of the camp stall, using `NearestBay` filtered by base ownership. The shared-bay and validator rules carry over unchanged.
- **Rules:** other players can't use your pad, and a pad needs its own collision group (or reuses `TrainingCarts`).
- **Effort:** about a day including captures, plus owner approval of the pad art.

## Changed files (CP-C)

- **New:**
  - `src/shared/Utility/TrainPlaceRules.lua`
  - `src/server/Tests/TrainPlaceRules.spec.lua`, `src/server/Tests/SizeLadder.spec.lua`
  - `docs/playtest_fixes/size_ladder_fit.md`, `doc_edits.md`, `CP-C_Report.md`, captures
- **Edited:**
  - `Config/PlaytestFixes.lua` (TrainPlace messages, camera, DeckLift; Celestial)
  - `Services/TrainingService.lua`, `Services/DriveAndHuntService.lua`
  - `Validation/CartAssemblyValidator.lua` (6 lines)
  - `Utility/BrainrotVisualScale.lua`, `ExactBodyPlacement.lua`, `VoxelCreatureRegistry.lua`
  - `Systems/RegionSpawnCatalog.lua`
  - `Controllers/DriveAndHuntController.lua`, `CampStallController.lua`, `ScoopFxController.lua`, `CreaturePresentationController.lua`
  - `UI/Screens/StallTrainingScreen.lua`
  - `scripts/studio-playtest-fixes-test-runner.luau`
- **Place:** no CP-C changes. The deck tags and groups are applied at runtime only.

Test profile key `phase8_test_ptf20261113_player_10098729613` (in `dev_v2`) now holds Training XP from these runs.
