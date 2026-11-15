#!/usr/bin/env python3
"""Top-down ASCII plan of a V5 region from the authored data (16-stud cells), for the region cards.
Usage: python3 -I tools/terrain/plan_ascii.py Beach"""
import math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import author_v5 as A
import author_v5_west as W
import author_v5_east as E
import v5_site as S

W.register(A)
E.register(A)
key = sys.argv[1]
r = A.REGIONS[key]
CELL = 16
xs = [x for cx, cz, sx, sz in S.FLOORS[key] for x in (cx - sx / 2, cx + sx / 2)]
zs = [z for cx, cz, sx, sz in S.FLOORS[key] for z in (cz - sz / 2, cz + sz / 2)]
x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)


def height(x, z):
    h = 0
    for t in r["terraces"]:
        if t["min"][0] <= x <= t["max"][0] and t["min"][2] <= z <= t["max"][2] and t["max"][1] > A.G + 0.1:
            h = max(h, round(t["max"][1] + 2))
    return h


def water(x, z):
    return any(w["min"][0] <= x <= w["max"][0] and w["min"][2] <= z <= w["max"][2] for w in r["water"])


marks = {}
def mark(x, z, ch):
    marks[(int((x - x0) // CELL), int((z - z0) // CELL))] = ch

for e in r["clusters"]:
    if e["kit"] == "Lane_GlowTiles":
        continue
    setpiece = any(k in e["kit"] for k in ("Arch", "Waterfall", "Boardwalk", "Dock", "Shipwreck", "BogHut", "Igloo",
                                          "IceSheet", "LavaStrip", "GridPlaza", "PixelTerrace", "Perch"))
    mark(e["position"][0], e["position"][2], "*" if setpiece else ".")
for e in r["signs"]:
    mark(e["position"][0], e["position"][2], "P")
for e in r["secrets"]:
    mark(e["position"][0], e["position"][2], "S")
for e in r["toys"]:
    mark(e["position"][0], e["position"][2], "L" if e["type"] == "Slide" else "J")
mark(r["landmark"]["position"][0], r["landmark"]["position"][2], "H")
for n, (bx, bz) in S.BURROWS.items():
    if S.region_at(bx, bz) == key:
        mark(bx, bz, "B")
for g, (gx, gz) in {**S.GATES, **S.GATES_EAST}.items():
    if g == key:
        east = g in S.GATES_EAST  # east gates sit on x 229 and face +x
        mark(gx + (8 if east else -8 if key == "Beach" else 0), gz + (8 if key not in ("Beach",) and not east else 0), "G")
print(f"{key}: x {x0:.0f} -> {x1:.0f} (left to right), z {z0:.0f} (top) -> {z1:.0f} (bottom), 16-stud cells")
for iz in range(int((z1 - z0) // CELL)):
    row = ""
    for ix in range(int((x1 - x0) // CELL)):
        cx, cz = x0 + (ix + 0.5) * CELL, z0 + (iz + 0.5) * CELL
        if S.region_at(cx, cz) != key:
            row += " "
        elif (ix, iz) in marks:
            row += marks[(ix, iz)]
        elif water(cx, cz):
            row += "~"
        elif any(S.is_lane(cx + dx, cz + dz) for dx in (-4, 4) for dz in (-4, 4)):
            row += "#"
        else:
            h = height(cx, cz)
            row += str(min(9, h // 4)) if h >= 4 else "-"
    print(f"{z0 + iz * CELL:6.0f} {row}")
print("Legend: # cart lane  ~ water  1-7 terrace height /4 (7 = 28)  - ground  . prop cluster  * set piece")
print("        H hero landmark  P POI sign  S secret  L slide  J bounce pad  B burrow (12-stud flat pad)  G gate")
