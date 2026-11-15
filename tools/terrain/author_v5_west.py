"""V5 CP-B authoring: Beach, Swamp and Jungle kits + region data, and their seams.

Called by tools/terrain/author_v5.py (register(A) adds kits and regions to A's tables before it
writes them), so one command regenerates everything: python3 -I tools/terrain/author_v5.py
Coordinates come from Studio Edit reads: region_floors.json, lane_mask_west.txt (precise lanes from
SurveyLanes.edit.luau) and the burrow/gate points in v5_site.py. Every terrain shape and every
collidable prop is checked here against the lane mask and the protected 12-stud pads.
"""
import math
import v5_site as S

A = None  # author_v5 module namespace (box, kit, T, C, G, PS, FILL, n)
PROBLEMS = []


def check_rect(label, x0, z0, x1, z1, margin=6, pad=18):
    if not S.rect_lane_clear(x0, z0, x1, z1, margin):
        PROBLEMS.append(f"{label}: within {margin} of a lane")
    for name, (bx, bz) in S.BURROWS.items():
        dx = max(x0 - bx, 0, bx - x1)
        dz = max(z0 - bz, 0, bz - z1)
        if math.hypot(dx, dz) < pad:
            PROBLEMS.append(f"{label}: within {pad} of burrow {name}")


def layers_west(x0, z0, x1, z1, heights, inset_x0=0, inset_x1=0, inset_z0=0, inset_z1=0):
    """Stepped stack: layer k shrinks each side by its inset * k."""
    return [(x0 + inset_x0 * k, z0 + inset_z0 * k, x1 - inset_x1 * k, z1 - inset_z1 * k, h) for k, h in enumerate(heights)]


def plateau(layers, cliff, top):
    out = []
    for i, (x0, z0, x1, z1, y1) in enumerate(layers):
        out.append(A.T(x0, A.G, z0, x1, A.FILL(y1), z1, top if i == len(layers) - 1 else cliff))
    return out


def pool(x0, z0, x1, z1, bed):
    """Sunken water: rock bed, carve, one full water cell (surface about -2)."""
    return ([A.T(x0 - 2, -12, z0 - 2, x1 + 2, -8, z1 + 2, bed)],
            [{"min": [x0, -8, z0], "max": [x1, 0, z1]}],
            [{"min": [x0, -8, z0], "max": [x1, -4, z1]}])


def ground_fills(key, material):
    out = []
    for cx, cz, sx, sz in S.FLOORS[key]:
        x0, x1, z0, z1 = cx - sx / 2, cx + sx / 2, cz - sz / 2, cz + sz / 2
        out.append(A.T(x0 - 8, -8, z0 - 8, x1 + 8, A.G, z1 + 8, material))
    return out


def seam_line(axis, fixed, a0, a1, inside_sign, inside_mat, outside_mat):
    """16-stud stepped patches alternating across a straight region boundary (both sides)."""
    out = []
    for i, a in enumerate(range(int(a0), int(a1), 16)):
        b = min(a + 16, a1)
        if i % 2 == 0:  # neighbour material reaching into this region
            lo, hi = (fixed, fixed + 16) if inside_sign > 0 else (fixed - 16, fixed)
            mat = outside_mat
        else:  # this region's material reaching into the neighbour
            lo, hi = (fixed - 16, fixed) if inside_sign > 0 else (fixed, fixed + 16)
            mat = inside_mat
        if axis == "x":  # boundary is x = fixed, line runs along z
            out.append(A.T(lo, -8, a, hi, A.G, b, mat))
        else:
            out.append(A.T(a, -8, lo, b, A.G, hi, mat))
    return out


# Outer map walls kept until CP-D (EV2_Run_01..04 shells, Studio read 9 Nov 2026): north z -654..-646,
# south z 522..562 (40 thick), west x -747..-739. Nothing is placed inside them.
# The island rim's ledges reach x -732 / z -644 (RIM_REACH), so props stand clear of those.
WALLS = [(-760, -660, 240, -638), (-760, 518, 240, 570), (-760, -660, -726, 570)]


def grid_spots(key, step, lane_margin, exclude, protect=20, offset=(0, 0)):
    """Staggered grid inside a region, off lanes, off protected pads and outside exclusion rects."""
    pts = []
    exclude = list(exclude) + WALLS
    xs = [x for cx, cz, sx, sz in S.FLOORS[key] for x in (cx - sx / 2, cx + sx / 2)]
    zs = [z for cx, cz, sx, sz in S.FLOORS[key] for z in (cz - sz / 2, cz + sz / 2)]
    row = 0
    z = min(zs) + 10 + offset[1]
    while z < max(zs) - 6:
        x = min(xs) + 10 + offset[0] + (step / 2 if row % 2 else 0)
        while x < max(xs) - 6:
            ok = S.region_at(x, z) == key and S.region_at(x + 8, z) == key and S.region_at(x - 8, z) == key \
                and S.region_at(x, z + 8) == key and S.region_at(x, z - 8) == key
            if ok and S.lane_distance(x, z, lane_margin + 4) >= lane_margin and S.protected_distance(x, z) >= protect:
                if not any(x0 - 4 <= x <= x1 + 4 and z0 - 4 <= z <= z1 + 4 for x0, z0, x1, z1 in exclude):
                    pts.append((round(x), round(z)))
            x += step
        z += step * 0.86
        row += 1
    return pts


def lane_glow(key, step=64):
    """Flush glow tiles on lane cells (staggered grid), >=16 from burrows, >=34 from gates."""
    pts = []
    xs = [x for cx, cz, sx, sz in S.FLOORS[key] for x in (cx - sx / 2, cx + sx / 2)]
    zs = [z for cx, cz, sx, sz in S.FLOORS[key] for z in (cz - sz / 2, cz + sz / 2)]
    for j, z in enumerate(range(int(min(zs)) + 12, int(max(zs)), step)):
        for x in range(int(min(xs)) + 12 + (step // 2 if j % 2 else 0), int(max(xs)), step):
            # Snap to the nearest lane cell within 20 studs.
            best = None
            for dx in range(-20, 21, 4):
                for dz in range(-20, 21, 4):
                    px, pz = x + dx, z + dz
                    if S.is_lane(px, pz) and S.is_lane(px + 6, pz) and S.is_lane(px - 6, pz) \
                            and S.is_lane(px, pz + 6) and S.is_lane(px, pz - 6) and S.region_at(px, pz) == key:
                        d = dx * dx + dz * dz
                        if best is None or d < best[0]:
                            best = (d, px, pz)
            if best:
                _, px, pz = best
                # Tiles reach ~10 studs from their centre, so 26 keeps the 12-stud burrow pads clear.
                if all(math.hypot(px - bx, pz - bz) >= 26 for bx, bz in S.BURROWS.values()) and \
                        all(math.hypot(px - gx, pz - gz) >= 34 for gx, gz in S.GATES.values()):
                    pts.append((px, pz))
    return pts


def slide_kit(name, drop, angle=30):
    """Stepped-free straight chute from the kit origin (top) down local -X at `angle` degrees."""
    box = A.box
    run = drop / math.tan(math.radians(angle))
    length = math.hypot(drop, run)
    ang = angle
    cx, cy = -run / 2, -drop / 2
    half = length / 2
    A.kit(name, [
        box("Chute", cx - half, cy - 0.5, -3, cx + half, cy + 0.5, 3, "slide", walkable=True, rot=(0, 0, ang)),
        box("WallN", cx - half, cy + 0.5, -3.8, cx + half, cy + 2.5, -3, "rim", rot=(0, 0, ang)),
        box("WallS", cx - half, cy + 0.5, 3, cx + half, cy + 2.5, 3.8, "rim", rot=(0, 0, ang)),
        box("GlowN", cx - half, cy + 2.5, -3.8, cx + half, cy + 2.9, -3, "glow", emissive=True, rot=(0, 0, ang)),
        box("GlowS", cx - half, cy + 2.5, 3, cx + half, cy + 2.9, 3.8, "glow", emissive=True, rot=(0, 0, ang)),
        box("StartLip", -1, -0.6, -3.8, 1, 0.4, 3.8, "rim", walkable=True),
        box("Landing", -run - 10, -drop, -4, -run + 2, -drop + 0.6, 4, "glow", emissive=True, walkable=True),
        box("LandingJoint", -run - 10.5, -drop, -4.5, -run + 2.5, -drop + 0.3, 4.5, "rim"),
    ])
    return run


# ============================================================================ kits
def beach_kits():
    box, kit = A.box, A.kit

    def lighthouse_arch():
        b = []
        # Two stepped rock legs (local x < 0 and > 0), 5 tiers of 8, each tier inset 1.
        for side in (-1, 1):
            for t in range(5):
                y0, y1 = 8 * t, 8 * t + 8
                outer, inner, half = 42 - t, 16 + t * 0.5, 16 - t
                x0, x1 = (-outer, -inner) if side < 0 else (inner, outer)
                role = "cliff" if t % 2 == 0 else "cliffLight"
                if side < 0 and t < 2:
                    # Hollow west leg (secret grotto): four walls, doorway on local -Z (world west, map edge).
                    b += [box(f"LegA{t}N", x0, y0, -half, x1, y1, -half + 4, role, relief=["Front"]) if t else
                          box(f"LegA{t}NL", x0, y0, -half, -31, y1, -half + 4, role, relief=["Front"]),
                          box(f"LegA{t}S", x0, y0, half - 4, x1, y1, half, role, relief=["Back"]),
                          box(f"LegA{t}W", x0, y0, -half + 4, x0 + 4, y1, half - 4, role, relief=["Left"]),
                          box(f"LegA{t}E", x1 - 4, y0, -half + 4, x1, y1, half - 4, role, relief=["Right"])]
                    if t == 0:
                        b.append(box("LegA0NR", -25, y0, -half, x1, y1, -half + 4, role, relief=["Front"]))
                        b.append(box("LegA0Door", -31, 6, -half, -25, y1, -half + 4, role))
                else:
                    b.append(box(f"Leg{'A' if side < 0 else 'B'}{t}", x0, y0, -half, x1, y1, half, role,
                                 relief=["Front", "Back", "Left" if side < 0 else "Right"]))
            b.append(box(f"Joint{'A' if side < 0 else 'B'}", (-42.5 if side < 0 else 15.5), 0, -16.5,
                         (-15.5 if side < 0 else 42.5), 1, 16.5, "rim"))
        b.append(box("GrottoRoof", -38, 15.4, -12, -20, 16, 12, "rim"))
        # Staircase curve of the opening, then the lintel and cap.
        b += [box("CurveA1", -14, 32, -12, -9, 40, 12, "cliff"), box("CurveB1", 9, 32, -12, 14, 40, 12, "cliff"),
              box("CurveA2", -9, 37, -12, -4, 40, 12, "cliffLight"), box("CurveB2", 4, 37, -12, 9, 40, 12, "cliffLight"),
              box("Lintel", -40, 40, -12, 40, 48, 12, "cliff", relief=True),
              box("LintelBand", -40.5, 39.4, -12.5, 40.5, 40, 12.5, "rim"),
              box("Cap", -34, 48, -10, 34, 52, 10, "cliffLight", relief=True)]
        # Coral and starfish glow on the legs (Beach glow accent).
        for i, (x, y, z) in enumerate([(-42.6, 6, -6), (-42.6, 14, 5), (42, 9, -4), (42, 20, 6), (-30, 28, -13.6), (28, 26, 13)]):
            b.append(box(f"Coral{i}", x, y, z, x + 0.6 if abs(x) > 40 else x + 3, y + 3, z + (3 if abs(x) > 40 else 0.6),
                         "glow", emissive=True))
        # Lighthouse on the cap: plinth, five striped bands, gallery, lamp room, roof.
        b += [box("Plinth", -9, 52, -9, 9, 55, 9, "white", relief=True), box("PlinthJoint", -9.5, 52, -9.5, 9.5, 52.6, 9.5, "rim")]
        for k in range(5):
            h = 7 - 0.5 * k
            b.append(box(f"Band{k}", -h, 55 + 8 * k, -h, h, 63 + 8 * k, h, "white" if k % 2 == 0 else "stripe",
                         relief=["Front", "Back", "Left", "Right"]))
        for k in (1, 3):
            y = 57 + 8 * k
            b += [box(f"WindowE{k}", 6.4 - 0.5 * k, y, -1.2, 7.2 - 0.5 * k, y + 3, 1.2, "lamp", emissive=True),
                  box(f"WindowW{k}", -7.2 + 0.5 * k, y, -1.2, -6.4 + 0.5 * k, y + 3, 1.2, "lamp", emissive=True)]
        b += [box("Gallery", -9, 95, -9, 9, 96.6, 9, "rim"),
              box("GalleryEdge", -9.4, 96.6, -9.4, 9.4, 97.2, 9.4, "stripe")]
        for i, (x, z) in enumerate([(-8, -8), (7, -8), (-8, 7), (7, 7)]):
            b.append(box(f"RailPost{i}", x, 97.2, z, x + 1, 99, z + 1, "rim"))
        b += [box("Lamp", -4.5, 97.2, -4.5, 4.5, 104, 4.5, "lamp", emissive=True),
              box("Roof1", -6, 104, -6, 6, 107, 6, "stripe", relief=True),
              box("Roof2", -3.5, 107, -3.5, 3.5, 109, 3.5, "stripe"),
              box("Beacon", -1.2, 109, -1.2, 1.2, 113, 1.2, "lamp", emissive=True)]
        return b

    kit("Beach_LighthouseArch", lighthouse_arch())
    kit("Beach_PalmTree", [
        box("BaseJoint", -2.5, 0, -2.5, 2.5, 0.8, 2.5, "rim"),
        box("Trunk1", -1.5, 0, -1.5, 1.5, 6, 1.5, "trunk", relief=["Front", "Back"]),
        box("Trunk2", -1, 6, -1.4, 2, 12, 1.4, "trunkLight"),
        box("Trunk3", 0, 12, -1.3, 3, 18, 1.3, "trunk", relief=["Front", "Back"]),
        box("Trunk4", 1, 18, -1.2, 4, 23, 1.2, "trunkLight"),
        box("CocoA", 1, 21.6, -2, 2.8, 23.4, -0.2, "trunkDark"),
        box("CocoB", 2.4, 21.6, 0.2, 4.2, 23.4, 2, "trunkDark"),
        box("Core", 0, 23, -2, 5, 25, 2, "leaf", relief=True),
        box("FrondN", 0.5, 24, -11, 4.5, 25, -2, "leaf", relief=True),
        box("FrondNTip", 1, 22.6, -14, 4, 24, -10, "leafDark"),
        box("FrondS", 0.5, 24, 2, 4.5, 25, 11, "leaf", relief=True),
        box("FrondSTip", 1, 22.6, 10, 4, 24, 14, "leafDark"),
        box("FrondE", 5, 24, -2, 14, 25, 2, "leafLight", relief=True),
        box("FrondETip", 13, 22.6, -1.5, 17, 24, 1.5, "leaf"),
        box("FrondW", -9, 24, -2, 0, 25, 2, "leafLight", relief=True),
        box("FrondWTip", -12, 22.6, -1.5, -8, 24, 1.5, "leaf"),
    ])
    kit("Beach_Coral", [
        box("Base", -3, 0, -3, 3, 1, 3, "cliffLight", relief=True),
        box("Joint", -3.3, 0, -3.3, 3.3, 0.4, 3.3, "rim"),
        box("BranchA", -0.6, 1, -0.6, 0.6, 6, 0.6, "glow", emissive=True),
        box("BranchA2", 0.6, 4, -0.4, 2.4, 5, 0.4, "glow", emissive=True),
        box("BranchA3", 1.6, 5, -0.4, 2.4, 7, 0.4, "glow", emissive=True),
        box("BranchB", -2.4, 1, 0.6, -1.4, 4.5, 1.6, "glowAlt", emissive=True),
        box("BranchB2", -2.4, 4.5, 0.6, -0.6, 5.3, 1.6, "glowAlt", emissive=True),
        box("BranchC", 1, 1, -2.2, 2, 3.5, -1.2, "glow", emissive=True),
        box("Starfish", 1.2, 1, 1, 2.8, 1.4, 2.6, "accent"),
    ])
    kit("Beach_Umbrella", [
        box("Pole", -0.4, 0, -0.4, 0.4, 9, 0.4, "white"),
        box("Canopy1", -6, 8, -6, 6, 8.8, 6, "umbrella", relief=True),
        box("Canopy2", -4, 8.8, -4, 4, 9.6, 4, "white", relief=True),
        box("Canopy3", -2, 9.6, -2, 2, 10.2, 2, "umbrella"),
        box("Tip", -0.5, 10.2, -0.5, 0.5, 11, 0.5, "rim"),
        box("Towel", 2, 0, -5, 6, 0.2, 3, "umbrellaAlt"),
        box("TowelStripe", 2, 0.2, -1.5, 6, 0.25, -0.5, "white"),
        box("Ball", -4, 0, 3, -2.4, 1.6, 4.6, "glow", emissive=True),
    ])

    def shipwreck():
        b = [box("KeelJoint", -24.5, -0.2, -7.5, 21.5, 0.8, 7.5, "rim"),
             box("HullLow", -18, -2, -6, 16, 4, 6, "trunk", relief=["Front", "Back"]),
             box("HullMid", -18, 4, -7, 14, 8, 7, "trunkLight", relief=["Front", "Back"]),
             box("StripeN", -18, 3.6, -7.2, 14, 4.4, -7, "accent"),
             box("StripeS", -18, 3.6, 7, 14, 4.4, 7.2, "accent"),
             box("Bow1", 16, -2, -4.5, 21, 6, 4.5, "trunk"),
             box("Bow2", 14, 6, -5, 19, 9, 5, "trunkLight"),
             box("Bow3", 21, 0, -2.5, 25, 7, 2.5, "trunkLight"),
             box("Bowsprit", 24, 6.4, -0.6, 32, 7.6, 0.6, "trunkDark", rot=(0, 0, 14)),
             box("Stern", -24, -2, -6, -18, 12, 6, "trunk", relief=["Left"]),
             box("SternCabin", -24, 12, -5, -17, 15, 5, "trunkDark"),
             box("SternLamp", -24.4, 8, -3, -24, 10, 3, "lamp", emissive=True),
             box("Deck", -18, 8, -6, 14, 8.6, 6, "trunkDark", walkable=True),
             box("RailN", -18, 8.6, -7, 14, 9.6, -6, "rim"),
             box("RailS", -18, 8.6, 6, 14, 9.6, 7, "rim"),
             box("HoleN", -6, 0, -7.4, 2, 5, -7, "rim"),
             box("HoleGlow", -4, 1, -7.6, 0, 3, -7.4, "glow", emissive=True),
             box("Barrel", -13, -0.5, 8, -9.6, 3.5, 11.4, "trunk", relief=True),
             box("BarrelBand", -13.2, 1.4, 7.8, -9.4, 2, 11.6, "rim"),
             box("Crate", 8, -0.5, 8, 12, 3.5, 12, "trunkLight", relief=True)]
        # Broken mast leaning over the sea side, with its torn sail (both rotated about the mast).
        ang = -18
        a = math.radians(ang)
        for slot, (h, w, t, role) in {"Mast": (0, 2, 2, "trunkDark"), "Sail": (3, 12, 0.4, "white"),
                                      "SailStripe": (6.6, 12.2, 0.5, "stripe")}.items():
            cx, cy = -h * math.sin(a), 19.3 + h * math.cos(a)
            sx, sy = (w, 21.4) if slot == "Mast" else (w, 9 if slot == "Sail" else 1.4)
            if slot == "Mast":
                b.append(box(slot, cx - 1, cy - sy / 2, -1, cx + 1, cy + sy / 2, 1, role, rot=(0, 0, ang)))
            else:
                b.append(box(slot, cx - sx / 2, cy - sy / 2, 1, cx + sx / 2, cy + sy / 2, 1 + t, role, rot=(0, 0, ang)))
        return b

    kit("Beach_Shipwreck", shipwreck())

    def dock():
        b = []
        for i in range(5):
            x1 = -12 * i
            b.append(box(f"Deck{i}", x1 - 12, 0, -4, x1, 1, 4, "trunk" if i % 2 == 0 else "trunkLight", relief=True, walkable=True))
            b.append(box(f"PostN{i}", x1 - 12.6, -8, -4.8, x1 - 11.4, 2, -3.6, "trunkDark"))
            b.append(box(f"PostS{i}", x1 - 12.6, -8, 3.6, x1 - 11.4, 2, 4.8, "trunkDark"))
        b += [box("End", -72, 0, -8, -60, 1, 8, "trunk", relief=True, walkable=True),
              box("EndJoint", -72.5, -8, -8.5, -71.5, 1.6, 8.5, "rim"),
              box("LampPost", -70, 1, -7, -69, 7, -6, "trunkDark"),
              box("Lamp", -70.6, 7, -7.6, -68.4, 9, -5.4, "glow", emissive=True),
              box("Bollard", -64, 1, 6, -62.6, 2.4, 7.4, "rim")]
        return b

    kit("Beach_Dock", dock())
    kit("Secret_Chest", [
        box("Joint", -2.4, 0, -1.8, 2.4, 0.3, 1.8, "rim"),
        box("Chest", -2, 0, -1.4, 2, 2.2, 1.4, "trunk", relief=["Front"]),
        box("Lid", -2.1, 2.2, -1.5, 2.1, 3, 1.5, "trunkDark"),
        box("Lock", -0.4, 1.4, -1.6, 0.4, 2.4, -1.4, "accent"),
        box("Coins", -1.6, 3, -1, 1.6, 3.4, 1, "accent", emissive=True),
        box("Gem", -0.5, 3.4, -0.5, 0.5, 4.4, 0.5, "glow", emissive=True),
    ])


def swamp_kits():
    box, kit = A.box, A.kit

    def sunken_tree():
        b = []
        # Leaning stepped trunk: seven 10-high segments, each shifted +x and narrower. Two hollow at the base.
        for s in range(7):
            y0, y1 = -4 + 10 * s, 6 + 10 * s
            h, ox = 14 - 1.2 * s, 2.2 * s
            role = "trunk" if s % 2 == 0 else "trunkDark"
            if s < 2:
                walls = [("N", ox - h, -h, ox + h, -h + 4, ["Front"]), ("S", ox - h, h - 4, ox + h, h, ["Back"]),
                         ("W", ox - h, -h + 4, ox - h + 4, h - 4, ["Left"]), ("E", ox + h - 4, -h + 4, ox + h, h - 4, ["Right"])]
                for tag, x0, z0, x1, z1, rel in walls:
                    if s == 0 and tag == "N":  # doorway in the north wall (local -Z)
                        b += [box("Seg0NL", x0, y0, z0, ox - 3, y1, z1, role, relief=rel),
                              box("Seg0NR", ox + 3, y0, z0, x1, y1, z1, role, relief=rel),
                              box("Seg0Door", ox - 3, 4, z0, ox + 3, y1, z1, role)]
                    else:
                        b.append(box(f"Seg{s}{tag}", x0, y0, z0, x1, y1, z1, role, relief=rel))
            else:
                b.append(box(f"Seg{s}", ox - h, y0, -h, ox + h, y1, h, role, relief=["Front", "Back", "Left", "Right"]))
        b.append(box("HollowRoof", 0, 15, -9, 6, 16, 9, "rim"))
        b.append(box("HollowFloor", -8, -0.6, -8, 10, -0.2, 8, "trunkDark", walkable=True))
        # Broken crown teeth at the top.
        ox, top = 2.2 * 6, 66
        for i, (dx, dz, hh) in enumerate([(-5, -5, 8), (4, -4, 5), (-4, 4, 6), (5, 5, 9)]):
            b.append(box(f"Tooth{i}", ox + dx - 2.5, top, dz - 2.5, ox + dx + 2.5, top + hh, dz + 2.5, "trunkDark"))
        # Dead branches stepping out and up, with drooping moss.
        for i, (y, dx, dz) in enumerate([(38, 1, 0), (46, -1, 0.3), (54, 0.2, 1)]):
            bx = 2.2 * 4 + dx * 10
            if abs(dx) > 0.5:
                x0, x1 = (bx, bx + 26) if dx > 0 else (bx - 26, bx)
                b.append(box(f"Branch{i}", x0, y, -2, x1, y + 4, 2, "trunk"))
                tip = x1 if dx > 0 else x0 - 4
                b.append(box(f"BranchTip{i}", tip, y + 4, -1.5, tip + 4, y + 12, 1.5, "trunkDark"))
                b.append(box(f"Moss{i}", (x0 + x1) / 2 - 2, y - 7, -1.2, (x0 + x1) / 2 + 2, y, 1.2, "leafDark"))
            else:
                b.append(box(f"Branch{i}", bx - 2, y, 8, bx + 2, y + 4, 32, "trunk"))
                b.append(box(f"BranchTip{i}", bx - 1.5, y + 4, 28, bx + 1.5, y + 12, 32, "trunkDark"))
                b.append(box(f"Moss{i}", bx - 1.2, y - 7, 18, bx + 1.2, y, 22, "leafDark"))
        # Ragged mossy crown around the broken top, with hanging moss curtains.
        cx = 2.2 * 6
        for i, (x0, z0, x1, z1, y0, y1, role) in enumerate([
                (cx - 20, -14, cx + 4, 6, 60, 66, "leafDark"), (cx - 4, -8, cx + 22, 16, 62, 68, "leaf"),
                (cx - 14, 4, cx + 10, 22, 58, 64, "leafDark"), (cx - 10, -20, cx + 12, -6, 64, 70, "leaf"),
                (cx - 8, -6, cx + 10, 10, 68, 73, "leafLight")]):
            b.append(box(f"Crown{i}", x0, y0, z0, x1, y1, z1, role, relief=True))
        for i, (x, z, top) in enumerate([(cx - 19, -10, 60), (cx + 20, 10, 62), (cx - 12, 20, 58), (cx + 8, -19, 64), (cx - 6, 21, 58)]):
            b.append(box(f"MossCurtain{i}", x - 1, top - 12, z - 1, x + 1, top, z + 1, "leafDark"))
            b.append(box(f"MossGlow{i}", x - 1.2, top - 13.2, z - 1.2, x + 1.2, top - 12, z + 1.2, "glow", emissive=True))
        # Lime shelf fungi up the trunk (glow).
        for i, (y, side) in enumerate([(10, "E"), (18, "W"), (26, "S"), (34, "E"), (42, "N"), (50, "W"), (58, "S"), (30, "N")]):
            s = (y + 4) // 10
            h, ox = 14 - 1.2 * s, 2.2 * s
            x, z = {"E": (ox + h, 0), "W": (ox - h - 5, 0), "S": (ox - 3, h), "N": (ox - 3, -h - 5)}[side]
            if side in ("E", "W"):
                b.append(box(f"Fungus{i}", x, y, -3, x + 5, y + 1.4, 3, "glow" if i % 2 == 0 else "glowAlt", emissive=True))
            else:
                b.append(box(f"Fungus{i}", x, y, z, x + 6, y + 1.4, z + 5, "glow" if i % 2 == 0 else "glowAlt", emissive=True))
        # Arching roots into the water.
        for i, a in enumerate(range(0, 360, 60)):
            r = math.radians(a + 20)
            cx, cz = math.cos(r) * 17, math.sin(r) * 17
            b.append(box(f"Root{i}", cx - 3, -4, cz - 3, cx + 3, 4, cz + 3, "trunk", relief=True))
            cx2, cz2 = math.cos(r) * 22, math.sin(r) * 22
            b.append(box(f"RootTip{i}", cx2 - 2, -4, cz2 - 2, cx2 + 2, 1, cz2 + 2, "trunkDark"))
        return b

    kit("Swamp_SunkenTree", sunken_tree())
    kit("Swamp_Boardwalk", [
        box("Deck", -12, 0, -3, 12, 0.8, 3, "trunk", relief=True, walkable=True),
        box("GapA", -6.2, 0.8, -3, -5.8, 0.85, 3, "trunkDark"),
        box("GapB", 5.8, 0.8, -3, 6.2, 0.85, 3, "trunkDark"),
        box("PostNW", -12.4, -8, -3.6, -11.2, 3, -2.4, "trunkDark"),
        box("PostNE", 11.2, -8, -3.6, 12.4, 3, -2.4, "trunkDark"),
        box("PostSW", -12.4, -8, 2.4, -11.2, 3, 3.6, "trunkDark"),
        box("PostSE", 11.2, -8, 2.4, 12.4, 3, 3.6, "trunkDark"),
        box("RopeN", -12, 2.4, -3.2, 12, 2.7, -2.8, "trunkLight"),
        box("RopeS", -12, 2.4, 2.8, 12, 2.7, 3.2, "trunkLight"),
        box("Lamp", 11.1, 3, -3.7, 12.5, 4.4, -2.3, "glow", emissive=True),
    ])
    kit("Swamp_LilyPad", [
        box("Pad", -3.5, 0, -3.5, 3.5, 0.5, 3.5, "leaf", relief=True, walkable=True),
        box("Notch", -0.6, 0.5, -3.5, 0.6, 0.55, 0, "leafDark"),
        box("Rim", -3.8, -0.2, -3.8, 3.8, 0.1, 3.8, "glow", emissive=True),
        box("Bud", 1.4, 0.5, 1.2, 2.4, 1.5, 2.2, "flower", emissive=True),
    ])

    def bog_hut():
        return [
            box("Floor", -8, 0, -8, 8, 0.6, 8, "trunkDark", walkable=True),
            box("WallW", -7, 0.6, -7, -6, 9, 7, "trunk", relief=["Left"]),
            box("WallE", 6, 0.6, -7, 7, 9, 7, "trunk", relief=["Right"]),
            box("WallS", -6, 0.6, 6, 6, 9, 7, "trunk", relief=["Back"]),
            box("WallNL", -6, 0.6, -7, -2, 9, -6, "trunk", relief=["Front"]),
            box("WallNR", 2, 0.6, -7, 6, 9, -6, "trunk", relief=["Front"]),
            box("DoorTop", -2, 6.5, -7, 2, 9, -6, "trunk"),
            box("DoorGlow", -2, 0.6, -5.6, 2, 6.5, -5.4, "glow", emissive=True),
            box("WindowE", 6.9, 4, -2, 7.2, 6.5, 2, "glow", emissive=True),
            box("WindowW", -7.2, 4, -2, -6.9, 6.5, 2, "glowAlt", emissive=True),
            box("Eave", -9, 9, -9, 9, 10, 9, "rim"),
            box("Roof1", -8.5, 10, -8.5, 8.5, 12.5, 8.5, "leafDark", relief=True),
            box("Roof2", -6, 12.5, -6, 6, 14.5, 6, "leaf", relief=True),
            box("Roof3", -3, 14.5, -3, 3, 16, 3, "leafDark"),
            box("Chimney", 3, 12, 3, 5, 19, 5, "cliff"),
            box("ChimneyGlow", 3.2, 19, 3.2, 4.8, 19.8, 4.8, "glowAlt", emissive=True),
            box("Lantern", -9.4, 7, -9.4, -8, 9, -8, "glow", emissive=True),
        ]

    kit("Swamp_BogHut", bog_hut())
    kit("Swamp_DeadTree", [
        box("Joint", -2.4, 0, -2.4, 2.4, 0.6, 2.4, "rim"),
        box("Trunk1", -1.8, 0, -1.8, 1.8, 7, 1.8, "trunkDark", relief=["Front", "Back"]),
        box("Trunk2", -1, 7, -1.5, 2, 13, 1.5, "trunk"),
        box("Trunk3", 0, 13, -1.2, 2.4, 19, 1.2, "trunkDark"),
        box("BranchE", 2, 11, -0.8, 8, 12.6, 0.8, "trunk"),
        box("BranchETip", 7, 12.6, -0.6, 8.4, 16, 0.6, "trunkDark"),
        box("BranchW", -6, 15, -0.7, 0, 16.4, 0.7, "trunk"),
        box("Moss", -4, 11.6, -0.6, -2.6, 15, 0.6, "leafDark"),
        box("Fungus", 1.8, 5, -1.6, 4.4, 5.8, 1.6, "glow", emissive=True),
    ])

    def reeds():
        b = [box("Clump", -3, 0, -2, 3, 1, 2, "leafDark", relief=True)]
        for i, (x, z, h) in enumerate([(-2, -1, 7), (-0.5, 0.6, 9), (1, -0.8, 8), (2.2, 0.8, 6), (0.2, -1.4, 5.5)]):
            b.append(box(f"Stalk{i}", x - 0.25, 1, z - 0.25, x + 0.25, h, z + 0.25, "leaf"))
            b.append(box(f"Head{i}", x - 0.5, h - 2.4, z - 0.5, x + 0.5, h - 0.4, z + 0.5, "trunk"))
        return b

    kit("Swamp_Reeds", reeds())
    kit("Swamp_FungiStump", [
        box("Joint", -3.4, 0, -3.4, 3.4, 0.6, 3.4, "rim"),
        box("Stump", -3, 0, -3, 3, 5, 3, "trunkDark", relief=["Front", "Back", "Left", "Right"]),
        box("Rings", -2.4, 5, -2.4, 2.4, 5.3, 2.4, "trunkLight"),
        box("ShelfA", 3, 2, -2, 6, 2.8, 2, "glow", emissive=True),
        box("ShelfB", -6, 3.2, -1.5, -3, 4, 1.5, "glowAlt", emissive=True),
        box("ShelfC", -1.5, 1.2, 3, 1.5, 2, 5.5, "glow", emissive=True),
        box("Cap", -1, 5.3, -1, 1, 7, 1, "glowAlt", emissive=True),
    ])


def jungle_kits():
    box, kit = A.box, A.kit

    def ruin_tower():
        b = []
        # Eight stepped tiers (10 high), dark joint band under each lip, Sun lanterns at the corners and
        # hanging vines on the faces; a stair runs up the local +Z face.
        for t in range(8):
            h = 22 - 2 * t
            y0 = 10 * t
            b.append(box(f"Tier{t}", -h, y0, -h, h, y0 + 10, h, "ruin" if t % 2 == 0 else "ruinLight",
                         relief=["Front", "Back", "Left", "Right"]))
            b.append(box(f"Band{t}", -h - 0.4, y0 + 9, -h - 0.4, h + 0.4, y0 + 10, h + 0.4, "rim"))
            if t % 2 == 1:
                for i, (sx, sz) in enumerate([(-1, -1), (1, -1), (-1, 1), (1, 1)]):
                    x, z = sx * (h - 1.2), sz * (h - 1.2)
                    b.append(box(f"Lantern{t}_{i}", x - 1.2, y0 + 10, z - 1.2, x + 1.2, y0 + 12.4, z + 1.2, "glow", emissive=True))
            if t < 6:
                for i, sx in enumerate((-0.55, 0.3)):
                    x = sx * h
                    b.append(box(f"VineW{t}_{i}", -h - 0.6, y0 + 2 + i * 2, x - 1, -h, y0 + 10, x + 1, "vine"))
                    b.append(box(f"VineE{t}_{i}", h, y0 + 1 + i * 3, -x - 1, h + 0.6, y0 + 10, -x + 1, "vine"))
        for k in range(8):  # front stair (decor), one flight per tier
            h = 22 - 2 * k
            b.append(box(f"Stair{k}", -4, 10 * k, h, 4, 10 * k + 10, h + 2, "ruinDark", relief=["Top"]))
        # Shrine crown on top (y 80): pillars, roof, Sun idol.
        b += [box("ShrineFloor", -7, 80, -7, 7, 81, 7, "ruinDark"),
              box("PillarA", -6, 81, -6, -3, 92, -3, "ruinLight", relief=["Front"]),
              box("PillarB", 3, 81, -6, 6, 92, -3, "ruinLight", relief=["Front"]),
              box("PillarC", -6, 81, 3, -3, 92, 6, "ruinLight", relief=["Back"]),
              box("PillarD", 3, 81, 3, 6, 92, 6, "ruinLight", relief=["Back"]),
              box("Idol", -2.5, 81, -2.5, 2.5, 88, 2.5, "glow", emissive=True),
              box("Roof", -8, 92, -8, 8, 95, 8, "ruin", relief=True),
              box("RoofTop", -5, 95, -5, 5, 98, 5, "ruinLight"),
              box("Crown", -2, 98, -2, 2, 104, 2, "glow", emissive=True)]
        return b

    kit("Jungle_RuinTower", ruin_tower())
    kit("Jungle_TreeTall", [
        box("BaseJoint", -4, 0, -4, 4, 0.8, 4, "rim"),
        box("ButtressN", -1.2, 0, -5, 1.2, 5, -2, "trunk"),
        box("ButtressS", -1.2, 0, 2, 1.2, 5, 5, "trunk"),
        box("ButtressE", 2, 0, -1.2, 5, 4, 1.2, "trunk"),
        box("Trunk", -2, 0, -2, 2, 26, 2, "trunk", relief=["Front", "Back", "Left", "Right"]),
        box("CanopyLow", -11, 18, -11, 11, 22, 11, "leafDark", relief=True),
        box("CanopyMid", -8, 22, -8, 8, 26, 8, "leaf", relief=True),
        box("CanopyTop", -5, 26, -5, 5, 30, 5, "leafLight", relief=True),
        box("LumpE", 9, 20, -4, 14, 24, 3, "leaf"),
        box("LumpW", -14, 21, -3, -9, 25, 4, "leaf"),
        box("VineA", -10, 10, 6, -9, 18, 7, "vine"),
        box("VineB", 8, 12, -9, 9, 18, -8, "vine"),
        box("Fruit", 5, 16, 5, 7, 18, 7, "glow", emissive=True),
    ])
    kit("Jungle_Fern", [
        box("Core", -1, 0, -1, 1, 2.5, 1, "leafDark"),
        box("FrondN", -1, 1.6, -6, 1, 2.6, -1, "leaf", relief=True),
        box("FrondS", -1, 1.6, 1, 1, 2.6, 6, "leaf", relief=True),
        box("FrondE", 1, 1.2, -1, 6, 2.2, 1, "leafLight", relief=True),
        box("FrondW", -6, 1.2, -1, -1, 2.2, 1, "leafLight", relief=True),
        box("Flower", -0.6, 2.5, -0.6, 0.6, 3.5, 0.6, "flower", emissive=True),
    ])

    def vine_arch():
        b = []
        for side in (-1, 1):
            x0, x1 = (-29, -24) if side < 0 else (24, 29)
            b += [box(f"Pillar{side}", x0, 0, -3, x1, 26, 3, "ruin", relief=["Front", "Back"]),
                  box(f"PillarJoint{side}", x0 - 0.5, 0, -3.5, x1 + 0.5, 1, 3.5, "rim"),
                  box(f"Lantern{side}", (x0 + x1) / 2 - 1.4, 31, -1.4, (x0 + x1) / 2 + 1.4, 34, 1.4, "glow", emissive=True)]
        b += [box("Lintel", -30, 26, -3.5, 30, 31, 3.5, "ruinLight", relief=True),
              box("LintelBand", -30.4, 25.4, -3.9, 30.4, 26, 3.9, "rim")]
        for i, x in enumerate([-18, -9, 0, 10, 19]):
            low = 19 + (i % 3) * 1.5
            b.append(box(f"Vine{i}", x - 0.6, low, -0.6, x + 0.6, 25.4, 0.6, "vine"))
            b.append(box(f"Bloom{i}", x - 1, low - 1.2, -1, x + 1, low, 1, "flower" if i % 2 else "glow", emissive=True))
        return b

    kit("Jungle_VineArch", vine_arch())
    kit("Jungle_RuinBlock", [
        box("Joint", -5, 0, -4, 5, 0.6, 4, "rim"),
        box("BlockA", -4.5, 0, -3.5, 1.5, 6, 3.5, "ruin", relief=["Front", "Top"]),
        box("BlockB", -3.5, 6, -2.5, 0.5, 10, 2.5, "ruinLight", relief=["Front"]),
        box("Broken", -3.5, 10, -2.5, -1.5, 11.5, 0, "ruinLight"),
        box("Fallen", 2, 0, -2, 7, 3, 2.5, "ruinLight", relief=True),
        box("Moss", -4.5, 6, -3.5, 1.5, 6.6, 3.5, "vine"),
        box("Glyph", -2.5, 2, -3.7, -0.5, 4, -3.5, "glow", emissive=True),
    ])
    kit("Jungle_Waterfall", [
        # Falls down the cliff face from the kit origin (top lip) to the pool at local y -28.
        box("Lip", -9, -0.6, -1, 9, 0.6, 2, "ruinDark"),
        box("SheetTop", -8, -10, -1.6, 8, 0, -0.4, "water", emissive=True),
        box("SheetMid", -7.5, -20, -2.4, 7.5, -10, -1.2, "water", emissive=True),
        box("SheetLow", -7, -29, -3.2, 7, -20, -2, "water", emissive=True),
        box("FoamA", -6, -12, -2.8, -4, -6, -2.4, "foam", emissive=True),
        box("FoamB", 3, -18, -3.4, 5, -13, -3, "foam", emissive=True),
        box("FoamC", -2, -27, -4.2, 1, -22, -3.8, "foam", emissive=True),
        box("SplashA", -9, -29.6, -8, -3, -28, -3, "foam", emissive=True),
        box("SplashB", 3, -29.6, -7, 9, -28.4, -3, "foam", emissive=True),
        box("RockL", -12, -29, -3, -8, -18, 1, "ruin", relief=True),
        box("RockR", 8, -29, -3, 12, -22, 1, "ruin", relief=True),
    ])


# ============================================================================ regions
def beach():
    T, C, G = A.T, A.C, A.G
    terr = ground_fills("Beach", "Sand")
    for x0, z0 in [(-740, -630), (-560, -580), (-420, -520), (-300, -640), (-736, -160), (-560, 40), (-720, 120), (-600, -470)]:
        terr.append(T(x0, -8, z0, x0 + 24, G, z0 + 20, "Sandstone"))
    excl = []
    # High: Faro bluff (7 x 4 studs) east-face slide; the arch stands north of it on the beach.
    bluff = layers_west(-745, -552, -685, -488, [4, 8, 12, 16, 20, 24, 28], inset_x1=6, inset_z0=2, inset_z1=2)
    terr += plateau(bluff, "Limestone", "Sandstone")
    check_rect("Beach bluff", -745, -552, -685, -488)
    excl.append((-748, -556, -660, -484))
    # Mid: dunes (4 and 8), Limestone faces, Sandstone tops.
    dunes = [((-500, -640, -430, -590), [4, 8]), ((-340, -648, -282, -600), [4, 8]), ((-560, -524, -506, -486), [4]),
             ((-470, -522, -412, -484), [4]), ((-326, -530, -284, -490), [4]), ((-704, -470, -668, -424), [4]),
             ((-596, -470, -548, -430), [4]), ((-592, -166, -546, -110), [4, 8]), ((-596, 92, -548, 150), [4]),
             ((-740, 90, -684, 160), [4, 8]), ((-678, -150, -656, -26), [4])]
    for (x0, z0, x1, z1), hs in dunes:
        ls = layers_west(x0, z0, x1, z1, hs, 6, 6, 6, 6)
        terr += plateau(ls, "Limestone", "Sandstone")
        check_rect(f"Beach dune {x0},{z0}", x0, z0, x1, z1, margin=6)
        excl.append((x0, z0, x1, z1))
    carves, water = [], []
    for x0, z0, x1, z1 in [(-598, -350, -562, -310), (-572, -276, -532, -238), (-560, -206, -530, -178)]:
        bed, cv, wt = pool(x0, z0, x1, z1, "Limestone")
        terr += bed
        carves += cv
        water += wt
        check_rect(f"Beach pool {x0},{z0}", x0, z0, x1, z1, margin=10)
        excl.append((x0 - 6, z0 - 6, x1 + 6, z1 + 6))
    # Lagoon at the west edge, under the dock (the sea itself arrives with the CP-D island edge).
    bed, cv, wt = pool(-755, -340, -690, -252, "Limestone")
    terr += bed
    carves += cv
    water += wt
    check_rect("Beach lagoon", -755, -340, -690, -252, margin=10)
    excl.append((-756, -344, -684, -248))
    excl += [(-720, -656, -660, -556), (-590, -80, -526, -20), (-690, -306, -676, -286)]  # arch, wreck, dock root

    slide_top = (-721, 28, -520)
    clusters = []
    mix = ["Beach_PalmTree", "Beach_PalmTree", "Forest_Rock", "Beach_Umbrella", "Beach_PalmTree", "Forest_Rock", "Beach_PalmTree", "Beach_Umbrella"]
    spots = grid_spots("Beach", 38, 14, excl + [(-640, -660, -600, -540)])
    clusters += [C(mix[i % len(mix)], x, G, z, (i * 37) % 360) for i, (x, z) in enumerate(spots)]
    # Coral around the tide pools and the lagoon edge.
    for i, (x, z) in enumerate([(-604, -330), (-556, -352), (-580, -302), (-526, -258), (-578, -244), (-552, -232),
                                (-566, -190), (-524, -200), (-686, -330), (-686, -262), (-700, -246)]):
        clusters.append(C("Beach_Coral", x, G, z, i * 40, 1.6))
    clusters += [C("Lane_GlowTiles", x, 0, z, (i * 37) % 360) for i, (x, z) in enumerate(lane_glow("Beach"))]
    clusters += [C("Beach_Shipwreck", -558, G, -50, 20, 1.2, "Wreck of the Mozzarella"),
                 C("Beach_Dock", -684, G, -296, 0, 0.75, "BeachDock")]  # 54 long: ends at x -738, clear of the west wall
    check_rect("Beach dock start", -688, -304, -680, -288, margin=6)

    return {
        "key": "Beach", "version": 1, "floorFolder": "Beach", "replacesLegacy": ["REGION_BEACH_"],
        "palette": {
            "ground": "#FFF07A", "secondary": "#FFF4CD", "cliff": "#E5A520", "cliffLight": "#FFCF45",
            "rim": "#1D2133", "glow": "#FF3D9E", "glowAlt": "#FF87C8", "lamp": "#BFF8FF",
            "trunk": "#C9894A", "trunkDark": "#8A5528", "trunkLight": "#E5A520",
            "leaf": "#2FBF5A", "leafLight": "#8DFF3A", "leafDark": "#3BD16F",
            "white": "#F7F5FC", "stripe": "#F0283C", "umbrella": "#2EE9FF", "umbrellaAlt": "#46A7FF",
            "flower": "#FF3D9E", "sign": "#FF3D9E", "slide": "#2EE9FF", "bounce": "#FF3D9E", "accent": "#FFD447",
        },
        "materials": {"ground": "Sand", "secondary": "Sandstone", "cliff": "Limestone"},
        "terraces": terr, "wedges": [], "rocks": [{"center": [-626, 1, -470], "radius": 2.5, "material": "Limestone"},
                                                 {"center": [-520, 1, 170], "radius": 3, "material": "Limestone"}],
        "carves": carves, "water": water, "rims": [], "clusters": clusters,
        "landmark": C("Beach_LighthouseArch", -690, G, -603, 90, 1, "Faro Bellissimo"),  # north leg ends at z -645
        "pois": [
            {"name": "Faro Bellissimo", "center": [-690, -596], "radius": 56},
            {"name": "Cannoli Coral Pools", "center": [-565, -262], "radius": 64},
            {"name": "Wreck of the Mozzarella", "center": [-558, -50], "radius": 44},
        ],
        "signs": [
            dict(C("POI_Sign", -660, G, -440, 90, 1, "Faro Bellissimo"), text="FARO BELLISSIMO"),
            dict(C("POI_Sign", -598, G, -284, 90, 1, "Cannoli Coral Pools"), text="CANNOLI CORAL POOLS"),
            dict(C("POI_Sign", -598, G, -86, 90, 1, "Wreck of the Mozzarella"), text="WRECK OF THE MOZZARELLA"),
        ],
        "secrets": [
            # Inside the hollow west arch leg (doorway faces the map edge); arch yaw 90 maps local x -> world -z.
            # Local (x, z) -> world (z, -x) at yaw 90, so the hollow leg's centre (-29, 0) sits at z -603 + 29.
            C("Secret_Shrine", -690, G, -574, 0, 1.4, "ArchGrotto"),
            C("Secret_Chest", -728, -8, -296, 90, 1.2, "DockChest"),  # on the lagoon bed under the dock end
        ],
        "toys": [
            dict(C("Toy_Slide_28", slide_top[0], slide_top[1], slide_top[2], 180, 1, "FaroSlide"), type="Slide",
                 params={"Boost": 36, "Downhill": "@Vector3.new(1, 0, 0)"}),
            dict(C("Toy_BouncePad", -452, G, -560, 0, 1, "DuneBounce"), type="BouncePad", params={"LaunchSpeed": 72}),
            dict(C("Toy_BouncePad", -568, G, -136 + 50, 0, 1, "WreckBounce"), type="BouncePad", params={"LaunchSpeed": 72}),
        ],
        "seamTerraces": (seam_line("x", -507, -474, 202, -1, "Sand", "LeafyGrass")
                         + seam_line("z", -474, -507, -267, -1, "Sand", "LeafyGrass")
                         + seam_line("x", -267, -654, -474, -1, "Sand", "LeafyGrass")),
    }


def swamp():
    T, C, G = A.T, A.C, A.G
    terr = ground_fills("Swamp", "Mud")
    for x0, z0 in [(-740, 270), (-600, 212), (-430, 330), (-560, 490), (-720, 470), (-330, 214)]:
        terr.append(T(x0, -8, z0, x0 + 24, G, z0 + 20, "Ground"))
    excl = []
    # High: Risotto Rock stack (6 x 4) with the Bog Hut on top; sheer east face carries the slide.
    stack = layers_west(-566, 210, -500, 262, [4, 8, 12, 16, 20, 24], inset_x0=6, inset_z0=2, inset_z1=2)
    terr += plateau(stack, "Slate", "Ground")
    check_rect("Swamp stack", -566, 210, -500, 262, margin=6)
    excl.append((-570, 206, -440, 266))
    for (x0, z0, x1, z1), hs in [((-350, 314, -282, 376), [4, 8]), ((-740, 210, -680, 262), [4]), ((-532, 392, -510, 448), [4])]:
        terr += plateau(layers_west(x0, z0, x1, z1, hs, 6, 6, 6, 6), "Slate", "Ground")
        check_rect(f"Swamp mound {x0},{z0}", x0, z0, x1, z1)
        excl.append((x0, z0, x1, z1))
    carves, water = [], []
    # West bog with a mist island (unexcavated) reached by lily pads.
    # (island (-730, 350)..(-708, 372) stays solid ground)
    bog = [(-745, 338, -664, 350), (-745, 372, -664, 444), (-745, 350, -730, 372), (-708, 350, -664, 372)]
    terr.append(T(-747, -12, 336, -662, -8, 446, "Slate"))
    for x0, z0, x1, z1 in bog:
        carves.append({"min": [x0, -8, z0], "max": [x1, 0, z1]})
        water.append({"min": [x0, -8, z0], "max": [x1, -4, z1]})
    check_rect("Swamp west bog", -745, 338, -664, 444, margin=12)
    excl.append((-748, 330, -660, 448))
    # (The Sunken Spaghetti Tree stands in the west bog; the south strip z 522+ is inside the outer wall.)

    clusters = []
    mix = ["Swamp_DeadTree", "Swamp_Reeds", "Swamp_FungiStump", "Forest_MushroomBig", "Swamp_DeadTree", "Swamp_Reeds", "Forest_Rock"]
    spots = grid_spots("Swamp", 24, 14, excl)  # denser than the Beach: low visibility, many silhouettes
    clusters += [C(mix[i % len(mix)], x, G, z, (i * 41) % 360) for i, (x, z) in enumerate(spots)]
    # Reeds along both bog shores.
    for i, (x, z) in enumerate([(-658, 344), (-658, 436), (-700, 328), (-736, 452), (-668, 452), (-596, 500), (-700, 500)]):
        clusters.append(C("Swamp_Reeds", x, G, z, i * 50, 1.3))
    # Lily-pad hop to the mist island, and pads around the sunken tree.
    pad_y = -1.75
    for i, x in enumerate([-670, -679, -688, -697, -704]):
        clusters.append(C("Swamp_LilyPad", x, pad_y, 361 + (2 if i % 2 else -2), i * 33, 1, f"LilyHop{i}"))
    # Pads around the tree; the last three step from the boardwalk end to the hollow door (north face, z ~388).
    for i, (x, z) in enumerate([(-672, 440), (-740, 438), (-676, 382), (-690, 386), (-700, 380), (-710, 382)]):
        clusters.append(C("Swamp_LilyPad", x, pad_y, z, i * 47, 1.1))
    # Boardwalk from the main lane's west shore out over the bog towards the tree (two segments along z 410).
    for i, x in enumerate([-670, -682]):
        clusters.append(C("Swamp_Boardwalk", x, -0.5, 410 + 12 * i - 6, 0, 1, f"Boardwalk{i}"))
    clusters += [C("Lane_GlowTiles", x, 0, z, (i * 37) % 360) for i, (x, z) in enumerate(lane_glow("Swamp"))]
    clusters.append(C("Swamp_BogHut", -518, 24, 236, 90, 1, "Risotto Bog Hut"))
    slide_top = (-500, 24, 236)
    check_rect("Swamp slide landing", -470, 230, -446, 242, margin=8)
    return {
        "key": "Swamp", "version": 1, "floorFolder": "Swamp", "replacesLegacy": ["REGION_SWAMP_"],
        "palette": {
            "ground": "#14C79F", "secondary": "#0E8F73", "cliff": "#2A2F45", "cliffLight": "#5D6788",
            "rim": "#1D2133", "glow": "#8DFF3A", "glowAlt": "#DCFF2B",
            "trunk": "#8A5528", "trunkDark": "#2A3A20", "trunkLight": "#C9894A",
            "leaf": "#72E65B", "leafLight": "#C8FF6A", "leafDark": "#2FBF5A",
            "white": "#F7F5FC", "flower": "#FF87C8", "sign": "#0E8F73", "slide": "#8DFF3A", "bounce": "#8DFF3A",
            "accent": "#FFD447",
        },
        "materials": {"ground": "Mud", "secondary": "Ground", "cliff": "Slate"},
        "terraces": terr, "wedges": [], "rocks": [], "carves": carves, "water": water, "rims": [],
        "clusters": clusters,
        "landmark": C("Swamp_SunkenTree", -714, G, 410, 0, 1.3, "Sunken Spaghetti Tree"),  # in the west bog; top y ~96
        "pois": [
            {"name": "Sunken Spaghetti Tree", "center": [-706, 412], "radius": 56},
            {"name": "Risotto Bog Hut", "center": [-530, 236], "radius": 44},
            {"name": "Lily-Pad Linguine Hop", "center": [-690, 374], "radius": 50},
        ],
        "signs": [
            dict(C("POI_Sign", -656, G, 452, 90, 1, "Sunken Spaghetti Tree"), text="SUNKEN SPAGHETTI TREE"),
            dict(C("POI_Sign", -592, G, 266, 0, 1, "Risotto Bog Hut"), text="RISOTTO BOG HUT"),
            dict(C("POI_Sign", -656, G, 326, 90, 1, "Lily-Pad Linguine Hop"), text="LILY-PAD LINGUINE HOP"),
        ],
        "secrets": [
            C("Secret_Shrine", -714, -0.7, 410, 0, 1.2, "SunkenTreeHollow"),
            C("Secret_Shrine", -719, G, 361, 45, 1.3, "MistIslandCrystals"),
            C("Forest_MushroomRing", -719, G, 361, 0, 0.7, "MistIslandRing"),
        ],
        "toys": [
            dict(C("Toy_Slide_24", slide_top[0], slide_top[1], slide_top[2], 180, 1, "BogHutSlide"), type="Slide",
                 params={"Boost": 36, "Downhill": "@Vector3.new(1, 0, 0)"}),
            dict(C("Toy_BouncePad", -470, G, 330, 0, 1, "BogBounce"), type="BouncePad", params={"LaunchSpeed": 72}),
        ],
        "seamTerraces": (seam_line("z", 202, -747, -507, 1, "Mud", "Sand")
                         + seam_line("z", 202, -507, -267, 1, "Mud", "LeafyGrass")),
    }


def jungle():
    T, C, G = A.T, A.C, A.G
    terr = ground_fills("Jungle", "Asphalt")
    excl = []
    # High: the Pistachio cliff in the SE corner, a 7-step giant stair rising east (9-stud treads, 4-stud
    # risers) up to the ruin tower; its sheer north face (z 404) carries the waterfall, the cave behind it
    # and the north slide. It stops at the outer wall (z 522) and the Glitch Zone seam (x 229).
    cliff = [(130 + 9 * k, 404, 229, 530, 4 * (k + 1)) for k in range(7)]
    for x0, z0, x1, z1, h in cliff:
        terr.append(T(x0, G, z0, x1, A.FILL(h), z1, "Ice"))
        terr.append(T(x0, A.FILL(h) - 4, z0 + 4, x0 + 9 if h < 28 else x1, A.FILL(h), z1, "Asphalt"))  # tread
    check_rect("Jungle cliff", 130, 404, 229, 522)
    excl.append((126, 400, 232, 530))
    excl.append((184, 336, 204, 404))  # north slide and its landing
    # Mid: canopy terraces between the two north-south lanes.
    canopy = [(-184, 320, -66, 442, 4), (-180, 324, -70, 438, 8), (-170, 336, -96, 412, 12), (-166, 340, -100, 408, 16),
              (-156, 352, -120, 392, 20), (-152, 356, -124, 388, 24)]
    terr += plateau(canopy, "Ice", "Asphalt")
    # Each exposed tier tread gets a green cap so the stack reads as stepped canopy, not a dark slab.
    for x0, z0, x1, z1, h in canopy[:-1]:
        terr.append(T(x0, A.FILL(h) - 4, z0, x1, A.FILL(h), z1, "Asphalt"))
    check_rect("Jungle canopy", -184, 320, -66, 442)
    excl.append((-188, 316, -62, 446))
    terr += plateau([(-360, 392, -244, 428, 4)], "Ice", "Asphalt")
    check_rect("Jungle ruin terrace", -360, 392, -244, 428, margin=6)
    excl.append((-364, 388, -240, 432))
    carves, water = [], []
    bed, cv, wt = pool(198, 382, 230, 396, "Ice")
    terr += bed
    carves += cv
    water += wt
    check_rect("Jungle falls pool", 198, 382, 230, 396, margin=10)
    excl.append((192, 376, 232, 404))
    # Secret: cave behind the waterfall, into the sheer north face of the top steps.
    carves.append({"min": [206, -0.5, 398], "max": [222, 10, 424]})

    clusters = []
    mix = ["Jungle_TreeTall", "Jungle_Fern", "Jungle_Fern", "Jungle_TreeTall", "Jungle_RuinBlock", "Jungle_Fern", "Forest_Lantern"]
    spots = grid_spots("Jungle", 32, 14, excl)
    clusters += [C(mix[i % len(mix)], x, G, z, (i * 43) % 360) for i, (x, z) in enumerate(spots)]
    # Canopy trees on the terraces (by tier height), ruin blocks on the ruin terrace.
    def tier_height(x, z):
        return max([h for x0, z0, x1, z1, h in canopy if x0 + 2 <= x <= x1 - 2 and z0 + 2 <= z <= z1 - 2] or [0])

    for i, (x, z) in enumerate([(-180, 322), (-74, 324), (-180, 440), (-72, 436), (-104, 374), (-162, 404), (-130, 382)]):
        y = tier_height(x, z)
        clusters.append(C("Jungle_TreeTall", x, y - 0.5, z, i * 51, 1.2 if y < 20 else 1))
    for i, (x, z) in enumerate([(-344, 410), (-310, 400), (-276, 416), (-252, 402)]):
        clusters.append(C("Jungle_RuinBlock", x, 3.5, z, i * 70, 1.3))
    # Vine-hung arches over the lanes, and Sun lanterns along them.
    clusters += [C("Jungle_VineArch", -216, G, 344, 0, 1, "VineArchWest"), C("Jungle_VineArch", -216, G, 424, 0, 1, "VineArchWest2"),
                 C("Jungle_VineArch", -18, G, 396, 0, 1, "VineArchEast"), C("Jungle_VineArch", 100, G, 292, 90, 1, "VineArchBand")]
    for e in clusters:
        if e["kit"] == "Jungle_VineArch":
            ax, _, az = e["position"]
            for side in (-1, 1):
                if e["yaw"] == 0:
                    check_rect(f"arch pillar {e['name']}", ax + side * 24 - (5 if side < 0 else 0), az - 3,
                               ax + side * 24 + (5 if side > 0 else 0), az + 3, margin=4, pad=12)
                else:
                    check_rect(f"arch pillar {e['name']}", ax - 3, az - side * 24 - (5 if side > 0 else 0),
                               ax + 3, az - side * 24 + (5 if side < 0 else 0), margin=4, pad=12)
    clusters += [C("Lane_GlowTiles", x, 0, z, (i * 37) % 360) for i, (x, z) in enumerate(lane_glow("Jungle"))]
    clusters.append(C("Jungle_Waterfall", 214, 28 - 0.5, 400, 0, 1, "PistachioFalls"))  # clear of the bevelled face
    slide_top = (194, 28, 404)
    return {
        "key": "Jungle", "version": 1, "floorFolder": "Jungle", "replacesLegacy": ["REGION_JUNGLE_"],
        "palette": {
            "ground": "#1EA845", "secondary": "#45D11E", "cliff": "#2A3A20", "cliffLight": "#5D6788",
            "ruin": "#5D6788", "ruinLight": "#9AA6C8", "ruinDark": "#2A2F45",
            "rim": "#1D2133", "glow": "#FFD447", "glowAlt": "#FFF0A3", "vine": "#45D11E",
            "trunk": "#8A5528", "trunkDark": "#2A2F45", "trunkLight": "#C9894A",
            "leaf": "#2FBF5A", "leafLight": "#C8FF6A", "leafDark": "#1F7A2E",
            "white": "#F7F5FC", "flower": "#FF3D9E", "sign": "#2FBF5A", "slide": "#FFD447", "bounce": "#FF8A2A",
            "accent": "#FF3D9E", "water": "#2EE9FF", "foam": "#BFF8FF",
        },
        "materials": {"ground": "Asphalt", "cliff": "Ice"},
        "terraces": terr, "wedges": [], "rocks": [], "carves": carves, "water": water, "rims": [],
        "clusters": clusters,
        "landmark": C("Jungle_RuinTower", 207, 27.5, 470, 90, 1, "Torre Tortellini"),  # stair faces west, down the cliff
        "pois": [
            {"name": "Torre Tortellini", "center": [200, 466], "radius": 50},
            {"name": "Pistachio Falls", "center": [214, 390], "radius": 36},
            {"name": "Cannelloni Canopy", "center": [-126, 380], "radius": 64},
        ],
        "signs": [
            dict(C("POI_Sign", 112, G, 430, 90, 1, "Torre Tortellini"), text="TORRE TORTELLINI"),
            dict(C("POI_Sign", 176, G, 370, 0, 1, "Pistachio Falls"), text="PISTACHIO FALLS"),
            dict(C("POI_Sign", -60, G, 452, 0, 1, "Cannelloni Canopy"), text="CANNELLONI CANOPY"),
        ],
        "secrets": [
            C("Secret_Shrine", 214, G, 414, 180, 1.3, "FallsCave"),
            C("Secret_Chest", -146, 23.5, 362, 0, 1.2, "CanopyIdolChest"),
        ],
        "toys": [
            dict(C("Toy_Slide_28", slide_top[0], slide_top[1], slide_top[2], -90, 1, "CliffSlide"), type="Slide",
                 params={"Boost": 36, "Downhill": "@Vector3.new(0, 0, -1)"}),
            dict(C("Toy_BouncePad", -60, G, 360, 0, 1, "CanopyBounce"), type="BouncePad", params={"LaunchSpeed": 72}),
            dict(C("Toy_BouncePad", 112, G, 404, 0, 1, "CliffBounce"), type="BouncePad", params={"LaunchSpeed": 72}),
        ],
        "seamTerraces": (seam_line("z", 202, -267, 229, 1, "Asphalt", "Salt")
                         + seam_line("x", -267, 202, 382, 1, "Asphalt", "Mud")
                         + seam_line("z", 382, -507, -267, 1, "Asphalt", "Mud")
                         + seam_line("x", -507, 382, 562, 1, "Asphalt", "Mud")),
    }


# Same idea as the Forest's KIT_SCALE: regions are ~500 studs across, so props are scaled up to read.
KIT_SCALE = {"Beach_PalmTree": 1.5, "Beach_Umbrella": 1.2, "Swamp_DeadTree": 1.7, "Swamp_Reeds": 1.3,
             "Swamp_FungiStump": 1.5, "Jungle_TreeTall": 1.4, "Jungle_Fern": 1.6, "Jungle_RuinBlock": 1.3}


# ---------------------------------------------------------------- island rim (pulled forward from CP-D)
# A stepped mountain ridge stands just inside the outer walls of the built regions, so players see
# region-coloured cliffs instead of the wall (W11). Studio read (9 Nov): the perimeter NavigationShells
# are visible but CanCollide = false, and the real boundary is the invisible CliffRun_Collider inside
# each EV2 cliff-art model. Under the flag the covered shells and cliff-art visuals only turn
# transparent (hidesLegacy); colliders, CanCollide and CanQuery never change. The rim's faces stand
# flush behind the collider faces (west -739, north -646, south 522), and its ledges stop short of the
# natural-spawn band (RIM_REACH), so no ground a brainrot can spawn on today is covered.
# Nothing on it is reachable: every step is 12+ studs high.
RIM_LOOK = {  # body, stratum bands, cap
    "Beach": ("Limestone", "Sandstone", "Sand"),
    "Forest": ("Rock", "LeafyGrass", "LeafyGrass"),
    "Swamp": ("Slate", "Ground", "Mud"),
    "Jungle": ("Asphalt", "Ice", "Asphalt"),  # bright body, dark-moss far ridge
}
# (edge, inner face, outer limit, along from, along to, region by along coordinate, covered EV2 art)
RIM_EDGES = [
    ("W", -740, -776, -680, 592, lambda a: "Beach" if a < 202 else "Swamp"),
    ("N", -648, -680, -776, 236, lambda a: "Beach" if a < -267 else "Forest"),
    ("S", 524, 592, -776, 236, lambda a: "Swamp" if a < -507 else "Jungle"),
]
RIM_ART = {
    "Beach": ["EV2_Run_03_Cliff_01", "EV2_Run_03_Cliff_02", "EV2_Run_03_Cliff_03",
              "EV2_Run_01_Cliff_01", "EV2_Run_01_Cliff_02"],
    "Swamp": ["EV2_Run_03_Cliff_04", "EV2_Run_03_Cliff_05", "EV2_Run_02_Cliff_01"],
    "Forest": ["EV2_Run_01_Cliff_03", "EV2_Run_01_Cliff_04"],
    "Jungle": ["EV2_Run_02_Cliff_02", "EV2_Run_02_Cliff_03", "EV2_Run_02_Cliff_04"],
}
# Ledge depths per edge. Natural spawns sample the inner 80% of each floor part
# (DevelopmentBrainrotSpawner.naturalCandidatePosition): west band x >= -723, north z >= -636; the
# south band runs into the 40-thick collider (z 522), where spawns already fail the clearance check.
RIM_LEDGES = {"W": (8, 4), "N": (4,), "S": ()}
RIM_REACH = {"W": -732, "N": -644, "S": 524}  # innermost coordinate any rim piece may reach
RIM_SHELLS = {"Beach": ["EV2_Run_03", "EV2_Run_01"], "Swamp": ["EV2_Run_02"]}
# Hero landmarks next to the rim: the ridge drops to a low saddle behind them so they keep the skyline.
RIM_HEROES = [(-690, -603), (-714, 410), (207, 470), (-218, -620)]


def _rim_box(edge, face, depth_in, outer, a0, a1, y0, y1, mat):
    """Box spanning along [a0, a1] from `outer` to `depth_in` studs inside the face."""
    if edge == "W":
        return A.T(outer, y0, a0, face + depth_in, y1, a1, mat)
    if edge == "N":
        return A.T(a0, y0, outer, a1, y1, face + depth_in, mat)
    return A.T(a0, y0, face - depth_in, a1, y1, outer, mat)  # S: inside is -z


def _rim_rect(edge, face, depth, a0, a1):
    if edge == "W":
        return face, a0, face + depth, a1
    if edge == "N":
        return a0, face, a1, face + depth
    return a0, face - depth, a1, face


def _rim_clear(rect, features, boxes):
    x0, z0, x1, z1 = rect
    if not S.rect_lane_clear(x0, z0, x1, z1, 8):
        return False
    for bx, bz in list(S.BURROWS.values()) + list(S.GATES.values()):
        if math.hypot(max(x0 - bx, 0, bx - x1), max(z0 - bz, 0, bz - z1)) < 30:
            return False
    for fx, fz in features:
        if x0 - 14 <= fx <= x1 + 14 and z0 - 14 <= fz <= z1 + 14:
            return False
    for bx0, bz0, bx1, bz1 in boxes:
        if bx0 < x1 + 4 and bx1 > x0 - 4 and bz0 < z1 + 4 and bz1 > z0 - 4:
            return False
    return True


def island_rim(regions):
    import random
    rng = random.Random(5150)
    feats, boxes = {}, {}
    for key, r in regions.items():
        feats[key] = [(e["position"][0], e["position"][2]) for g in ("clusters", "signs", "toys", "secrets")
                      for e in r.get(g, []) if "Lane_GlowTiles" != e.get("kit")]
        boxes[key] = [(c["min"][0], c["min"][2], c["max"][0], c["max"][2]) for c in r.get("carves", []) + r.get("water", [])]
        # Low terrain features (bluffs, cliffs) may meet the rim; spurs only avoid props, pools and lanes.
    added = {k: 0 for k in regions}
    rim_log = {}
    for edge, face, outer, a_lo, a_hi, owner in RIM_EDGES:
        a = a_lo
        while a < a_hi:
            width = rng.choice([16, 20, 24, 28, 32, 36])
            b = min(a + width, a_hi)
            key = owner((a + b) / 2)
            body, band, cap = RIM_LOOK[key]
            terr = regions[key].setdefault("rim", [])
            first = len(terr)
            cx, cz = ((face, (a + b) / 2) if edge == "W" else ((a + b) / 2, face))
            saddle = any(math.hypot(cx - hx, cz - hz) < 150 for hx, hz in RIM_HEROES)
            if saddle:
                top = rng.choice([56, 60, 64, 68])
                back = top + rng.choice([0, 4, 8])
            else:
                top = rng.choice([72, 80, 88, 96]) if rng.random() > 0.2 else rng.choice([104, 112])
                back = top + rng.choice([12, 16, 20, 28])  # second ridge line behind (layered skyline)
            terr.append(_rim_box(edge, face, 0, outer, a, b, A.G - 6, A.FILL(top) - 4, body))
            terr.append(_rim_box(edge, face, 0, face + (-12 if edge != "S" else 12), a, b,
                                 A.FILL(top) - 4, A.FILL(top), cap))
            if back > top:
                terr.append(_rim_box(edge, face - (12 if edge != "S" else -12), 0, outer, a, b,
                                     A.FILL(top) - 4, A.FILL(back) - 4, band))  # lighter far ridge
                terr.append(_rim_box(edge, face - (12 if edge != "S" else -12), 0, outer, a, b,
                                     A.FILL(back) - 4, A.FILL(back), cap))
            # One stratum band per chunk at a jittered height (reads as rock layers, not stripes).
            y = rng.choice([36, 44, 52]) if saddle else rng.choice([48, 56, 64])
            if rng.random() < 0.6:
                terr.append(_rim_box(edge, face, 0, face + (-4 if edge != "S" else 4), a, b,
                                     A.FILL(y), A.FILL(y + 4), band))
            # Foot ledge and middle tier in front of the face where the ground is free.
            for depth in RIM_LEDGES[edge]:
                rect = _rim_rect(edge, face, depth, a, b)
                if _rim_clear(rect, feats[key], boxes[key]):
                    h0 = rng.choice([12, 16, 20, 24])
                    h1 = min(top - 12, h0 + rng.choice([20, 28, 36]))
                    mid = max(4, depth // 2)
                    terr.append(_rim_box(edge, face, depth, face, a, b, A.G, A.FILL(h0) - 4, body))
                    terr.append(_rim_box(edge, face, depth, face, a, b, A.FILL(h0) - 4, A.FILL(h0), cap))
                    terr.append(_rim_box(edge, face, mid, face, a, b, A.G, A.FILL(h1) - 4, body))
                    terr.append(_rim_box(edge, face, mid, face, a, b, A.FILL(h1) - 4, A.FILL(h1), cap))
                    break
            rim_log.setdefault(key, []).extend((edge, t) for t in terr[first:])
            added[key] += 1
            a = b
    # Core loop guard: no rim piece reaches past RIM_REACH (see above).
    for key, rim_pieces in rim_log.items():
        for edge, t in rim_pieces:
            reach = t["max"][0] if edge == "W" else (t["max"][2] if edge == "N" else t["min"][2])
            if (edge == "S" and reach < RIM_REACH[edge]) or (edge != "S" and reach > RIM_REACH[edge]):
                PROBLEMS.append(f"{key} rim piece {t['min']}..{t['max']} reaches past {RIM_REACH[edge]}")
    for key in regions:
        regions[key]["hidesLegacy"] = RIM_SHELLS.get(key, []) + RIM_ART.get(key, [])
    return added


def register(author):
    global A
    A = author
    A.KIT_SCALE.update(KIT_SCALE)
    beach_kits()
    swamp_kits()
    jungle_kits()
    slide_kit("Toy_Slide_28", 28.5)
    slide_kit("Toy_Slide_24", 24.5)
    regions = {"Beach": beach(), "Swamp": swamp(), "Jungle": jungle()}
    for r in regions.values():
        keep = [e["position"] for e in r["signs"] + r["toys"] + r["secrets"]]
        r["clusters"] = [e for e in r["clusters"] if "name" in e or e["kit"] == "Lane_GlowTiles" or
                         all(math.hypot(e["position"][0] - p[0], e["position"][2] - p[2]) >= 14 for p in keep)]
    # Toy and sign lane checks (collidable/walkable parts).
    for key, r in regions.items():
        for t in r["toys"]:
            x, _, z = t["position"]
            if t["type"] == "BouncePad":
                check_rect(f"{key} {t['name']}", x - 5, z - 5, x + 5, z + 5, margin=6)
    rim_chunks = island_rim({"Forest": A.REGIONS["Forest"], **regions})
    print("island rim chunks: " + ", ".join(f"{k} {v}" for k, v in rim_chunks.items()))
    if PROBLEMS:
        raise SystemExit("author_v5_west checks failed:\n  " + "\n  ".join(PROBLEMS))
    A.REGIONS.update(regions)
    return regions
