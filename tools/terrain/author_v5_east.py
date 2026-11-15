"""V5 CP-C authoring: Arctic, Volcano and Glitch Zone kits + region data, their seams and the east
island rim.

Called by tools/terrain/author_v5.py after author_v5_west.register(), so one command regenerates
everything: python3 -I tools/terrain/author_v5.py
Coordinates come from Studio Edit reads (9 Nov 2026): region_floors.json, lane_mask_east.txt
(SurveyLanes.edit.luau with X0 224), the east burrows/gates in v5_site.py, the legacy Volcano massif
(REGION_VOLCANO_Hero, centre (497, -134), collider footprint 112 x 96) and the east perimeter colliders
(EV2_Run_04 x 701..709, EV2_Run_01 z -654..-646, EV2_Run_02 z 522..562).
Every terrain shape and every collidable prop is checked against the lane mask and protected pads.
"""
import math
import v5_site as S
import author_v5_west as W

A = None
PROBLEMS = []

# Outer walls and the rim ledges on the east side (rim faces: north -648, south 524, east 702; ledges
# reach z -644 / x 694). Nothing is placed inside them.
EAST_WALLS = [(220, -660, 760, -638), (220, 518, 760, 570), (690, -660, 760, 570)]
GATES = dict(S.GATES_EAST)


def check_rect(label, x0, z0, x1, z1, margin=6, pad=18):
    before = len(W.PROBLEMS)  # W.check_rect reports into the west list; carry its findings over
    W.check_rect(label, x0, z0, x1, z1, margin, pad)
    PROBLEMS.extend(W.PROBLEMS[before:])
    del W.PROBLEMS[before:]
    for name, (gx, gz) in GATES.items():
        if math.hypot(max(x0 - gx, 0, gx - x1), max(z0 - gz, 0, gz - z1)) < 30:
            PROBLEMS.append(f"{label}: within 30 of the {name} gate")


def protected_distance(x, z):
    d = S.protected_distance(x, z)
    for gx, gz in GATES.values():
        d = min(d, math.hypot(x - gx, z - gz) - 20)
    return d


def grid_spots(key, step, lane_margin, exclude, protect=20, offset=(0, 0)):
    """W.grid_spots with the east walls and east gates."""
    pts = []
    exclude = list(exclude) + EAST_WALLS
    xs = [x for cx, cz, sx, sz in S.FLOORS[key] for x in (cx - sx / 2, cx + sx / 2)]
    zs = [z for cx, cz, sx, sz in S.FLOORS[key] for z in (cz - sz / 2, cz + sz / 2)]
    row = 0
    z = min(zs) + 10 + offset[1]
    while z < max(zs) - 6:
        x = min(xs) + 10 + offset[0] + (step / 2 if row % 2 else 0)
        while x < max(xs) - 6:
            ok = all(S.region_at(x + dx, z + dz) == key for dx, dz in ((0, 0), (8, 0), (-8, 0), (0, 8), (0, -8)))
            if ok and S.lane_distance(x, z, lane_margin + 4) >= lane_margin and protected_distance(x, z) >= protect:
                if not any(x0 - 4 <= x <= x1 + 4 and z0 - 4 <= z <= z1 + 4 for x0, z0, x1, z1 in exclude):
                    pts.append((round(x), round(z)))
            x += step
        z += step * 0.86
        row += 1
    return pts


def lane_glow(key, step=64):
    return [(x, z) for x, z in W.lane_glow(key, step)
            if all(math.hypot(x - gx, z - gz) >= 34 for gx, gz in GATES.values())]


def stack(x0, z0, x1, z1, heights, cliff, top, **insets):
    ls = W.layers_west(x0, z0, x1, z1, heights, **insets)
    return W.plateau(ls, cliff, top), ls


# ============================================================================ kits
def arctic_kits():
    box, kit = A.box, A.kit

    def ice_spire():
        b = [box("PlinthJoint", -17, 0, -17, 17, 1, 17, "rim"),
             box("Plinth", -16, 0, -16, 16, 6, 16, "cliff", relief=["Front", "Back", "Left", "Right", "Top"])]
        # Ten stepped shaft tiers with a dark joint under each lip and one crystal sliver per tier.
        for t in range(10):
            h = 12.5 - 1.05 * t
            y0 = 6 + 9 * t
            ox = (1.2 if t % 3 == 1 else -1.2 if t % 3 == 2 else 0)
            b.append(box(f"Tier{t}", ox - h, y0, -h, ox + h, y0 + 9, h, "ice" if t % 2 == 0 else "iceLight",
                         relief=["Front", "Back", "Left", "Right"]))
            b.append(box(f"Joint{t}", ox - h - 0.3, y0 + 8.4, -h - 0.3, ox + h + 0.3, y0 + 9, h + 0.3, "rim"))
            side = t % 4
            if side == 0:
                b.append(box(f"Sliver{t}", ox + h, y0 + 1, -1.5, ox + h + 0.8, y0 + 8, 1.5, "glow", emissive=True))
            elif side == 1:
                b.append(box(f"Sliver{t}", ox - 1.5, y0 + 1, h, ox + 1.5, y0 + 8, h + 0.8, "glowAlt", emissive=True))
            elif side == 2:
                b.append(box(f"Sliver{t}", ox - h - 0.8, y0 + 1, -1.5, ox - h, y0 + 8, 1.5, "glow", emissive=True))
            else:
                b.append(box(f"Sliver{t}", ox - 1.5, y0 + 1, -h - 0.8, ox + 1.5, y0 + 8, -h, "glowAlt", emissive=True))
        # Crown: crystal cluster with a tall Sky point (glow) at about y 112.
        b += [box("CrownBase", -3.5, 96, -3.5, 3.5, 100, 3.5, "iceLight", relief=True),
              box("Crown", -2.5, 100, -2.5, 2.5, 108, 2.5, "glow", emissive=True),
              box("CrownTip", -1.2, 108, -1.2, 1.2, 114, 1.2, "glowAlt", emissive=True),
              box("CrownShardA", 1.5, 98, -1, 4, 105, 1, "glow", emissive=True, rot=(0, 0, -18)),
              box("CrownShardB", -4, 98, -1, -1.5, 104, 1, "glow", emissive=True, rot=(0, 0, 18)),
              box("CrownShardC", -1, 98, 1.5, 1, 103, 4, "glowAlt", emissive=True, rot=(18, 0, 0))]
        # Leaning side shards around the base (staircase silhouettes), each with a glowing tip.
        for i, a in enumerate(range(20, 380, 60)):
            r = math.radians(a)
            cx, cz = math.cos(r) * 15, math.sin(r) * 15
            hgt = 18 + (i % 3) * 8
            tilt = 14 if i % 2 else -14
            b.append(box(f"Shard{i}", cx - 2.5, 4, cz - 2.5, cx + 2.5, 4 + hgt, cz + 2.5, "iceLight",
                         relief=["Front", "Back"], rot=(tilt * math.sin(r), 0, -tilt * math.cos(r))))
            b.append(box(f"ShardTip{i}", cx - 1.5, 4 + hgt, cz - 1.5, cx + 1.5, 8 + hgt, cz + 1.5, "glow",
                         emissive=True, rot=(tilt * math.sin(r), 0, -tilt * math.cos(r))))
        return b

    kit("Arctic_IceSpire", ice_spire())
    kit("Arctic_IcePine", [
        box("Joint", -3, 0, -3, 3, 0.6, 3, "rim"),
        box("Trunk", -1.2, 0, -1.2, 1.2, 5, 1.2, "trunk"),
        box("Tier1", -7, 4, -7, 7, 8, 7, "leaf", relief=True),
        box("Snow1", -7.4, 8, -7.4, 7.4, 9, 7.4, "snow"),
        box("Tier2", -5.5, 9, -5.5, 5.5, 13, 5.5, "leafDark", relief=True),
        box("Snow2", -5.9, 13, -5.9, 5.9, 14, 5.9, "snow"),
        box("Tier3", -4, 14, -4, 4, 18, 4, "leaf", relief=True),
        box("Snow3", -4.4, 18, -4.4, 4.4, 19, 4.4, "snow"),
        box("Tier4", -2.5, 19, -2.5, 2.5, 23, 2.5, "leafDark"),
        box("Top", -1, 23, -1, 1, 26, 1, "glow", emissive=True),
        box("Icicle", 6.4, 5.4, -0.5, 7.2, 8, 0.5, "glowAlt", emissive=True),
    ])
    kit("Arctic_Crystal", [
        box("Joint", -3.6, 0, -3.6, 3.6, 0.4, 3.6, "rim"),
        box("Base", -3.2, 0, -3.2, 3.2, 1.6, 3.2, "cliff", relief=True),
        box("CrystalA", -0.9, 1.6, -0.9, 0.9, 10, 0.9, "glow", emissive=True),
        box("CrystalB", 0.8, 1.6, -2.2, 2.2, 7, -0.8, "glowAlt", emissive=True, rot=(0, 0, -16)),
        box("CrystalC", -2.4, 1.6, 0.6, -1, 6, 2, "glow", emissive=True, rot=(16, 0, 0)),
        box("CrystalD", 0.6, 1.6, 1, 1.8, 4.5, 2.2, "glowAlt", emissive=True),
    ])
    kit("Arctic_SnowDrift", [
        box("Base", -7, 0, -4, 7, 1.5, 4, "snow", relief=True),
        box("Mid", -5, 1.5, -3, 4, 3, 2.5, "snow", relief=True),
        box("Top", -3, 3, -2, 1.5, 4.2, 1.5, "snowLight"),
        box("Shadow", -7.3, 0, -4.3, 7.3, 0.3, 4.3, "iceLight"),
        box("Sparkle", 2, 1.5, 2.6, 2.8, 2.3, 3.4, "glowAlt", emissive=True),
    ])

    def igloo():
        b = [box("Joint", -9.5, 0, -9.5, 9.5, 0.6, 9.5, "rim")]
        for k, (h, y0, y1) in enumerate([(9, 0, 3), (8.2, 3, 6), (7, 6, 8.5), (5.4, 8.5, 10.5), (3.4, 10.5, 12)]):
            b.append(box(f"Dome{k}", -h, y0, -h, h, y1, h, "snow" if k % 2 == 0 else "snowLight", relief=True))
        b += [box("Tunnel", -3.5, 0, -14, 3.5, 5.5, -8, "snowLight", relief=["Left", "Right", "Top"]),
              box("Door", -2, 0, -14.2, 2, 4.2, -14, "glow", emissive=True),
              box("Sign", -1, 6, -14.4, 1, 7, -14.2, "glowAlt", emissive=True)]
        return b

    kit("Arctic_Igloo", igloo())

    def snowman():
        return [box("Joint", -4, 0, -4, 4, 0.5, 4, "rim"),
                box("Base", -3.6, 0, -3.6, 3.6, 6, 3.6, "snow", relief=True),
                box("Middle", -2.6, 6, -2.6, 2.6, 10.5, 2.6, "snowLight", relief=True),
                box("Head", -1.9, 10.5, -1.9, 1.9, 14, 1.9, "snow"),
                box("Nose", -0.4, 12, -4, 0.4, 12.8, -1.9, "accent"),
                box("EyeL", -1.2, 12.8, -2, -0.6, 13.4, -1.9, "rim"),
                box("EyeR", 0.6, 12.8, -2, 1.2, 13.4, -1.9, "rim"),
                box("Scarf", -2.8, 10, -2.8, 2.8, 10.9, 2.8, "stripe"),
                box("ScarfTail", 1.6, 7.5, -3.1, 2.6, 10, -2.8, "stripe"),
                box("Hat", -2.2, 14, -2.2, 2.2, 14.6, 2.2, "rim"),
                box("HatTop", -1.4, 14.6, -1.4, 1.4, 17, 1.4, "rim"),
                box("HatBand", -1.5, 14.6, -1.5, 1.5, 15.2, 1.5, "glow", emissive=True),
                box("ButtonA", -0.4, 7.5, -2.7, 0.4, 8.3, -2.6, "glow", emissive=True),
                box("ButtonB", -0.4, 4, -3.7, 0.4, 4.8, -3.6, "glow", emissive=True)]

    kit("Arctic_Snowman", snowman())
    # Frozen pond cover: walkable translucent ice over the pool water, with glowing crack lines.
    sheet = box("Sheet", -27, 0, -19, 27, 0.6, 19, "iceSheet", walkable=True)
    sheet["transparency"] = 0.35
    kit("Arctic_IceSheet", [
        sheet,
        box("CrackA", -18, 0.6, -2, 6, 0.65, -1.4, "glowAlt", emissive=True),
        box("CrackB", 4, 0.6, -10, 4.6, 0.65, 8, "glowAlt", emissive=True),
        box("CrackC", -10, 0.6, 6, 14, 0.65, 6.6, "glowAlt", emissive=True),
        box("RimN", -27.5, -0.4, -19.5, 27.5, 0.7, -19, "rim"),
        box("RimS", -27.5, -0.4, 19, 27.5, 0.7, 19.5, "rim"),
    ])


def volcano_kits():
    box, kit = A.box, A.kit

    def pyramid():
        """The legacy Volcano massif re-made as a V4 stepped pyramid: same centre, taller (top ~114),
        footprint inside the legacy collider (104 x 84 vs 112 x 96). Tiers keep collision so the
        exterior reads solid and brainrots still cannot spawn inside it. No interior."""
        b = []
        for t in range(11):
            hx, hz, y0 = 52 - 4 * t, 42 - 3.5 * t, 8 * t
            b.append(box(f"Tier{t}", -hx, y0, -hz, hx, y0 + 8, hz, "cliff" if t % 2 == 0 else "cliffLight",
                         relief=["Front", "Back", "Left", "Right", "Top"], walkable=True))
            b.append(box(f"Lip{t}", -hx - 0.4, y0 + 7.2, -hz - 0.4, hx + 0.4, y0 + 8, hz + 0.4, "rim"))
            # Lava cracks (Neon) down two faces per tier, alternating sides.
            if t % 2 == 0:
                b.append(box(f"CrackN{t}", -hx * 0.4, y0, -hz - 0.6, -hx * 0.4 + 4, y0 + 7.2, -hz, "glow", emissive=True))
                b.append(box(f"CrackE{t}", hx, y0, hz * 0.3, hx + 0.6, y0 + 7.2, hz * 0.3 + 4, "glow", emissive=True))
                b.append(box(f"VeinN{t}", -hx * 0.4 + 4, y0 + 3, -hz - 0.6, -hx * 0.4 + 10, y0 + 4.2, -hz, "glow", emissive=True))
            else:
                b.append(box(f"CrackS{t}", hx * 0.35, y0, hz, hx * 0.35 + 4, y0 + 7.2, hz + 0.6, "glow", emissive=True))
                b.append(box(f"CrackW{t}", -hx - 0.6, y0, -hz * 0.4, -hx, y0 + 7.2, -hz * 0.4 + 4, "glow", emissive=True))
                b.append(box(f"VeinW{t}", -hx - 0.6, y0 + 3, -hz * 0.4 + 4, -hx, y0 + 4.2, -hz * 0.4 + 11, "glow", emissive=True))
            # Exterior stair up the west face (decor), one flight per tier.
            b.append(box(f"Stair{t}", -hx - 3, y0, -5, -hx, y0 + 4, 5, "cliffLight", relief=["Top"]))
            b.append(box(f"StairB{t}", -hx - 1.5, y0 + 4, -5, -hx, y0 + 8, 5, "cliffLight", relief=["Top"]))
        # Summit crater (y 88): four walls round a lava pool, a Neon beacon and ember caps.
        b += [box("CraterN", -12, 88, -7, 12, 94, -4.5, "cliff", relief=["Front"]),
              box("CraterS", -12, 88, 4.5, 12, 94, 7, "cliff", relief=["Back"]),
              box("CraterW", -12, 88, -4.5, -9, 93, 4.5, "cliffLight"),
              box("CraterE", 9, 88, -4.5, 12, 92, 4.5, "cliffLight"),
              box("LavaPool", -9, 88, -4.5, 9, 90.5, 4.5, "glow", emissive=True),
              # Summit flame: a stepped Neon tongue of fire that narrows as it rises (no crossbar).
              box("Flame1", -6, 90.5, -4, 6, 97, 4, "glow", emissive=True),
              box("Flame2", -4.5, 97, -3, 3.5, 103, 3, "glow", emissive=True),
              box("Flame3", -2.5, 103, -2, 2.5, 108, 2, "glowAlt", emissive=True),
              box("Flame4", -1, 108, -1, 1.5, 113, 1, "glowAlt", emissive=True),
              box("Ember", 2.5, 104, -0.6, 3.7, 106, 0.6, "glowAlt", emissive=True),
              box("EmberA", 4, 94, -2, 6, 97, 0, "glow", emissive=True),
              box("EmberB", -7, 93, 1, -5, 96, 3, "glowAlt", emissive=True)]
        # Lava spill from the crater down the east face (the face away from the hub glows too).
        for k in range(5):
            t = 10 - 2 * k
            hx, y0 = 52 - 4 * t, 8 * t
            b.append(box(f"Spill{k}", hx, y0, -2, hx + 0.8, y0 + 8, 2, "glow", emissive=True))
        return b

    kit("Volcano_Pyramid", pyramid())
    kit("Volcano_BasaltColumns", [
        box("Joint", -8, 0, -6, 8, 0.6, 6, "rim"),
        box("ColA", -7, 0, -5, -3, 14, -1, "cliff", relief=["Front", "Left", "Top"]),
        box("ColB", -3, 0, -4, 1, 18, 0, "cliffLight", relief=["Front", "Top"]),
        box("ColC", 1, 0, -5, 5, 11, -1, "cliff", relief=["Front", "Right", "Top"]),
        box("ColD", -5, 0, -1, -1, 9, 3, "cliffLight", relief=["Back", "Left", "Top"]),
        box("ColE", -1, 0, 0, 3, 15, 4, "cliff", relief=["Back", "Top"]),
        box("ColF", 3, 0, -1, 7, 7, 3, "cliffLight", relief=["Back", "Right", "Top"]),
        box("GlowA", -2.6, 18, -3.6, 0.6, 18.4, -0.4, "glow", emissive=True),
        box("GlowB", -0.6, 15, 0.4, 2.6, 15.4, 3.6, "glowAlt", emissive=True),
        box("Seam", 1, 4, -5.2, 5, 4.6, -5, "glow", emissive=True),
    ])
    kit("Volcano_LavaVent", [
        box("Joint", -6.5, 0, -6.5, 6.5, 0.6, 6.5, "rim"),
        box("Cone1", -6, 0, -6, 6, 3, 6, "cliff", relief=True),
        box("Cone2", -4.5, 3, -4.5, 4.5, 5.5, 4.5, "cliffLight", relief=["Front", "Back", "Left", "Right"]),
        box("RimN", -3.5, 5.5, -3.5, 3.5, 7, -2.2, "cliff"),
        box("RimS", -3.5, 5.5, 2.2, 3.5, 7, 3.5, "cliff"),
        box("RimW", -3.5, 5.5, -2.2, -2.2, 6.6, 2.2, "cliff"),
        box("RimE", 2.2, 5.5, -2.2, 3.5, 6.4, 2.2, "cliff"),
        box("Lava", -2.2, 5.5, -2.2, 2.2, 6.2, 2.2, "glow", emissive=True),
        box("Spark", -0.5, 7.5, -0.5, 0.5, 9, 0.5, "glowAlt", emissive=True),
        box("Drip", 4.5, 0.6, -0.8, 6.1, 3, 0.8, "glow", emissive=True),
    ])
    kit("Volcano_LavaStrip", [  # one 16 x 8 river segment, laid flush in its carved channel
        box("Lava", -8, 0, -5, 8, 0.4, 5, "glow", emissive=True),
        box("HotA", -6, 0.4, -2, -1, 0.5, 1, "glowAlt", emissive=True),
        box("HotB", 2, 0.4, 0, 6, 0.5, 3, "glowAlt", emissive=True),
        box("BankN", -8, 0, -5.8, 8, 0.6, -5, "rim"),
        box("BankS", -8, 0, 5, 8, 0.6, 5.8, "rim"),
    ])
    kit("Volcano_CharredTree", [
        box("Joint", -2.6, 0, -2.6, 2.6, 0.6, 2.6, "rim"),
        box("Trunk1", -1.8, 0, -1.8, 1.8, 8, 1.8, "trunk", relief=["Front", "Back"]),
        box("Trunk2", -1.2, 8, -1.4, 1.8, 14, 1.4, "trunkDark"),
        box("BranchE", 1.8, 10, -0.8, 8, 11.6, 0.8, "trunk"),
        box("BranchETip", 7, 11.6, -0.6, 8.4, 15, 0.6, "trunkDark"),
        box("BranchW", -6, 13, -0.7, -1.2, 14.4, 0.7, "trunk"),
        box("EmberA", 7.2, 15, -0.5, 8.2, 16, 0.5, "glow", emissive=True),
        box("EmberB", -1, 14, -1, 0.6, 15.2, 0.6, "glowAlt", emissive=True),
        box("Crack", -1.9, 2, -0.4, -1.8, 6, 0.4, "glow", emissive=True),
    ])
    kit("Volcano_ColumnPerch", [  # secret 2: a walkable basalt perch (top y 12) reached by a bounce pad
        box("Joint", -6.5, 0, -6.5, 6.5, 0.6, 6.5, "rim"),
        box("Body", -6, 0, -6, 6, 8, 6, "cliff", relief=["Front", "Back", "Left", "Right"], walkable=True),
        box("Lip", -6.4, 7.4, -6.4, 6.4, 8, 6.4, "rim"),
        box("Top", -5, 8, -5, 5, 12, 5, "cliffLight", relief=True, walkable=True),
        box("SeamA", 6, 2, -1, 6.4, 7, 1, "glow", emissive=True),
        box("SeamB", -1, 9, 5, 1, 11.4, 5.4, "glowAlt", emissive=True),
    ])


def glitch_kits():
    box, kit = A.box, A.kit

    def cube_tower():
        b = []
        # Hollow base block (secret: shrine inside), doorway on local -Z.
        h = 13
        b += [box("BaseW", -h, 0, -h, -h + 3, 16, h, "cube", relief=["Left"]),
              box("BaseE", h - 3, 0, -h, h, 16, h, "cube", relief=["Right"]),
              box("BaseS", -h + 3, 0, h - 3, h - 3, 16, h, "cube", relief=["Back"]),
              box("BaseNL", -h + 3, 0, -h, -3.5, 16, -h + 3, "cube", relief=["Front"]),
              box("BaseNR", 3.5, 0, -h, h - 3, 16, -h + 3, "cube", relief=["Front"]),
              box("DoorTop", -3.5, 8, -h, 3.5, 16, -h + 3, "cube"),
              box("Roof", -h, 16, -h, h, 18, h, "cubeDark"),
              box("DoorGlow", -3.5, 7.6, -h - 0.4, 3.5, 8, -h, "glow", emissive=True),
              box("BaseEdge", -h - 0.4, 0, -h - 0.4, h + 0.4, 0.6, h + 0.4, "glowAlt", emissive=True)]
        # Floating stack: nine offset cubes with 2-stud gaps (they hover), pixel squares and edges.
        offs = [(0, 0), (3, -2), (-2, 3), (4, 2), (-3, -3), (2, 4), (-4, 1), (1, -4), (0, 0)]
        for k in range(9):
            c = 9 - 0.6 * k
            y0 = 20 + 10.5 * k
            ox, oz = offs[k]
            yaw = (0, 15, 30, 10, 0, 25, 40, 5, 20)[k]
            b.append(box(f"Cube{k}", ox - c, y0, oz - c, ox + c, y0 + 8.5, oz + c, "cube" if k % 2 else "cubeLight",
                         relief=["Front", "Back", "Left", "Right"], rot=(0, yaw, 0)))
            b.append(box(f"Edge{k}", ox - c - 0.3, y0 - 0.3, oz - c - 0.3, ox + c + 0.3, y0 + 0.4, oz + c + 0.3,
                         "glow" if k % 2 else "glowAlt", emissive=True, rot=(0, yaw, 0)))
            px = ox + (c * 0.4 if k % 2 else -c * 0.5)
            b.append(box(f"Pixel{k}", px - 1.5, y0 + 3, oz - c - 0.5, px + 1.5, y0 + 6, oz - c, "glowAlt" if k % 2 else "glow",
                         emissive=True, rot=(0, yaw, 0)))
        # Broken crown cube (about y 115..131): six chunks of a 16-cube with one missing corner,
        # and four fragments drifting off it.
        y0 = 116
        for i, (x0, z0, x1, z1, y1) in enumerate([(-8, -8, 0, 0, 132), (0, -8, 8, 0, 128), (-8, 0, 0, 8, 126),
                                                  (-8, -8, 8, 8, 120), (0, 0, 4, 8, 124), (4, 4, 8, 8, 122)]):
            b.append(box(f"Crown{i}", x0, y0 if i != 3 else y0 - 2, z0, x1, y1, z1, "cubeLight" if i % 2 else "cube",
                         relief=["Front", "Back", "Left", "Right", "Top"]))
        b += [box("CrownEdge", -8.4, 113.6, -8.4, 8.4, 114.2, 8.4, "glow", emissive=True),
              box("CrownCore", 2, 124, 2, 6, 128, 6, "glowAlt", emissive=True)]
        for i, (x, y, z, s, r) in enumerate([(12, 130, 10, 3, 25), (-13, 126, 6, 2.5, 40), (8, 138, -10, 2, 15), (-9, 136, -12, 3.2, 35)]):
            b.append(box(f"Fragment{i}", x - s, y - s, z - s, x + s, y + s, z + s, "cubeLight" if i % 2 else "glow",
                         emissive=(i % 2 == 0), rot=(r, r, 0)))
        return b

    kit("Glitch_CubeTower", cube_tower())
    kit("Glitch_FloatCubes", [
        box("Shadow", -5, 0, -5, 5, 0.3, 5, "cubeDark"),
        box("CubeA", -3, 6, -3, 3, 12, 3, "cube", relief=["Front", "Back"], rot=(0, 20, 0)),
        box("EdgeA", -3.3, 5.7, -3.3, 3.3, 6.2, 3.3, "glow", emissive=True, rot=(0, 20, 0)),
        box("CubeB", 3, 14, -1, 6, 17, 2, "cubeLight", rot=(20, 30, 0)),
        box("CubeC", -6, 16, 1, -3.5, 18.5, 3.5, "glowAlt", emissive=True, rot=(0, 45, 20)),
        box("PixelA", -1, 8, -3.4, 1, 10, -3.1, "glowAlt", emissive=True, rot=(0, 20, 0)),
    ])

    def grid_plaza():
        b = [box("Frame", -37, 0, -37, 37, 0.15, 37, "rim")]
        missing = {(1, 2), (4, 1), (3, 4), (0, 5), (5, 3)}
        for i in range(6):
            for j in range(6):
                x0, z0 = -36 + 12 * i, -36 + 12 * j
                if (i, j) in missing:
                    b.append(box(f"Void{i}{j}", x0 + 0.5, 0.15, z0 + 0.5, x0 + 11.5, 0.25, z0 + 11.5, "void"))
                    b.append(box(f"VoidPixel{i}{j}", x0 + 5, 0.25, z0 + 5, x0 + 7, 0.35, z0 + 7, "glowAlt", emissive=True))
                else:
                    b.append(box(f"Tile{i}{j}", x0 + 0.5, 0.15, z0 + 0.5, x0 + 11.5, 0.35, z0 + 11.5,
                                 "tile" if (i + j) % 2 == 0 else "tileLight", relief=["Top"]))
        for i, (x, z) in enumerate([(-37, -37), (35, -37), (-37, 35), (35, 35)]):
            b.append(box(f"Corner{i}", x, 0, z, x + 2, 0.5, z + 2, "glow", emissive=True))
        return b

    kit("Glitch_GridPlaza", grid_plaza())
    kit("Glitch_PixelTree", [
        box("Joint", -2.6, 0, -2.6, 2.6, 0.6, 2.6, "rim"),
        box("Trunk", -1.2, 0, -1.2, 1.2, 9, 1.2, "cubeDark"),
        box("LeafA", -5, 8, -5, 5, 13, 5, "leaf", relief=True),
        box("LeafB", -3, 13, -3, 3, 17, 3, "leafLight", relief=True),
        box("LeafC", 3, 10, 2, 7, 14, 6, "glow", emissive=True),
        box("LeafD", -7, 11, -4, -4, 14, -1, "glowAlt", emissive=True),
        box("LeafE", -1, 17, -1, 1, 19, 1, "glowAlt", emissive=True),
    ])

    def pixel_terrace():
        """Walkable stepped pixel blocks (the Glitch mid layer is parts, not terrain): three tiers of
        cubes, checker tops, dark joints, Neon pixel edges. Footprint 40 x 32, top y 12."""
        b = []
        tiers = [(-20, -16, 20, 16, 4), (-14, -12, 16, 12, 8), (-8, -6, 10, 8, 12)]
        for t, (x0, z0, x1, z1, y1) in enumerate(tiers):
            y0 = 0 if t == 0 else tiers[t - 1][4]
            cells = 2
            dx, dz = (x1 - x0) / cells, (z1 - z0) / cells
            for i in range(cells):
                for j in range(cells):
                    role = "cube" if (i + j + t) % 2 == 0 else "cubeLight"
                    b.append(box(f"T{t}_{i}{j}", x0 + dx * i, y0, z0 + dz * j, x0 + dx * (i + 1), y1, z0 + dz * (j + 1), role,
                                 relief=["Top", "Front", "Back", "Left", "Right"], walkable=True))
            b.append(box(f"Joint{t}", x0 - 0.3, y1 - 0.6, z0 - 0.3, x1 + 0.3, y1, z1 + 0.3, "rim"))
            b.append(box(f"PixelEdge{t}", x0 + 2, y1 - 3, z0 - 0.4, x0 + 5, y1 - 1, z0, "glow" if t % 2 == 0 else "glowAlt", emissive=True))
            b.append(box(f"PixelEdgeB{t}", x1, y1 - 3, z1 - 6, x1 + 0.4, y1 - 1, z1 - 3, "glowAlt" if t % 2 == 0 else "glow", emissive=True))
        return b

    kit("Glitch_PixelTerrace", pixel_terrace())
    kit("Glitch_BitPerch", [  # secret 2: a walkable floating bit platform (top y 11) reached by a bounce pad
        box("Shadow", -6, 0, -6, 6, 0.3, 6, "cubeDark"),
        box("Stem", -1.5, 0, -1.5, 1.5, 9, 1.5, "glowAlt", emissive=True),
        box("Deck", -6, 9, -6, 6, 11, 6, "cubeLight", relief=["Top"], walkable=True),
        box("Edge", -6.3, 8.7, -6.3, 6.3, 9.2, 6.3, "glow", emissive=True),
        box("BitA", 7, 12, -2, 9, 14, 0, "glowAlt", emissive=True, rot=(30, 30, 0)),
        box("BitB", -9, 13, 2, -7, 15, 4, "glow", emissive=True, rot=(0, 30, 30)),
    ])
    kit("Glitch_ErrorPillar", [
        box("Joint", -3, 0, -3, 3, 0.6, 3, "rim"),
        box("Low", -2.5, 0, -2.5, 2.5, 6, 2.5, "cube", relief=["Front", "Back"]),
        box("Shift", -1.5, 6, -2.5, 3.5, 11, 2.5, "cubeLight", relief=["Front"]),
        box("Gap", -2, 11.6, -2, 3, 15, 3, "cube", rot=(0, 18, 0)),
        box("Scan", -2.6, 3, -2.6, 2.6, 3.4, 2.6, "glow", emissive=True),
        box("ScanB", -1.6, 9, -2.7, 3.6, 9.4, 2.7, "glowAlt", emissive=True),
    ])


# ============================================================================ regions
def arctic():
    T, C, G = A.T, A.C, A.G
    terr = W.ground_fills("Arctic", "Snow")
    excl = []
    # High: Monte Granita, a glacier stack (7 x 4) in the open NE block; the long ice slide runs south off
    # its sheer south face; the Granita Grotto is carved into its east side.
    s, _ = stack(630, -636, 694, -590, [4, 8, 12, 16, 20, 24, 28], "Basalt", "Snow", inset_x0=3, inset_x1=3, inset_z0=3)
    terr += s
    check_rect("Arctic Monte Granita", 630, -636, 694, -590)
    excl.append((626, -640, 698, -586))
    excl.append((654, -590, 672, -480))  # long slide and its landing
    # Mid: ice ridges (Glacier faces, Snow treads) and the spire mound.
    ridges = [((380, -638, 452, -608), [4, 8]), ((470, -638, 540, -610), [4]), ((250, -638, 330, -610), [4])]
    for (x0, z0, x1, z1), hs in ridges:
        s, _ = stack(x0, z0, x1, z1, hs, "Basalt", "Snow", inset_x0=6, inset_x1=6, inset_z0=6, inset_z1=6)
        terr += s
        check_rect(f"Arctic ridge {x0},{z0}", x0, z0, x1, z1)
        excl.append((x0, z0, x1, z1))
    s, _ = stack(250, -446, 306, -352, [4, 8], "Basalt", "Snow", inset_x0=5, inset_x1=5, inset_z0=5, inset_z1=5)
    terr += s
    check_rect("Arctic spire mound", 250, -446, 306, -352)
    excl.append((246, -450, 310, -348))
    # Low: Lago Gelato, a frozen pond (water under a walkable ice sheet) with a chest under the ice.
    carves, water = [], []
    bed, cv, wt = W.pool(486, -526, 540, -488, "Basalt")
    terr += bed
    carves += cv
    water += wt
    check_rect("Arctic Lago Gelato", 486, -526, 540, -488, margin=10)
    excl.append((480, -532, 546, -482))
    # Secret: Granita Grotto, carved into the stack's sheer south face beside the slide (16 deep, 10 high;
    # the stack stands 16+ studs above it).
    carves.append({"min": [640, -0.5, -606], "max": [656, 10, -589]})

    clusters = []
    mix = ["Arctic_IcePine", "Arctic_SnowDrift", "Arctic_Crystal", "Arctic_IcePine", "Arctic_SnowDrift", "Arctic_IcePine", "Arctic_Snowman"]
    spots = grid_spots("Arctic", 34, 14, excl)
    clusters += [C(mix[i % len(mix)], x, G, z, (i * 37) % 360) for i, (x, z) in enumerate(spots)]
    for i, (x, z, y) in enumerate([(400, -623, 7.5), (430, -623, 7.5), (505, -624, 3.5), (290, -624, 3.5)]):
        clusters.append(C("Arctic_Crystal", x, y, z, i * 50, 1.4))
    # Route beats along the A01 -> A02 lane (W1): crystal clusters just off both lane edges.
    for i, (x, z) in enumerate([(382, -536), (452, -536), (520, -538), (470, -593), (530, -593), (410, -593)]):
        clusters.append(C("Arctic_Crystal", x, G, z, i * 70, 1.3, f"LaneCrystal{i}"))
    clusters.append(C("Arctic_IceSheet", 513, -2.1, -507, 0, 1, "LagoGelatoIce"))
    clusters.append(C("Arctic_Igloo", 462, G, -505, 90, 1.1, "GelatoIgloo"))
    clusters += [C("Lane_GlowTiles", x, 0, z, (i * 37) % 360) for i, (x, z) in enumerate(lane_glow("Arctic"))]
    slide_top = (662, 28, -590)
    return {
        "key": "Arctic", "version": 1, "floorFolder": "Arctic", "replacesLegacy": ["REGION_ARCTIC_"],
        "palette": {
            "ground": "#7FE8FF", "secondary": "#2B6FD6", "cliff": "#2B6FD6", "cliffLight": "#46A7FF",
            "ice": "#46A7FF", "iceLight": "#BFF8FF", "iceSheet": "#BFF8FF",
            "rim": "#1D2133", "glow": "#46A7FF", "glowAlt": "#BFF8FF",
            "snow": "#F7F5FC", "snowLight": "#DFF9FF",
            "trunk": "#8A5528", "trunkDark": "#2A2F45", "trunkLight": "#C9894A",
            "leaf": "#1F7A6E", "leafLight": "#3BD16F", "leafDark": "#14505A",
            "white": "#F7F5FC", "flower": "#46A7FF", "sign": "#2B6FD6", "slide": "#46A7FF", "bounce": "#46A7FF",
            "accent": "#FF8A2A", "stripe": "#F0283C",
        },
        "materials": {"ground": "Snow", "cliff": "Basalt"},
        "terraces": terr, "wedges": [], "rocks": [], "carves": carves, "water": water, "rims": [],
        "clusters": clusters,
        "landmark": C("Arctic_IceSpire", 278, 7.5, -399, 0, 1, "Stracciatella Spire"),
        "pois": [
            {"name": "Stracciatella Spire", "center": [278, -399], "radius": 50},
            {"name": "Monte Granita", "center": [662, -612], "radius": 52},
            {"name": "Lago Gelato", "center": [513, -507], "radius": 40},
        ],
        "signs": [
            dict(C("POI_Sign", 320, G, -460, 0, 1, "Stracciatella Spire"), text="STRACCIATELLA SPIRE"),
            dict(C("POI_Sign", 640, G, -570, 0, 1, "Monte Granita"), text="MONTE GRANITA"),
            dict(C("POI_Sign", 556, G, -500, 90, 1, "Lago Gelato"), text="LAGO GELATO"),
        ],
        "secrets": [
            C("Secret_Shrine", 648, G, -600, 180, 1.3, "GranitaGrotto"),
            C("Arctic_Crystal", 643, G, -603, 0, 0.6, "GranitaGrottoCrystals"),
            C("Secret_Chest", 500, -7.6, -514, 30, 1.3, "UnderIceChest"),  # on the pond bed, seen through the ice
        ],
        "toys": [
            dict(C("Toy_Slide_Ice", slide_top[0], slide_top[1], slide_top[2], 90, 1, "GranitaIceSlide"), type="Slide",
                 params={"Boost": 40, "Downhill": "@Vector3.new(0, 0, 1)"}),
            dict(C("Toy_BouncePad", 330, G, -340, 0, 1, "SpireBounce"), type="BouncePad", params={"LaunchSpeed": 72}),
            dict(C("Toy_BouncePad", 610, G, -620, 0, 1, "GranitaBounce"), type="BouncePad", params={"LaunchSpeed": 72}),
        ],
        "seamTerraces": W.seam_line("x", 229, -654, -294, 1, "Snow", "LeafyGrass"),
    }


def volcano():
    T, C, G = A.T, A.C, A.G
    terr = W.ground_fills("Volcano", "Glacier")
    excl = [(441, -182, 553, -86)]  # the pyramid (legacy massif footprint)
    check_rect("Volcano pyramid", 445, -176, 549, -92, margin=4)
    # High: Monte Magma, a CrackedLava stack (7 x 4) near the gate with a sheer east face and its slide.
    s, _ = stack(262, -244, 324, -196, [4, 8, 12, 16, 20, 24, 28], "CrackedLava", "Glacier", inset_x0=4, inset_z0=2, inset_z1=2)
    terr += s
    check_rect("Volcano Monte Magma", 262, -244, 324, -196)
    excl.append((258, -248, 390, -192))
    # Secret: Magma Grotto, carved into the stack's north face.
    carves = [{"min": [282, -0.5, -250], "max": [300, 10, -224]}]
    # Mid: basalt mesas.
    mesas = [((244, -60, 292, -4), [4, 8]), ((360, 30, 424, 100), [4]), ((250, 96, 300, 150), [4, 8]),
             ((620, -460, 690, -404), [4, 8]), ((486, -460, 556, -410), [4]), ((680, -190, 698, -40), [4]),
             ((508, 20, 560, 86), [4])]
    for (x0, z0, x1, z1), hs in mesas:
        s, _ = stack(x0, z0, x1, z1, hs, "CrackedLava", "Glacier", inset_x0=5, inset_x1=5, inset_z0=5, inset_z1=5)
        terr += s
        check_rect(f"Volcano mesa {x0},{z0}", x0, z0, x1, z1)
        excl.append((x0, z0, x1, z1))
    # Low: Lava Lasagna River from the pyramid west and north: Neon lava strips laid flush on a 16-wide
    # dark CrackedLava band. No carve, so walking, roaming and pathfinding are unchanged.
    river = [("x", -134, 300, 440), ("z", 304, -134, 20), ("x", 20, 304, 352), ("z", 500, -244, -186)]
    clusters = []
    for axis, fixed, a0, a1 in river:
        if axis == "x":
            x0, z0, x1, z1 = a0, fixed - 4, a1, fixed + 4
        else:
            x0, z0, x1, z1 = fixed - 4, a0, fixed + 4, a1
        terr.append(T(x0 - 8, -8, z0 - 8, x1 + 8, G, z1 + 8, "CrackedLava"))
        check_rect(f"Volcano river {x0},{z0}", x0, z0, x1, z1, margin=6)
        excl.append((x0 - 8, z0 - 8, x1 + 8, z1 + 8))
        for k, a in enumerate(range(int(a0) + 8, int(a1), 16)):
            if axis == "x":
                clusters.append(C("Volcano_LavaStrip", a, -0.45, fixed, 0))
            else:
                clusters.append(C("Volcano_LavaStrip", fixed, -0.45, a, 90))

    mix = ["Volcano_BasaltColumns", "Volcano_CharredTree", "Volcano_LavaVent", "Volcano_BasaltColumns", "Volcano_CharredTree", "Forest_Rock"]
    spots = grid_spots("Volcano", 46, 14, excl)
    clusters += [C(mix[i % len(mix)], x, G, z, (i * 41) % 360) for i, (x, z) in enumerate(spots)]
    for i, (x, z) in enumerate([(430, -160), (425, -104), (560, -200), (420, -60)]):
        clusters.append(C("Volcano_LavaVent", x, G, z, i * 60, 1.2))
    clusters += [C("Lane_GlowTiles", x, 0, z, (i * 37) % 360) for i, (x, z) in enumerate(lane_glow("Volcano"))]
    clusters.append(C("Volcano_ColumnPerch", 392, G, -20, 0, 1, "ColumnPerch"))
    check_rect("Volcano column perch", 384, -28, 400, -12, margin=6)
    excl.append((380, -32, 404, -8))
    slide_top = (326, 28, -220)
    return {
        "key": "Volcano", "version": 1, "floorFolder": "Volcano", "replacesLegacy": ["REGION_VOLCANO_"],
        "palette": {
            "ground": "#E2531E", "secondary": "#2B2238", "cliff": "#2B2238", "cliffLight": "#4A3A55",
            "rim": "#1D2133", "glow": "#FF6A1A", "glowAlt": "#FFD447",
            "trunk": "#2A2F45", "trunkDark": "#1D2133", "trunkLight": "#4A3A55",
            "leaf": "#4A3A55", "leafLight": "#FF8A2A", "leafDark": "#2B2238",
            "white": "#F7F5FC", "flower": "#FF8A2A", "sign": "#E2531E", "slide": "#FF8A2A", "bounce": "#FF8A2A",
            "accent": "#FFD447",
        },
        "materials": {"ground": "Glacier", "cliff": "CrackedLava"},
        "terraces": terr, "wedges": [], "rocks": [], "carves": carves, "water": [], "rims": [],
        "clusters": clusters,
        "landmark": C("Volcano_Pyramid", 497, G, -134, 0, 1, "Piramide Peperoncino"),
        "pois": [
            {"name": "Piramide Peperoncino", "center": [497, -134], "radius": 70},
            {"name": "Lava Lasagna River", "center": [330, -60], "radius": 70},
            {"name": "Monte Magma", "center": [296, -220], "radius": 44},
        ],
        "signs": [
            dict(C("POI_Sign", 420, G, -196, 0, 1, "Piramide Peperoncino"), text="PIRAMIDE PEPERONCINO"),
            dict(C("POI_Sign", 330, G, -152, 0, 1, "Lava Lasagna River"), text="LAVA LASAGNA RIVER"),
            dict(C("POI_Sign", 250, G, -180, 90, 1, "Monte Magma"), text="MONTE MAGMA"),
        ],
        "secrets": [
            C("Secret_Shrine", 291, G, -238, 0, 1.3, "MagmaGrotto"),
            C("Secret_Chest", 392, 11.5, -20, 0, 1.3, "ColumnPerchChest"),
        ],
        "toys": [
            dict(C("Toy_Slide_28", slide_top[0], slide_top[1], slide_top[2], 180, 1, "MagmaSlide"), type="Slide",
                 params={"Boost": 36, "Downhill": "@Vector3.new(1, 0, 0)"}),
            dict(C("Toy_BouncePad", 410, G, -20, 0, 1, "PerchBounce"), type="BouncePad", params={"LaunchSpeed": 72}),
            dict(C("Toy_BouncePad", 344, G, -180, 0, 1, "MagmaBounce"), type="BouncePad", params={"LaunchSpeed": 72}),
        ],
        "seamTerraces": (W.seam_line("x", 229, -294, 202, 1, "Glacier", "Salt")
                         + W.seam_line("z", -294, 229, 469, 1, "Glacier", "Snow")
                         + W.seam_line("x", 469, -474, -294, 1, "Glacier", "Snow")
                         + W.seam_line("z", -474, 469, 701, 1, "Glacier", "Snow")),
    }


def glitch():
    T, C, G = A.T, A.C, A.G
    # Ground is Grass: Pavement snaps its surface to whole studs (Studio, 9 Nov: fill -2.5 -> 0.0, -2.6 to
    # -3.0 -> -1.0), so it cannot meet the shared -0.48 lane ground without a step at every seam (the lane
    # carpets do not collide; carts drive on terrain). Pavement keeps the cliff faces only. Grass is the
    # last flat stud-backed material; its blades need Terrain.Decoration off (owner, Studio checkbox).
    terr = W.ground_fills("GlitchZone", "Grass")
    excl = []
    # High: Gnocchi Glitch Peak, a Pavement stack (7 x 4) in the SE corner with a sheer north face and slide.
    s, _ = stack(632, 446, 696, 514, [4, 8, 12, 16, 20, 24, 28], "Pavement", "Grass", inset_x0=3, inset_x1=3, inset_z1=3)
    terr += s
    check_rect("Glitch peak", 632, 446, 696, 514)
    excl.append((628, 380, 700, 518))  # peak, slide and landing
    # Mid: hero mound in the SW block.
    s, _ = stack(262, 444, 338, 516, [4], "Pavement", "Grass", inset_x0=4, inset_x1=4, inset_z0=4, inset_z1=4)
    terr += s
    check_rect("Glitch tower mound", 262, 444, 338, 516)
    excl.append((258, 440, 342, 520))
    carves = []

    clusters = []
    # Mid: pixel terraces (walkable parts), each checked as a collidable footprint.
    for i, (x, z, yaw) in enumerate([(669, 270, 0), (669, 330, 0), (520, 226, 0), (290, 226, 0), (400, 230, 0)]):
        clusters.append(C("Glitch_PixelTerrace", x, G, z, yaw, 1, f"PixelTerrace{i}"))
        check_rect(f"Glitch pixel terrace {i}", x - 20, z - 16, x + 20, z + 16)
        excl.append((x - 22, z - 18, x + 22, z + 18))
    # Grid floors with missing tiles (flush decor; visual only, no holes).
    for i, (x, z) in enumerate([(380, 420), (530, 400)]):
        clusters.append(C("Glitch_GridPlaza", x, -0.45, z, 0, 1, f"PixelPizzaPlaza{i}"))
        excl.append((x - 38, z - 38, x + 38, z + 38))
    mix = ["Glitch_PixelTree", "Glitch_FloatCubes", "Glitch_ErrorPillar", "Glitch_PixelTree", "Glitch_FloatCubes"]
    spots = grid_spots("GlitchZone", 44, 14, excl)
    clusters += [C(mix[i % len(mix)], x, G, z, (i * 43) % 360) for i, (x, z) in enumerate(spots)]
    clusters += [C("Lane_GlowTiles", x, 0, z, (i * 37) % 360) for i, (x, z) in enumerate(lane_glow("GlitchZone"))]
    # Route beats along the G02 -> G03 lanes (W1): floating cubes and error pillars just off the lane edges.
    for i, (x, z, k) in enumerate([(574, 350, "Glitch_FloatCubes"), (574, 420, "Glitch_ErrorPillar"),
                                   (560, 442, "Glitch_FloatCubes"), (560, 490, "Glitch_ErrorPillar"),
                                   (516, 442, "Glitch_ErrorPillar"), (444, 334, "Glitch_ErrorPillar"),
                                   (496, 348, "Glitch_FloatCubes"), (444, 396, "Glitch_FloatCubes"),
                                   (552, 330, "Glitch_FloatCubes"), (512, 388, "Glitch_FloatCubes")]):
        clusters.append(C(k, x, G, z, i * 50, None, f"LaneBeat{i}"))
    clusters.append(C("Glitch_BitPerch", 360, G, 350, 0, 1, "BitPerch"))
    check_rect("Glitch bit perch", 354, 344, 366, 356, margin=6)
    slide_top = (664, 28, 446)
    return {
        "key": "GlitchZone", "version": 1, "floorFolder": "Glitch Zone", "replacesLegacy": ["REGION_GLITCH_"],
        "palette": {
            "ground": "#6B2EE6", "secondary": "#5B2CC9", "cliff": "#5B2CC9", "cliffLight": "#B48CFF",
            "cube": "#5B2CC9", "cubeLight": "#B48CFF", "cubeDark": "#2B0F52",
            "tile": "#B48CFF", "tileLight": "#E0CCFF", "void": "#0B0716",
            "rim": "#1D2133", "glow": "#FF49E1", "glowAlt": "#2EE9FF",
            "trunk": "#2B0F52", "trunkDark": "#1D2133", "trunkLight": "#5B2CC9",
            "leaf": "#FF49E1", "leafLight": "#2EE9FF", "leafDark": "#5B2CC9",
            "white": "#F7F5FC", "flower": "#FF49E1", "sign": "#8A4DFF", "slide": "#2EE9FF", "bounce": "#FF49E1",
            "accent": "#2EE9FF",
        },
        "materials": {"ground": "Grass", "cliff": "Pavement"},
        "terraces": terr, "wedges": [], "rocks": [], "carves": carves, "water": [], "rims": [],
        "clusters": clusters,
        "landmark": C("Glitch_CubeTower", 300, 3.5, 480, 0, 1, "Torre Cubo Calzone"),
        "pois": [
            {"name": "Torre Cubo Calzone", "center": [300, 480], "radius": 50},
            {"name": "Pixel Pizza Plaza", "center": [380, 420], "radius": 50},
            {"name": "Gnocchi Glitch Peak", "center": [664, 480], "radius": 44},
        ],
        "signs": [
            dict(C("POI_Sign", 250, G, 430, 90, 1, "Torre Cubo Calzone"), text="TORRE CUBO CALZONE"),
            dict(C("POI_Sign", 330, G, 370, 0, 1, "Pixel Pizza Plaza"), text="PIXEL PIZZA PLAZA"),
            dict(C("POI_Sign", 626, G, 420, 90, 1, "Gnocchi Glitch Peak"), text="GNOCCHI GLITCH PEAK"),
        ],
        "secrets": [
            C("Secret_Shrine", 300, 3.5, 480, 0, 1.3, "CubeTowerCore"),
            C("Secret_Chest", 360, 10.5, 350, 0, 1.2, "BitPerchChest"),  # deck top 10.5
        ],
        "toys": [
            dict(C("Toy_Slide_28", slide_top[0], slide_top[1], slide_top[2], -90, 1, "GlitchSlide"), type="Slide",
                 params={"Boost": 36, "Downhill": "@Vector3.new(0, 0, -1)"}),
            dict(C("Toy_BouncePad", 376, G, 350, 0, 1, "BitBounce"), type="BouncePad", params={"LaunchSpeed": 72}),
            dict(C("Toy_BouncePad", 626, G, 504, 0, 1, "PeakBounce"), type="BouncePad", params={"LaunchSpeed": 72}),
        ],
        "seamTerraces": (W.seam_line("x", 229, 202, 400, 1, "Grass", "Asphalt")
                         + W.seam_line("z", 202, 229, 701, 1, "Grass", "Glacier")),
    }


KIT_SCALE = {"Arctic_IcePine": 1.6, "Arctic_SnowDrift": 1.4, "Arctic_Crystal": 1.3, "Arctic_Snowman": 1.2,
             "Volcano_BasaltColumns": 1.3, "Volcano_CharredTree": 1.6, "Volcano_LavaVent": 1.2,
             "Glitch_PixelTree": 1.5, "Glitch_FloatCubes": 1.4, "Glitch_ErrorPillar": 1.4}

# ---------------------------------------------------------------- east island rim
# Same rules as the west rim (author_v5_west): faces flush behind the perimeter colliders (east x 701,
# north z -646, south z 522), ledges stop short of the natural-spawn band (east floors x 469..709: inner
# 80% ends at x 685), nothing reachable. Appended after the west edges with its own seed, so the approved
# west rim regenerates unchanged.
EAST_RIM_LOOK = {
    "Arctic": ("Basalt", "Snow", "Snow"),
    "Volcano": ("CrackedLava", "Glacier", "Glacier"),
    "GlitchZone": ("Pavement", "Pavement", "Grass"),
}
EAST_RIM_EDGES = [
    ("N", -648, -680, 236, 740, lambda a: "Arctic"),
    ("E", 702, 740, -680, 592, lambda a: "Arctic" if a < -474 else ("Volcano" if a < 202 else "GlitchZone")),
    ("S", 524, 592, 236, 740, lambda a: "GlitchZone"),
]
EAST_RIM_ART = {
    "Arctic": ["EV2_Run_01_Cliff_05", "EV2_Run_01_Cliff_06", "EV2_Run_04_Cliff_01"],
    "Volcano": ["EV2_Run_04_Cliff_02", "EV2_Run_04_Cliff_03", "EV2_Run_04_Cliff_04"],
    "GlitchZone": ["EV2_Run_04_Cliff_05", "EV2_Run_02_Cliff_05", "EV2_Run_02_Cliff_06"],
}
EAST_RIM_SHELLS = {"Volcano": ["EV2_Run_04"]}
EAST_RIM_LEDGES = {"N": (4,), "E": (8, 4), "S": ()}
EAST_RIM_REACH = {"N": -644, "E": 694, "S": 524}
EAST_RIM_HEROES = [(662, -612), (664, 480)]


def _box(edge, face, depth_in, outer, a0, a1, y0, y1, mat):
    if edge == "E":  # inside is -x
        return A.T(face - depth_in, y0, a0, outer, y1, a1, mat)
    return W._rim_box(edge, face, depth_in, outer, a0, a1, y0, y1, mat)


def _rect(edge, face, depth, a0, a1):
    if edge == "E":
        return face - depth, a0, face, a1
    return W._rim_rect(edge, face, depth, a0, a1)


def east_rim(regions):
    import random
    rng = random.Random(5151)
    feats, boxes = {}, {}
    for key, r in regions.items():
        feats[key] = [(e["position"][0], e["position"][2]) for g in ("clusters", "signs", "toys", "secrets")
                      for e in r.get(g, []) if "Lane_GlowTiles" != e.get("kit")]
        boxes[key] = [(c["min"][0], c["min"][2], c["max"][0], c["max"][2]) for c in r.get("carves", []) + r.get("water", [])]
    added = {k: 0 for k in regions}
    log = []
    for edge, face, outer, a_lo, a_hi, owner in EAST_RIM_EDGES:
        inward = -1 if edge in ("S", "E") else 1  # direction from the face into the map
        a = a_lo
        while a < a_hi:
            width = rng.choice([16, 20, 24, 28, 32, 36])
            key = owner(a + width / 2)
            if key == "GlitchZone":
                width = rng.choice([8, 12, 16, 20])  # narrow chunks: a pixelated skyline
            b = min(a + width, a_hi)
            key = owner((a + b) / 2)
            body, band, cap = EAST_RIM_LOOK[key]
            terr = regions[key].setdefault("rim", [])
            first = len(terr)
            cx, cz = ((face, (a + b) / 2) if edge == "E" else ((a + b) / 2, face))
            saddle = any(math.hypot(cx - hx, cz - hz) < 150 for hx, hz in EAST_RIM_HEROES)
            if saddle:
                top = rng.choice([56, 60, 64, 68])
                back = top + rng.choice([0, 4, 8])
            else:
                top = rng.choice([72, 80, 88, 96]) if rng.random() > 0.2 else rng.choice([104, 112])
                back = top + rng.choice([12, 16, 20, 28])
            if key == "GlitchZone":
                # Pixel steps instead of one sheer face: three 8-stud setbacks, 16 studs apart.
                for k, drop in enumerate((32, 16)):
                    terr.append(_box(edge, face - 8 * k * inward, 0, face - 8 * (k + 1) * inward, a, b,
                                     A.G - 6, A.FILL(top - drop), body))
                terr.append(_box(edge, face - 16 * inward, 0, outer, a, b, A.G - 6, A.FILL(top) - 4, body))
                terr.append(_box(edge, face - 16 * inward, 0, face - 28 * inward, a, b, A.FILL(top) - 4, A.FILL(top), cap))
            else:
                terr.append(_box(edge, face, 0, outer, a, b, A.G - 6, A.FILL(top) - 4, body))
                terr.append(_box(edge, face, 0, face - 12 * inward, a, b, A.FILL(top) - 4, A.FILL(top), cap))
            setback = 28 if key == "GlitchZone" else 12
            if back > top:
                terr.append(_box(edge, face - setback * inward, 0, outer, a, b, A.FILL(top) - 4, A.FILL(back) - 4, band))
                terr.append(_box(edge, face - setback * inward, 0, outer, a, b, A.FILL(back) - 4, A.FILL(back), cap))
            y = rng.choice([36, 44, 52]) if saddle else rng.choice([48, 56, 64])
            if rng.random() < 0.6 and key != "GlitchZone":
                terr.append(_box(edge, face, 0, face - 4 * inward, a, b, A.FILL(y), A.FILL(y + 4), band))
            for depth in EAST_RIM_LEDGES[edge]:
                rect = _rect(edge, face, depth, a, b)
                if W._rim_clear(rect, feats[key], boxes[key]) and all(
                        math.hypot(max(rect[0] - gx, 0, gx - rect[2]), max(rect[1] - gz, 0, gz - rect[3])) >= 30
                        for gx, gz in GATES.values()):
                    h0 = rng.choice([12, 16, 20, 24])
                    h1 = min(top - 12, h0 + rng.choice([20, 28, 36]))
                    mid = max(4, depth // 2)
                    terr.append(_box(edge, face, depth, face, a, b, A.G, A.FILL(h0) - 4, body))
                    terr.append(_box(edge, face, depth, face, a, b, A.FILL(h0) - 4, A.FILL(h0), cap))
                    terr.append(_box(edge, face, mid, face, a, b, A.G, A.FILL(h1) - 4, body))
                    terr.append(_box(edge, face, mid, face, a, b, A.FILL(h1) - 4, A.FILL(h1), cap))
                    break
            log.extend((key, edge, t) for t in terr[first:])
            added[key] += 1
            a = b
    for key, edge, t in log:
        if edge == "E":
            reach = t["min"][0]
            bad = reach < EAST_RIM_REACH["E"]
        elif edge == "N":
            reach = t["max"][2]
            bad = reach > EAST_RIM_REACH["N"]
        else:
            reach = t["min"][2]
            bad = reach < EAST_RIM_REACH["S"]
        if bad:
            PROBLEMS.append(f"{key} rim piece {t['min']}..{t['max']} reaches past {EAST_RIM_REACH[edge]}")
    for key in regions:
        regions[key]["hidesLegacy"] = EAST_RIM_SHELLS.get(key, []) + EAST_RIM_ART.get(key, [])
    return added


def register(author):
    global A
    A = author
    A.KIT_SCALE.update(KIT_SCALE)
    arctic_kits()
    volcano_kits()
    glitch_kits()
    W.slide_kit("Toy_Slide_Ice", 28.5, angle=18)
    regions = {"Arctic": arctic(), "Volcano": volcano(), "GlitchZone": glitch()}
    for r in regions.values():
        keep = [e["position"] for e in r["signs"] + r["toys"] + r["secrets"]]
        r["clusters"] = [e for e in r["clusters"] if "name" in e or e["kit"] == "Lane_GlowTiles" or
                         all(math.hypot(e["position"][0] - p[0], e["position"][2] - p[2]) >= 14 for p in keep)]
    for key, r in regions.items():
        for t in r["toys"]:
            x, _, z = t["position"]
            if t["type"] == "BouncePad":
                check_rect(f"{key} {t['name']}", x - 5, z - 5, x + 5, z + 5, margin=6)
    chunks = east_rim(regions)
    print("east island rim chunks: " + ", ".join(f"{k} {v}" for k, v in chunks.items()))
    if PROBLEMS:
        raise SystemExit("author_v5_east checks failed:\n  " + "\n  ".join(PROBLEMS))
    A.REGIONS.update(regions)
    return regions
