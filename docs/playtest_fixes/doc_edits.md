# Proposed edits to the project docs (not applied)

These are proposals only. The project documents themselves were not edited (E6, F6).

## Brainrot_Creature_Design_Standard.md §3 (size)

**Replace** the single-height rule ("every brainrot is ≈6.7 studs tall, 1.3 × the reference body") **with:**

> **Size by rarity.** World, catch-reveal, Index-shot and front-team brainrots stand at their rarity height (× the 5.158-stud reference body):
>
> | Rarity | × body | ≈ studs |
> |---|---|---|
> | Common | 1.55 | 8.0 |
> | Uncommon | 1.65 | 8.5 |
> | Rare | 1.75 | 9.0 |
> | Epic | 1.90 | 9.8 |
> | Legendary | 2.05 | 10.6 |
> | Mythic | 2.20 | 11.4 |
> | Celestial | 2.30 | 11.9 |
> | Secret | 2.40 | 12.4 |
>
> **Base displays** use the same height, capped so the model fits 92% of the 10.2 × 13.9 slot, and never below 6.7.
>
> **Carried and cargo** brainrots stay at 6.7, so carts, doorways and cargo slots are unchanged.
>
> Design for the long-axis caps: a model longer than about 1.6 × its height on Z, or wider than about 1.2 × its height on X, displays smaller on bases (see `docs/playtest_fixes/size_ladder_fit.md`).

## V4 prompt §2.3

**Replace** "Target height ≈6.7 studs (1.3 × reference body)" **with:**

> "Author at the canonical 6.7-stud body (1.3 × reference). The game scales by role at runtime: rarity height in the world (8.0 Common … 12.4 Secret), slot-capped on bases, 6.7 when carried or in cargo. Keep long bodies within 1.6 × height in depth and 1.2 × height in width if they should show full-size on bases."

## Final_Decisions_Weapons_Stalls_Camp.md (F6)

**Replace** "four stalls plus the Announcements kiosk" **with:**

> "five stalls (Weapons, Carts, Sell, Training, Gems) plus a read-only NEWS board. Passes & Gems open from the Gems stall counter; the NEWS board has no prompt or window and shows the current update headline, one line and 'Codes → Settings'."
