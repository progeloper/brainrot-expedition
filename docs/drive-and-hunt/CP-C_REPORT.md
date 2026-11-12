# Drive-and-Hunt — CP-C report (12 Nov 2026)

Scope: Part D (scoop feedback), Part E (first-time hints), performance pass, full checks table, play checks. Flag `DriveAndHuntV1Enabled` is still **false**. Nothing committed, saved to Roblox or published. CP-D (flag on + publish) is not started and needs your explicit go-ahead.

## 1. What was found and how it was extended

| Item | Finding | What I did |
|---|---|---|
| Scoop distance | `HuntFlow.ScoopRadius = 13` from the cart pivot, checked in `DriveByHaulSystem` and `validateScoop` | While the flag is on, both use cart half-width + 7 from the centre line (a capsule: the same 7 studs past the front and back edges). Flag off: the original 13-stud radius, unchanged. `HuntFlow.lua` is byte-identical. Vertical limit unchanged. |
| Half-width source | `CartGeometry` profiles have `BodySize` | Half-width = `BodySize.X / 2`. A cart without a profile keeps the old radius. |
| `CargoPlaced` "already sent" | It is a server-side receipt, not sent to the client | The existing FX remote sends the driver a `Scoop` message from that receipt. No new remote. |
| Cart-load sound | `SFX_LoadAccent` already plays on every load through the existing presentation path | Not played a second time. **In this place the sound is not installed** (console: "Audio uninstalled: SFX_LoadAccent"), so loads are silent today. |
| Home indicator | No HUD compass. `WorldPointer` (gold world arrow + beam) exists | Cargo full reuses `WorldPointer` aimed at your base for 4 s, and adds one small gold "HOME ▲" arrow beside the cargo row that turns toward the base. |
| "Cargo full" toast | Server toast in `DriveByHaulSystem` | The same moment sets a player attribute the client listens to (flag on only). |
| Onboarding storage | None exists | Hints are session-only (a local player attribute). No profile field added. |

New files: `Controllers/ScoopFxController.lua`, `Controllers/DriveAndHuntHints.lua`. Edited: `DriveAndHuntRules.lua` (`ScoopShape`, `InScoopReach`), `Config/DriveAndHunt.lua` (`Scoop`, `HintToast`), `DriveByHaulSystem.lua`, `BrainrotInteractionSystem.lua` (one optional parameter on `validateScoop` / `TryScoopIntoCargo`, 18 changed lines), `DriveAndHuntService.lua`, `DriveAndHuntController.lua`, and the rules spec.

## 2. Scoop reach per cart (D1)

Reach beside the cart = half-width + 7. Reach ahead/behind = half-length + 7. Old rule: 13 from the pivot in every direction.

| Cart | Half-width | Reach beside | Reach ahead/behind |
|---|---|---|---|
| CRT_001 | 3.66 | 10.66 | 11.99 |
| CRT_006 | 3.76 | 10.76 | 12.09 |
| CRT_007 | 3.86 | 10.86 | 12.24 |
| CRT_008 | 3.26 | 10.26 | 11.39 |
| CRT_009 | 3.36 | 10.36 | 11.54 |
| CRT_010 | 3.46 | 10.46 | 11.69 |
| CRT_011 | 4.06 | 11.06 | 12.44 |
| CRT_012 | 4.21 | 11.21 | 12.59 |
| CRT_013 | 4.36 | 11.36 | 12.74 |

**This is shorter than today for every cart** (13 before). The prompt's formula gives that result; say if you want a larger `Scoop.Reach`.

## 3. What was built

- **Rings:** up to 6 pooled rings of 16 Neon segments (8 on Low) in rarity colour, a bobbing ▼ over the brainrot, for sleeping wild brainrots within 45 studs of the cart you are driving. Client-only; nothing shows on foot.
- **Magnet pull:** a local copy of the brainrot (made when its ring appears) flies to its cargo slot in 0.25 s (Back-in, 3-stud arc, shrinking), then a pop at the slot and a "+1" beside the cargo row. The real brainrot is never touched. If no ring existed yet, only the pop and "+1" show.
- **Cargo full:** gold HOME arrow on the HUD for 4 s plus the existing gold world arrow and beam to your base.
- **Hints:** one Stud Pop toast at a time, 3 s, queued, with an arrow to its control or to the ring. Nothing in it takes input.

## 4. Check results

Two Play starts, test profile `dah20261112`. CP-A and CP-B rows are carried over unchanged unless noted.

| ID | Result | Evidence |
|---|---|---|
| G1 | Pass (CP-A) | Seated 0.46 s after crossing |
| G2 | Pass, partial coverage (CP-A) | 400 launches, 0 overlaps; only the 15 Forest lanes received carts |
| G3 | Pass (CP-A) | |
| G4 | Pass (CP-A) | |
| G5 | Pass | CP-A, and again here: cargo 3 → 0 at the base, still seated. The cart was moved to the base by the test script, not driven. |
| S1 | Pass on keyboard (CP-A) | Not tested on touch |
| S2 | Pass | C exits, launcher equipped (again this run) |
| S3 | Pass (CP-A) | |
| S4 | **Pass, both paths now** | Success in CP-A. **Failure path run here:** cargo 3/3, LOAD & GO refused, still carrying, not seated. |
| S5 | Pass (ledge) | Brainrot 15 studs above the cart: pulse in 0.5 s. Indoor case not run. |
| L1–L7 | As CP-B | L3 and touch part of L7 still untested (no touch in Studio) |
| D1 | **Pass** | Spec over all cart profiles. Live: a sleeping brainrot 11.3 studs beside CRT_001 (inside the old 13) was **not** scooped; moved to 10.2 it was. |
| D2 | **Pass** | Rings: 6 rings × 8 segments with 7 sleepers nearby (capped at 6). Magnet copy in flight ≈ 0.3 s, then pop and "+1". Cargo full: HOME arrow, world arrow and beam on. Captures 01–03. |
| D3 | **Pass** | Synthetic "?" on a Forest villager (Suspicious), then a real drive-by scoop: villager went to WindUp, chase radius 225. |
| H1 | **Pass** | All five hints shown exactly once in one session, never two at once (frame-by-frame log). "Never blocks input" is by construction (no element is input-active); no key was pressed while a hint was on screen. |
| P1 | **Counts within budget; frame time not measured** | See section 5. |
| F1 | Pass by construction | Flag off: service and controllers return before creating anything; scoop uses the old radius; the attribute is never set. Not separately played. Spec confirms the flag ships false. |

**Play sequence 1** (launch → lock → FIRE → sleep → drive over → "+1" → home → auto-bank): every step happened, but not as one unbroken drive. The lock and shot were real (key press, server trace `ASSIST_LOCK` hit, slept). The first sleeper woke before the scripted drive reached it, so the scoop was staged by moving a sleeping brainrot into reach. The trip home was a test-script move.

**Play sequence 2** (HOP OUT → shoot on foot → LOAD & GO → chase → "ESCAPED!"): ran through HOP OUT hint, hop out, shot key press, carry and LOAD & GO with full cargo (refused correctly). **It did not reach chase or "ESCAPED!"**: I could not free a cargo slot, because the existing Drop request returned `NO_SAFE_POSE` at three different spots. LOAD & GO success was seen in CP-A and load → chase in D3, but the two were not run back to back, and "ESCAPED!" was not observed in this work.

**Tests:** `./scripts/run-drive-and-hunt-tests.sh` — **206 of 210 pass** (17 rules tests including 4 new for scoop reach and hints config, 18 selector tests). The 4 failures are the `BrainrotSleepSystem.spec` "B1 enlarged bounds" group. **I ran the same suite against the pre-change snapshot: the same 4 fail there**, so they predate this work.

**Lint:** Selene clean on all new and touched Drive-and-Hunt files; StyLua clean on the files I own. `BrainrotInteractionSystem.lua` and `DriveByHaulSystem.lua` were edited by hand and not reformatted.

Captures (1377 × 882 Studio viewport, not 844 × 390): `docs/drive-and-hunt/captures/cpC_01`–`04`.

## 5. Performance pass (P1)

Measured with the client's quality tier resolving to Low.

| Item | Budget | Observed |
|---|---|---|
| Target selection | ≤ 10 Hz, ≤ 12 scored | 10 Hz scan, 12 cap, reused scratch tables (code + spec) |
| Reticles | 1 BillboardGui | 1 |
| Sleeping rings | ≤ 6 × 16, pooled | 6 rings, 48 segments on Low (96 max), parts reused |
| Ring arrows | — | 6 BillboardGuis (one per ring); not in the prompt's budget table |
| Launch/call FX | ≤ 12 particles (6 Low), 1 Highlight | unchanged from CP-A |
| Magnet copy | — | at most 6 local copies held (one per ring), one in flight |
| Server gate | 10 Hz, edge band only | unchanged |
| Placement | ≤ 27 bounds queries | peak 1 this run (6 in CP-A) |
| New remotes | 1 FX + 1 request | unchanged; scoop and cargo-full add none |

**Frame time was not measurable.** Studio ran at about 10 fps under automation with or without rings (80 ms vs 96 ms per frame, inside the noise), so I have no trustworthy cost figure. This needs a device or a normal Studio session.

## 6. Final config values added in CP-C

`Scoop`: Reach 7, RingRadius 45, MaxRings 6, RingSegments 16 (Low 8), RingStuds 4.5, scan 4 Hz, pulse 10 Hz, MagnetSeconds 0.25, arc 3, end scale 0.4, "+1" 0.8 s, FullSeconds 4. `HintToast`: 3 s, queue of 4, texts as in the prompt.

## 7. Known limitations

- The HOME arrow was moved up one row after the last Play (it touched the toast's corner in capture 03). That final position is unverified.
- On Low, 8 segments on a 4.5-stud ring look sparse (capture 02).
- Rings appear on any sleeping wild brainrot nearby, including one the server would refuse (for example in a region you have not unlocked).
- "DRIVE OVER IT!" can show while cargo is full.
- "TAP TO SHOOT!" has no arrow on PC, where there is no FIRE button.
- Hints reset every session.
- The existing Drop request refused with `NO_SAFE_POSE` three times under automation. That code is untouched and I did not investigate.
- Turret swivel, hop animation and camera ease are still not built (open from CP-A/B).
- The test profile's wallet now shows 1.25B from banking during these runs. Test profile only.
- No physical phone test. No touch input test.

## 8. Owner decisions

1. **Scoop reach:** every cart now reaches less than the old 13 studs. Keep 7, or raise it?
2. **Load sound:** `SFX_LoadAccent` is not installed in this place. Upload it, or pick another existing sound for the scoop?
3. **Hints:** session-only is the only option without a profile field. Accept, or approve one saved field later?
4. **Bystander puff:** still sent to everyone within 120 studs.
5. Still open from earlier: turret (art / aim line / drop), keys (C / D-pad Up), launch boost, menus vs gate launch, hop animation, lock vs weapon assist cones.
6. **CP-D:** not authorised yet. I would not recommend turning the flag on before a phone test of touch FIRE, tap-to-switch and the jump block.

## 9. Recovery

`.checkpoints/drive_and_hunt_cpA_20261112/` (source before any change) and Roblox place version 1250. Test attributes are removed; I have no pending place changes. **Save the place yourself** when you are happy with your own Studio work.
