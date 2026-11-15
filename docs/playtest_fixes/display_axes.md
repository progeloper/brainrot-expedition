# Weapon display axes — Playtest Fixes Part B

Measured 13 Nov 2026 from `ReplicatedStorage.CodeAssets.WeaponDisplays` in the DEV place (Play server, read-only), using `Shared.Utility.StallDisplayPose` and `Config.PlaytestFixes.StallPoses`.

**Size** is the display's bounding box in its own frame (X × Y × Z, studs). Displays are authored at exactly **1.5× held size**: HRP_001 measures 6.90 against 4.60 held, and the other weapons match.

- **Largest / smallest:** measured axes.
- **Along:** the model axis laid on the rail. Its negative end (the muzzle, prod or point) points to the customer's left.
- **Face:** the model axis pointing at the customer.
- **Up:** the remaining axis.

**Rack** = 8.2-stud rail. **Wall** = 4.7-stud rail. **FX** = authored ParticleEmitter + Beam + Trail + Light count.

Family rules (config):

- **Bow:** along = largest, face = smallest.
- **Gun:** along = largest, face = smallest.
- **Crossbow:** along = Z (the stock), face = X (the side). On 8 of 10 crossbows the prod span is the largest axis, so "largest" would put the prod on the rail.
- **Lance:** along = largest, face = X.

Crossbows lean back 25° around the rail.

Config overrides (no code branches):

| Id | Override | Why |
|---|---|---|
| WPN_B07 | face = X | moon ornaments make X (5.11) wider than the draw depth Z (4.78) |
| WPN_G07 | along = Z, face = X | the eclipse ring is taller (Y 6.37) than the barrel is long (Z 5.80) |
| WPN_SP_PRISMREPEATER | family Gun, face = X | the display says Crossbow, but the decisions doc poses it as a blaster; the drum is wider than it is tall |
| WPN_SP_CRYSTALLANCE | family Lance | the display says Crossbow |

| Id | Display family | Pose family | Size X × Y × Z | Largest | Smallest | Along | Face | Up | Rack | Wall | FX |
|---|---|---|---|---|---|---|---|---|---|---|---|
| HRP_001 | Bow | Bow | 0.59 × 6.90 × 3.15 | Y | X | Y | X | Z | 1.50× fits | 1.20× **over** | 1 |
| WPN_B02 | Bow | Bow | 0.64 × 6.90 × 3.16 | Y | X | Y | X | Z | 1.50× fits | 1.20× **over** | 1 |
| WPN_B03 | Bow | Bow | 0.86 × 6.90 × 4.06 | Y | X | Y | X | Z | 1.50× fits | 1.20× **over** | 1 |
| WPN_B04 | Bow | Bow | 1.39 × 6.90 × 4.09 | Y | X | Y | X | Z | 1.50× fits | 1.20× **over** | 5 |
| WPN_B05 | Bow | Bow | 0.85 × 6.71 × 4.43 | Y | X | Y | X | Z | 1.50× fits | 1.20× **over** | 4 |
| WPN_B06 | Bow | Bow | 2.84 × 6.96 × 4.13 | Y | X | Y | X | Z | 1.50× fits | 1.20× **over** | 0 |
| WPN_B07 | Bow | Bow | 5.11 × 7.33 × 4.78 | Y | Z | Y | X *(override)* | Z | 1.50× fits | 1.20× **over** | 7 |
| WPN_B08 | Bow | Bow | 0.89 × 7.48 × 3.73 | Y | X | Y | X | Z | 1.50× fits | 1.20× **over** | 44 |
| WPN_SP_COLLECTORSBOW | Bow | Bow | 1.06 × 7.59 × 4.92 | Y | X | Y | X | Z | 1.50× fits | 1.20× **over** | 0 |
| WPN_C01 | Crossbow | Crossbow | 5.40 × 2.82 × 3.97 | X | Y | Z | X | Y | 1.50× fits | 1.50× fits | 0 |
| WPN_C02 | Crossbow | Crossbow | 6.49 × 3.41 × 7.50 | Z | Y | Z | X | Y | 1.50× fits | 1.20× **over** | 5 |
| WPN_C03 | Crossbow | Crossbow | 5.29 × 2.99 × 7.50 | Z | Y | Z | X | Y | 1.50× fits | 1.20× **over** | 1 |
| WPN_C04 | Crossbow | Crossbow | 5.42 × 3.30 × 7.50 | Z | Y | Z | X | Y | 1.50× fits | 1.20× **over** | 2 |
| WPN_C05 | Crossbow | Crossbow | 7.53 × 4.61 × 6.47 | X | Y | Z | X | Y | 1.50× fits | 1.20× **over** | 2 |
| WPN_C06 | Crossbow | Crossbow | 7.38 × 5.63 × 6.00 | X | Y | Z | X | Y | 1.50× fits | 1.20× **over** | 0 |
| WPN_C07 | Crossbow | Crossbow | 7.50 × 5.29 × 5.34 | X | Y | Z | X | Y | 1.50× fits | 1.32× fits | 7 |
| WPN_C08 | Crossbow | Crossbow | 8.19 × 2.63 × 5.20 | X | Y | Z | X | Y | 1.50× fits | 1.36× fits | 49 |
| WPN_SP_GETAWAY | Crossbow | Crossbow | 7.63 × 5.40 × 8.26 | Z | Y | Z | X | Y | 1.50× fits | 1.20× **over** | 24 |
| WPN_SP_CRYSTALLANCE | Crossbow | Lance | 5.62 × 3.34 × 8.25 | Z | Y | Z | X | Y | 1.50× fits | 1.20× **over** | 0 |
| WPN_G01 | Gun | Gun | 1.35 × 2.54 × 3.73 | Z | X | Z | X | Y | 1.50× fits | 1.50× fits | 0 |
| WPN_G02 | Gun | Gun | 1.35 × 2.96 × 6.30 | Z | X | Z | X | Y | 1.50× fits | 1.20× **over** | 4 |
| WPN_G03 | Gun | Gun | 1.71 × 2.30 × 5.66 | Z | X | Z | X | Y | 1.50× fits | 1.25× fits | 1 |
| WPN_G04 | Gun | Gun | 2.62 × 2.68 × 6.31 | Z | X | Z | X | Y | 1.50× fits | 1.20× **over** | 3 |
| WPN_G05 | Gun | Gun | 3.50 × 4.20 × 6.15 | Z | X | Z | X | Y | 1.50× fits | 1.20× **over** | 1 |
| WPN_G06 | Gun | Gun | 3.79 × 6.11 × 6.20 | Z | X | Z | X | Y | 1.50× fits | 1.20× **over** | 0 |
| WPN_G07 | Gun | Gun | 5.87 × 6.37 × 5.80 | Y | Z | Z *(override)* | X *(override)* | Y | 1.50× fits | 1.22× fits | 7 |
| WPN_G08 | Gun | Gun | 2.11 × 5.50 × 6.93 | Z | X | Z | X | Y | 1.50× fits | 1.20× **over** | 72 |
| WPN_SP_RIFTBLASTER | Gun | Gun | 2.40 × 4.29 × 6.93 | Z | X | Z | X | Y | 1.50× fits | 1.20× **over** | 0 |
| WPN_SP_PRISMREPEATER | Crossbow | Gun *(override)* | 7.37 × 4.19 × 8.25 | Z | Y | Z | X *(override)* | Y | 1.50× fits | 1.20× **over** | 0 |
| WPN_SP_SECRETHUNTER | Gun | Gun | 1.53 × 4.89 × 6.92 | Z | X | Z | X | Y | 1.50× fits | 1.20× **over** | 29 |

## Fit findings and owner decisions (13 Nov)

The **Wall** column in the table above is the first pass, measured on 4.7-stud wall slots.

- **Racks: two weapons per board, a random few** (owner, 13 Nov).
  - Rows sit 2.8 and 6.2 studs above the stall pivot.
  - Each weapon stays within an 8.2-stud rail and a 3.4-stud row, scaled 1.5×, or smaller to fit but never below 1.2×.
  - The four rack weapons are drawn at random once per session from the unowned, priced pool.
  - Crossbows lean back 10° instead of 25°.
- **Wall: two weapons** (owner, 13 Nov). The two slots split the 14.3-stud pegboard, with 7.0 studs usable each.
  - All 30 displays fit: the longest (8.25–8.26 studs) go up at 1.27×, and everything up to 7.0 studs at 1.5×.
  - WallSlot_3 stays empty while the flag is on.
- **Flag off:** RackSlot_3, RackSlot_6 and WallSlot_3 keep their `LegacySlotCFrame`, so the game looks as before.
- **Tier size:** displays keep their authored relative sizes. Tier 8 reads as "bigger and busier" mainly through its 44–72 authored effects, which come back in Part C.
