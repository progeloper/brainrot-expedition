# Size ladder fit report (E5)

Computed 13 Nov 2026 in the DEV place from the Voxel V4 measurements (`VoxelCreatureRegistry.Measure`), using `BrainrotVisualScale.LadderHeight` / `BaseHeight` with `Config.PlaytestFixes.SizeLadder`.

How the columns are worked out:

- **Ladder** = HeightByRarity × ReferenceBodyHeight (5.158).
- **Base display:** the ladder height, capped so the model fits 92% of the 10.2 × 13.9 slot (9.38 wide, 12.79 deep, model X across the slot and Z along it), and never below today's 6.706.
- **Wild W / D:** the brainrot's footprint at its ladder height.
- **Carried and cargo** stay at 6.706 for every species.

| Id | Brainrot | Rarity | Ladder | Base display | Cap | Wild W | Wild D |
|---|---|---|---:|---:|---|---:|---:|
| BRT_001 | Bingus Baguette | Common | 8.00 | 7.09 | depth | 4.2 | 14.4 |
| BRT_002 | Tralalero Toad | Common | 8.00 | 8.00 | — | 9.1 | 10.3 |
| BRT_003 | Cappuccino Capybara | Common | 8.00 | 8.00 | — | 3.2 | 9.5 |
| BRT_004 | Ballerina Banana | Common | 8.00 | 8.00 | — | 3.5 | 3.5 |
| BRT_005 | Bombardiro Pigeon | Common | 8.00 | 7.13 | width | 10.5 | 4.9 |
| BRT_006 | Spaghetti Crocodilo | Common | 8.00 | 6.71 | floor | 7.9 | 16.5 |
| BRT_007 | Tung Tung Tung Sahur | Common | 8.00 | 8.00 | — | 3.8 | 1.9 |
| BRT_008 | Lirili Larila | Common | 8.00 | 8.00 | — | 5.5 | 3.8 |
| BRT_009 | Chimpanzini Bananini | Common | 8.00 | 8.00 | — | 5.7 | 3.3 |
| BRT_010 | Talpa Di Fero | Common | 8.00 | 8.00 | — | 6.7 | 7.1 |
| BRT_011 | Glorbo Fruttodrillo | Uncommon | 8.51 | 6.71 | floor | 7.2 | 17.1 |
| BRT_012 | Frigo Camelo | Uncommon | 8.51 | 8.51 | — | 2.7 | 7.5 |
| BRT_013 | Cavallo Virtuoso | Uncommon | 8.51 | 8.51 | — | 3.4 | 6.1 |
| BRT_014 | Bandito Bobritto | Uncommon | 8.51 | 8.51 | — | 4.7 | 5.7 |
| BRT_015 | Strawberelli Flamingelli | Uncommon | 8.51 | 8.51 | — | 4.1 | 4.9 |
| BRT_016 | Gorillo Subwoofero | Uncommon | 8.51 | 8.51 | — | 7.6 | 4.1 |
| BRT_017 | Orangutini Ananassini | Uncommon | 8.51 | 8.51 | — | 4.6 | 3.5 |
| BRT_018 | Zibra Zubra Zibralini | Uncommon | 8.51 | 8.51 | — | 2.9 | 7.7 |
| BRT_019 | Trenostruzzo Turbo 3000 | Rare | 9.03 | 8.93 | depth | 3.5 | 12.9 |
| BRT_020 | Bisonte Giuppitere | Rare | 9.03 | 9.03 | — | 7.6 | 8.7 |
| BRT_021 | Cacto Hipopotamo | Rare | 9.03 | 9.03 | — | 3.2 | 4.5 |
| BRT_022 | Trulimero Trulicina | Rare | 9.03 | 9.03 | — | 5.4 | 12.2 |
| BRT_023 | Giraffa Celeste | Rare | 9.03 | 9.03 | — | 5.2 | 3.4 |
| BRT_024 | Nooo My Hotspot | Rare | 9.03 | 9.03 | — | 3.7 | 3.8 |
| BRT_025 | Salamino Penguino | Rare | 9.03 | 9.03 | — | 6.1 | 5.2 |
| BRT_026 | Rhino Toasterino | Epic | 9.80 | 9.80 | — | 5.1 | 6.8 |
| BRT_027 | Tralalero Tralala | Epic | 9.80 | 8.54 | depth | 5.2 | 14.7 |
| BRT_028 | Tartaragno | Epic | 9.80 | 7.77 | width | **11.8** | 12.6 |
| BRT_029 | Cocofanto Elefanto | Epic | 9.80 | 9.80 | — | 7.9 | 8.0 |
| BRT_030 | Tractoro Dinosauro | Epic | 9.80 | 9.80 | — | 6.9 | 12.7 |
| BRT_031 | Odin Din Din Dun | Legendary | 10.57 | 8.58 | width | **11.6** | 5.7 |
| BRT_032 | La Vaca Saturno Saturnita | Legendary | 10.57 | 9.24 | width | 10.7 | 10.7 |
| BRT_033 | Dragon Cannelloni | Legendary | 10.57 | 8.97 | width | 11.1 | 9.5 |
| BRT_034 | Orcalero Orcala | Mythic | 11.35 | 9.65 | depth | 5.3 | 15.0 |
| BRT_035 | La Secret Combinasion | Secret | 12.38 | 12.38 | — | 6.3 | 5.1 |

## Against the prompt's expected caps

| Species | Expected | Computed |
|---|---|---|
| BRT_001 | ~7.2 | 7.09 (depth) |
| BRT_006, BRT_011 | 6.7 floor | 6.71 floor |
| BRT_027 | ~8.7 | 8.54 (depth) |
| BRT_028 | ~8.0 | 7.77 (width) |
| BRT_032 | ~9.4 | 9.24 (width) |
| BRT_034 | ~9.8 | 9.65 (depth) |

All are within about 0.25 studs; the prompt's figures were estimates.

## Route and village fit (flags)

- **Width:** every species is narrower than the 12-stud village alleys at ladder size. **BRT_028 (11.8) and BRT_031 (11.6) leave almost no room**, and wild brainrots walk with their width across the alley.
- **Height:** village doorways are ≥ 10 studs tall. **Every Legendary (10.6), Mythic (11.4) and Secret (12.4) is taller than that**, so any route that sends wild brainrots through a doorway will clip or stall them.
  - Brainrots in the cart or carried stay at 6.7, so hauling through villages is unaffected.
  - Owner choice: cap the wild height at about 9.8 inside village footprints, or accept the clipping.
- **Spawning:** placement checks use the ladder envelope (RegionSpawnCatalog), so a spot that is too small for a big brainrot is refused, as it is today for any blocked spot.
- **Diagonal placement on base slots** (owner decision E5, default no): not implemented. With it, the six width/depth-capped species could use about 17 studs along the diagonal.
