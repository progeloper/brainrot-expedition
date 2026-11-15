"""Site data for the V5 authoring scripts: region floor rectangles, the precise lane mask and the
protected points (burrows, gates), all read from Studio Edit (see the files named below)."""
import json, math, os

HERE = os.path.dirname(os.path.abspath(__file__))
FLOORS = {k: v for k, v in json.load(open(os.path.join(HERE, "region_floors.json"))).items() if not k.startswith("_")}

# tools/terrain/lane_mask_{west,east}.txt: SurveyLanes.edit.luau output (4-stud cells, run-length rows).
# Both masks share the west grid (east X0 224 = -748 + 243 cells), so cells are stored in west indices.
_lines = open(os.path.join(HERE, "lane_mask_west.txt")).read().split("\n")
LX0, LZ0, LCELL, LNX, LNZ = map(int, _lines[0].split())
LANE = set()


def _load(lines, x_offset):
    for row in lines[1:]:
        if not row:
            continue
        iz, runs = row.split(":")
        for ab in runs.split(","):
            a, b = map(int, ab.split("-"))
            for ix in range(a, b + 1):
                LANE.add((ix + x_offset, int(iz)))


_load(_lines, 0)
_east = open(os.path.join(HERE, "lane_mask_east.txt")).read().split("\n")
_ex0, _ez0, _ecell = map(int, _east[0].split()[:3])
assert _ez0 == LZ0 and _ecell == LCELL and (_ex0 - LX0) % LCELL == 0
_load(_east, (_ex0 - LX0) // LCELL)

# Phase12Burrows pivots and gate thresholds (Studio Edit read: west 9 Nov, east 9 Nov 2026).
BURROWS = {
    "B01": (-622, -550), "B02": (-378, -550), "B03": (-620, 62),
    "S01": (-622, 290), "S02": (-378, 290), "S03": (-620, 472),
    "J01": (-150, 288), "J02": (102, 471), "J03": (-382, 470),
    "A01": (338, -550), "A02": (582, -550), "A03": (340, -378),
    "V01": (580, -382), "V02": (580, 82), "V03": (338, 80),
    "G01": (338, 290), "G02": (582, 290), "G03": (462, 470),
}
GATES = {"Beach": (-507, -384), "Swamp": (-387, 202), "Jungle": (-244.234, 202)}
# East gates are kept apart so the approved CP-B dressing (which reads GATES) regenerates unchanged;
# author_v5_east.py adds them to its own checks.
GATES_EAST = {"Arctic": (229, -564), "Volcano": (229, -280.206), "GlitchZone": (229, 292)}


def region_at(x, z):
    for key, rects in FLOORS.items():
        for cx, cz, sx, sz in rects:
            if abs(x - cx) <= sx / 2 and abs(z - cz) <= sz / 2:
                return key
    return None


def is_lane(x, z):
    return (math.floor((x - LX0) / LCELL), math.floor((z - LZ0) / LCELL)) in LANE


def lane_distance(x, z, limit=40):
    """Distance (studs, 4-stud resolution) from (x, z) to the nearest lane cell, capped at `limit`."""
    ix0, iz0 = math.floor((x - LX0) / LCELL), math.floor((z - LZ0) / LCELL)
    r = int(limit / LCELL) + 1
    best = limit
    for dx in range(-r, r + 1):
        for dz in range(-r, r + 1):
            if (ix0 + dx, iz0 + dz) in LANE:
                cx, cz = LX0 + (ix0 + dx + 0.5) * LCELL, LZ0 + (iz0 + dz + 0.5) * LCELL
                d = math.hypot(cx - x, cz - z) - LCELL * 0.7
                if d < best:
                    best = max(0, d)
    return best


def rect_lane_clear(x0, z0, x1, z1, margin):
    """True if the rectangle grown by `margin` contains no lane cell."""
    for ix in range(math.floor((x0 - margin - LX0) / LCELL), math.floor((x1 + margin - LX0) / LCELL) + 1):
        for iz in range(math.floor((z0 - margin - LZ0) / LCELL), math.floor((z1 + margin - LZ0) / LCELL) + 1):
            if (ix, iz) in LANE:
                return False
    return True


def protected_distance(x, z):
    d = 1e9
    for bx, bz in BURROWS.values():
        d = min(d, math.hypot(x - bx, z - bz))
    for gx, gz in GATES.values():
        d = min(d, math.hypot(x - gx, z - gz) - 20)
    return d
