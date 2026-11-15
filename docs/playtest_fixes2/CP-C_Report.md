# Playtest Fixes 2: CP-C report (14 Nov 2026)

The owner approved the treadmill look and **no speed cap** (16 → 26) on 14 Nov 2026. Part G is built.
Nothing is committed, the place is **not saved** and nothing is **published**. Part H (release) waits for the owner's go.
CP-A/CP-B details: `CP-AB_Report.md`.

## Part G: what was built (flag `LegsTrainingV1Enabled`, default false)

| Piece | Where | Notes |
|---|---|---|
| Config | `src/shared/Config/LegsTraining.lua`, `LegsTrainingFlags.lua` | 15 levels; XP curve has Training's shape (60 XP to level 1, ×1.35 per level); +1 XP/s, ×2 with the existing 2× Training pass; WalkSpeed 16 → 26 linear; 6 trails. |
| Save data | `Phase13Rules.MigrateLegs / ApplyLegsTick / ApplyTrailEquip` + validation | New `Phase13` fields `LegsXP`, `LegsLevel`, `OwnedTrails`, `EquippedTrail`, plus `LegsVersion`. Defaults are zero / empty. This follows the existing Training pattern (a field-versioned, idempotent migration inside `Phase13`) **instead of a global SchemaVersion bump**: one moving part, and the profile-schema specs stay untouched. With the flag off, profiles are never modified. Rebirth never touches these fields, so the Legs level is kept. |
| Treadmill | `MapArt.Services.LegsTreadmill` (authored in the place) | The approved concept. Only the belt collides, and the belt doesn't make players collide with each other. With the flag off, the server moves it to `ServerStorage._PlaytestFixesHidden` at start. |
| Server | `src/server/Services/LegsTrainingService.lua` | 5 Hz presence poll (point-in-belt test, no physics queries). Standing on the belt counts, no input needed, so it's AFK-friendly. Ticks every 1 s. The server sets WalkSpeed from the saved level and skips dazed players (daze owns WalkSpeed while active). One Trail per player, on foot only. `LegsRequest` RemoteFunction: EquipTrail (owned only, 0.5 s cooldown, exact payload keys). |
| Client | `src/client/Controllers/LegsTrainingController.lua` | Run in place: each character the server marks `LegsRunning` plays its **own Animate "run" animation locally**. This is the cheapest method: no new asset, no humanoid movement, nothing replicated. The belt slats scroll on the existing ≤ 10 Hz scheduler. It reuses Training's "+XP" pops, level-up burst and level toast (now "+1 LEGS LV", with chime U6). The console dial follows the Legs level. A "NEW TRAIL!" toast appears on unlock. Low quality halves the Lifetime of every visible Legs trail. |
| Trails | `Economy.GemShop` (3 items) + `GemRules` "Trail" kind | Free at Legs 5 / 10 / 15 (green, purple, gold). Rainbow 150, Glitch 300 and Fire 600 Gems go through the **existing GemShop critical transaction (receipts unchanged)**. The Gem Shop tab lists them automatically. Inventory has a new **Trails** tab with equip and unequip. |
| QA | `ServerStorage.LegsQA` (Studio + attribute only) | `AddXp` (through the real tick rule) and `GrantGems`, for the isolated test profile only. |

## Checks (Studio Play, release configuration = every Part H flag as a Studio preview)

| ID | Result | Evidence / limits |
|---|---|---|
| A1 | **Pass** (keyboard + controller emulator) | Daily Gift, Weapons, Carts, Sell, Training and Inventory each opened and closed with controller B (pad selection active): every time `MenusV2Open = nil`, `SelectedObject = nil`, `IsMenuOpen = false`. Window swap (Gems → Inventory), walk-away and ✕ click all close clean. Backspace was verified in CP-A. Each stall was run once per path, not 10 times. |
| A2 | **Pass** | Forced stale flags and a HUD selection healed within 2 s (CP-B). |
| A3 | **Pass** | Cart assembly `Valid` and `CarriedItemId` nil while driving. No "seated driver blocked" warning in any run. |
| B1 | **Pass** (keyboard) | Space hopped out and landed 11.3 studs from the cart. No double request. The grace period is covered by a spec. |
| C1 | **Pass** | 50/50 walk-ons (before and after). Standing still: 6 claims in 6 s (before: 1). In the release config: 2 claims in 2.5 s while standing. |
| C2 | **Pass** | The stack shows and grows, the pop and coins fire, and the counter waits and then rolls (4 coins on Low). |
| D1 | **Pass** (Base_01 walked, all 8 checked geometrically) | Walls block from inside and outside; doorway passes; 0 clearance conflicts in 8 bases. **Not tested:** driving into a wall, upper floors. |
| E1 | **Pass** | With everything off, Studio's switch hash is `aef590`, identical to live resolution. |
| E2 | **Pass** | The stall audit passes Weapons, Sell, Training, Gems and NEWS. **Carts fails** with two prompts on E (owner decision, unchanged). |
| F1 | **Pass** (specs) | Guard, crossing-to-full pop, hide < 4%, phase-locked stripes. Not visually captured. |
| G1 | **Pass** | On the belt: `LegsRunning`, XP +1/s, run animation looping (`913376220`). AddXp 600 took Legs 0 → 5: WalkSpeed **19.33 set by the server**, Green trail unlocked. Equip Green: trail on, Lifetime 0.225 (Low). Bought Rainbow: Gems 208 → 58, owned. Equip Rainbow: exactly one trail. Unowned Fire → `NOT_OWNED`; an extra payload key → `INVALID_REQUEST`. Seated → trail off, `LegsRunning` cleared. Hop out → trail on, WalkSpeed kept. |
| X1 | **Pass** (except the walls, by design) | Every new flag off: treadmill moved out of the world, no `LegsRequest`, no Legs attributes, WalkSpeed 16, no trail, no gem trails, switch hash `aef590`. |
| Touch | **Not tested** | The Studio tools cannot emulate touch. The touch Jump button route (`JumpRequest`) and touch input are untested. Please check on a phone: set `ReplicatedStorage.InputTrace = true` on a live server to log blocks. |

**Play sequences** (keyboard + controller, Studio):
1. Spawn → open and close every stall (done) → treadmill → buy and equip a trail (done). "Train" on the cart rollers was not re-run in CP-C.
2. Drive (60.9 studs) → fire G in the cart (no block; a hit on a brainrot was not confirmed) → hop out with Jump → bank (scooped and banked onto pad 1 in CP-B) → stand on a cash pad (claims). On-foot hunting was not exercised in CP-C.

**Tests:** `PlaytestFixes2.spec` **22/22**. Also passing: Phase10InputPolicy, DriveAndHuntRules, ConfigValidator, PlayerProfileSchema, Phase13Migration, Phase13Transactions, Phase13Durability, CampRework, Phase14CosmeticOwnership and CargoUpgradePersistence, **88/88**. The 5 pre-existing failures in CartCameraOcclusion are unchanged. Selene shows 0 errors (the only warnings are pre-existing), and StyLua is clean on new files.

## Fixed during CP-C
- Free-trail cards showed "TODO SHOT". They now use the Bolt icon, and the gem lock text is shortened to "300 Gems".

## Before Part H (owner)
1. **Save the place.** The walls, the treadmill, every script change and the cleared preview attributes exist only in the open Studio session. The Rojo plugin is still disconnected (deliberately: the mapped `.rbxm` hazard).
2. **Say go for Part H.** It will: switch on the six flags in one commit, re-run the checks with Studio previews off, save, and publish to 91958083796436 (I can't publish from tools; you publish and give me the version), then write `docs/RELEASE_NOTES_14Nov.md`.
3. **Open decisions:** the Carts stall's two prompts, the claim chime (provisional `E2_1`), no treadmill loop cue, the economy numbers seen in the test profile (2M/s income, $250M daily gift), and touch testing on a device.
