#!/usr/bin/env python3
"""Playtest Fixes C4: v2 art for WPN_C01 (crossbow) and WPN_G01 (blaster) in the T1 Trailwood style of
HRP_001 (same palette: wood browns, dark joints, cream wraps, Neon vine/leaf greens, red mushroom cap).

Writes Rojo model.json files (tracked in git, so a Rojo sync can't lose them):
  src/assets/PlaytestArtV2/<ID>.model.json       held art: Folder with Phase13Appearance (Handle frame)
  src/assets/PlaytestDisplaysV2/<ID>.model.json  stall display: the same parts at 1.5x, anchored
Coordinates are the Handle frame used by every weapon template: forward = -Z, up = +Y, grip near
(0, -0.3, 0.5). Phase13RuntimeService/CampStallController prefer these only while Playtest Fixes
WeaponFx is on. Run: python3 -I tools/playtest_fixes/build_t1_weapons.py
"""
import json
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
STUD = "rbxassetid://126387978066468"

PAL = {
    "wood": "a0652c", "woodDark": "7a4a22", "edge": "d08a45", "belly": "4e2e14", "joint": "1d2133",
    "wrap": "e7e4cf", "wrap2": "cfc9a8", "leaf": "3bd16f", "leafLight": "8dff3a", "leafDark": "1e8f45",
    "cap": "f0283c", "gill": "e7e4cf", "stem": "f7f5fc", "gold": "ffd447", "shaft": "e7c08a",
}


def rot(rx=0.0, ry=0.0, rz=0.0):
    """Rows of CFrame.Angles(rx, ry, rz) (degrees), i.e. Rx * Ry * Rz."""
    a, b, c = (math.radians(v) for v in (rx, ry, rz))
    rx_ = [[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]]
    ry_ = [[math.cos(b), 0, math.sin(b)], [0, 1, 0], [-math.sin(b), 0, math.cos(b)]]
    rz_ = [[math.cos(c), -math.sin(c), 0], [math.sin(c), math.cos(c), 0], [0, 0, 1]]

    def mul(p, q):
        return [[sum(p[i][k] * q[k][j] for k in range(3)) for j in range(3)] for i in range(3)]

    return mul(mul(rx_, ry_), rz_)


def look_at(p, q):
    """Rows for a part whose -Z (look) runs from p to q."""
    d = [q[i] - p[i] for i in range(3)]
    n = math.sqrt(sum(v * v for v in d))
    look = [v / n for v in d]
    up0 = [0, 1, 0] if abs(look[1]) < 0.95 else [1, 0, 0]
    right = [look[1] * up0[2] - look[2] * up0[1], look[2] * up0[0] - look[0] * up0[2], look[0] * up0[1] - look[1] * up0[0]]
    rn = math.sqrt(sum(v * v for v in right))
    right = [v / rn for v in right]
    up = [right[1] * look[2] - right[2] * look[1], right[2] * look[0] - right[0] * look[2], right[0] * look[1] - right[1] * look[0]]
    back = [-v for v in look]
    return [[right[i], up[i], back[i]] for i in range(3)], n


def box(name, size, pos, colour, neon=False, r=None, studs=None, wedge=False):
    return {"name": name, "size": list(size), "pos": list(pos), "rot": r or rot(), "colour": PAL[colour],
            "neon": neon, "studs": studs or [], "wedge": wedge}


def rod(name, p, q, width, colour, neon=False):
    r, n = look_at(p, q)
    mid = [(p[i] + q[i]) / 2 for i in range(3)]
    return box(name, (width, width, n), mid, colour, neon, r)


def mushroom(at):
    x, y, z = at
    return [
        box("Stem", (0.24, 0.34, 0.24), (x, y + 0.17, z), "stem"),
        box("Gill", (0.52, 0.06, 0.52), (x, y + 0.37, z), "gill"),
        box("Cap1", (0.6, 0.18, 0.6), (x, y + 0.49, z), "cap", studs=["Top"]),
        box("Cap2", (0.4, 0.14, 0.4), (x, y + 0.65, z), "cap"),
        box("Cap3", (0.2, 0.1, 0.2), (x, y + 0.77, z), "cap"),
    ]


def grip(z, pitch):
    """Grip leaning back by `pitch` degrees; wraps sit along its own axis."""
    r = rot(pitch, 0, 0)
    a = math.radians(pitch)
    axis = (0, math.cos(a), math.sin(a))  # the grip's up after Rx(pitch)
    centre = (0, -0.62, z)

    def along(d):
        return tuple(centre[i] + axis[i] * d for i in range(3))

    parts = [box("GripCore", (0.34, 0.95, 0.4), centre, "woodDark", r=r, studs=["Left", "Right"])]
    for i, d in enumerate((0.28, 0.06, -0.16)):
        parts.append(box("Wrap", (0.4, 0.12, 0.46), along(d), "wrap" if i % 2 == 0 else "wrap2", r=r))
    parts.append(box("WrapBandB", (0.42, 0.06, 0.48), along(-0.42), "leaf", neon=True, r=r))
    return parts


def crossbow():
    """WPN_C01 Trailwood-style crossbow: carved stock, recurve wood prod, vine string, mushroom sight."""
    p = []
    p += [
        box("Stock", (0.44, 0.44, 3.5), (0, 0.15, -0.55), "wood", studs=["Left", "Right", "Top"]),
        box("Belly", (0.38, 0.12, 3.3), (0, -0.12, -0.55), "belly"),
        box("TopRail", (0.22, 0.08, 3.0), (0, 0.41, -0.8), "edge"),
        box("Butt", (0.5, 0.82, 0.72), (0, -0.04, 1.36), "woodDark", studs=["Left", "Right"]),
        box("RiserCap", (0.52, 0.84, 0.12), (0, -0.04, 1.76), "edge"),
        box("ShelfMoss", (0.4, 0.06, 0.52), (0, 0.39, 1.36), "leafLight", neon=True),
        box("Collar", (0.52, 0.52, 0.1), (0, 0.15, -1.7), "joint"),
        box("Collar", (0.52, 0.52, 0.1), (0, 0.15, 0.95), "joint"),
        box("Trigger", (0.08, 0.26, 0.12), (0, -0.28, 0.12), "joint"),
        box("TriggerGuard", (0.1, 0.1, 0.55), (0, -0.48, 0.15), "joint"),
        box("LeafEmblem", (0.04, 0.32, 0.5), (0.24, 0.15, -0.15), "leaf", neon=True),
        box("LeafEmblem", (0.04, 0.32, 0.5), (-0.24, 0.15, -0.15), "leaf", neon=True),
        # bolt
        box("Shaft", (0.1, 0.1, 2.5), (0, 0.5, -1.25), "shaft"),
        box("HeadBase", (0.18, 0.18, 0.14), (0, 0.5, -2.52), "woodDark"),
        box("Head2", (0.24, 0.24, 0.36), (0, 0.5, -2.74), "leafLight", neon=True, wedge=True, r=rot(-90, 0, 0)),
        box("VaneSide", (0.04, 0.22, 0.42), (0.07, 0.56, -0.1), "leafLight"),
        box("VaneSide", (0.04, 0.22, 0.42), (-0.07, 0.56, -0.1), "leafLight"),
        box("ArrowNock", (0.14, 0.14, 0.1), (0, 0.5, 0.04), "gold"),
        # prod centre + crown leaves
        box("Riser", (0.62, 0.36, 0.46), (0, 0.3, -2.1), "woodDark", studs=["Front", "Top"]),
        box("Crown1", (0.3, 0.3, 0.3), (0, 0.58, -2.1), "leaf", r=rot(0, 45, 0)),
        box("Crown2", (0.2, 0.2, 0.2), (0, 0.76, -2.1), "leafLight", r=rot(0, 45, 0)),
        box("Crown4", (0.1, 0.16, 0.1), (0, 0.92, -2.1), "leafLight", neon=True),
    ]
    tips = {}
    for side in (1, -1):
        s = side
        p += [
            box("Limb", (1.0, 0.26, 0.3), (s * 0.78, 0.3, -2.02), "wood", r=rot(0, -s * 12, 0), studs=["Top"]),
            box("Limb", (0.95, 0.22, 0.27), (s * 1.66, 0.3, -1.8), "woodDark", r=rot(0, -s * 24, 0)),
            box("Recurve1", (0.42, 0.2, 0.24), (s * 2.12, 0.3, -1.8), "edge", r=rot(0, s * 18, 0)),
            box("Edge", (0.95, 0.06, 0.08), (s * 0.78, 0.45, -2.1), "edge", r=rot(0, -s * 12, 0)),
            box("Vine", (1.7, 0.05, 0.05), (s * 1.2, 0.46, -1.95), "leaf", neon=True, r=rot(0, -s * 18, 0)),
            box("VineLeafA", (0.22, 0.05, 0.14), (s * 1.5, 0.5, -1.86), "leafLight", r=rot(0, s * 30, 0)),
            box("Nock", (0.12, 0.12, 0.12), (s * 2.3, 0.3, -1.76), "gold", neon=True),
        ]
        tips[side] = (s * 2.3, 0.3, -1.76)
    p += [
        rod("String", tips[1], (0, 0.5, -0.95), 0.05, "leaf", neon=True),
        rod("String", tips[-1], (0, 0.5, -0.95), 0.05, "leaf", neon=True),
    ]
    p += mushroom((0, 0.37, 0.55))
    p += grip(0.45, 10)
    return p, (0, 0.5, -2.95)


def blaster():
    """WPN_G01 Trailwood-style blaster: carved log barrel with vine wraps, root-knot body, mushroom sight."""
    p = [
        box("Riser", (0.56, 0.7, 1.6), (0, 0.25, -0.1), "woodDark", studs=["Left", "Right"]),
        box("RiserCap", (0.6, 0.1, 1.6), (0, 0.63, -0.1), "edge", studs=["Top"]),
        box("Belly", (0.5, 0.1, 1.5), (0, -0.13, -0.1), "belly"),
        box("Limb", (0.4, 0.4, 2.0), (0, 0.36, -1.85), "wood", studs=["Left", "Right", "Top"]),
        box("Collar", (0.46, 0.46, 0.1), (0, 0.36, -1.2), "joint"),
        box("Collar", (0.46, 0.46, 0.1), (0, 0.36, -2.3), "joint"),
        box("HeadBase", (0.5, 0.5, 0.26), (0, 0.36, -2.92), "edge"),
        box("Head2", (0.3, 0.3, 0.06), (0, 0.36, -3.07), "leafLight", neon=True),
        box("Vine", (0.05, 0.05, 1.8), (0.22, 0.42, -1.85), "leaf", neon=True),
        box("Vine", (0.05, 0.05, 1.8), (-0.22, 0.3, -1.85), "leaf", neon=True),
        box("VineLeafA", (0.05, 0.16, 0.24), (0.24, 0.5, -1.4), "leafLight"),
        box("VineLeafB", (0.05, 0.16, 0.24), (-0.24, 0.22, -2.2), "leaf"),
        box("Butt", (0.46, 0.56, 0.8), (0, 0.2, 1.05), "wood", studs=["Left", "Right"]),
        box("RiserCap", (0.48, 0.58, 0.1), (0, 0.2, 1.5), "edge"),
        box("ShelfMoss", (0.4, 0.05, 0.6), (0, 0.5, 1.05), "leafLight", neon=True),
        box("Trigger", (0.08, 0.24, 0.12), (0, -0.25, 0.1), "joint"),
        box("TriggerGuard", (0.1, 0.1, 0.5), (0, -0.45, 0.15), "joint"),
        box("LeafEmblem", (0.04, 0.34, 0.5), (0.29, 0.25, -0.1), "leaf", neon=True),
        box("LeafEmblem", (0.04, 0.34, 0.5), (-0.29, 0.25, -0.1), "leaf", neon=True),
        box("Crest1", (0.14, 0.14, 0.3), (0, 0.72, -0.75), "leaf", neon=True),
        box("WrapBandT", (0.6, 0.06, 0.12), (0, 0.66, 0.6), "leaf", neon=True),
    ]
    p += mushroom((0, 0.68, 0.2))
    p += grip(0.5, 12)
    return p, (0, 0.36, -3.15)


def cframe(pos, r):
    return {"CFrame": {"position": pos, "orientation": r}}


def part_json(b, scale, anchored):
    size = [v * scale for v in b["size"]]
    pos = [v * scale for v in b["pos"]]
    colour = [int(b["colour"][i:i + 2], 16) / 255 for i in (0, 2, 4)]
    children = []
    if b["studs"]:
        for face in b["studs"]:
            children.append({"className": "Texture", "name": "Studs_" + face, "properties": {
                "Texture": STUD, "Face": face, "StudsPerTileU": 0.35 * scale, "StudsPerTileV": 0.35 * scale,
                # tinted to the part so the studs read without bleaching the wood
                "Color3": colour, "Transparency": 0.35}, "children": []})
    return {"className": "WedgePart" if b["wedge"] else "Part", "name": b["name"], "properties": {
        "Size": size, "CFrame": cframe(pos, b["rot"]), "Color": colour,
        "Material": "Neon" if b["neon"] else "SmoothPlastic", "Anchored": anchored, "CanCollide": False,
        "CanQuery": False, "CanTouch": False, "Massless": True, "CastShadow": max(size) > 1.0,
        "TopSurface": "Smooth", "BottomSurface": "Smooth"}, "children": children}


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=1)
        f.write("\n")


def main():
    weapons = {"WPN_C01": (crossbow, "Crossbow"), "WPN_G01": (blaster, "Gun")}
    report = {}
    for wid, (build, family) in weapons.items():
        parts, muzzle = build()
        held = {"className": "Folder", "attributes": {
            "Phase13ArtVersion": 2, "WeaponId": wid, "PlaytestArtV2": True,
            "MuzzleX": muzzle[0], "MuzzleY": muzzle[1], "MuzzleZ": muzzle[2], "CampPartCount": len(parts)},
            "children": [{"className": "Folder", "name": "Phase13Appearance",
                          "children": [part_json(b, 1.0, True) for b in parts]}]}
        write(os.path.join(ROOT, "src/assets/PlaytestArtV2", wid + ".model.json"), held)
        display = {"className": "Model", "attributes": {
            "Family": family, "Tier": 1, "WeaponId": wid, "Special": False, "ArtVersion": 2},
            "properties": {"WorldPivotData": {"OptionalCFrame": {"position": [0, 0, 0], "orientation": rot()}}},
            "children": [part_json(b, 1.5, True) for b in parts]}
        write(os.path.join(ROOT, "src/assets/PlaytestDisplaysV2", wid + ".model.json"), display)
        report[wid] = len(parts)
    print(json.dumps(report))


if __name__ == "__main__":
    sys.exit(main())
