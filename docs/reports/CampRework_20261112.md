# Camp Rework — weapons, stalls, camp layout, floor, Training, Rebirth UI (12 Nov 2026)

Branch `feature/camp-rework`, one commit per part (A–G). Nothing was published. All three new flags are
**false live** and on by default in Studio preview (`Config/CampReworkFlags`; the ReplicatedStorage attribute
`<Name>Preview = false` turns a preview off). `WeaponTiersV2Preview = true` is set in the Studio place only.
Paid delivery stays disabled (`ProductionDeliveryEnabled = false`).

Captures are in [`camp_rework_20261112/`](camp_rework_20261112/).

## A. Weapons
- 28 concept weapons converted by `tools/camp-rework/WeaponConverter.luau` (T1 Trailwood, T2–T8 × 3, 3 Premium, 3 Won).
  Scrapbolt Crossbow (`WPN_C01`) and Tinpop Blaster (`WPN_G01`) keep their art.
- Held sizes (longest axis): Bow 4.6, Crossbow 5.0, Blaster 4.2; T8 and specials +10%. Measured old tools: bow 4.1, crossbow 3.6, blaster 2.5.
- Every tool ≤ 150 BaseParts **including** the Handle and the invisible animation rotors (max 150; hard cap 220 never approached).
  Concept → tool: HRP_001 263→142, B02 272→145, B03 304→150, B04 334→149, B05 477→147, B06 933→147, B07 556→150,
  B08 488→150, C02 201→102, C03 251→147, C04 264→126, C05 450→150, C06 909→150, C07 564→149, C08 398→150,
  G02 189→66, G03 199→61, G04 402→149, G05 629→150, G06 924→148, G07 592→145, G08 246→150,
  Rift Blaster 340→149, Prism Repeater 356→150, Crystal Lance 325→148, Collector's Bow 298→107, Getaway 462→150, Secret Hunter 422→146.
- Muzzle (shot origin) re-placed at each new arrow/bolt/muzzle tip; Tool.Grip unchanged; `Phase13ArtVersion = 2`; art under `Phase13Appearance`
  (finish roles derived from part names). SPINS/MOVES groups ride one rotor Weld each on the shared ≤10 Hz scheduler (measured 10.5 ticks/s);
  Prism Repeater drum: exactly 60° per fire event (0.08 s Back + click). No ammo anywhere. Tier 7 keeps stars, eclipse (as a black sun in
  front of the weapon) and orbit rocks; no smoke/mist. 1.5× anchored displays for all 30 weapons in `CodeAssets.WeaponDisplays`.
- Six specials (`WPN_SP_*`) off the tier ladder; Gem shop (Prism Repeater 300, Crystal Lance 900), Robux pass row (Rift Blaster, no ID),
  milestone grants via the critical transaction (Collector's Bow 15 species, Getaway 25 clean escapes, Secret Hunter first Secret).
  Never Cash-buyable, never sellable.
- Verified in Play: bow/crossbow/blaster held from three angles (`weapon_*.jpg`); muzzle sits at the arrow/bolt/barrel tip.
  A real accepted shot was not fired in automation (needs a locked brainrot target); the server origin is `Handle.Muzzle.WorldPosition`.

## B. Stalls
| Stall | Concept parts | Shipped parts | Notes |
|---|---:|---:|---|
| Weapons | 3,253 | 561 | concept display/rack weapons replaced by per-player client displays; NEW! plank dropped; medal pedestals added (boxes, no text) |
| Carts | 1,314 | 556 | every approved element kept; hitched brainrots are client props (216 parts, `CodeAssets.CampStallProps`) |
| Sell | 49 | 49 | |
| Training | 235 | 214 | screenshot display cart removed |
- Prompts: "Open" + WEAPONS / CARTS / SELL / TRAINING, 12 studs; Training on the speedometer post; "Bay busy" for others.
- Kit kiosk and its "Manage kit" path removed. Sell counter opens a Sell menu: carried brainrot + Cash weapons/carts at 25% back.
- `ServiceStallPatches.SellStall` moved under the Sell counter (invisible, non-colliding); the legacy SELL BRAINROTS board is never spawned
  while the new stall exists. `StallFootprint_*` parts keep spawn exclusion working. `CartUpgradeStall` tag moved to the Carts anvil.

## C. Layout (seed 20261112, 400 candidates)
- Forest + Beach (busiest) leave camp through the **north-west** exit (west end of the north road ≈ (−267, −250)); Sell sits NW,
  Weapons + Carts opposite (sectors 225° / 0° / 90°, Training 315°).
- Winner (candidate 317, score 55.11 = sightlines 48.00 + earn→spend 10.39 − walking 9.87 + variety 6.59):
  Weapons (34.7, −59.1) 93.1° · Carts (−11.6, −2.6) 14.8° · Sell (−41.8, −73.6) −134.6° · Training (0.6, −71.3) −30.5° (ramp outward) ·
  Announcements (−44.5, −34.3) 114.6°. Landmark `REGION_CAMP_Hero` + shrub moved to (−19, −46).
- Walking: Sell–Weapons 77.9, Sell–Carts 77.2, Sell–Training 42.5, Weapons–Carts 73.0, Weapons–Training 36.2, Carts–Training 69.8 studs.
- Sightlines (5 studs above each entrance): every base sees ≥ 2 stall signs; the landmark is visible from 8 of 12
  (not Base_04/07/08/10 — the 20-stud barn and kiosk hide the 14.5-stud waystone). **No candidate met "every base sees the landmark".**
- Alternatives: #2 candidate 364 (51.71, landmark from 7 bases), #3 candidate 136 (50.15, from 5). Set `CampLayout.Selected` and re-run
  `tools/camp-rework/CampPlacer.luau` to switch.
- The random radius stays in 32–58 but is biased inward (u²): with Sell opposite the spending pair and pairs ≤ 80 apart, uniform radii
  left 1 survivor. Rejections: pair distance 203, landmark spacing 88, footprint spacing 84, shared axis 18, kiosk room 4.
- Stalls face the landmark (rule 8), so bases on the far side see sign backs.

## D. Floor
- `Path_Camp_1_1` (ring + cross + base driveways; one mesh, CSG not possible) deleted with a backup; its two outside-the-ring corner-road
  pieces rebuilt as `Path_Camp_1_1_CornerRoads`. Other `Path_Camp_*` are outside the ring and unchanged. Coloured pads removed.
  The ring interior is plain `Floor_R3_C3` grass (`after_topdown.jpg`). Verifiers/measurements updated; GLB pipeline unchanged (notes added).

## E. Training
- 25 levels; level 1 = 60 XP, ×1.35 per level; old Speed n = Training 5n (geometric between); rollers Wooden ×1 / Steel ×3 2.5B /
  Turbo ×10 15B / Rocket ×40 75B / Rift ×150 300B; 2× Training pass (no ID). Migration: TrainingLevel = max(current, 5 × SpeedLevel), versioned.
- Verified in Play: XP +1/s on Wooden with the cart on the rollers, level 1 at 60 XP (next 81), cart speed reconciled (+1.9%),
  LV readout live, bay occupancy published.
- Economy (`tools/camp-rework/economy_sim.py`, calibrated to the documented 4.3 h): free player to Glitch **4.29 h → 4.49 h (+12 min)**;
  2× Cash pass 2.83 h → 3.02 h. Level ≈ 10 at Jungle assuming ~10 s of training per trip (≈ 12 at 20 s). Level1Xp kept at 60.
  Speed matters little because progression is income-bound. Speed 1's 500M price point has no roller equivalent.

## F. Rebirth
- Base prompt "Rebirth" / "Rebirth — Ready!" (prompt name unchanged); HUD glow + breathe while READY; YOU LOSE / YOU GET / payback
  lines computed on the server; `Rules.ApplyRebirth` unchanged (Cash route → balance 0). No Base Upgrades stall.
- Not exercised end to end in Play (the test profile has no Cash to quote a rebirth); payback maths is unit-tested.

## G. Tests and performance
- Full TestEZ suite (headless Studio `RunScript`, 246 spec files): **3,242 tests, 3,134 passed, 108 failed, 0 file errors** on the
  last full run; the one rework-caused failure left in it (WeaponTiersV2 counted 24 definitions, now 24 + 6 specials) was then fixed
  and re-run with the other touched specs (CampRework, PlayerProfileSchema, Upgrades, WeaponTiersV2: 56/56 pass). So **107 failures
  remain, none in code this rework touched**: they reproduce in untouched areas (ProgressionMetrics fake player lacks `GetAttribute`,
  `StoredBrainrots` base fixtures, cargo/placement geometry, routes, terrain spawn catalogue, camera occlusion, map readiness,
  sleep bounds, nametags, rift renderer, wallet HUD, `MaxTravelSpeed` vs the uncommitted `Carts.lua`, a 300M rebirth fixture now
  below the reward price, a missing `_TestRefreshPerformanceProfile` hook, an imported base-sign fixture clash).
- New `CampRework.spec` (14 tests): flags, specials never sellable/never Cash-priced, sell-back 25%, Training maths/migration/levels/cap,
  roller purchase, Speed retired under Training, trigger box, rebirth payback/ready, scheduler culling. Sale point spec gained
  two camp-mode tests and parks the place's real SellStall/Sell Sign during its fixture.
- Legacy specs for the pre-Training profile/Speed contract pin `TrainingV1Enabled` off for their run
  (`CampReworkFlags._SetForTests`, Studio-only) — the flag previews on in Studio and these specs predate it.
- Fixes found by the suite: `Weapons.BuildDefinitions` re-froze the special unlock tables on a second build (crash);
  v2 weapon finish roles now resolve when the whole Tool is passed, not only the `Phase13Appearance` folder.

- Highlights active: 0 (all concept Highlights stripped). Stalls stream atomically.
- 60 FPS on a mid-range phone profile in the Studio device emulator was **not measured** (not drivable through the automation tools).

## Open owner actions
1. Create the Robux IDs: Rift Blaster game pass (499 R$) and 2× Training pass (price placeholder 199 R$ — confirm).
2. Flip `CampReworkV1Enabled`, `TrainingV1Enabled`, `RebirthUiV2Enabled` (and `WeaponTiersV2Enabled`) live when ready.
3. Choose the layout (winner or alternatives #2/#3); decide whether to raise the landmark or move the kiosk so every base can see it.
4. **Save the Studio place.** The new stalls, landmark move and path removal live in the place file (`MapBlockout` is Rojo-mapped
   from an older `.rbxm`, so a Rojo re-sync could restore removed instances). A full export of the new camp art is in
   `assets/native/camp_rework_20261112/CampReworkWorld.rbxm`; weapons/displays/props `.rbxm` are mapped in `default.project.json`
   (`.rbxm` files are git-ignored, as before).
5. Review the 1-second confirm delay and the Sell-menu "switch first" rule for equipped items.
