# Playtest Fixes 2: CP-A and CP-B report (14 Nov 2026)

Branch `feature/camp-rework` (uncommitted). DEV place 91958083796436, **not saved, not published**.
Snapshot: `.checkpoints/playtest_fixes2_20261114/src_and_project.tgz` (src, project, scripts, tools).

**Stopped at CP-B** for owner approval of the treadmill look and the Legs speed cap. Part G (build),
the full checks table and Part H (release) have not started.

## 0. Reconcile

- AGENTS.md read. The canonical root is in use, on branch `feature/camp-rework`, with a large dirty tree from earlier work.
- `Deployment.lua`: ReleaseId `P14_VILLAGER_OUTFITS_20261110_R1`, place 91958083796436.
- `design/Playtest_Fixes_14Nov.md` **does not exist** in either location. I worked from the prompt alone.
- Studio and `src/` matched byte-for-byte on every file touched, so there were no Studio-only moves.
- **The Rojo plugin was disconnected.** I did not reconnect it: connecting re-applies the mapped October `.rbxm` exports (AGENTS.md hazard). Every change was mirrored into Studio by script edits instead. Reconnecting later is safe for these files: Rojo will overwrite them with the identical `src/` versions.
- **Another session is editing `src/shared/Config/VillagerSkins/*`** in this checkout. I did not touch those files.

## A0. Root causes (reproduced in Studio Play with live settings: all previews off, new flags off)

| Input | Result | Cause (confirmed by the trace) |
|---|---|---|
| Controller | **Stuck.** I opened Weapons, entered pad selection and pressed B. The window closed, but Roblox moved the selection onto a HUD button (`DriveAndHunt.SwitchButton.Button_CART`, then `StudPopHud.Rail.Hud_Brainrots`). | `GuiService.SelectedObject` stayed set, so `Phase10InputPolicy.IsMenuOpen` stayed true and blocked driving and firing. No menu attribute was set. Trace line: `blocked drive (ButtonR2): Selected=…Button_CART … Carried=nil IsMenuOpen=true`. |
| Keyboard | The same stuck state blocked W once a selection existed (it can also be reached with `\` UI navigation). | Same as the controller row. |
| Keyboard, Backspace close | OK. | — |
| In cart (keyboard) | Not blocked: assembly `Valid`, `CarriedItemId` nil. | — |
| Touch | **Not reproduced.** The Studio MCP tools cannot emulate touch input. | Unknown. The DEV trace exists so a phone can capture it: set `ReplicatedStorage.InputTrace = true` on a live server. |

Second cause, found by reading code: on close, the Team window put back the selection it had saved when it opened, which could be a HUD button. This produces the same stuck state.

The prompt's "found" notes are otherwise correct. Two small corrections: `RetentionPublicInspectOpen` has no writer left in `src/`, so any value it holds is stale; and the shop writes `Phase13ShopOpen = false`, not nil.

## Part A: InputUnstick (flag `PlaytestFixesV2Enabled` + sub-flag)

- **A1:** `MenusV2.cleared`, `closeCurrent` and `setOpen` (when replacing a window) clear the selection. Gamepad B closes the top window in one press even when Roblox also used B to drop the selection. The Team window no longer puts back a HUD selection.
- **A2:** `IsMenuOpen` counts `SelectedObject` only when it is a visible descendant of an open menu gui (`MenusV2` or the compare dialog). A 1 Hz watchdog (`InputUnstickController`) heals stale `MenusV2Open`, `Phase13ShopOpen`, `ChariotTeamMenuOpen` (unbinding its R2 sink), `RetentionPublicInspectOpen`, `Phase13CompareDialogOpen` and stray selections, each after 2 stale ticks, and logs a DEV warning.
- **A3:** HUD buttons (every gui except menus and TouchGui) get `Selectable = false`. Brainrots and Inventory get D-pad Left and Right shortcuts. On a gamepad, a menu selects its first button when it opens and clears it when it closes.
- **A4:** In the two cargo-load paths, the server now clears `CarriedItemId` *before* `MarkFreshTransit`, which is now pcall-wrapped. An error there could previously skip the clear. Every other carry path already cleared it the same frame. A DEV warning fires when a seated driver stays blocked for more than 1 s.
- **A5:** Prompts are unchanged. They already carry E and ButtonX, and Roblox draws the right glyph per device.
- **Verified in Play, flags on:** the same controller sequence ends with selection nil, `IsMenuOpen = false` and no blocked trace. Forced stale `MenusV2Open`, `Phase13ShopOpen` and `RetentionPublicInspectOpen` plus a HUD selection all healed within 2 s.

## Part B: Jump hops out

Jump while driving your own cart sends the existing HOP OUT request: Space and Cross/A through the existing sink, touch through `JumpRequest`. Jump is ignored for `HopOut.SeatedGraceSeconds` after sitting, at most one request per 0.3 s, and the touch Jump button stays visible. The HOP OUT button, C and D-pad Up still work. With the part on, Space no longer fires while driving (G and left click do), and the hint reads "JUMP to hop out and reach it".
**Verified (keyboard):** Space unseated the player, who landed 11.3 studs beside the cart. A second Space 100 ms later sent nothing. Touch and pad Jump were not tested (no emulation).

## Part E: parity

- **E1:** `CampReworkFlags` previews are now opt-in (`<Name>Preview == true`). The place still had five preview attributes set to true (CampRework, Training, RebirthUi, WeaponTiersV2, VoxelCreaturesV4), so ordinary Studio Play ran five features that devices don't. **All preview attributes are now cleared in the place.** The server prints the resolved switch table at start. With previews off, Studio resolves exactly as a live server does (hash `aef590`).
- Studio/live gate audit, GAMEPLAY items that were on in Studio by default:
  1. The five preview attributes above (cleared).
  2. `PassesGemsScreen` showed "Preview" buttons on every Finish in Studio. This is now opt-in through `FinishPreview`.
  3. *Not fixed, reported:* `DevelopmentBrainrotSpawner.ValidateFreshRouteRelease` accepts route-less releases in Studio. Test fixtures may depend on it, so it needs a test run before gating.
  4. *Not fixed, minor:* `MutationAppearanceAdapter` builds V4 mutation FX on a Studio server.
  5. *By design:* Studio saves to an isolated `phase8_test_*` profile key, so Studio progress never matches a device.
- **E2:** Settings shows `Build <ReleaseId> · Switches <hash> · Place version …`.
- **E3:** Stall audit (`Utility/StallAudit`, DEV only, red label over failures). With release settings: Weapons, Training, Gems and NEWS **pass**. Carts **fails** with 2 prompts on E: the shop and the cargo-bay `CartUpgradePrompt`, the known shared stall. Sell's prompt lives in `ServiceStallPatches.SellStall`, so the audit now matches prompts by position. With live (flags-off) settings, Sell and Training have **no prompt** and NEWS still has its Passes prompt. That is today's device state until the release switch-on.

## Part C: cash pads (sub-flag CashPads)

- **C1:** The sensor is 6 studs tall. A 5 Hz poll runs over each owner's own pads, querying only pads within reach (one `GetPartBoundsInBox` each, owner-only filter). It claims on entry, then every 1 s while the pad holds ≥ 1. `Touched` stays as the instant trigger.
  - Bug found and fixed during the test: the poll passed the first overlapping part, often an accessory or the held tool, which the existing handler rejects. It now claims with the root part.

  | Measurement (50 scripted walk-ons over the 12 ground pads) | Before (flag off) | After (flag on) |
  |---|---|---|
  | Walk-ons that triggered a claim | 50/50 | 50/50 |
  | Standing still on a pad with income for 6 s | 1 claim (entry only) | 6 claims (entry + about 1/s) |
  | Server cost | — | about 0.2–0.36 ms per 5 Hz poll (1 player, Studio) |

  In Studio, plain walk-ons were already reliable. The real gain is standing still (and anything that jumps past a 1-stud sensor).
- **C2:** The stack appears over each owned pad with unclaimed cash: 12 welded, non-colliding, non-queryable parts in 3 steps, a `$77.2M`-style billboard, and one looping bob tween per pile. The ≤ 10 Hz scheduler refreshes it, culls it beyond 80 studs and hides it at 0. Capture: `captures/C2_stack.jpg`.
- **C3:** On claim the pile pops (1 → 1.25 → 0, 0.2 s) and pooled coins fly to the counter (4 on Low, 8 otherwise; off-screen pads start from the screen edge). The counter holds until the first coin lands, then rolls up and bumps (throttled), with "+$…" beside it. Coin ticks play on landings, and a chime (provisional cue `E2_1`) plays for claims worth ≥ 60 s of income. Measured in Play: 4 coins in flight (the resolved tier was Low), "+$" shown, counter held at 0 when Cash changed and then rolled to 336M → 424M. The flight was too short to capture.

## Part D: solid base walls (authored; revert `scripts/RevertBaseWalls.server.lua`)

- **Measured with raycasts:** side walls x −36.56…−33.16 and 6.50…9.90, back wall z 19.96…21.78, filleted back corners, 23 tall, front fully open (the doorway). The shell is identical in all 8 bases.
- **Colliders:** **5 per base, 40 total**, in `Base_0#.WallColliders`. They are invisible, CanCollide true, CanQuery and CanTouch false, collision group `BaseWalls` (registered in `Config/CollisionGroups` and `CollisionService`). Author tool: `tools/playtest_fixes2/BuildBaseWalls.edit.luau`.
- **Clearance check (all 8 bases):** the doorway, HouseRamp, CartRamp, DepositReturnZone, CartDisplay, CartSpawn, PlayerSpawn, every stair and landing, and all 48 slot approaches. **0 conflicts.**
- **Play, keyboard walking (Base_01):** blocked at the left wall (x −32.4), the back wall (z 19.3) and the right wall from the cart side (x 10.6). The doorway walk-out passes.
- **Not tested:** driving into a wall, and walking to upper-floor slots (capacity 12 profile). Villager and steal paths are unchanged (front open).

## Part F: stable bars (sub-flag StableBars)

The prompt's finding is partly corrected: `StudPop.ProgressBar` has **no callers**. The bars that twitch are `Plate.StripedProgress` (BrainrotsScreen ×2, StallTraining, StallWeapons). Their screens **rebuild** the bar on every update, which restarts the stripe scroll.
- **Fix:** both bars ignore sub-0.002 changes with an unchanged label, pop only when crossing to full, and hide fills under 4%. Striped bars start their scroll at the clock's phase, so a rebuilt bar continues seamlessly.
- **Other meters:** the Training world needle tweens only on a level change (OK). The Training screen needle is static per render. The Rebirth screen has no meter.

## Part G1: treadmill concept (CP-B stop)

29 parts in the Training stall's own family: wood-plank frame, dark metal, a black rubber belt with slats, yellow hazard trim, a blue "LEGS" console with a dial, and a "RUN!" sign. It sits in the gap between Training and Gems, 1.6 studs clear of the canopy brace. Only the belt collides.
Builder: `tools/playtest_fixes2/BuildTreadmillConcept.edit.luau`. The model is parked in `ServerStorage._ConceptBooth.LegsTreadmill_Concept`, so the live world is unchanged.
Captures: `captures/G1_treadmill_close.jpg` and `captures/G1_treadmill_context.jpg`.

## Tests

`src/server/Tests/PlaytestFixes2.spec.lua`: **16/16 pass**. It covers the predicate, selection rules, Jump debounce, pad poll decision, stack steps, coin origin, bar guard, opt-in previews, switch hash and stall verdict. Also passing: Phase10InputPolicy, DriveAndHuntRules and ConfigValidator. CartCameraOcclusion has 5 failures that are **pre-existing** (identical without these changes).
Selene shows 0 errors; its one warning is pre-existing in `StudPop`. StyLua is clean on new files; edited files kept their existing formatting. Strict Luau was not type-checked locally (no analyzer installed).

## Owner decisions

1. **Treadmill look:** approve, or name changes.
2. **Legs speed cap:** guards chase at 0.8–1.05 × the cart's top speed (≥ 34.6 studs/s), so Legs 15 at 26 studs/s cannot outrun them. Proposal: **no cap**, keep 16 → 26.
3. **Trail prices** 150 / 300 / 600 Gems (as specified). Confirm.
4. **Audio:** there is no dedicated claim chime. `E2_1` is used provisionally. A treadmill run loop has no cue either.
5. **Carts stall:** two prompts on E (shop + cargo bay). Keep, or merge into one?
6. **Release switch-on (Part H)** once G is built and checked.

## Notes and deferred items

- Economy observation (not changed): the test profile's BRT_007 earned 2,000,000/s and the Daily Gift offers $250M per day. Check that this is intended.
- The Studio MCP camera reset (`Fixed`) stops ProximityPrompts showing in automated Play. This is a tool artefact, not a game bug.
- Studio test profile key now in `dev_v2`: `phase8_test_ptf2a20261114_player_10098729613`.
