# Playtest Fixes — CP-A report (13 Nov 2026)

Scope: reconcile; Part A (map studs); Part B (weapon stall poses). The master flag `FeatureFlags.PlaytestFixesV1Enabled` is **false**. Nothing has been saved to the cloud or published.

## Reconcile

- Branch `feature/camp-rework` at `4e5ce25`, with a large set of uncommitted owner work (preserved). The build stamp is `P14_VILLAGER_OUTFITS_20261110_R1`. Rojo maps code and the `CodeAssets` weapon/display `.rbxm` files; `MapBlockout` is not mapped (the place owns the stall).
- **Studio vs `src`:** all 26 scripts named in the prompt exist in both, at identical byte sizes. No script was Studio-only, so nothing was moved.
- **Design docs:** `design/Playtest_Fixes_12Nov.md` and the other `design/` documents are not on this machine. The work follows the prompt.
- **World builder:** `tools/terrain/BuildWorld.edit.luau` (Edit-mode tool) → `Shared.Utility.TerrainBuilder.Dress`. The built world is stored in `ServerStorage.TerrainRedesign.World`; at server start `TerrainRedesignSwitch` parents it to `Workspace.World`.
- **Stall builder:** `tools/camp-rework/StallBuilder.luau` authors the `CampSlots`.

Recovery:

- **Source:** `.checkpoints/playtest_fixes_20261113_preCPA/` (`source.tgz`, `tracked.diff`, `status.txt`, `HEAD`).
- **Place:** `ServerStorage.PlaytestFixes_Recovery_20261113` holds copies of the World store, `Kiosk_WeaponHarpoonStall` and `Kiosk_AnnouncementStall`, taken before any change.

### Differences from the prompt's section 1

- **World textures:** the World had **2,911** stud Textures, not about 914, and 6,438 parts (4,921 SmoothPlastic, 1,517 Neon).
- **Rack/wall slots:** none faced the customer under a consistent frame. RackSlot_1–3 had **mirrored (left-handed) CFrames**. RackSlot_2 pointed along the rail, not at the customer. RackSlot_4–6 and the wall slots were tilted at assorted angles.
- **`SlotLength`:** it was the **peg spacing** (3.3–4.6 studs), not the rail. The rack boards are 8.27 studs between posts; each wall slot owns 4.77 of the 14.3-stud pegboard.
- **Display scale:** `WeaponDisplays` are already authored at exactly **1.5× held size** (HRP_001 6.90 vs 4.60 held). Each display carries `Family`/`Tier` attributes. Prism Repeater and Crystal Lance are tagged `Crossbow`.
- **B1 frame:** as written, it cannot be built. With Up = up and Look = the customer's left, the Right vector points *into* the stall. Slots therefore use Look = customer's left and Up = rack up, and the customer looks at −Right. The dev assert checks −Right.
- **Prompt's 12/12 count:** the stall has **9** rack/wall slots (6 rack + 3 wall); the 3 medal slots were already consistent.

## Part A — map studs (`MapStuds`)

Rule (`Shared.Utility.MapStudPolicy`, config `PlaytestFixes.MapStuds`):

- **Studded:** SmoothPlastic, Plastic or Glacier parts become Glacier + `Environment_Saved_Studs_13719188279`. Colour is kept, `CustomPhysicalProperties` is pinned to the pre-change physics, and the overlay Textures are deleted.
- **Skipped:** Neon, other materials, Transparency > 0.3, parts with a SurfaceGui/Decal, the `Lane_GlowTiles`/`Volcano_LavaStrip` kits, and trim under 0.6 studs on two axes.
- **Fixed at the source:** `BuildWorld.edit.luau` applies the same rule on rebuild. The stored world was migrated once in place (`tools/playtest_fixes/ApplyMapStuds.edit.luau`).

| | Before | After |
|---|---|---|
| World instances | 10,338 | **7,427** |
| BaseParts | 6,438 | 6,438 (no new parts) |
| Stud Textures | 2,911 | **0** |
| Parts with the variant | 0 | **4,407** |

Skipped: 1,517 Neon · 484 glow-kit parts · 18 sign/text parts · 8 trim · 1 transparent.

| Region | Changed | Textures removed |
|---|---:|---:|
| Forest | 1,357 | 729 |
| Beach | 735 | 396 |
| Jungle | 650 | 388 |
| Swamp | 513 | 190 |
| Volcano | 446 | 502 |
| GlitchZone | 332 | 514 |
| Arctic | 294 | 146 |
| Gates | 48 | 30 |
| Camp | 32 | 16 |

| Check | Result |
|---|---|
| A1 | Pass in the captures taken (Forest, Beach, Arctic, Jungle, Glitch props and four landmarks). Studs read at about 40 studs. The Play server shows all 4,407 parts studded at runtime. Per-region 20/40-stud close-ups for Swamp/Volcano are still to do. |
| A2 | Pass. Neon, glow kits, text plates and transparent parts were skipped; water is terrain and untouched. |
| A3 | Pass. Every migrated part was plain SmoothPlastic with no custom physics, and friction is 0.200 before and after (pinned). Stud size is the bases' own variant (4 studs per tile), so it matches by construction. The 20-stud base-slot close-up timed out and is still owed. Landmarks (100+ studs) show many small studs at a distance, which looked fine in the capture. |
| A4 | Pass: 2,911 Textures removed, 2,911 fewer instances. |
| A5 | Pass. 20 random parts reverted on detached clones match `stud_backup.json` 20/20. |

- **Backup:** `StudMigrationOriginal*` attributes on every changed part, plus [stud_backup.json](stud_backup.json) (4,407 parts, 2,911 texture faces).
- **Revert:** `scripts/RevertMapStuds.server.lua` (Edit only, dev only).
- **A5 Grass override:** no trial needed. Since the 10 Nov owner request, every terrain material (Grass, LeafyGrass, Ground, Sand, Rock, Snow, Mud, Basalt) already has an `AF2_Building_*` stud override. `Environment_Saved_Studs` is Glacier-based, so it cannot override Grass.

Captures:

- [A1_props_40_before.jpg](captures/A1_props_40_before.jpg)
- [A1_props_40_after.jpg](captures/A1_props_40_after.jpg)
- [A1_arctic_jungle_landmarks_after.jpg](captures/A1_arctic_jungle_landmarks_after.jpg)

## Part B — stall poses (`StallPoses`)

- **B1:** `tools/playtest_fixes/NormaliseStallSlots.edit.luau` rewrote the 9 rack/wall slots, keeping their positions. **9/9 failed the check before and 9/9 pass after.** The wall slots share a 12° lean. `SlotLength` is now the usable rail (Rack 8.2, Wall 4.7). The old frame and length are kept in `LegacySlotCFrame` / `LegacySlotLength`. `StallBuilder.luau` applies the same rule on rebuild; `RevertStallSlots.edit.luau` undoes it. `CampStallController` warns once per bad slot.
- **B2:** the pure resolver `Shared.Utility.StallDisplayPose` uses the family table plus per-ID overrides in `PlaytestFixes.StallPoses`, with no code branches. The per-ID mapping is in [display_axes.md](display_axes.md).
- **B3:** displays go up at 1.5× and shrink only on a >5% overrun, never below 1.2×.
- **B4:** medals use the same family pose at their existing small fit.
- **Flag-off path:** the old pose logic, reading the Legacy* attributes.

| Check | Result |
|---|---|
| B1 | 9/9 slots pass |
| B2/B3 wall (owner decision, 13 Nov) | **Pass.** Two weapons on the back wall: the two slots split the pegboard (7.0 studs each), and all 30 displays fit (the longest at 1.27×). WallSlot_3 is unused while the flag is on. Capture: [B_wall_two_slots.jpg](captures/B_wall_two_slots.jpg). |
| B2 (after owner decision, 13 Nov) | **Pass.** Two weapons per board, a random few (seeded once per session, from the same unowned pool), rows at 2.8 and 6.2 studs, each weapon kept inside a 3.4-stud row (still never below 1.2×), crossbow lean reduced to 10°. RackSlot_3 and RackSlot_6 are unused when the flag is on and keep their old frames for the flag-off path. All 9 slots still pass the check. Captures: [B_two_per_board_front.jpg](captures/B_two_per_board_front.jpg), [B_two_per_board_threequarter.jpg](captures/B_two_per_board_threequarter.jpg). |
| B2 (first pass) | **Partial.** The 30-ID resolver test passes, and guns read cleanly in side profile with the muzzle to the left. However, at the existing slot heights: the three tier-8 weapons on one 8-stud board overlap heavily; the 25° crossbow lean pushes crossbows out and below the board; and the top-row bow sits mostly under the roof beam. The poses are right, but the board can't hold three weapons at 1.5×. Owner decision 2. |
| B3 | Racks: 30/30 at 1.5×. Wall: **22/30 still overrun at the 1.2× floor**; reported, not squashed. Tier 8 reads bigger mainly through its effects (Part C), not its length. |
| X1 | Pass. In a live Play client (flag off), every stall display sits on its `LegacySlotCFrame` at the old `SlotLength` (positional error 0.000), so the game looks exactly as before. |

Captures (Edit-mode preview through the same pose maths, `tools/playtest_fixes/PreviewStallDisplays.edit.luau`; left board T8, right board T1–T2, wall = paid specials):

- [B_stall_front_before.jpg](captures/B_stall_front_before.jpg)
- [B_stall_front_after.jpg](captures/B_stall_front_after.jpg)
- [B_stall_threequarter_T8_board.jpg](captures/B_stall_threequarter_T8_board.jpg)
- [B_T1T2_board_closeup.jpg](captures/B_T1T2_board_closeup.jpg)
- Stud close-up at 20 studs: [A3_rock_studs_20.jpg](captures/A3_rock_studs_20.jpg)

The preview folders were removed afterwards.

## Tests and lint

- `scripts/run-playtest-fixes-tests.sh`: **51/51 pass.** StallDisplayPose.spec 38 (all 30 display IDs, slot frames, scale, rack-row and two-slot wall fit), MapStudPolicy.spec 5 (eligibility, apply, exact revert, flag-off gate), ConfigValidator.spec 8.
- StyLua and Selene are clean on every changed file. StyLua also reformatted some existing lines in `CampStallController.lua` and `FeatureFlags.lua`.
- No Luau type checker (`luau-lsp`/`luau-analyze`) is installed, so **strict typing was not checked**.

## Owner decisions

1. **Decided 13 Nov: two on the wall.** Done. Earlier note: **wall slots** were too short for most top-tier weapons, even at 1.2×. Choose one: two wall slots (7.1 studs each), diagonal hanging, or accept the overlap.
2. **Decided 13 Nov: two per board, a random few.** Done (see B2). Earlier note: **rack rows** are 1.6–2.9 studs apart, so at 1.5× neighbouring weapons overlap badly (see the ¾ capture). My recommendation: **two weapons per board** (rows about 3.5 studs apart, with the bottom row above the board foot), and drop the crossbow lean to about 10°. Alternatively keep three per board and accept 1.2×, which still overlaps. This changes the slot positions, which B1 told me to keep, so it needs your approval.
3. **`SlotLength`** now means the rail length (the old values are kept in `LegacySlotLength`). Confirm this reading of B1.
4. **Grass terrain studs (A5):** already live through the AF2 overrides. Nothing to decide unless you want a different tile size.

## Changed files

- **New:**
  - `src/shared/Config/PlaytestFixes.lua`, `src/shared/Config/PlaytestFixesFlags.lua`
  - `src/shared/Utility/MapStudPolicy.lua`, `src/shared/Utility/StallDisplayPose.lua`
  - `src/server/Tests/{StallDisplayPose,MapStudPolicy}.spec.lua`
  - `scripts/RevertMapStuds.server.lua`, `scripts/run-playtest-fixes-tests.sh`, `scripts/studio-playtest-fixes-test-runner.luau`
  - `tools/playtest_fixes/*.edit.luau`
  - `docs/playtest_fixes/*`
- **Edited:**
  - `src/shared/Config/FeatureFlags.lua` (new flag, false)
  - `src/client/Controllers/CampStallController.lua`
  - `tools/terrain/BuildWorld.edit.luau`
  - `tools/camp-rework/StallBuilder.luau`
- **Place (Edit DataModel, unsaved):** the stored World stud migration, the 9 Weapons stall slots, and the recovery folder.

## Known limitations

- Captures are at the Studio viewport size (935 × 882). The capture tool cannot set 844 × 390.
- No phone test, no Play check of the flag-on path, and no frame-time numbers yet (P1 is due at CP-D).
- A3 relies on the props using the bases' own variant object (4 studs per tile); there is no side-by-side capture with a base slot.

**Please save the place in Studio** to keep the stud migration and the slot frames.
