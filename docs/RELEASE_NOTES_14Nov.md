# Release notes, 14 Nov 2026

**Place:** Brainrot Expedition [DEV], 91958083796436 (universe 10548905405)
**Published version:** 1409 (published from Studio by the owner on 14 Nov 2026, number confirmed by the owner)
**Commit:** `8acd726` (flag flip). Most of the code it switches on is still uncommitted on `feature/camp-rework`; the Studio place is what ships.
**Release switch hash:** `8d24b6` (Settings → Build line shows it on a live server)

## Switched on

| Flag | What players get |
|---|---|
| `CampReworkV1Enabled` | The rebuilt camp main street: new stalls, special weapons and selling back. |
| `TrainingV1Enabled` | The Training stall and 25 Training levels, replacing the cart Speed upgrades. |
| `RebirthUiV2Enabled` | "Rebirth" naming, the YOU LOSE / YOU GET window, the payback line and the READY glow. |
| `PlaytestFixesV1Enabled` | Stall weapon poses, weapon effects, "Train" sends you to the rollers, the brainrot size ladder, the Gems stall, map studs. |
| `PlaytestFixesV2Enabled` | Menus can no longer leave controls stuck; Jump hops you out of the cart; cash pads keep paying while you stand on them, with a coin pile and coins flying to the counter; steady progress bars. |
| `LegsTrainingV1Enabled` | The Legs treadmill beside Training: stand on it to gain Legs XP (AFK works). Legs levels raise walking speed from 16 to 26. Free trails at Legs 5, 10 and 15; Rainbow, Glitch and Fire trails for 150, 300 and 600 Gems. New Trails tab in Inventory. |

Always on, not behind a flag: solid walls around all 8 bases. The doorway stays open.

## Unchanged
Income, prices, weapon stats, HP, odds, cargo, carrying and stealing, guard chase rules and existing save fields. The Legs fields are new and start at zero. Gem purchases use the existing purchase path and receipts.

## Checked before release (Studio, previews off, flags on)
- All six flags resolve on from `FeatureFlags` with no Studio preview attributes set.
- Treadmill: Legs XP 0 → 3 in 3.5 s on a fresh test profile; no script errors at start.
- Spec batch (24 suites): 245/248 pass. The 3 failures are the same ones that fail with every flag off (a plaque material check and two Phase14 inspector tests).
- Four specs were updated because they assumed the flags were off: the profile schema, cash-pad touch height, the PlaytestFixes "ships off" check and the controller-focus legacy contract.
- CP-C checks (keyboard + controller emulator) cover the rest: `docs/playtest_fixes2/CP-C_Report.md`.

## Known gaps
- **Touch / phones not tested.** To trace stuck input on a live server, set `ReplicatedStorage.InputTrace = true`.
- The Carts stall still has two prompts on E (shop and cargo bay).
- The cash-pad claim chime is a stand-in sound, and the treadmill has no sound.
- Not re-run after the flip: driving into a base wall. (Re-run since: the cart rollers and on-foot hunting, see below.)

## Playtest Fixes 1 re-check after the flip (14 Nov, Studio Play, released flags, no preview attributes, test profile `ptf20261114`)
- Train!: seated on the rollers in 0.130 s; Training XP 7 → 10 in 3 s; the cart stays in `TrainingCarts`, flagged, not despawned. STOP puts you on foot and keeps your XP.
- On-foot hunting: a real shot at a Common was accepted (asleep, HP 0), and the shot-effect pool was built.
- Size ladder: wild server proxies are 8.0 studs (Common) and 8.5 (Uncommon).
- Camp: the Gems stall is in the world with its "GEMS" prompt; the NEWS board is up and NEWS has no prompt.
- One Play start. The test attributes were cleared afterwards. The place had no new edits, so there was nothing new to save.

## Rollback
Set the flag(s) back to `false` in `ReplicatedStorage.Shared.Config.FeatureFlags` and publish. Turning `LegsTrainingV1Enabled` off hides the treadmill; saved Legs data is kept. To remove the base walls, run `scripts/RevertBaseWalls.server.lua`.
