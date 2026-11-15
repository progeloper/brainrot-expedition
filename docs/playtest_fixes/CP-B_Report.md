# Playtest Fixes — CP-B report (13 Nov 2026)

Scope: Part C (weapon VFX) and the F1 Gems stall **concept**, which is not placed in camp. The master flag `FeatureFlags.PlaytestFixesV1Enabled` is **false**. Nothing has been saved to the cloud or published.

## What I found and how I extended it

- **Shots:** `SleepLauncherController.renderShot` draws each bolt as a few Neon parts plus a PointLight; `receiveSleepResult` already runs for every observer. `WeaponArtController.OnShot` already bursts any emitter tagged `EmitOnFire` and spins `CampAnimRotor` rigs on the shared ≤10 Hz scheduler. I reused both, adding no second FX or animation system.
- **Textures:** the place only uses the engine's `sparkles_main` and `smoke_main`. The new effects use six engine-built textures (`rbxasset://textures/particles/...`: sparkles, smoke, explosion core, shockwave, implosion, fire sparks), so **no uploads are needed**.
- **`CodeAssets.Weapons` / `WeaponDisplays`** are Rojo-mapped, git-ignored `.rbxm` files. Authoring effects or art into them in Studio would be reverted on the next Rojo connect, and the MCP bridge timed out on `SerializationService` export. So:
  - effects are **added at runtime by one authoring pass**, `WeaponFxLibrary.Author`, which hangs config-listed effects on the weapons' existing V4 parts (server, held art in `Phase13RuntimeService.applyWeapon`; client, stall displays);
  - the new WPN_C01/G01 art ships as generated, git-tracked `src/assets/PlaytestArtV2/*.model.json` and `PlaytestDisplaysV2/*.model.json` (builder: `tools/playtest_fixes/build_t1_weapons.py`). It is preferred only while the flag is on.

## C1 — stall display effects

- **Effects on:** `staticize` keeps ParticleEmitters on rack and wall displays when `WeaponFx` is on. Greyed medals now switch off emitters and trails as well as beams and lights.
- **Culling:** each display registers one entry with `CampAnimationScheduler`. I added an optional `hidden` callback to the scheduler, so effects switch off beyond **60 studs** or off-screen, back on when visible, at the ≤10 Hz tick. On Low quality, beams and lights stay but particles are off.
- **Play check (flag on, isolated test profile):**
  - rack displays B04 5/5, G02 4/4, C03 1/1 and the wall HRP_001 1/1 effects on;
  - greyed medals Getaway 0/24 and Secret Hunter 0/29;
  - console clean.
  - Capture: [C1_stall_effects_play.jpg](captures/C1_stall_effects_play.jpg).

## C2/C3 — shot effects (new, shared, pooled)

`src/shared/Utility/WeaponFxLibrary.lua` builds the templates once in code into `ReplicatedStorage.CodeAssets.Effects` on the client: MuzzleFlash, ImpactBurst, BoltTrail (Trail + BoltCore Beam + 2 ghost Beams), SleepPuff. It clones 4 rigs of each onto Terrain attachments and reuses them round-robin. Bursts use `:Emit(n)`. **No instance is created per shot after warm-up**: tested over 25 shots, the Terrain descendant count is unchanged.

`SleepLauncherController` (flag-gated):

- the bolt halo and light take the tier colour;
- a muzzle flash fires when the shot is drawn;
- a pooled trail follows the bolt;
- on arrival, an impact burst, plus Zzz when the server result says `Slept`.

Tier ladder (`PlaytestFixes.WeaponFx.Tiers`). Each tier adds to the one before; counts are High.

| Tier | Colour | Fire | Bolt | Hit | Particles/shot High · Low |
|---|---|---|---|---|---|
| T1 | #E3EAF3 | flash + 3 sparks | 0.18 trail | 4 sparks + one Z | 9 · 5 |
| T2 | #72E65B | flash + 4 | 0.22 trail | 5 + one Z | 11 · 6 |
| T3 | #46A7FF | + expanding ring | 0.28 trail + sparkles | 6 + Zzz | 15 · 7 |
| T4 | #B86CFF | same | 0.32 | same | 15 · 7 |
| T5 | crimson #E3173E | + shockwave | Beam core | + ground ring | 16 · 8 |
| T6 | icy #6DEBFF | same | same | same | 16 · 8 |
| T7 | black, pale halo #E8E4FF | flash/ring/shockwave only (no smoke, no mist) | dark core + pale halo | black eclipse ring | 15 · 7 |
| T8 | rainbow | rainbow | rainbow Beam + 2 afterimage ghosts | + rift crack (implosion) | 16 · 6 |

- **Budget conflict in the prompt:** its per-effect caps (Muzzle 8, Impact 14, Puff 6) add up to 28, which is over its own 16-per-shot budget. The ladder stays inside **both** (tested). Low halves the bursts and drops the secondary ring, shockwave and crack, but keeps every beat (flash, hit, ground ring, one Z).
- **Captures** (Play, frozen with `TimeScale = 0`, on a dark backing plate):
  - [C2_shots_T1_T4.jpg](captures/C2_shots_T1_T4.jpg): white → green → blue → purple trails widening; one Z at T1–T2, Zzz at T3–T4.
  - [C2_shots_T5_T8.jpg](captures/C2_shots_T5_T8.jpg): crimson and icy cores, the dark core with pale halo, rainbow.

## C4 — empty weapons, signatures, T1 art

Authored on existing parts (config `WeaponFx.Authored`):

| Id | Effects | Signature |
|---|---|---|
| WPN_B06 / C06 / G06 | frost mist off FloatIce / FloatIceCore / CoreCrystalCore (Rate 4) + cyan sparkle (Rate 2) | — (T6) |
| Rift Blaster | rift tear at the muzzle (violet implosion, Rate 3) + violet sparks on RiftCore (Rate 4) | rift tear |
| Prism Repeater | spectrum split from the drum axle, a 6-particle rainbow burst on every 60° snap (`EmitOnFire`) | spectrum split |
| Crystal Lance | 4 orbiting Neon shards on a `CampAnimRotor` spun by WeaponArtController, plus a frost Trail on the tip | orbit shards |
| Collector's Bow | gold sparkle on the string (Rate 3) | gold sparkle |
| Getaway / Secret Hunter | as authored (24 / 29 effects) | as authored |
| T5 ladder (B05, C05, G05) | one slow tier-colour aura (Rate 3) | — |

- **WPN_C01 / WPN_G01** now have v2 art in the T1 Trailwood style of HRP_001: same palette, carved wood with tinted studs, a red mushroom sight, Neon vines, leaf emblems and a gold nock. The crossbow has 48 parts and the blaster 31. The muzzle moves to the new tip.
  - Capture: [C4_T1_trailwood_art.jpg](captures/C4_T1_trailwood_art.jpg). It is also live on the rack in [C1_stall_effects_play.jpg](captures/C1_stall_effects_play.jpg).
- **Captures:** [C4_specials_and_T6.jpg](captures/C4_specials_and_T6.jpg).

## C5 — budgets (held weapon: authored + added, enabled emitters / total Rate)

| Ids | Emitters / Rate | Budget | Result |
|---|---|---|---|
| T1–T4 ladder (12 ids incl. C01/G01) | 0 / 0 | 2 / 10 | ok |
| B05 · C05 · G05 | 1 / 3 each | 3 / 20 | ok |
| B06 · C06 · G06 | 2 / 6 each | 3 / 20 | ok |
| B07 · C07 · G07 (T7) | 7 / 14 each | as authored | ok |
| B08 · C08 · G08 | 4/12 · 3/9 · 3/9 | 6 / 40 | ok |
| Rift Blaster | 2 / 7 | 6 / 40 | ok |
| Prism Repeater | 1 / 0 (burst only) | 6 / 40 | ok |
| Crystal Lance | 0 emitters (orbit shards + trail) | 6 / 40 | ok |
| Collector's Bow | 1 / 3 | 6 / 40 | ok |
| Getaway | 0 enabled emitters (beams/lights) | 6 / 40 | ok |
| Secret Hunter | 2 / 6 | 6 / 40 | ok |

- **Low quality:** idle emitters on held weapons (tag `PlaytestIdleFx`) switch off (WeaponArtController), and stall particles are off. Burst counts halve, as in the table above.
- The **T3–T4 "soft glow strip"** uses the Neon accents the models already have; there is no new emitter, as the prompt asks.

## F1 — Gems stall concept (not placed)

- **Built:** `tools/playtest_fixes/BuildGemsStallConcept.edit.luau` creates `ServerStorage._ConceptBooth.Stalls.Kiosk_GemsStall`. It is cloned from the live Sell stall (the Sell/Training family: box counter, plank top, dark X-braced sides, sloping canopy with pointed flags, sign board).
- **Look:**
  - canopy and flags alternate purple #8A3DFF / cyan #2EE9FF;
  - purple counter with a cyan trim;
  - sign text "GEMS";
  - six jagged gem rocks on the counter (tilted shell, two-wedge ridge, chipped wedge, slim Neon sliver);
  - one sparkle (Rate 4);
  - the cores carry `GlowPulseHz = 0.5`, for the scheduler pulse wired at placement (CP-D).
- **Budget:** 79 parts, 1 emitter; decoration is `CanQuery = false`, with no shadows under 1 stud. No NPCs, no prices, no stickers.
- **Captures:** [F1_gems_concept_front.jpg](captures/F1_gems_concept_front.jpg), [F1_gems_concept_threequarter.jpg](captures/F1_gems_concept_threequarter.jpg).
- **Sign text in captures:** "GEMS" is set the same way as the live SELL sign, but Edit-mode captures do not render either sign's SurfaceGui text (the live SELL sign is also blank in a capture). **Check in Play that SELL/GEMS show in game.**

## Tests and lint

- `scripts/run-playtest-fixes-tests.sh`: **57/57 pass** (ConfigValidator 8, MapStudPolicy 5, StallDisplayPose 38, WeaponFxLibrary 6).
- New `WeaponFxLibrary.spec` covers the ladder within budgets on High and Low, beats on Low, tier colours and specials, authoring budgets for all 30 templates, idempotence, and no pool growth after warm-up.
- Selene: 0 errors on the changed files. Five warnings remain in `Phase13RuntimeService.lua` (shadowing, an unused `CommerceRules`), the same count as before my edits. StyLua clean. No Luau type checker is installed.

## Play run (1 of the 2 allowed)

- Isolated test profile `ptf20261113` (key `phase8_test_ptf20261113_player_10098729613` in `dev_v2`); flag preview via `ReplicatedStorage.PlaytestFixesV1Preview`. Both attributes were removed afterwards.
- **Not exercised end-to-end:** a real server-confirmed shot. The test profile only owns HRP_001 and the camp is a safe zone. The strips drive the same library functions the shot hook calls. The real-shot check is CP-D play check 2.

## Owner decisions

1. **VFX look:** approve the tier ladder (colours, sizes) and the specials' signatures.
2. **Gems stall look**, before placement in CP-D.
3. **WPN_C01 / WPN_G01 Trailwood art.** For it to also replace the art when the flag is off, it would need to go into `Weapons.rbxm` (owner export).
4. **Optional uploads:** a "Z" sprite (currently text) and a rift-crack decal (currently the engine implosion texture).
5. **Pool size:** 4 bolt rigs per client. With more than 4 bolts in flight at once, the oldest trail is cut short. 6 is cheap if you want it.

## Changed files (CP-B)

- **New:**
  - `src/shared/Utility/WeaponFxLibrary.lua`
  - `src/server/Tests/WeaponFxLibrary.spec.lua`
  - `src/assets/PlaytestArtV2/*`, `src/assets/PlaytestDisplaysV2/*`
  - `tools/playtest_fixes/build_t1_weapons.py`, `tools/playtest_fixes/BuildGemsStallConcept.edit.luau`
- **Edited:**
  - `Config/PlaytestFixes.lua` (WeaponFx section)
  - `SleepLauncherController.client.lua`, `WeaponArtController.lua`, `CampStallController.lua`
  - `Utility/CampAnimationScheduler.lua` (`hidden` callback)
  - `Services/Phase13RuntimeService.lua` (authoring + art override)
  - `scripts/studio-playtest-fixes-test-runner.luau`
- **Place (unsaved):** the Gems concept in `ServerStorage._ConceptBooth.Stalls`.
