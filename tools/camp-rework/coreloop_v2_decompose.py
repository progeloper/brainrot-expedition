#!/usr/bin/env python3
"""Core Loop V2 economy guard: where the speed-up comes from (free player, 80 s nominal).

Switches the V2 features off one at a time, cumulatively, starting from the full model:

    python3 -I tools/camp-rework/coreloop_v2_decompose.py [--runs=N] [--write]

--write saves docs/coreloop/2026-11/economy/decomposition.csv. Standard library only, fixed seeds.
"""
from __future__ import annotations

import csv
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coreloop_v2_sim as c  # noqa: E402
import economy_sim as es  # noqa: E402


def old_player_cell(runs, trip, fill):
    saved = es.CARGO_FILL
    es.CARGO_FILL = fill
    try:
        return [es.Player(random.Random(1 + i), training=False, pass2x=False, train_seconds=0,
                          level1_xp=60, growth=1.35, trip_seconds=trip, expansions=True).run()
                for i in range(runs)]
    finally:
        es.CARGO_FILL = saved


def main(argv):
    runs = next((int(a.split("=", 1)[1]) for a in argv if a.startswith("--runs=")), 400)
    rows = []

    def add(label, res):
        s = c.summarise(res)
        rows.append([label, round(s["Beach"]["p50"] / 60, 1), round(s["GlitchZone"]["p10"] / 3600, 3),
                     round(s["GlitchZone"]["p50"] / 3600, 3), round(s["GlitchZone"]["p90"] / 3600, 3)])
        print(f"| {label} | {c.mn(s['Beach']['p50'])} | {c.hm(s['GlitchZone']['p50'])} "
              f"({c.hm(s['GlitchZone']['p10'])}-{c.hm(s['GlitchZone']['p90'])}) |")

    print("| Step | Beach p50 | Glitch p50 (p10-p90) |\n|---|---:|---:|")
    add("Flag off: old model, 247 s eff. trip, 75% random cargo", old_player_cell(runs, c.CAL_TRIP_OLD, 0.75))
    add("Old model, trip shortened to 80 s nominal (132 s eff.)", old_player_cell(runs, 80 * c.OVERHEAD, 0.75))
    add("... and full cargo of random pool draws", old_player_cell(runs, 80 * c.OVERHEAD, 1.0))
    add("Full Core Loop V2 at 80 s", c.run_cell(runs=runs, v2=True))
    add("V2 at 150 s nominal (247 s eff., the old trip)", c.run_cell(runs=runs, v2=True, nominal_trip=150))
    saved = c.LUCKY_STAR_SECONDS
    c.LUCKY_STAR_SECONDS = 1e18
    add("V2 at 80 s without the 3.5-min Lucky Star", c.run_cell(runs=runs, v2=True))
    saved_rs, saved_mw = c.rush_state, c.mega_windows
    c.rush_state = lambda t, offset: ("Idle", None)
    c.mega_windows = lambda t0, t1, offset: iter(())
    add("... and without RUSH / MEGA (no MEGA Lucky Star, no Rain)", c.run_cell(runs=runs, v2=True))
    saved_p = (c.PITY_SUPER, c.PITY_JACKPOT, c.PITY_MUT)
    c.PITY_SUPER = c.PITY_JACKPOT = c.PITY_MUT = 1e18
    add("... and without pity (herds + Stars + loner only)", c.run_cell(runs=runs, v2=True))
    saved_d, saved_m = dict(c.STAR_DRAWS), dict(c.STAR_MUT_MULT)
    for k in c.STAR_DRAWS:
        c.STAR_DRAWS[k] = 1
        c.STAR_MUT_MULT[k] = 1
    add("... and Stars rolled as plain snacks (herd + loner, best-by-value cargo)", c.run_cell(runs=runs, v2=True))
    c.STAR_DRAWS.update(saved_d); c.STAR_MUT_MULT.update(saved_m)
    c.PITY_SUPER, c.PITY_JACKPOT, c.PITY_MUT = saved_p
    c.rush_state, c.mega_windows = saved_rs, saved_mw
    c.LUCKY_STAR_SECONDS = saved

    if "--write" in argv:
        repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        path = os.path.join(repo, "docs", "coreloop", "2026-11", "economy", "decomposition.csv")
        with open(path, "w", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["step", "beach_p50_min", "glitch_p10_h", "glitch_p50_h", "glitch_p90_h"])
            w.writerows(rows)
        print(f"wrote {path}", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1:])
