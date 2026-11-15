#!/usr/bin/env python3
"""Core Loop V2 economy guard (spec C4). Driven by `economy_sim.py --core-loop-v2`.

Extends the calibrated free-player model in economy_sim.py (effective trip 247 s for a nominal
150 s trip, i.e. overhead x247/150) with herds, Stars, Lucky Stars, pity, BRAINROT RUSH / MEGA
RUSH and Mutation Rain, transcribed from src/shared/Config/CoreLoop.lua and
src/shared/CoreLoop/{HerdComposer,MutationRoller,StarGrade,PoolData,RushClock}.lua.

Standard library only. Deterministic (fixed seeds). Writes CSV/JSON/Markdown tables to
docs/coreloop/2026-11/economy/ when --write is passed.
"""
from __future__ import annotations

import contextlib
import csv
import json
import math
import os
import random
import statistics
import sys
import time

import economy_sim as es

# --------------------------------------------------------------------------------------
# CoreLoop.lua numbers (transcribed)
# --------------------------------------------------------------------------------------
CAL_TRIP_OLD = 247.0                 # economy_sim calibrate() result (reproduced, see report)
NOMINAL_OLD = es.TRIP_SECONDS        # 150 s
OVERHEAD = CAL_TRIP_OLD / NOMINAL_OLD  # 1.6467
NOMINAL_V2 = 80.0
TRIP_SENSITIVITY = [20.0, 40.0, 60.0, 80.0, 100.0, 120.0]
HUNT_SHARE = 0.60                    # share of a trip that is hunting (pity clocks, rush exposure)
HUNT_WINDOW = (0.20, 0.80)           # hunting interval inside a trip (drive out 20%, back 20%)

WILD_SIZES = {3: 0.30, 4: 0.45, 5: 0.25}
VILLAGE_SIZES = {4: 0.35, 5: 0.40, 6: 0.25}
VILLAGE_CHANCE = 0.5
STAR_DRAWS = {("Wild", "Idle"): 2, ("Village", "Idle"): 3, ("Wild", "Rush"): 3,
              ("Village", "Rush"): 4, ("Wild", "Mega"): 4, ("Village", "Mega"): 5}
STAR_MUT_MULT = {("Wild", "Idle"): 2, ("Village", "Idle"): 3, ("Wild", "Rush"): 3,
                 ("Village", "Rush"): 4, ("Wild", "Mega"): 4, ("Village", "Mega"): 5}
SNACK_MUT_MULT = {"Idle": 1.0, "Rush": 1.5, "Mega": 2.0}
MUT_BASE, MUT_CAP = 0.04, 0.30
MEGA_RARE_SHARE_MULT = 2.0
SUPER_MULTIPLE, JACKPOT_MULTIPLE = 2.9, 7.0
LUCKY_REROLL_CAP, JACKPOT_REROLL_CAP = 500, 5000
LONERS = {"Idle": 1, "Rush": 3, "Mega": 3}   # prompt: 1 per trip; CoreLoop.Loners.RushPerHunter = 3
LUCKY_STAR_SECONDS = 210.0           # prompt: one Lucky Star every 3.5 min
PITY_SUPER, PITY_JACKPOT, PITY_MUT = 300.0, 900.0, 180.0
PITY_MUT_SHARES = [("Shiny", 0.7), ("Golden", 0.3)]
RUSH_CYCLE, RUSH_LEN, MEGA_EVERY, MEGA_LEN = 300.0, 60.0, 3, 90.0
MEGA_LUCKY_MIN = 30.0
RAIN_SHARES = [("Shiny", 0.80), ("Golden", 0.18), ("Glitched", 0.02)]
RAIN_EVERY_NTH_MEGA = 1

MUT_MULT = {name: mult for name, mult, _ in es.MUTATIONS}
MUT_MULT["None"] = 1.0
RUNS = 400
PROFILES = ["free", "pass", "vip_pass_boost"]
PROFILE_LABEL = {"free": "Free", "pass": "2x pass", "vip_pass_boost": "VIP + 2x pass + boost"}
VIP_BONUS = 0.15      # Economy.Income.VipBonus (additive with rebirth bonus)
CASH_BOOST = 2.0      # Economy.Income.CashBoost


def mutation_shares(mega: bool):
    rows = []
    for name, _, share in es.MUTATIONS:
        if mega and name in ("Radioactive", "Astral"):
            share *= MEGA_RARE_SHARE_MULT
        rows.append((name, share))
    tot = sum(s for _, s in rows)
    return [(n, s / tot) for n, s in rows]


SHARES = {False: mutation_shares(False), True: mutation_shares(True)}


def pick(rng, rows):
    roll, acc = rng.random(), 0.0
    for name, share in rows:
        acc += share
        if roll < acc:
            return name
    return rows[-1][0]


def tier_weight(region, tier):
    weights, species = es.POOLS[region]
    if not species.get(tier):
        return 0.0
    return weights[es.TIERS.index(tier)]


def species_rows(region, tier):
    pool = es.POOLS[region][1].get(tier, [])
    ov = es.SPECIES_WEIGHT_OVERRIDES.get(region, {})
    tot = sum(ov.get(s, 1) for s in pool)
    return [(s, ov.get(s, 1) / tot) for s in pool]


REGIONS = list(es.POOLS)
SPECIES_ROWS = {(r, t): species_rows(r, t) for r in REGIONS for t in es.TIERS}
TIER_ROWS = {r: [(t, tier_weight(r, t)) for t in es.TIERS if tier_weight(r, t) > 0] for r in REGIONS}
CPS_WB = {k: v[1] for k, v in es.CATALOG_CPS.items()}   # workbook units (StarGrade.Value)
REGION_MEAN = {r: sum(p * sh * CPS_WB[s] for t, p in TIER_ROWS[r] for s, sh in SPECIES_ROWS[(r, t)])
               for r in REGIONS}
TOP_TIER = {r: TIER_ROWS[r][-1][0] for r in REGIONS}
GRADE_RANK = {"Star": 1, "Super": 2, "Jackpot": 3}


def grade(region, sid, mut):
    ratio = CPS_WB[sid] * MUT_MULT[mut] / REGION_MEAN[region]
    if ratio >= JACKPOT_MULTIPLE:
        return "Jackpot"
    if ratio >= SUPER_MULTIPLE:
        return "Super"
    return "Star"


def rush_state(t, offset):
    """RushClock.At: (state, mega_index or None, window_start, window_end)."""
    e = t + offset
    idx = int(e // RUSH_CYCLE)
    end = (idx + 1) * RUSH_CYCLE
    mega = (idx + 1) % MEGA_EVERY == 0
    start = end - (MEGA_LEN if mega else RUSH_LEN)
    if e >= start:
        return ("Mega" if mega else "Rush"), ((idx + 1) // MEGA_EVERY if mega else None)
    return "Idle", None


def mega_windows(t0, t1, offset):
    """Yield (mega_index, start, end) in session time for every MEGA window overlapping [t0, t1]."""
    e0, e1 = t0 + offset, t1 + offset
    k = max(1, int(e0 // (RUSH_CYCLE * MEGA_EVERY)))
    while True:
        end = k * RUSH_CYCLE * MEGA_EVERY
        start = end - MEGA_LEN
        if start > e1:
            break
        if end >= e0:
            yield k, start - offset, end - offset
        k += 1


class V2Player(es.Player):
    """Speed-upgrade baseline player (training off) with Core Loop V2 hunting when v2=True."""

    def __init__(self, rng, *, profile="free", v2=True, nominal_trip=NOMINAL_V2,
                 rain_every=RAIN_EVERY_NTH_MEGA, rain_target="random", flag_off_trip=CAL_TRIP_OLD,
                 loners_idle=None, cargo_fill=None):
        trip = nominal_trip * OVERHEAD if v2 else flag_off_trip
        super().__init__(rng, training=False, pass2x=profile != "free", train_seconds=0,
                         level1_xp=60, growth=1.35, trip_seconds=trip, expansions=True)
        self.v2 = v2
        self.vip = profile == "vip_pass_boost"
        self.boost = profile == "vip_pass_boost"
        self.rain_every = rain_every
        self.rain_target = rain_target
        self.loners_idle = LONERS["Idle"] if loners_idle is None else loners_idle
        self.cargo_fill = cargo_fill   # None = full cargo (prompt); 0.75 = old model's fill
        self.slot_mut: list[str] = []
        self.slot_sid: list[str] = []
        # Player joins at a random RUSH clock phase (drawn only in v2 so flag-off seeds match economy_sim).
        self.offset = rng.random() * RUSH_CYCLE * MEGA_EVERY if v2 else 0.0
        self.lucky_acc = 0.0
        self.pending_lucky = 0
        self.mega_hunt: dict[int, float] = {}
        self.mega_lucky_given: set[int] = set()
        self.rain_done: set[int] = set()
        self.pity = {"super": 0.0, "jackpot": 0.0, "mut": 0.0}
        self.stats = {"trips": 0, "loaded": 0, "Super": 0, "Jackpot": 0, "lucky": 0, "mega_lucky": 0,
                      "pity_super": 0, "pity_jackpot": 0, "pity_mut": 0, "fallback": 0,
                      "rain": 0, "rain_noop": 0, "mutated_loaded": 0, "rush_trips": 0, "mega_trips": 0}

    # --- income -------------------------------------------------------------------
    def income(self):
        mult = 1 + es.REBIRTH_BONUS * self.rebirths + (VIP_BONUS if self.vip else 0.0)
        return sum(self.slots) * mult * self.income_mult_pass * (CASH_BOOST if self.boost else 1.0)

    # --- banking keeps species + mutation per slot (for Mutation Rain) -------------
    def bank_v2(self, sid, mut):
        self.banked_species.setdefault(sid, es.RANK[es.RARITY[sid]])
        m = MUT_MULT[mut]
        inc, sell = es.CPS[sid] * m, es.SELL[sid] * m
        if len(self.slots) < self.capacity:
            self.slots.append(inc); self.slot_sell.append(sell)
            self.slot_mut.append(mut); self.slot_sid.append(sid)
            return
        worst = min(range(len(self.slots)), key=lambda i: self.slots[i])
        if inc > self.slots[worst]:
            self.cash += self.slot_sell[worst]
            self.slots[worst], self.slot_sell[worst] = inc, sell
            self.slot_mut[worst], self.slot_sid[worst] = mut, sid
        else:
            self.cash += sell

    # --- herd composition (HerdComposer.lua) --------------------------------------
    def draw_tier(self, region):
        return pick(self.rng, TIER_ROWS[region])

    def pick_species(self, region, tier):
        return pick(self.rng, SPECIES_ROWS[(region, tier)])

    def roll_mut(self, chance, mega):
        if chance <= 0 or self.rng.random() >= chance:
            return "None"
        return pick(self.rng, SHARES[mega])

    def roll_star(self, region, kind, rush):
        best = None
        for _ in range(STAR_DRAWS[(kind, rush)]):
            t = self.draw_tier(region)
            if best is None or es.RANK[t] > es.RANK[best]:
                best = t
        sid = self.pick_species(region, best)
        chance = min(MUT_CAP, MUT_BASE * STAR_MUT_MULT[(kind, rush)])
        return sid, self.roll_mut(chance, rush == "Mega")

    def compose_star(self, region, kind, rush, minimum):
        if not minimum:
            return self.roll_star(region, kind, rush)
        cap = JACKPOT_REROLL_CAP if minimum == "Jackpot" else LUCKY_REROLL_CAP
        need = GRADE_RANK[minimum]
        for _ in range(cap):
            sid, mut = self.roll_star(region, kind, rush)
            if GRADE_RANK[grade(region, sid, mut)] >= need:
                return sid, mut
        self.stats["fallback"] += 1
        return self.pick_species(region, TOP_TIER[region]), ("Radioactive" if minimum == "Jackpot" else "Golden")

    def roll_snack(self, region, rush):
        sid = self.pick_species(region, self.draw_tier(region))
        chance = min(MUT_CAP, MUT_BASE * SNACK_MUT_MULT[rush])
        return sid, self.roll_mut(chance, rush == "Mega")

    # --- one trip -----------------------------------------------------------------
    def v2_trip(self, region, dur):
        t0 = self.t
        h0, h1 = t0 + HUNT_WINDOW[0] * dur, t0 + HUNT_WINDOW[1] * dur
        hunt = h1 - h0
        rush, _ = rush_state(self.rng.uniform(h0, h1), self.offset)
        self.stats["rush_trips"] += rush == "Rush"
        self.stats["mega_trips"] += rush == "Mega"

        # Lucky Star: one every 3.5 min of session time, plus MEGA grants queued from earlier trips.
        self.lucky_acc += dur / LUCKY_STAR_SECONDS
        if self.lucky_acc >= 1.0:
            self.lucky_acc -= 1.0
            self.pending_lucky += 1
        minimum = None
        forced_by = None
        if self.pity["jackpot"] + hunt >= PITY_JACKPOT:
            minimum, forced_by = "Jackpot", "pity_jackpot"
        elif self.pending_lucky > 0:
            minimum, forced_by = "Super", "lucky"
            self.pending_lucky -= 1
        elif self.pity["super"] + hunt >= PITY_SUPER:
            minimum, forced_by = "Super", "pity_super"
        if forced_by:
            self.stats[forced_by] += 1

        kind = "Village" if self.rng.random() < VILLAGE_CHANCE else "Wild"
        size = pick(self.rng, [(k, v) for k, v in (VILLAGE_SIZES if kind == "Village" else WILD_SIZES).items()])
        star = self.compose_star(region, kind, rush, minimum)
        members = [star] + [self.roll_snack(region, rush) for _ in range(size - 1)]
        mut_pity = self.pity["mut"] + hunt >= PITY_MUT and not any(m != "None" for _, m in members)
        loners = [self.roll_snack(region, rush) for _ in range(LONERS[rush] if rush != "Idle" else self.loners_idle)]
        if mut_pity and not any(m != "None" for _, m in loners):
            members[1] = (members[1][0], pick(self.rng, PITY_MUT_SHARES))
            self.stats["pity_mut"] += 1

        g = grade(region, *star)
        if g in ("Super", "Jackpot"):
            self.stats[g] += 1
        # Pity clocks (hunting seconds).
        self.pity["super"] = 0.0 if GRADE_RANK[g] >= 2 else self.pity["super"] + hunt
        self.pity["jackpot"] = 0.0 if g == "Jackpot" else self.pity["jackpot"] + hunt
        spawned = members + loners
        self.pity["mut"] = 0.0 if any(m != "None" for _, m in spawned) else self.pity["mut"] + hunt

        # MEGA: >= 30 s hunting inside a MEGA earns one Lucky Star (applied to the next herd).
        for k, ws, we in mega_windows(h0, h1, self.offset):
            ov = max(0.0, min(h1, we) - max(h0, ws))
            self.mega_hunt[k] = self.mega_hunt.get(k, 0.0) + ov
            if self.mega_hunt[k] >= MEGA_LUCKY_MIN and k not in self.mega_lucky_given:
                self.mega_lucky_given.add(k)
                self.pending_lucky += 1
                self.stats["mega_lucky"] += 1

        cap = es.BASE_CARGO + self.cargo_level
        if self.cargo_fill is not None:
            exp = self.cargo_fill * cap
            cap = int(exp) + (1 if self.rng.random() < exp - int(exp) else 0)
        loaded = sorted(spawned, key=lambda x: es.CPS[x[0]] * MUT_MULT[x[1]], reverse=True)[:cap]
        self.stats["trips"] += 1
        self.stats["loaded"] += len(loaded)
        self.stats["mutated_loaded"] += sum(1 for _, m in loaded if m != "None")
        return loaded

    def mutation_rain(self, t0, t1):
        for k, ws, _ in mega_windows(t0, t1, self.offset):
            if ws < t0 or ws > t1 or k in self.rain_done:
                continue
            self.rain_done.add(k)
            if k % self.rain_every != 0:
                continue
            cands = [i for i, m in enumerate(self.slot_mut) if m == "None"]
            if not cands:
                self.stats["rain_noop"] += 1
                continue
            if self.rain_target == "best":
                i = max(cands, key=lambda j: self.slots[j])
            else:
                i = self.rng.choice(cands)
            mut = pick(self.rng, RAIN_SHARES)
            sid = self.slot_sid[i]
            self.slot_mut[i] = mut
            self.slots[i] = es.CPS[sid] * MUT_MULT[mut]
            self.slot_sell[i] = es.SELL[sid] * MUT_MULT[mut]
            self.stats["rain"] += 1

    def run(self):
        if not self.v2:
            return super().run()
        while "GlitchZone" not in self.gate_times and self.t < es.HORIZON:
            region = self.unlocked[-1]
            dur = self.trip_duration()
            t0 = self.t
            loaded = self.v2_trip(region, dur)
            self.advance(dur)
            for sid, mut in loaded:
                self.bank_v2(sid, mut)
            self.mutation_rain(t0, self.t)
            self.shop()
        return self


# --------------------------------------------------------------------------------------
# Running scenarios
# --------------------------------------------------------------------------------------
GATE_KEYS = es.GATE_KEYS


@contextlib.contextmanager
def price_factor(f):
    saved = (es.GATES, es.SPEED_PRICES, es.CARGO_PRICES, es.EXPANSIONS)
    es.GATES = [(k, p * f, a, b) for k, p, a, b in saved[0]]
    es.SPEED_PRICES = [p * f for p in saved[1]]
    es.CARGO_PRICES = [p * f for p in saved[2]]
    es.EXPANSIONS = [p * f for p in saved[3]]
    try:
        yield
    finally:
        es.GATES, es.SPEED_PRICES, es.CARGO_PRICES, es.EXPANSIONS = saved


def run_cell(runs=RUNS, seed0=1, factor=1.0, **kw):
    with price_factor(factor):
        res = [V2Player(random.Random(seed0 + i), **kw).run() for i in range(runs)]
    return res


def q(results, key, p):
    vals = sorted(r.gate_times.get(key, math.inf) for r in results)
    if p == 0.5:
        return statistics.median(vals)
    return vals[min(len(vals) - 1, int(p * len(vals)))]


def summarise(results):
    out = {}
    for key in GATE_KEYS:
        out[key] = {"p10": q(results, key, .1), "p50": q(results, key, .5), "p90": q(results, key, .9),
                    "reached": sum(1 for r in results if key in r.gate_times)}
    return out


def diag(results):
    if not hasattr(results[0], "stats"):
        return {}
    tot = {k: sum(r.stats[k] for r in results) for k in results[0].stats}
    trips = max(1, tot["trips"])
    hours = sum(r.t for r in results) / 3600
    return {"trips_per_run": tot["trips"] / len(results),
            "loaded_per_trip": tot["loaded"] / trips,
            "super_per_hour": tot["Super"] / hours, "jackpot_per_hour": tot["Jackpot"] / hours,
            "lucky_per_hour": tot["lucky"] / hours, "mega_lucky_per_hour": tot["mega_lucky"] / hours,
            "pity_super_per_hour": tot["pity_super"] / hours,
            "pity_jackpot_per_hour": tot["pity_jackpot"] / hours,
            "pity_mut_per_hour": tot["pity_mut"] / hours,
            "mutated_loaded_share": tot["mutated_loaded"] / max(1, tot["loaded"]),
            "rain_strikes_per_run": tot["rain"] / len(results),
            "rain_noop_per_run": tot["rain_noop"] / len(results),
            "reroll_fallbacks": tot["fallback"],
            "rush_trip_share": tot["rush_trips"] / trips, "mega_trip_share": tot["mega_trips"] / trips}


def hm(s):
    return "n/a" if math.isinf(s) else f"{s / 3600:.2f} h"


def mn(s):
    return "n/a" if math.isinf(s) else f"{s / 60:.0f} min"


def solve_factor(target, runs, **kw):
    """Bisection on the global Cash price factor so the p50 free -> Glitch equals `target`."""
    lo, hi = 1.0, 2.0
    hist = []
    while q(run_cell(runs=runs, factor=hi, **kw), "GlitchZone", .5) < target:
        hist.append((hi, None))
        lo, hi = hi, hi * 2
    for _ in range(12):
        mid = (lo + hi) / 2
        g = q(run_cell(runs=runs, factor=mid, **kw), "GlitchZone", .5)
        hist.append((mid, g))
        if g < target:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2, hist


def main(argv):
    started = time.time()
    write = "--write" in argv
    runs = RUNS
    for a in argv:
        if a.startswith("--runs="):
            runs = int(a.split("=", 1)[1])
    cells = []   # rows for CSV
    blob = {"meta": {"runs_per_cell": runs, "overhead": OVERHEAD, "cal_trip_old": CAL_TRIP_OLD,
                     "region_mean_workbook_cps": REGION_MEAN,
                     "super_threshold": {r: REGION_MEAN[r] * SUPER_MULTIPLE for r in REGIONS},
                     "jackpot_threshold": {r: REGION_MEAN[r] * JACKPOT_MULTIPLE for r in REGIONS}},
            "cells": []}

    def record(name, profile, flag, nominal, lever, results, extra=None):
        s = summarise(results)
        d = diag(results)
        blob["cells"].append({"scenario": name, "profile": profile, "flag": flag, "nominal_trip": nominal,
                              "lever": lever, "gates": s, "diagnostics": d, **(extra or {})})
        for key in GATE_KEYS:
            cells.append([name, profile, flag, nominal, lever, key, round(s[key]["p10"], 1),
                          round(s[key]["p50"], 1), round(s[key]["p90"], 1), s[key]["reached"], runs])
        print(f"  [{time.time() - started:6.0f}s] {name:<36} {profile:<15} glitch p50 {hm(s['GlitchZone']['p50'])}",
              file=sys.stderr)
        return s

    S = {}
    # Flag off: the existing calibrated model (247 s effective trip, 75% cargo fill, random catches).
    for prof in PROFILES:
        S[("off", prof, None)] = record("flag_off", prof, "off", 150, "none",
                                        run_cell(runs=runs, profile=prof, v2=False))
    # Flag on at each nominal trip length.
    for nom in TRIP_SENSITIVITY:
        for prof in PROFILES:
            S[("on", prof, nom)] = record(f"flag_on_{nom:.0f}s", prof, "on", nom, "none",
                                          run_cell(runs=runs, profile=prof, v2=True, nominal_trip=nom))
    # Assumption sensitivities (80 s, free).
    sens = {}
    sens["loners2"] = record("sens_2_loners_idle", "free", "on", 80, "none",
                             run_cell(runs=runs, v2=True, loners_idle=2))
    sens["rain_best"] = record("sens_rain_best_slot", "free", "on", 80, "none",
                               run_cell(runs=runs, v2=True, rain_target="best"))
    sens["fill75"] = record("sens_cargo_fill_75", "free", "on", 80, "none",
                            run_cell(runs=runs, v2=True, cargo_fill=0.75))
    sens["no_rain"] = record("sens_no_rain", "free", "on", 80, "none",
                             run_cell(runs=runs, v2=True, rain_every=10 ** 9))

    # Levers, evaluated at each trip length that is faster than the band.
    target = 4.29 * 3600
    band = (3.9 * 3600, 4.7 * 3600)
    levers = {}
    for nom in TRIP_SENSITIVITY:
        base = S[("on", "free", nom)]["GlitchZone"]["p50"]
        if base >= band[0]:
            continue
        a = record(f"lever_a_{nom:.0f}s", "free", "on", nom, "rain_every_2nd_mega",
                   run_cell(runs=runs, v2=True, nominal_trip=nom, rain_every=2))
        entry = {"a": a}
        if a["GlitchZone"]["p50"] < band[0]:
            f, hist = solve_factor(target, runs=200, v2=True, nominal_trip=nom, rain_every=2)
            f = round(f, 3)
            b_res = {prof: record(f"lever_b_{nom:.0f}s", prof, "on", nom, f"rain2+price_x{f}",
                                  run_cell(runs=runs, factor=f, profile=prof, v2=True, nominal_trip=nom,
                                           rain_every=2)) for prof in PROFILES}
            entry.update(factor=f, factor_hist=hist, b=b_res)
        levers[nom] = entry
        blob.setdefault("levers", {})[str(nom)] = {"factor": entry.get("factor"),
                                                    "factor_bisection": entry.get("factor_hist")}

    # ------------------------------------------------------------------------------
    # Markdown tables
    # ------------------------------------------------------------------------------
    md = []
    p = md.append
    p(f"Generated by `python3 -I tools/camp-rework/economy_sim.py --core-loop-v2 --write` "
      f"({runs} runs per cell, fixed seeds).\n")
    p("### Region means and grade thresholds (workbook CPS units)\n")
    p("| Region | Mean (Normal spawn) | Super >= 2.9x | Jackpot >= 7.0x |")
    p("|---|---:|---:|---:|")
    for r in REGIONS:
        p(f"| {r} | {REGION_MEAN[r]:.2f} | {REGION_MEAN[r] * SUPER_MULTIPLE:.1f} | {REGION_MEAN[r] * JACKPOT_MULTIPLE:.1f} |")
    p("")

    def gate_table(title, rows):
        p(f"### {title}\n")
        p("| Scenario | " + " | ".join(GATE_KEYS) + " |")
        p("|---|" + "---:|" * len(GATE_KEYS))
        for label, s in rows:
            cells_ = []
            for key in GATE_KEYS:
                v = s[key]
                f = hm if key in ("Volcano", "GlitchZone", "Arctic") else mn
                cells_.append(f"{f(v['p50'])} ({f(v['p10'])}-{f(v['p90'])})")
            p(f"| {label} | " + " | ".join(cells_) + " |")
        p("")

    for prof in PROFILES:
        rows = [("Flag off (247 s eff.)", S[("off", prof, None)])]
        rows += [(f"Flag on, {nom:.0f} s nominal ({nom * OVERHEAD:.0f} s eff.)", S[("on", prof, nom)])
                 for nom in TRIP_SENSITIVITY]
        gate_table(f"{PROFILE_LABEL[prof]}: p50 (p10-p90) time to each region", rows)

    p("### Free player summary vs targets\n")
    p("| Scenario | Beach p50 | Glitch p10 | Glitch p50 | Glitch p90 | Glitch in 3.9-4.7 h? | Beach in 13-25 min? |")
    p("|---|---:|---:|---:|---:|---|---|")
    for label, s in [("Flag off", S[("off", "free", None)])] + \
            [(f"Flag on {nom:.0f} s", S[("on", "free", nom)]) for nom in TRIP_SENSITIVITY]:
        g, b = s["GlitchZone"], s["Beach"]
        p(f"| {label} | {mn(b['p50'])} | {hm(g['p10'])} | {hm(g['p50'])} | {hm(g['p90'])} | "
          f"{'yes' if band[0] <= g['p50'] <= band[1] else ('FASTER' if g['p50'] < band[0] else 'slower')} | "
          f"{'yes' if 13 * 60 <= b['p50'] <= 25 * 60 else ('faster' if b['p50'] < 13 * 60 else 'slower')} |")
    p("")

    p("### Assumption sensitivities (free, 80 s nominal)\n")
    p("| Variant | Beach p50 | Glitch p50 (p10-p90) |")
    p("|---|---:|---:|")
    base80 = S[("on", "free", 80.0)]
    for label, s in [("As modelled (1 idle loner, random Rain target, Rain every MEGA)", base80),
                     ("2 idle loners (CoreLoop.Loners.PerHunter = 2)", sens["loners2"]),
                     ("Rain hits the best unmutated slot", sens["rain_best"]),
                     ("No Mutation Rain", sens["no_rain"]),
                     ("Cargo filled to 75% of capacity (old model's fill), best by value", sens["fill75"])]:
        g = s["GlitchZone"]
        p(f"| {label} | {mn(s['Beach']['p50'])} | {hm(g['p50'])} ({hm(g['p10'])}-{hm(g['p90'])}) |")
    p("")

    if levers:
        p("### Levers (free player; applied in order, evaluated only, not applied to game code)\n")
        p("| Nominal trip | Flag on p50 | (a) Rain every 2nd MEGA p50 | (b) price factor | (a)+(b) free p50 (p10-p90) | (a)+(b) Beach p50 | (a)+(b) 2x pass p50 | (a)+(b) VIP+pass+boost p50 |")
        p("|---|---:|---:|---:|---:|---:|---:|---:|")
        for nom, e in levers.items():
            base = S[("on", "free", nom)]["GlitchZone"]["p50"]
            a = e["a"]["GlitchZone"]
            if "b" in e:
                bf, bp, bv = e["b"]["free"], e["b"]["pass"], e["b"]["vip_pass_boost"]
                p(f"| {nom:.0f} s | {hm(base)} | {hm(a['p50'])} | x{e['factor']:.3f} | "
                  f"{hm(bf['GlitchZone']['p50'])} ({hm(bf['GlitchZone']['p10'])}-{hm(bf['GlitchZone']['p90'])}) | "
                  f"{mn(bf['Beach']['p50'])} | {hm(bp['GlitchZone']['p50'])} | {hm(bv['GlitchZone']['p50'])} |")
            else:
                p(f"| {nom:.0f} s | {hm(base)} | {hm(a['p50'])} | not needed | - | - | - | - |")
        p("")

    p("### Diagnostics (flag on, free player)\n")
    p("| Nominal | Trips/run | Loaded/trip | Super Stars/h | Jackpots/h | Lucky/h | MEGA Lucky/h | Super pity/h | Jackpot pity/h | Mut. pity/h | Mutated share of loaded | Rain strikes/run | Rush trips | MEGA trips |")
    p("|---|" + "---:|" * 14)
    for nom in TRIP_SENSITIVITY:
        d = next(c["diagnostics"] for c in blob["cells"] if c["scenario"] == f"flag_on_{nom:.0f}s" and c["profile"] == "free")
        p(f"| {nom:.0f} s | {d['trips_per_run']:.0f} | {d['loaded_per_trip']:.2f} | {d['super_per_hour']:.1f} | "
          f"{d['jackpot_per_hour']:.2f} | {d['lucky_per_hour']:.1f} | {d['mega_lucky_per_hour']:.1f} | "
          f"{d['pity_super_per_hour']:.2f} | {d['pity_jackpot_per_hour']:.2f} | {d['pity_mut_per_hour']:.2f} | "
          f"{d['mutated_loaded_share']:.1%} | {d['rain_strikes_per_run']:.1f} | {d['rush_trip_share']:.0%} | "
          f"{d['mega_trip_share']:.0%} |")
    p("")
    p(f"Runtime: {time.time() - started:.0f} s.")
    report = "\n".join(md)
    print(report)

    if write:
        repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        out = os.path.join(repo, "docs", "coreloop", "2026-11", "economy")
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, "results.csv"), "w", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["scenario", "profile", "flag", "nominal_trip_s", "lever", "region",
                        "p10_s", "p50_s", "p90_s", "reached", "runs"])
            w.writerows(cells)

        def clean(o):
            if isinstance(o, float) and math.isinf(o):
                return None
            if isinstance(o, dict):
                return {str(k): clean(v) for k, v in o.items()}
            if isinstance(o, (list, tuple)):
                return [clean(v) for v in o]
            return o
        with open(os.path.join(out, "results.json"), "w") as fh:
            json.dump(clean(blob), fh, indent=1)
        with open(os.path.join(out, "results_tables.md"), "w") as fh:
            fh.write(report + "\n")
        print(f"wrote {out}/results.csv, results.json, results_tables.md", file=sys.stderr)
    return report
