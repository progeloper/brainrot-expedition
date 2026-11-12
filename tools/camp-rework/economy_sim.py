#!/usr/bin/env python3
"""Offline free-player progression simulation (Camp Rework, Training vs cart Speed).

Recreates the economy simulation described in docs/economy/Brainrot_Economy.md section 3
("150 s trips, 75% cargo fill, real region pools and mutation odds") and measures the
effect of Training (src/shared/Config/Training.lua) replacing the cart Speed upgrades.

All game data below is transcribed from src/shared/Config (see DATA section). Run:

    python3 -I tools/camp-rework/economy_sim.py            # prints the report
    python3 -I tools/camp-rework/economy_sim.py --write    # also writes economy_sim_results.md

Standard library only. Deterministic (fixed seeds).
"""
from __future__ import annotations

import math
import os
import random
import statistics
import sys

# --------------------------------------------------------------------------------------
# DATA (transcribed from src/shared/Config)
# --------------------------------------------------------------------------------------

# BrainrotCatalog.lua rows: id -> (rarity, workbook cps). cashPerSecond = cps * 1e6,
# sellValue = workbook sale * 5e5 = 30 s of income. Only "Live" rows (BRT_001..032).
CATALOG_CPS = {
    "BRT_001": ("Common", 1.8), "BRT_002": ("Common", 2), "BRT_003": ("Common", 2.2),
    "BRT_004": ("Common", 2.3), "BRT_005": ("Common", 1.9), "BRT_006": ("Common", 1.8),
    "BRT_007": ("Common", 2), "BRT_008": ("Common", 2.2), "BRT_009": ("Common", 2.3),
    "BRT_010": ("Common", 1.9), "BRT_011": ("Uncommon", 4), "BRT_012": ("Uncommon", 4.5),
    "BRT_013": ("Uncommon", 5), "BRT_014": ("Uncommon", 5.2), "BRT_015": ("Uncommon", 4.3),
    "BRT_016": ("Uncommon", 4), "BRT_017": ("Uncommon", 4.5), "BRT_018": ("Uncommon", 5),
    "BRT_019": ("Rare", 10.8), "BRT_020": ("Rare", 12), "BRT_021": ("Rare", 13.2),
    "BRT_022": ("Rare", 13.8), "BRT_023": ("Rare", 11.4), "BRT_024": ("Rare", 10.8),
    "BRT_025": ("Rare", 12), "BRT_026": ("Epic", 36), "BRT_027": ("Epic", 40),
    "BRT_028": ("Epic", 44), "BRT_029": ("Epic", 46), "BRT_030": ("Epic", 38),
    "BRT_031": ("Legendary", 135), "BRT_032": ("Legendary", 150),
}
CPS = {k: v[1] * 1_000_000 for k, v in CATALOG_CPS.items()}
SELL = {k: v[1] * 60 * 500_000 for k, v in CATALOG_CPS.items()}  # sale = 60 x cps (workbook)
RARITY = {k: v[0] for k, v in CATALOG_CPS.items()}
RANK = {"Common": 1, "Uncommon": 2, "Rare": 3, "Epic": 4, "Legendary": 5, "Mythic": 6}
TIERS = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]

# WorldProgression.lua poolRows: tier weights + species per tier (uniform within a tier,
# except GlitchZone's speciesWeightOverrides BRT_031=2999, BRT_032=1).
POOLS = {
    "Forest": ([0.68, 0.26, 0.06, 0, 0, 0], {
        "Common": ["BRT_001", "BRT_002", "BRT_003", "BRT_004", "BRT_005", "BRT_006", "BRT_007", "BRT_008", "BRT_009", "BRT_010"],
        "Uncommon": ["BRT_011", "BRT_013"], "Rare": ["BRT_019"]}),
    "Beach": ([0.4, 0.4, 0.2, 0, 0, 0], {
        "Common": ["BRT_001", "BRT_002", "BRT_003", "BRT_004", "BRT_005", "BRT_006", "BRT_008", "BRT_009", "BRT_010"],
        "Uncommon": ["BRT_011", "BRT_012", "BRT_013", "BRT_014", "BRT_015"], "Rare": ["BRT_019", "BRT_020"]}),
    "Swamp": ([0.15, 0.3, 0.4, 0.15, 0, 0], {
        "Common": ["BRT_001", "BRT_002", "BRT_003", "BRT_004", "BRT_005", "BRT_006", "BRT_008", "BRT_009", "BRT_010"],
        "Uncommon": ["BRT_011", "BRT_013", "BRT_014", "BRT_015", "BRT_016", "BRT_017", "BRT_018"],
        "Rare": ["BRT_019", "BRT_020", "BRT_021", "BRT_022"], "Epic": ["BRT_026", "BRT_028", "BRT_030"]}),
    "Jungle": ([0.05, 0.15, 0.45, 0.35, 0, 0], {
        "Common": ["BRT_008", "BRT_009", "BRT_010"],
        "Uncommon": ["BRT_014", "BRT_015", "BRT_016", "BRT_017", "BRT_018"],
        "Rare": ["BRT_019", "BRT_020", "BRT_022", "BRT_023", "BRT_024", "BRT_025"],
        "Epic": ["BRT_026", "BRT_027", "BRT_028", "BRT_030"]}),
    "Arctic": ([0, 0.05, 0.25, 0.7, 0, 0], {
        "Uncommon": ["BRT_016", "BRT_017", "BRT_018"],
        "Rare": ["BRT_020", "BRT_022", "BRT_023", "BRT_024", "BRT_025"],
        "Epic": ["BRT_026", "BRT_028", "BRT_029", "BRT_030"]}),
    "Volcano": ([0, 0, 0.1, 0.65, 0.25, 0], {
        "Rare": ["BRT_022", "BRT_023", "BRT_024", "BRT_025"],
        "Epic": ["BRT_026", "BRT_028", "BRT_030"], "Legendary": ["BRT_031"]}),
    "GlitchZone": ([0, 0, 0.05, 0.35, 0.6, 0], {
        "Rare": ["BRT_023", "BRT_024", "BRT_025"], "Epic": ["BRT_026", "BRT_028", "BRT_030"],
        "Legendary": ["BRT_031", "BRT_032"]}),
}
SPECIES_WEIGHT_OVERRIDES = {"GlitchZone": {"BRT_031": 2999, "BRT_032": 1}}

# WorldProgression.lua rows: key, price, branchA, branchB (distinct banked species at >= rarity).
GATES = [
    ("Beach", 4_000_000_000, ("Uncommon", 1), None),
    ("Swamp", 60_000_000_000, ("Rare", 1), ("Uncommon", 3)),
    ("Jungle", 300_000_000_000, ("Epic", 1), ("Rare", 4)),
    ("Arctic", 1_500_000_000_000, ("Epic", 2), ("Rare", 5)),
    ("Volcano", 4_000_000_000_000, ("Legendary", 1), ("Epic", 3)),
    ("GlitchZone", 10_000_000_000_000, ("Legendary", 2), ("Epic", 4)),
]
GATE_KEYS = [g[0] for g in GATES]

# Phase12.lua MutationChance 0.04; MutationCatalog.lua conditional shares and multipliers.
MUTATION_CHANCE = 0.04
MUTATIONS = [("Shiny", 1.5, 0.45), ("Golden", 2.5, 0.25), ("Glitched", 4, 0.15),
             ("Radioactive", 7, 0.0875), ("Astral", 15, 0.0625)]

# Phase13.lua
INITIAL_SLOTS = 12
SPEED_PRICES = [500_000_000, 2_500_000_000, 15_000_000_000, 75_000_000_000, 300_000_000_000]
CARGO_PRICES = [1_500_000_000, 12_500_000_000, 100_000_000_000]
BASE_CARGO = 3  # Carts.lua CargoCapacity = 3; +1 per Cargo level
# Expansion rows (Cash route): price, +6 slots. A Cash-route rebirth sets the wallet to 0
# (Phase13Rules.ApplyRebirth) and adds +10% income (Economy.Income.RebirthBonusPerRebirth).
EXPANSIONS = [125_000_000_000, 500_000_000_000, 2_000_000_000_000, 6_000_000_000_000,
              20_000_000_000_000, 50_000_000_000_000]
REBIRTH_BONUS = 0.10
OLD_SPEED_STEP = 0.10

# Training.lua
TRAINING_MAX_LEVEL = 25
ROLLERS = [("Wooden", 1, 0), ("Steel", 3, 2_500_000_000), ("Turbo", 10, 15_000_000_000),
           ("Rocket", 40, 75_000_000_000), ("Rift", 150, 300_000_000_000)]


def old_speed_mult(n: int) -> float:
    return 1 + OLD_SPEED_STEP * n


def training_speed_mult(level: int) -> float:
    lv = max(0, min(TRAINING_MAX_LEVEL, int(level)))
    n0 = lv // 5
    if n0 >= 5:
        return old_speed_mult(5)
    a, b = old_speed_mult(n0), old_speed_mult(n0 + 1)
    return a * (b / a) ** ((lv - 5 * n0) / 5)


def xp_to_next(level: int, level1_xp: float, growth: float) -> float:
    if level < 0 or level >= TRAINING_MAX_LEVEL:
        return math.inf
    return math.floor(level1_xp * growth ** level + 0.5)


# --------------------------------------------------------------------------------------
# MODEL ASSUMPTIONS (documented in the results file)
# --------------------------------------------------------------------------------------
TRIP_SECONDS = 150.0          # doc: one hunt trip at base cart speed
DRIVE_SHARE = 0.60            # share of a trip that is driving and scales with 1/speed
CARGO_FILL = 0.75             # doc: 75% cargo fill -> expected catches = 0.75 x capacity
UPGRADE_GATE_FRACTION = 0.25  # buy an upgrade only if price <= 25% of the next gate price
UPGRADE_INCOME_SECONDS = 600  # ...or if it costs <= 10 min of current income
EXPANSION_HEADROOM = 1.25     # Cash expansion only while wallet is in [price, 1.25 x price]
DEFAULT_TRAIN_SECONDS = 20.0  # Training variant: seconds on the rollers per trip (no hunting)
RUNS = 400                    # Monte-Carlo runs per scenario (median reported)
HORIZON = 24 * 3600


ASSUMPTIONS = [
    "Free player always hunts the newest unlocked region (pools are strictly better further along).",
    "A trip is one cart run: catches = 75% of cargo capacity in expectation (3 + Cargo level; the "
    "fractional part is a Bernoulli draw), drawn by the region's tier weights, uniform species within "
    "a tier (GlitchZone override BRT_031 2999 : BRT_032 1), 4% mutation chance with MutationCatalog shares.",
    "Trip time = effective trip x (60% / speed multiplier + 40%). The 60% driving share is an assumption "
    "(sensitivity table covers 40-80%). Effective trip is the calibration knob (documented 150 s gave a "
    "faster baseline than the doc).",
    "Every catch is banked (counts toward gate rarity requirements as a distinct species, matching "
    "WorldProgressionRules.Count). The base keeps the best N by income (N = 12 + 6 per expansion); "
    "anything displaced or worse is sold for its sale value (60 x workbook cps x 500,000 x mutation).",
    "Income accrues continuously (as with Auto-Collect / prompt collection): sum of slot cps x mutation x "
    "(1 + 0.10 x rebirths) x 2 with the 2x Cash pass. No VIP, Cash Boosts, Gems, crates, daily rewards, "
    "Starter Pack, rare waves or quests.",
    "Purchases are checked at camp after each trip, in priority order: (1) next region gate when its "
    "price and rarity branch are met; (2) next Cargo level; (3) next Speed level (baseline) or next roller "
    "(Training); (4) next base expansion. Upgrades (2-3) are bought only if the price is <= 25% of the next "
    "gate price or <= 10 min of current income, so they never stall a gate.",
    "Expansions use the Cash route, which zeroes the wallet (Phase13Rules.ApplyRebirth) and adds +6 slots "
    "and +10% income; bought only with a full base while the wallet is within 1.25 x the price and below "
    "the next gate. Collection-route expansions, base designs, carts and weapons are not modelled.",
    "Training: after every trip the player spends a fixed number of seconds on the rollers (no hunting; "
    "income still accrues). XP = seconds x roller multiplier (x2 only with the separate Training 2x pass, "
    "which the '2x pass' rows do NOT include; they own the 2x Cash pass only). Level-ups use "
    "Training.XpToNext; speed uses Training.SpeedMultiplier. Rollers are bought at Steel 2.5B, Turbo 15B, "
    "Rocket 75B, Rift 300B, in the same priority slot Speed had; the old Speed 1 price point (500M) has no "
    "roller equivalent.",
    "Weapons, shot time, escape timers, other players and competition for spawns are folded into the "
    "effective trip time; capture always succeeds for whatever fills the cargo.",
    "Not found in the repo: the original simulation script, its trip-time breakdown (drive vs hunt), "
    "its purchase priority, and whether it used expansions or designs. The documented 2.6 h for the "
    "2x pass is reproduced only approximately (the model gives the value in section 0).",
]


class Player:
    def __init__(self, rng, *, training: bool, pass2x: bool, train_seconds: float,
                 level1_xp: float, growth: float, trip_seconds: float, expansions: bool,
                 training_pass: bool = False):
        self.rng = rng
        self.training = training
        self.income_mult_pass = 2.0 if pass2x else 1.0
        self.train_seconds = train_seconds if training else 0.0
        self.level1_xp, self.growth = level1_xp, growth
        self.trip_seconds = trip_seconds
        self.use_expansions = expansions
        self.training_pass = training_pass
        self.t = 0.0
        self.cash = 0.0
        self.slots: list[float] = []      # income per slot (cps x mutation), kept sorted desc
        self.slot_sell: list[float] = []
        self.capacity = INITIAL_SLOTS
        self.rebirths = 0
        self.expansion_level = 0
        self.banked_species: dict[str, int] = {}  # species -> rarity rank at first bank
        self.unlocked = ["Forest"]
        self.gate_times: dict[str, float] = {}
        self.cargo_level = 0
        self.speed_level = 0      # baseline: Speed upgrades owned
        self.roller = 0           # training: index into ROLLERS
        self.tlevel = 0
        self.txp = 0.0
        self.level_at_gate: dict[str, int] = {}
        self.purchases: list[tuple[float, str]] = []

    # --- economy -------------------------------------------------------------------
    def income(self) -> float:
        return sum(self.slots) * (1 + REBIRTH_BONUS * self.rebirths) * self.income_mult_pass

    def speed_mult(self) -> float:
        return training_speed_mult(self.tlevel) if self.training else old_speed_mult(self.speed_level)

    def trip_duration(self) -> float:
        s = self.trip_seconds
        return s * (DRIVE_SHARE / self.speed_mult() + (1 - DRIVE_SHARE))

    def counts(self) -> dict[str, int]:
        c = {t: 0 for t in TIERS}
        for rank in self.banked_species.values():
            for tier in TIERS:
                if rank >= RANK[tier]:
                    c[tier] += 1
        return c

    def gate_eligible(self, gate) -> bool:
        _, _, a, b = gate
        c = self.counts()
        return any(spec and c[spec[0]] >= spec[1] for spec in (a, b))

    def next_gate(self):
        idx = len(self.unlocked) - 1
        return GATES[idx] if idx < len(GATES) else None

    # --- hunting -------------------------------------------------------------------
    def draw(self, region: str) -> tuple[str, float]:
        weights, species = POOLS[region]
        tiers = [t for t, w in zip(TIERS, weights) if w > 0 and species.get(t)]
        tw = [weights[TIERS.index(t)] for t in tiers]
        tier = self.rng.choices(tiers, tw)[0]
        pool = species[tier]
        ov = SPECIES_WEIGHT_OVERRIDES.get(region, {})
        sid = self.rng.choices(pool, [ov.get(s, 1) for s in pool])[0]
        mult = 1.0
        if self.rng.random() < MUTATION_CHANCE:
            mult = self.rng.choices([m[1] for m in MUTATIONS], [m[2] for m in MUTATIONS])[0]
        return sid, mult

    def catches(self) -> int:
        cap = BASE_CARGO + self.cargo_level
        expected = CARGO_FILL * cap
        base = int(expected)
        return base + (1 if self.rng.random() < expected - base else 0)

    def bank(self, sid: str, mult: float):
        self.banked_species.setdefault(sid, RANK[RARITY[sid]])
        inc, sell = CPS[sid] * mult, SELL[sid] * mult
        if len(self.slots) < self.capacity:
            self.slots.append(inc)
            self.slot_sell.append(sell)
        else:
            worst = min(range(len(self.slots)), key=lambda i: self.slots[i])
            if inc > self.slots[worst]:
                self.cash += self.slot_sell[worst]
                self.slots[worst], self.slot_sell[worst] = inc, sell
            else:
                self.cash += sell

    # --- time ----------------------------------------------------------------------
    def advance(self, seconds: float):
        self.cash += self.income() * seconds
        self.t += seconds

    def train(self):
        if self.train_seconds <= 0:
            return
        mult = ROLLERS[self.roller][1] * (2 if self.training_pass else 1)
        self.txp += self.train_seconds * mult
        while self.tlevel < TRAINING_MAX_LEVEL:
            need = xp_to_next(self.tlevel, self.level1_xp, self.growth)
            if self.txp < need:
                break
            self.txp -= need
            self.tlevel += 1
        self.advance(self.train_seconds)

    # --- purchases (at camp, after each trip) -------------------------------------
    def shop(self):
        bought = True
        while bought:
            bought = False
            gate = self.next_gate()
            if gate and self.gate_eligible(gate) and self.cash >= gate[1]:
                self.cash -= gate[1]
                self.unlocked.append(gate[0])
                self.gate_times[gate[0]] = self.t
                self.level_at_gate[gate[0]] = self.tlevel
                self.purchases.append((self.t, gate[0]))
                bought = True
                continue
            gate_price = gate[1] if gate else math.inf
            budget_ok = lambda price: price <= max(UPGRADE_GATE_FRACTION * gate_price,
                                                   UPGRADE_INCOME_SECONDS * self.income())
            # Priority 2: Cargo (more catches per trip).
            if self.cargo_level < len(CARGO_PRICES):
                price = CARGO_PRICES[self.cargo_level]
                if self.cash >= price and budget_ok(price):
                    self.cash -= price
                    self.cargo_level += 1
                    self.purchases.append((self.t, f"Cargo{self.cargo_level}"))
                    bought = True
                    continue
            # Priority 3: Speed (baseline) or rollers (Training) at the same price points.
            if self.training:
                if self.roller + 1 < len(ROLLERS):
                    price = ROLLERS[self.roller + 1][2]
                    if self.cash >= price and budget_ok(price):
                        self.cash -= price
                        self.roller += 1
                        self.purchases.append((self.t, ROLLERS[self.roller][0]))
                        bought = True
                        continue
            elif self.speed_level < len(SPEED_PRICES):
                price = SPEED_PRICES[self.speed_level]
                if self.cash >= price and budget_ok(price):
                    self.cash -= price
                    self.speed_level += 1
                    self.purchases.append((self.t, f"Speed{self.speed_level}"))
                    bought = True
                    continue
            # Priority 4: Cash-route expansion (wipes the wallet) while base is full and the
            # wallet is only just above the price, so little extra Cash is sacrificed.
            if self.use_expansions and self.expansion_level < len(EXPANSIONS):
                price = EXPANSIONS[self.expansion_level]
                if (len(self.slots) >= self.capacity and price <= self.cash <= EXPANSION_HEADROOM * price
                        and self.cash < gate_price):
                    self.cash = 0.0
                    self.expansion_level += 1
                    self.capacity += 6
                    self.rebirths += 1
                    self.purchases.append((self.t, f"Expansion{self.expansion_level}"))
                    bought = True
                    continue

    def run(self):
        while "GlitchZone" not in self.gate_times and self.t < HORIZON:
            region = self.unlocked[-1]
            dur = self.trip_duration()
            n = self.catches()
            self.advance(dur)
            for _ in range(n):
                self.bank(*self.draw(region))
            self.train()
            self.shop()
        return self


def simulate(runs=RUNS, seed0=1, **kw):
    results = []
    for i in range(runs):
        results.append(Player(random.Random(seed0 + i), **kw).run())
    return results


def median_gate(results, key):
    vals = [r.gate_times.get(key, math.inf) for r in results]
    return statistics.median(vals)


def median_level(results, key):
    return statistics.median([r.level_at_gate.get(key, 0) for r in results])


def pct(results, key, q):
    vals = sorted(r.gate_times.get(key, math.inf) for r in results)
    return vals[min(len(vals) - 1, int(q * len(vals)))]


def hm(seconds: float) -> str:
    if math.isinf(seconds):
        return "n/a"
    return f"{seconds / 3600:.2f} h"


def mins(seconds: float) -> str:
    return "n/a" if math.isinf(seconds) else f"{seconds / 60:.0f} min"


# --------------------------------------------------------------------------------------
# CALIBRATION: effective trip seconds so the baseline free player reaches Glitch ~4.3 h.
# --------------------------------------------------------------------------------------
TARGET_GLITCH_FREE = 4.3 * 3600


def calibrate(expansions: bool):
    lo, hi = 60.0, 900.0
    best = None
    for _ in range(18):
        mid = (lo + hi) / 2
        g = median_gate(simulate(runs=120, training=False, pass2x=False, train_seconds=0,
                                 level1_xp=60, growth=1.35, trip_seconds=mid,
                                 expansions=expansions), "GlitchZone")
        best = (mid, g)
        if g < TARGET_GLITCH_FREE:
            lo = mid
        else:
            hi = mid
    return best


def main():
    out: list[str] = []
    p = out.append
    common = dict(level1_xp=60, growth=1.35, expansions=True)

    # Step 1: uncalibrated reproduction with the documented 150 s trips.
    raw = {pass2x: simulate(training=False, pass2x=pass2x, train_seconds=0,
                             trip_seconds=TRIP_SECONDS, **common) for pass2x in (False, True)}
    raw_free, raw_pass = median_gate(raw[False], "GlitchZone"), median_gate(raw[True], "GlitchZone")

    # Step 2: calibrate effective trip seconds to the documented 4.3 h free baseline.
    cal_trip, _ = calibrate(expansions=True)
    cal_trip = round(cal_trip)

    scen = {}
    for training in (False, True):
        for pass2x in (False, True):
            scen[(training, pass2x)] = simulate(training=training, pass2x=pass2x,
                                                train_seconds=DEFAULT_TRAIN_SECONDS,
                                                trip_seconds=cal_trip, **common)

    p("# Economy simulation: cart Speed upgrades vs Training\n")
    p("Generated by `python3 -I tools/camp-rework/economy_sim.py --write` "
      f"({RUNS} Monte-Carlo runs per scenario, medians; fixed seeds, so reruns are identical).\n")

    p("## 0. Reproducing the documented baseline\n")
    p("| Scenario (Speed upgrades available) | Trip at base speed | Free -> Glitch | 2x pass -> Glitch |")
    p("|---|---:|---:|---:|")
    p(f"| Documented (Brainrot_Economy.md section 3) | 150 s | 4.30 h | 2.60 h |")
    p(f"| This model, uncalibrated | {TRIP_SECONDS:.0f} s | {hm(raw_free)} | {hm(raw_pass)} |")
    p(f"| This model, calibrated | {cal_trip} s | {hm(median_gate(scen[(False, False)], 'GlitchZone'))} | "
      f"{hm(median_gate(scen[(False, True)], 'GlitchZone'))} |")
    p("")
    p(f"Calibration knob: **effective trip seconds** (the 150 s trip plus everything the doc's 150 s "
      f"leaves out: walking to the gate/shop, banking, selling, re-equipping, idle). With the "
      f"documented 150 s the model is faster than the doc ({hm(raw_free)} vs 4.3 h), so the trip "
      f"was stretched to **{cal_trip} s** at base cart speed. The 2x-pass result is not calibrated "
      f"separately; compare it with the documented 2.6 h as a check of the model's shape.\n")

    p("## 1. Baseline (Speed) vs Training: time to each region gate\n")
    p(f"Training variant: {DEFAULT_TRAIN_SECONDS:.0f} s on the rollers per trip, Level1Xp 60, "
      f"growth 1.35, no Training 2x pass. Times are median elapsed play time.\n")
    for pass2x in (False, True):
        label = "2x Cash pass" if pass2x else "Free player"
        b, t = scen[(False, pass2x)], scen[(True, pass2x)]
        p(f"### {label}\n")
        p("| Gate | Baseline (Speed) | Training | Change | Training level at unlock |")
        p("|---|---:|---:|---:|---:|")
        for key in GATE_KEYS:
            gb, gt = median_gate(b, key), median_gate(t, key)
            change = (gt - gb) / gb * 100 if gb else 0
            p(f"| {key} | {mins(gb)} | {mins(gt)} | {change:+.1f}% | {median_level(t, key):.0f} |")
        gb, gt = median_gate(b, "GlitchZone"), median_gate(t, "GlitchZone")
        p(f"\nTime to Glitch Zone: {hm(gb)} -> {hm(gt)} "
          f"({(gt - gb) / 60:+.0f} min, {(gt - gb) / gb * 100:+.1f}%). "
          f"Spread (p10-p90) baseline {hm(pct(b, 'GlitchZone', .1))}-{hm(pct(b, 'GlitchZone', .9))}, "
          f"Training {hm(pct(t, 'GlitchZone', .1))}-{hm(pct(t, 'GlitchZone', .9))}.\n")

    # Purchase timeline of a representative run (median Glitch time among runs).
    def representative(results):
        ordered = sorted(results, key=lambda r: r.gate_times.get("GlitchZone", math.inf))
        return ordered[len(ordered) // 2]

    p("### Purchase timeline of the median run (free player)\n")
    for training in (False, True):
        r = representative(scen[(training, False)])
        items = ", ".join(f"{name} {s / 60:.0f}m" for s, name in r.purchases)
        p(f"- {'Training' if training else 'Baseline'}: {items}")
    p("")

    # Section 2: Training level at Jungle unlock.
    durations = [10, 15, 20, 30, 45]
    level1s = [45, 60, 75]
    grid = {}
    for l1 in level1s:
        for d in durations:
            res = simulate(runs=200, training=True, pass2x=False, train_seconds=d,
                           level1_xp=l1, growth=1.35, trip_seconds=cal_trip, expansions=True)
            grid[(l1, d)] = (median_level(res, "Jungle"), median_gate(res, "Jungle"),
                             median_gate(res, "GlitchZone"))
    p("## 2. Training level when Jungle unlocks (free player)\n")
    p("Median Training level at the moment the Jungle gate is bought (growth 1.35, no Training pass). "
      "Cell: level (Jungle time / Glitch time).\n")
    p("| Level1Xp \\ s per trip | " + " | ".join(f"{d} s" for d in durations) + " |")
    p("|---|" + "---:|" * len(durations))
    for l1 in level1s:
        cells = [f"**{grid[(l1, d)][0]:.0f}** ({hm(grid[(l1, d)][1])} / {hm(grid[(l1, d)][2])})"
                 for d in durations]
        p(f"| {l1} | " + " | ".join(cells) + " |")
    p("")
    # Closest to level 10, preferring Level1Xp 60, then 20 s.
    ranked = sorted(grid.items(), key=lambda kv: (abs(kv[1][0] - 10), abs(kv[0][0] - 60),
                                                    abs(kv[0][1] - 20)))
    (best_l1, best_d), (best_lv, best_j, best_g) = ranked[0]
    hits = [f"Level1Xp {l1} / {d} s (level {v[0]:.0f})" for (l1, d), v in grid.items()
            if abs(v[0] - 10) <= 0.5]
    p("Combinations landing at level 10: " + (", ".join(hits) if hits else "none exactly") + ".\n")
    p(f"Closest to level 10 (tie-break: Level1Xp nearest 60, then 20 s): "
      f"**Level1Xp {best_l1}, {best_d} s per trip** -> level {best_lv:.0f} at Jungle "
      f"({hm(best_j)}), Glitch at {hm(best_g)}.\n")

    # XP table for reference
    p("### XP curve reference (growth 1.35)\n")
    p("| Level1Xp | Total XP to L5 | L10 | L15 | L20 | L25 |")
    p("|---|---:|---:|---:|---:|---:|")
    for l1 in level1s:
        tot = [sum(xp_to_next(i, l1, 1.35) for i in range(L)) for L in (5, 10, 15, 20, 25)]
        p(f"| {l1} | " + " | ".join(f"{v:,.0f}" for v in tot) + " |")
    p("")
    p("Speed multiplier by Training level: " + ", ".join(
        f"L{lv} x{training_speed_mult(lv):.3f}" for lv in (0, 5, 10, 15, 20, 25)) + ".\n")

    # Sensitivity: drive share and Training pass
    p("### Sensitivity (free player, Level1Xp 60, 20 s/trip)\n")
    p("| Variant | Baseline -> Glitch | Training -> Glitch | Training level at Jungle |")
    p("|---|---:|---:|---:|")
    global DRIVE_SHARE
    saved = DRIVE_SHARE
    for share in (0.4, 0.6, 0.8):
        DRIVE_SHARE = share
        b = simulate(runs=200, training=False, pass2x=False, train_seconds=0, trip_seconds=cal_trip, **common)
        t = simulate(runs=200, training=True, pass2x=False, train_seconds=20, trip_seconds=cal_trip, **common)
        p(f"| Drive share {share:.0%} | {hm(median_gate(b, 'GlitchZone'))} | "
          f"{hm(median_gate(t, 'GlitchZone'))} | {median_level(t, 'Jungle'):.0f} |")
    DRIVE_SHARE = saved
    t = simulate(runs=200, training=True, pass2x=False, train_seconds=20, trip_seconds=cal_trip,
                 training_pass=True, **common)
    p(f"| + Training 2x pass (XP x2) | - | {hm(median_gate(t, 'GlitchZone'))} | "
      f"{median_level(t, 'Jungle'):.0f} |")
    t = simulate(runs=200, training=True, pass2x=False, train_seconds=0, trip_seconds=cal_trip, **common)
    grid_none = median_gate(t, 'GlitchZone')
    p(f"| No training at all (level 0 forever) | - | {hm(grid_none)} | 0 |")
    p("")

    l60 = {d: grid[(60, d)][0] for d in durations}
    p("## 3. Recommendation\n")
    p(f"- **Keep Level1Xp = 60, growth 1.35.** Level1Xp moves the Jungle level by only about one level per "
      f"+/-15 XP, because roller multipliers (Steel x3 ... Rocket x40, bought before Jungle) dominate XP "
      f"income. At 60 the Jungle level is {', '.join(f'{l60[d]:.0f} at {d} s' for d in durations)}.")
    p(f"- **Design assumption: ~10 s of training per trip on average** (for example one ~1 min session every "
      f"6 trips). That lands level ~10 (x1.20 speed, = old Speed 2) at Jungle with Level1Xp 60. A player who "
      f"trains 20 s every trip is ~2 levels ahead, which is fine because speed is capped at x1.5 (level 25).")
    p(f"- Training costs the free player roughly {(median_gate(scen[(True, False)], 'GlitchZone') - median_gate(scen[(False, False)], 'GlitchZone')) / 60:+.0f} min "
      f"to Glitch at 20 s/trip versus the Speed baseline: the time on the rollers does not hunt, and the "
      f"speed multiplier arrives later than the purchased Speed levels did. The game is income-bound "
      f"(slots and gates), so cart speed is a small lever either way (no training at all is only "
      f"~{(grid_none - median_gate(scen[(False, False)], 'GlitchZone')) / 60:.0f} min slower than baseline). "
      f"One untested lever if parity matters: the old Speed-1 price point (500M) currently has no roller equivalent.\n")

    p("## 4. Assumptions and missing data\n")
    for line in ASSUMPTIONS:
        p(f"- {line}")
    p("")
    p(f"Calibrated effective trip: {cal_trip} s at base cart speed, of which {DRIVE_SHARE:.0%} scales with 1/speed.")

    report = "\n".join(out)
    print(report)
    return report, dict(cal_trip=cal_trip, grid=grid)


if __name__ == "__main__":
    report, _ = main()
    if "--write" in sys.argv:
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "economy_sim_results.md")
        with open(path, "w") as fh:
            fh.write(report + "\n")
        print(f"\nwrote {path}", file=sys.stderr)
