# Playtest Fixes — CP-D report (13 Nov 2026)

Scope:

- Part F: the Gems stall placed (F2–F4), and the NEWS kiosk becomes a read-only board.
- A performance pass.
- The full checks table.
- Both play-check sequences.

The master flag `FeatureFlags.PlaytestFixesV1Enabled` is still **false**. Nothing has been published. **The placed Gems stall is in the open place but not saved. Please save the place (File → Save).**

## Part F — Gems stall

### F2 — wiring (code, flag-gated)

- **PassesKiosk:** with `PlaytestFixesV1` / `GemsStall` on, the existing client `PassesKioskPrompt` binds to `Kiosk_GemsStall` and reads "GEMS" instead of the NEWS kiosk. It opens the same Passes & Gems window, with no new remote and no new purchase path.
- **Walk-away close:** `Phase13ShopController` adds the Passes window to the stall prompts that close when you walk away, and `MenusV2` knows the prompt name.
- **NEWS:** `Systems/PlaytestCampStalls` keeps the NEWS kiosk prompt-free. It adds a read-only SurfaceGui board on its customer face with the headline, one line and "Codes → Settings", all from `Config.PlaytestFixes.NewsBoard`.
- **Flag off:** at server start, `Kiosk_GemsStall` is moved to `ServerStorage._PlaytestFixesHidden`, so the world and the NEWS prompt are exactly as before.

### F3 — the board

Panel 9 × 5 studs, centred 6.5 studs above the floor, 0.15 studs in front of the kiosk box, LightInfluence 0, nothing in front of the text. Capture: [F3_news_board.jpg](captures/F3_news_board.jpg).

### F4 — placement (native, place-owned)

`tools/playtest_fixes/PlaceGemsStall.edit.luau` cloned the approved concept into `MapBlockout.MapArt.Services.Kiosk_GemsStall` at **(-121.4, 0.05, -46), yaw 0**: 79 parts, 13 small decoration parts with CanQuery and CastShadow off. Capture: [F4_gems_placed_edit.jpg](captures/F4_gems_placed_edit.jpg).

| Main street (z = -46), x | Before | After |
|---|---|---|
| -150 | Sell | Sell |
| **-121.4** | (open street) | **Gems** (12.2 to Sell, 13.0 to Training) |
| -92 | Training | Training |
| -52 | NEWS (Passes & Gems prompt) | NEWS (read-only board) |
| -19 | landmark | landmark |
| 42 | Weapons | Weapons |
| 108 | Carts | Carts |

- **First choice rejected:** x = 75 failed the 12-stud spacing rule, with gaps of 6.7 and 0.1.
- **CampLayout:** `CampLayout.MainStreet` records the live positions. The ring layouts got a `gems` entry for completeness only, because their generator rules describe the old ring camp, not the main street.
- **Walking it:** only the street's north–south crossing was walked. The east–west walk along the full street was not.

### F5 — owner action (not something code can do)

To show the platform shop button:

1. Open Creator Hub → your experience → **Monetization → Shop**.
2. Turn on **In-game shop button**.

### HUD opener finding

The HUD gem pill has no plus action, and there is no contextual "Get Gems" button; only the NotEnoughGems toast and the Gems tab exist. With the flag on, the Gems stall is the only in-world way to the Passes window, as the NEWS kiosk was before. I did not add a HUD button, because that is outside this prompt.

## Play-check sequences

Both use the isolated test profile `ptf20261113`. The owner's ordinary profile was never loaded.

**Sequence 1 (flag preview on): camp.**

- The Gems prompt "GEMS · Open" (12 studs) opens Passes & Gems and closes on walk-away. Capture: [F2_gems_opens_passes.jpg](captures/F2_gems_opens_passes.jpg).
- NEWS has no prompt, and the board reads correctly in Play.
- Train! seats you in **0.129 s**; XP ticks; the level-up toast and burst play; STOP unseats you.

**Sequence 2 (flag preview on): hunt and bank.**

- A real shot at a Common BRT_001 was accepted (hit, slept), and the shot-effect pool built 68 pooled instances from 4 templates.
- The rare wave spawned a Rare BRT_019 at ratio **1.346** (9.1 studs), against Commons at 1.192 and Uncommons at 1.269. It slept after 2 hits and was scooped into cargo beside the cart. Capture: [P2_rare_wave_drive.jpg](captures/P2_rare_wave_drive.jpg).
- Driving it home banked it on Base_01. The deposited display measured h 9.04, w 3.50, **d 12.79**. That is depth-capped at 13.9 × 0.92 = 12.79, ratio 1.332, which is the base-fit cap working.
- **Not captured:** a picture of the base display. The automation tool resets the camera and the Daily Gift window covered the view; the measurement above is the evidence.

**Flag off (preview cleared): X1.**

- `Kiosk_GemsStall` is not in the world (it is in `ServerStorage._PlaytestFixesHidden`).
- There is no NEWS board.
- The NEWS prompt is `PassesKioskPrompt` "PASSES & GEMS · Open · 12", as before.

## Performance

| Sample (camp, single client) | Flag on | Flag off |
|---|---|---|
| Instances | 106,183 | 105,614 (**+569 with the flag on**) |
| Client memory | ~8,175 MB | ~8,262 MB (Studio total; noise at this size) |
| Frame time | 16.66 ms (60-fps cap, Low quality) | 66.6 ms (exactly 15 fps: Studio throttling an unfocused window, so not comparable) |

Limits:

- These are Studio numbers on one client, not a device test.
- The prompt's six dummy carts in the bay were not spawned.
- Frame time is capped at 60 fps in Studio. The flag-off frame time is throttled and does not compare with the flag-on sample.
- The shot pool is fixed at 4 per effect type and does not grow with shots fired.

## Full checks table

| Check | Result | Where |
|---|---|---|
| A1 world studs | Pass: 4,407 parts studded, read at 40 studs | CP-A |
| A2 skips (Neon, glow, text, transparent, water) | Pass | CP-A |
| A3 physics and stud size unchanged | Pass: friction 0.200 pinned, bases' 4-stud tile | CP-A |
| A4 instance cost | Pass: 2,911 Textures removed | CP-A |
| A5 revert | Pass: 20/20 match `stud_backup.json` | CP-A |
| B1 slots normalised | Pass: 9/9 | CP-A |
| B2 rack poses (two per board, random few) | Pass | CP-A |
| B2/B3 wall (two slots) | Pass: 30/30 fit | CP-A |
| B3 rack scale | Pass: 30/30 at 1.5× | CP-A |
| C1 display effects on, culled when hidden | Pass | CP-B |
| C2/C3 pooled shot effects, tier ladder | Pass: T1–T8 captured; pool of 4, 68 instances in Play | CP-B, CP-D |
| C4 empty weapons filled, v2 art WPN_C01/G01 | Pass | CP-B |
| C5 effect budgets | Pass: all within budget | CP-B |
| D1 Train! → seated ≤ 0.5 s | Pass: 0.127 / 0.128 / 0.129 s | CP-C, CP-D |
| D2 refusals | Pass: TooFar in Play, the rest in spec | CP-C |
| D3 four players at once | **Not tested in Play** (single client); covered by spec | CP-C |
| D4 STOP | Pass | CP-C, CP-D |
| D5 no idle ejection | By construction; a 10-minute idle run was not done | CP-C |
| E1/E2 ladder by role | Pass: Wild 1.192 / 1.269 / 1.346 | CP-C, CP-D |
| E3 base fit cap | Pass: Rare deposited, depth-capped 12.79 | CP-D |
| E4 catch pop / first sighting | Catch pop runs on scoop; first sighting **not seen** (no Mythic+ spawned) | CP-C |
| E5 fit report | Done | [size_ladder_fit.md](size_ladder_fit.md) |
| F1 concept | Approved | CP-B |
| F2 Gems opens Passes & Gems, closes on walk-away | Pass | CP-D |
| F3 NEWS read-only board | Pass | CP-D |
| F4 placement, 12-stud spacing | Pass: gaps 12.2 / 13.0 | CP-D |
| F5 platform shop button | **Owner action** (Creator Hub) | above |
| X1 flag off = unchanged | Pass: stall hidden, NEWS prompt as before | CP-D |
| P1 performance | Partial: +569 instances; no dummy-cart run, no comparable frame time | above |

## Tests and lint

- **`run-playtest-fixes-tests.sh`: 74/75.**
  - The new `PlaytestCampStalls.spec` passes 2/2 (board on the customer front, a turned kiosk).
  - The one failure is the stale `BrainrotVisualScale.spec` 0.64 check, unchanged since CP-C.
- **Selene: 0 errors** on the CP-D files.
  - The 5 warnings are in existing `Phase13RuntimeService` code: an unused `CommerceRules` and shadowed variables.

## Play starts

Three Play starts this checkpoint, against a budget of two:

1. Sequence 1.
2. Sequence 2.
3. Flag off for X1.

All used the test profile.

## State left behind

- **Place, Edit mode:** `Kiosk_GemsStall` placed (**unsaved**). `PlaytestFixesV1Preview`, `DriveByHaulQA` and `Phase8TestProfileNamespace` are all cleared.
- **Test profile key** `phase8_test_ptf20261113_player_10098729613` (in `dev_v2`) holds test data: Training XP and one banked Rare BRT_019.
- **Recovery:** `.checkpoints/playtest_fixes_20261113_preCPA/` and `ServerStorage.PlaytestFixes_Recovery_20261113`.

## Owner decisions still open

1. **NEWS board text:** headline and line, in `Config.PlaytestFixes.NewsBoard`.
2. **Celestial** ladder value: 2.30.
3. **Doorway height:** cap wild Legendary, Mythic and Secret at about 9.8 inside villages, or accept the clipping.
4. **Diagonal base placement** for long species (default no).
5. **D6 roller pad per base** (not built; see the CP-C report).
6. **Missing uploads** noted in CP-B (engine particle textures are in use for now).
7. **CP-E (14 Nov):** the master flag was turned on by the Part H release (`8acd726`, see `docs/RELEASE_NOTES_14Nov.md`). The Train!, hunting, size-ladder and camp checks were re-run with the released flags and passed; the results are in the release notes. The owner published it as version 1409.

## Changed files (CP-D)

- **New:**
  - `src/server/Systems/PlaytestCampStalls.lua`
  - `src/server/Tests/PlaytestCampStalls.spec.lua`
  - `tools/playtest_fixes/PlaceGemsStall.edit.luau`
  - this report and its captures
- **Edited:**
  - `Config/PlaytestFixes.lua` (GemsStall placement, NewsBoard)
  - `Config/CampLayout.lua` (`MainStreet`, gems entries)
  - `Services/Phase13RuntimeService.lua` (starts PlaytestCampStalls)
  - `UI/Screens/PassesKiosk.lua`
  - `Controllers/Phase13ShopController.lua`
  - `UI/MenusV2.lua`
  - `scripts/studio-playtest-fixes-test-runner.luau`
- **Place:** `MapBlockout.MapArt.Services.Kiosk_GemsStall` (unsaved).
