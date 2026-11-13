#!/usr/bin/env python3
"""Print a species' design notes, catalog row, rig and per-bone bounding boxes.
Usage: describe_species.py BRT_004"""
import re, sys
sid = sys.argv[1]
build = open(f"tools/voxel_v4/builds/{sid}.js").read().split("\n")
print("\n".join(line[:230] for line in build[:11]))
for line in build:
    if "rigOverrides" in line:
        print(line[:260])
for line in open("src/shared/Config/BrainrotCatalog.lua"):
    if '"' + sid.replace("_", "-") + '"' in line:
        print(line.strip()[:120])
s = open(f"src/shared/Config/VoxelCreatures/{sid}.lua").read()
print(re.search(r"designHeight = [\d.]+", s).group(0), re.search(r'irisFamily = "\w+"', s).group(0))
print(s[s.index("rig = table.freeze"):s.index("boxes = table.freeze")])
by = {}
for slot, mn, mx, bone in re.findall(r'slot = "(\w+)",\s*min = \{ ([^}]*) \},\s*max = \{ ([^}]*) \},.*?bone = "(\w+)"', s, re.S):
    mn = [float(x) for x in mn.split(",")]; mx = [float(x) for x in mx.split(",")]
    b = by.setdefault(bone, [[99] * 3, [-99] * 3, {}])
    for i in range(3):
        b[0][i] = min(b[0][i], mn[i]); b[1][i] = max(b[1][i], mx[i])
    b[2][slot] = b[2].get(slot, 0) + 1
for k, v in by.items():
    print(k, [round(x, 2) for x in v[0]], [round(x, 2) for x in v[1]], dict(sorted(v[2].items())))
import os
print("overrides file:", os.path.exists(f"tools/voxel_v4/builds/{sid}.overrides.json"))
